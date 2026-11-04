import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_service.dart';
import '../content/content_repository.dart';
import '../content/curriculum.dart';
import '../content/models.dart';
import '../content/question_generator.dart';
import '../input/calibrator.dart';
import '../input/plugin_pose_frame_source.dart';
import '../input/pose_frame_source.dart';
import '../levels/level_config.dart';
import '../levels/scoring.dart';
import '../modes/say_it.dart';
import '../progress/progress_store.dart';
import '../speech/on_device_speech_source.dart';
import '../speech/speech_session.dart';
import '../speech/speech_source.dart';
import '../ui/mascot/tin_tin.dart';
import '../ui/parent/parent_gate.dart';
import '../ui/parent/parent_settings.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/play_screen.dart';
import '../ui/screens/result_screen.dart';
import '../ui/screens/say_it_screen.dart';
import '../ui/shell/calibration_screen.dart';
import '../ui/shell/camera_problem_screen.dart';
import '../ui/shell/game_shell.dart';
import '../ui/shell/permission_screen.dart';
import '../ui/shell/pose_camera_host.dart';
import '../ui/shell/safety_screen.dart';
import '../ui/theme/app_theme.dart';
import 'game_controller.dart';

/// Everything the app needs from the outside world, so widget tests can
/// inject fakes (the real wiring lives in [AppDependencies.load]).
class AppDependencies {
  AppDependencies({
    required this.store,
    required this.audio,
    required this.repo,
    required this.levels,
    PoseFrameSource Function()? sourceFactory,
    TickerFactory? ticker,
    this.wakelock = const WakelockPlusAdapter(),
    this.speech,
    VoidCallback? openSettings,
    Random? rng,
    this.closeTimeout = const Duration(seconds: 3),
    this.controllerFactory,
    Widget? cameraHost,
  }) : sourceFactory = sourceFactory ?? PluginPoseFrameSource.new,
       // The real plugin source needs its preview view in the tree; an
       // injected (fake) source does not.
       cameraHost =
           cameraHost ??
           (sourceFactory == null ? const PoseCameraHost() : null),
       openSettings = openSettings ?? _openAppSettings,
       ticker = ticker ?? periodicTicker,
       rng = rng ?? Random();

  final ProgressStore store;
  final AudioService audio;
  final ContentRepository repo;
  final List<LevelConfig> levels;

  /// A fresh camera/pose source for each play flow.
  final PoseFrameSource Function() sourceFactory;

  /// Invisible platform view the pose plugin needs while its camera runs
  /// (see [PoseCameraHost]); placed once in the [GameShell] of a play flow.
  final Widget? cameraHost;
  final TickerFactory ticker;
  final Wakelock wakelock;
  final Random rng;

  /// On-device speech recognition for SayIt (null: SayIt is not offered).
  /// Never a recogniser that can use the network.
  final SpeechSource? speech;

  /// Longest wait for a previous controller to release the camera.
  final Duration closeTimeout;

  /// Test seam: builds the controller (default: the real one).
  final GameController Function(
    int grade,
    LevelConfig level,
    AppDependencies d,
  )?
  controllerFactory;

  /// Opens the OS app-settings page (permanently denied camera). Defaults to
  /// `permission_handler`'s [openAppSettings] (local OS call, no network).
  final VoidCallback openSettings;

  static void _openAppSettings() {
    unawaited(
      openAppSettings().then<void>(
        (_) {},
        onError: (Object e) => debugPrint('Opening app settings failed: $e'),
      ),
    );
  }

  /// Real objects: SharedPreferences, flutter_tts + just_audio, bundled
  /// content and level config.
  static Future<AppDependencies> load({AssetBundle? bundle}) async {
    final b = bundle ?? rootBundle;
    final prefs = await SharedPreferences.getInstance();
    final manifest = await AssetManifest.loadFromAssetBundle(b);
    final assets = manifest.listAssets().toSet();
    return AppDependencies(
      store: ProgressStore(prefs),
      audio: AudioService(
        FlutterTtsEngine(),
        JustAudioClipPlayer(),
        assetExists: assets.contains,
      ),
      repo: await ContentRepository.loadFromAssets(b),
      levels: await LevelConfig.load(b),
      speech: OnDeviceSpeechSource(SpeechToTextBackend()),
    );
  }

