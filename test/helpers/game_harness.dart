// Test harness for GameController: fake camera, fake audio engines, a manual
// ticker and a synthetic player standing in a chosen lane.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/game_controller.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'synthetic_poses.dart';

/// Counts stop() calls; can hold back the permission answer.
class CountingSource extends FakePoseFrameSource {
  CountingSource.fromStream(
    super.frames, {
    super.outcome,
    bool delayPermission = false,
    this.hangStop = false,
  }) : _gate = delayPermission ? Completer<void>() : null,
       super.fromStream();
  final Completer<void>? _gate;
  int stops = 0;

  /// stop() never completes (a hung native camera release).
  final bool hangStop;

  void finishPermission() => _gate?.complete();

  @override
  Future<PermissionOutcome> start() async {
    await _gate?.future;
    return super.start();
  }

  @override
  Future<void> stop() async {
    stops++;
    if (hangStop) await Completer<void>().future;
    await super.stop();
  }
}

class HarnessTts implements SpeechEngine {
  HarnessTts(this.log, {this.hang = false});
  final List<String> log;
  final bool hang;
  @override
  Future<bool> isEnglishAvailable() async => true;
  @override
  Future<void> speak(String text) async {
    log.add('tts:$text');
    if (hang) await Completer<void>().future;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class HarnessClips implements ClipPlayer {
  HarnessClips({this.hangPath});

  /// Playing this asset never completes on its own (only stop() ends it).
  final String? hangPath;
  final _gate = Completer<bool>();
  @override
  Future<bool> play(String assetPath) async {
    if (assetPath == hangPath) return _gate.future;
    return false;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

const harnessWords = [
  'apple',
  'ball',
  'cat',
  'dog',
  'egg',
  'fish',
  'goat',
  'hat',
];

Unit harnessUnit({
  int grade = 1,
  int index = 1,
  int count = 8,
  bool withImages = false,
}) {
  final p = 'g${grade}u$index';
  return Unit(
    grade: grade,
    index: index,
    id: 'u${index.toString().padLeft(2, '0')}',
    title: p,
    items: [
      for (var i = 0; i < count; i++)
        ContentItem(
          id: '${p}i$i',
          word: harnessWords[i % harnessWords.length],
          ttsText: harnessWords[i % harnessWords.length],
          image: withImages
              ? 'grade1/${harnessWords[i % harnessWords.length]}.png'
              : null,
          distractorIds: ['${p}i${(i + 1) % count}', '${p}i${(i + 2) % count}'],
          modes: const [ModeKind.laneJump],
        ),
    ],
  );
}

const harnessLevel = LevelConfig(
  level: 1,
  questionCount: 8,
  baseTime: Duration(seconds: 20),
  choiceCount: 3,
  hints: HintMode.full,
  window: UnitWindow.current,
);

class GameHarness {
  GameHarness._(
    this.store,
    this.source,
    this.audio,
    this.ttsLog,
    this.captions,
    this.controller,
    this.frames,
    this.tickCtl,
  );

  static Future<GameHarness> create({
    bool withContent = true,
    PermissionOutcome permission = PermissionOutcome.granted,
    bool hangTts = false,
    String? hangClip,
    LevelConfig level = harnessLevel,
    bool delayPermission = false,
    ConfirmGesture confirm = ConfirmGesture.jump,
    bool withImages = false,
    int unitSize = 8,
    int seed = 7,
    bool hangStop = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final store = ProgressStore(await SharedPreferences.getInstance());
    await store.setConfirmGesture(confirm);
    final frames = StreamController<PoseFrame>(sync: true);
    final source = CountingSource.fromStream(
      frames.stream,
      outcome: permission,
      delayPermission: delayPermission,
      hangStop: hangStop,
    );
    final ttsLog = <String>[];
    final audio = AudioService(
      HarnessTts(ttsLog, hang: hangTts),
      HarnessClips(hangPath: hangClip),
      assetExists: (p) => p == hangClip,
      speechTimeout: const Duration(seconds: 30),
      clipTimeout: const Duration(seconds: 30),
    );
    final captions = <String>[];
    audio.captions.listen(captions.add);
    final tickCtl = StreamController<Duration>.broadcast(sync: true);
    final repo = ContentRepository(
      withContent ? [harnessUnit(withImages: withImages, count: unitSize)] : [],
    );
    final controller = GameController(
      grade: 1,
      level: level,
      store: store,
      repo: repo,
      audio: audio,
      ticker: () => tickCtl.stream,
      rng: math.Random(seed),
    );
    return GameHarness._(
      store,
      source,
      audio,
      ttsLog,
      captions,
      controller,
      frames,
      tickCtl,
    );
  }

  final ProgressStore store;
  final CountingSource source;
  final AudioService audio;
  final List<String> ttsLog;
  final List<String> captions;
  final GameController controller;
  final StreamController<PoseFrame> frames;
  final StreamController<Duration> tickCtl;

  Duration _t = Duration.zero;
  Duration _elapsed = Duration.zero;
  int lane = 1;

  /// Timestamp of the most recent synthetic frame.
  Duration get lastFrameAt => _t;

  static const _step = Duration(milliseconds: 33);

  /// Hip x that puts the (mirrored) player in [l] of [n] lanes.
  static double hipXForLane(int l, int n) {
    // Torso 0.3 of the height; frames carry the default 16:9 aspect.
    const width = 0.6 * 0.3 / PoseFrame.defaultAspectRatio;
    final left = 0.5 - n * width / 2;
    return 1 - (left + (l + 0.5) * width);
  }

  Pose standing({double lift = 0}) => makePose(
    hipX: hipXForLane(lane, controller.level.choiceCount),
    hipY: 0.6 - lift,
  );

  /// Advances time by [d]: one synthetic frame (unless [withFrames] is false)
  /// and one ticker event per step.
  Future<void> run(
    Duration d, {
    bool withFrames = true,
    Pose Function(Duration since)? pose,
    List<Pose> Function(Duration since)? poses,
    bool Function()? stopWhen,
  }) async {
    var spent = Duration.zero;
    while (spent < d) {
      spent += _step;
      _t += _step;
      _elapsed += _step;
      if (withFrames) {
        frames.add(
          PoseFrame(
            poses != null
                ? poses(spent)
                : [pose != null ? pose(spent) : standing()],
            _t,
          ),
        );
        // Like production: a frame's events are delivered (microtask)
        // before the ticker's next event.
        await pumpEventQueue(times: 1);
        if (stopWhen?.call() ?? false) return;
      }
      tickCtl.add(_elapsed);
      await pumpEventQueue(times: 2);
    }
  }

  /// Calibration frames (standing in the middle), then lets the flow settle.
  Future<PermissionOutcome> startAndCalibrate() async {
    final fut = controller.start(source);
    await pumpEventQueue();
    final out = await fut;
    if (out != PermissionOutcome.granted) return out;
    lane = 1;
    for (var i = 0; i < 75 && controller.phase == GamePhase.calibrating; i++) {
      _t += _step;
      frames.add(PoseFrame([makePose()], _t));
      await pumpEventQueue(times: 1);
    }
    await pumpEventQueue();
    return out;
  }

  Pose jumpPose(Duration since) {
    const air = Duration(milliseconds: 500);
    return standing(
      lift: since < air
          ? 0.06 * math.sin(math.pi * since.inMicroseconds / air.inMicroseconds)
          : 0,
    );
  }

  /// Jumps in place (no walking).
  Future<void> jump({bool Function()? stopWhen}) => run(
    const Duration(milliseconds: 700),
    pose: jumpPose,
    stopWhen: stopWhen,
  );

  /// Walks to [l], stands still, then jumps once.
  Future<void> answerInLane(int l, {bool Function()? stopWhen}) async {
    lane = l;
    await run(const Duration(milliseconds: 1500), stopWhen: stopWhen);
    await jump(stopWhen: stopWhen);
  }

  Future<void> dispose() async {
    controller.dispose();
    await controller.closed;
    unawaited(frames.close()); // never completes without a listener
    await tickCtl.close();
  }
}
