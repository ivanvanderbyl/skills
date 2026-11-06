---
name: reflex-pattern
description: Design, build or migrate native Swift/SwiftUI and Kotlin/Android apps around a testable shared Swift core, typed contracts and platform adapters. Use for cross-platform architecture, core extraction, persistence/sync boundaries, shared behaviour tests and visual, motion or native-input parity.
---

# Reflex pattern for Swift and Android

Keep portable application decisions in a Swift core. Native Apple and Android hosts render its state, dispatch typed actions and execute platform effects through explicit ports. A headless host exercises the same production state/action owner.

Keep UIKit/AppKit or Android Views when the app uses them; SwiftUI and Compose are common adapters, not prerequisites for the core boundary. Do not rewrite a working UI framework solely to adopt this pattern.

[Shopify's Reflex architecture](https://shopify.engineering/reflex) uses native implementations with shared behaviour tests. A shared Swift implementation is a supported architectural choice here, not a requirement of Shopify's pattern. Preserve the project's selected core and UI technologies.

## Check applicability

For an isolated styling change or a platform API task that does not affect cross-platform ownership or testing, continue with the relevant platform guidance. For cross-platform rendering, motion or input parity, use the verification references without requiring an architecture change. Do not introduce a shared core or sync system solely because this skill was loaded.

## Choose explicit boundaries

Inspect public consumers, repositories, persistence, backend contracts, supported OS versions, tests and dirty files. Reuse decisions already authorised by the user. Record the owner of each state transition and external effect before extracting code.

Use these defaults when the project has no established equivalent:

| Boundary | Recommended shape |
| --- | --- |
| Domain core | Swift value types, typed actions/internal events and explicit effects; no native managed objects |
| Swift/Kotlin API | App-owned Swift value types, actions, effects, results and protocols exposed through a narrow public façade |
| Native interop | SwiftJava-generated Java wrappers and JNI bindings called directly from Kotlin; no Protobuf or JSON dispatcher for ordinary core calls |
| Apple persistence | SwiftData, Core Data or the existing store behind a native repository adapter |
| Android persistence | Room or the existing store behind the same semantic repository contract |
| External services | One declared owner per operation, either portable Swift transport or native host adapter |
| Sync | Per-feature online-only, cached-read or durable queued-write policy; one coordinator with native scheduling |
| Repository layout | One monorepo containing the Swift package, native apps, SwiftJava build integration and shared test fixtures |
| Shared product tests | One e2e mobile suite using `e2e` and `@e2e-dev/mobile`, with explicit iOS and Android targets |
| Fast platform-specific tests | Native Swift Testing/XCTest and Kotlin JUnit tests; use native device/instrumentation tests where OS or JNI behaviour is required |

Use SwiftJava for the in-process Swift/Kotlin boundary regardless of core size. Keep network and persisted payload formats separate from that API. Preserve a useful external Protobuf or JSON contract where it belongs. Handwritten maps and string action names are not a substitute for typed production interfaces. When migrating an existing byte-dispatch bridge, follow [Typed contracts](references/typed-contracts.md) and retain required consumer compatibility until the native path is verified.

## Load the relevant references

| Work | Reference |
| --- | --- |
| Fresh projects, separate repositories or iOS-to-monorepo migration | [Projects and migrations](references/projects-and-migrations.md) |
| Domain state, effects, lifecycle and headless introspection | [Core and contract](references/core-and-contract.md) |
| SwiftJava API types, platform ports, compatibility and serialized data boundaries | [Typed contracts](references/typed-contracts.md) |
| SwiftData/Room adapters, transactions, migrations and offline/online sync | [Persistence and sync](references/persistence-and-sync.md) |
| HTTP/RPC, authentication, streams, retries and background transfers | [External APIs](references/external-apis.md) |
| Swift cross-compilation, JNI, actors and packaging | [Swift on Android](references/swift-on-android.md) |
| Permissions, OS lifecycle, files, payments, identity and native capabilities | [Platform services](references/platform-services.md) |
| Contract, repository, sync, native and shared UI tests | [Shared tests](references/shared-tests.md) |
| Animation, effects, streaming text, scrolling or keyboard parity | [Motion and native input](references/motion-and-input.md) |
| Generated UI, rich text or embedded web content, only when present | [Rich native content](references/rich-content.md) |
| A failing boundary | [Troubleshooting](references/troubleshooting.md) |

## Implement one production path

1. **Define authority and write policy.** Distinguish transient view state, durable local data and server-authoritative data. Specify which operations work offline and which require an online decision. Choose domain-specific conflict behaviour.
2. **Define typed contracts.** Specify the SwiftJava façade's actions, state snapshots/deltas, effect requests/results and failures. Define IDs, correlation, account/session generation, revisions and compatibility. Track the generated native API, external API schemas and stored payload versions separately.
3. **Extract the core.** Move portable decisions into a UI-free module with injected ports, identifiers and clocks. Route UI and headless actions through the same owner. Reject invalid input before committing state.
4. **Implement native adapters.** Map SwiftData/Room records to portable values inside their native isolation/transaction boundaries. Return explicit persistence results. Keep credentials, native handles, schedulers and permissions in their host adapters.
5. **Prove a vertical slice.** Drive one real action through the CLI and both native apps. If it is a durable offline operation, verify local commit, restart, replay and server acknowledgement. If it is online-only, verify the offline refusal and ambiguous-result recovery instead.
6. **Expand from the feature inventory.** Include native input, accessibility, lifecycle, background effects, data migrations and public consumer compatibility where the product uses them. Record implementation and executed verification separately.

For a durable write, distinguish optimistic presentation, committed local state, queued work, remote acknowledgement and conflict. Do not label an edit saved before the promised persistence boundary completes. UI disposal, coroutine cancellation and process death are different events; define what each may cancel and what must resume from durable state.

## Expose production behaviour for tests

Project the real state and typed action descriptors into a headless inspection API. Keep eligibility and domain validation in the production owner. Focus the active screen/node, validate target identity and define any ancestor-action propagation. Fixture construction, clocks and effect delivery belong to a separate harness boundary.

Use an explicit JSON projection or NDJSON CLI for inspectability. Have it call the same typed owner as the SwiftJava façade; keep the production Android path on generated native calls. Keep diagnostics off protocol stdout. If a debug introspection server is needed, exclude it from release builds and restrict/redact sensitive state.

## Verify and deliver

Use e2e mobile for shared Apple/Android product journeys through both native apps. Keep fast core and platform-specific unit tests in native Swift Testing/XCTest and Kotlin JUnit suites. Add real native store/migration, transport and lifecycle checks for boundaries a unit test cannot establish. Retain native tests for input, rendering and OS behaviours the shared driver cannot exercise. Use [Shared tests](references/shared-tests.md) for the test layers and their evidence.

When porting an existing interface, verify its transitions and native input through [motion and native input](references/motion-and-input.md). Compare timestamped frame sequences, including the first changed frame and settled content. Static screenshots and shared state tests do not establish animation or keyboard parity. Keep visual parity incomplete until the required comparisons pass or the user accepts a specific difference.

Require the intended tests to execute on every claimed host. Distinguish simulator/emulator, physical device, release artifact and remote CI results. Validate an independent public consumer and preserve existing failures without weakening assertions to produce a green report.

Record confirmed failures with their cause, repair and bounded proof in the project's evidence. Keep app-specific versions, paths, counts and incident history out of this reusable skill. Promote only general decisions supported by vendor contracts or observed behaviour; do not claim this guidance implements or runtime-tests a project's sync system.
