import 'dart:async';
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
  bool cursor = false,
  bool pull = false,
}) async {
  final source = FakePoseFrameSource(frames);
  final session = PoseSession(
    source.frames,
    calibration,
    laneCount: laneCount,
    confirm: confirm,
    cursor: cursor,
    pull: pull,
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
  int fps = 30,
}) {
  return poseSequence(
    duration: duration,
    fps: fps,
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

  test('lane width follows the frame aspect ratio carried by frames', () async {
    List<PoseFrame> still(double aspect) => [
      for (var i = 0; i < 60; i++)
        PoseFrame([makePose(hipX: 0.4)], ms(i * 33), aspectRatio: aspect),
    ];
    // Mirrored x = 0.6: inside lane 1 for a square frame (width 0.18) but
    // lane 2 for 16:9 (width 0.101).
    expect((await run(still(1.0))).whereType<LaneChanged>(), isEmpty);
    expect(
      (await run(still(16 / 9))).whereType<LaneChanged>().map((e) => e.lane),
      [2],
    );
  });

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

  test('re-acquires a player who returns far from the last position', () async {
    final frames = motion(
      ms(6000),
      hipX: (t) => t < ms(1000) ? 0.5 : (t < ms(2000) ? 0.5 : 0.9),
      lift: jumpAt(ms(4000)),
    );
    // Gap: nobody between 1000 and 2000 ms.
    final gapped = [
      for (final f in frames)
        if (f.timestamp >= ms(1000) && f.timestamp < ms(2000))
          PoseFrame(const [], f.timestamp)
        else
          f,
    ];
    final events = await run(gapped);
    expect(events.whereType<PlayerLost>(), hasLength(1));
    expect(events.whereType<PlayerFound>(), hasLength(1));
    expect(events.whereType<LaneChanged>().map((e) => e.lane), [0]);
    final confirmed = events.whereType<Confirmed>().toList();
    expect(confirmed, hasLength(1));
    expect(confirmed.single.lane, 0);
  });

  test(
    'frame-stream errors and handler exceptions reach events as errors',
    () async {
      final c = StreamController<PoseFrame>();
      final session = PoseSession(c.stream, calibration, laneCount: 3);
      final received = <Object>[];
      final done = Completer<void>();
      session.events.listen(
        received.add,
        onError: received.add,
        onDone: done.complete,
      );
      final stand = standingSequence(duration: ms(300));
      c.add(stand.first);
      c.addError(StateError('stream boom'));
      c.add(PoseFrame([_ThrowingPose()], ms(400)));
      // Session keeps working: a full jump afterwards still confirms.
      final jump = jumpSequence(jumps: 1);
      for (final f in jump) {
        c.add(PoseFrame(f.poses, f.timestamp + ms(500)));
      }
      await c.close();
      await done.future;
      await session.dispose();
      expect(received.whereType<StateError>(), hasLength(1));
      expect(received.whereType<UnimplementedError>(), hasLength(1));
      expect(received.whereType<Confirmed>(), hasLength(1));
    },
  );

  test(
    'child hip confidence dip does not hand tracking to a bystander',
    () async {
      final frames = poseSequence(
        duration: ms(4000),
        posesAt: (t) {
          final dip = t >= ms(1500) && t < ms(1700);
          return [
            makePose(
              hipY: 0.6 - jumpAt(ms(1500))(t),
              confidence: dip ? 0.3 : 1.0,
            ),
            // Bystander inside the gate, hips reliable, lifted differently.
            makePose(hipX: 0.62, hipY: 0.6 - jumpAt(ms(2500))(t) * 2),
          ];
        },
      );
      final events = await run(frames);
      // Bystander's jump (at 2500) must produce nothing, and no loss/found.
      expect(
        events.whereType<Confirmed>().where((e) => e.at > ms(2400)),
        isEmpty,
      );
      expect(events.whereType<LaneChanged>(), isEmpty);
      expect(events.whereType<PlayerLost>(), isEmpty);
      expect(events.whereType<PlayerFound>(), isEmpty);
    },
  );

  test(
    'hands raised before a gap cannot confirm on the first frame back',
    () async {
      final frames = poseSequence(
        duration: ms(3000),
        posesAt: (t) {
          if (t >= ms(1400) && t < ms(2000)) return [];
          final up = t >= ms(1000) && t < ms(2300);
          return [
            up
                ? makePose(
                    leftWrist: const Offset(0.4, 0.1),
                    rightWrist: const Offset(0.6, 0.1),
                  )
                : makePose(),
          ];
        },
      );
      final events = await run(frames, confirm: ConfirmGesture.raiseHands);
      expect(events.whereType<PlayerFound>(), hasLength(1));
      expect(events.whereType<Confirmed>(), isEmpty);
    },
  );

  group('persistent frame errors', () {
    // Collects events and errors from a manually fed session.
    Future<({List<GameInputEvent> events, List<Object> errors})> feed(
      List<PoseFrame> frames,
    ) async {
      final c = StreamController<PoseFrame>();
      final session = PoseSession(c.stream, calibration, laneCount: 3);
      final events = <GameInputEvent>[];
      final errors = <Object>[];
      final done = Completer<void>();
      session.events.listen(
        events.add,
        onError: errors.add,
        onDone: done.complete,
      );
      frames.forEach(c.add);
      await c.close();
      await done.future;
      await session.dispose();
      return (events: events, errors: errors);
    }

    PoseFrame boom(int t) => PoseFrame([_ThrowingPose()], ms(t));

    test('frames that keep throwing for >= 500 ms yield PlayerLost, then '
        'PlayerFound when a good frame returns', () async {
      final stand = standingSequence(duration: ms(1000), fps: 15);
      final r = await feed([
        ...stand,
        for (var t = 1000; t <= 1800; t += 67) boom(t),
        ...standingSequence(duration: ms(600), fps: 15, start: ms(1867)),
      ]);
      expect(r.errors, isNotEmpty);
      expect(r.events.whereType<PlayerLost>(), hasLength(1));
      expect(r.events.whereType<PlayerFound>(), hasLength(1));
      expect(
        r.events.whereType<PlayerLost>().single.at,
        greaterThanOrEqualTo(ms(1500)),
      );
    });

    test('a few throwing frames (< 500 ms) do not yield PlayerLost', () async {
      final r = await feed([
        ...standingSequence(duration: ms(1000), fps: 15),
        boom(1000),
        boom(1067),
        boom(1134),
        ...standingSequence(duration: ms(600), fps: 15, start: ms(1200)),
      ]);
      expect(r.errors, hasLength(3));
      expect(r.events.whereType<PlayerLost>(), isEmpty);
    });

    test('a good frame between throwing ones restarts the count', () async {
      final r = await feed([
        ...standingSequence(duration: ms(1000), fps: 15),
        for (var t = 1000; t <= 1400; t += 67) boom(t),
        PoseFrame([makePose()], ms(1467)),
        for (var t = 1534; t <= 1934; t += 67) boom(t),
      ]);
      expect(r.events.whereType<PlayerLost>(), isEmpty);
    });
  });

  group('re-acquisition while lost', () {
    // Child present 0..1000, nobody 1000..1700 (lost), then [after].
    List<PoseFrame> scene(List<Pose> Function(Duration t) after) => [
      ...standingSequence(duration: ms(1000), fps: 15),
      ...poseSequence(
        duration: ms(700),
        fps: 15,
        start: ms(1000),
        posesAt: (_) => const [],
      ),
      ...poseSequence(
        duration: ms(1400),
        fps: 15,
        start: ms(1700),
        posesAt: after,
      ),
    ];

    test('a much larger bystander near the centre is not adopted', () async {
      final events = await run(
        scene((_) => [makePose(hipX: 0.55, hipY: 0.7, torso: 0.5)]),
      );
      expect(events.whereType<PlayerLost>(), hasLength(1));
      expect(events.whereType<PlayerFound>(), isEmpty);
      expect(events.whereType<Confirmed>(), isEmpty);
      expect(events.whereType<LaneChanged>(), isEmpty);
    });

    test('a much smaller bystander is not adopted either', () async {
      final events = await run(
        scene((_) => [makePose(hipX: 0.45, hipY: 0.6, torso: 0.15)]),
      );
      expect(events.whereType<PlayerFound>(), isEmpty);
    });

    test(
      'the child (torso within 35%) is re-adopted next to a bystander',
      () async {
        final events = await run(
          scene(
            (_) => [
              makePose(hipX: 0.5, hipY: 0.7, torso: 0.5),
              makePose(hipX: 0.62, torso: 0.36), // 20% larger: accepted
            ],
          ),
        );
        expect(events.whereType<PlayerFound>(), hasLength(1));
      },
    );

    test('a torso 40% off the calibrated one is rejected', () async {
      final events = await run(
        scene((_) => [makePose(hipX: 0.5, torso: 0.3 * 1.4)]),
      );
      expect(events.whereType<PlayerFound>(), isEmpty);
    });

    // The jump baseline is stale while the child is away: it must be
    // re-taken on re-acquisition and nothing graded during the grace.
    test(
      'a gradual walk back into frame confirms nothing (15 fps)',
      () async {
        // Stand 2 s, nobody for 1 s, then walk back over 600 ms ending 0.05
        // higher in the image (0.05 > 0.12 * 0.3 torso) and stay there.
        final frames = [
          ...standingSequence(duration: ms(2000), fps: 15),
          ...poseSequence(
            duration: ms(1000),
            fps: 15,
            start: ms(2000),
            posesAt: (_) => const [],
          ),
          ...poseSequence(
            duration: ms(2500),
            fps: 15,
            start: ms(3000),
            posesAt: (t) {
              final s = (t - ms(3000)).inMilliseconds.clamp(0, 600) / 600;
              return [makePose(hipY: 0.6 - 0.05 * s)];
            },
          ),
        ];
        final events = await run(frames);
        expect(events.whereType<PlayerFound>(), hasLength(1));
        expect(
          events.whereType<Confirmed>(),
          isEmpty,
          reason: 'walking back into position is not a jump',
        );
      },
    );

    test(
      'a real jump just after the grace confirms, even when the child '
      'returns higher in the frame (15 fps)',
      () async {
        // Returns 0.08 higher than the pre-loss baseline: with a stale
        // baseline that offset alone latches the detector and the jump at
        // 3550 ms is swallowed.
        double jump(Duration t) {
          final s = (t - ms(3550)).inMilliseconds;
          if (s < 0 || s > 500) return 0;
          return 0.04 * math.sin(math.pi * s / 500);
        }

        final frames = [
          ...standingSequence(duration: ms(2000), fps: 15),
          ...poseSequence(
            duration: ms(1000),
            fps: 15,
            start: ms(2000),
            posesAt: (_) => const [],
          ),
          ...poseSequence(
            duration: ms(1500),
            fps: 15,
            start: ms(3000),
            posesAt: (t) => [makePose(hipY: 0.52 - jump(t))],
          ),
        ];
        final events = await run(frames);
        expect(events.whereType<PlayerFound>(), hasLength(1));
        final confirmed = events.whereType<Confirmed>().toList();
        expect(confirmed, hasLength(1));
        expect(
          confirmed.single.at,
          greaterThanOrEqualTo(ms(3500)),
          reason: 'nothing is graded during the 500 ms re-acquire grace',
        );
      },
    );
  });

  group('15 fps (single-pose plugin)', () {
    test('a jump of rise 0.04 confirms exactly once with lane 1', () async {
      final frames = jumpSequence(jumps: 1, rise: 0.04, fps: 15, noise: 0);
      final events = await run(frames);
      final confirmed = events.whereType<Confirmed>().toList();
      expect(confirmed, hasLength(1));
      expect(confirmed.single.lane, 1);
      expect(events.whereType<LaneChanged>(), isEmpty);
    });

    test('three jumps of rise 0.04 -> three Confirmed', () async {
      final frames = jumpSequence(jumps: 3, rise: 0.04, fps: 15, noise: 0);
      expect((await run(frames)).whereType<Confirmed>(), hasLength(3));
    });

    test('stepping to another lane and jumping confirms that lane', () async {
      final frames = motion(
        ms(5000),
        fps: 15,
        hipX: (t) => t < ms(1500) ? 0.5 : 0.3,
        lift: (t) {
          final s = (t - ms(3000)).inMilliseconds;
          return s < 0 || s > 500 ? 0 : 0.04 * math.sin(math.pi * s / 500);
        },
      );
      final events = await run(frames);
      expect(events.whereType<LaneChanged>().map((e) => e.lane), [2]);
      final confirmed = events.whereType<Confirmed>().toList();
      expect(confirmed, hasLength(1));
      expect(confirmed.single.lane, 2);
    });

    test('a step 0-150 ms before takeoff confirms the lane stepped INTO', () async {
      // Takeoff at 3000 ms, rise 0.06: the threshold crossing lands ~130 ms
      // later, so a fixed 250 ms look-back queries the lane ~120 ms BEFORE
      // takeoff and misses a step that is already settled.
      for (final step in [2850, 2900, 2950, 3000]) {
        final frames = motion(
          ms(5000),
          fps: 15,
          hipX: (t) => t < ms(step) ? 0.5 : 0.68,
          lift: (t) {
            final s = (t - ms(3000)).inMilliseconds;
            return s < 0 || s > 500 ? 0 : 0.06 * math.sin(math.pi * s / 500);
          },
        );
        final events = await run(frames);
        expect(
          events.whereType<LaneChanged>().map((e) => e.lane),
          [0],
          reason: 'step at $step',
        );
        final confirmed = events.whereType<Confirmed>().toList();
        expect(confirmed, hasLength(1), reason: 'step at $step');
        expect(confirmed.single.lane, 0, reason: 'step at $step');
      }
    });

    test('a slow walk toward the camera never confirms', () async {
      final frames = motion(
        ms(8000),
        fps: 15,
        lift: (t) {
          final s = t.inMilliseconds / 1000;
          return s < 1 ? 0 : (s < 4 ? 0.02 * (s - 1) : 0.06);
        },
      );
      expect((await run(frames)).whereType<Confirmed>(), isEmpty);
    });
  });

  group('raise-hands confidence', () {
    // Wrists detected with confidence 0.6, everything else 1.0.
    List<PoseFrame> hands() => poseSequence(
      duration: ms(3000),
      fps: 15,
      posesAt: (t) {
        final base = makePose(
          leftWrist: const Offset(0.4, 0.1),
          rightWrist: const Offset(0.6, 0.1),
        );
        if (t < ms(1000) || t >= ms(2500)) return [makePose()];
        return [
          Pose({
            ...base.joints,
            PoseJoint.leftWrist: const Landmark(0.4, 0.1, 0.6),
            PoseJoint.rightWrist: const Landmark(0.6, 0.1, 0.6),
          }),
        ];
      },
    );

    Future<List<GameInputEvent>> withMin(double minConfidence) async {
      final session = PoseSession(
        FakePoseFrameSource(hands()).frames,
        calibration,
        laneCount: 3,
        confirm: ConfirmGesture.raiseHands,
        minConfidence: minConfidence,
      );
      final events = await session.events.toList();
      await session.dispose();
      return events;
    }

    test(
      'the session minConfidence is used by the raise-hands detector',
      () async {
        expect((await withMin(0.5)).whereType<Confirmed>(), hasLength(1));
        expect((await withMin(0.7)).whereType<Confirmed>(), isEmpty);
      },
    );
  });

  group('pull', () {
    // Left wrist: down 0.15 over 300 ms and back up, starting at 200 ms.
    double leftY(Duration t) {
      final s = t.inMilliseconds - 200;
      if (s < 0 || s >= 600) return 0.3;
      return s < 300
          ? 0.3 + 0.15 * s / 300
          : 0.3 + 0.15 * (1 - (s - 300) / 300);
    }

    List<PoseFrame> pulling() => poseSequence(
      duration: const Duration(milliseconds: 1500),
      posesAt: (t) => [makePose(leftWrist: Offset(0.4, leftY(t)))],
    );

    test('a pull beat of the left wrist is emitted as Pulled(left)', () async {
      final ev = await run(pulling(), pull: true);
      expect(ev.whereType<Pulled>().map((e) => e.hand), [Hand.left]);
      expect(ev.whereType<Confirmed>(), isEmpty);
    });

    test('nothing is emitted unless enabled', () async {
      expect((await run(pulling())).whereType<Pulled>(), isEmpty);
    });
  });

  group('cursor', () {
    List<PoseFrame> waving({bool hands = true}) => poseSequence(
      duration: const Duration(seconds: 1),
      posesAt: (_) => [
        makePose(rightWrist: hands ? const Offset(0.5, 0.4) : null),
      ],
    );

    test(
      'CursorMoved per frame with a visible wrist, only when enabled',
      () async {
        final on = await run(waving(), cursor: true);
        final moved = on.whereType<CursorMoved>().toList();
        expect(moved, hasLength(30));
        expect(moved.last.x, closeTo(0.5, 0.05));
        expect(moved.last.y, inInclusiveRange(0.0, 1.0));
        expect((await run(waving())).whereType<CursorMoved>(), isEmpty);
      },
    );

    test('no wrist -> no CursorMoved (unknown, not a miss)', () async {
      final ev = await run(waving(hands: false), cursor: true);
      expect(ev.whereType<CursorMoved>(), isEmpty);
    });
  });
}

class _ThrowingPose extends Pose {
  _ThrowingPose() : super(const {});

  @override
  Map<PoseJoint, Landmark> get joints => throw UnimplementedError('boom');
}
