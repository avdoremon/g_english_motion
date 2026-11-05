import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'mp_pose_landmarker_backend.dart';
import 'pose_frame_source.dart';
import 'pose_types.dart';

/// One landmark as the pose plugin reports it (normalised image coordinates).
class RawPoseLandmark {
  const RawPoseLandmark({
    required this.x,
    required this.y,
    this.visibility = 0,
    this.presence = 0,
  });

  final double x;
  final double y;
  final double visibility;
  final double presence;
}

/// One plugin result. [landmarks] holds 33 BlazePose landmarks per detected
/// person, flattened (empty when nobody is in the frame).
class RawPoseResult {
  const RawPoseResult({
    required this.landmarks,
    this.timestampMs,
    this.imageWidth,
    this.imageHeight,
  });

  final List<RawPoseLandmark> landmarks;

  /// Monotonic milliseconds from the native side, when it sends one.
  final int? timestampMs;

  /// Upright analysed image size in pixels, when the native side sends it.
  final int? imageWidth;
  final int? imageHeight;
}

/// The pose plugin as seen by [PluginPoseFrameSource]. The production
/// implementation ([MpPoseLandmarkerBackend]) is a thin wrapper over
/// `flutter_mp_pose_landmarker`; tests use fakes.
abstract interface class PoseLandmarkerBackend {
  /// Loads/configures the model. Throws when the plugin is missing or cannot
  /// initialise.
  Future<void> configure();

  /// Pose results. Subscribing opens the camera; cancelling the
  /// subscription releases it.
  Stream<RawPoseResult> results();

  /// Upright width / height of the analysed image when [RawPoseResult]
  /// carries no size; null means [PoseFrame.defaultAspectRatio].
  double? get assumedAspectRatio;
}

/// Pose frames from the published `flutter_mp_pose_landmarker` plugin
/// (Android CameraX + MediaPipe Pose Landmarker). See
/// docs/pose-plugin-evaluation.md for what the plugin does natively.
///
/// Output contract (as for every [PoseFrameSource]): coordinates normalised
/// 0..1, y down, in the UNMIRRORED upright camera image; the game mirrors for
/// display and lane mapping itself.
///
/// Privacy: frames are mapped and forwarded only; nothing is stored or sent.
class PluginPoseFrameSource implements PoseFrameSource {
  PluginPoseFrameSource({
    PoseLandmarkerBackend? backend,
    Future<PermissionStatus> Function()? requestPermission,
    this.landmarksMirrored = false,
    Duration Function()? clock,
  }) : _backend = backend ?? const MpPoseLandmarkerBackend(),
       _requestPermission = requestPermission ?? _requestCamera,
       _clock = clock ?? _monotonic;

  /// Whether the backend delivers x already mirrored (selfie view). The
  /// plugin feeds the model the raw, unmirrored CameraX analysis image, so
  /// this is false for it; it exists so a mirrored backend can be undone
  /// here instead of in the game logic.
  final bool landmarksMirrored;

  final PoseLandmarkerBackend _backend;
  final Future<PermissionStatus> Function() _requestPermission;
  final Duration Function() _clock;

  final StreamController<PoseFrame> _out =
      StreamController<PoseFrame>.broadcast();
  final StreamController<PoseSourceFailure> _failures =
      StreamController<PoseSourceFailure>.broadcast();
  StreamSubscription<RawPoseResult>? _sub;

  /// Bumped by [stop] so a start still awaiting cannot open the camera after.
  int _generation = 0;
  int _lastMicros = -1;

  static final Stopwatch _sw = Stopwatch()..start();
  static Duration _monotonic() => _sw.elapsed;

  static Future<PermissionStatus> _requestCamera() =>
      Permission.camera.request();

  /// MediaPipe BlazePose (33 landmarks) indices of the joints the game uses.
  static const Map<PoseJoint, int> blazePoseIndex = {
    PoseJoint.nose: 0,
    PoseJoint.leftShoulder: 11,
    PoseJoint.rightShoulder: 12,
    PoseJoint.leftWrist: 15,
    PoseJoint.rightWrist: 16,
    PoseJoint.leftHip: 23,
    PoseJoint.rightHip: 24,
    PoseJoint.leftKnee: 25,
    PoseJoint.rightKnee: 26,
  };

  static const int landmarksPerPose = 33;

  /// permission_handler status → the game's outcome. `restricted` (OS policy,
  /// no dialog will ever show) is treated like permanently denied: only a
  /// grown-up in Settings can change it.
  static PermissionOutcome mapPermission(PermissionStatus s) => switch (s) {
    PermissionStatus.granted ||
    PermissionStatus.limited => PermissionOutcome.granted,
    PermissionStatus.permanentlyDenied ||
    PermissionStatus.restricted => PermissionOutcome.permanentlyDenied,
    _ => PermissionOutcome.denied,
  };

