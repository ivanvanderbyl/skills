# Shared tests

Use one set of behaviour expectations across platform hosts. A shared Swift implementation still needs tests of both its direct host and Android bridge; serialization, ownership and lifecycle differ.

## Headless behaviour journeys

Drive the production introspection contract with fixture construction at process or session startup. Keep assertions on user-visible state and permitted actions. Reserve small unit tests for non-trivial parsers, policies, reducers and bridge invariants that journeys cannot expose directly.

Admit each permanent test before adding it. Record which existing cases catch distinct regressions and consolidate duplicates in the affected area. For new product behaviour, prove an admitted test fails for the intended missing behaviour before implementation. Use the repository's test skill if available; otherwise record the same decision and failure evidence locally.

Useful journey boundaries include successful submission, partial failure, cancellation with late delivery, invalid input and state retained across presentation changes. Choose cases from the actual product contract rather than generating a test for every method.

Make identifiers, time and fixture effect delivery deterministic. Wait for the expected state with bounded polling or an explicit fixture clock. Return the failed action, expected state, observed state and fixture identity on failure. Do not use sleeps to make a journey pass.

## Typed contract compatibility

Generate Swift/Kotlin bindings with pinned schema tools and runtimes, then verify regeneration produces no unexplained drift. Run shared vectors through the actual encoders/decoders on both sides of the bridge. A schema compiling does not prove the generated bindings, JNI transport or semantic validation work.

Cover the contract's meaningful boundaries: absent/default/null values, unknown enum/action/version handling, oneof/tagged-union cases, integer limits beyond JavaScript's exact range, decimal/currency representation, date/time precision, binary payload length and Unicode. Exercise older supported readers/writers when stored outbox records or distributed app versions can outlive a release. Verify structured rejection leaves state unchanged.

For direct generated SwiftJava APIs, compile an independent Kotlin consumer of the exported types and exercise its asynchronous error/cancellation behaviour in an installed Android app. For an owned-buffer ABI, add real allocation/release and cancelled-handoff checks. Do not infer either guarantee from an in-process Swift unit test.

## Native repositories and sync

Define semantic repository cases once and execute them through both real adapters: committed reads, failed writes, transaction rollback, expected-revision conflicts, observations and account isolation. An in-memory fake earns core/effect tests; it does not establish SwiftData or Room transaction, migration or durability behaviour.

Test SwiftData upgrades from representative released store versions and Room upgrades with retained exported schemas and the supported migration helper. Check actual values, relationships, pending commands, tombstones and checkpoints, not only successful container/database creation. Use synthetic fixture data. Use on-disk/process-restart checks for durability claims rather than substituting an in-memory database.

For queued writes and delta sync, select cases from these distinct failure boundaries:

| Boundary | Observable result |
| --- | --- |
| Local save fails, or process dies before commit | No durable entity/outbox half-write; UI does not report durable success |
| Process dies after local commit but before scheduling | Restart finds the same pending operation and resumes it |
| Server commits but acknowledgement is lost | Retry/reconciliation uses the original operation identity without a duplicate domain effect |
| Foreground/background runners overlap or a lease expires | One valid claim commits; stale claims cannot acknowledge replacement work |
| An older acknowledgement arrives after a newer local edit | The newer pending intent is preserved while the older operation settles |
| Pull is interrupted between changes and checkpoint | Both commit together, or replay from the previous checkpoint |
| Deletes, duplicate/out-of-order changes or cursor expiry meet pending edits | Documented merge/full-refresh policy preserves or explicitly conflicts the local intent |
| Logout/account switch happens before a callback commits | No old-account data, credentials or visible state cross into the replacement account |
| Online-only purchase/reservation loses connectivity | No false success or blind queued charge; ambiguous outcomes reconcile with the server |

Inject clock, transport outcomes and scheduling into core tests. Use controlled servers for actual HTTP retry/framing/cancellation, and real native storage for transaction/recovery checks. Exercise native background expiration and app recreation on supported devices. A connectivity flag alone does not prove the service can be reached or that a queued write is durable.

## Enforce fixture isolation

For deterministic fixture-only suites, install a network-attempt guard in each host's network transport. Retain an attempted-request record independently of the app's error handling, and fail session teardown when a request was attempted. Verify this with a case where the app catches the transport error. Process-level egress blocking can add containment, but a blocked or recovered request alone does not satisfy the assertion that no request was attempted. Keep authorised controlled-server/API integration tests in a separate suite with explicit permitted origins and credentials.

Choose the guard to cover the transports the core can actually use. State any uncovered custom clients or platform effects. Fixture injection without a guard is deterministic setup, not proof that network access is impossible.

## Shared e2e mobile journeys

