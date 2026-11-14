// Seeded simulation of the write path: a user who edits, a server that other
// people also change, a store that survives the app being killed, and a network
// that loses requests and acknowledgements. It drives the pure DataCore and
// checks six things, on every step or at the end; see `Outcome`.
//
// To reuse it, replace DataCore with the project's own core and keep the
// faults, the checks and one control per rule. No imports: it runs wherever
// the core's tests run.

struct SplitMix64 {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func chance(_ p: Double) -> Bool { Double(next() >> 11) / Double(UInt64(1) << 53) < p }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
}

struct Faults {
    var sendLostBeforeServer = 0.1
    var ackLost = 0.1
    var fetchFail = 0.1
    var hintDrop = 0.1
    var kill = 0.005
    var serverRejects = 0.03
    /// Chance per step that the device goes offline, and how long it stays so. While offline no
    /// send or fetch reaches the server and no hint arrives. The user keeps editing.
    var goOffline = 0.0
    var offlineSteps = 60
}

struct Outcome {
    var notConverged = false  // once quiet, the store, the view and the server differ, or the outbox is not empty
    var lostWrites = 0  // accepted 3 or more steps before any kill, yet never applied or rejected
    var ownWriteReverted = 0  // the user's edit vanished from the view without being rejected
    var rowWentBackwards = 0  // a row showed an older server revision than before
    var rowCameBack = 0  // a row the view had dropped reappeared
    var rejectionsForgotten = 0  // the server rejected a write and, at the end, the core no longer says so
    var intents = 0
    var applied = 0
    var rejected = 0
    var lostNearKill = 0  // edits made within 2 steps of a kill, before their outbox record was durable: lost by design
    var kills = 0
    var intentsWhileOffline = 0
    var passed: Bool { !failed }
    var failed: Bool {
        notConverged || lostWrites > 0 || ownWriteReverted > 0 || rowWentBackwards > 0 || rowCameBack > 0
            || rejectionsForgotten > 0
    }
}

enum Request {
    case fetch(id: Int, epoch: Int)
    case fetchRow(id: Int, epoch: Int, rowID: Int)
    case send(id: Int, epoch: Int, rowID: Int, writes: [Mutation])
}

enum Delivery {
    case load
    case event(Event)
}

final class World {
    var rng: SplitMix64
    let rules: Rules
    let faults: Faults
    let activeSteps = 400
    let endStep = 650
    var t = 0
    // Server.
    var serverRows: [Int: Row] = [:]
    var clock = 0
    var applied: [Int: Int] = [:]  // writeID -> the row revision it produced
    var rejected: Set<Int> = []
    var dead: Set<Int> = []
    var nextRemoteRow = 10_000
    // Store: survives a kill. Commits apply in the order issued.
    var storeRows: [Int: Row] = [:]
    var storeOutbox: [Mutation] = []
    var storeFailed: [Int] = []
    var commitQueue: [(at: Int, id: Int, write: StoreWrite)] = []
    var lastCommitAt = 0
    // Core: lost on a kill.
    var core: DataCore
    var epoch = 0
    var queue: [(at: Int, seq: Int, epoch: Int, delivery: Delivery)] = []
    var requests: [(at: Int, seq: Int, request: Request)] = []
    var seq = 0
    // User.
    var nextWrite = 1
    var nextToken = 1
    var nextLocalRow = 1_000
    var intents: [Int: (rowID: Int, madeAt: Int)] = [:]
    var rowWrites: [Int: [Int]] = [:]
    var killTimes: [Int] = []
    var offlineUntil = 0
    var isOffline: Bool { t < offlineUntil }
    // What the view has shown since the last start.
    var lastBase: [Int: Int] = [:]
    var shown: Set<Int> = []
    var dropped: Set<Int> = []
    var outcome = Outcome()

