import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/jump_detector.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/input/pose_session.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

const calibration = Calibration(
  torsoHeight: 0.3,
  centerX: 0.5,
  baselineHipY: 0.6,
  baselineShoulderY: 0.3,
);

Duration ms(int v) => Duration(milliseconds: v);

Future<List<GameInputEvent>> run(
  List<PoseFrame> frames, {
  ConfirmGesture confirm = ConfirmGesture.jump,
  int laneCount = 3,
}) async {
  final source = FakePoseFrameSource(frames);
  final session = PoseSession(
    source.frames,
    calibration,
    laneCount: laneCount,
    confirm: confirm,
  );
  final events = await session.events.toList(); // closes when frames end
  await session.dispose();
  return events;
}

/// One person: x(t) and lift(t) driven by closures, 30 fps.
List<PoseFrame> motion(
  Duration duration, {
  double Function(Duration t)? hipX,
  double Function(Duration t)? lift,
}) {
  return poseSequence(
    duration: duration,
    posesAt: (t) => [
      makePose(hipX: hipX?.call(t) ?? 0.5, hipY: 0.6 - (lift?.call(t) ?? 0)),
    ],
  );
}

/// Half-sine jump of 0.06 over 500 ms starting at [start].
double Function(Duration) jumpAt(Duration start) => (t) {
  final s = (t - start).inMicroseconds;
  if (s < 0 || s > 500000) return 0;
  return 0.06 * math.sin(math.pi * s / 500000);
};

/// First timestamp where a raw (unfiltered) JumpDetector fires.
Duration? rawCrossing(List<PoseFrame> frames) {
  final d = JumpDetector(calibration);
  for (final f in frames) {
    if (d.update(f.poses.first, f.timestamp)) return f.timestamp;
  }
  return null;
}

