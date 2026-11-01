// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audio/audio_service.dart';
import '../audio/voice_lines.dart';
import '../content/content_repository.dart';
import '../content/curriculum.dart';
import '../content/models.dart';
import '../content/question_generator.dart';
import '../content/question_models.dart';
import '../input/calibrator.dart';
import '../input/game_input_event.dart';
import '../input/pose_frame_source.dart';
import '../input/pose_session.dart';
import '../input/pose_types.dart';
import '../levels/level_config.dart';
import '../levels/scoring.dart';
import '../modes/lane_jump.dart';
import '../modes/round.dart';
import '../progress/progress_store.dart';
import '../session/level_session.dart';

enum GamePhase {
  idle,
  requestingPermission,
  permissionDenied,

  /// The grade has no lessons yet (Task 15 content): nothing was started.
  noContent,
  calibrating,

  /// A [LevelSession] exists and is running (see [GameController.session]
  /// for its own phase).
  playing,
  finished,
}

/// Source of monotonic elapsed time, one event per frame. Tests drive it by
/// hand; production uses a periodic stream.
typedef TickerFactory = Stream<Duration> Function();

/// Orchestrates one grade 1-2 LaneJump play-through:
/// permission -> calibration -> plan -> [LevelSession] -> result.
///
/// Ordering and timing rules:
/// - Input events reach the session through [PoseSession.events], which is
///   delivered on a microtask after the frame that produced it, always before
///   the next ticker event (a separate event-loop turn). So within a frame
///   events are applied before [LevelSession.tick].
/// - The injected [ticker] is the controller's only clock (no Timers):
///   it drives [LevelSession.tick] (dt capped at [maxTickStep] so a stall
///   never eats a child's answer time) and both watchdogs.
/// - Frame watchdog: [PoseSession]'s PlayerLost is frame-driven, so if the
///   camera stalls and no frame arrives for [frameWatchdog] while playing,
///   the controller synthesizes PlayerLost (and PlayerFound at the next
///   frame). If the player is really gone, [PoseSession] reports it itself
///   500 ms later.
/// - Prompt watchdog: if the spoken question does not complete within
///   [promptWatchdog] the round is started anyway.
/// - Presence events: PlayerLost is given to the session first and then
///   published on [events] (GameShell then pauses it); PlayerFound is
///   published first (GameShell resumes) and then given to the session, which
///   ignores events while paused.
/// - Only the Round decides wrong/timeout; unsure input and a lost player
///   never grade.
class GameController extends ChangeNotifier {
  GameController({
    required this.grade,
    required this.level,
    required ProgressStore store,
    required ContentRepository repo,
    required AudioService audio,
    required TickerFactory ticker,
    Random? rng,
    Calibrator Function()? calibratorFactory,
    this.feedbackTime = const Duration(milliseconds: 2500),
    this.frameWatchdog = const Duration(seconds: 2),
    this.promptWatchdog = const Duration(seconds: 12),
  }) : _store = store,
       _repo = repo,
       _audio = audio,
       _tickerFactory = ticker,
       _rng = rng ?? Random(),
       _calibratorFactory = calibratorFactory ?? Calibrator.new;

  static const maxTickStep = Duration(milliseconds: 250);

  final int grade;
  final LevelConfig level;
  final Duration feedbackTime, frameWatchdog, promptWatchdog;

  final ProgressStore _store;
  final ContentRepository _repo;
  final AudioService _audio;
  final TickerFactory _tickerFactory;
  final Random _rng;
  final Calibrator Function() _calibratorFactory;

  // Sync so GameShell reacts inside the dispatch (see class docs).
  final StreamController<GameInputEvent> _events =
      StreamController<GameInputEvent>.broadcast(sync: true);

  GamePhase _phase = GamePhase.idle;
  PermissionOutcome? _permission;
  CalibrationProgress? _calibrationProgress;
  LevelSession? _session;
  LevelOutcome? _outcome;
  PoseFrameSource? _source;
  PoseSession? _pose;
  Calibrator? _calibrator;
  StreamSubscription<PoseFrame>? _frameSub;
  StreamSubscription<GameInputEvent>? _poseSub;
  StreamSubscription<Duration>? _tickSub;
  StreamController<PoseFrame>? _poseFrames;
  List<PlannedQuestion> _plan = const [];

