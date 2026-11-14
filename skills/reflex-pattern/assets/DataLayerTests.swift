// Tests for the data layer model. They import a module named `DataLayerModel`;
// change the import to the module that holds DataLayerCore.swift and
// WritePathSimulation.swift. Swift 6 toolchain, Swift Testing.
//
// Two kinds of test, and a project's own core needs both:
// - "Write path" drives the core by hand through one sequence per rule. Each
//   reads as the example of that rule.
// - "Write path simulation" runs seeded worlds with faults. All rules together
//   must pass, and each rule's control must fail.

import Testing

@testable import DataLayerModel

extension [Effect] {
    fileprivate var commits: [StoreWrite] {
        compactMap { if case let .commit(_, write) = $0 { write } else { nil } }
    }
    fileprivate var commitIDs: [Int] {
        compactMap { if case let .commit(id, _) = $0 { id } else { nil } }
    }
    fileprivate var fetchID: Int? {
        compactMap { if case let .fetch(id) = $0 { id } else { nil } }.first
    }
    fileprivate var sends: [(requestID: Int, writes: [Mutation])] {
        compactMap { if case let .send(id, _, writes) = $0 { (id, writes) } else { nil } }
    }
}

/// A started core, the request ID of its first list fetch, and whatever it sent at once.
private func started(
    rows: [Row], outbox: [Mutation] = [], failed: [Int] = []
) -> (core: DataCore, firstFetch: Int, effects: [Effect]) {
    var core = DataCore()
    _ = core.start()
    let effects = core.handle(.loaded(rows: rows, outbox: outbox, failed: failed))
    return (core, effects.fetchID!, effects)
}

/// Takes an edit as far as its envelope being in flight. Returns the send's request ID.
private func submit(_ mutation: Mutation, to core: inout DataCore) -> Int {
    let accepted = core.handle(.intent(mutation))
    return core.handle(.didCommit(commitID: accepted.commitIDs[0])).sends[0].requestID
}

private let row = Row(id: 1, title: 10, revision: 1)
private let rename = Mutation(writeID: 100, rowID: 1, op: .rename(title: 11))
private let create = Mutation(writeID: 200, rowID: 2, op: .create(title: 20))

@Suite("Write path")
struct WritePathTests {
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

    @Test("A list answer that predates the edit does not revert it")
    func staleListKeepsTheEdit() {
        var (core, firstFetch, _) = started(rows: [row])
        _ = submit(rename, to: &core)

        let answered = core.handle(.didFetch(requestID: firstFetch, rows: [row]))

        #expect(answered.commits.isEmpty)
        #expect(core.view() == [ViewRow(id: 1, title: 11, confirmedRevision: 1, pending: true)])
    }

    @Test("The acknowledgement settles the outbox and stores the server's row in one write")
    func acknowledgementIsOneWrite() {
        var (core, firstFetch, _) = started(rows: [row])
        let send = submit(rename, to: &core)
        _ = core.handle(.didFetch(requestID: firstFetch, rows: [row]))
        let confirmed = Row(id: 1, title: 11, revision: 2)

        let settled = core.handle(
            .didSend(requestID: send, result: SendResult(row: confirmed, applied: [100], rejected: [])))

        #expect(settled.commits == [StoreWrite(upserts: [confirmed], settleOutbox: [100])])
        #expect(core.view() == [ViewRow(id: 1, title: 11, confirmedRevision: 2, pending: false)])
    }

    @Test("An older revision does not replace a newer row")
    func olderRevisionIsIgnored() {
        var (core, firstFetch, _) = started(rows: [Row(id: 1, title: 10, revision: 5)])

        let answered = core.handle(.didFetch(requestID: firstFetch, rows: [Row(id: 1, title: 9, revision: 4)]))

        #expect(answered.commits.isEmpty)
        #expect(core.view().map(\.title) == [10])
    }

    @Test("A list fetch in flight when an acknowledgement lands may not touch that row")
    func fetchInFlightSkipsAcknowledgedRow() {
        var (core, firstFetch, _) = started(rows: [])
        let send = submit(create, to: &core)
        _ = core.handle(
            .didSend(
                requestID: send,
                result: SendResult(row: Row(id: 2, title: 20, revision: 5), applied: [200], rejected: [])))

        // The list was read before the server applied the create, so it lacks the row.
        let stale = core.handle(.didFetch(requestID: firstFetch, rows: []))

        #expect(stale.commits.isEmpty)
        #expect(stale.fetchID != nil, "the core asks again instead of trusting the stale list")
        #expect(core.view() == [ViewRow(id: 2, title: 20, confirmedRevision: 5, pending: false)])
    }

    @Test("A create a list already confirmed is not shown again after someone deletes its row")
    func confirmedCreateCountsAsApplied() {
        var (core, firstFetch, _) = started(rows: [])
        let send = submit(create, to: &core)
        _ = core.handle(.didFailSend(requestID: send))  // the acknowledgement is lost
        _ = core.handle(.didFetch(requestID: firstFetch, rows: [Row(id: 2, title: 20, revision: 3)]))
        #expect(core.view() == [ViewRow(id: 2, title: 20, confirmedRevision: 3, pending: true)])

        let again = core.handle(.hint(rowID: nil))
        _ = core.handle(.didFetch(requestID: again.fetchID!, rows: []))  // someone deleted it

        #expect(core.view().isEmpty)
    }

