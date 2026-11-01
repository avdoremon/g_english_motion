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

  int _score = 0;
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

  SessionPhase? _lastSessionPhase;
  bool _disposed = false;
  bool _finishHandled = false;
  Future<void> _persisted = Future<void>.value();
  Future<void> _closed = Future<void>.value();

  GamePhase get phase => _phase;

  /// Last permission result (null until asked).
  PermissionOutcome? get permission => _permission;
  CalibrationProgress? get calibrationProgress => _calibrationProgress;
  LevelSession? get session => _session;

  /// Result of the finished level (null while playing).
  LevelOutcome? get outcome => _outcome;

  /// Points earned so far (first-attempt correct answers only).
  int get score => _score;

  /// Lane the player currently stands in (live, also while the question is
  /// being read aloud).
  int get selectedLane => _selectedLane;

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
  /// With no lessons for the grade nothing is started and the phase becomes
  /// [GamePhase.noContent] (the returned outcome is then `granted` only
  /// because the camera was never asked).
  Future<PermissionOutcome> start(PoseFrameSource source) async {
    if (_disposed) return PermissionOutcome.denied;
    _source = source;
    _plan = QuestionGenerator(_repo, _store, _rng).plan(
      level: level,
      pos: CurriculumPosition(
        grade: grade,
        currentUnitIndex: _store.currentUnit(grade),
      ),
      modes: {ModeKind.laneJump},
    );
    if (_plan.isEmpty) {
      _setPhase(GamePhase.noContent);
      return PermissionOutcome.granted;
    }
    _setPhase(GamePhase.requestingPermission);
    PermissionOutcome outcome;
    try {
      outcome = await source.start();
    } catch (_) {
      outcome = PermissionOutcome.denied;
    }
    if (_disposed) return outcome;
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
    if (_phase == GamePhase.calibrating) {
      final p = _calibrator!.add(f);
      _calibrationProgress = p;
      if (p.result != null) {
        _beginPlay(p.result!);
      } else {
        notifyListeners();
      }
      return;
    }
    if (_phase != GamePhase.playing) return;
    if (_watchdogLost) {
      _watchdogLost = false;
      _setLost(false, PlayerFound(at: f.timestamp));
    }
    _poseFrames?.add(f);
  }

  void _beginPlay(Calibration cal) {
    final frames = StreamController<PoseFrame>.broadcast(sync: true);
    _poseFrames = frames;
    final pose = PoseSession(frames.stream, cal, laneCount: level.choiceCount);
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
    s.begin();
    _afterSessionChange();
  }

  // ---- input ----

  void _onPoseEvent(GameInputEvent e) {
    if (_disposed) return;
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
      _setLost(true, PlayerLost(at: elapsed));
    }
    s.tick(dt);
    _afterSessionChange();
    if (s.phase == SessionPhase.playing) notifyListeners();
  }

  // ---- session reactions ----

  void _afterSessionChange() {
    final s = _session;
    if (s == null || _disposed) return;
    final before = _lastSessionPhase;
    final now = s.phase;
    _lastSessionPhase = now;
    if (now == SessionPhase.prompting) _maybePrompt(s);
    if (now == SessionPhase.feedback && before != SessionPhase.feedback) {
      _onFeedback(s);
    }
    if (now == SessionPhase.finished && !_finishHandled) _onFinished(s);
    if (before != now) notifyListeners();
  }

  void _maybePrompt(LevelSession s) {
    final pq = s.current;
    if (identical(pq, _prompted) && _promptedReview == s.isReview) return;
    _prompted = pq;
    _promptedReview = s.isReview;
    final token = ++_promptToken;
    _promptPending = true;
    _promptStartedAt = _now;
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
      if (!s.isReview) _score += Scoring.points(1);
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
    if (q is! ChoiceQuestion) return;
    try {
      final correct = _repo.byId(q.choices[q.correctIndex].itemId);
      await _audio.explainAnswer(correct);
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
    await _tickSub?.cancel();
    await _frameSub?.cancel();
    await _poseSub?.cancel();
    await _pose?.dispose();
    await _poseFrames?.close();
    // Drop whatever is still being said and let the next screen speak.
    _audio.muteForListening();
    _audio.restoreAfterListening();
    try {
      await _source?.stop();
    } catch (_) {}
    await _events.close();
    try {
      await _persisted;
    } catch (_) {}
  }
}
