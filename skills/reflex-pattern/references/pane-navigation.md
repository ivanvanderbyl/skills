# Pane layout and navigation across widths

Read this when the app has more than one level of navigation, such as a list and its detail, and any target can show two levels side by side: a foldable, a tablet, a resizable window or a desktop browser. It is a design guideline. Apply it when the project has no established navigation model, and record a decision when the user chooses another.

The rule comes from the model the Claude for iPhone Duo team published for Apple's folding iPhone, checked frame by frame against their clips. Applying it to Android and the web is this skill's extension. It was not observed on those targets, so say so when you report.

## The rule

1. Order the app's screens as one **path of panes**, from general to specific. The reference app's path is Sidebar, List, Chat, Artifact.
2. Every target shows a **window** of adjacent panes that ends at the **trailing pane**: the most specific pane on screen. The window holds one pane when the width is narrow and two when it is wide. That number is the **capacity**.
3. A fold, unfold, rotation or window resize changes only the capacity. The trailing pane stays, and the pane before it appears or disappears on the leading side. `[Chat]` widens to `[List, Chat]`; `[Chat, Artifact]` narrows to `[Artifact]`.
4. Navigation slides the window along the path one pane at a time. The order never changes, and no target reorders panes to suit its platform.
5. Sliding back does not remove panes. A pane that slid out of the window stays on the path and returns when the window slides forward again.

## Put the window in the core

The path, the trailing pane, the capacity and the full-screen flag are navigation state, which the [core owns](core-and-contract.md). One owner in the core gives every target the same answer; a window computed in each host drifts.

- The core holds one pane window and handles six events: `resize(to:)` for a new capacity, `forward`, `back`, `open(pane)`, `close(pane)` and `toggleExpanded`, which lets the trailing pane fill a wide window and brings side by side back.
- Each façade exposes a concrete snapshot: the visible panes in order, and whether back, forward and full screen are available. Hosts render that snapshot and never decide which panes show.
- A host sends two kinds of input: the capacity when its width changes, and the user's navigation. System back on Android and the browser's back button dispatch `back`.

The `duo-pattern` skill in the same repository as this one bundles a tested implementation: `assets/PaneWindow.swift`, a value type with no platform imports, and `assets/PaneWindowTests.swift`. When `duo-pattern` is installed beside this skill, read its `SKILL.md`, copy both files into the core and its test target, and wrap the generic type in the app's concrete pane type before exporting it through a façade. Otherwise write the state owner test-first from these cases:

- `[Chat]` at capacity 2 becomes `[List, Chat]`. `[Chat, Artifact]` at capacity 1 becomes `[Artifact]`.
- `back` stops while a wide window is still full, so a wide target never shows one pane beside an empty slot.
- `open` of a pane already in the window changes nothing.
- `open` of a pane outside the window slides the least distance that shows it: from `[Sidebar, List]`, opening a chat whose artifact is on the path gives `[List, Chat]`.
- `open` of a different pane at a level already on the path replaces the old pane and drops the deeper panes, because they belonged to the pane it replaced.
- Narrowing leaves full screen, so the next widening is side by side.
- Widening on the root pane fills forward, because nothing precedes the root. A path shorter than the capacity shows what it has.

The last three cases, and the least-distance rule, are choices of this model that the reference clips do not show. Tell the user about them when they affect the app.

## Set capacity from width, with one threshold

Choose between the narrow and the wide layout by the width the app has, never by device model, hinge state or user agent. The same two layouts then serve a folded and an unfolded phone, both orientations, a tablet, a split screen and a browser window.

- iOS: the horizontal size class. Compact is 1, regular is 2.
- Android: `currentWindowAdaptiveInfo().windowSizeClass` from `androidx.compose.material3.adaptive`, an `androidx.window.core.layout.WindowSizeClass`. Capacity is 2 when `isAtLeastBreakpoint(WindowSizeClass.WIDTH_DP_MEDIUM_LOWER_BOUND, WindowSizeClass.HEIGHT_DP_MEDIUM_LOWER_BOUND)` is true, which is 600 dp wide and 480 dp tall, and 1 otherwise. Android's documentation places most unfolded inner displays in portrait in the medium width class, and Material's default `calculatePaneScaffoldDirective` shows one pane there, so the default would leave an unfolded phone on one pane. The height test keeps a phone in landscape on one pane, which the same documentation calls impractical for two.
- Web: the width of the element that holds the panes, read with a container query or a `ResizeObserver`. Capacity is 2 from 600 CSS px.

