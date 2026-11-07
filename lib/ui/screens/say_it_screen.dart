import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../audio/audio_service.dart';
import '../../audio/voice_lines.dart';
import '../../modes/round.dart';
import '../../modes/say_it.dart';
import '../../progress/progress_store.dart';
import '../../speech/speech_session.dart';
import '../../speech/word_judge.dart';
import '../mascot/tin_tin.dart';
import '../shell/play_surface.dart';
import '../theme/app_theme.dart';

/// SayIt: read the running word aloud.
///
/// No camera and no pose tracking here: the child stands 0.5-1 m from the
/// phone. The screen owns the clock (a [Ticker]) and the listening; all rules
/// are in [SayItRound].
///
/// - Grades 1-2 (`modelFirst`): Tin Tin reads the word first; it starts to run
///   (and the microphone opens) afterwards.
/// - While listening, music and effects are muted ([SpeechSession]).
/// - A word is graded only from what was heard: if the microphone fails, the
///   level pauses with a message instead of marking the child wrong.
/// - What the microphone hears is never stored: results go straight into
///   [SayItRound.onRecognized] and are dropped.
///
/// The screen is wrapped in a [PlaySurface] - the non-camera half of
/// [GameShell] - so its spoken lines appear as captions and its play time
/// counts towards the same break reminder as the camera modes. There is
/// deliberately no [GameShell] here: no camera host and no pose source.
class SayItScreen extends StatefulWidget {
  const SayItScreen({
    super.key,
    required this.level,
    required this.speech,
    required this.audio,
    required this.onExit,
    this.onPlayAgain,
    this.store,
    this.breakAfter = const Duration(minutes: 20),
    this.timerFactory = Timer.new,
  });

  final SayItLevel level;
  final SpeechSession speech;
  final AudioService audio;
  final VoidCallback onExit;
  final VoidCallback? onPlayAgain;

  /// Where play time is banked towards the break reminder (null: not
  /// counted, e.g. in widget tests of this screen alone).
  final ProgressStore? store;
  final Duration breakAfter;
  final BreakTimerFactory timerFactory;

  /// Longest frame step applied to the clock, so a stall does not eat a word.
  static const maxTickStep = Duration(milliseconds: 250);

  @override
  State<SayItScreen> createState() => _SayItScreenState();
}

