# Persistence and sync

Use this reference when a Reflex app persists data, calls a remote service or synchronizes devices. Apply the [Core and contract](core-and-contract.md) boundary first. The repository and sync design here is an architecture recommendation. The linked platform behaviours are documentation-backed; this reference is not runtime validation of a particular store, SDK or backend.

## Choose storage and operation semantics

Default to platform repositories: SwiftData on supported Apple targets and Room on Android. Adapt both to shared Swift value contracts. Keep SwiftData imports, `@Model` classes, `ModelContext`, Room entities and DAOs outside the shared domain core. Share identity, validation, commands and merge decisions where portable. Keep local schema definitions and migrations with their store adapters. Equivalent domain behaviour does not imply identical tables, SQLite files or migration versions.

If one portable SQLite implementation would materially reduce duplication, first prove its library, driver, threading, encryption and migration support on every required Apple and Android target. Give that implementation ownership of its schema and connections. Do not open SwiftData's private store through Room or treat either framework's schema as a portable contract. Preserve native repositories when the portable dependency or bridge cannot meet the app's requirements.

Choose semantics per operation, rather than making every feature offline-first:

| Operation requirement | Suitable behaviour |
| --- | --- |
| Server approval is needed before success, such as a reservation | Keep a local draft if useful; show success only after server confirmation. |
| A user's edit must survive offline use, such as renaming a task | Commit locally with a durable pending operation; show pending, acknowledged or failed status. |
| Read-only catalog data can be stale | Cache it with freshness metadata and an explicit refresh/error policy. |
| Disposable telemetry can be delayed | Use a bounded queue with the product's permitted loss policy. |

Android's [offline-first guide](https://developer.android.com/topic/architecture/data-layer/offline-first) describes several write strategies and permits online-only writes. Use product requirements to choose; an offline cache does not establish that a remote operation is safe to queue.

## Define repository and remote contracts

Use value snapshots and typed commands across the SwiftJava API, such as `TaskSnapshot`, `RenameTask` and `ApplyTaskChanges`. Map store objects to snapshots inside their owning context or coroutine. Implement a supported generated protocol interface or consume typed effect requests and return typed completion events. Keep Room's Flow, suspending DAO calls and entities inside the Kotlin adapter; do not assume the generator translates them into Swift repository requirements. Let the reducer distinguish an optimistic edit, a successful local commit and a server acknowledgement.

Record these semantics before implementing adapters:

| Contract | Decisions to record |
| --- | --- |
| Identity and ownership | Stable domain ID; account/tenant scope; client-created IDs or server-ID reconciliation. Keep framework persistent IDs internal. |
| Values | Required versus absent versus null; timestamp/time-zone precision; decimal and integer ranges; unknown enum cases; relationship IDs. |
| Repository operations | Read/observe snapshots; atomically commit a command with its outbox record; atomically apply a delta page with its checkpoint; structured failures and cancellation. |
| Remote mutation | Payload version; base server revision; operation ID; authentication scope; validation/conflict errors; acknowledgement result; duplicate-request semantics. |
| Remote reads | Cursor scope, ordering and expiry; pagination consistency; deletes; full-resync procedure; schema compatibility. |

Separate local schema version, wire payload version, entity server revision and sync cursor. Give persisted commands an upgrade policy when their payload format changes. Avoid serializing platform model graphs or credentials into the outbox. Treat cancellation and timeouts as an unknown remote outcome unless the service proves otherwise.

For third-party APIs, inspect the actual endpoint's pagination, retention, preconditions and retry contract. HTTP provides [idempotent method semantics](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.2) and [conditional updates with `If-Match`](https://www.rfc-editor.org/rfc/rfc9110.html#section-13.1.1). These do not establish that an arbitrary POST accepts an idempotency key or that a provider offers a change feed. If a required guarantee is absent, use a backend adapter, reconciliation or a restricted operation policy.

## Implement each native store

### Apple: SwiftData

