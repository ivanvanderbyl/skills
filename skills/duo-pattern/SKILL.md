---
name: duo-pattern
description: Lays out and navigates an app for Apple's iPhone Duo, a folding iPhone, and other devices that switch between one narrow pane and two side-by-side panes, as a window over an ordered path of panes. Closed shows the last pane, open shows the last two, and folding keeps the pane the user was on. Use when adapting an iOS app for iPhone Duo, designing or reviewing fold, unfold, sidebar, side-by-side or full-screen panel behaviour, or matching the fold transition's motion. Not for a single-pane app or a styling change that no pose affects.
---

# Duo pattern: a window over a path of panes

iPhone Duo is Apple's folding iPhone (iOS 27.1 and later): a narrow outer display when closed and a wide inner display when open. This pattern keeps an app predictable across both, and across rotation and shared-screen sizes.

It encodes the model the Claude for iPhone Duo team published, checked frame by frame against their clips. [Clip analysis](references/clip-analysis.md) has the measurements and marks what was observed, what the author stated and what is inferred.

## The rule

1. Order the app's screens as one **path of panes**, from general to specific. The reference app's path is Sidebar, List, Chat, Artifact.
2. The device shows a **window** of adjacent panes that ends at the **trailing pane**: the most specific pane on screen. The window holds one pane when the width is narrow and two when it is wide. That number is the **capacity**.
3. A fold, unfold or rotation changes only the capacity. The trailing pane stays, and the pane before it appears or disappears on the leading side. `[Chat]` unfolds to `[List, Chat]`; `[Chat, Artifact]` folds to `[Artifact]`.
4. Navigation slides the window along the path one pane at a time. The order never changes and nothing is reordered to fit a pose.
5. Sliding back does not remove panes. A pane that slid out of the window stays on the path and returns when the window slides forward again.

The author's words: "think of your app as a path of screens, from general to specific. When the Duo is closed you see the last screen, and when it's open you see the last two. The order stays the same."

## Use the bundled state owner

`assets/PaneWindow.swift` implements the rule as a value type with no platform imports. `assets/PaneWindowTests.swift` holds its Swift Testing tests: one per reference clip, the `open` cases, the clamps, and a walk of every reachable state.

1. Copy `PaneWindow.swift` into the module that owns navigation state. In a project with a shared core, that is the core, so every surface gets the same rule.
2. Copy the tests into that module's test target. They import a module named `PaneWindow` and define their own `Pane` enum; change the import to your module's name. Run `swift test` before changing any behaviour (Swift 6 toolchain).
3. Make the app's pane type conform to `PathPane`. `depth` is the pane's position on the path. Two panes of one kind, such as two chats, share a depth.
4. Route every event through the type. Views render `visible` and never decide which panes show.

State: `path`, `trailingIndex`, `capacity`, `isExpanded`. Read `visible`, `trailing`, `leadingIndex`, `canGoBack`, `canGoForward`, `canExpand`.

Events:

- `resize(to:)`: the width class changed. Keeps the trailing pane. Folding also leaves full screen, so the next unfold is side by side.
- `forward()` and `back()`: slide the window one pane. `back()` stops while the window is still full, so an open device never shows one pane beside an empty slot.
- `open(_:)`: put a pane on the path and slide the window the least distance that shows it. A pane already in the window changes nothing. A pane at a new depth is inserted and deeper panes stay. A different pane at an existing depth replaces the old one and drops the deeper panes, because they belonged to the pane it replaced.
- `close(_:)`: remove a pane, such as the artifact's Close button. The root cannot be closed.
- `toggleExpanded()`: the trailing pane fills the wide window, and the same call brings back side by side.

Port the type and its tests together when the state owner is not Swift. The tests are the specification; the reference clips are the first suite.

## Decisions this model makes that the clips do not show

Tell the user about these when they affect the app, because they are this skill's choices and not observed behaviour:

- Unfolding on the root pane fills forward: `[Sidebar]` becomes `[Sidebar, Chat]` when a chat is on the path. Nothing precedes the root, so the trailing pane changes in this one case.
- A path shorter than the capacity shows what it has: the root alone on an open device is one pane.
- Opening a pane beyond the trailing edge stops as soon as it shows: from `[Sidebar, List]`, picking a chat whose artifact is on the path gives `[List, Chat]`, not `[Chat, Artifact]`.
- Capacity above two is accepted but untested against any reference.

