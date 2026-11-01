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
  bool _englishOk = false; // cached positive isEnglishAvailable()
  int _epoch = 0;
  Completer<void> _cancel = Completer<void>();
  Future<void> _tail = Future<void>.value();

  Stream<String> get captions => _captions.stream;
  bool get muted => _muted;

  /// Mutes, stops anything playing, completes the in-flight call promptly and
  /// drops queued items.
  void muteForListening() {
    _muted = true;
    _epoch++;
    if (!_cancel.isCompleted) _cancel.complete();
    _cancel = Completer<void>();
    unawaited(_safe(_tts.stop));
    unawaited(_safe(_clips.stop));
  }

  void restoreAfterListening() => _muted = false;

  Future<void> sayEnglish(String text, {String? itemId}) {
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

  Future<void> playLine(VoiceLine l) {
    if (_muted) {
      _emit(l.caption);
      return Future<void>.value();
    }
    return _enqueue(() async {
      _emit(l.caption);
      if (_assetExists(l.assetPath)) await _clip(l.assetPath);
    });
  }

  Future<void> explainAnswer(ContentItem correct) async {
    await playLine(VoiceLine.theAnswerIs);
    await sayEnglish(correct.ttsText, itemId: correct.id);
  }

  Future<void> dispose() async {
    _epoch++;
    if (!_cancel.isCompleted) _cancel.complete();
    await _safe(_tts.dispose);
    await _safe(_clips.dispose);
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

class FlutterTtsEngine implements SpeechEngine {
  FlutterTtsEngine() : _tts = FlutterTts();
  final FlutterTts _tts;

  @override
  Future<bool> isEnglishAvailable() async =>
      await _tts.isLanguageAvailable('en-US') == true;

  @override
  Future<void> speak(String text) async {
    await _tts.setLanguage('en-US');
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> dispose() => stop();
}

class JustAudioClipPlayer implements ClipPlayer {
  final AudioPlayer _player = AudioPlayer();

  /// Completes when playback ends or is interrupted; true only if it played
  /// to the end.
  @override
  Future<bool> play(String assetPath) async {
    try {
      await _player.setAsset(assetPath);
      await _player.play();
      return _player.processingState == ProcessingState.completed;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
