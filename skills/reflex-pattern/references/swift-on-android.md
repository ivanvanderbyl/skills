# Shared Swift core on Android

Read this reference when Kotlin consumes the same Swift logic as the Apple app. Verify current installation details in the [official Swift SDK for Android documentation](https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html) and its linked interoperability examples. SDK releases and NDK requirements change.

## Prove the toolchain before broad extraction

Record the host Swift compiler version, Android Swift SDK version, NDK version, target triple and minimum Android API. Record SwiftJava, its support libraries, the build JDK and generated Java source level. The open-source host toolchain and Android Swift SDK must match. An installed Xcode Swift compiler is not sufficient evidence that cross-compilation is configured.

Keep task tooling in a declared local cache or use an existing toolchain manager. Avoid changing the user's global active toolchain just to run the project. Pin a verified toolchain matrix in the repository's build scripts or CI configuration. For native Android dependencies, also inspect AAR minimum compile SDK/minor-SDK metadata and Kotlin dependencies before selecting AGP, Gradle and Kotlin/Compose compiler versions. A transitive browser engine can require a newer Android toolchain even when the Swift core still builds.

Build in these increments:

1. Compile a minimal Swift library for the Android ABI required by the emulator.
2. Inspect its native dependencies and package its runtime libraries in an APK.
3. Generate Java wrappers and Swift JNI glue with SwiftJava; call the library from Kotlin inside the installed app.
4. Cross-compile the actual portable core and its dependencies.
5. Run a real production state/action journey through the Kotlin wrapper.

A successful macOS executable or an Android command-line executable does not prove app packaging or JNI integration. Verify the APK installation and observed output before calling the bridge usable.

## Generate the native API with SwiftJava

