# Project state and continuation

Every Reflex run starts and ends with `scripts/reflex_state.py`. It keeps the project's state in the project, so a later run continues from the files with no chat history. Run it; do not read it. Call it by its absolute path in this skill's directory and pass the project root with `--repo`. Every command prints JSON and supports `--help`.

Contents: the run loop, the state directory, product context, targets and work items, receipts, decisions, handoff, adopting existing records, several repositories, limits of the helper.

## The run loop

1. Run `next`. It changes nothing. It reports the phase, any open or interrupted run, each required check that failed, went stale or never ran, the last handoff, and one step in `do`.
2. Read the files listed in `read`: the product context, the status notes, the last closed run and the decisions. Read older runs only when one is cited.
3. Reconcile the report with the branch, the dirty paths in `source_now` and the tools on this machine. Fetch the base branch when a newer state directory may exist there, and bring it in through the project's normal branch workflow. Keep edits you cannot explain and note that their owner is unknown.
4. Run `start`. It opens a run record and an evidence directory and refuses while another run is open. A run that another session left open is an interruption to investigate: read its record, compare its claims with the tree, then run `start --interrupted <run-id>`.
5. Do the step in `do` unless the user's request says otherwise. A user request outranks `do`; record the request as an item or a decision first, so the next run sees it. Repair a failed check before work that depends on it.
6. After each executed check, save its raw output in the run's evidence directory and record it with `receipt`. Write reasoning, hypotheses and failed attempts in the run record as you go, so an interrupted session leaves them behind.
7. Write the run record's `Did`, `Not done` and `Next action` sections, then run `finish --outcome complete|partial|blocked|no-change`.

Exit code 2 means the helper refused the request until the step named in its message is taken. Take that step; do not edit `ledger.json` or the generated block of `status.md` by hand to get past it. Exit code 1 means invalid input or unreadable state.

`next` reports one of these phases:

- `uninitialized`: no state exists. Inspect existing plans and records, then run `init`.
- `legacy`: state from schema 1. Run `migrate`. It adds the ledger and product context and keeps every record; re-enter tracked work with `item`, and record a receipt only after rerunning a check.
- `setup`: no app target is declared.
- `inventory`: no work item exists.
- `slice`: no item has passed every required check on every target. One item is active until one does.
- `expand`: a vertical slice is proven; checks or planned items remain.
- `maintain`: every active item passes against the current sources.

## The state directory

```text
.reflex/
  manifest.json           schema version, document paths, targets and their source globs
  product.md              the facts every target must agree on; hand-written
  ledger.json             work items and receipts; written only by the helper
  status.md               a generated matrix plus hand-written notes
  decisions.md            append-only decisions with IDs
  runs/<UTC-run-id>.md    one record per run, including interrupted runs
  evidence/<UTC-run-id>/  raw output of that run's checks
```

Commit the directory with the change it describes. Separate sessions and sandboxes share only git, so uncommitted state is lost to the next run. Keep credentials, customer payloads and local secrets out of it. Store large video, traces and binaries in the project's artifact store and pass their durable URL to `receipt --evidence`.

## Product context

`product.md` is what keeps the surfaces one product. Fill it before the first item and keep it under about 100 lines. It records what the app is for, each target and whether it is required, the product's vocabulary, where user-visible strings, accessibility identifiers and design tokens are defined and how each target reads them, and the differences between targets that the user accepted. Give each of those one source that every target consumes or generates from. A value copied by hand into two targets will drift.

Build it from the code and the user's words, with the file or the quote each fact came from. Delete the `reflex:incomplete` line once it is true; `next` reports `product_context_incomplete` until then. The helper never rewrites this file.

## Targets and work items

Declare each surface once with the source globs that belong to it:

```sh
reflex_state.py target --repo <root> --name core --inputs 'Sources/AppCore/**' 'Package.swift'
reflex_state.py target --repo <root> --name ios --inputs 'platforms/apple/**'
reflex_state.py target --repo <root> --name android --inputs 'platforms/android/**' 'Sources/AppBridge/**'
```

Add `web` or any other target the same way. Include the façade, generated bindings' configuration and the shared journey tests in the target they affect. Globs decide staleness: a glob that is too narrow lets a result outlive the change that broke it.

A work item is one feature or journey with one acceptance result that holds on every target:

```sh
reflex_state.py item --repo <root> --title "Rename a record" --acceptance "The new title shows after relaunch" --ui-id record.title --ui-id record.save --state active
```

