# Motion and native input parity

Read this reference when porting an existing interface or investigating flashing text, unstable layout, scrolling, animation or keyboard differences. Use the working platform as the reference unless the product specifies another target. Preserve its observable behaviour with the target platform's native controls.

## Define the comparison

Inventory each visible transition before changing it. Include text reveal, insertion, replacement, loading, completion, cancellation, scrolling, keyboard appearance and focus where present. Record the trigger, affected region, start/end states, timing, easing and any approved platform difference.

Replay the same fixture, chunk boundaries, chunk cadence and actions on both apps. Match logical viewport size, font scale, appearance, content and motion settings. Record platform fonts or geometry differences that prevent direct pixel comparison. Keep capture coordinates, logical layout units and display scale explicit.

Set acceptance criteria from the reference before tuning. Compare onset delay, duration, stagger, opacity, translation, blur, line wrapping, scroll position and settling. Use the same motion parameters where the contract requires identical effects. Declare measurement precision and tolerances explicitly. Do not silently substitute a different effect or widen tolerances after a failed comparison.

## Capture the transition

1. Reserve each device for one runner. Record the actual app revision, build mode, OS, device, display refresh rate and capture configuration.
2. Capture the reference and port from before the trigger through the settled state. Use native screen recording or a device stream by default. Request at least 60 frames per second for moving content; use the actual display cadence, including 120 Hz where relevant and supported.
3. Inspect frame presentation timestamps, frame count, repeated frames and gaps during motion. Repeated idle frames are normal. A requested frame rate is a cap or setting, not proof of captured cadence. Never upsample or interpolate a recording to claim higher temporal coverage.
4. If capture misses display updates or the defect occurs between captured frames, use a faster capture path or a high-speed external camera. Correlate display callbacks, render instrumentation and platform frame traces with the recording when needed. Report any interval that the evidence cannot resolve.
5. Retain paired recordings, trigger markers, capture metadata and frame indexes. Keep synthetic clip/tool checks separate from app recordings. A simulator or emulator result does not establish physical-device frame pacing.

Discover supported flags from the installed recording tool. Examples include `xcrun simctl io <device> recordVideo`, Android `screenrecord`, and scrcpy recording. Their configured rates and actual output can differ. Prefer direct device capture for comparison; a desktop mirror adds another presentation path. If a defect appears only through a mirror, compare that path with direct capture.

For timestamp and lossless frame inspection with FFmpeg tools:

```sh
ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,avg_frame_rate,time_base:frame=best_effort_timestamp_time,duration_time \
  -of json recording.mp4 > recording-frames.json

mkdir -p frames
ffmpeg -i recording.mp4 -map 0:v:0 -fps_mode passthrough frames/%06d.png
ffmpeg -i recording.mp4 -map 0:v:0 -f framemd5 recording-framemd5.txt
```

Use a new output directory for each capture. Frame extraction preserves the recorded frames; it does not recover display updates that the recorder missed. Check the installed tools' flags before use.

## Inspect every frame around the defect

Align the clips to the same event, not their recording start times. Compare frames at equivalent elapsed times. Retain the original timings when making slow-motion copies. Build contact sheets from consecutive frames around each transition. Do not sample only every tenth frame or review only the first and last screenshots.

Inspect the full transition at normal speed, then frame by frame. Measure stable regions separately from newly changing regions. For streaming text, track already-visible glyphs, line baselines, block bounds, newly appended ranges and scroll offset. Account for expected scroll translation before interpreting a region difference as a flash.

Check these boundaries when the feature uses them:

| Boundary | Required observation |
| --- | --- |
| A new text chunk arrives | Existing text remains visible; new text starts at the intended opacity without an intervening fully visible frame |
| Reveal advances | Only intended ranges change appearance; settled glyphs do not repeatedly fade, disappear or jump |
| Markdown structure changes | Paragraphs, lists, code fences and syntax spans retain the reference's layout and transition behaviour |
| An effect updates during layout | Line breaks, measured height and scroll anchoring change only as required by content or the reference |
| Streaming completes or stops | No whole-block flash, final layout jump, leftover animation or unexpected scroll |
| The user reads older content | Automatic following and Latest behaviour match the reference without fighting user scrolling |
| Focus, keyboard or a preview changes | The editor, transcript and overlays move together without occlusion or duplicate effects |
| Reduced motion is enabled | The product's reduced-motion behaviour applies without replaying hidden effects on resume |

Use region differences, pixel/luminance histories, native bounds and attributed-range probes to locate a mismatch. Separate font rasterisation differences from changes in visibility, geometry and timing. Inspect full-resolution frames before drawing conclusions from a compressed video or thumbnail sheet.

Trace a confirmed mismatch through native view identity, effect lifetime, attributed-text updates, bridge replies, layout and scroll ownership. Inspect whether new text is drawn before its initial reveal attributes arrive. Check whether unchanged content resets a timeline or whether opacity-only updates replace the entire text/layout. Frame timing tools can locate missed deadlines; they do not establish matching appearance or identify a cause by themselves.

Retain the same scenario and capture method after a repair. Compare before, reference and repaired sequences against the original criteria. Keep unresolved flashes and timing gaps visible in the result. Do not disable or shorten the product's effects merely to obtain a passing capture.

## Exercise the actual keyboard path

Write an input matrix from the working product. Distinguish software Return, an IME Send/Done action, physical Return, keypad Enter and a host keyboard forwarded through an emulator or mirror. These can reach different native callbacks or carry different device/source metadata.

For each supported path, exercise the real editor through the native input system. Inspect key down/up, repeat count, modifiers, composition and the editor action. Do not infer hardware input from a device ID alone. A test driver can inject a virtual event even when the user's host key is physical.

Check plain Enter, each editing modifier, held/repeated Enter, blank and disabled drafts, active composition and focus loss between down/up. Match the reference's submit versus newline policy for each path. Preserve multiline software editing and composition where the product supports them.

Verify one accepted submission, the exact submitted text, draft clearing and retained focus. Continue typing the next draft. Check the release event and repeated keys so a held key cannot send duplicate messages or add an unwanted newline. When the driver cannot represent a path, use a real InputConnection, native event injection or a manual physical-key check and name its scope.

Keep shared reducer tests, native input tests and actual end-to-end keyboard evidence distinct. Calling a submit callback or tapping Send proves neither Enter handling nor the user's emulator input route.

## Report the bounded result

Record the scenario, paired artifact paths, measured cadence/gaps, alignment marker, frame/time indexes of each mismatch, measurements against the reference and the rerun result. State which input sources actually ran. Report visual appearance, frame pacing and keyboard behaviour separately.

If the reference, adequate temporal coverage or required native input path is unavailable, name the missing evidence. Keep the corresponding parity claim unverified. A build pass, matching core values or reviewed static screenshots cannot close that gap.
