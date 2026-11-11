import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../content/models.dart';
import 'voice_lines.dart';

abstract class SpeechEngine {
  Future<bool> isEnglishAvailable();

  /// Completes when the utterance has finished (or was stopped).
  Future<void> speak(String text);

  /// Interrupts any in-flight utterance.
  Future<void> stop();

  Future<void> dispose();
}

abstract class ClipPlayer {
  /// Plays [assetPath] to the end; returns false if it could not be played
  /// to completion.
  Future<bool> play(String assetPath);

  /// Interrupts any in-flight clip.
  Future<void> stop();

  Future<void> dispose();
}

/// Speech and clips with graceful fallback: recorded clip -> TTS -> caption
/// only. Never throws.
///
/// All playback is serialized through a queue (calls play in call order and
/// never overlap). A caption is emitted when playback of that item STARTS, so
/// caption and audio stay in sync. Items dropped by [muteForListening] before
/// they start emit nothing; calls made while muted emit their caption
/// immediately and play no audio.
///
/// Every engine/clip call is bounded by a timeout; a timeout counts as a
/// failure and falls through to the next fallback.
class AudioService {
  AudioService(
    this._tts,
    this._clips, {
    required bool Function(String path) assetExists,
    this.speechTimeout = const Duration(seconds: 10),
    this.clipTimeout = const Duration(seconds: 15),
    // ignore: prefer_initializing_formals
  }) : _assetExists = assetExists;

  final SpeechEngine _tts;
  final ClipPlayer _clips;
  final bool Function(String path) _assetExists;
  final Duration speechTimeout, clipTimeout;
  // Synchronous so a caption always precedes the audio call it announces.
  final StreamController<String> _captions = StreamController.broadcast(
    sync: true,
  );
  bool _muted = false;
  bool _disposed = false;
  bool _englishOk = false; // cached positive isEnglishAvailable()
  int _epoch = 0;
  Completer<void> _cancel = Completer<void>();
  Future<void> _tail = Future<void>.value();

  Stream<String> get captions => _captions.stream;
  bool get muted => _muted;

  /// Mutes, stops anything playing, completes the in-flight call promptly and
  /// drops queued items.
  void muteForListening() {
    if (_disposed) return;
    _muted = true;
    cancelAll();
  }

  /// Stops anything playing, completes the in-flight call promptly and drops
  /// queued items, WITHOUT muting: later calls play normally.
  void cancelAll() {
    if (_disposed) return;
    _epoch++;
    if (!_cancel.isCompleted) _cancel.complete();
    _cancel = Completer<void>();
    unawaited(_safe(_tts.stop));
    unawaited(_safe(_clips.stop));
  }

  void restoreAfterListening() => _muted = false;

  Future<void> sayEnglish(String text, {String? itemId}) {
    if (_disposed) return Future<void>.value();
    if (_muted) {
      _emit(text);
      return Future<void>.value();
    }
    return _enqueue(() async {
      _emit(text);
      if (itemId != null) {
        final path = 'assets/audio/en/$itemId.m4a';
        if (_assetExists(path) && await _clip(path)) return;
      }
      await _speak(text);
    });
  }

  /// Shows [text] as a caption only (no speech, no clip), in queue order.
  Future<void> showCaption(String text) {
    if (_disposed) return Future<void>.value();
    if (_muted) {
      _emit(text);
      return Future<void>.value();
    }
    return _enqueue(() async => _emit(text));
  }

  Future<void> playLine(VoiceLine l) {
    if (_disposed) return Future<void>.value();
    if (_muted) {
      _emit(l.caption);
      return Future<void>.value();
    }
    return _enqueue(() async {
      _emit(l.caption);
      if (_assetExists(l.assetPath)) await _clip(l.assetPath);
    });
  }

  /// Two legs ("the answer is", then the word). If the service is cancelled,
  /// muted or disposed during the first leg, the second never starts
  /// (otherwise it would play under the new epoch, e.g. on the next screen).
  Future<void> explainAnswer(ContentItem correct) async {
    final epoch = _epoch;
    await playLine(VoiceLine.theAnswerIs);
    if (_disposed || _epoch != epoch) return;
    await sayEnglish(correct.ttsText, itemId: correct.id);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    if (!_cancel.isCompleted) _cancel.complete();
    const t = Duration(seconds: 2);
    await Future.wait([
      _safe(() => _tts.dispose().timeout(t)),
      _safe(() => _clips.dispose().timeout(t)),
    ]);
    await _captions.close();
  }

  // --- internals ---