class _SayItScreenState extends State<SayItScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  Duration? _last;
  int _roundIdx = 0;
  bool _paused = false;
  bool _micProblem = false;
  bool _done = false;

  int? _listeningFor; // session id of the word the microphone is open for
  int? _modelFor; // session id of the word whose model reading was started
  StreamSubscription<RecognitionResult>? _sub;

  /// The break reminder is up: the word stands still and the microphone is
  /// closed until a grown-up dismisses it (same rule as a pause).
  bool _breakDue = false;

  /// Nothing runs: backgrounded, or waiting on the break reminder.
  bool get _frozen => _paused || _breakDue;

  SayItRound get _round => widget.level.rounds[_roundIdx];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    unawaited(_stopListening());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active == !_paused) return;
    _paused = !active;
    if (_paused) {
      unawaited(_stopListening());
    } else {
      _last = null;
      _sync();
    }
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    final prev = _last;
    _last = elapsed;
    if (prev == null || _frozen || _micProblem || _done) return;
    var dt = elapsed - prev;
    if (dt > SayItScreen.maxTickStep) dt = SayItScreen.maxTickStep;
    if (dt <= Duration.zero) return;
    _round.tick(dt);
    _sync();
    if (mounted) setState(() {});
  }

  /// Brings listening and the model reading in line with the current word.
  void _sync() {
    if (!mounted || _done) return;
    while (_round.finished) {
      if (_roundIdx < widget.level.rounds.length - 1) {
        _roundIdx++;
      } else {
        _finish();
        return;
      }
    }
    final w = _round.current;
    Future<void>? stopped;
    if (w.phase == WordPhase.running && !_frozen && !_micProblem) {
      if (_listeningFor != w.sessionId) _startListening(w);
    } else if (_listeningFor != null) {
      stopped = _stopListening();
    }
    if (w.phase == WordPhase.waitingForModel && _modelFor != w.sessionId) {
      _startModel(w);
    }
    if (w.phase == WordPhase.judged) _reactOnce(w, after: stopped);
  }

  int? _reactedFor;

  /// Tin Tin's voice reaction, once per word. Sound is muted while the
  /// microphone is open, so it waits until listening has been stopped.
  void _reactOnce(SayItWord w, {Future<void>? after}) {
    if (_reactedFor == w.sessionId) return;
    _reactedFor = w.sessionId;
    final line = w.result == RoundResult.correct
        ? VoiceLine.correct1
        : VoiceLine.tryAgain;
    unawaited(
      (after ?? Future<void>.value()).then((_) {
        if (mounted) return widget.audio.playLine(line);
      }),
    );
  }

  void _startModel(SayItWord w) {
    _modelFor = w.sessionId;
    final round = _round;
    unawaited(
      widget.audio
          .sayEnglish(w.item.ttsText, itemId: w.item.id)
          // A broken model reading must not strand the word: it just runs.
          .catchError((Object _) {})
          .then((_) {
            if (!mounted || !identical(round, _round)) return;
            if (_modelFor != w.sessionId || _round.current != w) return;
            _round.onModelFinished();
            _sync();
            if (mounted) setState(() {});
          }),
    );
  }

  void _startListening(SayItWord w) {
    final id = w.sessionId;
    _listeningFor = id;
    _sub?.cancel();
    _sub = widget.speech
        .listenWhile(
          sessionId: id,
          keepListening: () =>
              mounted && !_frozen && !_micProblem && _listeningFor == id,
        )
        .listen(
          _onResult,
          onDone: () {
            // The source failed (not just stopped): do not blame the child.
            if (mounted && _listeningFor == id && widget.speech.failed) {
              setState(() => _micProblem = true);
              unawaited(_stopListening());
            }
          },
        );
  }

  Future<void> _stopListening() async {
    _listeningFor = null;
    final sub = _sub;
    _sub = null;
    unawaited(sub?.cancel());
    await widget.speech.cancel();
  }

  void _onResult(RecognitionResult r) {
    if (!mounted || _frozen || _micProblem || _done) return;
    _round.onRecognized(r);
    _sync();
    setState(() {});
  }

  void _finish() {
    _done = true;
    unawaited(
      _stopListening().then((_) {
        if (mounted) return widget.audio.playLine(VoiceLine.levelComplete);
      }),
    );
    if (mounted) setState(() {});
  }

  void _retryMic() {
    setState(() => _micProblem = false);
    _sync();
  }

  void _onBreakDue() {
    if (!mounted) return;
    setState(() => _breakDue = true);
    unawaited(_stopListening());
  }

  void _dismissBreak() {
    if (!mounted || !_breakDue) return;
    setState(() => _breakDue = false);
    // Do not count the pause as elapsed word time.
    _last = null;
    _sync();
  }

  TinTinState get _tinTin {
    if (_done) {
      return widget.level.stars >= 2 ? TinTinState.dance : TinTinState.cheer;
    }
    final w = _round.current;
    if (w.phase == WordPhase.judged || w.phase == WordPhase.exploding) {
      return w.result == RoundResult.correct
          ? TinTinState.happy
          : TinTinState.sad;
    }
    return TinTinState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: AppTheme.background,
      child: SafeArea(
        child: PlaySurface(
          audio: widget.audio,
          store: widget.store,
          breakAfter: widget.breakAfter,
          timerFactory: widget.timerFactory,
          // The clock counts only time actually spent reading words.
          paused: _frozen || _micProblem || _done,
          breakVisible: _breakDue,
          onBreakDue: _onBreakDue,
          onDismissBreak: _dismissBreak,
          overlay: _micProblem && !_done
              ? _MicProblem(onRetry: _retryMic, onExit: widget.onExit)
              : null,
          child: _done
              ? _ResultView(
                  level: widget.level,
                  onExit: widget.onExit,
                  onPlayAgain: widget.onPlayAgain,
                )
              : _play(t),
        ),
      ),
    );
  }

  /// Header, stage and footer as a real Column: the stage gets exactly what
  /// the measured header and footer leave over, instead of the fixed 88/120
  /// insets that left a judged word card without headroom on a 360 px tall
  /// screen (and clipped the Đúng/Sai row, the one thing the child needs).
  Widget _play(TextTheme t) {
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxHeight < 420;
        return Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(16, 4, 16, 4)
              : const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(
            children: [
              _header(t),
              SizedBox(height: compact ? 4 : 8),
              Expanded(child: _stage(compact: compact)),
              SizedBox(height: compact ? 4 : 8),
              _footer(t, compact: compact),
            ],
          ),
        );
      },
    );
  }

  Widget _footer(TextTheme t, {required bool compact}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TinTin(state: _tinTin, size: compact ? 72 : 104),
        const SizedBox(width: 16),
        Expanded(child: _hint(t)),
      ],
    );
  }

  Widget _header(TextTheme t) {
    final w = _round.current;
    final index = (w.sessionId - _round.words.first.sessionId) + 1;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('exit'),
          tooltip: 'Thoát',
          iconSize: 36,
          onPressed: widget.onExit,
          icon: const Icon(Icons.close),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Ván ${_roundIdx + 1}/${widget.level.rounds.length} · Từ $index/3',
            key: const ValueKey('say-it-progress'),
            style: t.bodyLarge,
          ),
        ),
        Icon(Icons.star, color: AppTheme.yellow, size: 32),
        const SizedBox(width: 4),
        Text(
          '${widget.level.correctOfNine}',
          key: const ValueKey('say-it-score'),
          style: t.bodyLarge,
        ),
      ],
    );
  }

  Widget _hint(TextTheme t) {
    final w = _round.current;
    final listening = w.phase == WordPhase.running && !_micProblem;
    final text = w.phase == WordPhase.waitingForModel
        ? 'Nghe Tin Tin đọc nhé'
        : (listening ? VoiceLine.sayTheWord.caption : '');
    return Row(
      key: const ValueKey('say-it-hint'),
      children: [
        if (listening) Icon(Icons.mic, color: AppTheme.accent, size: 36),
        if (w.phase == WordPhase.waitingForModel)
          Icon(Icons.volume_up, color: AppTheme.accent, size: 36),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: t.bodyLarge)),
      ],
    );
  }

  Widget _stage({bool compact = false}) {
    final w = _round.current;
    if (w.phase == WordPhase.gone) return const SizedBox.shrink();
    final alignment = switch (w.motion) {
      WordMotion.fallDown => Alignment(0, -1 + 2 * w.progress),
      WordMotion.rightToLeft => Alignment(1 - 2 * w.progress, 0),
    };
    final Widget child;
    if (w.phase == WordPhase.exploding) {
      child = _Explosion(
        key: const ValueKey('say-it-explosion'),
        progress: w.explosionProgress,
        size: compact ? 150 : 220,
      );
    } else {
      child = _WordCard(word: w, compact: compact);
    }
    return Align(
      key: const ValueKey('say-it-motion'),
      alignment: alignment,
      child: child,
    );
  }
}

