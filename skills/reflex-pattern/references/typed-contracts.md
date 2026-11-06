# Typed contracts across native boundaries

Read this reference when a Swift core exchanges commands, state, effects or
results with Kotlin, a persistence adapter or an external service. These are
architecture recommendations. The example schema is illustrative; this reference
does not establish generated-language integration, runtime compatibility or
installed Android bridge behavior.

## Select the contract for each boundary

Keep the app-owned boundary schema separate from its native transport and from
the service's API schema. Choose each independently.

| Boundary | Default | Conditions for another choice |
| --- | --- | --- |
| Swift core to Kotlin host, with evolving messages or persisted payloads | Generate Swift and Kotlin/Java Protobuf DTOs from app-owned `.proto` files | Retain an existing, well-specified schema. Schema-generated JSON is suitable when JSON is the established interchange format. |
| Small API shipped in one app with its Swift library | A narrow typed façade, including generated SwiftJava JNI bindings when supported | Prove its exact type graph, ownership and asynchronous behavior. Do not add serialization solely to wrap a few co-versioned methods. |
| REST service | Generate client DTOs from the service's OpenAPI document | Keep a useful existing client or provider SDK. Map it into app-owned domain types. |
| Protobuf RPC service | Generate messages and service clients from the service schema | Keep the app boundary distinct when service releases or representations differ. |
| Database or durable queue | Versioned persistence records and explicit migrations | Reuse an interchange message only when its retention and migration rules fit the stored data. |

