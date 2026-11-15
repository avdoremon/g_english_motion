import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/app.dart';
import 'package:g_english_motion/audio/voice_lines.dart';
import 'package:g_english_motion/content/action_config.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/action_detector.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/levels/scoring.dart';
import 'package:g_english_motion/modes/mode_availability.dart';
import 'package:g_english_motion/modes/action_round.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';
import '../helpers/map_asset_bundle.dart';
import '../helpers/synthetic_poses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameHarness h;
  late ActionConfig config;

  setUpAll(() async {
    config = await ActionConfig.load(
      MapAssetBundle({
        ActionConfig.assetPath: File(ActionConfig.assetPath).readAsStringSync(),
      }),
    );
  });

  Future<void> setUp({
    bool enabled = true,
    bool withConfig = true,
    ModeKind? mode = ModeKind.puppySays,
    bool shuffle = false,
    int grade = 1,
    bool hangTts = true,
    int seed = 7,
  }) async {
    h = await GameHarness.create(
      modes: const [ModeKind.laneJump],
      mode: mode,
      shuffle: shuffle,
      grade: grade,
      hangTts: hangTts,
      seed: seed,
      actions: withConfig ? config : null,
      puppySaysEnabled: enabled,
    );
  }

  tearDown(() => h.dispose());

  ActionQuestion q0() =>
      h.controller.session!.current.question as ActionQuestion;
  void endPrompt() => h.controller.session!.onPromptFinished();
  ActionPerformed doing(PuppyAction a) => ActionPerformed(a, at: h.lastFrameAt);
  PuppyAction other(PuppyAction a) =>
      PuppyAction.values.firstWhere((x) => x != a);

  group('gating', () {
    test('flag off: puppySays falls back to the default mix', () async {
      await setUp(enabled: false);
      expect(h.controller.activeModes, defaultModesForGrade(1));
      expect(h.controller.activeModes, isNot(contains(ModeKind.puppySays)));
    });

    test('flag on without ActionConfig: not active', () async {
      await setUp(withConfig: false);
      expect(h.controller.activeModes, defaultModesForGrade(1));
    });

    test('flag on + config: plays alone', () async {
      await setUp();
      expect(h.controller.activeModes, {ModeKind.puppySays});
    });

    test('flag on + config but grade 3: not offered', () async {
      await setUp(grade: 3);
      expect(h.controller.activeModes, defaultModesForGrade(3));
    });

    test('grades 1 and 2 are on, 3 and up are off (flag on)', () async {
      for (final g in [1, 2, 3, 4, 5]) {
        await setUp(grade: g);
        expect(
          h.controller.activeModes.contains(ModeKind.puppySays),
          g <= 2,
          reason: 'grade $g',
        );
        if (g > 2) {
          expect(h.controller.activeModes, defaultModesForGrade(g));
        }
        await h.dispose();
      }
      await setUp(); // for tearDown
    });

    test('shuffle never includes puppySays, flag on or off', () async {
      for (final on in [true, false]) {
        for (final g in [1, 2, 3]) {
          await setUp(enabled: on, mode: null, shuffle: true, grade: g);
          expect(
            h.controller.activeModes,
            isNot(contains(ModeKind.puppySays)),
            reason: 'enabled=$on grade=$g',
          );
          await h.dispose();
        }
      }
      await setUp(); // for tearDown
    });

    test('default Chơi mix is unchanged and never puppySays', () async {
      await setUp(mode: null);
      expect(h.controller.activeModes, defaultModesForGrade(1));
    });
  });

  group('round', () {
    test('builds an ActionRound with the mode time limit', () async {
      await setUp();
      await h.startAndCalibrate();
      final s = h.controller.session!;
      expect(s.current.mode, ModeKind.puppySays);
      expect(s.round, isA<ActionRound>());
      expect(
        s.round.timeLimit,
        Scoring.timeFor(h.controller.level, ModeKind.puppySays),
      );
    });

    test('the prompt speaks ttsText, no word clip', () async {
      await setUp(hangTts: false);
      await h.startAndCalibrate();
      expect(h.ttsLog, contains('tts:${q0().ttsText}'));
    });

    test('the correct action ends the round correct', () async {
      await setUp();
      await h.startAndCalibrate();
      final s = h.controller.session!;
      endPrompt();
      expect(s.phase, SessionPhase.playing);
      h.controller.debugInject(doing(q0().action));
      expect(s.lastResult, RoundResult.correct);
    });

    test('another action is ignored', () async {
      await setUp();
      await h.startAndCalibrate();
      final s = h.controller.session!;
      endPrompt();
      h.controller.debugInject(doing(other(q0().action)));
      expect(s.round.result, isNull);
      expect(s.lastResult, isNull);
      expect(s.phase, SessionPhase.playing);
    });

    test('an action during the prompt is ignored', () async {
      await setUp();
      await h.startAndCalibrate();
      final s = h.controller.session!;
      expect(s.phase, SessionPhase.prompting);
      h.controller.debugInject(doing(q0().action));
      expect(s.round.result, isNull);
    });

    test('timeout is neutral: outOfTime then the hint, never wrong', () async {
      await setUp(hangTts: false);
      await h.startAndCalibrate();
      final s = h.controller.session!;
      final hint = q0().hintVi;
      endPrompt();
      await h.run(s.round.timeLimit + const Duration(seconds: 1));
      expect(s.lastResult, RoundResult.timeout);
      expect(h.captions, contains(VoiceLine.outOfTime.caption));
      expect(h.captions, contains(hint));
      expect(h.captions, contains('Pup chưa thấy rõ… thử lại nhé'));
      // outOfTime, then the kind camera line, then the hint.
      final iOut = h.captions.indexOf(VoiceLine.outOfTime.caption);
      final iSeen = h.captions.indexOf('Pup chưa thấy rõ… thử lại nhé');
      expect(iSeen, greaterThan(iOut));
      expect(h.captions.indexOf(hint), greaterThan(iSeen));
      expect(h.captions.any((c) => c.toLowerCase().contains('sai')), isFalse);
      expect(h.captions, isNot(contains(VoiceLine.tryAgain.caption)));
      // The hint is a caption only: it is never spoken.
      expect(h.ttsLog.where((e) => e.contains(hint)), isEmpty);
    });

    test('a correct answer says no hint and no wrong line', () async {
      await setUp();
      await h.startAndCalibrate();
      final hint = q0().hintVi;
      endPrompt();
      h.controller.debugInject(doing(q0().action));
      await h.run(const Duration(milliseconds: 300));
      expect(h.captions, isNot(contains(hint)));
      expect(h.captions, isNot(contains(VoiceLine.tryAgain.caption)));
      expect(h.captions, isNot(contains(VoiceLine.outOfTime.caption)));
    });

    test(
      'child absent at round start: the round waits, then resumes',
      () async {
        await setUp();
        await h.startAndCalibrate();
        final s = h.controller.session!;
        final r = s.round as ActionRound;
        h.controller.debugInject(PlayerLost(at: h.lastFrameAt));
        endPrompt();
        expect(s.phase, SessionPhase.playing);
        await h.run(r.timeLimit * 2, withFrames: false);
        expect(s.lastResult, isNull);
        expect(s.round, same(r));
        expect(r.remaining, r.timeLimit);
        h.controller.debugInject(doing(q0().action));
        expect(r.result, isNull);
        h.controller.debugInject(PlayerFound(at: h.lastFrameAt));
        await h.run(const Duration(seconds: 2));
        expect(r.remaining, lessThan(r.timeLimit));
        expect(r.result, isNull);
      },
    );

    /// Starts a level whose first command is [a] (seed search).
    Future<void> startWith(PuppyAction a) async {
      var seed = 1;
      while (true) {
        await setUp(seed: seed);
        await h.startAndCalibrate();
        if (q0().action == a) return;
        await h.dispose();
        seed++;
        expect(seed, lessThan(80), reason: 'no seed gives $a first');
      }
    }

    final hx = GameHarness.hipXForLane(1, 3);
    Pose handsUpPose() => makePose(
      hipX: hx,
      leftWrist: Offset(hx - 0.2, 0.1),
      rightWrist: Offset(hx + 0.2, 0.1),
    );
    Pose squatPose() => makePose(hipX: hx, hipY: 0.7, kneeY: 0.75);

    test('hands already up when the hands-up round starts: correct', () async {
      await startWith(PuppyAction.handsUp);
      final s = h.controller.session!;
      // The child raises the hands during the prompt: the event is dropped
      // there and the detector latches...
      await h.run(
        const Duration(milliseconds: 1200),
        pose: (_) => handsUpPose(),
      );
      expect(s.phase, SessionPhase.prompting);
      expect(s.lastResult, isNull);
      // ...but the held pose counts once the round starts.
      endPrompt();
      await h.run(
        const Duration(milliseconds: 1000),
        pose: (_) => handsUpPose(),
        stopWhen: () => s.lastResult != null,
      );
      expect(s.lastResult, RoundResult.correct);
    });

    test('a squat right after the prompt is not eaten by a grace', () async {
      await startWith(PuppyAction.squat);
      final s = h.controller.session!;
      endPrompt();
      await h.run(
        const Duration(milliseconds: 900),
        pose: (_) => squatPose(),
        stopWhen: () => s.lastResult != null,
      );
      expect(s.lastResult, RoundResult.correct);
    });

    test('hands held up while the command is squat: ignored', () async {
      await startWith(PuppyAction.squat);
      final s = h.controller.session!;
      await h.run(
        const Duration(milliseconds: 1200),
        pose: (_) => handsUpPose(),
      );
      endPrompt();
      await h.run(
        const Duration(milliseconds: 2000),
        pose: (_) => handsUpPose(),
        stopWhen: () => s.lastResult != null,
      );
      expect(s.lastResult, isNull);
      expect(s.round.result, isNull);
      expect(s.phase, SessionPhase.playing);
    });

    test('no jump-to-choose instruction is spoken', () async {
      await setUp();
      await h.startAndCalibrate();
      expect(h.captions, isNot(contains(VoiceLine.jumpToChoose.caption)));
      expect(h.captions, isNot(contains(VoiceLine.raiseHandsToChoose.caption)));
    });

    test('the lane tracker is not touched', () async {
      await setUp();
      await h.startAndCalibrate();
      final initial = h.controller.selectedLane;
      expect(initial, 1);
      endPrompt();
      // Stand in the left lane for a good while (no action, no timeout).
      final left = GameHarness.hipXForLane(0, 3);
      await h.run(
        const Duration(milliseconds: 1500),
        pose: (_) => makePose(hipX: left),
        stopWhen: () => h.controller.session!.lastResult != null,
      );
      expect(h.controller.selectedLane, initial);
    });

    test('control: the same pose does move the lane in laneJump', () async {
      await setUp(mode: ModeKind.laneJump);
      await h.startAndCalibrate();
      final left = GameHarness.hipXForLane(0, 3);
      h.controller.session!.onPromptFinished();
      await h.run(
        const Duration(milliseconds: 1500),
        pose: (_) => makePose(hipX: left),
      );
      expect(h.controller.selectedLane, 0);
    });

    test('a real clap pose sequence answers a clap command', () async {
      // Find a seed whose first command is clap.
      var seed = 1;
      while (true) {
        await setUp(seed: seed);
        await h.startAndCalibrate();
        if (q0().action == PuppyAction.clap) break;
        await h.dispose();
        seed++;
        expect(seed, lessThan(60));
      }
      final s = h.controller.session!;
      endPrompt();
      final hipX = GameHarness.hipXForLane(1, 3);
      Pose standPose() => makePose(
        hipX: hipX,
        leftWrist: Offset(hipX - 0.1, 0.55),
        rightWrist: Offset(hipX + 0.1, 0.55),
      );
      Pose apart() => makePose(
        hipX: hipX,
        leftWrist: Offset(hipX - 0.2, 0.4),
        rightWrist: Offset(hipX + 0.2, 0.4),
      );
      Pose together() => makePose(
        hipX: hipX,
        leftWrist: Offset(hipX - 0.01, 0.4),
        rightWrist: Offset(hipX + 0.01, 0.4),
      );
      await h.run(
        const Duration(milliseconds: 2000),
        pose: (_) => standPose(),
        stopWhen: () => s.lastResult != null,
      );
      expect(s.lastResult, isNull);
      await h.run(
        const Duration(milliseconds: 500),
        pose: (_) => apart(),
        stopWhen: () => s.lastResult != null,
      );
      await h.run(
        const Duration(milliseconds: 500),
        pose: (_) => together(),
        stopWhen: () => s.lastResult != null,
      );
      expect(s.lastResult, RoundResult.correct);
    });
  });

  group('app wiring', () {
    test('AppDependencies.load keeps the actions when they load', () async {
      SharedPreferences.setMockInitialValues({});
      final deps = await AppDependencies.load(bundle: rootBundle);
      expect(deps.actions, isNotNull);
      expect(deps.actions!.forGrade(1), isNotEmpty);
    });

    test(
      'a failing ActionConfig load gives null, the rest still loads',
      () async {
        SharedPreferences.setMockInitialValues({});
        final deps = await AppDependencies.load(bundle: _WithoutActions());
        expect(deps.actions, isNull);
        expect(deps.levels, isNotEmpty);
      },
    );
  });
}

/// The real bundle, but the actions file is broken.
class _WithoutActions extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => rootBundle.load(key);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == ActionConfig.assetPath) throw const FormatException('broken');
    return rootBundle.loadString(key, cache: cache);
  }
}
