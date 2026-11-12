# Clip analysis

What the reference clips show, how it was measured and how far each claim can be trusted. Read this when a behaviour in `SKILL.md` is questioned, when matching the motion, or when analysing a new recording the same way.

Contents: source, method, geometry, timeline, motion fit, secondary changes, the other clips, limits.

## Source

Robert Bye's thread on building Claude for iPhone Duo, <https://x.com/RobertJBye/status/2113808129368760750>. The main clip is the video on the thread's opening post, a 10.8 s loop: 648 frames, 60 fps, 1080 × 1080.

The clip is an explainer diagram. Its upper half is a strip of four panes (Sidebar, List, Chat, Artifact) with an outline marking the visible window. Its lower half is a device mock showing those panes, with a "Closed" or "Open" label under it. It is not a recording of a device.

## Method

1. Extract every frame: `ffmpeg -i clip.mp4 frames/f_%04d.png`.
2. In each frame, find the pixels of the outline colour (`#d16b58`) and take their left and right extent, once in the strip's rows and once in the device's rows. That gives four edge positions per frame.
3. Measure the mean luminance of each pane in the strip and the amount of dark ink in the label's area, per frame.
4. Fit one periodic cubic-bezier to all four edges by least squares: start offset, duration and four control values, repeating every 2.700 s.
5. Replay the fitted model and compare it with every frame.

A fit is accepted when the replay is within 2 px on every frame. Step 5 is what caught the rounding error below.

## Geometry (observed)

- Background `#eeeeeb`, outline `#d16b58`.
- Pane pitch in the strip: 244 px. The window's left edge is at 52 + 244 × leading index and its right edge at 295 + 244 × trailing index, counting Sidebar as 0.
- Device mock, centred on x ≈ 540: closed 386 to 693 (308 px wide), open 232 to 847 (616 px wide), so exactly two closed widths.
- The open mock is 4 px shorter at the top and at the bottom (520 to 955 against 516 to 959).

## Timeline (observed)

One transition every 2.700 s. Frame numbers count from 0.

- Frame 48: unfold. `[Chat]` becomes `[List, Chat]`. The window's right edge stays at 783 and its left edge moves from 540 to 296. The device grows about its centre.
- Frame 209: forward while open. `[List, Chat]` becomes `[Chat, Artifact]`. The device does not change; both window edges move 244 px.
- Frame 371: fold. `[Chat, Artifact]` becomes `[Artifact]`. The right edge stays at 1027 and the left edge moves from 540 to 784.
- Frame 534: back while closed. `[Artifact]` becomes `[Chat]`. Both edges move 244 px.

The transitions reach 50% at frames 73, 235, 397 and 559 and settle 65 to 70 frames after they start.

## Motion fit

Best fit on all four edges:

- start 0.782 s into each 2.700 s period
- duration 1129 ms
- `cubic-bezier(0.44, 0.04, 0.26, 0.97)`
- largest error 2 px, mean error at most 0.13 px, no frame off by more than 2 px

Fitting the strip alone gives 1163 ms and (0.44, 0.02, 0.25, 0.99); the device alone gives 1040 ms and (0.43, 0.08, 0.28, 0.93). Each of those also replays every edge within 2 px, so the clip does not distinguish a shared curve from two slightly different ones. One shared curve is the simpler reading.

A tidied version (start 0.800 s, 1150 ms, 0.44, 0.03, 0.26, 0.98) misses by up to 16 px and is off by more than 2 px on 185 of 648 frames. A few milliseconds matter because the edges move several hundred pixels a second mid-transition. Quote fitted values, and call any round number approximate.

No edge overshoots its target. A spring model fits about eight times worse than the bezier.

## Secondary changes (observed)

- The Closed/Open label fades out and back in around the midpoint of each fold and unfold (ink reaches zero at frames 73 and 397). It does not change during forward and back.
- A pane's shade changes when it enters or leaves the window, over roughly the middle 60% of the transition. The Sidebar's shade never changes; it is never in the window in this clip.

## The other clips in the thread

Viewed as contact sheets, not measured per frame.

- "Path of screens": a three-pane strip, Sidebar, Chat, Artifact. `[Sidebar]`, forward to `[Chat]`, unfold to `[Sidebar, Chat]`, forward to `[Chat, Artifact]`, fold to `[Artifact]`, back to `[Chat]`, back to `[Sidebar]`.
- Journeys: an artifact opened on the closed device sits beside the chat after unfolding.
- Full screen: one button on the artifact takes it full screen and the same button brings back side by side.
- Predictable input: when open, tapping Code replaces the sidebar with the list on the left and the chat stays on the right; going back restores the sidebar. With chat and file showing, opening the sidebar hides the file and closing the sidebar brings it back.
- Panel states diagram: Sidebar + chat, to Chat + artifact, to Artifact full screen, each step reversible with one button, and a Close button from Chat + artifact back to Sidebar + chat.

Each of these is a test in `assets/PaneWindowTests.swift`.

## Limits

- The motion values describe a diagram's pacing. Nothing here measures the system's fold animation or the shipped app.
- The clips never unfold on the root pane, never show a path shorter than the window, and never show more than two panes at once. The model's behaviour in those cases is this skill's choice.
- The author's statement that side by side "is always sidebar + chat or chat + artefact" conflicts with the two clips that show List beside Chat. The model follows the clips.
- Colours and positions are from a compressed video and can be off by a pixel or a shade.
