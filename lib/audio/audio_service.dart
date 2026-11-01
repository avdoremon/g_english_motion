import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import '../content/models.dart';
import 'voice_lines.dart';

abstract class SpeechEngine {
  Future<bool> isEnglishAvailable();

  /// Completes when the utterance has finished.
  Future<void> speak(String text);
}

abstract class ClipPlayer {
  /// Plays [assetPath] to the end; returns false if it could not be played.
  Future<bool> play(String assetPath);
}

/// Speech and clips with graceful fallback: recorded clip -> TTS -> caption
/// only. Never throws.
class AudioService {
  AudioService(
    this._tts,
    this._clips, {
    required bool Function(String path) assetExists,
    // ignore: prefer_initializing_formals
  }) : _assetExists = assetExists;

  final SpeechEngine _tts;
  final ClipPlayer _clips;
  final bool Function(String path) _assetExists;
  final StreamController<String> _captions = StreamController.broadcast();
  bool _muted = false;

  Stream<String> get captions => _captions.stream;
  bool get muted => _muted;

  void muteForListening() => _muted = true;
  void restoreAfterListening() => _muted = false;

  Future<void> sayEnglish(String text, {String? itemId}) async {
    _emit(text);
    if (_muted) return;
    try {
      if (itemId != null) {
        final path = 'assets/audio/en/$itemId.m4a';
        if (_assetExists(path) && await _tryClip(path)) return;
      }
      if (await _tts.isEnglishAvailable()) await _tts.speak(text);
    } catch (_) {
      // Audio must never break the game.
    }
  }

  Future<void> playLine(VoiceLine l) async {
    _emit(l.caption);
    if (_muted) return;
    if (_assetExists(l.assetPath)) await _tryClip(l.assetPath);
  }

  Future<void> explainAnswer(ContentItem correct) async {
    await playLine(VoiceLine.theAnswerIs);
    await sayEnglish(correct.ttsText, itemId: correct.id);
  }

  Future<bool> _tryClip(String path) async {
    try {
      return await _clips.play(path);
    } catch (_) {
      return false;
    }
  }

  void _emit(String s) {
    if (!_captions.isClosed) _captions.add(s);
  }

  Future<void> dispose() => _captions.close();
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
}

class JustAudioClipPlayer implements ClipPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<bool> play(String assetPath) async {
    try {
      await _player.setAsset(assetPath);
      await _player.play(); // completes when playback ends
      return true;
    } catch (_) {
      return false;
    }
  }
}
