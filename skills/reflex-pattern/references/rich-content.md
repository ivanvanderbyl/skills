# Rich native content in a Reflex port

Inventory the actual native renderer's models, defaults and actions. A matching list of component names is only the start of a port. Preserve supported props, readonly versus locally editable inputs, confirmation ownership, repeated-instance identity, custom slots, fallback renderers and appearance configuration.

## Generated native interfaces

Pass the complete native component catalog into the portable runtime, including named slots and fallback capability. Keep one runtime for inline and expanded views. A custom native editor must write to the same binding that headless actions inspect.

Key native child loops by the runtime's rendered instance ID. A source element key is ambiguous inside a repeat. Position-based view reuse can preserve correct JSON state while transferring native focus, selection or IME state to another logical item. Exercise an edit, reorder the items and check both values and focused identity.

Separate screen focus from background measurements. An expanded artifact can make conversation actions unavailable while a native geometry observer still emits. Suspend those reports while the background is inactive, resume from current geometry on close and handle a late rejected report. Preserve cancellation and backpressure; spawning an unbounded job per frame does not repair the boundary.

Present a pending confirmation through one active surface. Inline and expanded trees may both remain mounted. Rendering a dialog from both creates duplicate prompts even when the core has one pending action.

Treat the generated UI canvas as an explicit presentation choice. Preserve the product's default appearance and any opt-in to inherited appearance or a custom background. Reset native content/text styles as well as a colour scheme; fixed dark component text and inherited light labels can otherwise become unreadable. Presentation changes should retain the core runtime's edits.

## Markdown

Port the original inline feature set and link policy, not the parser library's defaults. For example, a native Markdown builder may need a strike-through plugin, a restricted URL-span factory and explicit code typeface/size settings. Updating the builder is insufficient if a source-only memo prevents it from re-rendering existing text after a theme change.

Verify a real native span or interaction for a renderer boundary. Core parser tests establish block structure; they do not establish native strike-through, safe link interaction, text selection, code copying or font application.

## Private web previews

For a project with private HTML/SVG/web previews, establish the required website-data lifetime before selecting the Android engine. Named Android WebView profiles with deletion on disposal are disk-backed; deletion is asynchronous and cannot supply the same confidentiality after a process crash.

Choose an engine against the required isolation, JavaScript, navigation, rendering, accessibility, package-size and update contracts. A private mode can isolate website data while still writing encrypted temporary bytes. Distinguish website-data lifetime from a promise of zero disk writes. Inspect the current engine documentation and prove cookies, localStorage and IndexedDB writes/readback, simultaneous-session isolation, close/reopen and process death without clearing app data when those stores are in scope.

Keep one process-owned engine where the engine requires it and a distinct private context/session per preview. Closing a preview should release its owned session without shutting down other previews or clearing unrelated data. Verify these ownership rules against the chosen engine's APIs.

Use the production URL policy asynchronously from navigation delegates. Main-thread blocking can deadlock a Swift actor that is waiting for Android's UI Looper. Invalidate pending permission results on configuration change and disposal so an old allow response cannot reopen a denied navigation. Verify the result type's equality and hash semantics before using it as a collection key. For a result type with mutable value-based equality, track pending decisions by stable request IDs and exercise two simultaneous pending decisions through disposal. Limit any local-data exception to the application's exact direct load; page-initiated data navigation and new windows remain subject to the existing policy.

Inspect browser AAR compile-SDK/minor-SDK and Kotlin metadata before choosing Android build tools. Measure the actual product's release/split artifacts and define who updates the embedded engine. A compile pass does not establish package size, supported ABIs, storage isolation or runtime behaviour. Keep platform-specific capability and lifecycle checks beside the shared preview journey.

For simpler projects, select only the content capabilities in their approved feature set. The core pattern does not require a browser engine.
