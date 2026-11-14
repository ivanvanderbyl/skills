// A model of the data layer's core for one resource, with no imports and no I/O.
// It takes events and returns effects; a host runs the effects against a store
// and a server. references/data-layer.md explains each rule and why it exists.
//
// This is a worked example and a test subject, not a sync engine. Titles and
// identifiers are integers so the simulation can generate and compare them.
//
// The central choice: `confirmed` holds only what the server confirmed. A pending
// edit lives in the outbox and is laid over its row when the view is built.

public struct Row: Equatable, Sendable {
    public var id: Int
    public var title: Int  // a token that stands for the text
    public var revision: Int  // the server's revision of this row
    public init(id: Int, title: Int, revision: Int) {
        self.id = id
        self.title = title
        self.revision = revision
    }
}

/// Every mutation sets a value. None is a delta, so applying one twice is harmless.
public enum Op: Equatable, Sendable {
    case create(title: Int)
    case rename(title: Int)
}

public struct Mutation: Equatable, Sendable {
    public var writeID: Int  // made by the host when the user acts; reused on every retry
    public var rowID: Int
    public var op: Op
    public init(writeID: Int, rowID: Int, op: Op) {
        self.writeID = writeID
        self.rowID = rowID
        self.op = op
    }
}

/// One atomic change to the store. The store applies all of it or none of it,
/// and applies writes in the order the core issued them.
public struct StoreWrite: Equatable, Sendable {
    public var upserts: [Row] = []
    public var deletes: [Int] = []
    public var addOutbox: [Mutation] = []
    public var settleOutbox: [Int] = []
    /// Outbox records the server rejected. The store keeps them as failed until the user dismisses them.
    public var failOutbox: [Int] = []
    public var isEmpty: Bool {
        upserts.isEmpty && deletes.isEmpty && addOutbox.isEmpty && settleOutbox.isEmpty && failOutbox.isEmpty
    }
}

/// The server's answer to one envelope: the row as it now stands, and each write's outcome.
public struct SendResult: Equatable, Sendable {
    public var row: Row?  // nil: the row does not exist on the server
    public var applied: [Int]
    public var rejected: [Int]
    public init(row: Row?, applied: [Int], rejected: [Int]) {
        self.row = row
        self.applied = applied
        self.rejected = rejected
    }
}

public enum Event: Sendable {
    /// What the store held when the session started: rows, unsent writes and rejected writes.
    case loaded(rows: [Row], outbox: [Mutation], failed: [Int])
    case intent(Mutation)
    case didCommit(commitID: Int)
    /// Something changed on the server. `rowID` names the row when the source knows it.
    case hint(rowID: Int?)
    case timerFired(timerID: Int)
    case didFetch(requestID: Int, rows: [Row])
    case didFailFetch(requestID: Int)
    case didFetchRow(requestID: Int, row: Row?)
    case didFailFetchRow(requestID: Int)
    case didSend(requestID: Int, result: SendResult)
    case didFailSend(requestID: Int)
}

public enum Effect: Sendable {
    case load
    case commit(commitID: Int, write: StoreWrite)
    case fetch(requestID: Int)
    case fetchRow(requestID: Int, rowID: Int)
    case send(requestID: Int, rowID: Int, writes: [Mutation])
    case startTimer(timerID: Int, after: Int)
}

/// Each flag is one rule of the write path. A control in the simulation turns
/// one off and must then fail; that is the evidence the rule is needed.
public struct Rules: Sendable {
    /// 1. Pending edits are laid over confirmed rows. Off: they are written into the rows.
    public var pendingEditsAreOverlaid = true
    /// 2. The outbox is in the store. Off: it is kept in memory only.
    public var outboxIsDurable = true
    /// 3. The acknowledgement's row and the outbox settlement are one write.
    public var acknowledgementCarriesRow = true
    /// 4. A row is replaced only by a newer server revision.
    public var onlyNewerRevisionsReplace = true
    /// 5. A fetch that was in flight when an acknowledgement landed may not touch that row.
    public var fetchInFlightSkipsAcknowledgedRows = true
    /// 6. A create whose row has appeared in confirmed rows counts as applied.
    public var confirmedCreateCountsAsApplied = true
    /// 7. Only a list answer brings back a row that a list answer removed.
    public var onlyListRestoresRemovedRows = true
    /// 8. A rejected write is kept in the store as failed. Off: the rejection is held in memory only.
    public var rejectionsAreDurable = true
    public var pollEvery = 25
    public var retryAfter = 4
    public init() {}
}

