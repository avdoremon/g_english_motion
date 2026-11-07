// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:math';
import 'dart:ui' show Offset, Rect;

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
import '../modes/catch_it.dart';
import '../modes/drag_spell.dart';
import '../modes/hold_pick.dart';
import '../modes/lane_jump.dart';
import '../modes/mode_availability.dart';
import '../modes/round.dart';
import '../modes/sky_shoot.dart';
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

  /// The camera delivers nothing usable (no frames, persistent errors, or
  /// calibration never completes); the session was stopped and the camera
  /// released. The UI offers retry / home.
  cameraProblem,
}

/// Source of monotonic elapsed time, one event per frame. Tests drive it by
/// hand; production uses a periodic stream.
typedef TickerFactory = Stream<Duration> Function();

/// Lets the welcome line be spoken once per APP session. A controller is
/// built per level, so a flag inside it would greet the child again at every
/// level; the app owns one gate and hands it to each controller.
class WelcomeGate {
  bool _done = false;

  /// True exactly once (for the first caller), false afterwards.
  bool take() {
    if (_done) return false;
    _done = true;
    return true;
  }
}

/// Orchestrates one play-through (grades 1-2 LaneJump, grades 3-5 DragSpell
/// and SkyShoot):
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
/// - Camera problems: the ticker also runs during calibration. No frame for
///   [calibrationNoFrameTimeout], source errors without a frame in between
///   for [failureTimeout] (calibration or play), or a calibration that does
///   not finish within [calibrationTimeout] end in [GamePhase.cameraProblem]:
///   the session is paused, the camera released, and the app offers a retry
///   (a new controller + source, started after this one closed). The timers
///   stand still while the app is in the background ([setAppActive]).
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
    this.mode,
    required ProgressStore store,
    required ContentRepository repo,
    required AudioService audio,
    required TickerFactory ticker,
    Random? rng,
    WelcomeGate? welcome,
    this.castLatency = defaultCastLatency,
    Calibrator Function()? calibratorFactory,
    this.feedbackTime = const Duration(milliseconds: 2500),
    this.frameWatchdog = const Duration(seconds: 2),
    this.promptWatchdog = const Duration(seconds: 12),
    this.calibrationNoFrameTimeout = const Duration(seconds: 5),
    this.calibrationTimeout = const Duration(seconds: 30),
    this.failureTimeout = const Duration(seconds: 5),
  }) : _store = store,
       _repo = repo,
       _audio = audio,
       _tickerFactory = ticker,
       _rng = rng ?? Random(),
       _welcome = welcome ?? WelcomeGate(),
       _calibratorFactory = calibratorFactory ?? Calibrator.new;

  static const maxTickStep = Duration(milliseconds: 250);

  /// The chosen [mode] when it is offered at [grade], else the grade's default
  /// mix (grades 1-2 LaneJump; 3-5 DragSpell and SkyShoot).
  Set<ModeKind> get _modes => activeModes;

  @visibleForTesting
  Set<ModeKind> get activeModes {
    final m = mode;
    return m != null && modesForGrade(grade).contains(m)
        ? {m}
        : defaultModesForGrade(grade);
  }

  /// Arrow sweep speed (fractions of the width per second) of [level]: the
  /// higher the level, the faster (0.24 .. 0.40).
  static double sweepSpeedFor(LevelConfig level) => 0.2 + 0.04 * level.level;

  /// Placeholder until the cast latency of the real displays is measured
  /// (spike, Task 0): camera event -> what the child sees on the TV.
  static const defaultCastLatency = Duration(milliseconds: 250);

  final int grade;
  final LevelConfig level;

  /// Mode chosen in the picker; null plays the grade's default mix.
  final ModeKind? mode;

  /// SkyShoot scores a shot where the arrow was this long before the event.
  final Duration castLatency;
  final Duration feedbackTime, frameWatchdog, promptWatchdog;

  /// Calibration: no frame at all for this long => [GamePhase.cameraProblem].
  final Duration calibrationNoFrameTimeout;

  /// Calibration: frames arrive but it never completes within this long
  /// (measured on the injected ticker) => [GamePhase.cameraProblem].
  final Duration calibrationTimeout;

  /// Source errors with no frame in between for this long (calibration or
  /// play) => [GamePhase.cameraProblem].
  final Duration failureTimeout;

  final ProgressStore _store;
  final ContentRepository _repo;
  final AudioService _audio;
  final TickerFactory _tickerFactory;
  final Random _rng;

  /// Shared with every other controller of this app session: the welcome
  /// line is said once, not at every level.
  final WelcomeGate _welcome;
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
  StreamSubscription<PoseSourceFailure>? _failSub;
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

  // Calibration/failure timing, all on the ticker clock ([_now]).
  Duration? _calibAnchor;
  Duration? _calibLastFrame;
  Duration? _failedSince;

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

  /// First moments of each question: jumps are ignored (spec: 500 ms).
  static const confirmGrace = Duration(milliseconds: 500);

  SessionPhase? _lastSessionPhase;
  bool _lastTileHints = false;
  bool _lastPromptHint = false;
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

  /// Whether the hint picture beside the prompt is shown right now (see
  /// [LevelSession.showPromptHint]). Listeners are notified when it flips,
  /// so the DragSpell / SkyShoot prompt does not rebuild on every tick.
  bool get showPromptHint => _session?.showPromptHint ?? false;

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
        modes: _modes,
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
    // Once per app session: a retry from the permission screen re-enters
    // here, and a new level builds a new controller.
    if (_welcome.take()) {
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
    _calibAnchor = null;
    _calibLastFrame = null;
    _failedSince = null;
    _setPhase(GamePhase.calibrating);
    // The ticker also times calibration (it used to start only with play).
    _tickSub ??= _tickerFactory().listen(_onTick);
    _frameSub = source.frames.listen(
      _onFrame,
      onError: (Object e) => _onSourceFailure(e),
    );
    _failSub = source.failures.listen(_onSourceFailure);
    return outcome;
  }

  /// Whether the app is in the foreground (lifecycle `resumed`). While it is
  /// not, the camera delivers nothing, so the calibration/failure timeouts
  /// must not run (see [_resyncTimers]).
  bool get appActive => _appActive;
  bool _appActive = true;

  Duration? _inactiveFrom;
  bool _resyncPending = false;

  /// Told by the app on every lifecycle change (`true` only for `resumed`).
  /// While inactive the calibration/failure timeouts stand still; the first
  /// tick after the resume restarts the no-frame and error timers and moves
  /// the 30 s calibration clock forward by the time spent away.
  void setAppActive(bool active) {
    if (_disposed || active == _appActive) return;
    _appActive = active;
    if (active) {
      _resyncPending = true;
    } else {
      _inactiveFrom = _lastTick ?? _now;
    }
  }

  /// Run on the first tick after a resume (or after a tick gap larger than
  /// [maxTickStep], e.g. a suspended process whose lifecycle callback was
  /// missed): background time is not camera silence.
  void _resyncTimers(Duration now, Duration from) {
    final away = now - from;
    if (away > Duration.zero && _calibAnchor != null) {
      _calibAnchor = _calibAnchor! + away;
    }
    if (_phase == GamePhase.calibrating) _calibLastFrame = now;
    if (_failedSince != null) _failedSince = now;
  }

  void _onSourceFailure(Object e) {
    if (_disposed ||
        (_phase != GamePhase.calibrating && _phase != GamePhase.playing)) {
      return;
    }
    debugPrint('GameController: camera/pose source error: $e');
    _failedSince ??= _now;
  }

  /// Gives up on the camera: stops the session and input (camera released)
  /// and shows the camera-problem screen. A retry builds a new controller and
  /// source, after this one is fully closed (see the app's `_release`).
  void _enterCameraProblem(String why) {
    if (_disposed ||
        _phase == GamePhase.cameraProblem ||
        _phase == GamePhase.finished) {
      return;
    }
    debugPrint('GameController: camera problem: $why');
    _quiet(() => _tickSub?.cancel());
    _tickSub = null;
    _promptPending = false;
    _promptToken++;
    _session?.pause();
    _audio.cancelAll();
    _setPhase(GamePhase.cameraProblem);
    unawaited(_stopInput());
  }

  void _checkCalibrationTimeouts(Duration now) {
    final anchor = _calibAnchor ??= now;
    final lastFrame = _calibLastFrame ?? anchor;
    if (now - lastFrame >= calibrationNoFrameTimeout) {
      _enterCameraProblem('no camera frame during calibration');
    } else if (_failedSince != null && now - _failedSince! >= failureTimeout) {
      _enterCameraProblem('camera errors during calibration');
    } else if (now - anchor >= calibrationTimeout) {
      _enterCameraProblem('calibration did not finish');
    }
  }

  void _onFrame(PoseFrame f) {
    if (_disposed) return;
    _failedSince = null;
    _lastFrameAt = _now;
    if (_phase == GamePhase.calibrating) _calibLastFrame = _now;
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
    // Spell / order: the spoken word or sentence IS the answer.
    if (q is SpellQuestion || q is OrderQuestion) return false;
    return !(q is ChoiceQuestion && _hidesWord.contains(q.form));
  }

  static const _hidesWord = {
    QuestionForm.listenPickPicture,
    QuestionForm.seePicturePickWord,
    QuestionForm.listenPickWord,
    // memoryFlip / balloonPop: the picture is the prompt, the word the answer.
    QuestionForm.memoryMatch,
    QuestionForm.popWord,
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
      // The hand cursor is also what memoryFlip / balloonPop are played with,
      // at any grade. It is independent of the lane / jump tracking.
      cursor:
          grade >= 3 ||
          activeModes.contains(ModeKind.memoryFlip) ||
          activeModes.contains(ModeKind.balloonPop),
      pull: grade >= 3,
    );
    _pose = pose;
    _selectedLane = pose.currentLane;
    _poseSub = pose.events.listen(_onPoseEvent, onError: (Object _) {});

    final s = LevelSession(
      level: level,
      plan: _plan,
      history: _store,
      feedbackTime: feedbackTime,
      makeRound: (pq, {required review}) => _makeRound(pq, pose),
    );
    _session = s;
    _lastFrameAt = _now;
    _lastTick = null;
    _tickSub ??= _tickerFactory().listen(_onTick);
    _setPhase(GamePhase.playing);
    // Before the first question; the audio queue keeps the order.
    if (grade < 3) {
      unawaited(
        _audio.playLine(
          confirm == ConfirmGesture.raiseHands
              ? VoiceLine.raiseHandsToChoose
              : VoiceLine.jumpToChoose,
        ),
      );
    }
    s.begin();
    _afterSessionChange();
  }

  Round _makeRound(PlannedQuestion pq, PoseSession pose) {
    final q = pq.question;
    switch (pq.mode) {
      case ModeKind.dragSpell:
        if (q is SpellQuestion) {
          return DragSpellRound.spell(
            q,
            timeLimit: Scoring.timeFor(
              level,
              ModeKind.dragSpell,
              slots: q.tiles.length,
            ),
          );
        }
        if (q is OrderQuestion) {
          return DragSpellRound.order(
            q,
            timeLimit: Scoring.timeFor(
              level,
              ModeKind.dragSpell,
              slots: q.words.length,
            ),
          );
        }
      case ModeKind.laneJump:
        if (q is ChoiceQuestion) {
          return LaneJumpRound(
            q,
            timeLimit: Scoring.timeFor(level, ModeKind.laneJump),
            initialLane: pose.currentLane,
          );
        }
      case ModeKind.skyShoot:
        if (q is ChoiceQuestion) {
          return SkyShootRound(
            q,
            timeLimit: Scoring.timeFor(level, ModeKind.skyShoot),
            field: SkyField(
              rng: _rng,
              answerCount: q.choices.length,
              sweepSpeed: sweepSpeedFor(level),
            ),
            castLatency: castLatency,
          );
        }
      case ModeKind.sayIt:
        break;
      case ModeKind.catchIt:
        if (q is ChoiceQuestion) {
          return CatchItRound(
            q,
            timeLimit: Scoring.timeFor(level, ModeKind.catchIt),
            initialLane: pose.currentLane,
          );
        }
      case ModeKind.memoryFlip:
        if (q is ChoiceQuestion) {
          return HoldPickRound(
            q,
            timeLimit: Scoring.timeFor(level, ModeKind.memoryFlip),
            holdTime: const Duration(seconds: 1),
            peek: const Duration(seconds: 2),
            targetRect: _holdRect(q.choices.length),
          );
        }
      case ModeKind.balloonPop:
        if (q is ChoiceQuestion) {
          return HoldPickRound(
            q,
            timeLimit: Scoring.timeFor(level, ModeKind.balloonPop),
            holdTime: const Duration(milliseconds: 600),
            targetRect: _holdRect(q.choices.length),
          );
        }
    }
    throw StateError('No round for ${pq.mode} with ${q.runtimeType}');
  }

  Rect Function(int choice)? _holdLayout;

  /// The screen's real layout of the hold-to-pick targets (memoryFlip,
  /// balloonPop): the normalised (0..1) rect of choice `i`, in the same space
  /// as [CursorMoved]. The round reads it lazily, so a layout change takes
  /// effect at once, also mid-round. Does not notify (call it while building).
  void setHoldLayout(Rect Function(int choice) targetRect) {
    _holdLayout = targetRect;
  }

  /// Back to the default placeholder grid (the screen went away). With
  /// [only], clears just if that is still the current layout: a screen that
  /// is disposed after its successor set its own must not wipe it.
  void clearHoldLayout([Rect Function(int choice)? only]) {
    if (only != null && !identical(only, _holdLayout)) return;
    _holdLayout = null;
  }

  Rect Function(int) _holdRect(int n) {
    final fallback = _defaultChoiceRect(n);
    return (i) => (_holdLayout ?? fallback)(i);
  }

  /// Placeholder layout of [n] choices for [HoldPickRound] while no screen
  /// supplies one: a grid of up to 3 columns whose cells use 70 % of their
  /// slot, so there are gaps between them and margins at the edges: a hand
  /// resting in a gap picks nothing.
  static Rect Function(int) _defaultChoiceRect(int n) {
    final cols = n <= 3 ? n : (n + 1) ~/ 2;
    final rows = (n + cols - 1) ~/ cols;
    return (i) => Rect.fromCenter(
      center: Offset(((i % cols) + 0.5) / cols, ((i ~/ cols) + 0.5) / rows),
      width: 0.7 / cols,
      height: 0.7 / rows,
    );
  }

  /// Touch / hold fallback: the player held (or tapped) the target
  /// [targetId]: DragSpell `tile:<i>`, `slot:<i>`, `check`; memoryFlip and
  /// balloonPop `choice:<i>`.
  void holdTarget(String targetId) {
    if (_disposed) return;
    _session?.act((r) {
      if (r is DragSpellRound) r.onTargetHeld(targetId);
      if (r is HoldPickRound) r.onTargetHeld(targetId);
    });
    _afterSessionChange();
    if (!_disposed) notifyListeners();
  }

  /// Time on the clock of the pose frames' timestamps right now (the latest
  /// frame plus the time since it arrived). SkyShoot draws its field at this
  /// time, so the child sees the arrow where a shot is scored.
  Duration get frameClock => _lastFrameTs + (_now - _lastFrameAt);

  /// Touch fallback for SkyShoot (a tap shoots / pulls): behaves like an
  /// event coming from [PoseSession].
  void touchInput(GameInputEvent e) {
    if (_disposed || e is PlayerLost || e is PlayerFound) return;
    _dispatch(e);
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
      // The session drops lane changes outside the playing phase; catchIt
      // grades the lane at the catch line, so keep its round current anyway.
      final s = _session;
      if (s != null && s.phase != SessionPhase.finished) {
        final r = s.round;
        if (r is CatchItRound) r.syncLane(e.lane);
      }
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
    // The cursor moves ~15 times a second: screens follow it themselves.
    if (!_disposed && e is! CursorMoved) notifyListeners();
  }

  void _setLost(bool lost, GameInputEvent e) {
    if (lost == _lost) return;
    _dispatch(e);
  }

  // ---- time ----

  void _onTick(Duration elapsed) {
    if (_disposed) return;
    final prev = _lastTick;
    _lastTick = elapsed;
    _now = elapsed;
    if (_appActive && _resyncPending) {
      _resyncPending = false;
      _resyncTimers(elapsed, _inactiveFrom ?? prev ?? elapsed);
      _inactiveFrom = null;
    } else if (_appActive && prev != null && elapsed - prev > maxTickStep) {
      _resyncTimers(elapsed, prev);
    }
    // Camera timeouts stand still in the background (no camera, no frames).
    if (_phase == GamePhase.calibrating) {
      if (_appActive) _checkCalibrationTimeouts(elapsed);
      return;
    }
    final s = _session;
    if (s == null || _phase == GamePhase.cameraProblem) return;
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
    if (_appActive &&
        _phase == GamePhase.playing &&
        _failedSince != null &&
        _now - _failedSince! >= failureTimeout) {
      _enterCameraProblem('camera errors during play');
      return;
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
    if (now == SessionPhase.playing) {
      _maybeStartRound(s);
      _maybeCheerPull(s);
    }
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
    final promptHint = s.showPromptHint;
    final hintsChanged =
        hints != _lastTileHints || promptHint != _lastPromptHint;
    _lastTileHints = hints;
    _lastPromptHint = promptHint;
    if (before != now || hintsChanged) notifyListeners();
  }

  Round? _pullCheered;

  /// "Kéo dây" once per SkyShoot question, when the arrow hit something.
  void _maybeCheerPull(LevelSession s) {
    final r = s.round;
    if (r is! SkyShootRound ||
        r.phase != SkyPhase.reeling ||
        identical(_pullCheered, r)) {
      return;
    }
    _pullCheered = r;
    unawaited(_audio.playLine(VoiceLine.pullTheRope));
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
    // The player left during the prompt: a hold-pick round (peek, clock) must
    // not run with nobody there. Lane rounds keep their existing behaviour.
    if (_lost && s.round is HoldPickRound) {
      s.onEvent(PlayerLost(at: _lastFrameTs));
    }
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
          .sayEnglish(q.ttsText, itemId: _clipId(q))
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
    // A timeout opens with the neutral line: the child is told the time ran
    // out, never that the answer was wrong (it may never have been seen).
    unawaited(
      _explain(
        s.current,
        s.isReview,
        opening: result == RoundResult.timeout
            ? VoiceLine.outOfTime
            : VoiceLine.tryAgain,
      ),
    );
  }

  /// Whether an explanation started for [pq] may still speak: the controller
  /// is alive and the session is still on that question's feedback (a pause
  /// keeps it there). Once the session has moved on to the next question the
  /// rest of the explanation is dropped instead of talking over its prompt.
  bool _stillExplaining(PlannedQuestion pq, bool review) {
    final s = _session;
    if (_disposed || s == null) return false;
    if (s.phase != SessionPhase.feedback && s.phase != SessionPhase.paused) {
      return false;
    }
    return identical(s.current, pq) && s.isReview == review;
  }

  /// The recorded word clip may stand in for the spoken text only when the
  /// text is exactly the item's word: a sentence (order) or a gap sentence
  /// (fill-in) must go through TTS, or the clip would say the answer.
  String? _clipId(Question q) => switch (q) {
    OrderQuestion() => null,
    ChoiceQuestion(form: QuestionForm.fillBlank) => null,
    _ => q.itemId,
  };

  Future<void> _explain(
    PlannedQuestion pq,
    bool review, {
    required VoiceLine opening,
  }) async {
    final q = pq.question;
    await _audio.playLine(opening);
    // Left the screen, or the next question is already up: never speak over
    // it (the legs together outlast the 2.5 s feedback once clips ship).
    if (!_stillExplaining(pq, review)) return;
    try {
      switch (q) {
        case ChoiceQuestion():
          final correct = _repo.byId(q.choices[q.correctIndex].itemId);
          if (_stillExplaining(pq, review)) {
            await _audio.explainAnswer(correct);
          }
        case SpellQuestion():
          if (_stillExplaining(pq, review)) {
            await _audio.explainAnswer(_repo.byId(q.itemId));
          }
        case OrderQuestion():
          await _audio.playLine(VoiceLine.theAnswerIs);
          if (_stillExplaining(pq, review)) {
            await _audio.sayEnglish(q.answer.join(' '));
          }
      }
    } on StateError {
      // Unknown id: the opening line alone is fine.
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
    _quiet(() => _failSub?.cancel());
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