Start from the recommended [hello-swift-java example](https://github.com/swiftlang/swift-android-examples/tree/main/hello-swift-java). Use SwiftJava `jextract --mode=jni` to generate the Kotlin-callable Java API and Swift JNI glue from the public façade. Compile the glue with the Swift library and package the matching generated Java classes and support runtimes. Consult the pinned release's CLI/configuration and example build tasks for complete commands; one generator invocation alone is not an Android build. Keep the build JDK, generated Java level and Android/desugaring support distinct. SwiftJava's FFM mode targets a different Java runtime integration; select JNI for Android.

Expose typed methods and values directly. Keep Protobuf and JSON encoding in external-service, persistence or inspection adapters when those formats are needed there. See [Typed contracts](typed-contracts.md) for API design and migration from a byte dispatcher.

Prove the actual type graph with the pinned generator. The examined [0.7.0 feature documentation](https://github.com/swiftlang/swift-java/blob/0.7.0/Sources/SwiftJavaDocumentation/Documentation.docc/FeaturesJextract.md) includes classes, structs, enums with associated values, protocols, throwing functions and async functions. It also lists limited generic support and unsupported `@Sendable` closure parameters. Check the selected release rather than assuming the latest documentation applies. Flatten an unsupported export to concrete façade types or typed effect requests/results before considering a different bridge.

Use generated protocol interfaces for Kotlin-implemented native ports only after checking the exact requirements. The [weather example](https://github.com/swiftlang/swift-android-examples/tree/main/swift-java-weather-app) demonstrates a Kotlin implementation of a Swift protocol and an asynchronous Swift call. That example does not establish automatic export of every asynchronous repository interface.

For Swift `async`, select the supported future mode for the minimum Android API. In the documented `CompletableFuture` mode, Kotlin can use `kotlinx.coroutines.future.await` with the matching coroutine dependency. Do not block Compose's UI thread with `get()`, `join()` or a synchronous callback waiting on UI work. Verify cancellation of the underlying Swift operation separately from cancellation of its Kotlin observer. Adapt observation to `StateFlow`/`Flow` explicitly; do not infer automatic `AsyncSequence` translation.

Follow the generated `SwiftArena` lifetime rules. Give the Kotlin session owner responsibility for native wrappers, subscriptions and in-flight work. Keep values referenced by state alive until their users finish, or copy them into Kotlin-owned snapshots through an explicit mapping. Use the pinned runtime's closeable ownership API when deterministic teardown is required; do not guess method names or assume garbage collection supplies that lifecycle. See [Typed contracts](typed-contracts.md#async-callbacks-and-ownership).

Keep a consumer outside the implementation module. Exercise representative optional values, enum payloads, collections, errors and a Kotlin-to-Swift-to-Kotlin callback through installed native calls. Do not infer support for an actor or closure path merely because another exported method compiled.

## Migrate an existing manual bridge

Keep the existing public bridge compatible while replacing its internal callers in verified slices. [Typed contracts](typed-contracts.md#build-compatibility-and-migration) defines the migration route. Preserve a headless JSON projection as a separate adapter where required. Do not route the new generated methods through the old generic serialized dispatcher.

While a manual C/JNI bridge remains in use, retain its ownership contract beside the header and wrapper:

- Who owns each input buffer and how long it remains valid.
- Who allocates the response and which exported function frees it.
- How null input, decoding errors and allocation failures are represented.
- Whether requests are serialized, thread-safe or restricted to one dispatcher.
- How session destruction interacts with in-flight work.

Copy response bytes before freeing their native buffer. Release JNI strings and arrays on success and failure paths. Do not allow Swift errors or Kotlin exceptions to cross the C ABI without translation. Define callback-thread attachment/global-reference ownership when callbacks originate on native worker threads, and translate failures into the typed result contract.

JNI's modified UTF-8 conventions differ from ordinary UTF-8. Verify supplementary characters, embedded NUL and combined graphemes using the actual chosen conversion path. Do not infer correct Unicode from an ASCII greeting.

Keep native handles behind an `AutoCloseable` or equivalent Kotlin owner. Release a session once and reject use after close. Make the Compose state holder's lifecycle own the wrapper rather than allocating a fresh native session on recomposition.

## Package and release

Inspect all dynamic native library dependencies for every supported ABI. Match packaged libraries to their ABI directories and verify the Android linker can locate them from a clean installation. A developer machine's library search path is not part of the app.

Build the Android library independently of the demo. Verify a small consumer can load the library, create a session and dispatch an action. Keep compilation, installed-app behaviour and the vendors' published compatibility matrices as separate evidence; do not suppress metadata or unsupported-SDK checks to turn one into another. If distribution requires generated libraries or downloaded artifacts, make that build path reproducible and document the artifact's version/checksum source.

For asynchronous effects, publish state updates through a declared subscription/callback or bounded polling policy. Define snapshot revision, delta ordering, buffering/backpressure and resubscription after a missed update. Check cancellation, teardown and activity recreation. Verify whether cancelling a Java future or Kotlin coroutine cancels the Swift operation or only its observer; do not discard an already accepted durable result. Keep network credentials and production endpoints out of deterministic fixture sessions.

Check release shrinking, exported JNI entry points, package resources and native page alignment for the supported Android configurations. Static ELF alignment is not a substitute for execution on the corresponding page-size device. Pin reproducible source/generator/runtime versions and verify generated-code drift in CI.

## Swift actors and the Android main loop

Inspect actor requirements in portable dependencies before choosing a synchronous JNI call. Kotlin's UI thread alone does not prove that Swift MainActor work can execute. A blocking JNI request on that thread can prevent the event loop from servicing work that the request awaits.

If the core uses MainActor-bound dependencies, prove the chosen Android Looper integration in the installed app. Keep blocking bridge requests off the UI thread. Verify asynchronous actions and an interactive control after the first successful request. [Swift issue 89711](https://github.com/swiftlang/swift/issues/89711) describes a JNI-app hang that a working Android command-line executable did not reveal. Verify a library's current integration guidance before using private runtime entry points; pin and check any such dependency explicitly.

## Evidence to retain

Record exact build/install commands, compiler/SDK/NDK versions, the APK ABI, linker dependencies and a Kotlin-to-Swift result from the app. State whether only one ABI or emulator configuration was tested. Keep failed downloads, unsupported dependencies and unverified lifecycle behaviour visible until resolved.