    @Test("An acknowledgement does not bring back a row the list removed")
    func onlyListRestoresRemovedRow() {
        var (core, firstFetch, _) = started(rows: [row])
        _ = core.handle(.didFetch(requestID: firstFetch, rows: [row]))
        let send = submit(rename, to: &core)
        let again = core.handle(.hint(rowID: nil))
        _ = core.handle(.didFetch(requestID: again.fetchID!, rows: []))  // deleted after the rename applied
        #expect(core.view().isEmpty)

        // The answer was written before the deletion and arrives after the list.
        let late = core.handle(
            .didSend(
                requestID: send,
                result: SendResult(row: Row(id: 1, title: 11, revision: 2), applied: [100], rejected: [])))

        #expect(late.commits == [StoreWrite(settleOutbox: [100])])
        #expect(late.fetchID != nil, "the list decides whether the row exists")
        #expect(core.view().isEmpty)
    }

    @Test("A rejected write moves to the failed list in the write that settles its envelope")
    func rejectionIsDurable() {
        var (core, firstFetch, _) = started(rows: [row])
        _ = core.handle(.didFetch(requestID: firstFetch, rows: [row]))
        let send = submit(rename, to: &core)

        let rejected = core.handle(
            .didSend(requestID: send, result: SendResult(row: row, applied: [], rejected: [100])))

        #expect(rejected.commits == [StoreWrite(failOutbox: [100])])
        #expect(core.failed == [100])
        #expect(core.view() == [ViewRow(id: 1, title: 10, confirmedRevision: 1, pending: false)])

        let (restarted, _, _) = started(rows: [row], failed: [100])
        #expect(restarted.failed == [100])
    }

    @Test("After a restart the outbox is shown and sent again under the same write ID")
    func outboxSurvivesRestart() {
        let (core, _, effects) = started(rows: [row], outbox: [rename])

        #expect(core.view() == [ViewRow(id: 1, title: 11, confirmedRevision: 1, pending: true)])
        #expect(effects.sends.map(\.writes) == [[rename]])
    }
}

/// One rule turned off, and seeds on which the simulation then fails.
struct Control: CustomTestStringConvertible, Sendable {
    let testDescription: String
    let seeds: ClosedRange<UInt64>
    let rules: Rules

    init(_ name: String, seeds: ClosedRange<UInt64>, _ turnOff: (inout Rules) -> Void) {
        testDescription = name
        self.seeds = seeds
        var rules = Rules()
        turnOff(&rules)
        self.rules = rules
    }
}

@Suite("Write path simulation")
struct WritePathSimulationTests {
    @Test("All rules hold under app kills, lost requests and other people's edits")
    func allRulesHold() {
        var totals = Outcome()
        for seed in UInt64(1)...300 {
            let outcome = simulate(seed: seed)
            #expect(outcome.passed, "seed \(seed)")
            totals.intents += outcome.intents
            totals.applied += outcome.applied
            totals.rejected += outcome.rejected
            totals.kills += outcome.kills
        }
        // The run exercised what the title says it did.
        #expect(totals.applied > 0 && totals.rejected > 0 && totals.kills > 0)
    }

    // The two single seeds were found by scanning 20,000 seeds with `failingSeeds`.
    // Those rules fail too rarely to catch with a small range. Scan again after
    // changing the world or the faults: every pinned seed moves.
    static let controls = [
        Control("1. edits written into rows", seeds: 1...40) { $0.pendingEditsAreOverlaid = false },
        Control("2. outbox kept in memory", seeds: 1...40) { $0.outboxIsDurable = false },
        Control("3. acknowledgement without the row", seeds: 1...40) { $0.acknowledgementCarriesRow = false },
        Control("4. rows replaced without comparing revisions", seeds: 1...100) { $0.onlyNewerRevisionsReplace = false },
        Control("5. a fetch in flight may touch an acknowledged row", seeds: 1...40) {
            $0.fetchInFlightSkipsAcknowledgedRows = false
        },
        Control("6. a confirmed create is shown until its acknowledgement", seeds: 4107...4107) {
            $0.confirmedCreateCountsAsApplied = false
        },
        Control("7. an acknowledgement may bring back a removed row", seeds: 3347...3347) {
            $0.onlyListRestoresRemovedRows = false
        },
        Control("8. rejections held in memory", seeds: 1...40) { $0.rejectionsAreDurable = false },
    ]

    @Test("Each rule is needed: with it off the simulation fails, and the same seeds pass with it on", arguments: controls)
    func ruleIsNeeded(_ control: Control) {
        #expect(!failingSeeds(in: control.seeds, rules: control.rules).isEmpty)
        #expect(failingSeeds(in: control.seeds).isEmpty)
    }
}