  late int _jobEpoch;
  late Future<void> _jobCancel;

  Future<void> _enqueue(Future<void> Function() job) {
    final epoch = _epoch;
    final prev = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      await prev;
      try {
        if (epoch == _epoch && !_muted) {
          _jobEpoch = epoch;
          _jobCancel = _cancel.future;
          await job();
        }
      } catch (_) {
        // Audio must never break the game.
      } finally {
        done.complete();
      }
    }();
  }

  bool get _live => !_muted && _jobEpoch == _epoch;

  /// Runs [f] bounded by [t] and by mute-cancellation; null on any failure.
  Future<T?> _run<T>(Future<T> Function() f, Duration t) async {
    try {
      return await Future.any<T?>([
        f().timeout(t),
        _jobCancel.then<T?>((_) => null),
      ]);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _clip(String path) async {
    if (!_live) return false;
    final r = await _run(() => _clips.play(path), clipTimeout);
    if (r == null) unawaited(_safe(_clips.stop));
    return r == true;
  }

  Future<void> _speak(String text) async {
    if (!_live) return;
    if (!_englishOk) {
      final ok = await _run(_tts.isEnglishAvailable, speechTimeout);
      if (ok != true) return;
      _englishOk = true;
    }
    if (!_live) return;
    final r = await _run(
      () => _tts.speak(text).then((_) => true),
      speechTimeout,
    );
    if (r == null) unawaited(_safe(_tts.stop));
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  void _emit(String s) {
    if (!_captions.isClosed) _captions.add(s);
  }
}

/// Tiny seam over flutter_tts so the adapter's stop-guard is unit-testable.
abstract class TtsBackend {
  Future<bool> isLanguageAvailable(String lang);
  Future<void> setLanguage(String lang);
  Future<void> awaitCompletion(bool value);
  Future<void> speak(String text);
  Future<void> stop();
}

class FlutterTtsBackend implements TtsBackend {
  final FlutterTts _t = FlutterTts();
  @override
  Future<bool> isLanguageAvailable(String lang) async =>
      await _t.isLanguageAvailable(lang) == true;
  @override
  Future<void> setLanguage(String lang) async => _t.setLanguage(lang);
  @override
  Future<void> awaitCompletion(bool value) async =>
      _t.awaitSpeakCompletion(value);
  @override
  Future<void> speak(String text) async => _t.speak(text);
  @override
  Future<void> stop() async => _t.stop();
}

/// Generation guard: a stop() landing between the setup awaits and the native
/// speak cancels the utterance instead of letting it play afterwards.
class FlutterTtsEngine implements SpeechEngine {
  FlutterTtsEngine({TtsBackend? backend}) : _b = backend ?? FlutterTtsBackend();
  final TtsBackend _b;
  int _gen = 0;

  @override
  Future<bool> isEnglishAvailable() => _b.isLanguageAvailable('en-US');

  @override
  Future<void> speak(String text) async {
    final g = _gen;
    await _b.setLanguage('en-US');
    if (g != _gen) return;
    await _b.awaitCompletion(true);
    if (g != _gen) return;
    await _b.speak(text);
  }

  @override
  Future<void> stop() async {
    _gen++;
    await _b.stop();
  }

  @override
  Future<void> dispose() => stop();
}

/// Tiny seam over just_audio's AudioPlayer.
abstract class AudioBackend {
  Future<void> setAsset(String path);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
  bool get completed;
}

class JustAudioBackend implements AudioBackend {
  final AudioPlayer _p = AudioPlayer();
  @override
  Future<void> setAsset(String path) async {
    await _p.setAsset(path);
  }

  @override
  Future<void> play() => _p.play();
  @override
  Future<void> stop() => _p.stop();
  @override
  Future<void> dispose() => _p.dispose();
  @override
  bool get completed => _p.processingState == ProcessingState.completed;
}

class JustAudioClipPlayer implements ClipPlayer {
  JustAudioClipPlayer({AudioBackend? backend})
    : _b = backend ?? JustAudioBackend();
  final AudioBackend _b;
  int _gen = 0;

  /// Completes when playback ends or is interrupted; true only if it played
  /// to the end. A stop() during setAsset aborts before play().
  @override
  Future<bool> play(String assetPath) async {
    final g = _gen;
    try {
      await _b.setAsset(assetPath);
      if (g != _gen) return false;
      await _b.play();
      return g == _gen && _b.completed;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _gen++;
    await _b.stop();
  }

  @override
  Future<void> dispose() async {
    _gen++;
    await _b.dispose();
  }
}