public struct ViewRow: Equatable, Sendable {
    public var id: Int
    public var title: Int
    public var confirmedRevision: Int
    public var pending: Bool
}

public struct DataCore {
    enum Stage: Equatable {
        case local(commitID: Int)  // shown, not yet durable
        case queued  // durable, waiting to be sent
        case sending(requestID: Int)
    }
    struct Pending {
        var mutation: Mutation
        var stage: Stage
        /// A create whose row has shown up in confirmed rows was applied by the
        /// server, even if its acknowledgement never arrived.
        var seenConfirmed = false
    }

    public private(set) var loaded = false
    /// Write IDs the server rejected and the user has not dismissed.
    public private(set) var failed: [Int] = []
    var confirmed: [Int: Row] = [:]
    var pending: [Pending] = []
    var nextID = 1
    var fetchInFlight: Int?
    var fetchDirty = false
    var fresh: Set<Int> = []
    var rowFetchInFlight: [Int: Int] = [:]  // rowID -> requestID
    var rowFresh: Set<Int> = []
    var rowDirty: Set<Int> = []
    /// Rows a list answer removed. Kept in memory only: an answer cannot outlive the process.
    var removedByList: Set<Int> = []
    var sendInFlight: [Int: Int] = [:]  // rowID -> requestID
    var retryTimers: [Int: Int] = [:]  // timerID -> rowID
    var pollTimer: Int?
    var fetchRetryTimer: Int?
    let rules: Rules

    public init(rules: Rules = Rules()) { self.rules = rules }

    public var pendingMutations: [Mutation] { pending.map(\.mutation) }

    public mutating func start() -> [Effect] { [.load] }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case let .loaded(rows, outbox, storedFailures):
            failed = storedFailures
            confirmed = [:]
            for row in rows { confirmed[row.id] = row }
            pending = outbox.map { Pending(mutation: $0, stage: .queued) }
            noteConfirmedCreates()
            loaded = true
            var effects = refresh() + schedulePoll()
            for rowID in Set(pending.map(\.mutation.rowID)).sorted() { effects += trySend(rowID) }
            return effects

        case let .intent(mutation):
            guard loaded else { return [] }
            if !rules.pendingEditsAreOverlaid { writeInPlace(mutation) }
            guard rules.outboxIsDurable else {
                pending.append(Pending(mutation: mutation, stage: .queued))
                return trySend(mutation.rowID)
            }
            // The edit is visible from here. The first write holds the outbox record only.
            let commitID = take()
            pending.append(Pending(mutation: mutation, stage: .local(commitID: commitID)))
            var write = StoreWrite(addOutbox: [mutation])
            if !rules.pendingEditsAreOverlaid, let row = confirmed[mutation.rowID] { write.upserts = [row] }
            return [.commit(commitID: commitID, write: write)]

        case let .didCommit(commitID):
            // Only a durable write may be sent.
            var rows: [Int] = []
            for index in pending.indices where pending[index].stage == .local(commitID: commitID) {
                pending[index].stage = .queued
                rows.append(pending[index].mutation.rowID)
            }
            return rows.flatMap { trySend($0) }