  int _selectedLane = 0;
  Duration _now = Duration.zero;
  Duration? _lastTick;
  Duration _lastFrameAt = Duration.zero;
  bool _lost = false;
  bool _watchdogLost = false;

  PlannedQuestion? _prompted;
  bool _promptedReview = false;
  int _promptToken = 0;
  bool _promptPending = false;
  Duration _promptStartedAt = Duration.zero;

  PlannedQuestion? _fedBack;
  bool _fedBackReview = false;
  PlannedQuestion? _roundStarted;
  bool _roundStartedReview = false;
  Duration _lastFrameTs = Duration.zero;
  Future<PermissionOutcome>? _startFuture;
  Future<void>? _inputStopped;
  bool _cameraStarting = false;
  bool _welcomed = false;

  /// First moments of each question: jumps are ignored (spec: 500 ms).
  static const confirmGrace = Duration(milliseconds: 500);

  SessionPhase? _lastSessionPhase;
  bool _lastTileHints = false;
  bool _disposed = false;
  bool _finishHandled = false;
  Future<void> _persisted = Future<void>.value();
  Future<void> _closed = Future<void>.value();

  /// Pinged on every ticker event while playing (timer ring only), so the
  /// 60 Hz tick does not rebuild the whole screen.
  final _Pulse _hud = _Pulse();
  ChangeNotifier get hudTick => _hud;

  /// Pinged when a new question starts being read, so the caption strip drops
  /// the previous question's feedback caption instead of showing it for up to
  /// its full display time.
  Listenable get captionReset => _captionReset;
  final _Pulse _captionReset = _Pulse();

  GamePhase get phase => _phase;

  /// Last permission result (null until asked).
  PermissionOutcome? get permission => _permission;
  CalibrationProgress? get calibrationProgress => _calibrationProgress;
  LevelSession? get session => _session;

  /// Result of the finished level (null while playing).
  LevelOutcome? get outcome => _outcome;

  /// Points earned so far: derived from the session's first-attempt correct
  /// count, so pause/resume or reviews can never double count.
  int get score => Scoring.points(_session?.correctCount ?? 0);

  /// Lane the player currently stands in (live, also while the question is
  /// being read aloud).
  int get selectedLane => _selectedLane;

  /// Whether the word lanes show their pictures as a hint right now (see
  /// [LevelSession.showTileHints]). Listeners are notified when it flips
  /// (e.g. `partial` crossing 50% of the time limit), not on every tick.
  bool get showTileHints => _session?.showTileHints ?? false;

  /// Input events (including synthetic presence events) for GameShell.
  Stream<GameInputEvent> get events => _events.stream;

  /// Completes when stars and history of the finished level are stored.
  Future<void> get persisted => _persisted;

  /// Completes when [dispose] has released everything.
  Future<void> get closed => _closed;

  ContentItem itemFor(String id) => _repo.byId(id);

  /// Asks for the camera, then (when granted) runs calibration and the level.
  /// May be called again after [GamePhase.permissionDenied].
  ///
  /// With no lessons for the grade (or when planning fails) nothing is started and the phase becomes
  /// [GamePhase.noContent] (the returned outcome is then `granted` only
  /// because the camera was never asked).
  Future<PermissionOutcome> start(PoseFrameSource source) {
    if (_disposed) return Future.value(PermissionOutcome.denied);
    // Already starting/running: never subscribe to the frames twice.
    return _startFuture ??= _start(source).whenComplete(() {
      if (_phase == GamePhase.permissionDenied) _startFuture = null;
    });
  }

