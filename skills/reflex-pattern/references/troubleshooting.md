# Troubleshooting Reflex implementations

Establish a failure's boundary before editing. Record the smallest failing command, last known state and whether the fault lies in the product, bridge, build, fixture or device runner. Reproduce the chosen boundary, then change the smallest confirmed cause.

| Symptom | Inspect | Proof after a fix |
| --- | --- | --- |
| Core still requires a simulator | UI imports and transitive renderer dependencies | Core builds and a production journey runs without UI frameworks |
| CLI passes while the screen behaves differently | Whether UI and CLI dispatch to the same production owner | Same action/state sequence through each host and a native interaction check |
| One-shot CLI invocation works but a persistent session times out | Buffered stdout and whether each NDJSON reply is flushed | Multiple requests receive replies before the input stream closes |
| Swift CLI works but actor-bound actions hang inside an Android APK | Swift MainActor integration with Android's main Looper, and whether JNI blocks that Looper | Actual Kotlin-to-Swift requests complete while async runtime work and UI events continue |
| Android cross-compilation rejects the SDK | Exact host compiler, Android Swift SDK and NDK versions | Matching toolchain compiles the real dependency graph |
| APK builds but native library will not load | ABI directory, library dependency list, packaged Swift runtime | Fresh installation loads the library and Kotlin dispatch returns real state |
| Non-ASCII text changes across JNI | Modified UTF-8 versus UTF-8 conversion and byte length | Emoji, combining characters and embedded NUL round-trip through the app |
| A cancelled stream alters a new response | Request identity and late internal-message handling | Late delivery cannot mutate the cancelled or replacement response |
| Inline and expanded artifacts lose edits | Runtime identity and spec-default merge semantics | Native edit and action result survive expansion, close and a spec update |
| A visible JSON input ignores taps | Native hit testing, decorative overlays and parent semantics | Real driver taps/typing change state through the control |
| First JSON render is empty | Validation, initial state seeding and tree preparation order | First visible frame contains expected native controls |
| Latest remains visible at the resting bottom | Actual native viewport/insets and final idle geometry callback | Latest clears at rest and growth follows without overscroll |
| Screenshot mismatch affects most fixtures | Pixel dimensions, scale, appearance, fonts and capture configuration | Reviewed comparison in the intended configuration, with cause recorded |
| Shared suite appears green on only one platform | Target discovery, test filtering, skips and app artifacts | Expected test-target pairs execute and pass on both |
| e2e reports `NO_TESTS` despite files existing on macOS | Tracked directory case versus glob spelling, including `Tests` versus `tests` | `e2e list --reporter json` lists every expected test-target pair |
| e2e cannot find prose that its failure screenshot clearly shows | Whether native selectable text is exposed as a textbox value rather than node text | A shared text/display-value locator passes without removing visibility or bounds assertions |
| A fixture session recovers from a network error and passes | Whether attempted requests are recorded outside app recovery | Teardown fails even when the caller catches the denied request |
| An incremental HTTP adapter compiles but never receives data | Actual session delegate routing in the target Foundation implementation | A live server withholds its second chunk until the first is observed; cancellation closes the live request |
| A remote draft echo erases newer typing or marked text | Revision acknowledgements, native editor initialization callbacks and composition ownership | An actual native InputConnection retains newer text, selection and composition through an older acknowledgement |
| Custom JSON controls disappear only on one host | Component/slot/fallback metadata passed to the portable runtime | The same custom native editor and named slot work through CLI and both UIs |
| Closing/removing an artifact crashes an async handler | Runtime lifetime through success/error callbacks, including unowned dependency captures | An accepted operation settles safely after message removal and session disposal |
| Switching sessions edits the previous conversation | Retained native context keyed to the initial session | Two sessions with identical artifact IDs remain independent after switching |
| Reordering repeated editors moves focus to another item | Native composition keys and factory-bound identifiers, using rendered instance IDs | The focused native editor keeps its identity and accepts the next edit after reorder |
| A visible field or preview tap reaches another control | Full padded dock bounds, floating Latest bounds and the actual tap point | The target is above covering controls and the intended dialog or typed value appears |
| One of two navigation decisions stays pending after disposal | Completion-result equality/hashCode and the pending-request collection | Both real native callbacks resolve once when request ownership changes or closes |
| A browser AAR rejects an otherwise working Android build | minCompileSdk/minCompileMinorSdk, Kotlin metadata and the complete AGP/Gradle/compiler matrix | The actual production library, demo and test artifacts build without suppressing compatibility checks |
| A typed message parses but updates the wrong account or operation | Account generation, correlation, operation ID and domain preconditions | Late/wrong-scope events reject without changing the replacement state |
| A shared core requires SwiftData or Room types | Domain/contract mappings and native repository isolation | Both stores exchange portable value DTOs and domain IDs with Core |
| An offline edit appears saved but disappears after restart | Explicit save/commit receipt and same-store entity/outbox transaction | Committed edits and pending intent survive a real process restart |
| An edit uploads twice after reconnect or worker recreation | Durable claims, stable operation identity and the server's deduplication contract | Lost acknowledgement/replay yields one domain effect, or a documented reconciliation result |
| A SwiftData queue loses a lease under competing writers | Proven native conditional-claim semantics, process count and writer ownership | Real contention rejects stale claims; actor isolation alone is not treated as cross-process atomicity |
| A cursor advances past missing local data | Delta/checkpoint transaction boundary and snapshot completeness | Interrupted pull replays without lost changes or inferred deletions from a partial page |
| SwiftData and Room users see different datasets | Actual server authority, CloudKit integration, account mapping and migration path | Both authenticated clients read/write the same declared dataset through its supported sync contract |
| A schema upgrade drops pending work | Native migrations and persisted-command payload versions | Released-store fixtures retain user records, pending operations and checkpoints |
| An API write times out and retry repeats a purchase/reservation | Endpoint-specific idempotency/status lookup and ambiguous outcome handling | Original operation is reconciled before a new side effect is requested |

These are diagnostic routes, not findings that every project has these faults. Record observed instances and their limits in the current project. Add a repair command only after it has been run successfully in the relevant environment.

Keep package and device failures visible. Do not remove assertions, substitute inert controls, display a JSON source string in place of an interactive artifact or call a host result an Android pass.
