# Project evidence and continuation

Use this workflow for each applicable Reflex design, implementation, migration or
parity run. Store choices, observations and unfinished work in the project so a
later agent can continue without the chat history. Keep app-specific records out
of the installed skill and global agent memory.

## Establish one project record

Inspect existing plans, architecture decisions, validation documents, issue links
and dirty files before creating state. Use `.reflex/` as the default index. Reuse
existing canonical documents through its manifest; do not maintain a second
backlog or copy an existing evidence archive into it. For a small task, a short
status entry and one run record are sufficient.

```text
.reflex/
  manifest.json             state schema version and canonical document paths
  status.md                 current work, target verification, blockers, next action
  decisions.md              material choices, reasons and supporting evidence
  runs/<UTC-run-id>.md       one record per invocation, including interrupted runs
  evidence/<UTC-run-id>/     bounded receipts or links to existing artifacts
```

Paths in the manifest are relative to the selected repository root. Use the
bundled helper with an absolute skill path and an explicit project root:

```sh
python3 <skill>/scripts/reflex_state.py init --repo <project-root>
python3 <skill>/scripts/reflex_state.py resume --repo <project-root>
python3 <skill>/scripts/reflex_state.py start --repo <project-root>
```

To adopt existing documents, use `init --status-doc docs/port-status.md
--decisions-doc docs/architecture-decisions.md`. Use `--state-dir` consistently
when the project already has another state location. The helper creates missing
files, preserves existing content and rejects unknown manifest versions. It
locates records and captures starting Git context; it does not validate test
claims, select work, infer approval or migrate an unknown state schema. Review a
partial/legacy layout and map or migrate it explicitly without erasing history.

Keep the manifest and small text records in version control with the change they
describe. Link existing project/CI artifacts instead of duplicating them. Retain
only redacted, synthetic or otherwise appropriate evidence; omit credentials,
customer payloads and local secrets. Put large video, traces and binaries in the
project's artifact store, with a durable locator, checksum and retention limits.

For separate Apple/Android repositories, select one coordination record and
record both repository URLs, revisions and consumer artifact versions. Keep a
small pointer in the other repository's existing project guidance. A local path
alone does not let another checkout find the evidence. Preserve the root
`Package.swift` and the distribution boundaries already chosen by the project.

## Resume before selecting work

