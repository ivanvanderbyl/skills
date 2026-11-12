---
name: reflex-pattern
description: Builds, migrates or continues native iOS (Swift/SwiftUI) and Android (Kotlin/Compose) apps, and optionally a web app, around one shared Swift core with typed contracts and platform adapters, keeping resumable project state in `.reflex/`. Use for cross-platform app architecture, core extraction, persistence and sync boundaries, shared behaviour tests, visual, motion or input parity across platforms, or any work in a project that has a `.reflex/` directory. Not for a styling change or a platform API task that affects one platform only.
---

# Reflex pattern for Swift, Android and web

Keep portable application decisions in a Swift core. Native Apple and Android hosts, and an optional web host, render its state, dispatch typed actions and execute platform effects through explicit ports. A headless host exercises the same production state/action owner.

Keep UIKit/AppKit or Android Views when the app uses them; SwiftUI and Compose are common adapters, not prerequisites for the core boundary. Do not rewrite a working UI framework solely to adopt this pattern.

[Shopify's Reflex architecture](https://shopify.engineering/reflex) uses native implementations with shared behaviour tests. A shared Swift implementation is a supported architectural choice here, not a requirement of Shopify's pattern. Preserve the project's selected core and UI technologies.

## Check applicability

For an isolated styling change or a platform API task that does not affect cross-platform ownership or testing, continue with the relevant platform guidance. For cross-platform rendering, motion or input parity, use the verification references without requiring an architecture change. Do not introduce a shared core, a web target or a sync system solely because this skill was loaded.

## Start every run from the project state

You have no memory between runs. The project's `.reflex/` directory holds it, and `scripts/reflex_state.py` in this skill's directory reads and writes it. Run the script by its absolute path; do not read it.

1. Run `python3 <skill>/scripts/reflex_state.py next --repo <project-root>` before reading code or choosing work. It prints the phase, any open or interrupted run, each required check that failed, went stale or never ran, and one next step in `do`.
2. Read the files it lists in `read`. `.reflex/product.md` comes first: it names the vocabulary, strings, identifiers, design tokens and accepted differences that every target must share.
3. Run `start` to open a run record before changing anything.
4. Do the step in `do` unless the user's request says otherwise. Record a new request as an item first.
5. Record each executed check with `receipt`, each material choice with `decide`, and close the run with `finish`.

[Project state and continuation](references/evidence-and-resumption.md) has the commands, the phases and the rules for receipts, decisions and handoff. Read it on the first run in a project and whenever the script refuses a command.

Rules the script enforces, so plan for them:

- One work item is active until one item has passed every required check on every target. Prove a vertical slice before widening.
- A pass needs a command, saved output and at least one executed test. A compile, a skipped target or zero discovered tests is not a pass.
- A pass goes stale when the target's sources, the core's sources or the item's acceptance text change. A core change reopens every target.
- Dropping an item or waiving a check on one target needs a decision the user confirmed. A default you chose is recorded as an assumption and must be named in the final reply.

## Keep every surface one product

- One acceptance result per work item, shared by every target. A target that cannot meet it gets a recorded decision, not a quieter test.
- One source for each shared fact: user-visible strings, accessibility identifiers, design tokens, fixtures and journey tests. Targets consume or generate from that source. Record where each lives in `.reflex/product.md`.
- Every façade (Swift API, SwiftJava, web) maps the same core types, so a new core action fails to compile in each façade until it is mapped.
- Report each target's state separately, in the script's words: `passed`, `failed`, `blocked`, `stale`, `not-run` or `waived`. Never summarize a mixed row as done.

## Choose explicit boundaries

Inspect public consumers, repositories, persistence, backend contracts, supported OS versions, tests and dirty files. Reuse decisions already recorded in `.reflex/decisions.md`. Record the owner of each state transition and external effect before extracting code.

Use these defaults when the project has no established equivalent:

- Domain core: Swift value types, typed actions and internal events, and explicit effects. No native managed objects.
- Swift/Kotlin API: app-owned Swift value types, actions, effects, results and protocols exposed through a narrow public façade.
- Native interop: SwiftJava-generated Java wrappers and JNI bindings called directly from Kotlin. No Protobuf or JSON dispatcher for ordinary core calls.
- Apple persistence: SwiftData, Core Data or the existing store behind a native repository adapter.
- Android persistence: Room or the existing store behind the same semantic repository contract.
- Web, only when requested: the core compiled to WebAssembly behind a BridgeJS façade, with persistence and network as TypeScript adapters.
- External services: one declared owner per operation, either portable Swift transport or a native host adapter.
- Sync: per-feature online-only, cached-read or durable queued-write policy, with one coordinator and native scheduling.
- Repository layout: one monorepo containing the Swift package, the apps, SwiftJava build integration and shared test fixtures.
- Shared product tests: one e2e suite using `e2e` and `@e2e-dev/mobile`, with an explicit target per surface.
- Fast platform-specific tests: Swift Testing/XCTest and Kotlin JUnit. Use native device or instrumentation tests where OS or JNI behaviour is required.

Use SwiftJava for the in-process Swift/Kotlin boundary regardless of core size. Keep network and persisted payload formats separate from that API. Preserve a useful external Protobuf or JSON contract where it belongs. Handwritten maps and string action names are not a substitute for typed production interfaces. When migrating an existing byte-dispatch bridge, follow [Typed contracts](references/typed-contracts.md) and retain required consumer compatibility until the native path is verified.

## Load the relevant references

- First run in a project, a refused command, receipts, decisions or handoff: [Project state and continuation](references/evidence-and-resumption.md)
- Fresh projects, separate repositories or iOS-to-monorepo migration: [Projects and migrations](references/projects-and-migrations.md)
- Domain state, effects, lifecycle and headless introspection: [Core and contract](references/core-and-contract.md)
- SwiftJava API types, platform ports, compatibility and serialized data boundaries: [Typed contracts](references/typed-contracts.md)
- SwiftData/Room adapters, transactions, migrations and offline/online sync: [Persistence and sync](references/persistence-and-sync.md)
- HTTP/RPC, authentication, streams, retries and background transfers: [External APIs](references/external-apis.md)
- Swift cross-compilation, JNI, actors and packaging: [Swift on Android](references/swift-on-android.md)
- A web surface on the same core: [Optional web target](references/web-target.md)
- Permissions, OS lifecycle, files, payments, identity and native capabilities: [Platform services](references/platform-services.md)
- Contract, repository, sync, native and shared UI tests: [Shared tests](references/shared-tests.md)
- Animation, effects, streaming text, scrolling or keyboard parity: [Motion and native input](references/motion-and-input.md)
- Generated UI, rich text or embedded web content, only when present: [Rich native content](references/rich-content.md)
- A failing boundary: [Troubleshooting](references/troubleshooting.md)

## Implement one production path

1. **Define authority and write policy.** Distinguish transient view state, durable local data and server-authoritative data. Specify which operations work offline and which require an online decision. Choose domain-specific conflict behaviour.
2. **Define typed contracts.** Specify the façade's actions, state snapshots/deltas, effect requests/results and failures. Define IDs, correlation, account/session generation, revisions and compatibility. Track the generated native API, external API schemas and stored payload versions separately.
3. **Extract the core.** Move portable decisions into a UI-free module with injected ports, identifiers and clocks. Route UI and headless actions through the same owner. Reject invalid input before committing state.
4. **Implement native adapters.** Map SwiftData/Room records to portable values inside their native isolation/transaction boundaries. Return explicit persistence results. Keep credentials, native handles, schedulers and permissions in their host adapters.
5. **Prove a vertical slice.** Drive one real action through the CLI and every declared target. If it is a durable offline operation, verify local commit, restart, replay and server acknowledgement. If it is online-only, verify the offline refusal and ambiguous-result recovery instead.
6. **Expand from the item ledger.** Include native input, accessibility, lifecycle, background effects, data migrations and public consumer compatibility where the product uses them.

For a durable write, distinguish optimistic presentation, committed local state, queued work, remote acknowledgement and conflict. Do not label an edit saved before the promised persistence boundary completes. UI disposal, coroutine cancellation and process death are different events; define what each may cancel and what must resume from durable state.

## Expose production behaviour for tests

Project the real state and typed action descriptors into a headless inspection API. Keep eligibility and domain validation in the production owner. Focus the active screen/node, validate target identity and define any ancestor-action propagation. Fixture construction, clocks and effect delivery belong to a separate harness boundary.

Use an explicit JSON projection or NDJSON CLI for inspectability. Have it call the same typed owner as the SwiftJava façade; keep the production Android path on generated native calls. Keep diagnostics off protocol stdout. If a debug introspection server is needed, exclude it from release builds and restrict/redact sensitive state.

## Verify and deliver

Use the shared e2e suite for product journeys through every declared app. Keep fast core and platform-specific unit tests in native Swift Testing/XCTest and Kotlin JUnit suites. Add real native store/migration, transport and lifecycle checks for boundaries a unit test cannot establish. Retain native tests for input, rendering and OS behaviours the shared driver cannot exercise. Use [Shared tests](references/shared-tests.md) for the test layers and their evidence.

When porting an existing interface, verify its transitions and native input through [motion and native input](references/motion-and-input.md). Compare timestamped frame sequences, including the first changed frame and settled content. Static screenshots and shared state tests do not establish animation or keyboard parity. Keep visual parity incomplete until the required comparisons pass or the user accepts a specific difference.

Require the intended tests to execute on every claimed host. Distinguish simulator/emulator, physical device, release artifact and remote CI results in each receipt's `--environment` and `--note`. Validate an independent public consumer and preserve existing failures without weakening assertions to produce a green report.

Keep app-specific versions, paths, counts and incident history in the project's `.reflex/` records, not in this skill. Promote only general decisions supported by vendor contracts or observed behaviour; do not claim this guidance implements or runtime-tests a project's sync system.