When the project selects [e2e mobile](https://e2e.com/docs/mobile), use one test file with explicit iOS and Android targets. Install its pinned compatible packages using the project's package manager. Check the installed `e2e guide setup` and `e2e guide writing-tests` before relying on a remembered API.

An illustrative config is:

```ts
import type { E2EConfig } from 'e2e';
import { mobile } from '@e2e-dev/mobile';

export default {
  tests: 'tests/mobile/**/*.e2e.ts',
  targets: [
    {
      name: 'ios',
      engine: mobile({ platform: 'ios', device: 'Named iOS simulator' }),
      app: { bundleId: 'example.app', appPath: './build/Example.app' },
    },
    {
      name: 'android',
      engine: mobile({ platform: 'android', device: 'Named Android emulator' }),
      app: { bundleId: 'example.app', appPath: './build/example.apk' },
    },
  ],
  workers: 1,
  retries: 0,
} satisfies E2EConfig;
```

These names and paths are examples. Use devices and app artifacts discovered in the project. Run `e2e doctor` against the actual config. The mobile engine does not install `appPath` by itself in the documented API: install it once per device through a fixture, then open the app at the start of each test.

Match the repository's tracked directory case exactly in test globs and scripts. On a case-insensitive macOS volume, writing `tests/mobile` into an existing `Tests` tree can succeed while e2e's glob traversal discovers no tests. Run `e2e list --reporter json` and inspect the intended test-target pairs before starting a device run.

Prefer shared accessible names and roles. Where a stable ID is needed, set SwiftUI's accessibility identifier and Compose's test tag to the same value. Enable Compose `testTagsAsResourceId` at the Android root so the accessibility driver can read those tags.

Use exact locators and retrying assertions for required CI regression tests. These tests need no model key when they have no agent steps. Agent actions can support exploration and visual judgements, with an assertion after each meaningful goal. Do not accept an agent's successful action as proof that the intended state appeared.

Reset fixture state and device settings between journeys. Keep iOS/Android differences explicit where the driver lacks a capability. An immediate negative visibility query does not prove that an asynchronous system clipboard overlay will stay absent. For an Android copy flow that shows this overlay, condition-wait for its native window to appear, dismiss it, then condition-wait for the actual SystemUI window to disappear before focusing the editor. A returned dismissal tap is not proof of window absence. When clipboard reading is unavailable, verify copied content through a real native paste and exact editor read-back, including Unicode and terminal newlines. Keep OS workarounds in the test harness; do not add product hooks for them. The documented mobile API cannot put an iOS simulator offline through `setNetwork('offline')`; do not silently skip a shared network requirement or replace it with Android-only evidence.

Reserve each simulator/emulator for one active worker. Independent source work can run concurrently, but two runners launching or reinstalling on the same device invalidate each other's state. Give each run a distinct evidence directory.

## Native and visual checks

Keep native tests for input paths the shared driver cannot exercise, including marked-text composition and hardware-key lifecycle when relevant. Preserve macOS checks if the product supports it.

For animation, streaming, scrolling and keyboard equivalence, follow [motion and native input](motion-and-input.md). Retain timestamped frame comparisons and actual native key/editor-action results alongside shared journey results.

Check real native geometry when newest content must remain above the composer or keyboard. A visibility matcher alone may not prove that a multiline paragraph fits within the usable viewport. Measure the complete padded composer dock, not only its inner editor. Include visible floating controls such as Latest in the usable touch area. A visible control with stable bounds can still be covered at its tap point. Record bounds in the platform's coordinate units and expose the target above both the dock and any covering floating control before tapping or typing. Require the expected dialog or native text read-back after the interaction.

Keep screenshot baselines per target, OS and display configuration. Review expected, actual and diff images before accepting updates. A changed pixel scale, color space or capture API can invalidate a comparison without establishing a product regression. Do not lower thresholds or record all new images solely to make the suite green.

For repeated editable items, retain focus through a real reorder and continue editing the same logical instance; correct values alone can hide native view reuse. If the app has generated interfaces or inline/expanded content, exercise those presentation and action contracts as described in [rich native content](rich-content.md).

## CI and delivery

Build each app before its device job. Require the shared test selection to execute on both targets and report their results separately. Fail missing targets, unbuilt artifacts and unexpected skips. Keep behavior failures separate from runner/device setup failures without turning either into a pass.

Archive enough state, logs, screenshots and video to diagnose failures. Verify fresh install and an independent package consumer. Report which OS/ABI/device and availability branches ran; do not infer coverage of older supported systems from a latest-OS run.

Keep schema generation/compatibility, core journeys, native repository/migration tests and mobile journeys as separate gates. Add restart/offline/reconnect coverage where promised. Preserve the distinction between a proposed validation plan, a selected test, an emulator result, a physical-device result and an executed remote CI job.