Protobuf is a practical default for a new binary Swift/Kotlin contract, not a
requirement for every app. A schema generator provides message types and codecs;
it does not generate JNI calls, a reducer, authorization or persistence
transactions. SwiftProtobuf generates Swift structs; the official Kotlin
generator adds Kotlin DSLs around generated Java messages. Select full or lite
Java/Kotlin runtimes deliberately for Android. See the
[SwiftProtobuf API](https://github.com/apple/swift-protobuf/blob/main/Documentation/API.md)
and [Kotlin generated code guide](https://protobuf.dev/reference/kotlin/kotlin-generated/).

Pin schema tools, plugins and runtimes in the build. Generate both languages from
one source, prohibit hand edits to generated files, and check regeneration for
drift. Check each runtime's compatibility policy instead of assuming that any
compiler output works with any runtime. The official
[Protobuf cross-version guarantee](https://protobuf.dev/support/cross-version-runtime-guarantee/)
does not provide a universal compatibility promise for every implementation.

## Put types on both sides of the codec

Expose Swift enums with associated values and Kotlin sealed interfaces/classes
for commands, effects, results and product failures. Let the façade encode and
decode generated messages internally. Keep `Data`, `ByteArray`, dictionaries and
generated field names out of ordinary view code.

Use distinct domain IDs such as `AccountID`, `RecordID` and `OperationID`. Validate
their wire representation at the adapter. A string-backed generated field does
not make two ID types interchangeable. Use separate mappings for:

- Domain models and reducer state, which express product invariants.
- Boundary DTOs, which express interchange and compatibility.
- Database records, which express keys, indexes, revisions and migrations.
- API DTOs, which express a particular service's contract.

Small apps can reuse types where the semantics truly match. Do not expose a Room
entity, managed database object or server response as the reducer's mutable state
merely because its fields currently match.

Represent variants with Protobuf `oneof`, a JSON discriminated union or the
generator's equivalent. Define typed payloads for expected effects and failures.
Reserve `map<string, ...>`, `Any` and arbitrary JSON for genuinely open data, such
as user-authored documents, with a separate validation policy. Do not use them as
the default command or effect protocol.

## Illustrative request, effect and event schema

This standalone proto3 example models a record update. `Request` carries a public
command. `Effect` asks an adapter to persist or send it. `Event` carries a typed
completion. `State` exposes a tagged sync status. Adapt names and validation to
the app; the schema is not a complete sync engine.

```proto
syntax = "proto3";
package sample.boundary.v1;
option java_package = "sample.boundary.v1";
option java_multiple_files = true;

message Context {
  uint32 schema_version = 1;
  string correlation_id = 2;
  string operation_id = 3;
  string account_id = 4;
  int64 account_generation = 5;
  int64 request_generation = 6;
}

message UpdateRecord {
  string record_id = 1;
  string title = 2;
  optional int64 expected_server_revision = 3;
  optional int64 expected_local_revision = 4;
}

message CancelOperation {
  string target_operation_id = 1;
}

message Request {
  Context context = 1;
  oneof command {
    UpdateRecord update = 10;
    CancelOperation cancel = 11;
  }
}

message Effect {
  Context context = 1;
  oneof work {
    UpdateRecord persist_mutation = 10;
    UpdateRecord send_mutation = 11;
  }
}

message Persisted {
  int64 local_revision = 1;
}

message Acknowledged {
  int64 server_revision = 1;
}

enum FailureCode {
  FAILURE_CODE_UNSPECIFIED = 0;
  FAILURE_CODE_INVALID_INPUT = 1;
  FAILURE_CODE_UNAUTHORIZED = 2;
  FAILURE_CODE_CONFLICT = 3;
  FAILURE_CODE_OFFLINE = 4;
  FAILURE_CODE_CANCELLED = 5;
  FAILURE_CODE_STORAGE = 6;
  FAILURE_CODE_OUTCOME_UNKNOWN = 7;
  FAILURE_CODE_UNSUPPORTED = 8;
}

message Failure {
  FailureCode code = 1;
  string safe_message = 2;
  bool retryable = 3;
  optional int64 retry_after_millis = 4;
}

message Event {
  Context context = 1;
  oneof result {
    Persisted persisted = 10;
    Acknowledged acknowledged = 11;
    Failure failed = 12;
  }
}

message State {
  string record_id = 1;
  string title = 2;
  oneof sync_status {
    string pending_operation_id = 10;
    Acknowledged synced = 11;
    Failure failed = 12;
  }
}
```

Give each identifier a defined lifetime:

- `correlation_id` associates one request with its immediate responses and logs.
- `operation_id` identifies a logical mutation. Persist it with the mutation and
  reuse it through retries when the server supports idempotency.
- `account_id` scopes data access. `account_generation` invalidates work from an
  earlier sign-in, sign-out or account switch.
- `request_generation` distinguishes replaceable work within its declared scope,
  such as the latest search or selected record. It is not a server revision.

The example assumes account-scoped records and numeric revisions. Omit account metadata for an app with no account concept; retain the ownership/correlation needed by its sessions. Treat an opaque server revision as an opaque value rather than forcing it into an integer. Check the expected local revision inside the storage transaction; a successful core validation against an earlier snapshot is not that check.

Copy the original context into effect results. Do not stamp a late callback with
the current account or request generation. Before applying an event to visible
state, match its account, generation, operation and expected effect phase. Ignore
duplicates and stale UI events. Reconcile durable acknowledgements against the
correct account's operation ledger even when the originating screen has closed.

For this example, commit the local update and outbox entry together before
emitting `persisted` and scheduling `send_mutation`. An immediate acceptance of
`Request` does not mean that storage or the server committed it. Cancellation is
a request to stop work; it is not proof that a submitted remote write was undone.
See [External APIs](external-apis.md) for network outcome semantics.

## Define value and validation semantics

| Value | Contract decision |
| --- | --- |
| 64-bit integer | Use Swift `Int64` and Kotlin `Long` for a signed range. Do not pass through floating-point JSON numbers. ProtoJSON emits 64-bit integers as decimal strings. Define bounds for unsigned values before mapping them to signed host types. |
| Money or precise decimal | Specify a canonical decimal string, or an integer coefficient plus scale. Include currency when relevant. Define rounding and overflow. Do not substitute `Double`. |
| Instant, date or duration | Use a defined timestamp/duration representation and precision. Distinguish a calendar date from an instant. Carry a time-zone identifier separately when the product needs it. |
| Missing, empty or clear | Use explicit presence when absence differs from a default. Model patch operations such as keep/set/clear explicitly. JSON `null`, a missing field and an empty string need declared meanings. |
| Binary data | Use bytes for bounded payloads. Pass attachment IDs and metadata across the reducer boundary rather than copying large files into state. |
| Collection | Define ordering, duplicate handling, size limits and whether replacement or merge is intended. A map does not establish chronology. |

For proto3 scalar fields, use `optional` when presence matters; message and
`oneof` fields already track presence. ProtoJSON `null` normally leaves a field
unset, so it does not provide a general patch-clear operation. See
[field presence](https://protobuf.dev/programming-guides/field_presence/) and the
[ProtoJSON format](https://protobuf.dev/programming-guides/json/).

Validate after decoding and before mutation: supported version and variant,
required IDs, nonnegative generations/revisions, length and range limits,
cross-field relationships, account access and action eligibility. Successful
decoding proves wire shape, not product validity. Return a typed failure and
leave state unchanged when validation fails. Keep diagnostics safe for logs;
do not put credentials or raw response bodies in `safe_message`.

## Evolve the contract deliberately

Add fields compatibly; reserve deleted field numbers and names. Never reuse a
field number or reinterpret an existing field's meaning. Treat binary and JSON
compatibility separately. Binary Protobuf retains unknown fields, but JSON
conversion or rebuilding a message field by field can lose them. Preserve unknown
data when forwarding or rewriting records that must survive a newer writer.

Handle unknown enum values explicitly in both façades. Do not map them to a
known success, authorization or destructive-action case. SwiftProtobuf's proto3
enums expose `UNRECOGNIZED(Int)`; other generators have their own representation.
An unset `oneof` can also represent a newer, unknown variant. Reject unsupported
commands before effects, and give unknown state a deliberate UI fallback. See the
[proto3 evolution guide](https://protobuf.dev/programming-guides/proto3/).

Use a typed session handshake when hosts and libraries can differ: supported
protocol range, selected version, build identity and required/optional
capabilities. Represent capabilities with a defined enum or schema field, such
as support for a particular upload-resume protocol. Negotiate before creating
work and fail clearly when required
capabilities are absent. A `schema_version` field alone does not make an
incompatible change safe. Even a co-versioned app should detect a mismatched
packaged native library; a full negotiation protocol may be unnecessary there.

Check old/new readers and writers, missing fields, unknown variants/enums,
malformed bytes, numeric edges, Unicode, duplicate and stale events, and storage
round trips. Run the real generated codecs in Swift and Kotlin. Do not require
byte-for-byte equality for ordinary Protobuf encodings; assert semantic values
and required unknown-field retention. Keep this evidence distinct from an
installed Android JNI call or a database migration test.

## Keep transport independent of schema

A manual C ABI can accept a pointer and explicit byte count and return an owned
buffer plus length. Carry binary Protobuf as bytes; do not use NUL-terminated
strings or Base64 merely to cross JNI. A stream needs an explicit frame length
and bounds; one `ByteArray` per call already supplies a message boundary.

Declare allocation, copy/free rules, thread/dispatcher rules, handle lifetime,
callback retention, cancellation and close behavior beside the ABI. A JNI shim
can copy `byte[]` with region calls, or release every successfully acquired array
on each path. `JNIEnv` is thread-local; retain callback objects with the proper
reference lifetime. See [Android JNI tips](https://developer.android.com/ndk/guides/jni-tips).

Alternatively, generate a small typed API with SwiftJava `jextract --mode=jni`.
Its documented JNI features include async functions returning Java futures and
copying `[UInt8]` to `byte[]`. The feature documentation lists limited generic
member export and no support for `@Sendable` closure parameters. Check the pinned
release's
[feature documentation](https://docs.swift.org/latest/documentation/swiftjavadocumentation/featuresjextract/).
The project [does not promise API stability before 1.0](https://github.com/swiftlang/swift-java).
Do not infer automatic Kotlin coroutine cancellation, actor execution policy or
safe lifecycle handling from generated bindings. Prove those behaviors in the
installed app. Use [Swift on Android](swift-on-android.md) for packaging and host
verification.