  @override
  Future<PermissionOutcome> start() async {
    if (_sub != null) return PermissionOutcome.granted;
    final gen = _generation;
    final PermissionOutcome outcome;
    try {
      outcome = mapPermission(await _requestPermission());
    } catch (_) {
      // No permission plugin on this platform/device.
      return PermissionOutcome.unavailable;
    }
    if (outcome != PermissionOutcome.granted) return outcome;
    try {
      await _backend.configure();
    } catch (_) {
      return PermissionOutcome.unavailable;
    }
    // Stopped meanwhile (or another start won): do not open the camera.
    if (gen != _generation || _sub != null) return outcome;
    // Plugin stream errors (NO_MANAGER, CAMERA_ERROR, POSE_ERROR) are not
    // fatal on their own; they are reported on [failures] and the game
    // decides (it gives up when they persist without frames).
    _sub = _backend.results().listen(
      _onResult,
      onError: (Object e) {
        if (_sub != null) _failures.add(PoseSourceFailure(e));
      },
    );
    return outcome;
  }

  @override
  Stream<PoseSourceFailure> get failures => _failures.stream;

  /// Broadcast; frames arrive only between [start] and [stop].
  @override
  Stream<PoseFrame> get frames => _out.stream;

  /// Releases the camera: the plugin has no Dart stop/release call, it
  /// unbinds CameraX when its event stream loses its last listener.
  @override
  Future<void> stop() async {
    _generation++;
    final s = _sub;
    _sub = null;
    if (s == null) return;
    try {
      await s.cancel();
    } catch (_) {
      // Stopping must never throw.
    }
  }

  void _onResult(RawPoseResult r) {
    if (_sub == null) return;
    final frame = _map(r);
    if (frame != null) _out.add(frame);
  }

  PoseFrame? _map(RawPoseResult r) {
    try {
      var micros = r.timestampMs != null
          ? r.timestampMs! * 1000
          : _clock().inMicroseconds;
      if (micros <= _lastMicros) micros = _lastMicros + 1;
      _lastMicros = micros;

      final lms = r.landmarks;
      final poses = <Pose>[
        for (
          var o = 0;
          o + landmarksPerPose <= lms.length;
          o += landmarksPerPose
        )
          _pose(lms, o),
      ];

      final w = r.imageWidth, h = r.imageHeight;
      final aspect = (w != null && h != null && w > 0 && h > 0)
          ? w / h
          : (_backend.assumedAspectRatio ?? PoseFrame.defaultAspectRatio);
      return PoseFrame(
        poses,
        Duration(microseconds: micros),
        aspectRatio: aspect,
      );
    } catch (_) {
      return null;
    }
  }

  Pose _pose(List<RawPoseLandmark> lms, int offset) {
    // A pose whose landmarks carry no score at all: MediaPipe left both
    // fields empty and the plugin sends 0.0 for each (see
    // docs/pose-plugin-evaluation.md). Taking that literally would hide the
    // player from the whole game (every Pose getter gates on confidence) and
    // the child would just wait for a camera that is in fact working, so the
    // landmarks are trusted instead; the geometry checks still guard against
    // nonsense.
    var scored = false;
    for (var i = 0; i < landmarksPerPose && !scored; i++) {
      final l = lms[offset + i];
      scored = _confidence(l) > 0;
    }
    if (!scored && !_warnedUnscored) {
      _warnedUnscored = true;
      debugPrint(
        'PluginPoseFrameSource: the pose plugin reports no visibility/presence '
        'score for any landmark; treating them as fully visible.',
      );
    }
    final joints = <PoseJoint, Landmark>{};
    for (final e in blazePoseIndex.entries) {
      final l = lms[offset + e.value];
      if (!l.x.isFinite || !l.y.isFinite) continue;
      final x = landmarksMirrored ? 1 - l.x : l.x;
      joints[e.key] = Landmark(x, l.y, scored ? _confidence(l) : 1.0);
    }
    return Pose(joints);
  }

  /// The "no scores at all" note is worth one line in the log, not one a
  /// frame.
  bool _warnedUnscored = false;

  /// The lower of visibility and presence; a score the native side left at
  /// 0.0 (not filled in) is ignored in favour of the other.
  static double _confidence(RawPoseLandmark l) {
    final v = l.visibility.isFinite ? l.visibility : 0.0;
    final p = l.presence.isFinite ? l.presence : 0.0;
    if (v <= 0) return p < 0 ? 0 : p;
    if (p <= 0) return v;
    return v < p ? v : p;
  }
}