  Future<PermissionOutcome> _start(PoseFrameSource source) async {
    _source = source;
    try {
      _plan = QuestionGenerator(_repo, _store, _rng).plan(
        level: level,
        pos: CurriculumPosition(
          grade: grade,
          currentUnitIndex: _store.currentUnit(grade),
        ),
        modes: {ModeKind.laneJump},
      );
    } catch (e, st) {
      // E.g. not enough distractors in the bundled content: behave like an
      // empty grade instead of leaving the child at a blank screen.
      debugPrint('GameController: planning the level failed: $e\n$st');
      _plan = const [];
    }
    if (_plan.isEmpty) {
      _setPhase(GamePhase.noContent);
      return PermissionOutcome.granted;
    }
    _setPhase(GamePhase.requestingPermission);
    // Once per controller: a retry from the permission screen re-enters here.
    if (!_welcomed) {
      _welcomed = true;
      unawaited(_audio.playLine(VoiceLine.welcome));
    }
    PermissionOutcome outcome;
    _cameraStarting = true;
    try {
      outcome = await source.start();
    } catch (_) {
      outcome = PermissionOutcome.denied;
    }
    _cameraStarting = false;
    if (_disposed) {
      // Disposed while the camera was starting: dispose could not stop it
      // yet, so release the orphan now.
      if (outcome == PermissionOutcome.granted) {
        try {
          await source.stop();
        } catch (_) {}
      }
      return outcome;
    }
    _permission = outcome;
    if (outcome != PermissionOutcome.granted) {
      _setPhase(GamePhase.permissionDenied);
      return outcome;
    }
    _calibrator = _calibratorFactory();
    _calibrationProgress = null;
    _setPhase(GamePhase.calibrating);
    _frameSub = source.frames.listen(_onFrame, onError: (Object _) {});
    return outcome;
  }

  void _onFrame(PoseFrame f) {
    if (_disposed) return;
    _lastFrameAt = _now;
    _lastFrameTs = f.timestamp;
    if (_phase == GamePhase.calibrating) {
      final p = _calibrator!.add(f);
      _calibrationProgress = p;
      _speakCalibrationIssue(p.issue, f.timestamp);
      if (p.result != null) {
        _beginPlay(p.result!);
      } else {
        notifyListeners();
      }
      return;
    }
    if (_phase != GamePhase.playing) return;
    // After a watchdog Lost, only a frame that actually shows someone ends
    // it: an empty frame would make PoseSession report Lost right after.
    if (_watchdogLost && f.poses.any((p) => p.midHipX != null)) {
      _watchdogLost = false;
      _setLost(false, PlayerFound(at: f.timestamp));
    }
    _poseFrames?.add(f);
  }

  /// Spoken hints while calibrating, each at most once per
  /// [issueLineEvery] (frame time), so a persistent issue is not nagged.
  static const issueLineEvery = Duration(seconds: 5);
  final Map<VoiceLine, Duration> _issueSpokenAt = {};

  void _speakCalibrationIssue(CalibrationIssue? issue, Duration at) {
    final line = switch (issue) {
      CalibrationIssue.notStill => VoiceLine.standStill,
      CalibrationIssue.tooClose => VoiceLine.stepBack,
      _ => null,
    };
    if (line == null) return;
    final last = _issueSpokenAt[line];
    if (last != null && at - last < issueLineEvery) return;
    _issueSpokenAt[line] = at;
    unawaited(_audio.playLine(line));
  }

  /// Whether a caption may be displayed now. Vietnamese lines always are; the
  /// spoken English word of a lane-jump question is held back until the child
  /// has answered: in every lane form (listen-pick-picture, see-picture-pick-
  /// word and listen-pick-word) the prompt deliberately hides the word, so
  /// its caption would reveal the answer.
  bool shouldShowCaption(String text) {
    if (VoiceLine.isCaption(text)) return true;
    final s = _session;
    if (s == null ||
        s.phase == SessionPhase.finished ||
        s.phase == SessionPhase.feedback) {
      return true;
    }
    final q = s.current.question;
    return !(q is ChoiceQuestion && _hidesWord.contains(q.form));
  }

  static const _hidesWord = {
    QuestionForm.listenPickPicture,
    QuestionForm.seePicturePickWord,
    QuestionForm.listenPickWord,
  };

  void _beginPlay(Calibration cal) {
    final frames = StreamController<PoseFrame>.broadcast(sync: true);
    _poseFrames = frames;
    final confirm = _store.confirmGesture;
    final pose = PoseSession(
      frames.stream,
      cal,
      laneCount: level.choiceCount,
      confirm: confirm,
    );
    _pose = pose;
    _selectedLane = pose.currentLane;
    _poseSub = pose.events.listen(_onPoseEvent, onError: (Object _) {});

    final s = LevelSession(
      level: level,
      plan: _plan,
      history: _store,
      feedbackTime: feedbackTime,
      makeRound: (pq, {required review}) => LaneJumpRound(
        pq.question as ChoiceQuestion,
        timeLimit: Scoring.timeFor(level, ModeKind.laneJump),
        initialLane: pose.currentLane,
      ),
    );
    _session = s;
    _lastFrameAt = _now;
    _lastTick = null;
    _tickSub = _tickerFactory().listen(_onTick);
    _setPhase(GamePhase.playing);
    // Before the first question; the audio queue keeps the order.
    unawaited(
      _audio.playLine(
        confirm == ConfirmGesture.raiseHands
            ? VoiceLine.raiseHandsToChoose
            : VoiceLine.jumpToChoose,
      ),
    );
    s.begin();
    _afterSessionChange();
  }

