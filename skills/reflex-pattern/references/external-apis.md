# External APIs and platform services

Read this reference when a shared Swift core needs an API, authentication,
streaming or background transfer. Choose ownership explicitly and map service
results into [typed app contracts](typed-contracts.md). The guidance is not proof
that a particular networking package works in a Swift Android build.

## Assign one owner to each operation

Record who owns request construction, transport execution, credentials, refresh,
retry, cancellation, durable scheduling and result delivery. Keep one policy
owner per concern for an operation. A reducer and a native adapter should not
independently retry the same request or refresh the same account.

| Route | Use when | Required proof |
| --- | --- | --- |
| Shared Swift service | The client and its dependencies compile and behave on both Apple and Android, and the operation fits the core's lifecycle | Real HTTP, TLS, decoding, timeout, cancellation and streaming checks on both hosts; dependency and runtime packaging for Android |
| Native host adapter | The existing app owns the API client, an SDK is platform-specific, or an operation needs OS credentials/background facilities | Equivalent typed effects/results and policy across Apple and Kotlin adapters; real native lifecycle checks |
| Shared policy with native transport | Product mapping and sync policy should be shared while hosts execute requests | A narrow transport/service interface, one retry owner and explicit credential access; no duplicate reducer decisions in the adapters |

Preserve a useful existing ownership boundary during a migration. Prefer a
typed service effect such as `FetchRecords(cursor)` or `SubmitMutation(operation)`
over exposing arbitrary URLs and headers to the reducer. A generic HTTP adapter
can be appropriate inside a service implementation; validate origin and
credential policy there.

