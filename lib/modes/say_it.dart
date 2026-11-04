import 'dart:math';

import '../content/models.dart';
import '../levels/scoring.dart';
import '../speech/word_judge.dart';
import 'round.dart';

/// How long "Đúng"/"Sai" stays on a judged word.
const kJudgedHold = Duration(milliseconds: 700);

/// How long the word explodes before it is gone.
const kExplosionTime = Duration(milliseconds: 800);

/// A result may arrive this long after the word has run off the screen and
/// still counts.
const kLateGrace = Duration(seconds: 1);

enum WordMotion { fallDown, rightToLeft }

enum WordPhase { waitingForModel, running, judged, exploding, gone }

class SayItWord {
  SayItWord(this.item, this.motion, this.sessionId, {required bool modelFirst})
    : phase = modelFirst ? WordPhase.waitingForModel : WordPhase.running;

  final ContentItem item;
  final WordMotion motion;

  /// Names the listen this word owns; a result with another id is not ours.
  final int sessionId;
  WordPhase phase;
  RoundResult? result;

  /// 0 (entering) .. 1 (ran off the screen) while running.
  double progress = 0;

  /// 0..1 while exploding.
  double explosionProgress = 0;
}

/// One "ván": three words, one after another. Pure Dart: the screen feeds it
/// recognition results and time.
///
/// Rules:
/// - The clock of a word stands still while the model reading plays
///   ([WordPhase.waitingForModel]).
/// - A result is graded only while the word is running (including the
///   [kLateGrace] after it ran off the screen) and only if its `sessionId` is
///   the word's. Only a match decides early (correct). Anything else, a
///   confident other word included, leaves the word running: it turns wrong
///   only when the word has run off the screen and the grace ended with no
///   match. Uncertain input therefore never costs a word.
class SayItRound {
  SayItRound(
    List<ContentItem> items, {
    required Duration travelTime,
    required Random rng,
    required bool modelFirst,
    required int firstSessionId,
  }) : travelTime = travelTime,
       _modelFirst = modelFirst,
       words = _build(items, rng, modelFirst, firstSessionId) {
    if (travelTime <= Duration.zero) {
      throw ArgumentError.value(travelTime, 'travelTime', 'must be positive');
    }
  }

  static List<SayItWord> _build(
    List<ContentItem> items,
    Random rng,
    bool modelFirst,
    int firstSessionId,
  ) {
    if (items.length != 3) {
      throw ArgumentError.value(items.length, 'items', 'a round has 3 words');
    }
    return List.unmodifiable([
      for (var i = 0; i < 3; i++)
        SayItWord(
          items[i],
          WordMotion.values[rng.nextInt(WordMotion.values.length)],
          firstSessionId + i,
          modelFirst: modelFirst && i == 0,
        ),
    ]);
  }

  final Duration travelTime;
  final bool _modelFirst;
  final List<SayItWord> words;
  int _index = 0;
  Duration _ran = Duration.zero; // running time of the current word
  Duration _inPhase = Duration.zero; // time in judged / exploding

  SayItWord get current => words[_index];
  bool get finished =>
      _index >= words.length - 1 && current.phase == WordPhase.gone;
  int get correctCount =>
      words.where((w) => w.result == RoundResult.correct).length;

  /// The model reading of the current word ended: it starts to run.
  void onModelFinished() {
    if (current.phase == WordPhase.waitingForModel) {
      current.phase = WordPhase.running;
    }
  }

  void onRecognized(RecognitionResult r) {
    final w = current;
    if (w.phase != WordPhase.running || r.sessionId != w.sessionId) return;
    switch (WordJudge.judge(r, w.item)) {
      case Judgement.match:
        _judge(RoundResult.correct);
      case Judgement.miss:
        // Only tentative: the word keeps running and the microphone stays
        // open; a later match (before the word's end + grace) overrides it.
        // It turns wrong only when that deadline passes.
        break;
      case Judgement.uncertain:
        break;
    }
  }

  void _judge(RoundResult result) {
    current
      ..result = result
      ..phase = WordPhase.judged;
    _inPhase = Duration.zero;
  }

  void tick(Duration dt) {
    var left = dt;
    while (left > Duration.zero && !finished) {
      final w = current;
      switch (w.phase) {
        case WordPhase.waitingForModel:
        case WordPhase.gone:
          return;
        case WordPhase.running:
          if (_ran < travelTime) {
            final used = _min(left, travelTime - _ran);
            _ran += used;
            left -= used;
            w.progress = _ran.inMicroseconds / travelTime.inMicroseconds;
          } else {
            final used = _min(left, kLateGrace - (_ran - travelTime));
            _ran += used;
            left -= used;
            if (_ran - travelTime >= kLateGrace) _judge(RoundResult.wrong);
          }
        case WordPhase.judged:
          final used = _min(left, kJudgedHold - _inPhase);
          _inPhase += used;
          left -= used;
          if (_inPhase >= kJudgedHold) {
            w.phase = WordPhase.exploding;
            _inPhase = Duration.zero;
          }
        case WordPhase.exploding:
          final used = _min(left, kExplosionTime - _inPhase);
          _inPhase += used;
          left -= used;
          w.explosionProgress =
              _inPhase.inMicroseconds / kExplosionTime.inMicroseconds;
          if (_inPhase >= kExplosionTime) {
            w.phase = WordPhase.gone;
            _advance();
          }
      }
    }
  }

  void _advance() {
    if (_index >= words.length - 1) return;
    _index++;
    _ran = Duration.zero;
    _inPhase = Duration.zero;
    if (_modelFirst) current.phase = WordPhase.waitingForModel;
  }

  static Duration _min(Duration a, Duration b) => a < b ? a : b;
}

/// A SayIt level: three rounds (9 words).
class SayItLevel {
  SayItLevel({required List<SayItRound> rounds})
    : rounds = List.unmodifiable(rounds) {
    if (rounds.length != 3) {
      throw ArgumentError.value(
        rounds.length,
        'rounds',
        'a level has 3 rounds',
      );
    }
  }

  /// Splits [nineWords] into three rounds; word i gets session id
  /// `firstSessionId + i`.
  factory SayItLevel.build(
    List<ContentItem> nineWords, {
    required Duration travelTime,
    required Random rng,
    required bool modelFirst,
    required int firstSessionId,
  }) {
    if (nineWords.length != 9) {
      throw ArgumentError.value(nineWords.length, 'nineWords', 'need 9 words');
    }
    return SayItLevel(
      rounds: [
        for (var i = 0; i < 3; i++)
          SayItRound(
            nineWords.sublist(i * 3, i * 3 + 3),
            travelTime: travelTime,
            rng: rng,
            modelFirst: modelFirst,
            firstSessionId: firstSessionId + i * 3,
          ),
      ],
    );
  }

  final List<SayItRound> rounds;

  int get correctOfNine => rounds.fold(0, (a, r) => a + r.correctCount);
  int get stars => Scoring.sayItStars(correctOfNine);
}