- Items get IDs (`F-001`) that never change. Cite them in run records, decisions and commits.
- Every item requires `core:unit` and one `<target>:journey` per app target. Add stricter checks with `--require`, such as `android:binding` for an installed SwiftJava call, `ios:store` for a real migration, or `android:motion`. The kinds are unit, integration, binding, store, journey, visual and motion.
- `--ui-id` names an identifier every UI target must use. Define it once, in the core or in a file every target reads. `next` reports a target when the identifier appears in neither that target's sources nor the core's.
- Adding a target makes every item require it. Dropping an item, or waiving one check with `waive`, needs the ID of a decision the user or a cited source settled. An assumption does not qualify.

## Receipts

A receipt is one executed check for one item on one target:

```sh
reflex_state.py receipt --repo <root> --item F-001 --check android:journey --result passed --command "pnpm e2e test --target android" --evidence .reflex/evidence/<run-id>/android-journey.txt --executed 4 --environment "Pixel 9 API 36 emulator, arm64-v8a, Swift 6.3 Android SDK"
```

- A pass needs the command, saved evidence and at least one executed test. Zero discovered tests, a skipped target and a successful compile are not passes; record `blocked` with a `--note`.
- `failed` and `blocked` need a `--note` with the symptom and the smallest reproduction, or what blocks the check. A blocker explains missing evidence. It never becomes a pass.
- Each receipt stores a digest of the target's sources, the core's sources and the item's acceptance text. When any of them change, the helper reports the pass as `stale` and the check must run again. A change to the core therefore reopens every target; that is the mechanism that keeps the surfaces consistent. Edited or deleted evidence also makes a pass stale.
- State the limits of a pass in `--note`: simulator or device, debug or release, which data was synthetic. Report states as the helper prints them. `not-run` and `stale` are never "probably fine".
- Receipts are appended and never removed, so an earlier failure stays visible after a later pass.

## Decisions

Record a decision when a choice affects ownership, the public API, persistence, sync policy, build or distribution, verification, or a difference between targets. Routine edits belong in the run record.

```sh
reflex_state.py decide --repo <root> --title "Web reads records but does not edit them" --decision "..." --reason "..." --alternatives "Full editing: rejected because ..." --authority user --authority-ref "<the user's words>" --revisit "A user asks to edit on the web"
```

- Authority is `user` (quote their words), `source` (a file and line), `vendor` (a URL and access date), `experiment` (an evidence path) or `assumption`.
- Use `assumption` for a default chosen without asking. It is recorded as `assumed`, `next` lists it every run, and the final reply must name it. Turn it into an accepted decision with `--confirms D-NNN` and the user's words.
- Change a decision by appending a new one with `--supersedes D-NNN`. Never edit an earlier entry.
- Keep an accepted decision when this run merely lacks the tools to reproduce its evidence. Missing access is a blocker to record, not a reason to choose a new architecture.
- State which behaviour was observed in this app and which is only documented by a vendor.

## Handoff

Before `finish`, the run record must say:

- `Did`: what changed, with item and decision IDs and paths.
- `Not done`: every unfinished part of the selected scope, unresolved failure and required check that did not run.
- `Next action`: a command or procedure, its target and the result that would accept it. Write `None` only when nothing remains.

Choose the outcome honestly. `complete` means this run's scope is closed, not that the app is finished, and the helper refuses it while a check this run recorded still fails. Correct an earlier run by adding a dated addendum to its record, never by rewriting it.

In the final reply, state the outcome, what was verified on which target, what is not done, each assumed decision, and the next action, in plain words. An ID or a path alone does not tell the user what remains.

## Adopting existing records

Before `init`, look for existing plans, architecture decisions and validation documents. Adopt them with `init --status-doc docs/port-status.md --decisions-doc docs/architecture-decisions.md` so the project keeps one of each. The helper adds its generated block to an adopted status document and leaves the rest alone. Entries in an adopted decisions document count only when they use the `## D-NNN · Title` heading that `decide` writes. Pass `--state-dir` on every command when the project keeps state somewhere other than `.reflex`.

## Several repositories or workers

- When the Apple and Android apps live in separate repositories, keep one state directory in the repository that owns the core. Record the other repository's URL, revision and the consumed artifact version in each receipt's `--environment`, and put a pointer to the state directory in the other repository's guidance file.
- The helper does not lock. One coordinator runs `start`, `receipt` and `finish`. Parallel workers save evidence files and report results to the coordinator.

## Limits of the helper

It records that a check ran and detects when its inputs changed. It does not run checks, judge whether a test asserts the acceptance result, or read the evidence. Read the actual output before recording a pass.