  // ---- input ----

  void _onPoseEvent(GameInputEvent e) {
    if (_disposed) return;
    // The watchdog and PoseSession can both report presence changes: only
    // real changes of the shared state get through (never Lost twice, never
    // Found while present).
    if (e is PlayerLost && _lost) return;
    if (e is PlayerFound && !_lost) return;
    _dispatch(e);
  }

  /// Test seam: behaves exactly like an event coming from [PoseSession].
  @visibleForTesting
  void debugInject(GameInputEvent e) => _dispatch(e);

  void _dispatch(GameInputEvent e) {
    if (e is LaneChanged) {
      _selectedLane = e.lane;
    }
    switch (e) {
      case PlayerLost():
        _lost = true;
        _session?.onEvent(e);
        _events.add(e);
      case PlayerFound():
        _lost = false;
        _watchdogLost = false;
        _events.add(e);
        _session?.onEvent(e);
      default:
        _session?.onEvent(e);
        _events.add(e);
    }
    _afterSessionChange();
    if (!_disposed) notifyListeners();
  }

  void _setLost(bool lost, GameInputEvent e) {
    if (lost == _lost) return;
    _dispatch(e);
  }

  // ---- time ----

  void _onTick(Duration elapsed) {
    if (_disposed) return;
    final s = _session;
    if (s == null) return;
    final prev = _lastTick;
    _lastTick = elapsed;
    _now = elapsed;
    var dt = prev == null ? Duration.zero : elapsed - prev;
    if (dt > maxTickStep) dt = maxTickStep;
    if (dt.isNegative) dt = Duration.zero;

    if (_promptPending && _now - _promptStartedAt >= promptWatchdog) {
      _finishPrompt(_promptToken);
    }
    if (_phase == GamePhase.playing &&
        !_lost &&
        _now - _lastFrameAt >= frameWatchdog) {
      _watchdogLost = true;
      _setLost(true, PlayerLost(at: _lastFrameTs));
    }
    s.tick(dt);
    _afterSessionChange();
    if (s.phase == SessionPhase.playing && !_disposed) {
      _hud.ping();
    }
  }

  // ---- session reactions ----

  void _afterSessionChange() {
    final s = _session;
    if (s == null || _disposed) return;
    final before = _lastSessionPhase;
    final now = s.phase;
    _lastSessionPhase = now;
    if (now == SessionPhase.prompting) _maybePrompt(s);
    if (now == SessionPhase.playing) _maybeStartRound(s);
    // Once per question: feedback -> paused -> feedback (player lost, app
    // backgrounded) must not award or speak a second time.
    if (now == SessionPhase.feedback &&
        !(identical(_fedBack, s.current) && _fedBackReview == s.isReview)) {
      _fedBack = s.current;
      _fedBackReview = s.isReview;
      _onFeedback(s);
    }
    if (now == SessionPhase.finished && !_finishHandled) _onFinished(s);
    final hints = s.showTileHints;
    final hintsChanged = hints != _lastTileHints;
    _lastTileHints = hints;
    if (before != now || hintsChanged) notifyListeners();
  }

  void _maybeStartRound(LevelSession s) {
    if (identical(_roundStarted, s.current) &&
        _roundStartedReview == s.isReview) {
      return;
    }
    _roundStarted = s.current;
    _roundStartedReview = s.isReview;
    // PoseSession compares against frame timestamps.
    _pose?.suppressConfirmUntil(_lastFrameTs + confirmGrace);
  }