One conflict in the source: the author writes that side by side "is always sidebar + chat or chat + artefact", while two of the clips show List beside Chat. This model treats the list as a pane between Sidebar and Chat, which reproduces every clip. If the user's app has no list level, leave it off the path.

## Drive capacity from width, not from the hinge

Set capacity from the horizontal size class: compact is 1, regular is 2. The same two layouts then serve the closed and open poses, both orientations, a shared screen and iPad. The author: "one narrow layout and one wide layout, flexing between them".

```swift
.onChange(of: sizeClass, initial: true) { _, new in
    window.resize(to: new == .regular ? 2 : 1)
}
```

Use hinge status for behaviour that is about the hinge itself, such as reacting when the device closes or sits partially open. Choose between the narrow and the wide layout by width only.

Observed on the iPhone Duo simulator (iOS 27.3): the closed pose reports compact width, and `onHingeChange` delivers a `closed` status at launch. The open pose was not observed. Confirm it reports regular width before relying on it.

Prefer a system container when it already produces the rule's result, and use `PaneWindow` as the test oracle for which panes it should show in each state. Own the window yourself only for a custom pane strip. [iOS 27 fold APIs](references/ios-fold-apis.md) lists the SwiftUI and UIKit names that exist in the SDK; they are newer than most training data, so read it before writing fold code from memory.

## Motion

One progress value drives every moving edge: the window's leading edge, its trailing edge and the content offset. Derive all three from it. Separate animations for the device frame and the content let the trailing pane drift during the fold, which is the thing the rule forbids.

- Unfold: the trailing edge is pinned to its pane and the earlier pane is revealed on the leading side. Fold is the reverse.
- Forward and back with the pose unchanged: the frame holds still and the content slides one pane.
- No overshoot. A cubic-bezier fits the reference within 2 px on every frame; a spring fits about eight times worse.
- Panes change emphasis during the middle of the move, not at its start or end.

Fitted to the reference clip: `cubic-bezier(0.44, 0.04, 0.26, 0.97)` over 1129 ms. In SwiftUI that is `.timingCurve(0.44, 0.04, 0.26, 0.97, duration: 1.13)`. The clip is an explainer diagram, not a device capture, so keep the curve's shape and choose the duration on a device. When you fit a curve to a recording yourself, quote the fitted numbers unrounded; [Clip analysis](references/clip-analysis.md) shows a tidied version of this fit missing by up to 16 px.

## Design rules the author states

- Build one narrow and one wide layout that flex. Do not design each pose.
- Lean on system components; they already move to the right place when the phone opens, closes or rotates.
- Design the journey across a fold: an artifact opened while closed sits beside its chat after unfolding.
- Offer side by side and full screen, with one control that goes both ways.
- Keep panels predictable. When open, opening a list puts it on the left and the chat stays on the right until the user picks. Opening the sidebar over chat and file hides the file; closing the sidebar brings it back.
- On the closed pose, show the sidebar full screen, not as a drawer.
- Let a pane's background colour continue under the toolbar. Keep text and buttons clear of it.
- Check what the thumb reaches and what the hand covers. The bottom right of the open device is hard to see when held.
- Put destructive actions in the overflow menu, not the toolbar.
- In landscape, give the sidebar-to-chat margin more room than the arithmetic suggests. Judge it by eye.

## Verify

A pane state test does not establish that a fold looks right, and a screenshot does not establish a transition.

1. Run the bundled tests after any change to the state owner.
2. On a device or the iPhone Duo simulator, walk each journey in both poses and both orientations: the fold loop (`[Chat]`, unfold, forward, fold, back), an artifact opened while closed and then unfolded, full screen and back, the sidebar over chat and file, and a fold while full screen.
3. Record each transition and review it at full speed, then at quarter speed. Check that the trailing pane's content does not jump, that no pane is reordered, and that nothing sits under the toolbar except background colour.
4. Report each pose and orientation separately. A pose you could not reach is "not checked", never a pass.

`simctl` has no command that folds the simulator. `simctl io <device> screenConfig power` does not change the pose, and using it left the simulator service unresponsive. Change the pose in the Simulator app or on a device.

## Mistakes to avoid

- Anchoring the window to the leading pane, or to a selected sidebar item, when the capacity shrinks. The user was on the trailing pane; folding must keep it. The bundled tests fail on this.
- Popping panes on back. Sliding back hides them; only `open` of a different pane or `close` removes them.
- Building a third layout for a particular pose. Add a size threshold to the wide or narrow layout instead.
- Treating the motion numbers as device measurements. They come from a diagram.