/// The word, with "Đúng"/"Sai" (icon + text + colour) once judged.
class _WordCard extends StatelessWidget {
  const _WordCard({required this.word, this.compact = false});
  final SayItWord word;

  /// Short screens (a 360 px tall landscape phone): a smaller word and
  /// verdict, so both always fit the stage.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final judged = word.phase == WordPhase.judged;
    final ok = word.result == RoundResult.correct;
    final color = ok ? AppTheme.green : AppTheme.coral;
    return Semantics(
      label: judged
          ? '${word.item.word}, ${ok ? 'Đúng' : 'Sai'}'
          : word.item.word,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: const ValueKey('say-it-word'),
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 20, vertical: 6)
                : const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: judged ? color : AppTheme.accent,
                width: 4,
              ),
            ),
            child: Text(
              word.item.word,
              style: compact
                  ? AppTheme.textStyles.heading
                  : AppTheme.textStyles.title,
              textAlign: TextAlign.center,
            ),
          ),
          if (judged) ...[
            SizedBox(height: compact ? 4 : 8),
            Row(
              key: const ValueKey('say-it-verdict'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.cancel,
                  color: color,
                  size: compact ? 36 : 44,
                ),
                const SizedBox(width: 8),
                Text(
                  ok ? 'Đúng' : 'Sai',
                  style: AppTheme.textStyles.heading.copyWith(color: color),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Space Cadets burst: sparks flying out and fading, once (0.8 s, no flicker).
class _Explosion extends StatelessWidget {
  const _Explosion({super.key, required this.progress, this.size = 220});
  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Từ nổ tung',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _ExplosionPainter(progress)),
      ),
    );
  }
}