void main() {
  test(
    'jump yields one Confirmed(lane 1) at the crossing frame timestamp',
    () async {
      final frames = jumpSequence(jumps: 1);
      final events = await run(frames);
      final confirmed = events.whereType<Confirmed>().toList();
      expect(confirmed, hasLength(1));
      expect(confirmed.single.lane, 1);
      expect(frames.map((f) => f.timestamp), contains(confirmed.single.at));
      final raw = rawCrossing(frames)!;
      expect(confirmed.single.at - raw, lessThanOrEqualTo(ms(70)));
      expect(confirmed.single.at, greaterThanOrEqualTo(raw));
      expect(events.whereType<LaneChanged>(), isEmpty);
    },
  );

  test('stepping right yields LaneChanged(2)', () async {
    final frames = motion(ms(3000), hipX: (t) => t < ms(1500) ? 0.5 : 0.3);
    final events = await run(frames);
    final lanes = events.whereType<LaneChanged>().toList();
    expect(lanes.map((e) => e.lane), [2]);
    expect(events.whereType<Confirmed>(), isEmpty);
  });

  test(
    'hips drifting to another lane mid-air keep the pre-jump lane',
    () async {
      // Step right (lane 2), stand, then jump while drifting back to lane 1
      // starting 150 ms after takeoff.
      final takeoff = ms(3000);
      final frames = motion(
        ms(5000),
        hipX: (t) {
          if (t < ms(1000)) return 0.5;
          if (t < takeoff + ms(150)) return 0.3;
          return 0.5;
        },
        lift: jumpAt(takeoff),
      );
      final events = await run(frames);
      expect(events.whereType<LaneChanged>().map((e) => e.lane), [2, 1]);
      final confirmed = events.whereType<Confirmed>().toList();
      expect(confirmed, hasLength(1));
      expect(confirmed.single.lane, 2);
    },
  );

  test(
    'no pose for 600 ms -> PlayerLost, then PlayerFound without Confirmed',
    () async {
      final stand = standingSequence(duration: ms(1500));
      final gap = poseSequence(
        duration: ms(600),
        start: ms(1500),
        posesAt: (_) => [],
      );
      // Back while mid-jump-ish: player present and already lifted high.
      final back = poseSequence(
        duration: ms(1000),
        start: ms(2100),
        posesAt: (_) => [makePose(hipY: 0.52)],
      );
      final events = await run([...stand, ...gap, ...back]);
      expect(events.whereType<PlayerLost>(), hasLength(1));
      expect(events.whereType<PlayerFound>(), hasLength(1));
      expect(
        events.indexWhere((e) => e is PlayerLost),
        lessThan(events.indexWhere((e) => e is PlayerFound)),
      );
      expect(
        events.whereType<PlayerLost>().single.at,
        greaterThanOrEqualTo(ms(1466) + ms(500)),
      );
      expect(events.whereType<Confirmed>(), isEmpty);
      expect(events.whereType<PlayerFound>().single.at, ms(2100));
    },
  );

  test('a nearer second person does not steal tracking', () async {
    final other = makePose(hipX: 0.85, hipY: 0.8, torso: 0.45);
    final base = jumpSequence(jumps: 1);
    for (final first in [false, true]) {
      final events = await run(withExtraPerson(base, other, first: first));
      expect(events.whereType<Confirmed>(), hasLength(1));
      expect(events.whereType<Confirmed>().single.lane, 1);
      expect(events.whereType<LaneChanged>(), isEmpty);
      expect(events.whereType<PlayerLost>(), isEmpty);
    }
  });

  test('second person jumping and raising hands produces no events', () async {
    final frames = poseSequence(
      duration: ms(4000),
      posesAt: (t) {
        final lift = jumpAt(ms(1500))(t);
        return [
          makePose(),
          makePose(
            hipX: 0.85,
            hipY: 0.8 - lift * 1.5,
            torso: 0.45,
            leftWrist: const Offset(0.8, 0.05),
            rightWrist: const Offset(0.9, 0.05),
          ),
        ];
      },
    );
    for (final gesture in ConfirmGesture.values) {
      final events = await run(frames, confirm: gesture);
      expect(events, isEmpty, reason: '$gesture');
    }
  });

  test(
    'two-person scene: only the child (calibrated person) is reported',
    () async {
      // Child: small torso near centre, jumps. Adult: large, off to the side,
      // also jumps harder and lifts both hands.
      final frames = poseSequence(
        duration: ms(4000),
        posesAt: (t) => [
          makePose(
            hipX: 0.15,
            hipY: 0.85 - jumpAt(ms(2000))(t) * 2,
            torso: 0.5,
          ),
          makePose(hipY: 0.6 - jumpAt(ms(1500))(t)),
        ],
      );
      final events = await run(frames);
      final confirmed = events.whereType<Confirmed>().toList();
      expect(confirmed, hasLength(1));
      expect(confirmed.single.at, lessThan(ms(1800)));
      expect(events.whereType<LaneChanged>(), isEmpty);
    },
  );

  test(
    'low hip confidence exactly at the crossing frame -> no Confirmed',
    () async {
      final frames = jumpSequence(jumps: 1);
      final clean = await run(frames);
      final at = clean.whereType<Confirmed>().single.at;
      final idx = frames.indexWhere((f) => f.timestamp == at);
      final degraded = replacePoseAt(
        frames,
        idx,
        (f) => [makePose(hipY: f.poses.first.midHipY!, confidence: 0.3)],
      );
      final events = await run(degraded);
      expect(events.whereType<Confirmed>(), isEmpty);
    },
  );

  test('raiseHands gesture confirms on raised hands, jump does not', () async {
    final hands = poseSequence(
      duration: ms(3000),
      posesAt: (t) => [
        t >= ms(1000) && t < ms(2500)
            ? makePose(
                leftWrist: const Offset(0.4, 0.1),
                rightWrist: const Offset(0.6, 0.1),
              )
            : makePose(),
      ],
    );
    final events = await run(hands, confirm: ConfirmGesture.raiseHands);
    expect(events.whereType<Confirmed>(), hasLength(1));

    final jumped = await run(
      jumpSequence(jumps: 1),
      confirm: ConfirmGesture.raiseHands,
    );
    expect(jumped.whereType<Confirmed>(), isEmpty);
  });

  test('suppressConfirmUntil blocks Confirmed until the given time', () async {
    final frames = jumpSequence(jumps: 1);
    final session = PoseSession(
      FakePoseFrameSource(frames).frames,
      calibration,
      laneCount: 3,
    )..suppressConfirmUntil(const Duration(seconds: 10));
    final events = await session.events.toList();
    await session.dispose();
    expect(events.whereType<Confirmed>(), isEmpty);
  });

  test('setLaneCount and currentLane', () async {
    final session = PoseSession(
      FakePoseFrameSource(standingSequence(duration: ms(300))).frames,
      calibration,
      laneCount: 3,
    );
    expect(session.currentLane, 1);
    session.setLaneCount(1);
    expect(session.currentLane, 0);
    await session.events.toList();
    await session.dispose();
  });
}
