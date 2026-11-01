# Native pose channel contract (Android)

Status: Dart side implemented (`lib/input/mediapipe_frame_source.dart`).
Native Kotlin side is PENDING spike Task 0: either the plugin
`flutter_mp_pose_landmarker` or custom Kotlin on MediaPipe Tasks Vision.
Whichever is chosen must support `numPoses = 2`, the GPU delegate, image
rotation handling, and front/back camera selection.

## Channels

| Kind | Name |
|---|---|
| MethodChannel | `vn.avdoremon.g_english_motion/pose` |
| EventChannel | `vn.avdoremon.g_english_motion/pose_frames` |

## MethodChannel methods

- `start` with arguments `{ "numPoses": int, "frontCamera": bool }`
  (Dart defaults: 2, true). Requests the CAMERA permission if needed, opens the
  camera and starts detection. Returns a String: `"granted"`, `"denied"` or
  `"permanentlyDenied"`. Alternatively fail with a `PlatformException` whose
  code is `PERMISSION_DENIED` (denied) or `PERMISSION_PERMANENTLY_DENIED`
  (permanentlyDenied); any other code or unknown string is treated as denied.
  Events are only expected after a `"granted"` result.
- `stop` (no arguments). Stops detection and releases the camera. Returns null.

## EventChannel payload

One map per processed camera frame:

```
{
  "timestampMicros": int,            // microseconds
  "frameWidth": int,                 // upright frame size in pixels (see
  "frameHeight": int,                //   "Axes and aspect ratio"); optional
  "poses": [                         // 0..numPoses entries
    { "landmarks": {
        "<PoseJoint.name>": { "x": double, "y": double, "confidence": double },
        ...                          // only joints that are present
    } }
  ]
}
```

Joint keys: `nose, leftShoulder, rightShoulder, leftHip, rightHip, leftWrist,
rightWrist, leftKnee, rightKnee`. Other joints may be sent and are ignored.
Malformed events are skipped by Dart and never throw.

## Semantics

- Coordinates are normalized 0..1 with y pointing DOWN, in the UNMIRRORED
  camera image, already rotated upright to match device orientation. The
  native side must NOT mirror the front camera (neither the image the model
  sees nor the landmarks it sends): Dart mirrors for display and lane mapping.
- `confidence` is the landmark visibility/presence score in 0..1.
- `timestampMicros` is the camera frame's capture time (monotonic, strictly
  increasing), not the time the result was delivered. Dart wraps it directly in
  `Duration(microseconds: ...)`.
- Privacy: the native side must not persist or upload frames or landmarks.

## Axes and aspect ratio

x is normalised by the upright frame WIDTH and y by the upright frame HEIGHT
(the usual MediaPipe convention), so one unit of x and one unit of y are
different physical distances. Dart needs the frame size to compare them (lane
width is derived from the torso height, which is a y distance, and applied to
x): `aspectRatio = frameWidth / frameHeight`, and

    laneWidthInX = 0.6 * torsoHeight(y fraction) / aspectRatio

- Send `frameWidth` and `frameHeight` (positive ints, the size of the image
  AFTER rotation to upright) in every event. They may change when the device
  rotates; Dart always uses the latest frame's values.
- When either is absent or not positive, Dart assumes 16:9 (`1.7778`).
- The "centred" check (`|centerX - 0.5|`) is in x fractions and is unaffected.

## Native lifecycle requirements

- Frames must keep flowing after the app is backgrounded and resumed, and after
  a system interruption (Smart View / screen mirroring, split-screen, another
  app taking the camera). The native side restarts the camera session by itself
  on resume. If it cannot (camera lost for good) it must send an event
  `{ "type": "interrupted" }` on the EventChannel (Dart ignores unknown events
  today and then relies on its frame watchdog, which pauses the game) and later
  resume frames; it must never go silent without telling.
- `stop` is idempotent: calling it when nothing runs (or twice) returns null and
  never throws. `start` after `stop` must work (a new play flow).
- There is exactly ONE EventChannel stream handler. Dart consumers share one
  broadcast stream; do not create a camera session per listener. Frames are
  produced only between `start` and `stop`.
- Release the camera, the model and any threads when the Activity is destroyed
  (and on `stop`), even if Dart never calls `stop`.
- `timestampMicros` is monotonic and strictly increasing across the whole
  `start`..`stop` run, including after a resume (never reset to 0 mid-run).
- Dart-side summary of what is mirrored: nothing on the native side (see
  Semantics). Landmarks are sent as seen by the unmirrored upright image.