Record the threshold with `decide`, as an assumption until the user confirms it, and list it in `.reflex/product.md` with the other design tokens. The Android breakpoints come from Android's documentation, and the web threshold is chosen to match them. None was measured on a foldable for this skill.

Prefer a system container when it produces the rule's result, and use the core's snapshot as the oracle for what it should show. A container that keeps its own navigation history is a second owner; the navigator behind Compose's `NavigableListDetailPaneScaffold` keeps a destination history, for example. Drive the container's selection and path from the core's snapshot, send its back and selection events to the core, and assert in the journey test that the two agree.

## Motion

One progress value drives every moving edge: the window's leading edge, its trailing edge and the content offset. Separate animations for the frame and the content let the trailing pane drift during a resize, which the rule forbids.

- Widening pins the trailing edge to its pane and reveals the earlier pane on the leading side. Narrowing is the reverse.
- Forward and back at one width hold the frame still and slide the content one pane.
- No overshoot. Use a timing curve, not a spring.

The curve fitted to the reference clip is `cubic-bezier(0.44, 0.04, 0.26, 0.97)` over 1129 ms. The clip is an explainer diagram, not a device capture: keep the curve's shape and choose the duration on a device. Define the curve once as a design token and read it on every target: `.timingCurve(0.44, 0.04, 0.26, 0.97, duration:)` in SwiftUI, `CubicBezierEasing(0.44f, 0.04f, 0.26f, 0.97f)` in Compose, and `cubic-bezier(0.44, 0.04, 0.26, 0.97)` in CSS. Compare the targets with [Motion and native input](motion-and-input.md).

## Design rules

The first five are the reference team's stated rules. The rest follow from them for a multi-target app.

- Build one narrow and one wide layout that flex. Do not design a layout per device or pose.
- Design the journey across a width change: a detail opened while narrow sits beside its parent after the window widens.
- Offer side by side and full screen on a wide window, with one control that goes both ways.
- Keep panes predictable. Opening a list on a wide window puts it on the leading side, and the trailing pane stays until the user picks. A pane hidden by sliding back returns when the window slides forward.
- On a narrow window, show the root pane full screen, not as a drawer over the next pane.
- Leading and trailing follow the layout direction, so the path mirrors in right-to-left languages.
- Give each pane the same accessibility identifier on every target, and name the panes once in `.reflex/product.md`.
- A platform control that conflicts with the rule, such as a drawer or a bottom sheet the platform's guidelines prefer, is a difference between targets: record it with `decide` and the user's words.

## Record and verify

A state test does not establish that a resize looks right, and a screenshot does not establish a transition.

1. Write each journey as a work item whose acceptance names the panes, such as "A chat opened on a narrow window sits beside its list after the window widens". The state owner's tests are the item's `core:unit` check.
2. Run each target's `journey` at a narrow and a wide width, and through one width change with a detail open. Name the widths, the device or emulator and the orientation in the receipt's `--environment`.
3. Add `--require <target>:motion` when the item covers the transition, and review the recording at full speed and slowed down. The trailing pane's content must not jump and no pane may change sides.
4. Report each target and each width separately. A width or pose you could not reach is `blocked` with a note, never a pass.

## Mistakes to avoid

- Anchoring the window to the leading pane, or to the selected list row, when the capacity shrinks. The user was on the trailing pane; narrowing must keep it.
- Popping panes on back. Sliding back hides them; only `open` of a different pane or `close` removes them.
- Building a third layout for one device. Add a size threshold to the narrow or the wide layout instead.
- Letting one target reorder, drop or overlay a pane without a recorded decision.
- Treating the motion numbers as device measurements.