        case let .hint(rowID):
            guard loaded else { return [] }
            // A known row is fetched on its own; anything else refreshes the list.
            guard let rowID, confirmed[rowID] != nil else { return refresh() }
            guard rowFetchInFlight[rowID] == nil else {
                rowDirty.insert(rowID)  // a hint during a fetch causes one more look
                return []
            }
            let requestID = take()
            rowFetchInFlight[rowID] = requestID
            rowFresh.remove(rowID)
            rowDirty.remove(rowID)
            return [.fetchRow(requestID: requestID, rowID: rowID)]

        case let .didFetchRow(requestID, row):
            guard let rowID = rowFetchInFlight.first(where: { $0.value == requestID })?.key else { return [] }
            rowFetchInFlight[rowID] = nil
            let again = rowDirty.remove(rowID) != nil
            if rules.fetchInFlightSkipsAcknowledgedRows, rowFresh.contains(rowID) { return refresh() }
            // A missing row is left to the list fetch, which decides removals.
            guard let row, let current = confirmed[rowID] else { return refresh() }
            let replace = rules.onlyNewerRevisionsReplace ? row.revision > current.revision : row != current
            return (replace ? commit(StoreWrite(upserts: [row])) : []) + (again ? refresh() : [])

        case let .didFailFetchRow(requestID):
            guard let rowID = rowFetchInFlight.first(where: { $0.value == requestID })?.key else { return [] }
            rowFetchInFlight[rowID] = nil
            return refresh()

        case let .timerFired(timerID):
            if let rowID = retryTimers.removeValue(forKey: timerID) { return trySend(rowID) }
            if timerID == fetchRetryTimer {
                fetchRetryTimer = nil
                return refresh()
            }
            if timerID == pollTimer { return schedulePoll() + refresh() }
            return []

        case let .didFetch(requestID, rows):
            guard requestID == fetchInFlight else { return [] }
            fetchInFlight = nil
            var write = StoreWrite()
            var seen: Set<Int> = []
            for row in rows {
                seen.insert(row.id)
                if rules.fetchInFlightSkipsAcknowledgedRows, fresh.contains(row.id) { continue }
                if let current = confirmed[row.id] {
                    let replace = rules.onlyNewerRevisionsReplace ? row.revision > current.revision : row != current
                    if replace { write.upserts.append(row) }
                } else {
                    write.upserts.append(row)
                }
            }
            for id in confirmed.keys.sorted() where !seen.contains(id) {
                if rules.fetchInFlightSkipsAcknowledgedRows, fresh.contains(id) { continue }
                write.deletes.append(id)
            }
            var effects = commit(write)
            if fetchDirty { effects += refresh() }
            return effects

        case let .didFailFetch(requestID):
            guard requestID == fetchInFlight else { return [] }
            fetchInFlight = nil
            let timer = take()
            fetchRetryTimer = timer
            return [.startTimer(timerID: timer, after: rules.retryAfter)]

        case let .didSend(requestID, result):
            guard let rowID = sendInFlight.first(where: { $0.value == requestID })?.key else { return [] }
            sendInFlight[rowID] = nil
            let batch = pending.filter { $0.stage == .sending(requestID: requestID) }.map(\.mutation.writeID)
            pending.removeAll { $0.stage == .sending(requestID: requestID) }
            failed += result.rejected
            // One write settles the envelope and stores the server's row.
            var write = StoreWrite()
            if rules.outboxIsDurable {
                if rules.rejectionsAreDurable {
                    write.failOutbox = batch.filter { result.rejected.contains($0) }
                    write.settleOutbox = batch.filter { !result.rejected.contains($0) }
                } else {
                    write.settleOutbox = batch
                }
            }
            var askForList = false
            if rules.acknowledgementCarriesRow {
                if let row = result.row {
                    let current = confirmed[row.id]
                    // Written in place, a rejected value has to be undone by force.
                    let undo = !rules.pendingEditsAreOverlaid && !result.rejected.isEmpty
                    // An answer for a row the list removed does not bring it back; the list decides.
                    let removed = rules.onlyListRestoresRemovedRows && current == nil && removedByList.contains(row.id)
                    askForList = removed
                    if !removed, current == nil || !rules.onlyNewerRevisionsReplace || undo || row.revision > current!.revision {
                        write.upserts = [row]
                    }
                } else if confirmed[rowID] != nil {
                    write.deletes = [rowID]
                }
            }
            if fetchInFlight != nil {
                fresh.insert(rowID)
                fetchDirty = true
            }
            if rowFetchInFlight[rowID] != nil { rowFresh.insert(rowID) }
            var effects = commit(write)
            if !rules.acknowledgementCarriesRow || askForList { effects += refresh() }
            return effects + trySend(rowID)