- Confine model access to its owning context/executor. SwiftUI's environment context and `ModelContainer.mainContext` use the main actor. Use a dedicated `@ModelActor` repository when isolated storage work fits the app. Return value snapshots or domain IDs across actor boundaries and refetch models in the receiving context. Apple's [ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext) and [concurrency support](https://developer.apple.com/documentation/swiftdata/concurrencysupport) describe these boundaries.
- Make durable command acceptance an explicit save boundary. Use a dedicated working context so unrelated unsaved view edits cannot join the command. Disable autosave for that context when it would split the intended unit. Put the entity change and outbox record in the same physical store and commit together. [`transaction(block:)`](https://developer.apple.com/documentation/swiftdata/modelcontext/transaction(block:)) saves pending changes after its closure; Apple's [SwiftData history session](https://developer.apple.com/videos/play/wwdc2024/10075/) describes one save's changes as one transaction in the default store. Do not infer atomicity across configurations, stores or a custom `DataStore`. On failure, discard or roll back the working context and report failure.
- Version the local model with `VersionedSchema` and [`SchemaMigrationPlan`](https://developer.apple.com/documentation/swiftdata/schemamigrationplan) when evolution needs explicit stages. Preserve unsent operations, tombstones and checkpoints through migrations. Test upgrades from supported released stores, including data values and interrupted sync state. Opening a fresh container does not verify a migration.
- Connect store observation to the Reflex owner through adapter messages. Keep command handling and application eligibility in that owner even when SwiftUI uses `@Query` for a presentation read.

### Android: Room

- Keep Room entities and DAOs in Kotlin. Use asynchronous one-shot operations and observable `Flow` queries, then map results to portable snapshots before entering Swift. Room's [asynchronous query guide](https://developer.android.com/training/data-storage/room/async-queries) notes that table changes can rerun observable queries even when the result does not change. Use result deduplication when appropriate; a Flow emission is not a remote acknowledgement.
- Group entity changes and outbox writes in one database transaction on the same `RoomDatabase`. Use the transaction API for the pinned Room version, such as [`withTransaction`](https://developer.android.com/reference/androidx/room/RoomDatabaseKt#withTransaction(androidx.room.RoomDatabase,kotlin.jvm.functions.Function1)) or a transactional DAO operation. Keep network waits outside transactions. The cited `withTransaction` contract treats exceptions and coroutine cancellation as unsuccessful transactions; do not swallow a failure and accidentally commit.
- Export and retain Room schemas. Supply automatic or manual migrations as appropriate, then test each supported upgrade path and the migrated values with the version's migration helper. [Room migration guidance](https://developer.android.com/training/data-storage/room/migrating-db-versions) distinguishes schema validation from data checks. Destructive fallback deletes local data; use it only for explicitly disposable data, never as a routine repair for unsent user edits.

### CloudKit and a cross-platform service

SwiftData's automatic CloudKit integration synchronizes through iCloud; it does not provide a Room replicator. Apple's [sync guide](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices) requires compatible capabilities and schemas: uniqueness cannot be enforced, relationships must be optional, relationship changes are not remotely atomic, and production schema evolution is additive. A local save does not prove remote delivery.

For Apple and Android accounts sharing data, default to a common backend contract both platforms can call. If choosing CloudKit APIs explicitly for cross-platform access, verify their authentication, access and synchronization contract separately from SwiftData's automatic integration. Choose one synchronization authority for each dataset. When a custom backend owns sync, explicitly configure SwiftData's CloudKit setting, such as `.none`, rather than relying on entitlement discovery. Keep any Apple-only dataset separate and document its account and sharing behaviour.

## Persist and replay offline mutations

Use this procedure for operations that the product permits accepting locally. These transaction and protocol requirements belong to the application; neither native store supplies an end-to-end sync protocol.

1. Validate the command in the core. In one local transaction, recheck account scope and expected local revision, apply the durable change and insert an outbox record containing account scope, stable operation ID, entity ID, command/payload version, base server revision and ordering dependencies. Reject or recompute a decision based on stale local data. Return local acceptance only after commit. A memory queue or a separate preferences write cannot make these records atomic.
2. Wake a runner after commit and on launch/resume. Treat scheduling as a hint: a crash between commit and scheduling must be recovered by scanning the outbox. Claim eligible records transactionally with an owner/lease token and expiry. Acknowledge only the current claim. Recover expired claims after a crash and preserve ordering where later commands depend on earlier ones. Use a fencing generation if an expired runner could still return.
3. Send outside the transaction with credentials for the recorded account. Reuse the same operation ID and payload for a retry. Require the server to define deduplication scope, retention and result replay for non-idempotent mutations. If the server committed but its response was lost, reconcile by that identity before reporting failure or creating a replacement operation. Do not promise exactly-once effects from client retries.
4. In one local transaction, persist the confirmed result/revision and acknowledge the matching outbox entry. Preserve newer pending local edits when applying an older acknowledgement. Coalesce or supersede queued commands only when their domain semantics permit it.
5. Persist retry state and next-attempt time. Retry transient failures with backoff and jitter, respecting provider rate limits. Pause for expired authentication; surface validation errors and conflicts as resolvable states. Avoid an endless retry loop for a permanently rejected record.

Prove claim and revision checks against the chosen store under contention. Actor isolation serializes one repository owner; it does not make a SwiftData read/modify/save sequence a cross-process compare-and-swap. For multiple contexts or processes, use an enforceable native claim primitive or restrict writes to a coordinated single writer. Do not infer queue exclusivity solely from a WorkManager unique-work name or one foreground mutex.

Keep account data and runners isolated. Attach account ID, persisted session epoch and request/claim identity to effects. Advance the epoch on logout or account replacement before cancellation and cleanup. Recheck it inside the transaction that would commit a callback; cancellation alone does not reject a late response. Apply the product's explicit retain-or-delete policy to pending edits and credentials. Reauthentication to the same account must not revive callbacks from an older epoch.

## Pull deltas and resolve conflicts

Apply each validated delta page and its next checkpoint in one local transaction in the same store. On failure, replay from the previous checkpoint. Scope cursors to account, collection, filter and protocol version. Keep a local SwiftData history token distinct from a server change cursor. If a provider has no delta protocol, define polling and snapshot completeness before interpreting absence as deletion.

Use server revisions or another specified ordering rule to reject duplicate and stale changes. Preserve local pending intent while updating the server baseline. Choose conflict policy per domain: a task title might need an explicit choice, independent preferences might merge by field, and a reservation might require server rejection. Use server preconditions where available. Do not choose last-write-wins merely because device timestamps exist; clock skew and domain invariants still need a policy.

Represent deletion in the sync contract with a tombstone or equivalent durable delete event. Specify its revision, acknowledgement and retention rules so an offline device cannot resurrect deleted data. If cursor expiry or tombstone retention requires a full refresh, preserve pending operations, stage a complete consistent server snapshot, then promote it and its checkpoint together. Rebase or surface conflicts for local intent. Do not wipe the active store or infer deletions from a partial page.

## Schedule and verify recovery

On Android, use [WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent) for eligible persistent sync work. It retains scheduled work across restarts and reboots. [Constraints and retries](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work) affect execution and can stop a running worker. Unique work helps scheduling but does not replace outbox claims when foreground and background runners coexist.

On Apple platforms, choose the target's supported background mechanism. For iOS/iPadOS, the system chooses when [background refresh or processing](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) runs. Handle expiration, persist progress and resume on the next opportunity. Provide foreground launch/resume sync on both platforms. Neither scheduler establishes a delivery deadline or proves server reachability.

Verify these outcomes against each real store and backend contract:

- Restart after local commit but before scheduling; restart after remote commit but before local acknowledgement.
- Fail the mutation/outbox transaction and the delta/checkpoint transaction; recover without a partial durable result.
- Race two runners, expire a claim, repeat a response and deliver an old response after logout and same-account login.
- Pull duplicates, out-of-order changes, deletes and expired cursors while local edits remain pending.
- Upgrade released stores containing pending operations; exercise native observation and background expiration.

Use deterministic core tests for command and merge decisions. Use adapter integration tests for database transactions, migrations and observation; use installed native hosts for lifecycle and background behaviour. Record the tested versions and evidence separately. Before implementation, recheck the links against the project's Xcode/Swift toolchain, minimum OS versions, pinned Room namespace/version, WorkManager version and provider API. Current vendor guides can describe newer APIs than the project uses.