On Apple, `URLSession` supports data, uploads, downloads and WebSockets, including
async byte sequences for incremental data. On Android, platform
`HttpsURLConnection` and established clients such as OkHttp are options. Select
from the app's dependencies and required behavior. Neither an Apple
`URLSession` pass nor a package manifest proves the chosen Swift networking
implementation works on Android. See [URLSession](https://developer.apple.com/documentation/foundation/urlsession)
and [Android network connections](https://developer.android.com/develop/connectivity/network-ops/connecting).

## Generate service DTOs without importing service policy into state

For REST, use the provider's OpenAPI document when it is authoritative. Swift
OpenAPI Generator provides generated operation methods and types with a
pluggable `ClientTransport`. Its supported feature matrix matters for unions,
nullable values, streaming and non-JSON bodies. See
[Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator) and
[supported OpenAPI features](https://github.com/apple/swift-openapi-generator/blob/main/Sources/swift-openapi-generator/Documentation.docc/Articles/Supported-OpenAPI-features.md).

If Kotlin owns requests, generate Kotlin clients from the same API document or
retain its existing generated client. Pin the generator, HTTP library and
serialization options. OpenAPI Generator's Kotlin union wrappers and unknown
enum fallback behavior depend on those options; generation alone does not prove
the desired semantics. Check the current
[Kotlin generator matrix](https://openapi-generator.tech/docs/generators/kotlin/).

For a Connect/gRPC service, use the published Protobuf service definitions and
the selected runtime's generated clients. Connect has
[Swift](https://connectrpc.com/swift/) and
[Kotlin](https://connectrpc.com/docs/kotlin/getting-started/) client generators.
Choose the actual server protocol and required unary/streaming modes. A shared
`.proto` message does not make every HTTP server a Connect endpoint, and the
availability of a Swift client does not establish Android compatibility.

Map API DTOs into domain values at a service boundary. Keep HTTP status, transport
errors, decoding errors and domain rejections distinct during mapping. Expose
stable product outcomes such as unauthorized, rate-limited, conflict,
unavailable and outcome-unknown. Preserve useful retry metadata without leaking
provider exception types or response bodies into view state. A successful HTTP
status can still contain a domain failure, and a transport failure can follow a
successful server commit.

Record pagination, conditional requests, cache validators, API versions,
server revisions and clock assumptions in the adapter contract. Validate
identifier and account mappings rather than accepting an API DTO as trusted
domain state. Generation checks wire structure; it does not check permissions,
cross-field invariants or conflict policy.

## Keep authentication native and account-scoped

Keep long-lived credentials in host-owned secure storage. Use Apple Keychain
for secrets. Android Keystore protects cryptographic keys; use those keys with
an appropriate encrypted credential store rather than treating Keystore as an
arbitrary token database. Choose access conditions that match foreground and
background needs. See [Keychain services](https://developer.apple.com/documentation/security/keychain-services)
and [Android Keystore](https://developer.android.com/privacy-and-security/keystore).

Let the core request an authenticated service operation or use a narrowly scoped
credential provider. Keep access tokens ephemeral when a shared Swift client
needs them. Do not serialize tokens into state snapshots, bridge traces, outbox
records or ordinary database entities. Partition refresh and credential state
by account and environment.

For OAuth, use authorization code with PKCE and the provider's supported native
flow. Use an external user agent through platform authentication APIs, such as
[`ASWebAuthenticationSession`](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
on Apple and a browser-based Android integration with
[Custom Tabs](https://developer.android.com/develop/ui/views/layout/webapps/overview-of-android-custom-tabs)
or a compatible authentication library. Validate redirect, state and issuer;
validate nonce when the OpenID Connect flow requires it. Keep confidential client
secrets on a server. Installed native apps cannot protect a shared client secret.
These requirements follow [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252).

Deduplicate refresh work for one account. After refresh, replay only requests
whose retry and idempotency rules allow it. Bound authentication retries and
surface expired/revoked credentials to the core. On sign-out or account switch,
advance the account generation, cancel relevant work and reject late events from
changing the new account's state. A callback must retain the initiating account
context, not read whichever account is current when it completes.

## Retry according to the operation's outcome

Separate the logical mutation ID from the individual HTTP attempt ID. Persist a
stable operation/idempotency key before the first attempt when the backend
supports deduplication. Reuse that key and the original logical payload for
retries. Document the server's key scope, expiry, payload comparison and status
lookup behavior; the header's presence alone is not an idempotency guarantee.

| Observation | Core-visible meaning | Next action |
| --- | --- | --- |
| Local transaction committed | Accepted locally, pending remote acknowledgement | Keep the durable operation queued until the server result is reconciled |
| Authoritative server success | Acknowledged with remote identity/revision | Commit the acknowledgement and dequeue atomically according to storage policy |
| Conflict or domain rejection | Known rejection | Apply the declared merge, user-resolution or rollback policy |
| Timeout, connection loss or cancellation after submission may have started | Remote outcome unknown | Query operation status or retry with supported deduplication; do not report an undo or invent a new mutation ID |
| Rate limit or transient unavailability | Retry may be permitted | Honor applicable retry metadata; apply bounded backoff and jitter through the single retry owner |

Do not automatically retry a non-idempotent write just because its response was
lost. HTTP permits automatic retry under defined idempotency/knowledge
conditions, not for every failed request. See
[RFC 9110, idempotent methods](https://www.rfc-editor.org/rfc/rfc9110#section-9.2.2).

Treat connectivity observations as scheduling hints. A connected device can
still face DNS failure, captive portals, expired credentials or an unreachable
service. Let actual attempt results drive typed state. Keep reads, optimistic
local writes, pending uploads, confirmed server state and permanent rejections
distinguishable in product state.

## Stream framed events with bounded work

Declare whether the service uses SSE, NDJSON, WebSocket messages, Connect frames
or another framing protocol. Incremental network chunks are not application
messages. Buffer only until a complete bounded frame is available, preserve
partial UTF-8 sequences, and then decode and validate the typed event. Use the
runtime's protocol implementation when available. Connect's streaming framing
and end-of-stream error metadata are defined in its
[protocol reference](https://connectrpc.com/docs/protocol/).

Define event identity, sequence ordering, duplication, gap detection and resume
cursor semantics. Distinguish clean completion, server terminal error,
malformed frame, connection loss and user cancellation. Preserve partial domain
content according to the product contract; EOF does not automatically mean a
successful result.

Bound pending bytes and queued events across HTTP, JNI, Swift task and Kotlin
Flow/coroutine boundaries. Use backpressure or an explicit credit/demand policy.
Coalesce replaceable progress/state updates only when losing intermediate values
is harmless. Do not drop durable acknowledgements or commands. A callback per
byte or token can overwhelm the bridge even if each codec is fast.

Propagate cancellation to the owning request/task and retain ownership until its
terminal cleanup. Avoid holding locks or JNI array pins across suspension. Drop
late UI events by operation and generation, and reconcile any durable outcome
separately. Verify early cancellation, mid-frame cancellation, teardown, slow
consumers and reconnects on the actual hosts.

## Use native background transfer for durable work

Represent an attachment in the core with a stable ID, account, size, content
type, checksum when required, local availability and transfer state. Keep the
native file/URI handle and access permissions in the host adapter. Stage content
into durable app-owned storage, or persist the required platform permission,
before acknowledging that it can be uploaded later. An expiring picker URI or
temporary file is not a durable upload source.

Persist the outbox operation, attachment relationship and stable operation ID
before scheduling. Record the native task/job identifier against that operation.
On relaunch, reconcile durable records with existing OS tasks and server status
before creating more work. Keep payload metadata and mutation ordering consistent
with the persistence transaction. A foreground Swift task is not a replacement
for OS-managed scheduling.

On Apple, use background `URLSession` for suitable file uploads/downloads and
reassociate the session by its stable identifier after a system relaunch. Its
background upload support requires a file source, and transfer scheduling and
delegate delivery have platform constraints. See
[background URLSession transfers](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background).

On Android, choose WorkManager, a user-initiated data transfer job or a more
specific API according to the operation, OS support and execution limits.
Design interruptible and repeatable work; WorkManager can cancel and retry.
Do not promise immediate or continuous execution from an ordinary scheduled job.
See [Android data transfer options](https://developer.android.com/develop/background-work/background-tasks/data-transfer-options).

Deliver typed progress and terminal events with the original operation/account
context. Keep retry authority consistent when the OS scheduler can restart work.
Protect staged files until terminal reconciliation and the declared retention
policy allow deletion. Test process death, relaunch, sign-out, missing source
files, duplicate completion and an ambiguous remote commit. Report native
background proof separately from deterministic core/outbox tests.
