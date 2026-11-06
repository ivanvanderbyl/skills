# Core, effects and introspection

Put domain decisions, application transitions and reusable policy in the Swift core. Keep native views, managed persistence objects and OS integration in adapters. A headless host and each native UI use the same production owner.

## Define state ownership

| State | Ownership and lifetime |
| --- | --- |
| Selection, focus, navigation and optimistic presentation | Feature/session state; restore only what the product promises |
| Durable records, local revisions, queued operations and sync cursors | Repository; survive process death according to the storage contract |
| Server revision, entitlement or accepted transaction | Backend authority; a local projection does not establish remote acceptance |
| Tokens, file access grants, native handles and permission state | Native service adapter; expose only the portable result/capability |

Choose one writer/coordinator for each operation. Repository observation, an API response and a push can describe the same change; correlate and deduplicate them before replacing visible state. Specify whether the repository stream or an explicit committed result advances durable state. Tag results with local/server revisions so an older observation cannot undo newer accepted state.

## Extract portable decisions

Trace imports and transitive dependencies before moving files. A type that carries a SwiftUI factory, SwiftData model, Android Context or native SDK handle is not portable because its file moved into a Core target. Separate data/runtime logic from native factories where needed.

Use Swift value models and enums for domain actions, internal events and effects. Expose a narrow [SwiftJava API](typed-contracts.md) over that owner. Reuse suitable portable types and add bridge-specific types only where export support or public compatibility requires them. Keep native database entities and third-party API models in their adapters rather than adding platform fields to every domain model.

Serialize state transitions through a declared actor/executor or reducer owner. Do not hold that owner blocked while a native repository, UI thread or network callback must return work to it. Use a SwiftJava-generated protocol interface for a Kotlin port when its requirements are supported. Use typed asynchronous effect requests and result events when a direct protocol implementation is unsuitable.

For each effect define its request ID, account/session generation, cancellation owner and result type. Match a result to the initiating operation before applying it. Preserve partial results, retries and user-visible errors according to the feature contract. Keep independent effects concurrent when useful; coordinate refresh, sync and transactions where they share a resource.

Distinguish accepting a command from committing durable state. For a local write, the core can issue a typed repository command and show pending presentation; the repository must report commit/rejection before the core advertises durable success. Put atomicity in the actual storage transaction, not in an in-memory reducer update that precedes it. [Persistence and sync](persistence-and-sync.md) defines that boundary.

## Lifetime and cancellation

Give the core/session and its native façade an explicit owner. Compose recomposition and SwiftUI body evaluation should not allocate a new session. If a host replaces a session at the same view identity, resolve retained renderers/subscriptions against the replacement identity.

Specify separately what happens when a view disappears, a caller cancels, an account changes and the process dies. An accepted operation may outlive its initiating view; retain the execution context through its callbacks when that is the contract. Conversely, cancel observers and session-scoped reads when their owner closes. Reconstruct durable operations from the repository after restart rather than keeping an immortal UI task.

Keep accepted native replies from being discarded during a cancellable thread/executor handoff. If creation allocates a native handle but cancellation prevents delivery to its owner, close that abandoned handle. Handle late results idempotently and reject callbacks for destroyed or replaced sessions.

## Headless inspection

Derive a stable node name, redacted state projection, typed action descriptors and active child from the production owner. For example, a task workspace may expose a `SetTitle` descriptor generated from its action contract and a `canEdit` field derived by Core.

The inspection layer decodes an envelope, maps to a typed action, dispatches and serializes the resulting production state. It must not reimplement validation, persistence or a second reducer. Validate the target identity and focused action scope, not just a shared action name. Rejected malformed, unknown or ineligible actions must leave live state unchanged.

Define session creation, inspection, dispatch and closure. Keep deterministic fixtures, clocks and scheduled service delivery outside discoverable user actions. Test IDs and scheduling controls must not become production mutation backdoors.

NDJSON is useful for a persistent subprocess host. Flush each reply before waiting for the next request, correlate concurrent requests and keep logging off stdout. Map the inspection projection to the typed owner. Keep Android production calls on SwiftJava-generated methods independently of this projection. Prefer local calls or subprocesses when no network listener is needed. Compile a network inspection service out of release artifacts.

## Compatibility

Preserve existing Swift products, imports, initializers, resources and minimum OS versions unless the requested migration changes them. Re-exports or wrappers can preserve source compatibility when public types move modules; they do not establish binary ABI compatibility. Build independent source consumers and verify binary clients separately when distributing frameworks.

Keep Android API and packaging compatibility distinct from the Swift domain API. Verify public Kotlin façades and their transitive dependencies from a published AAR/POM consumer, not only a project dependency or internal test target.
