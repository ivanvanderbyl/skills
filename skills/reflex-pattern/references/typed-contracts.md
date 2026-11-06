# Typed native contracts with SwiftJava

Read this reference when a Swift core exchanges actions, state, effects or
results with Kotlin. Use SwiftJava-generated bindings for this in-process API.
Keep network protocols, stored records and headless JSON projections separate.
This reference describes an architecture and an illustrative API. It does not
establish that a particular type graph builds or runs on Android.

## Select the contract for each boundary

| Boundary | Default | Verification |
| --- | --- | --- |
| Swift core to Kotlin host in the same app | Public Swift types and a narrow façade; generate Java wrappers and JNI with SwiftJava | Compile an independent Kotlin consumer and exercise the actual types, callbacks, async operations and lifetimes in an installed APK |
| Kotlin repository or platform service to Swift | A Swift protocol exported as a Java interface when supported, or typed effect requests and completion events | Prove callback direction, threading, retention, cancellation and teardown for the pinned generator |
| REST service | Existing typed client or DTOs generated from the service's OpenAPI document | Map API values into app-owned domain types; retain the service's actual compatibility rules |
| Protobuf RPC service | Messages and clients generated from the service schema | Keep serialization in the service adapter; the Kotlin-to-Swift API still uses native calls |
| Database or durable queue | Versioned persistence records and explicit migrations | Preserve released data and pending work independently of native wrapper changes |
| Headless tests and diagnostics | JSON/NDJSON projection of typed actions and state | Dispatch through the production owner; keep fixtures and logging outside the public action API |

The native call path is:

```text
Kotlin/Compose -> generated Java API -> JNI -> compiled Swift façade -> Swift core
SwiftUI        -> Swift API                                      -> Swift core
```