  void _maybePrompt(LevelSession s) {
    final pq = s.current;
    if (identical(pq, _prompted) && _promptedReview == s.isReview) return;
    _prompted = pq;
    _promptedReview = s.isReview;
    final token = ++_promptToken;
    _promptPending = true;
    _promptStartedAt = _now;
    // Before the question's own (possibly synchronous) caption.
    _captionReset.ping();
    final q = pq.question;
    unawaited(
      _audio
          .sayEnglish(q.ttsText, itemId: q.itemId)
          .catchError((Object _) {})
          .then((_) => _finishPrompt(token)),
    );
  }

  void _finishPrompt(int token) {
    if (_disposed || token != _promptToken || !_promptPending) return;
    _promptPending = false;
    _session?.onPromptFinished();
    _afterSessionChange();
  }

  void _onFeedback(LevelSession s) {
    final result = s.lastResult;
    if (result == RoundResult.correct) {
      final line = [
        VoiceLine.correct1,
        VoiceLine.correct2,
        VoiceLine.correct3,
      ][_rng.nextInt(3)];
      unawaited(_audio.playLine(line));
      return;
    }
    unawaited(_explain(s.current.question));
  }

  Future<void> _explain(Question q) async {
    await _audio.playLine(VoiceLine.tryAgain);
    // Left the screen meanwhile: never speak on the next one.
    if (_disposed || q is! ChoiceQuestion) return;
    try {
      final correct = _repo.byId(q.choices[q.correctIndex].itemId);
      if (!_disposed) await _audio.explainAnswer(correct);
    } on StateError {
      // Unknown id: the tryAgain line alone is fine.
    }
  }

  void _onFinished(LevelSession s) {
    _finishHandled = true;
    final o = s.outcome!;
    _outcome = o;
    // saveStars updates the store's cache synchronously, so Home is correct
    // even before the disk write completes.
    final saved = _store.saveStars(grade, level.level, o.stars);
    if (o.stars >= 1) unawaited(_audio.playLine(VoiceLine.levelComplete));
    _persisted = () async {
      try {
        await saved;
      } catch (e) {
        debugPrint('GameController: saving stars failed: $e');
      }
      await s.historyWritten;
    }();
    _setPhase(GamePhase.finished);
    // Nothing more to see: release the camera (privacy, battery).
    unawaited(_stopInput());
  }

  /// Stops frames, pose tracking and the camera, once.
  Future<void> _stopInput() => _inputStopped ??= () async {
    // Release the camera first; the local clean-up runs alongside.
    final camera = () async {
      // A start still in flight stops the camera itself when it returns.
      if (_cameraStarting) return;
      try {
        await _source?.stop();
      } catch (_) {}
    }();
    // Cancelling/closing takes effect synchronously; the returned futures are
    // deliberately not awaited (they add nothing and can stall under
    // FakeAsync).
    _quiet(() => _frameSub?.cancel());
    _quiet(() => _poseSub?.cancel());
    _quiet(() => _pose?.dispose());
    _quiet(() => _poseFrames?.close());
    await camera;
  }();

  /// Fire-and-forget clean-up whose failure must never surface as an
  /// uncaught zone error.
  void _quiet(Future<Object?>? Function() f) {
    try {
      final r = f();
      if (r != null) {
        unawaited(
          r.then<void>(
            (_) {},
            onError: (Object e) => debugPrint('GameController: cleanup: $e'),
          ),
        );
      }
    } catch (e) {
      debugPrint('GameController: cleanup: $e');
    }
  }

  void _setPhase(GamePhase p) {
    _phase = p;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final session = _session;
    _closed = _shutdown(session);
    super.dispose();
  }

  Future<void> _shutdown(LevelSession? session) async {
    _quiet(() => _tickSub?.cancel());
    // Drop whatever is still being said; the audio stays usable for the
    // next screen (not muted).
    _audio.cancelAll();
    // Release the listeners first: a hung camera stop must not keep the
    // shell's subscription or the hud notifier alive (nothing below emits
    // on them any more: _disposed guards every producer).
    _quiet(_events.close);
    _hud.dispose();
    _captionReset.dispose();
    await _stopInput();
    // A permission/camera start still in flight finishes (and releases an
    // orphan camera) inside `closed`; the app bounds this wait.
    final pending = _startFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    try {
      await _persisted;
    } catch (_) {}
  }
}

class _Pulse extends ChangeNotifier {
  void ping() => notifyListeners();
}
