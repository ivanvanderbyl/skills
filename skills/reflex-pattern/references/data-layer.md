# Data layer and sync strategy

Read this reference when a feature keeps server data on the device and lets the user change it: a list that must stay fresh, an edit that must survive an app kill or an offline period, or a view that must never flip between a local and a server value. It gives one design for the path from a tap to the store, the server and back, the reason for each rule, and the tests that prove a project's own core follows them. [Persistence and sync](persistence-and-sync.md) covers each native store, runner claims, account scope and scheduling.

The rules were found and checked with the seeded simulation in `assets/`, on a model core for one resource, with Swift 6.4.2 on Linux and macOS. That is evidence about the rules. It says nothing about a project's store, backend or devices. One run then drove the same rules against a real API server and database, with the client store and the network faults still simulated and no creates. Rules 1, 2, 3 and 8 were needed there too, and rule 4 failed because a timestamp stood in for the revision. The browser store notes were observed with TanStack DB 1.0.0-rc.1.5 in Chromium only.

Contents: the shape; the write path; the eight rules; what the server must provide; remote changes; store adapters; decisions to make per app; the bundled model; test strategies; limits.

## The shape

- **The core decides everything.** Each feature is a session in the [core](core-and-contract.md): it takes events, returns effects and exposes a view. It performs no I/O, has no clock and makes no identifiers.
- **Each host runs effects and decides nothing.** One runtime per platform executes each kind of effect against two adapters: a store adapter (SwiftData, Room, a browser store) and a network adapter (the platform's API client).
- **The UI reads only the session's view and writes only by sending an intent.** A view that queries the store directly shows rows without the user's pending edits, for the reason under "The write path".

Declare each effect's kind and result type. A request is answered exactly once. A stream is answered until the core cancels it.

| Effect | Kind | The host answers with |
| --- | --- | --- |
| `load` | request | the rows, unsent writes and rejected writes the store holds |
| `commit(StoreWrite)` | request | committed, or rejected whole |
| `watch(scope)` | stream | one signal for each change made by another writer |
| `send(writes)` | request | each write's outcome and the server's row, or a failure whose outcome is unknown |
| `fetch(scope)`, `fetchRow(id)` | request | server rows, or a failure |
| `startTimer(after)` | request | fired |
| `subscribeRemote(scopes)` | stream | hints that something changed |

The core describes every durable change as one value, and the store applies all of it or none of it:

```swift
public struct StoreWrite: Equatable, Sendable {
    public var upserts: [Row] = []         // server-confirmed rows only
    public var deletes: [Int] = []
    public var addOutbox: [Mutation] = []  // the user's unsent writes
    public var settleOutbox: [Int] = []    // writes the server applied
    public var failOutbox: [Int] = []      // writes the server rejected
}
```

A project's `StoreWrite` also carries the sync checkpoint that belongs to a page of rows, and expected row revisions when another writer shares the store. The model leaves both out.

The runtime stamps every event with the current time and every intent with a new write ID, because the core can produce neither. The write ID is stored with the outbox record and reused on every retry.

## The write path

One edit, from tap to settled:

1. The UI sends an intent. The runtime adds a write ID.
2. The core adds the edit to its pending list and renders. The view shows the new value, marked pending. Nothing has been written or sent.
3. The core emits `commit` with the outbox record only. The row is not in this write.
4. The store reports the commit. From here the edit survives an app kill.
5. The core emits `send` with that row's durable writes, in order. The writes sent together are one envelope, and one envelope per row is in flight at a time.
6. The server applies the write and answers with each write's outcome and the row as it now stands.
7. The core updates its memory and renders. The pending mark clears.
8. The core emits one `commit` that settles the outbox record and stores the server's row.

Two choices carry the design.

**Rows hold only what the server confirmed.** The obvious alternative writes the edit into the row and adds an outbox record beside it. Then any fetch that lands before the server has the edit overwrites the row, and the user watches the edit vanish and come back. Preventing that needs per-field dirty marks, a remembered base value and an undo for each rejected write. With confirmed rows, every stored row is a copy of some server state, so an incoming row is compared by revision alone, a rejection needs no undo, and "pending" is derived: a row is pending while an outbox record names it. The cost is that every read goes through the overlay, which is why the view comes from the core and the store's own live query is used only as a change signal.

**The core changes its memory when it issues a write.** It renders in the same call that took the event and does not wait for the store or read it back. The view therefore updates before any I/O and does not depend on when a store's observer fires. `watch` exists for writers the core did not issue: a share extension, a widget, another browser tab. The cost is that memory runs ahead of the store by one commit. An edit made within that commit of an app kill is lost, and a commit that fails means memory is wrong, so the core must drop it and `load` again.

## The eight rules

Each rule exists because the simulation fails without it. The text after each rule says how.

1. **Rows hold only what the server confirmed; a pending edit is an outbox record laid over its row in the view.** Written into the row, the edit is reverted by the next fetch that predates it. This failed in almost every run.
2. **The outbox is in the store, and a write is sent only after its outbox record is committed.** Kept in memory, an edit the user saw accepted is lost when the app is killed, and so is the record that the server rejected one.
3. **The acknowledgement carries the server's row, and settling the outbox record and storing that row are one `StoreWrite`.** Settled alone, the overlay disappears before the row arrives, and the view shows the old value until the next fetch.
4. **A row is replaced only by a newer server revision.** Answers arrive out of order, and an older one would move a row backwards. This rule is safe only with a true revision; "What the server must provide" says what a timestamp does to it.
5. **A fetch that was in flight when an acknowledgement landed may not touch that row; the core fetches again.** That fetch may have read the server before the write applied, so its copy of the row is older than the acknowledgement, and for a new row it is missing.
6. **A create whose row has appeared in confirmed rows counts as applied, even if its acknowledgement never arrived.** Otherwise, when someone deletes that row, the pending create draws it again as a new row.
7. **Only a list answer brings back a row that a list answer removed.** An acknowledgement written before a deletion can arrive after the list that reported the deletion. The core keeps a mark for each row a list removed, does not apply such an acknowledgement, and asks for the list again.
8. **A rejected write moves to a failed list in the store, in the write that settles the rest of its envelope, and stays until the user dismisses it.** Held in memory, the rejection is forgotten on the next kill and the user's edit disappears without explanation.

Rules 6 and 7 each failed in fewer than 1 run in 1,000. Manual testing and a handful of unit tests do not find failures that rare, which is the reason for the simulation below.

Rules 4, 5 and 7 overlap, so a short run can pass without one of them. For a row that already exists, rule 4 refuses most of what rule 5 guards against, and with creates turned off in the model rule 5's control failed about 1 run in 5,000 and rule 7's about 1 in 2,500. Forty seeds against a real backend showed neither failing, which is what those rates predict. Do not drop a rule because a short run passed without it; scan enough seeds to see its control fail.

The model also depends on these, which have no control of their own: one envelope in flight per row, holding its writes in order; a write ID the server answers the same way every time; a hint that names a row fetching that row alone; and a store that applies writes in the order issued.

In a project, the unit sent in order is the aggregate whose writes depend on each other, such as a record with its child rows, not always one row.

## What the server must provide

- **A revision on each row, raised in the same transaction as every change to it.** Rule 4 compares it. A timestamp taken from an application server's clock is not a revision. Two servers can order two changes wrongly, and one server can too when it reads the clock before it takes the row's lock. With a timestamp, rule 4 does harm: the user's second edit commits after their first but is stamped earlier, the core refuses the acknowledged row as older while settling its outbox record, and the view shows the first edit with no pending mark until some later change carries a higher stamp. This was observed against a real backend with one server's clock 250 ms behind, and it reproduces in the model by hand.
- **Writes that carry a client-chosen write ID and never apply one twice.** A repeated write reports its outcome again. Without it, a retry after a lost acknowledgement applies the write a second time, and was observed overwriting a change another writer had made in between.
- **An acknowledgement that returns the row as it stands after the write.** Rule 3 stores it. This includes a delete or a cancel. An answer of bare success forces a separate read, which can already hold a later writer's change, and it hides a write that changed nothing.
- **A list answer that is complete for its scope, or says that it is not.** The model reads absence from the list as removal. A paged or windowed read cannot be read that way; follow "Pull deltas and resolve conflicts" in [Persistence and sync](persistence-and-sync.md).

A marker on each list answer for "as of which revision" is not needed. An earlier form of rule 7 used one; the local mark replaced it and passed the same runs. Revisions on hints are optional and let the core skip a fetch for a change it already has.

Record which of these the backend lacks before choosing a queued-write policy. Without a repeat-safe write ID, keep the operation online-only. Without a true revision, either keep it online-only, or turn rule 4 off for that resource and store each answer as it arrives: the model still converges that way, and a row can briefly show an older value when answers arrive out of order.

## Remote changes are hints

A push, a stream event, a poll timer, a return to the foreground, a background wake and a reconnect all become one event: something changed, in this scope, possibly naming a row. Data reaches the store only through `fetch` and `commit`.

The reason is that no source is reliable. Apple does not guarantee delivery of [background pushes](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) and may throttle them. Android may delay [normal-priority messages](https://firebase.google.com/docs/cloud-messaging/android/message-priority) in Doze. A stream can drop an event without the client knowing unless the server numbers them. A core that applies a hint's payload as data inherits every gap. A core that treats it as a reason to fetch only has to converge, with three rules:

1. One fetch is in flight per scope. A hint during it causes exactly one more.
2. Every gap is a reconcile: start, stream connect or reconnect, foreground, background wake, sign-in and account switch each refetch the watched scopes.
3. Poll slowly even while a stream is live, unless the stream proves it lost nothing, for example with sequence numbers.

The model implements the first rule, the poll and the reconcile at start. Stream connection state was checked in a separate simulation that is not bundled.

In the background the runtime runs the core's sessions until no effect is in flight or the operating system's budget ends, then reports the result to the system. Unfinished work stays in the outbox or is redone at the next gap. The core does not know which system woke it.

## Store adapters

Every store adapter has the same five duties, and nothing else:

1. `load` returns the rows, the outbox and the failed list.
2. `commit` applies one `StoreWrite` in one transaction on one physical store, or rejects it whole. Rows, outbox, failed list and checkpoint are in that one store.
3. Writes apply in the order the core issued them.
4. A reported commit is durable across process death.
5. `watch` signals a change made by any other writer.

Merge, ordering and conflict rules stay in the core, so two adapters that pass the same conformance fixture behave identically. For SwiftData and Room, [Persistence and sync](persistence-and-sync.md) names the transaction and observation APIs.

### A browser store

The browser adapter needs the same single transaction. A raw IndexedDB transaction can [span several object stores](https://developer.mozilla.org/en-US/docs/Web/API/IDBDatabase/transaction), and SQLite on OPFS in a worker gives ordinary SQL transactions. Neither claim was run here.

A collection library is a different matter. Observed with TanStack DB 1.0.0-rc.1.5 and its browser SQLite persistence in Chromium; recheck against the version the project pins:

- A persisted transaction belonged to one collection. With rows, outbox and checkpoint in three collections, a fault between them left two saved and one missing.
- With one collection, an injected storage fault left memory showing the write as applied while storage had none of it.
- In the default setup, two tabs each made writes that resolved, and one tab's were gone after a restart. With the library's multi-tab coordinator nothing was lost, but both tabs were told the same conditional update succeeded.
- The library's offline queue is documented to keep its records in a different store from the rows, so it cannot satisfy rule 3. This was read, not run.

What passed: the project's own tables for rows, outbox and checkpoint, written in one `BEGIN IMMEDIATE` transaction with the expected-revision check in SQL, under a Web Lock, on the database the library's SQLite package opens. The library's plain collections were then patched from the committed write and served as the in-memory view. Patch each resource's collection in one batch: a subscriber saw a half-applied write when three collections were patched in turn, and none when one collection took the whole write.

Still to design for the web: a `BroadcastChannel` message after each commit as the other tabs' `watch`, the project's own SQL migrations, and a private window that refuses persistent storage. In that case the host tells the core it has no durable outbox, and the session uses the online-only policy.

## Decisions to make per app

None of these is in the model or was simulated. Settle each before the first durable write ships, and record it with `decide`.

| Question | Default |
| --- | --- |
| A commit fails | The core drops its memory and loads again. If the store cannot open, the host resets it and refetches, and tells the user when the outbox was not empty. |
| Sign-out and account switch | One store per account. Ask the user before discarding a non-empty outbox. |
| Expired sign-in and no connection | Both are events to the core. Being offline pauses sending without counting a failure. An authentication failure pauses the outbox until the token is refreshed. |
| Retry | Backoff with jitter and a cap, decided in the core through the timer effect. An error that a retry cannot fix moves the write to the failed list. |
| Writes that depend on each other | Send per aggregate, in order. A create needs an ID the client chose and the server accepts. |
| Another writer on the same store | It adds outbox records through the same `StoreWrite`; expected revisions settle a race. A second sender is safe only because the write ID is repeat-safe. |
| Stored outbox records after an app upgrade | Version the record's payload and give old records an upgrade path or a visible failure. |
| Local-only state | Drafts and settings are rows with no outbox and no revision, written through the same `StoreWrite`. Commit a text draft on each pause in typing. |
| Long lists | The core owns the window of rows a view holds. View rows carry stable IDs, and the runtime reads the view at most once per frame. |

## The bundled model

`assets/DataLayerCore.swift` is the core for one resource, with no imports: the eight rules as flags in `Rules`, the overlay, and the `load`, `commit`, `send`, `fetch`, `fetchRow` and `startTimer` effects. It has no `watch` and no `subscribeRemote`. `assets/WritePathSimulation.swift` is the harness. `assets/DataLayerTests.swift` holds the tests. Read the core as the worked example of the rules. It is not a sync engine: titles are integers, there is one resource, and a row is the unit of sending.

To run it, put the first two files in a module named `DataLayerModel` and the third in its test target, then run `swift test` with a Swift 6 toolchain. Expect 12 tests in 2 suites to pass.

The overlay is the code to copy first. Confirmed rows are never edited to show pending state:

```swift
public func view() -> [ViewRow] {
    var rows: [Int: ViewRow] = [:]
    for row in confirmed.values {
        rows[row.id] = ViewRow(id: row.id, title: row.title, confirmedRevision: row.revision, pending: false)
    }
    for item in pending {
        let id = item.mutation.rowID
        switch item.mutation.op {
        case let .create(title):
            if rows[id] == nil {
                if !item.seenConfirmed { rows[id] = ViewRow(id: id, title: title, confirmedRevision: 0, pending: true) }
            } else {
                rows[id]?.pending = true
            }
        case let .rename(title):
            rows[id]?.title = title
            rows[id]?.pending = true
        }
    }
    return rows.values.sorted { $0.id < $1.id }
}
```

This excerpt omits the branch the first control uses. `seenConfirmed` is rule 6.

## Test strategies

Use four layers. Each proves something the others cannot.

### One hand-driven test per rule

Drive the core event by event and assert the exact effects and view. These tests document the rules and fail on a wrong implementation without any randomness. From the bundled suite:

```swift
@Test("An edit shows at once, and its first write holds only the outbox record")
func editIsOverlaid() {
    var (core, _, _) = started(rows: [row])
    let accepted = core.handle(.intent(rename))

    #expect(core.view() == [ViewRow(id: 1, title: 11, confirmedRevision: 1, pending: true)])
    #expect(accepted.commits == [StoreWrite(addOutbox: [rename])])
    #expect(accepted.sends.isEmpty, "a write is sent only after its outbox record is durable")

    let durable = core.handle(.didCommit(commitID: accepted.commitIDs[0]))
    #expect(durable.sends.map(\.writes) == [[rename]])
}
```

### A seeded simulation with one control per rule

Hand-driven tests only cover the interleavings someone thought of. The simulation generates the rest.

- **Build a world around the core:** a server that other people also change, a store that survives a kill and loses writes it had not applied, and a network that delays answers.
- **Inject every fault the product can meet:** app kills, a send lost before the server, an acknowledgement lost after it, failed fetches, dropped hints and server rejections.
- **Check after every step:** the user's pending edit is in the view; no row shows an older revision than it did; no removed row comes back. **Check at the end:** store, view and server agree, the outbox is empty, every accepted write was applied or rejected, and every rejection is still reported.
- **Give each rule a flag and a control.** The control turns one rule off and must fail, and the same seeds must pass with the rule on. A rule whose control cannot be made to fail is not shown to be needed: remove it, or find the fault that needs it.
- **Assert the run did what it claims.** Count kills, applied writes and rejections and require each to be above zero, so a change that silences the faults cannot pass.
- **Include long offline periods.** While offline no send or fetch reaches the server and no hint arrives, and the user keeps editing and the app is still killed. Set `goOffline` in `Faults`. All rules held in the model through such periods, and the controls for rules 1 and 2 failed.
- **Scan wide, then pin.** Run tens of thousands of seeds in a release build when a rule changes. Pin the first failing seed of a rare control in the test suite, and scan again after any change to the world, because every pinned seed moves.
- **Trace a failing seed before changing the core.** First decide whether the check is wrong. Then find the exact order of events; a fix written from a guess at the cause can leave the control failing on the same seeds.
- **Count what is lost by design.** Edits made within one commit of a kill never reach the store. Report that number separately instead of excluding those edits without saying so.

To use the harness on a project's core, replace `DataCore` with that core, keep the faults and checks, and write one control per rule the project adds.

Then run the same harness against the real server, with the client store and the faults still simulated. The fake server assumes what the rules need, so only a real one shows what is missing. In that run:

- record commit order in the database, for example with an audit trigger, and compare it with the revision the API returns;
- count writes the server applied more than once after a retry;
- put two server instances behind the client with one clock set behind;
- keep the controls, because a seed does not replay exactly against a live server and a control is then the only evidence that a rule mattered.

### One conformance fixture for every store adapter

The simulation's store is a dictionary. Replay one fixture against each real adapter, on disk:

- a write with rows, outbox and checkpoint is all there or all absent after a fault injected in the middle and a reopen;
- writes issued in order are applied in order;
- a reported commit is present after the process restarts;
- a write with a stale expected revision is rejected whole;
- two writers race on one conditional update and exactly one wins;
- `watch` fires for the other writer's commit.

Include a control here too: an adapter that deliberately splits one write into two transactions must be caught by the first case.

### One loop test per host

Through each target's real façade, with a fake store behind the adapter: start, send a rename, see it in the view marked pending while the store still holds the old value, commit, see the mark clear, stop, and see the watch stream cancelled in the host. Change the pending label in the core and require every host's test to fail.

Record each layer as its own check per target with `receipt`. The simulation and the hand-driven tests are core checks; the fixture and the loop test are per target and need the real store or façade. See [Shared tests](shared-tests.md) for the runners.

## Limits

- The model has one resource on one device. The user creates and renames, and never deletes.
- Its server answers each write on its own. An all-or-nothing envelope that is partly rejected and resent was not simulated.
- A failed commit, a second writer, backoff and authentication were not simulated.
- Time is counted in steps, not seconds.
- In the simulation no real store, network or device took part. Prove those with the fixture and the loop test.
- The run against a real backend was one backend, with a simulated client store, no creates, a timestamp as the revision and 30 to 190 seeds per case.