class _ExplosionPainter extends CustomPainter {
  _ExplosionPainter(this.t);
  final double t;

  static const _colors = [
    AppTheme.yellow,
    AppTheme.coral,
    AppTheme.accent,
    AppTheme.green,
    AppTheme.orange,
    AppTheme.purple,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final eased = 1 - math.pow(1 - t, 3).toDouble();
    final fade = (1 - t).clamp(0.0, 1.0);
    canvas.drawCircle(
      c,
      r * 0.35 * (0.4 + eased),
      Paint()..color = AppTheme.yellow.withValues(alpha: 0.35 * fade),
    );
    const sparks = 12;
    for (var i = 0; i < sparks; i++) {
      final a = i * 2 * math.pi / sparks;
      final d = Offset(math.cos(a), math.sin(a));
      final from = c + d * (r * 0.25 * eased);
      final to = c + d * (r * (0.35 + 0.65 * eased));
      final color = _colors[i % _colors.length].withValues(alpha: fade);
      canvas.drawLine(
        from,
        to,
        Paint()
          ..color = color
          ..strokeWidth = 8 * (1 - 0.5 * t)
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(to, 6 * (1 - 0.5 * t), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ExplosionPainter old) => old.t != t;
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.level,
    required this.onExit,
    required this.onPlayAgain,
  });
  final SayItLevel level;
  final VoidCallback onExit;
  final VoidCallback? onPlayAgain;

  @override
  Widget build(BuildContext context) {
    final stars = level.stars;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              key: const ValueKey('say-it-stars'),
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Icon(
                    i < stars ? Icons.star : Icons.star_border,
                    size: 64,
                    color: i < stars ? AppTheme.yellow : AppTheme.muted,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Đúng ${level.correctOfNine}/9 từ',
              key: const ValueKey('say-it-total'),
              style: AppTheme.textStyles.heading,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (onPlayAgain != null)
                  FilledButton(
                    key: const ValueKey('say-it-again'),
                    onPressed: onPlayAgain,
                    child: const Text('Chơi lại'),
                  ),
                FilledButton(
                  key: const ValueKey('say-it-home'),
                  onPressed: onExit,
                  child: const Text('Về nhà'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MicProblem extends StatelessWidget {
  const _MicProblem({required this.onRetry, required this.onExit});
  final VoidCallback onRetry, onExit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ColoredBox(
      key: const ValueKey('say-it-mic-problem'),
      color: AppTheme.background.withValues(alpha: 0.94),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TinTin(state: TinTinState.sad, size: 120),
              const SizedBox(height: 12),
              Text(
                'Micro đang gặp sự cố, em thử lại nhé!',
                style: t.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                children: [
                  FilledButton(
                    key: const ValueKey('say-it-retry'),
                    onPressed: onRetry,
                    child: const Text('Thử lại'),
                  ),
                  FilledButton(
                    key: const ValueKey('say-it-mic-home'),
                    onPressed: onExit,
                    child: const Text('Về nhà'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