    init(seed: UInt64, rules: Rules = Rules(), faults: Faults = Faults()) {
        rng = SplitMix64(s: seed)
        self.rules = rules
        self.faults = faults
        core = DataCore(rules: rules)
        for id in 0..<5 {
            clock += 1
            serverRows[id] = Row(id: id, title: token(), revision: clock)
        }
        run(core.start())
    }

    func token() -> Int {
        defer { nextToken += 1 }
        return nextToken
    }

    func fault(_ p: Double) -> Bool { t < activeSteps + 100 && rng.chance(p) }

    func schedule(_ delivery: Delivery, at: Int, anyEpoch: Bool = false) {
        seq += 1
        queue.append((at, seq, anyEpoch ? -1 : epoch, delivery))
    }

    func run(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .load:
                schedule(.load, at: t + 1)
            case let .commit(id, write):
                let at = max(lastCommitAt, t + rng.int(0...1))
                lastCommitAt = at
                commitQueue.append((at, id, write))
            case let .fetch(id):
                seq += 1
                requests.append((t + rng.int(0...2), seq, .fetch(id: id, epoch: epoch)))
            case let .fetchRow(id, rowID):
                seq += 1
                requests.append((t + rng.int(0...2), seq, .fetchRow(id: id, epoch: epoch, rowID: rowID)))
            case let .send(id, rowID, writes):
                if fault(faults.sendLostBeforeServer) {
                    schedule(.event(.didFailSend(requestID: id)), at: t + rng.int(1...3))
                } else {
                    seq += 1
                    requests.append((t + rng.int(0...2), seq, .send(id: id, epoch: epoch, rowID: rowID, writes: writes)))
                }
            case let .startTimer(id, after):
                schedule(.event(.timerFired(timerID: id)), at: t + after)
            }
        }
    }

    func remoteChanged(_ rowID: Int) {
        clock += 1
        if isOffline { return }
        if !fault(faults.hintDrop) { schedule(.event(.hint(rowID: rowID)), at: t + rng.int(1...3), anyEpoch: true) }
    }

    func respond(_ event: Event, epoch requestEpoch: Int) {
        seq += 1
        queue.append((t + rng.int(1...3), seq, requestEpoch, .event(event)))
    }

    func handle(_ request: Request) {
        if isOffline {
            switch request {
            case let .fetch(id, requestEpoch): respond(.didFailFetch(requestID: id), epoch: requestEpoch)
            case let .fetchRow(id, requestEpoch, _): respond(.didFailFetchRow(requestID: id), epoch: requestEpoch)
            case let .send(id, requestEpoch, _, _): respond(.didFailSend(requestID: id), epoch: requestEpoch)
            }
            return
        }
        switch request {
        case let .fetch(id, requestEpoch):
            if fault(faults.fetchFail) {
                respond(.didFailFetch(requestID: id), epoch: requestEpoch)
            } else {
                let rows = serverRows.values.sorted { $0.id < $1.id }
                respond(.didFetch(requestID: id, rows: rows), epoch: requestEpoch)
            }
        case let .fetchRow(id, requestEpoch, rowID):
            if fault(faults.fetchFail) {
                respond(.didFailFetchRow(requestID: id), epoch: requestEpoch)
            } else {
                respond(.didFetchRow(requestID: id, row: serverRows[rowID]), epoch: requestEpoch)
            }
        case let .send(id, requestEpoch, rowID, writes):
            var appliedIDs: [Int] = []
            var rejectedIDs: [Int] = []
            for write in writes {
                // A write the server has already answered gets the same answer again.
                if applied[write.writeID] != nil {
                    appliedIDs.append(write.writeID)
                    continue
                }
                if rejected.contains(write.writeID) {
                    rejectedIDs.append(write.writeID)
                    continue
                }
                var ok = !fault(faults.serverRejects)
                switch write.op {
                case let .create(title):
                    if ok, serverRows[rowID] == nil, !dead.contains(rowID) {
                        clock += 1
                        serverRows[rowID] = Row(id: rowID, title: title, revision: clock)
                    } else if serverRows[rowID] == nil {
                        ok = false
                        dead.insert(rowID)
                    }
                case let .rename(title):
                    if ok, serverRows[rowID] != nil {
                        clock += 1
                        serverRows[rowID]!.title = title
                        serverRows[rowID]!.revision = clock
                    } else {
                        ok = false
                    }
                }
                if ok {
                    applied[write.writeID] = serverRows[rowID]!.revision
                    appliedIDs.append(write.writeID)
                } else {
                    rejected.insert(write.writeID)
                    rejectedIDs.append(write.writeID)
                }
            }
            if fault(faults.ackLost) {
                respond(.didFailSend(requestID: id), epoch: requestEpoch)
            } else {
                let result = SendResult(row: serverRows[rowID], applied: appliedIDs, rejected: rejectedIDs)
                respond(.didSend(requestID: id, result: result), epoch: requestEpoch)
            }
        }
    }

    func kill() {
        epoch += 1
        core = DataCore(rules: rules)
        commitQueue = []  // writes the store had not applied yet are gone
        lastCommitAt = t
        killTimes.append(t)
        lastBase = [:]
        shown = []
        dropped = []
        outcome.kills += 1
        run(core.start())
    }

    func pick(_ ids: [Int]) -> Int { ids[rng.int(0...(ids.count - 1))] }

    func step() {
        if t < activeSteps {
            if core.loaded, rng.chance(faults.kill) { kill() }
            // Checked only when the fault is on, so runs without it draw the same random numbers.
            if faults.goOffline > 0, !isOffline, rng.chance(faults.goOffline) { offlineUntil = t + faults.offlineSteps }
            // Other people change the server.
            if rng.chance(0.05), !serverRows.isEmpty {
                let id = pick(serverRows.keys.sorted())
                remoteChanged(id)
                serverRows[id]!.title = token()
                serverRows[id]!.revision = clock
            }
            if rng.chance(0.01), !serverRows.isEmpty {
                let id = pick(serverRows.keys.sorted())
                serverRows[id] = nil
                dead.insert(id)
                remoteChanged(id)
            }
            if rng.chance(0.02) {
                remoteChanged(nextRemoteRow)
                serverRows[nextRemoteRow] = Row(id: nextRemoteRow, title: token(), revision: clock)
                nextRemoteRow += 1
            }
            // The user edits what the view shows.
            if core.loaded, rng.chance(0.06) {
                let view = core.view()
                let mutation: Mutation
                if view.isEmpty || rng.chance(0.3) {
                    mutation = Mutation(writeID: nextWrite, rowID: nextLocalRow, op: .create(title: token()))
                    nextLocalRow += 1
                } else {
                    mutation = Mutation(writeID: nextWrite, rowID: pick(view.map(\.id)), op: .rename(title: token()))
                }
                nextWrite += 1
                intents[mutation.writeID] = (mutation.rowID, t)
                if isOffline { outcome.intentsWhileOffline += 1 }
                rowWrites[mutation.rowID, default: []].append(mutation.writeID)
                run(core.handle(.intent(mutation)))
            }
        }

        while let first = commitQueue.first, first.at <= t {
            commitQueue.removeFirst()
            for row in first.write.upserts { storeRows[row.id] = row }
            for id in first.write.deletes { storeRows[id] = nil }
            for mutation in first.write.addOutbox where !storeOutbox.contains(mutation) { storeOutbox.append(mutation) }
            storeOutbox.removeAll { first.write.settleOutbox.contains($0.writeID) }
            storeOutbox.removeAll { first.write.failOutbox.contains($0.writeID) }
            for id in first.write.failOutbox where !storeFailed.contains(id) { storeFailed.append(id) }
            schedule(.event(.didCommit(commitID: first.id)), at: t)
        }

        let due = requests.filter { $0.at <= t }.sorted { $0.seq < $1.seq }
        requests.removeAll { $0.at <= t }
        for item in due { handle(item.request) }

        while let next = queue.filter({ $0.at <= t }).min(by: { $0.seq < $1.seq }) {
            queue.removeAll { $0.seq == next.seq }
            guard next.epoch == epoch || next.epoch == -1 else { continue }
            switch next.delivery {
            case .load:
                let rows = storeRows.values.sorted { $0.id < $1.id }
                run(core.handle(.loaded(rows: rows, outbox: storeOutbox, failed: storeFailed)))
            case let .event(event):
                run(core.handle(event))
            }
        }

        check()
        t += 1
    }

    func check() {
        guard core.loaded else { return }
        var view: [Int: ViewRow] = [:]
        for row in core.view() { view[row.id] = row }
        var pendingByRow: [Int: [Mutation]] = [:]
        for mutation in core.pendingMutations { pendingByRow[mutation.rowID, default: []].append(mutation) }

        for (rowID, writes) in rowWrites {
            if let pending = pendingByRow[rowID] {
                // While an edit is pending, the view shows it.
                if let row = view[rowID] {
                    if case let .rename(title) = pending.last!.op, row.title != title { outcome.ownWriteReverted += 1 }
                } else {
                    let creating = pending.contains { if case .create = $0.op { return true } else { return false } }
                    // A create the server applied and someone then deleted is rightly hidden.
                    let appliedThenRemoved = serverRows[rowID] == nil && writes.contains { applied[$0] != nil }
                    if (creating && !appliedThenRemoved) || serverRows[rowID] != nil { outcome.ownWriteReverted += 1 }
                }
            } else if let newest = writes.compactMap({ applied[$0] }).max() {
                // Once the server has applied an edit, the view never shows an older revision.
                if let row = view[rowID] {
                    if row.confirmedRevision < newest { outcome.ownWriteReverted += 1 }
                } else if serverRows[rowID] != nil {
                    outcome.ownWriteReverted += 1
                }
            }
        }

        for (id, row) in view {
            if let last = lastBase[id], row.confirmedRevision < last {
                outcome.rowWentBackwards += 1
            }
            lastBase[id] = row.confirmedRevision
        }
        for id in shown where view[id] == nil { dropped.insert(id) }
        for id in view.keys where dropped.contains(id) {
            outcome.rowCameBack += 1
            dropped.remove(id)
        }
        shown = Set(view.keys)
    }

    func finish() -> Outcome {
        while t <= endStep { step() }
        outcome.intents = intents.count
        for (writeID, intent) in intents {
            let answered = applied[writeID] != nil || rejected.contains(writeID)
            if applied[writeID] != nil { outcome.applied += 1 }
            if rejected.contains(writeID) { outcome.rejected += 1 }
            if answered { continue }
            if let kill = killTimes.first(where: { $0 > intent.madeAt }), kill - intent.madeAt < 3 {
                outcome.lostNearKill += 1
            } else {
                outcome.lostWrites += 1
            }
        }
        outcome.rejectionsForgotten = rejected.subtracting(core.failed).count
        let viewRows = core.view().map { Row(id: $0.id, title: $0.title, revision: $0.confirmedRevision) }
        let server = serverRows.values.sorted { $0.id < $1.id }
        outcome.notConverged =
            storeRows != serverRows || !storeOutbox.isEmpty || !core.pendingMutations.isEmpty || viewRows != server
        return outcome
    }
}

/// Runs one seed to the end and returns what the checks counted.
func simulate(seed: UInt64, rules: Rules = Rules(), faults: Faults = Faults()) -> Outcome {
    World(seed: seed, rules: rules, faults: faults).finish()
}

/// The seeds in `seeds` on which any check failed. Use it to scan for a control's
/// first failing seed, then pin that seed in a test.
func failingSeeds(in seeds: ClosedRange<UInt64>, rules: Rules = Rules(), faults: Faults = Faults()) -> [UInt64] {
    seeds.filter { simulate(seed: $0, rules: rules, faults: faults).failed }
}
