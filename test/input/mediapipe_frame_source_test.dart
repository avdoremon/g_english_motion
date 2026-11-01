import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/mediapipe_frame_source.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/input/pose_types.dart';

const _method = MethodChannel('vn.avdoremon.g_english_motion/pose');
const _events = EventChannel('vn.avdoremon.g_english_motion/pose_frames');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MockStreamHandlerEventSink? sink;
  final calls = <MethodCall>[];
  Object? Function(MethodCall)? onCall;

  setUp(() {
    sink = null;
    calls.clear();
    onCall = (_) => 'granted';
    messenger.setMockMethodCallHandler(_method, (call) async {
      calls.add(call);
      return onCall!(call);
    });
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(onListen: (args, s) => sink = s),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_method, null);
    messenger.setMockStreamHandler(_events, null);
  });

  Map<String, Object?> lm(double x, double y, double c) => {
    'x': x,
    'y': y,
    'confidence': c,
  };

  test('maps payload to PoseFrame with exact coords and timestamp', () async {
    final src = MediapipeFrameSource();
    final got = <PoseFrame>[];
    final sub = src.frames.listen(got.add);
    await Future<void>.delayed(Duration.zero);
    sink!.success({
      'timestampMicros': 1234567,
      'poses': [
        {
          'landmarks': {
            'nose': lm(0.5, 0.25, 0.9),
            'leftHip': lm(0.4, 0.6, 0.8),
          },
        },
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(1));
    expect(got.single.timestamp, const Duration(microseconds: 1234567));
    final j = got.single.poses.single.joints;
    expect(j.keys.toSet(), {PoseJoint.nose, PoseJoint.leftHip});
    expect(j[PoseJoint.nose]!.x, 0.5);
    expect(j[PoseJoint.nose]!.y, 0.25);
    expect(j[PoseJoint.nose]!.confidence, 0.9);
    expect(j[PoseJoint.leftHip]!.y, 0.6);
    await sub.cancel();
  });

  test(
    'frameWidth/frameHeight give the aspect ratio; absent -> 16:9',
    () async {
      final src = MediapipeFrameSource();
      final got = <PoseFrame>[];
      final sub = src.frames.listen(got.add);
      await Future<void>.delayed(Duration.zero);
      sink!.success({
        'timestampMicros': 1,
        'frameWidth': 640,
        'frameHeight': 480,
        'poses': <Object>[],
      });
      sink!.success({'timestampMicros': 2, 'poses': <Object>[]});
      sink!.success({
        'timestampMicros': 3,
        'frameWidth': 0,
        'frameHeight': 480,
        'poses': <Object>[],
      });
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(3));
      expect(got[0].aspectRatio, closeTo(4 / 3, 1e-9));
      expect(got[1].aspectRatio, PoseFrame.defaultAspectRatio);
      expect(got[2].aspectRatio, PoseFrame.defaultAspectRatio);
      await sub.cancel();
    },
  );

  test('two poses preserved in order; ints accepted as numbers', () async {
    final src = MediapipeFrameSource();
    final got = <PoseFrame>[];
    final sub = src.frames.listen(got.add);
    await Future<void>.delayed(Duration.zero);
    sink!.success({
      'timestampMicros': 10,
      'poses': [
        {
          'landmarks': {'nose': lm(0.2, 0.2, 1.0)},
        },
        {
          'landmarks': {
            'nose': {'x': 1, 'y': 0, 'confidence': 1},
          },
        },
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(got.single.poses, hasLength(2));
    expect(got.single.poses[0].joints[PoseJoint.nose]!.x, 0.2);
    expect(got.single.poses[1].joints[PoseJoint.nose]!.x, 1.0);
    await sub.cancel();
  });

  test('unknown joint is ignored', () async {
    final src = MediapipeFrameSource();
    final got = <PoseFrame>[];
    final sub = src.frames.listen(got.add);
    await Future<void>.delayed(Duration.zero);
    sink!.success({
      'timestampMicros': 1,
      'poses': [
        {
          'landmarks': {'leftEar': lm(0, 0, 1), 'nose': lm(0.1, 0.1, 1)},
        },
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(got.single.poses.single.joints.keys, [PoseJoint.nose]);
    await sub.cancel();
  });

  test('malformed events are skipped and later good event arrives', () async {
    final src = MediapipeFrameSource();
    final got = <PoseFrame>[];
    final errors = <Object>[];
    final sub = src.frames.listen(got.add, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    sink!.success('garbage');
    sink!.success(null);
    sink!.success({'poses': []});
    sink!.success({'timestampMicros': 'x', 'poses': []});
    sink!.success({'timestampMicros': 1, 'poses': 'nope'});
    sink!.success({
      'timestampMicros': 1,
      'poses': [
        {
          'landmarks': {
            'nose': {'x': 'bad', 'y': 0, 'confidence': 1},
          },
        },
      ],
    });
    sink!.success({
      'timestampMicros': 99,
      'poses': [
        {
          'landmarks': {'nose': lm(0.3, 0.3, 0.7)},
        },
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);
    expect(got, hasLength(1));
    expect(got.single.timestamp, const Duration(microseconds: 99));
    await sub.cancel();
  });

  test('platform stream errors do not break the stream', () async {
    final src = MediapipeFrameSource();
    final got = <PoseFrame>[];
    final errors = <Object>[];
    final sub = src.frames.listen(got.add, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    sink!.error(code: 'X', message: 'boom');
    sink!.success({'timestampMicros': 5, 'poses': []});
    await Future<void>.delayed(Duration.zero);
    expect(errors, isEmpty);
    expect(got.single.poses, isEmpty);
    await sub.cancel();
  });

  group('start/stop', () {
    for (final e in {
      'granted': PermissionOutcome.granted,
      'denied': PermissionOutcome.denied,
      'permanentlyDenied': PermissionOutcome.permanentlyDenied,
      'weird': PermissionOutcome.denied,
    }.entries) {
      test('start maps "${e.key}"', () async {
        onCall = (_) => e.key;
        expect(await MediapipeFrameSource().start(), e.value);
      });
    }

    test('start null result -> denied', () async {
      onCall = (_) => null;
      expect(await MediapipeFrameSource().start(), PermissionOutcome.denied);
    });

    test('start passes defaults numPoses=2 frontCamera=true', () async {
      await MediapipeFrameSource().start();
      expect(calls.single.method, 'start');
      expect(calls.single.arguments, {'numPoses': 2, 'frontCamera': true});
    });

    test('start passes custom options', () async {
      await MediapipeFrameSource(numPoses: 1, frontCamera: false).start();
      expect(calls.single.arguments, {'numPoses': 1, 'frontCamera': false});
    });

    for (final e in {
      'PERMISSION_DENIED': PermissionOutcome.denied,
      'PERMISSION_PERMANENTLY_DENIED': PermissionOutcome.permanentlyDenied,
      'OTHER': PermissionOutcome.denied,
    }.entries) {
      test('PlatformException ${e.key} -> ${e.value}', () async {
        onCall = (_) => throw PlatformException(code: e.key);
        expect(await MediapipeFrameSource().start(), e.value);
      });
    }

    test('MissingPluginException -> unavailable, no throw', () async {
      messenger.setMockMethodCallHandler(_method, null);
      expect(
        await MediapipeFrameSource().start(),
        PermissionOutcome.unavailable,
      );
    });

    test('stop invokes stop and swallows errors', () async {
      await MediapipeFrameSource().stop();
      expect(calls.single.method, 'stop');
      onCall = (_) => throw PlatformException(code: 'E');
      await MediapipeFrameSource().stop();
    });
  });

  test('custom channel instances are used', () async {
    const m = MethodChannel('x/m');
    const ev = EventChannel('x/e');
    String? seen;
    messenger.setMockMethodCallHandler(m, (c) async {
      seen = c.method;
      return 'granted';
    });
    final src = MediapipeFrameSource(methodChannel: m, eventChannel: ev);
    expect(await src.start(), PermissionOutcome.granted);
    expect(seen, 'start');
    messenger.setMockMethodCallHandler(m, null);
  });
}
