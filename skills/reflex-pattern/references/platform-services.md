# Native services and lifecycle

Read this reference for features that cannot be implemented solely by a portable reducer. Expose typed capabilities and results to Core; retain OS objects and SDK lifecycle in the native adapter. Use [typed contracts](typed-contracts.md) for the envelope and [external APIs](external-apis.md) for transport/authentication ownership.

## Assign the native boundary

| Area | Keep in the host | Specify in the portable contract |
| --- | --- | --- |
| Permissions, camera, location, Bluetooth and biometrics | OS requests, prompts, handles and foreground/background restrictions | Requested capability, operation/account generation, granted/denied/restricted/unavailable result and cancellation |
| Credentials and authentication | Keychain or appropriate Android secure storage, system auth UI, refresh coordination | Account identity, authentication-needed state and sanitised failure; no credential in UI snapshots or durable command payloads |
| Background execution | Supported Apple scheduler/transfer API or Android WorkManager and its cancellation/expiration callbacks | Durable operation identity, progress/checkpoint, retry eligibility and remaining work |
| Files and attachments | Security-scoped access, Android content URI grants, sandbox paths, native transfer sessions and file cleanup | Attachment ID, media type, size/hash, upload state and an adapter-owned opaque access reference |
| Push, deep links and app shortcuts | Registration tokens, OS delivery, URL/intent parsing and launch lifecycle | Validated typed route/refresh intent, authorised account/entity scope and deduplication identity |
| StoreKit/Play Billing and entitlements | Store SDK interaction, pending purchases, transaction delivery and platform-specific receipt material | Purchase intent, pending/confirmed/rejected state, product mapping and backend-verified entitlement |
| Widgets, extensions and multiple windows/processes | Shared-container access, supported native storage coordination and process lifecycle | Stable IDs, repository revisions and independent subscriptions; no shared in-memory singleton assumption |
| Appearance, accessibility and text editing | SwiftUI/Compose semantics, Dynamic Type/font scale, native IME, selection, focus and display geometry | Semantic state/actions, stable item identity and policy inputs in explicit units |
| Locale, clocks and ordering | Display formatting, user locale/time zone and OS time sources | UTC instants or explicit civil date/time-zone values, currency/decimal precision, monotonic durations and server revisions |
| Observability and feature configuration | Native crash integration and platform diagnostics | Correlation IDs, typed error categories, redacted events and versioned capability/feature inputs |

Request permissions in response to the feature's user interaction and lifecycle requirements. Treat revoked, restricted, unavailable and denied capabilities as ordinary states. A persisted permission flag is not proof that access still exists after restart. Avoid a second permission decision in the reducer that contradicts the adapter's current OS result.

Use the credential ownership in [external APIs](external-apis.md#keep-authentication-native-and-account-scoped). Match native credential availability, device-lock, backup/restore and logout behaviour to the product's foreground and background operations.

## Background execution is an opportunity

Choose the native mechanism by workload and target availability. Apple's [background strategy guide](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app) distinguishes deferred processing, short refresh and transfers; the system chooses scheduling time. Android [WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent) persists eligible work, while constraints, quotas and retries affect execution. Neither supplies a portable always-running process or an exact completion deadline.

Use the native scheduler to wake the declared sync/transfer coordinator. Keep queue policy and merge decisions in their established shared owner. Scan durable work on launch/resume so a crash between commit and scheduling cannot strand an edit. Handle expiration by committing safe progress and releasing/recovering claims, not by reporting unfinished work as successful. An Android foreground service is a separate capability with its own current platform requirements, not a generic substitute for iOS background limits.

After a background native transfer finishes, reconcile its task identifier with the durable attachment/operation record before starting another upload. Keep dependent domain mutations pending until their prerequisite upload is accepted. A bridge cancellation can stop observation without proving the server rolled back bytes or a transaction.

## Account and process boundaries

Carry account scope and an account generation through native callbacks and storage writes. Cancel old subscriptions and fence late callbacks when an account changes. Keep device-global permissions distinct from per-account data and credentials. Follow the product's retain/delete policy for pending offline edits rather than silently wiping them during a technical refactor.

For multiple processes or extensions, prove how repository changes become visible and how competing writers are coordinated. A Swift actor or Kotlin mutex protects one owner in one process. It does not provide cross-process compare-and-swap or refresh another process's cached state. Reconnect observations and validate repository revision after resume.

## Platform verification and release

Exercise actual native permission revocation, activity/scene recreation, background expiration, deep-link delivery and callback-after-account-switch where the feature uses them. Keep unsupported simulator behaviours separate from physical-device evidence. For purchases or reservations, use authorised sandbox/test accounts and assert pending and ambiguous-result reconciliation; a client callback alone is not server entitlement verification.

Check native input composition, keyboard modifiers, large fonts, right-to-left layout, screen readers and reduced motion against the supported feature set. Sharing a state model does not make two native renderers geometrically equivalent. Keep presentation strings localised and separate from protocol enum values or error codes.

Validate release packaging, ABI closure, JNI symbol retention/shrinking rules, resources, minimum OS/API support and independent consumers. Distinguish source compatibility from binary compatibility and debug execution from release operation. Verify the current vendor requirements for the project's versions rather than adopting another app's SDK pins or size measurements.