1. Read the manifest, canonical status and newest run's `Not done` and `Next
   action`. Read the decisions and evidence relevant to the requested work.
   Do not load every historical run or re-derive every accepted choice.
2. Inspect the current branch, source revision, dirty paths, generated artifacts
   and available tools. Reconcile them with the record. Continue explained,
   authorized unfinished work; preserve unexplained edits and note their owner
   as unknown. A run left `in_progress` is an interruption to investigate, not
   evidence of completion or failure.
3. Check for newer coordination records on the project's configured base branch
   when available. If the checkout predates relevant records, bring those records
   into the working branch through the normal branch workflow before relying on
   their state. Preserve dirty work. If remote access is unavailable, record the
   freshness limit and continue independent work with the local evidence.
4. Reconcile contradictions. Read the actual receipt before trusting a green
   status row. Zero discovered tests, a skipped target or source compilation do
   not establish an executed Android journey. Mark unsupported claims unverified
   or stale with a reason; preserve the original receipt and correction history.
5. Choose the next increment within the current user request and explain why it
   follows from the inherited work. Repair a confirmed blocking failure before
   expanding dependent scope. Honor changed user requirements and record which
   earlier decision they supersede. Do not impose a one-action limit on a larger
   authorized task.
6. Create a unique run record before changes. Fill its inherited work and choice;
   keep its status `in_progress` until the handoff is written. Checkpoint the
   record after material decisions, verification outcomes and partial progress,
   so an interrupted session leaves a useful continuation point.

Scope evidence freshness to its inputs. Record the tested revision and any
relevant uncommitted diff or input/artifact hashes, generator/runtime versions,
target and test selection. Recheck affected boundaries when those inputs change.
A new documentation commit does not invalidate every native test, and an
unchanged HEAD does not establish freshness when source files are dirty. Label
carried-forward results with their original scope and source identity.

## Record why a choice was made

Add a decision entry when a choice affects ownership, public API, persistence,
sync policy, build/distribution or verification. Small routine edits can use the
run record without a separate decision. Give each material decision a stable ID
and include:

- Date, scope and status: proposed, accepted, rejected or superseded.
- The decision, alternatives considered and concrete reason for choosing it.
- Authority: the user's instruction, source/code location, vendor source and
  access date, or observed experiment with its source/target and evidence link.
- Consequences, unresolved assumptions and the conditions that warrant revisiting
  it. Distinguish documented support from behavior actually tested in this app.
- A superseding decision ID when the choice changes. Retain the earlier rationale.

For example, record why SwiftJava was chosen for in-process calls, which exported
type graph was proven, and which async/ownership paths remain unverified. Record
the separate service/storage formats without treating them as native-call
contracts. Preserve accepted choices when a later run merely lacks the tools to
reproduce their evidence. Do not turn missing access into a new architecture.

## Keep current work and evidence distinct

Use the canonical status document as the current index. Track meaningful feature
or work-item IDs, implementation status, verification per required target,
evidence links, limitations, dependencies and the next executable action. An
existing project backlog may own this table; map it in the manifest instead of
creating a competing tracker.

Separate these facts when relevant:

| Dimension | Example states |
| --- | --- |
| Implementation | planned, in progress, implemented, blocked |
| Verification by target | not run, passed, failed, blocked, stale |
| Delivery | local diff, committed, pushed, PR open, merged, released |

Mark a feature verified only for targets and acceptance criteria with evidence.
Keep iOS and Android results separate. Track Swift unit, Kotlin host-unit,
installed SwiftJava/JNI, real store/migration, shared e2e mobile and visual/motion
checks where the feature requires them. A blocker explains missing evidence; it
does not convert it into a pass. A design-only run produces decisions and a plan,
with runtime checks still `not run`.

Each verification receipt should make the claim reproducible:

| Field | Record |
| --- | --- |
| Claim and scope | Work/decision ID, behavior and acceptance condition |
| Source and inputs | Repository revision, relevant dirty/input hashes, artifact/fixture identity and pinned toolchain/runtime |
| Target | Host OS, simulator/emulator/device, ABI/API and configuration as applicable |
| Execution | Time, exact command or procedure, test filter/discovery and expected outcome |
| Observation | Actual result, executed/failed/skipped counts or equivalent, exit status and limits |
| Artifact | Existing log/report/screenshot/video locator, checksum where useful and access/retention limits |

For failures, retain the symptom, smallest reproduction, cause when established,
repair and bounded recheck. Record a hypothesis as a hypothesis. Keep failed
attempts and untested targets visible when a later check passes. For external
documentation, record the supported version or access date separately from the
app's observed runtime result. Do not present missing or expired artifacts as
durable proof; retain the claim's scope and rerun the affected check when needed.

## Handoff after each run

Update the run record and canonical status before yielding:

- State what was inherited, chosen and changed, with decision/work IDs and paths.
- List each relevant check as passed, failed, blocked or not run, with receipts.
  Record a no-change audit and its evidence without inventing a code change.
- Carry forward every unfinished part of the selected scope, unresolved failure
  and unrun required check. Give the next action a command or concrete procedure,
  prerequisite, target and expected acceptance result. Avoid a vague `continue`.
- Record actual blockers and any human decision as a complete question with its
  impact. Reuse existing authorization and continue independent work.
- Link changed files and actual commit/PR/CI/release state when available. Include
  the evidence records with the code handoff under the project's existing Git
  workflow. Do not add publication or approval requirements through this file.

Set the run outcome to `complete`, `partial`, `blocked` or `no-change` accurately.
Run completion means its record is closed, not that the whole application is
complete. Keep prior run records; correct a historical claim with a dated
addendum and a linked newer result rather than rewriting the original outcome.
Keep status summaries short and link detail to the owning run or existing plan.

Use one coordinator to update shared status and decisions. Parallel workers
write distinct assigned receipts/run files or isolated worktrees; the coordinator
reconciles them. The helper does not lock shared documents. Check for intervening
changes before writing and merge their entries instead of replacing the files.

In the final reply, state the outcome, verification limits, unfinished work and
next action in plain language. Link the run record for detail. A path or internal
ID alone does not tell the user what remains.
