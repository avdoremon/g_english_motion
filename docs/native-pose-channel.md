# Native pose channel (retired)

The custom MethodChannel/EventChannel contract
(`vn.avdoremon.g_english_motion/pose`, `…/pose_frames`) and its Dart side
`MediapipeFrameSource` were retired on 2026-11-01 before any Kotlin was
written. Pose frames now come from the published plugin
`flutter_mp_pose_landmarker` via `lib/input/plugin_pose_frame_source.dart`;
see `docs/pose-plugin-evaluation.md`. The old contract is in git history
(commit `c14ffb3`) should we ever write our own native side (fallback 2).

## Rules that still apply to any PoseFrameSource

- Coordinates are normalised 0..1, y DOWN, in the UNMIRRORED camera image
  rotated upright. The source never mirrors; the game mirrors for display and
  lane mapping (`LaneTracker.mirror`). If a backend delivers mirrored x, the
  adapter undoes it (`PluginPoseFrameSource.landmarksMirrored`).
- x is normalised by the upright frame WIDTH and y by its HEIGHT, so the two
  axes are only comparable through `PoseFrame.aspectRatio = width / height`
  (`laneWidthInX = 0.6 * torsoHeight / aspectRatio`). The plugin does not
  report the size; the adapter assumes its 640x480 analysis size (4:3).
- Timestamps are monotonic and strictly increasing for a whole start..stop
  run, including after background/resume.
- `stop` is idempotent, never throws, releases the camera; `start` after
  `stop` must work (retry, next level, play again).
- One camera session only: the Dart consumers share one broadcast stream.
  With the plugin this also means exactly ONE `PoseCameraHost` (it hands out
  a single shared preview view).
- The camera must recover by itself after background/resume or another app
  taking it; if it goes silent, the game's frame watchdog pauses play.
- Privacy: frames and landmarks are never stored or sent.
