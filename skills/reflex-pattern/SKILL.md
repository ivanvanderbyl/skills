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
| Swift/Kotlin data contracts | App-owned schema with generated Swift/Kotlin types; prefer Protobuf for durable or substantial cross-language protocols |
| Native interop | Generated SwiftJava JNI bindings where supported, or a small owned-buffer C ABI/JNI bridge; keep schema and transport separate |
| Apple persistence | SwiftData, Core Data or the existing store behind a native repository adapter |
| Android persistence | Room or the existing store behind the same semantic repository contract |
| External services | One declared owner per operation, either portable Swift transport or native host adapter |
| Sync | Per-feature online-only, cached-read or durable queued-write policy; one coordinator with native scheduling |

Keep a suitable existing typed contract or direct generated interop. A tiny co-versioned API does not automatically need a second serialization layer. Handwritten maps and string action names are not a substitute for typed production interfaces.

## Load the relevant references

| Work | Reference |
| --- | --- |
| Fresh projects, separate repositories or iOS-to-monorepo migration | [Projects and migrations](references/projects-and-migrations.md) |
| Domain state, effects, lifecycle and headless introspection | [Core and contract](references/core-and-contract.md) |
| Generated DTOs, ABI envelopes, versioning and schema evolution | [Typed contracts](references/typed-contracts.md) |
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
2. **Define typed contracts.** Specify actions, state snapshots/deltas, effect requests/results and failures. Define IDs, correlation, account/session generation, revisions and compatibility. Keep bridge, API and database schemas independently versioned.
3. **Extract the core.** Move portable decisions into a UI-free module with injected ports, identifiers and clocks. Route UI and headless actions through the same owner. Reject invalid input before committing state.
4. **Implement native adapters.** Map SwiftData/Room records to portable values inside their native isolation/transaction boundaries. Return explicit persistence results. Keep credentials, native handles, schedulers and permissions in their host adapters.
5. **Prove a vertical slice.** Drive one real action through the CLI and both native apps. If it is a durable offline operation, verify local commit, restart, replay and server acknowledgement. If it is online-only, verify the offline refusal and ambiguous-result recovery instead.
6. **Expand from the feature inventory.** Include native input, accessibility, lifecycle, background effects, data migrations and public consumer compatibility where the product uses them. Record implementation and executed verification separately.

For a durable write, distinguish optimistic presentation, committed local state, queued work, remote acknowledgement and conflict. Do not label an edit saved before the promised persistence boundary completes. UI disposal, coroutine cancellation and process death are different events; define what each may cancel and what must resume from durable state.

## Expose production behaviour for tests

Project the real state and typed action descriptors into a headless inspection API. Keep eligibility and domain validation in the production owner. Focus the active screen/node, validate target identity and define any ancestor-action propagation. Fixture construction, clocks and effect delivery belong to a separate harness boundary.

Use a schema-derived JSON projection or NDJSON CLI for inspectability without making untyped JSON the production contract. Keep diagnostics off protocol stdout. If a debug introspection server is needed, exclude it from release builds and restrict/redact sensitive state.

## Verify and deliver

Run shared behaviour expectations through the production Swift core and Android bridge. Add real native store/migration, transport and lifecycle checks for boundaries the headless core cannot establish. Use shared mobile journeys when appropriate; retain native tests for unsupported input, rendering and OS behaviours.

When porting an existing interface, verify its transitions and native input through [motion and native input](references/motion-and-input.md). Compare timestamped frame sequences, including the first changed frame and settled content. Static screenshots and shared state tests do not establish animation or keyboard parity. Keep visual parity incomplete until the required comparisons pass or the user accepts a specific difference.

Require the intended tests to execute on every claimed host. Distinguish simulator/emulator, physical device, release artifact and remote CI results. Validate an independent public consumer and preserve existing failures without weakening assertions to produce a green report.

Record confirmed failures with their cause, repair and bounded proof in the project's evidence. Keep app-specific versions, paths, counts and incident history out of this reusable skill. Promote only general decisions supported by vendor contracts or observed behaviour; do not claim this guidance implements or runtime-tests a project's sync system.