  /// Monotonic elapsed time, about 60 events per second.
  static Stream<Duration> periodicTicker() {
    final sw = Stopwatch()..start();
    return Stream<Duration>.periodic(
      const Duration(milliseconds: 16),
      (_) => sw.elapsed,
    );
  }
}

class GEnglishMotionApp extends StatelessWidget {
  const GEnglishMotionApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tin Tin English',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: _Root(deps: deps),
    );
  }
}

/// "No lessons yet" (Task 15 content not bundled): friendly, never a crash.
class NoLessonsView extends StatelessWidget {
  const NoLessonsView({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TinTin(state: TinTinState.sad, size: 120),
            const SizedBox(height: 16),
            Text('Chưa có bài học', style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tin Tin đang chuẩn bị bài mới cho em. Quay lại sau nhé!',
              style: t.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onClose, child: const Text('Đóng')),
          ],
        ),
      ),
    );
  }
}

/// One SayIt play-through (no camera): the level and its listening session.
class _SayItPlay {
  _SayItPlay({
    required this.grade,
    required this.level,
    required this.session,
    required this.game,
  });
  final int grade, level;
  final SpeechSession session;
  final SayItLevel game;
}

class _Root extends StatefulWidget {
  const _Root({required this.deps});

  final AppDependencies deps;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  AppDependencies get _d => widget.deps;

  GameController? _ctl;
  PoseFrameSource? _source;
  (int, int)? _afterSafety;

  /// SayIt availability: asked once the entry is wanted (the check may ask for
  /// the microphone), never assumed.
  SpeechAvailability _sayItAvailability =
      SpeechAvailability.noOnDeviceRecognizer;
  bool _sayItChecking = false;
  _SayItPlay? _sayIt;
  int _nextSessionId = 1;
  Future<void> _closing = Future<void>.value();

