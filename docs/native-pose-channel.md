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
  camera image, already rotated upright to match device orientation. Dart does
  not mirror; mirroring for display or lane mapping is a consumer concern.
- `confidence` is the landmark visibility/presence score in 0..1.
- `timestampMicros` is the camera frame's capture time (monotonic, strictly
  increasing), not the time the result was delivered. Dart wraps it directly in
  `Duration(microseconds: ...)`.
- Privacy: the native side must not persist or upload frames or landmarks.
