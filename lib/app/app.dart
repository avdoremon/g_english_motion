import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../audio/audio_service.dart';
import '../content/content_repository.dart';
import '../input/calibrator.dart';
import '../input/mediapipe_frame_source.dart';
import '../input/pose_frame_source.dart';
import '../levels/level_config.dart';
import '../progress/progress_store.dart';
import '../ui/mascot/tin_tin.dart';
import '../ui/parent/parent_gate.dart';
import '../ui/parent/parent_settings.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/lane_jump_screen.dart';
import '../ui/screens/result_screen.dart';
import '../ui/shell/calibration_screen.dart';
import '../ui/shell/game_shell.dart';
import '../ui/shell/permission_screen.dart';
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
    this.sayItAvailable = false,
    this.openSettings,
    Random? rng,
    this.closeTimeout = const Duration(seconds: 3),
    this.controllerFactory,
  }) : sourceFactory = sourceFactory ?? MediapipeFrameSource.new,
       ticker = ticker ?? periodicTicker,
       rng = rng ?? Random();

  final ProgressStore store;
  final AudioService audio;
  final ContentRepository repo;
  final List<LevelConfig> levels;

  /// A fresh camera/pose source for each play flow.
  final PoseFrameSource Function() sourceFactory;
  final TickerFactory ticker;
  final Wakelock wakelock;
  final Random rng;

  /// Whether on-device speech recognition exists. No recogniser is wired in
  /// this phase, so the SayIt entry stays hidden in production.
  final bool sayItAvailable;

  /// Longest wait for a previous controller to release the camera.
  final Duration closeTimeout;

  /// Test seam: builds the controller (default: the real one).
  final GameController Function(
    int grade,
    LevelConfig level,
    AppDependencies d,
  )?
  controllerFactory;

  /// Opens the OS app-settings page (permanently denied camera). Not wired
  /// yet: needs an app-settings plugin, so the button currently does nothing.
  final VoidCallback? openSettings;

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

class _Root extends StatefulWidget {
  const _Root({required this.deps});

  final AppDependencies deps;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  AppDependencies get _d => widget.deps;

  GameController? _ctl;
  PoseFrameSource? _source;
  (int, int)? _afterSafety;
  Future<void> _closing = Future<void>.value();

  @override
  void dispose() {
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
    await ctl.start(source);
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
    Navigator.of(context).push(
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
              child: ParentSettings(
                store: _d.store,
                grades: const [1, 2],
                unitCounts: {
                  for (final g in const [1, 2]) g: _d.repo.unitsFor(g).length,
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _afterSafety;
    if (pending != null) {
      return Scaffold(
        body: SafetyScreen(
          store: _d.store,
          onAcknowledged: () => _begin(pending.$1, pending.$2),
        ),
      );
    }
    final ctl = _ctl;
    if (ctl == null) {
      return Scaffold(
        body: HomeScreen(
          store: _d.store,
          sayItAvailable: _d.sayItAvailable,
          onPlay: _onPlay,
          onOpenParent: _openParent,
        ),
      );
    }
    return Scaffold(
      body: ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => GameShell(
          events: ctl.events,
          session: ctl.session,
          audio: _d.audio,
          wakelock: _d.wakelock,
          captionFilter: ctl.shouldShowCaption,
          child: _stage(ctl),
        ),
      ),
    );
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
            onOpenSettings: _d.openSettings ?? () {},
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
      case GamePhase.playing:
        return LaneJumpScreen(controller: ctl, onExit: _goHome);
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
