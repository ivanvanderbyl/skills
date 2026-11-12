# iOS 27 fold APIs

Names that exist in the iOS 27.3 simulator SDK's Swift interfaces and headers. Read this before writing fold or arrangement code, because these APIs are newer than most training data.

This is a list of names and shapes. Only the two marked "exercised" were compiled and run for this skill. For everything else, read the declaration and its documentation comment in the SDK before use:

```sh
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
grep -rn --include='*.swiftinterface' -B12 'func onHingeChange' "$SDK/System/Library/Frameworks"
grep -rn 'UIHinge' "$SDK/System/Library/Frameworks/UIKit.framework/Headers"
```

## SwiftUI

- `onHingeChange(isEnabled:_:)`: calls the closure with the old and new `DeviceHingeContext`. Exercised: on the iPhone Duo simulator it delivered a `closed` status at launch.
- `DeviceHingeContext`: `hinge: DeviceHinge?`, whose `status` is `.closed`, `.partiallyOpen` or `.fullyOpen`.
- `@Environment(\.horizontalSizeClass)`: exercised; compact in the closed pose.
- `ArrangementView<Primary, Secondary>` with `.arrangementViewStyle(_:)`. Styles: `.automatic`, `.split`, `.overlay`, each with `.axes(_:)`.
- Arrangement modifiers: `splitArrangementLayoutRatio`, `splitArrangementLayoutSize`, `splitArrangementFixedLayoutSize`, `splitArrangementAxis`, `overlayArrangementEdge`, `overlayArrangementZIndex`.
- `reservedRegions(kind:options:layoutDirectionBehavior:)`: kinds `.occlusion` and `.division`; option `.includeInactive`.
- `presentationPlacement(_:)`: `.automatic`, `.leading`, `.center`, `.trailing`.
- `toolbarVerticalBehavior(_:)`: `.automatic`, `.disabled`.

## UIKit (iOS 27.1)

- `UIArrangementViewController`, `UISplitArrangement`, `UIOverlayArrangement`.
- `UIHinge` (`status`, `angle`) and `UIHingeInteraction`.

## From Apple's documentation, not checked on a device

- Lay out with size classes, not one layout per pose.
- Keep the same functionality in every pose.
- `NavigationSplitView` collapses to one pane when the device is closed.
- Do not nest navigation containers inside `ArrangementView`.

## Simulator

The iPhone Duo simulator has two integrated displays. In `xcrun simctl io <device> enumerate` they are screen 1 (1398 × 2034) and screen 3 (2007 × 2853), both at scale 3. Screen 1 showed the app in the closed pose, so it is the outer display; screen 3 is taken to be the inner one from its size, and its screenshot is black while the device is closed. Pass `--display=1` or `--display=3` to `simctl io <device> screenshot`.