        case let .didFailSend(requestID):
            guard let rowID = sendInFlight.first(where: { $0.value == requestID })?.key else { return [] }
            sendInFlight[rowID] = nil
            for index in pending.indices where pending[index].stage == .sending(requestID: requestID) {
                pending[index].stage = .queued
            }
            let timer = take()
            retryTimers[timer] = rowID
            return [.startTimer(timerID: timer, after: rules.retryAfter)]
        }
    }

    /// Confirmed rows with pending edits laid over them.
    public func view() -> [ViewRow] {
        var rows: [Int: ViewRow] = [:]
        for row in confirmed.values {
            rows[row.id] = ViewRow(id: row.id, title: row.title, confirmedRevision: row.revision, pending: false)
        }
        for item in pending {
            let id = item.mutation.rowID
            guard rules.pendingEditsAreOverlaid else {
                rows[id]?.pending = true
                continue
            }
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

    /// Memory is changed when the write is issued; the store follows in order.
    mutating func commit(_ write: StoreWrite) -> [Effect] {
        guard !write.isEmpty else { return [] }
        for row in write.upserts {
            confirmed[row.id] = row
            removedByList.remove(row.id)
        }
        noteConfirmedCreates()
        for id in write.deletes where confirmed[id] != nil {
            removedByList.insert(id)
            confirmed[id] = nil
        }
        return [.commit(commitID: take(), write: write)]
    }

    mutating func noteConfirmedCreates() {
        guard rules.pendingEditsAreOverlaid, rules.confirmedCreateCountsAsApplied else { return }
        for index in pending.indices {
            if case .create = pending[index].mutation.op, confirmed[pending[index].mutation.rowID] != nil {
                pending[index].seenConfirmed = true
            }
        }
    }

    mutating func writeInPlace(_ mutation: Mutation) {
        switch mutation.op {
        case let .create(title):
            if confirmed[mutation.rowID] == nil {
                confirmed[mutation.rowID] = Row(id: mutation.rowID, title: title, revision: 0)
            }
        case let .rename(title):
            confirmed[mutation.rowID]?.title = title
        }
    }

    /// One envelope per row at a time, holding its durable writes in order.
    mutating func trySend(_ rowID: Int) -> [Effect] {
        guard sendInFlight[rowID] == nil else { return [] }
        var writes: [Mutation] = []
        var indices: [Int] = []
        for index in pending.indices where pending[index].mutation.rowID == rowID {
            guard pending[index].stage == .queued else { break }
            writes.append(pending[index].mutation)
            indices.append(index)
        }
        guard !writes.isEmpty else { return [] }
        let requestID = take()
        for index in indices { pending[index].stage = .sending(requestID: requestID) }
        sendInFlight[rowID] = requestID
        return [.send(requestID: requestID, rowID: rowID, writes: writes)]
    }

    /// One list fetch at a time. A request during it causes exactly one more.
    mutating func refresh() -> [Effect] {
        if fetchInFlight != nil {
            fetchDirty = true
            return []
        }
        let requestID = take()
        fetchInFlight = requestID
        fetchDirty = false
        fresh = []
        return [.fetch(requestID: requestID)]
    }

    mutating func schedulePoll() -> [Effect] {
        let timer = take()
        pollTimer = timer
        return [.startTimer(timerID: timer, after: rules.pollEvery)]
    }

    mutating func take() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}
