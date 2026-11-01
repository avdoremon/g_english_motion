import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/game_controller.dart';
import 'package:g_english_motion/audio/voice_lines.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';

const _correctLines = [
  'Giỏi quá!',
  'Đúng rồi, tuyệt vời!',
  'Chính xác! Em làm tốt lắm!',
];

void main() {
  late GameHarness h;

  Future<GameHarness> playing({bool hangTts = false}) async {
    h = await GameHarness.create(hangTts: hangTts);
    expect(await h.startAndCalibrate(), PermissionOutcome.granted);
    return h;
  }

  GameController c() => h.controller;
  int correctIndex() =>
      (c().session!.current.question as ChoiceQuestion).correctIndex;
  Future<void> inject(GameInputEvent e) async {
    c().debugInject(e);
    await pumpEventQueue();
  }

  tearDown(() => h.dispose());

  group('start', () {
    test(
      'permission denied: state exposes it, no session, no camera loop',
      () async {
        h = await GameHarness.create(permission: PermissionOutcome.denied);
        expect(await h.startAndCalibrate(), PermissionOutcome.denied);
        expect(c().phase, GamePhase.permissionDenied);
        expect(c().permission, PermissionOutcome.denied);
        expect(c().session, isNull);
      },
    );

    test('permanently denied is exposed as such', () async {
      h = await GameHarness.create(
        permission: PermissionOutcome.permanentlyDenied,
      );
      await h.startAndCalibrate();
      expect(c().permission, PermissionOutcome.permanentlyDenied);
    });

    test(
      'no content: noContent phase and the camera is never started',
      () async {
        h = await GameHarness.create(withContent: false);
        await h.startAndCalibrate();
        expect(c().phase, GamePhase.noContent);
        expect(c().session, isNull);
        expect(h.source.started, isFalse);
      },
    );

    test('calibration progress is exposed while calibrating', () async {
      h = await GameHarness.create();
      final f = c().start(h.source);
      await pumpEventQueue();
      await f;
      expect(c().phase, GamePhase.calibrating);
      await h.run(const Duration(seconds: 1));
      expect(c().calibrationProgress, isNotNull);
      expect(c().calibrationProgress!.progress, inExclusiveRange(0, 1));
      expect(c().session, isNull);
    });

    test(
      'after calibration: session built, lanes = choiceCount, question spoken',
      () async {
        await playing();
        expect(c().phase, GamePhase.playing);
        final s = c().session!;
        expect(s.totalQuestions, 8);
        expect(s.phase, SessionPhase.playing);
        expect(
          (s.current.question as ChoiceQuestion).choices.length,
          harnessLevel.choiceCount,
        );
        expect(h.captions, contains(s.current.question.ttsText));
      },
    );
  });

  group('answers', () {
    test('correct lane + jump: correct line, score 100, no tryAgain', () async {
      await playing();
      await h.answerInLane(correctIndex());
      final s = c().session!;
      expect(s.phase, SessionPhase.feedback);
      expect(s.lastResult, RoundResult.correct);
      expect(c().score, 100);
      expect(h.captions.where(_correctLines.contains), hasLength(1));
      expect(h.captions, isNot(contains(VoiceLine.tryAgain.caption)));
    });

    test(
      'wrong lane: tryAgain, then the answer is explained, in order',
      () async {
        await playing();
        final ok = correctIndex();
        final answer = c().session!.current.question.ttsText;
        await h.answerInLane((ok + 1) % 3);
        expect(c().session!.lastResult, RoundResult.wrong);
        expect(c().score, 0);
        final tail = h.captions.sublist(h.captions.length - 3);
        expect(tail, [
          VoiceLine.tryAgain.caption,
          VoiceLine.theAnswerIs.caption,
          answer,
        ]);
      },
    );

    test('timeout is treated as wrong (own timeout only)', () async {
      await playing();
      final answer = c().session!.current.question.ttsText;
      await h.run(const Duration(seconds: 21));
      expect(c().session!.lastResult, RoundResult.timeout);
      expect(c().score, 0);
      expect(h.captions.sublist(h.captions.length - 3), [
        VoiceLine.tryAgain.caption,
        VoiceLine.theAnswerIs.caption,
        answer,
      ]);
    });

    test('an unsure confirmation (lane out of range) is not graded', () async {
      await playing();
      await inject(const Confirmed(-1, at: Duration.zero));
      expect(c().session!.phase, SessionPhase.playing);
      expect(c().session!.lastResult, isNull);
    });

    test('selectedLane follows LaneChanged even while prompting', () async {
      await playing();
      await inject(const LaneChanged(2, at: Duration.zero));
      expect(c().selectedLane, 2);
    });
  });

  group('finish', () {
    test('8 correct answers: outcome, stars saved, history written', () async {
      await playing();
      for (var i = 0; i < 8; i++) {
        expect(c().session!.phase, SessionPhase.playing, reason: 'q$i');
        await inject(Confirmed(correctIndex(), at: Duration.zero));
        await h.run(const Duration(milliseconds: 2700));
      }
      expect(c().phase, GamePhase.finished);
      final o = c().outcome!;
      expect((o.correct, o.total, o.points, o.stars), (8, 8, 800, 3));
      await c().persisted;
      expect(h.store.starsFor(1, 1), 3);
      expect(h.store.recentIds(), isNotEmpty);
      expect(h.captions, contains(VoiceLine.levelComplete.caption));
    });

    test('a failed level with 0 stars saves nothing', () async {
      await playing();
      for (var i = 0; i < 8; i++) {
        final wrong = (correctIndex() + 1) % 3;
        await inject(Confirmed(wrong, at: Duration.zero));
        await h.run(const Duration(milliseconds: 2700));
      }
      // 8 reviews follow the 8 wrong answers.
      for (var i = 0; i < 8; i++) {
        await inject(Confirmed((correctIndex() + 1) % 3, at: Duration.zero));
        await h.run(const Duration(milliseconds: 2700));
      }
      expect(c().phase, GamePhase.finished);
      expect(c().outcome!.stars, 0);
      await c().persisted;
      expect(h.store.starsFor(1, 1), 0);
      expect(h.captions, isNot(contains(VoiceLine.levelComplete.caption)));
    });
  });

  group('player presence', () {
    test('PlayerLost stops the round clock, PlayerFound restarts it', () async {
      await playing();
      final seen = <GameInputEvent>[];
      c().events.listen((e) {
        seen.add(e);
        // Mimic GameShell.
        if (e is PlayerLost) c().session!.pause();
        if (e is PlayerFound) c().session!.resume();
      });
      await inject(const PlayerLost(at: Duration.zero));
      expect(c().session!.round.clockRunning, isFalse);
      expect(c().session!.phase, SessionPhase.paused);
      await inject(const PlayerFound(at: Duration.zero));
      expect(c().session!.phase, SessionPhase.playing);
      expect(c().session!.round.clockRunning, isTrue);
      expect(seen.map((e) => e.runtimeType), [PlayerLost, PlayerFound]);
    });

    test(
      'watchdog: no frame for 2 s while playing -> PlayerLost, then Found',
      () async {
        await playing();
        final seen = <GameInputEvent>[];
        c().events.listen(seen.add);
        await h.run(const Duration(milliseconds: 1500), withFrames: false);
        expect(seen, isEmpty);
        await h.run(const Duration(milliseconds: 800), withFrames: false);
        expect(seen.single, isA<PlayerLost>());
        final before = c().session!.round.remaining;
        // 25 s without frames: the clock is stopped, nothing times out.
        await h.run(const Duration(seconds: 25), withFrames: false);
        expect(seen, hasLength(1));
        expect(c().session!.lastResult, isNull);
        expect(c().session!.round.remaining, before);
        await h.run(const Duration(milliseconds: 200));
        expect(seen.last, isA<PlayerFound>());
        expect(c().session!.round.clockRunning, isTrue);
      },
    );
  });

  group('prompt watchdog', () {
    test('hung speech: round starts after 12 s anyway', () async {
      await playing(hangTts: true);
      expect(c().session!.phase, SessionPhase.prompting);
      await h.run(const Duration(seconds: 11));
      expect(c().session!.phase, SessionPhase.prompting);
      await h.run(const Duration(seconds: 2));
      expect(c().session!.phase, SessionPhase.playing);
    });
  });

  group('dispose', () {
    test('stops camera, closes events, ignores later frames/ticks', () async {
      await playing();
      var done = false;
      c().events.listen(null, onDone: () => done = true);
      c().dispose();
      await c().closed;
      expect(h.source.stopped, isTrue);
      expect(done, isTrue);
      await h.run(const Duration(seconds: 1));
    });
  });

  group('fix round 1', () {
    Future<void> lostFound() async {
      final sub = c().events.listen((e) {
        if (e is PlayerLost) c().session!.pause();
        if (e is PlayerFound) c().session!.resume();
      });
      addTearDown(sub.cancel);
      await inject(const PlayerLost(at: Duration.zero));
      await inject(const PlayerFound(at: Duration.zero));
    }

    test(
      'pause/resume during correct feedback: no second score or line',
      () async {
        await playing();
        await h.answerInLane(correctIndex());
        expect(c().session!.phase, SessionPhase.feedback);
        await lostFound();
        expect(c().session!.phase, SessionPhase.feedback);
        expect(c().score, 100);
        expect(c().session!.correctCount, 1);
        expect(h.captions.where(_correctLines.contains), hasLength(1));
      },
    );

    test(
      'pause/resume during wrong feedback: tryAgain and explain once',
      () async {
        await playing();
        await h.answerInLane((correctIndex() + 1) % 3);
        await lostFound();
        expect(
          h.captions.where((x) => x == VoiceLine.tryAgain.caption),
          hasLength(1),
        );
        expect(
          h.captions.where((x) => x == VoiceLine.theAnswerIs.caption),
          hasLength(1),
        );
        expect(c().score, 0);
      },
    );

    test('score is derived from the session (first attempts only)', () async {
      await playing();
      await inject(Confirmed(correctIndex(), at: Duration.zero));
      expect(c().session!.correctCount, 1);
      expect(c().score, 100);
    });

    test(
      'finishing stops the camera and pose session before dispose',
      () async {
        await playing();
        for (var i = 0; i < 8; i++) {
          await inject(Confirmed(correctIndex(), at: Duration.zero));
          await h.run(const Duration(milliseconds: 2700));
        }
        await pumpEventQueue();
        expect(c().phase, GamePhase.finished);
        expect(h.source.stopped, isTrue);
        expect(h.frames.hasListener, isFalse);
      },
    );

    test('dispose during a long tryAgain never explains the answer', () async {
      h = await GameHarness.create(hangClip: VoiceLine.tryAgain.assetPath);
      await h.startAndCalibrate();
      await h.answerInLane((correctIndex() + 1) % 3);
      expect(h.captions, contains(VoiceLine.tryAgain.caption));
      c().dispose();
      await c().closed;
      await pumpEventQueue();
      expect(h.captions, isNot(contains(VoiceLine.theAnswerIs.caption)));
    });

    test('start twice does not leak a second frame subscription', () async {
      h = await GameHarness.create();
      final a = c().start(h.source);
      final b = c().start(h.source);
      await pumpEventQueue();
      expect(await b, await a);
      await h.startAndCalibrate();
      expect(await c().start(h.source), PermissionOutcome.granted);
      expect(c().phase, GamePhase.playing);
    });

    test(
      'ticks only ping the HUD listenable, not the main listeners',
      () async {
        await playing();
        var main = 0, hud = 0;
        c().addListener(() => main++);
        c().hudTick.addListener(() => hud++);
        await h.run(const Duration(seconds: 1));
        expect(main, 0);
        expect(hud, greaterThan(20));
      },
    );

    test('a jump 200 ms into a question is ignored (first 500 ms)', () async {
      await playing();
      await h.jump();
      expect(c().session!.lastResult, isNull);
      expect(c().session!.phase, SessionPhase.playing);
      // After the grace period and a rest, a jump counts.
      await h.run(const Duration(seconds: 2));
      await h.jump();
      expect(c().session!.lastResult, isNotNull);
    });

    test(
      'events of a frame are applied before the tick that follows it',
      () async {
        // Dry run: how much round time passes until the jump confirms?
        await playing();
        await h.answerInLane(
          correctIndex(),
          stopWhen: () => c().session!.lastResult != null,
        );
        final r = c().session!.round;
        final used = const Duration(seconds: 20) - r.remaining;
        expect(c().session!.lastResult, RoundResult.correct);
        await h.dispose();

        // Same run with a time limit that expires at the tick right after the
        // confirming frame: the answer must win over the timeout.
        h = await GameHarness.create(
          level: LevelConfig(
            level: 1,
            questionCount: 8,
            baseTime: used + const Duration(milliseconds: 33),
            choiceCount: 3,
            hints: HintMode.full,
            window: UnitWindow.current,
          ),
        );
        await h.startAndCalibrate();
        await h.answerInLane(correctIndex());
        expect(c().session!.lastResult, RoundResult.correct);
      },
    );

    test('dispose during the theAnswerIs clip: the word never plays', () async {
      h = await GameHarness.create(hangClip: VoiceLine.theAnswerIs.assetPath);
      await h.startAndCalibrate();
      final answer = c().session!.current.question.ttsText;
      await h.answerInLane((correctIndex() + 1) % 3);
      expect(h.captions.last, VoiceLine.theAnswerIs.caption);
      final captionsBefore = h.captions.length;
      final spokenBefore = h.ttsLog.length;
      expect(answer, isNotEmpty);
      c().dispose();
      await c().closed;
      await pumpEventQueue();
      expect(h.captions.length, captionsBefore);
      expect(h.ttsLog.length, spokenBefore);
    });

    test(
      'disposed while the permission request is pending: camera stopped',
      () async {
        h = await GameHarness.create(delayPermission: true);
        final f = c().start(h.source);
        await pumpEventQueue();
        c().dispose();
        await c().closed;
        expect(h.source.stops, 0, reason: 'start has not returned yet');
        h.source.finishPermission();
        await f;
        await pumpEventQueue();
        expect(h.source.started, isTrue);
        expect(h.source.stops, 1, reason: 'the orphan camera is released');
        expect(c().phase, isNot(GamePhase.calibrating));
      },
    );

    test('exactly one camera stop per source over a full level', () async {
      await playing();
      for (var i = 0; i < 8; i++) {
        await inject(Confirmed(correctIndex(), at: Duration.zero));
        await h.run(const Duration(milliseconds: 2700));
      }
      await pumpEventQueue();
      expect(h.source.stops, 1);
      c().dispose();
      await c().closed;
      expect(h.source.stops, 1);
    });

    test(
      'review question: feedback once each, no points for the review',
      () async {
        await playing();
        final sub = c().events.listen((e) {
          if (e is PlayerLost) c().session!.pause();
          if (e is PlayerFound) c().session!.resume();
        });
        addTearDown(sub.cancel);
        // Q1 wrong (queues a review at the end), the other 7 correct.
        await inject(Confirmed((correctIndex() + 1) % 3, at: Duration.zero));
        await h.run(const Duration(milliseconds: 2700));
        for (var i = 1; i < 8; i++) {
          await inject(Confirmed(correctIndex(), at: Duration.zero));
          await h.run(const Duration(milliseconds: 2700));
        }
        expect(c().session!.isReview, isTrue);
        await inject(Confirmed(correctIndex(), at: Duration.zero));
        // Pause/resume during the review's feedback must not repeat anything.
        await inject(const PlayerLost(at: Duration.zero));
        await inject(const PlayerFound(at: Duration.zero));
        await h.run(const Duration(milliseconds: 2700));
        expect(c().phase, GamePhase.finished);
        expect(
          h.captions.where((x) => x == VoiceLine.tryAgain.caption),
          hasLength(1),
        );
        expect(h.captions.where(_correctLines.contains), hasLength(8));
        expect(c().outcome!.correct, 7);
        expect(c().score, 700);
      },
    );
  });
}