SwiftJava generates the interop glue. It does not require a `.proto` schema, an
RPC server, a generic `dispatch(String)` method or JSON-encoded state. Core size
does not change this choice. Use the official
[Swift Android examples](https://github.com/swiftlang/swift-android-examples#readme)
as the integration starting point. Use `jextract --mode=jni` for Android.

## Shape the Swift façade for native callers

Expose typed actions, state snapshots, effect requests, completion events and
expected failures. Use Swift value types and enums with associated values where
the pinned generator supports them. SwiftJava generates Java wrappers that Kotlin
can consume; it does not promise Kotlin data classes or sealed hierarchies.
Keep JNI implementation details and arena handling inside a small Kotlin adapter.

Reuse portable domain types when their semantics and generated API fit. Add
dedicated bridge types only where export limitations or a public compatibility
boundary require them. Keep Room entities, SwiftData managed objects and service
DTOs behind their adapters. Use distinct domain IDs and validate their raw
representation before mutation.

This Swift API sketch shows typed values and effects for a record rename. A
concrete exported session/factory would implement the interface and own its
runtime. Initializers, generated Java names and ownership depend on the selected
public API and generator; this is not a complete binding sample.

```swift
public struct RecordID {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct OperationContext {
    public let operationID: String
    public let accountID: String
    public let accountGeneration: Int64

    public init(operationID: String, accountID: String, accountGeneration: Int64) {
        self.operationID = operationID
        self.accountID = accountID
        self.accountGeneration = accountGeneration
    }
}

public struct RecordSnapshot {
    public let recordID: RecordID
    public let title: String
    public let localRevision: Int64

    public init(recordID: RecordID, title: String, localRevision: Int64) {
        self.recordID = recordID
        self.title = title
        self.localRevision = localRevision
    }
}

public enum RecordAction {
    case rename(recordID: RecordID, title: String, expectedLocalRevision: Int64)
    case cancel(operationID: String)
}

public enum RecordEffect {
    case persistRename(context: OperationContext, recordID: RecordID,
                       title: String, expectedLocalRevision: Int64)
}

public enum RecordFailure {
    case invalidInput
    case unauthorized
    case conflict
    case offline
    case cancelled
    case storage
    case outcomeUnknown
    case unsupported
}

public enum RecordEvent {
    case persisted(context: OperationContext, localRevision: Int64)
    case failed(context: OperationContext, failure: RecordFailure)
}

public protocol RecordSession {
    func snapshot() -> RecordSnapshot
    func dispatch(context: OperationContext, action: RecordAction)
    func receive(event: RecordEvent)
    func close()
}
```

Add an explicit observation/effect-delivery API for the feature. Keep state
transitions in the production owner. Do not reconstruct the
reducer in Kotlin to make a wrapper easier to generate.

## Preserve operation identity and validation

Give each identifier a defined lifetime:

- Correlation ID associates a call with responses and diagnostics when needed.
- Operation ID identifies a logical mutation. Persist it and reuse it through
  retries when the server supports idempotency.
- Account/session generation invalidates work from an earlier account or session.
- Request generation distinguishes replaceable work, such as the latest search.
  Keep it distinct from entity revisions and durable operation identity.

Omit account metadata when the product has no account concept; retain its session
and operation ownership. Preserve opaque server revisions as opaque values.

Carry the initiating context through callbacks. Do not stamp an old result with
the current account or generation. Match its operation and expected phase before
applying it. Ignore stale presentation events; reconcile durable acknowledgements
against the correct operation ledger even after its screen closes.

Validate IDs, ranges, required values, account access, cross-field constraints
and action eligibility before mutation. Generated type safety does not establish
product validity. Return a typed failure and leave state unchanged on rejection.
Keep diagnostics redacted; omit credentials and raw service response bodies.
Check expected local revisions inside the actual storage transaction. Emit local
acceptance only after commit. Cancellation does not prove that a remote write
was undone. See [Persistence and sync](persistence-and-sync.md) and
[External APIs](external-apis.md).

## Define value semantics across the binding

| Value | Contract decision |
| --- | --- |
| Integer | Use explicit widths, such as Swift `Int64` and Kotlin `Long`. Verify the generated signed/unsigned mapping and reject overflow. |
| Money or precise decimal | Specify a canonical decimal string or integer coefficient plus scale, currency and rounding. Do not substitute `Double`. |
| Instant, date or duration | Define precision and units. Distinguish civil dates from instants and carry a time-zone identifier when needed. |
| Optional value or patch | Verify optional export for the exact type. Model keep/set/clear explicitly when absence differs from clearing. |
| Enum with associated values | Verify generated case construction, discrimination and payload access from Kotlin. Keep expected failures typed. |
| Collection or binary data | Verify supported element types, ordering, copying and size limits. Pass attachment IDs instead of large file contents in state. |
| Mutable value | Publish a deliberate snapshot or command API. Do not assume Kotlin references reproduce Swift value-copy semantics. |

Reserve arbitrary JSON for genuinely open product data, such as a user-authored
document, with its own validation policy. An interactive JSON artifact can remain
JSON content while its actions, runtime identity and state access use typed native
bindings. Keep raw dictionaries and serialized action names out of normal UI code.

## Async, callbacks and ownership

Follow [Swift on Android](swift-on-android.md) for generation and packaging.
SwiftJava documents `async` exports as Java futures, including a
`CompletableFuture` mode usable with Kotlin's `await()` extension. Verify the
project's minimum Android API, future mode and coroutine dependencies.

Use generated protocol interfaces for Kotlin-implemented ports only after proving
their exact requirements. Otherwise, pass typed effect requests and completion
events through the façade. Keep Room work in Kotlin's native coroutine/transaction
boundary. A synchronous callback must not use `runBlocking` on the UI thread to
wait for work that needs that same thread.

Define native lifetime with the generated `SwiftArena` API for the pinned release.
Keep returned objects alive through their observers and in-flight work. Close only
after cancelling or draining those users. Compose recomposition does not own a new
arena/session. Verify duplicate close, callback-after-close and cancelled handoff.

Specify coroutine-to-Swift cancellation, observer teardown, callback executor,
MainActor scheduling, buffering and backpressure explicitly. A generated future
or `@ThreadSafe` annotation does not establish these policies. Do not assume
`AsyncSequence` becomes Kotlin `Flow`; write and test an adapter using supported
bindings when needed.

## Build compatibility and migration

Pin SwiftJava, its Java/native support libraries and the compiler/Android SDK
matrix. Generate wrappers and JNI from the same Swift source revision; do not hand
edit them. Check regeneration for drift and rebuild consumers when the public API
changes. SwiftJava is pre-1.0 in the examined release, so check the selected
release's guarantees and feature support before upgrading. Keep wrapper, runtime
and native library identities aligned in packaged artifacts.

For co-shipped hosts and core, verify artifact/build identity rather than adding
a wire-version handshake. Test source/binary compatibility separately if the
library is independently distributed. A generated wrapper does not establish
compatibility with an unrelated native binary.

When replacing an existing Protobuf/JSON dispatcher:

1. Inventory current actions, states, effects, errors and public consumers.
2. Add a typed Swift façade over the same production owner. Prove its generated
   type graph in a small Kotlin consumer before moving every feature.
3. Migrate Kotlin calls and platform ports in vertical slices. Run existing
   behaviour expectations through the native path, including async failures and
   lifecycle cleanup.
4. Retire the internal codec/byte dispatcher once migrated callers and required
   compatibility checks pass. Keep any supported CLI projection, external API
   format and durable payload migrations independently intact.

If a Swift feature cannot be exported, first narrow the façade or use concrete
types and typed effect delivery. Record the exact remaining blocker and justify
an alternative interop path if one is required. Do not silently restore a generic
JSON/Protobuf dispatcher to claim the SwiftJava migration is complete.

Retain schemas where data must outlive a process or cross a network. Apply the
chosen format's presence, unknown-value, numeric and evolution rules there. A
native API refactor is not a database migration or an API protocol upgrade.

## Primary references

- [SwiftJava README and JNI mode](https://github.com/swiftlang/swift-java)
- [Feature documentation at the examined 0.7.0 tag](https://github.com/swiftlang/swift-java/blob/0.7.0/Sources/SwiftJavaDocumentation/Documentation.docc/FeaturesJextract.md)
- [Official weather example: async calls and Kotlin-implemented protocol](https://github.com/swiftlang/swift-android-examples/tree/main/swift-java-weather-app)

Use the project's pinned release documentation when it differs from these
examples. Confirm installed-app behaviour independently of documentation claims.