  /// Owned by the app session so re-entering the parent area cannot reset
  /// the wrong-answer count or skip a running lockout.
  final GateLockout _gateLockout = GateLockout();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSayIt();
  }

  /// Asks the speech source once (and again later while it said no, e.g. the
  /// parent granted the microphone in the system settings meanwhile).
  void _checkSayIt() {
    final speech = _d.speech;
    if (speech == null ||
        _sayItChecking ||
        _sayItAvailability == SpeechAvailability.available ||
        !_d.store.sayItEnabled) {
      return;
    }
    _sayItChecking = true;
    speech.check().then<void>(
      (a) {
        _sayItChecking = false;
        if (mounted && a != _sayItAvailability) {
          setState(() => _sayItAvailability = a);
        }
      },
      onError: (Object e) {
        _sayItChecking = false;
        debugPrint('SayIt availability check failed: $e');
      },
    );
  }

  /// The camera timeouts of the running game stand still while the app is
  /// not in the foreground (same signal as GameShell: only `resumed` counts).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _ctl?.setAppActive(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gateLockout.dispose();
    _closeSayIt();
    _ctl?.dispose();
    super.dispose();
  }

  void _onPlay(int grade, int level) {
    if (_d.repo.unitsFor(grade).isEmpty ||
        !_d.levels.any((l) => l.level == level)) {
      _showNoLessons();
      return;
    }
    if (SafetyScreen.needed(_d.store)) {
      setState(() => _afterSafety = (grade, level));
      return;
    }
    _begin(grade, level);
  }

  /// Starts SayIt: no camera, no pose source, no safety screen (the child
  /// stands still near the phone).
  void _beginSayIt(int grade, int level) {
    final speech = _d.speech;
    final cfg = _d.levels.where((l) => l.level == level).firstOrNull;
    if (speech == null || cfg == null) {
      _showNoLessons();
      return;
    }
    final words = QuestionGenerator(_d.repo, _d.store, _d.rng).sayItWords(
      pos: CurriculumPosition(
        grade: grade,
        currentUnitIndex: _d.store.currentUnit(grade),
      ),
      level: cfg,
      count: 9,
    );
    if (words.length < 3) {
      _showNoLessons();
      return;
    }
    final nine = [for (var i = 0; i < 9; i++) words[i % words.length]];
    final first = _nextSessionId;
    _nextSessionId += 9;
    _closeSayIt();
    unawaited(_d.wakelock.enable().catchError((Object _) {}));
    setState(() {
      _sayIt = _SayItPlay(
        grade: grade,
        level: level,
        session: SpeechSession(speech, _d.audio),
        game: SayItLevel.build(
          nine,
          travelTime: Scoring.timeFor(cfg, ModeKind.sayIt),
          rng: _d.rng,
          modelFirst: grade < 3,
          firstSessionId: first,
        ),
      );
    });
  }

  void _closeSayIt() {
    final p = _sayIt;
    if (p == null) return;
    _sayIt = null;
    unawaited(p.session.cancel());
    unawaited(_d.wakelock.disable().catchError((Object _) {}));
  }

  void _exitSayIt() {
    setState(_closeSayIt);
  }

  void _showNoLessons() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.background,
        child: NoLessonsView(onClose: () => Navigator.of(ctx).pop()),
      ),
    );
  }

  /// Starts a new play flow. The previous controller is released after the
  /// frame so its listeners can detach first. GameShell stays mounted across
  /// levels (same place in the tree), so its break clock keeps running for
  /// the whole play session.
  void _begin(int grade, int level) {
    final cfg = _d.levels.firstWhere((l) => l.level == level);
    final source = _d.sourceFactory();
    final ctl =
        _d.controllerFactory?.call(grade, cfg, _d) ??
        GameController(
          grade: grade,
          level: cfg,
          store: _d.store,
          repo: _d.repo,
          audio: _d.audio,
          ticker: _d.ticker,
          rng: _d.rng,
        );
    final old = _ctl;
    setState(() {
      _afterSafety = null;
      _ctl = ctl;
      _source = source;
    });
    _release(old);
    unawaited(_startWhenFree(ctl, source));
  }

  /// The camera channel is a singleton: the new flow may only start after
  /// every earlier controller finished shutting down (its camera stop would
  /// otherwise release the new camera).
  Future<void> _startWhenFree(
    GameController ctl,
    PoseFrameSource source,
  ) async {
    await _closing;
    // Superseded: its successor disposes it.
    if (!mounted || _ctl != ctl) return;
    try {
      await ctl.start(source);
    } catch (e, st) {
      // The controller handles its known failures itself (noContent); this
      // is the last resort so the child is never stuck on a blank screen.
      debugPrint('Starting the game failed: $e\n$st');
      if (!mounted || _ctl != ctl) return;
      _goHome();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Có lỗi rồi, em thử lại sau nhé!')),
        );
      });
    }
  }

  void _goHome() {
    final old = _ctl;
    setState(() {
      _ctl = null;
      _source = null;
      _afterSafety = null;
    });
    _release(old);
  }

  /// Disposes [c] after the frame (so listeners detach first); [_closing]
  /// completes when it is fully closed.
  void _release(GameController? c) {
    if (c == null) return;
    // Isolated and bounded: one hung native stop or failed write must not
    // block every later start.
    _closing = _closing
        .then((_) async {
          await WidgetsBinding.instance.endOfFrame;
          c.dispose();
          await c.closed.timeout(
            _d.closeTimeout,
            onTimeout: () =>
                debugPrint('close timed out — possible camera overlap'),
          );
        })
        .catchError((Object e) {
          debugPrint('Closing the previous game failed: $e');
        });
  }

  void _openParent() {
    final route = Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Quay lại',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: SafeArea(
            child: ParentGate(
              lockout: _gateLockout,
              child: ParentSettings(
                store: _d.store,
                grades: const [1, 2],
                unitCounts: {
                  for (final g in const [1, 2]) g: _d.repo.unitsFor(g).length,
                },
                // The only place that may ask for the microphone.
                onSayItTurnedOn: () async {
                  await _d.speech?.check(askPermission: true);
                },
              ),
            ),
          ),
        ),
      ),
    );
    // The parent may have switched SayIt on or granted the microphone.
    unawaited(route.then((_) => _checkSayIt()));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _afterSafety;
    if (pending != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _afterSafety = null);
        },
        child: Scaffold(
          body: SafetyScreen(
            store: _d.store,
            onAcknowledged: () => _begin(pending.$1, pending.$2),
          ),
        ),
      );
    }
    final sayIt = _sayIt;
    if (sayIt != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitSayIt();
        },
        child: Scaffold(
          body: SayItScreen(
            key: ObjectKey(sayIt),
            level: sayIt.game,
            speech: sayIt.session,
            audio: _d.audio,
            onExit: _exitSayIt,
            onPlayAgain: () => _beginSayIt(sayIt.grade, sayIt.level),
          ),
        ),
      );
    }
    final ctl = _ctl;
    if (ctl == null) {
      return Scaffold(
        body: HomeScreen(
          store: _d.store,
          sayItAvailability: _sayItAvailability,
          onPlay: _onPlay,
          onSayIt: _beginSayIt,
          onOpenParent: _openParent,
        ),
      );
    }
    // Back never exits the app from a play flow: it goes through the same
    // close path as the exit button (the controller is disposed, the camera
    // released). While a question is running, a grown-up-free confirmation
    // protects against an accidental swipe.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack(ctl);
      },
      child: Scaffold(
        body: ListenableBuilder(
          listenable: ctl,
          builder: (context, _) => GameShell(
            events: ctl.events,
            session: ctl.session,
            audio: _d.audio,
            wakelock: _d.wakelock,
            captionFilter: ctl.shouldShowCaption,
            captionReset: ctl.captionReset,
            cameraHost: _d.cameraHost,
            child: _stage(ctl),
          ),
        ),
      ),
    );
  }

  Future<void> _onBack(GameController ctl) async {
    if (ctl.phase != GamePhase.playing) {
      _goHome();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        title: const Text('Thoát trò chơi?'),
        actions: [
          TextButton(
            key: const ValueKey('stay'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            key: const ValueKey('leave'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Thoát'),
          ),
        ],
      ),
    );
    if (leave == true && mounted && _ctl == ctl) _goHome();
  }

  Widget _exitOverlay(Widget child) => Stack(
    children: [
      Positioned.fill(child: child),
      Positioned(
        left: 8,
        top: 8,
        child: SafeArea(
          child: IconButton(
            key: const ValueKey('exit'),
            tooltip: 'Thoát',
            iconSize: 36,
            onPressed: _goHome,
            icon: const Icon(Icons.close),
          ),
        ),
      ),
    ],
  );

  Widget _stage(GameController ctl) {
    switch (ctl.phase) {
      case GamePhase.idle:
      case GamePhase.requestingPermission:
        return _exitOverlay(
          const Center(child: TinTin(state: TinTinState.idle, size: 160)),
        );
      case GamePhase.permissionDenied:
        return _exitOverlay(
          PermissionScreen(
            outcome: ctl.permission ?? PermissionOutcome.denied,
            onRetry: () {
              final s = _source;
              if (s != null) unawaited(ctl.start(s));
            },
            onOpenSettings: _d.openSettings,
          ),
        );
      case GamePhase.noContent:
        return NoLessonsView(onClose: _goHome);
      case GamePhase.calibrating:
        return _exitOverlay(
          CalibrationScreen(
            progress:
                ctl.calibrationProgress ??
                const CalibrationProgress(progress: 0),
          ),
        );
      case GamePhase.cameraProblem:
        return CameraProblemScreen(
          onRetry: () => _begin(ctl.grade, ctl.level.level),
          onHome: _goHome,
        );
      case GamePhase.playing:
        return PlayScreen(controller: ctl, onExit: _goHome);
      case GamePhase.finished:
        final o = ctl.outcome!;
        final grade = ctl.grade, level = ctl.level.level;
        final hasNext = _d.levels.any((l) => l.level == level + 1);
        return ResultScreen(
          outcome: o,
          hasNext: hasNext,
          onPlayAgain: () => _begin(grade, level),
          onNext: () {
            if (o.unlockedNext && _d.levels.any((l) => l.level == level + 1)) {
              _begin(grade, level + 1);
            } else {
              _goHome();
            }
          },
        );
    }
  }
}
