import '../content/models.dart';

/// What the recogniser heard in one utterance. [transcripts] are alternative
/// readings of the same utterance, best first. [confidences] (when the
/// platform gives any) line up with them; a value <= 0 means "unknown".
/// [sessionId] names the word the listen belonged to, so a late result can
/// never be credited to the next word.
///
/// Held in memory only: never persisted, logged or sent anywhere.
class RecognitionResult {
  const RecognitionResult({
    required this.transcripts,
    this.confidences,
    required this.sessionId,
  });

  final List<String> transcripts;
  final List<double>? confidences;
  final int sessionId;
}

enum Judgement {
  /// A usable alternative is the target word (or one of its variants).
  match,

  /// The recogniser clearly heard something else.
  miss,

  /// Nothing usable (silence, or every reading has low confidence): the game
  /// keeps listening and never grades this as wrong.
  uncertain,
}

class WordJudge {
  const WordJudge._();

  static const _ones = [
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
  ];
  static const _tens = [
    '',
    '',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
  ];
  static const _articles = {'a', 'an', 'the'};

  static String _numberWords(int n) {
    if (n < 20) return _ones[n];
    if (n == 100) return 'one hundred';
    final t = _tens[n ~/ 10];
    return n % 10 == 0 ? t : '$t ${_ones[n % 10]}';
  }

  /// Lower case; hyphens become spaces; other punctuation (apostrophes
  /// included) is dropped; the numbers 0-100 written as digits become words;
  /// a leading a/an/the is dropped when a word remains.
  static String normalize(String s) {
    final cleaned = s
        .toLowerCase()
        .replaceAll(RegExp(r'[\-‐-―]'), ' ')
        .replaceAll(RegExp(r"['’]"), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ');
    var tokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    tokens = tokens.map((t) {
      final n = RegExp(r'^\d{1,3}$').hasMatch(t) ? int.parse(t) : null;
      return n != null && n <= 100 ? _numberWords(n) : t;
    });
    final out = tokens.join(' ').split(' ');
    if (out.length > 1 && _articles.contains(out.first)) out.removeAt(0);
    return out.join(' ').trim();
  }

  static Set<String> _targets(ContentItem item) => {
    normalize(item.word),
    for (final v in item.spokenVariants) normalize(v),
  }..remove('');

  /// Whether an alternative's score allows grading. Missing or <= 0 means the
  /// platform gave no score: it is not held against the reading.
  static bool _confident(RecognitionResult r, int i, double min) {
    final c = r.confidences;
    if (c == null || i >= c.length) return true;
    return c[i] <= 0 || c[i] >= min;
  }

  static Judgement judge(
    RecognitionResult r,
    ContentItem item, {
    double minConfidence = 0.3,
  }) {
    final targets = _targets(item);
    var heardSomethingUsable = false;
    for (var i = 0; i < r.transcripts.length; i++) {
      final n = normalize(r.transcripts[i]);
      if (n.isEmpty || !_confident(r, i, minConfidence)) continue;
      heardSomethingUsable = true;
      if (targets.contains(n)) return Judgement.match;
    }
    return heardSomethingUsable ? Judgement.miss : Judgement.uncertain;
  }

  /// Exact match after normalisation (no near-match by letter distance) of any
  /// usable alternative against the word or one of its `spokenVariants`.
  static bool matches(
    RecognitionResult r,
    ContentItem item, {
    double minConfidence = 0.3,
  }) => judge(r, item, minConfidence: minConfidence) == Judgement.match;
}
