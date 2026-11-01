import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/plugin_pose_frame_source.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:permission_handler/permission_handler.dart';

/// Stands in for the plugin: subscribing to [results] is "camera on",
/// cancelling is "camera released" (that is how the real plugin behaves).
class FakeBackend implements PoseLandmarkerBackend {
  FakeBackend({this.assumedAspectRatio});

  Object? configureError;
  int configures = 0;
  int listens = 0;
  int cancels = 0;
  StreamController<RawPoseResult>? _ctl;

  @override
  final double? assumedAspectRatio;

  @override
  Future<void> configure() async {
    configures++;
    final e = configureError;
    if (e != null) throw e;
  }

  @override
  Stream<RawPoseResult> results() {
    final c = StreamController<RawPoseResult>(
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
    _ctl = c;
    return c.stream;
  }

  bool get cameraLive => _ctl?.hasListener ?? false;

  void emit(RawPoseResult r) => _ctl!.add(r);
  void fail(Object e) => _ctl!.addError(e);
}

RawPoseLandmark _lm(double x, double y, {double v = 0.9, double p = 0.8}) =>
    RawPoseLandmark(x: x, y: y, visibility: v, presence: p);

/// A full 33-landmark BlazePose body; landmark i sits at (i/100, i/50).
List<RawPoseLandmark> body([Map<int, RawPoseLandmark> overrides = const {}]) =>
    [for (var i = 0; i < 33; i++) overrides[i] ?? _lm(i / 100, i / 50)];

RawPoseResult result(
  List<RawPoseLandmark> lms, {
  int? ts = 1000,
  int? w,
  int? h,
}) => RawPoseResult(
  timestampMs: ts,
  landmarks: lms,
  imageWidth: w,
  imageHeight: h,
);

void main() {
  late FakeBackend backend;
  late PermissionStatus status;
  late int permissionRequests;

  PluginPoseFrameSource source({
    bool mirrored = false,
    Duration Function()? clock,
    Future<PermissionStatus> Function()? request,
  }) => PluginPoseFrameSource(
    backend: backend,
    requestPermission:
        request ??
        () async {
          permissionRequests++;
          return status;
        },
    landmarksMirrored: mirrored,
    clock: clock,
  );

  setUp(() {
    backend = FakeBackend();
    status = PermissionStatus.granted;
    permissionRequests = 0;
  });

  Future<List<PoseFrame>> collect(
    PluginPoseFrameSource src,
    void Function() emit,
  ) async {
    final got = <PoseFrame>[];
    final sub = src.frames.listen(got.add);
    emit();
    await pumpEventQueue();
    await sub.cancel();
    return got;
  }

  group('mapping', () {
    test('BlazePose indices map onto PoseJoint', () async {
      final src = source();
      expect(await src.start(), PermissionOutcome.granted);
      final got = await collect(src, () => backend.emit(result(body())));
      expect(got, hasLength(1));
      expect(got.single.poses, hasLength(1));
      final j = got.single.poses.single.joints;
      const expected = {
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
      expect(j.keys.toSet(), PoseJoint.values.toSet());
      for (final e in expected.entries) {
        expect(j[e.key]!.x, closeTo(e.value / 100, 1e-12), reason: '${e.key}');
        expect(j[e.key]!.y, closeTo(e.value / 50, 1e-12), reason: '${e.key}');
      }
    });

    test('confidence is the lower of visibility and presence', () async {
      final src = source();
      await src.start();
      final got = await collect(
        src,
        () => backend.emit(
          result(
            body({
              0: _lm(0.5, 0.1, v: 0.3, p: 0.9),
              23: _lm(0.4, 0.6, v: 0.95, p: 0.6),
              // A score the native side did not fill in arrives as 0.0: the
              // other one is used.
              24: _lm(0.6, 0.6, v: 0.0, p: 0.7),
              25: _lm(0.4, 0.8, v: 0.0, p: 0.0),
            }),
          ),
        ),
      );
      final j = got.single.poses.single.joints;
      expect(j[PoseJoint.nose]!.confidence, closeTo(0.3, 1e-9));
      expect(j[PoseJoint.leftHip]!.confidence, closeTo(0.6, 1e-9));
      expect(j[PoseJoint.rightHip]!.confidence, closeTo(0.7, 1e-9));
      expect(j[PoseJoint.leftKnee]!.confidence, 0.0);
    });

    test('unmirrored landmarks pass through; mirrored ones are flipped '
        'back so x is in the unmirrored image', () async {
      final plain = source();
      await plain.start();
      final a = await collect(
        plain,
        () => backend.emit(result(body({23: _lm(0.2, 0.6)}))),
      );
      expect(a.single.poses.single.joints[PoseJoint.leftHip]!.x, 0.2);
      await plain.stop();

      final flipped = source(mirrored: true);
      await flipped.start();
      final b = await collect(
        flipped,
        () => backend.emit(result(body({23: _lm(0.2, 0.6)}))),
      );
      final hip = b.single.poses.single.joints[PoseJoint.leftHip]!;
      expect(hip.x, closeTo(0.8, 1e-12));
      expect(hip.y, 0.6, reason: 'y is never flipped');
    });

    test(
      'no person: a frame with no poses (the camera is still alive)',
      () async {
        final src = source();
        await src.start();
        final got = await collect(src, () => backend.emit(result(const [])));
        expect(got.single.poses, isEmpty);
      },
    );

    test('landmarks are split per 33 (flattened multi-pose); a partial '
        'tail is ignored', () async {
      final src = source();
      await src.start();
      final second = body({23: _lm(0.9, 0.6)});
      final got = await collect(src, () {
        backend.emit(result([...body(), ...second]));
        backend.emit(result([...body(), ...body().take(7)], ts: 2000));
      });
      expect(got[0].poses, hasLength(2));
      expect(got[0].poses[1].joints[PoseJoint.leftHip]!.x, 0.9);
      expect(got[1].poses, hasLength(1));
    });

    test('non-finite coordinates drop only that joint', () async {
      final src = source();
      await src.start();
      final got = await collect(
        src,
        () => backend.emit(result(body({0: _lm(double.nan, 0.1)}))),
      );
      final j = got.single.poses.single.joints;
      expect(j.containsKey(PoseJoint.nose), isFalse);
      expect(j.containsKey(PoseJoint.leftHip), isTrue);
    });

    test(
      'plugin ms timestamps become strictly increasing microseconds',
      () async {
        final src = source();
        await src.start();
        final got = await collect(src, () {
          backend.emit(result(body(), ts: 5000));
          backend.emit(result(body(), ts: 5000)); // same millisecond
          backend.emit(result(body(), ts: 4999)); // out of order
          backend.emit(result(body(), ts: 5040));
        });
        expect(got.map((f) => f.timestamp.inMicroseconds), [
          5000000,
          5000001,
          5000002,
          5040000,
        ]);
      },
    );

    test('without a plugin timestamp the monotonic clock is used', () async {
      var now = const Duration(milliseconds: 70);
      final src = source(clock: () => now);
      await src.start();
      final got = <PoseFrame>[];
      final sub = src.frames.listen(got.add);
      backend.emit(result(body(), ts: null));
      await pumpEventQueue();
      now = const Duration(milliseconds: 90);
      backend.emit(result(body(), ts: null));
      await pumpEventQueue();
      await sub.cancel();
      expect(got.map((f) => f.timestamp), [
        const Duration(milliseconds: 70),
        const Duration(milliseconds: 90),
      ]);
    });

    test('aspect ratio: image size when sent, else the backend assumption, '
        'else the default', () async {
      backend = FakeBackend(assumedAspectRatio: 4 / 3);
      final src = source();
      await src.start();
      final got = await collect(src, () {
        backend.emit(result(body(), w: 1280, h: 720));
        backend.emit(result(body(), ts: 2000));
        backend.emit(result(body(), ts: 3000, w: 0, h: 480));
      });
      expect(got[0].aspectRatio, closeTo(16 / 9, 1e-12));
      expect(got[1].aspectRatio, closeTo(4 / 3, 1e-12));
      expect(got[2].aspectRatio, closeTo(4 / 3, 1e-12));

      backend = FakeBackend();
      final plain = source();
      await plain.start();
      final g2 = await collect(plain, () => backend.emit(result(body())));
      expect(g2.single.aspectRatio, PoseFrame.defaultAspectRatio);
    });

    test('backend stream errors are forwarded as failures and frames keep '
        'flowing', () async {
      final src = source();
      await src.start();
      final failures = <PoseSourceFailure>[];
      final sub = src.failures.listen(failures.add);
      addTearDown(sub.cancel);
      final got = await collect(src, () {
        backend.fail(PlatformException(code: 'POSE_ERROR'));
        backend.emit(result(body()));
      });
      expect(got, hasLength(1));
      expect(failures, hasLength(1));
      expect((failures.single.error as PlatformException).code, 'POSE_ERROR');
    });
  });

  group('permission and start', () {
    test('granted: configures the plugin and opens the camera', () async {
      final src = source();
      expect(await src.start(), PermissionOutcome.granted);
      expect(permissionRequests, 1);
      expect(backend.configures, 1);
      expect(backend.cameraLive, isTrue);
    });

    for (final e in {
      PermissionStatus.denied: PermissionOutcome.denied,
      PermissionStatus.permanentlyDenied: PermissionOutcome.permanentlyDenied,
      PermissionStatus.restricted: PermissionOutcome.permanentlyDenied,
    }.entries) {
      test('${e.key.name} → ${e.value.name}, camera stays off', () async {
        status = e.key;
        final src = source();
        expect(await src.start(), e.value);
        expect(backend.configures, 0);
        expect(backend.listens, 0);
      });
    }

    test('limited counts as granted', () async {
      status = PermissionStatus.limited;
      expect(await source().start(), PermissionOutcome.granted);
    });

    test('the permission plugin failing ⇒ unavailable', () async {
      final src = source(
        request: () async => throw MissingPluginException('no handler'),
      );
      expect(await src.start(), PermissionOutcome.unavailable);
      expect(backend.listens, 0);
    });

    for (final err in <Object>[
      MissingPluginException('pose plugin absent'),
      PlatformException(code: 'INIT_FAILED'),
      StateError('model failed'),
    ]) {
      test('pose plugin failing to initialise (${err.runtimeType}) ⇒ '
          'unavailable, camera stays off', () async {
        backend.configureError = err;
        final src = source();
        expect(await src.start(), PermissionOutcome.unavailable);
        expect(backend.listens, 0);
      });
    }

    test(
      'a second start while running does not open the camera twice',
      () async {
        final src = source();
        await src.start();
        expect(await src.start(), PermissionOutcome.granted);
        expect(backend.listens, 1);
      },
    );

    test(
      'stop during an in-flight start: the camera is never opened',
      () async {
        final gate = Completer<PermissionStatus>();
        final src = source(request: () => gate.future);
        final starting = src.start();
        await src.stop();
        gate.complete(PermissionStatus.granted);
        await starting;
        expect(backend.listens, 0);
      },
    );
  });

  group('stop', () {
    test('releases the camera (cancels the plugin stream)', () async {
      final src = source();
      await src.start();
      await src.stop();
      expect(backend.cancels, 1);
      expect(backend.cameraLive, isFalse);
    });

    test('is idempotent and safe before start', () async {
      final src = source();
      await src.stop();
      await src.start();
      await src.stop();
      await src.stop();
      expect(backend.cancels, 1);
    });

    test('no frames are delivered after stop', () async {
      final src = source();
      await src.start();
      final got = <PoseFrame>[];
      final sub = src.frames.listen(got.add);
      backend.emit(result(body()));
      await pumpEventQueue();
      final ctl = backend._ctl!;
      await src.stop();
      // A late native event after the release must not reach the game.
      if (!ctl.isClosed) ctl.add(result(body(), ts: 9000));
      await pumpEventQueue();
      expect(got, hasLength(1));
      await sub.cancel();
    });

    test(
      'start after stop opens the camera again (retry / next level)',
      () async {
        final src = source();
        await src.start();
        await src.stop();
        expect(await src.start(), PermissionOutcome.granted);
        expect(backend.listens, 2);
        expect(backend.cameraLive, isTrue);
        final got = await collect(src, () => backend.emit(result(body())));
        expect(got, hasLength(1));
      },
    );
  });
}
