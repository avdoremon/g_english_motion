import 'dart:math';

import '../levels/level_config.dart';
import 'content_repository.dart';
import 'curriculum.dart';
import 'edit_distance.dart';
import 'history_store.dart';
import 'models.dart';
import 'question_models.dart';

const _modeForms = <ModeKind, List<QuestionForm>>{
  ModeKind.laneJump: [
    QuestionForm.listenPickPicture,
    QuestionForm.seePicturePickWord,
    QuestionForm.listenPickWord,
  ],
  ModeKind.skyShoot: [QuestionForm.listenPickWord, QuestionForm.fillBlank],
  ModeKind.dragSpell: [QuestionForm.spellWord, QuestionForm.orderSentence],
  ModeKind.catchIt: [QuestionForm.listenPickPicture],
  ModeKind.memoryFlip: [QuestionForm.memoryMatch],
  ModeKind.balloonPop: [QuestionForm.popWord],
  ModeKind.yesNo: [QuestionForm.trueFalse],
};

/// One (item x form) candidate; [modes] are the requested modes that can host it.
class _Pair {
  _Pair(this.item, this.form, this.modes, this.sentence);
  final ContentItem item;
  final QuestionForm form;
  final List<ModeKind> modes;

  /// Sentence pattern used by fillBlank / orderSentence.
  final String? sentence;
}

class _Pick {
  _Pick(this.pair, this.cycle, [this.mode]);
  final _Pair pair;
  final int cycle;
  ModeKind? mode;
}

class QuestionGenerator {
  QuestionGenerator(this._repo, this._history, this._rng);

  final ContentRepository _repo;
  final HistoryStore _history;
  final Random _rng;

  /// Plans [level.questionCount] questions.
  ///
  /// Selection is item-first: every eligible item is used once (wrong items
  /// within their 30% quota, then not-recently-asked items, then recent ones;
  /// shuffled) before any item is asked again in another form, and so on for
  /// the 2nd, 3rd... use. A (item, form) pair repeats only once the whole pool
  /// is exhausted.
  ///
  /// The wrong-item quota is a hard cap of floor(0.3 * n) questions. The one
  /// exception: when every non-wrong (item, form) pair has been used and
  /// slots remain, over-quota wrong pairs fill them before any pair repeats.
  ///
  /// Wrong ids (from the history) that do not belong to an item in the level's
  /// unit window, or whose item cannot be asked in the requested modes, are
  /// ignored: they are neither planned nor counted towards the quota.
  List<PlannedQuestion> plan({
    required LevelConfig level,
    required CurriculumPosition pos,
    required Set<ModeKind> modes,
  }) {
    final n = level.questionCount;
    final units = unitsForLevel(_repo, pos, level.window);
    if (n <= 0) return const [];
    var pairs = _pool(units, pos.grade, modes);
    // Never an empty session, and never one picture carrying the plan: when
    // the level's window offers too few distinct items for the modes (a unit
    // with no or a single balloonPop-tagged word), widen the content step by
    // step: every unit up to the current one, then the whole grade. Once a
    // pool is widened its items are mixed without preferring the current unit,
    // so units that are not reached yet can appear in the whole-grade step.
    // Windows that already hold enough items are untouched.
    final enough = (n + 1) ~/ 2; // no item more than twice
    int distinct(List<_Pair> ps) => {for (final p in ps) p.item.id}.length;
    if (distinct(pairs) < enough) {
      final learned = _pool(
        unitsForLevel(_repo, pos, UnitWindow.allLearned),
        pos.grade,
        modes,
      );
      if (distinct(learned) > distinct(pairs)) pairs = learned;
    }
    if (distinct(pairs) < enough) {
      final all = _pool(_repo.unitsFor(pos.grade), pos.grade, modes);
      if (distinct(all) > distinct(pairs)) pairs = all;
    }
    if (pairs.isEmpty) return const [];

    final recent = _history.recentIds().toSet();
    final wrong = _history.wrongIds();
    final wrongPairs = [
      for (final p in pairs)
        if (wrong.contains(p.item.id)) p,
    ]..shuffle(_rng);
    final others = [
      for (final p in pairs)
        if (!wrong.contains(p.item.id)) p,
    ];

    // Wrong-item quota: 30% rounded down (so n < 4 asks no wrong item).
    final cap = (n * 3) ~/ 10;
    final picks = <_Pick>[];
    final wrongItems = <String>{};
    final leftoverWrong = <_Pair>[];
    for (final p in wrongPairs) {
      if (picks.length < cap && wrongItems.add(p.item.id)) {
        picks.add(_Pick(p, 0));
      } else {
        leftoverWrong.add(p);
      }
    }

    // Priority order for the rest: not recently asked first, then recent.
    final fresh = [
      for (final p in others)
        if (!recent.contains(p.item.id)) p,
    ]..shuffle(_rng);
    final stale = [
      for (final p in others)
        if (recent.contains(p.item.id)) p,
    ]..shuffle(_rng);
    final remaining = [...fresh, ...stale];

    // How often each item has been picked so far: picks are balanced by it
    // (item-first), ties keep the priority order of the lists.
    final itemCount = <String, int>{};
    for (final k in picks) {
      itemCount.update(k.pair.item.id, (c) => c + 1, ifAbsent: () => 1);
    }
    _Pair? takeBest(List<List<_Pair>> lists, [ModeKind? mode]) {
      List<_Pair>? bestList;
      var bestIdx = -1, bestCount = 1 << 30;
      for (final list in lists) {
        for (var i = 0; i < list.length; i++) {
          final p = list[i];
          if (mode != null && !p.modes.contains(mode)) continue;
          final c = itemCount[p.item.id] ?? 0;
          if (c < bestCount) {
            bestCount = c;
            bestList = list;
            bestIdx = i;
          }
        }
      }
      if (bestList == null) return null;
      final p = bestList.removeAt(bestIdx);
      itemCount.update(p.item.id, (c) => c + 1, ifAbsent: () => 1);
      return p;
    }

    // Seed one question per requested mode that cannot otherwise be missed.
    final used = <ModeKind, int>{};
    for (final k in picks) {
      if (k.pair.modes.length == 1) {
        k.mode = k.pair.modes.first;
        used[k.mode!] = (used[k.mode!] ?? 0) + 1;
      }
    }
    final wanted = _modeForms.keys.where(modes.contains).toList()
      ..shuffle(_rng);
    for (final m in wanted) {
      if (picks.length >= n) break;
      if ((used[m] ?? 0) > 0) continue;
      final p = takeBest([remaining], m);
      if (p == null) continue;
      picks.add(_Pick(p, 0, m));
      used[m] = 1;
    }

    // Remaining slots: least-used non-wrong item first. The wrong-item cap is
    // hard: over-quota wrong pairs are used only once the non-wrong pool (all
    // its items x forms) is exhausted, never to balance item counts.
    while (picks.length < n) {
      final p = takeBest([remaining]) ?? takeBest([leftoverWrong]);
      if (p == null) break;
      picks.add(_Pick(p, 0));
    }
    // Pool exhausted: cycle through a freshly shuffled pool again.
    var cycle = 0;
    while (picks.length < n) {
      cycle++;
      final base = [...(others.isNotEmpty ? others : pairs)]..shuffle(_rng);
      for (final p in base) {
        if (picks.length >= n) break;
        picks.add(_Pick(p, cycle));
      }
    }

    // Assign modes to pairs hosted by several modes (least used first).
    for (final k in picks) {
      if (k.mode != null) continue;
      final cands = [...k.pair.modes]..shuffle(_rng);
      cands.sort((a, b) => (used[a] ?? 0).compareTo(used[b] ?? 0));
      k.mode = cands.first;
      used[k.mode!] = (used[k.mode!] ?? 0) + 1;
    }

    final ordered = _arrange(picks, wrong);
    return _build(ordered, level, pos);
  }

  /// Shuffles within each cycle (so a pair repeats only after the pool is
  /// used up), keeps wrong items off position 0 and splits adjacent repeats.
  List<_Pick> _arrange(List<_Pick> picks, Set<String> wrong) {
    final out = <_Pick>[];
    final maxCycle = picks.fold<int>(0, (m, k) => max(m, k.cycle));
    for (var c = 0; c <= maxCycle; c++) {
      out.addAll(
        [
          for (final k in picks)
            if (k.cycle == c) k,
        ]..shuffle(_rng),
      );
    }
    if (out.length > 1 && wrong.contains(out[0].pair.item.id)) {
      final j = out.indexWhere(
        (k) => k.cycle == out[0].cycle && !wrong.contains(k.pair.item.id),
      );
      if (j > 0) {
        final t = out[0];
        out[0] = out[j];
        out[j] = t;
      }
    }
    int conflicts() {
      var c = 0;
      for (var i = 1; i < out.length; i++) {
        if (out[i].pair.item.id == out[i - 1].pair.item.id) c++;
      }
      return c;
    }

    for (var i = 1; i < out.length; i++) {
      if (out[i].pair.item.id != out[i - 1].pair.item.id) continue;
      final before = conflicts();
      for (var j = 1; j < out.length; j++) {
        if (j == i || out[j].cycle != out[i].cycle) continue;
        final t = out[i];
        out[i] = out[j];
        out[j] = t;
        if (conflicts() < before) break;
        out[j] = out[i];
        out[i] = t;
      }
    }
    return out;
  }

  List<PlannedQuestion> _build(
    List<_Pick> ordered,
    LevelConfig level,
    CurriculumPosition pos,
  ) {
    final out = <PlannedQuestion>[];
    int? prev1, prev2;
    // True / false statements are balanced over the plan (counts differ by at
    // most one), in a random order.
    final tfCount = ordered
        .where((k) => k.pair.form == QuestionForm.trueFalse)
        .length;
    final tfTruths = [for (var i = 0; i < tfCount; i++) i.isEven]
      ..shuffle(_rng);
    var tfNext = 0;
    for (final k in ordered) {
      final item = k.pair.item;
      final Question q;
      switch (k.pair.form) {
        case QuestionForm.spellWord:
          q = SpellQuestion(
            itemId: item.id,
            ttsText: item.ttsText,
            word: item.word,
            tiles: _scramble(_letters(item.word)),
            imageItemId: item.image != null ? item.id : null,
          );
        case QuestionForm.orderSentence:
          final answer = k.pair.sentence!.trim().split(RegExp(r'\s+'));
          q = OrderQuestion(
            itemId: item.id,
            ttsText: k.pair.sentence!,
            words: _scramble(answer),
            answer: answer,
          );
        case QuestionForm.trueFalse:
          final statement = _statement(k.pair, truth: tfTruths[tfNext++]);
          q = ChoiceQuestion(
            itemId: item.id,
            form: QuestionForm.trueFalse,
            ttsText: statement.text,
            promptText: statement.text,
            promptImageItemId: item.id,
            // Choice 0 = Đúng, 1 = Sai; the screen labels them itself.
            choices: [
              for (var i = 0; i < 2; i++)
                ChoiceOption(
                  itemId: item.id,
                  showPicture: false,
                  showWord: false,
                ),
            ],
            correctIndex: statement.isTrue ? 0 : 1,
          );
        case QuestionForm.memoryMatch:
        case QuestionForm.popWord:
        case QuestionForm.listenPickPicture:
        case QuestionForm.seePicturePickWord:
        case QuestionForm.listenPickWord:
        case QuestionForm.fillBlank:
          final form = k.pair.form;
          final others = switch (form) {
            QuestionForm.popWord => _popDistractors(item, level, pos),
            QuestionForm.memoryMatch => _distractors(
              item,
              form,
              level,
              pos,
              need: _wordChoiceCount(level) - 1,
            ),
            // catchIt: three pictures fall in three lanes.
            QuestionForm.listenPickPicture when k.mode == ModeKind.catchIt =>
              _distractors(item, form, level, pos, need: 2),
            _ => _distractors(item, form, level, pos),
          };
          final all = [item, ...others]..shuffle(_rng);
          var idx = all.indexOf(item);
          if (prev1 != null && prev1 == prev2 && idx == prev1) {
            var other = _rng.nextInt(all.length - 1);
            if (other >= idx) other++;
            final t = all[idx];
            all[idx] = all[other];
            all[other] = t;
            idx = other;
          }
          prev2 = prev1;
          prev1 = idx;
          final pic = form == QuestionForm.listenPickPicture;
          final blank = form == QuestionForm.fillBlank;
          q = ChoiceQuestion(
            itemId: item.id,
            form: form,
            ttsText: blank ? _blank(k.pair, 'blank') : item.ttsText,
            promptText: blank ? _blank(k.pair, '____') : null,
            promptImageItemId:
                (form == QuestionForm.seePicturePickWord ||
                    form == QuestionForm.memoryMatch ||
                    form == QuestionForm.popWord ||
                    (blank && item.image != null))
                ? item.id
                : null,
            choices: [
              for (final c in all)
                ChoiceOption(itemId: c.id, showPicture: pic, showWord: !pic),
            ],
            correctIndex: idx,
          );
      }
      out.add(PlannedQuestion(mode: k.mode!, question: q));
    }
    return out;
  }

  /// The yes/no statement for [p]: the item's sentence as is when [truth],
  /// otherwise the sentence with the item's word swapped for a distractor's
  /// (the article before each swapped word is fixed to "a" / "an"). Without a
  /// usable sentence the statement is the bare claimed word.
  ({String text, bool isTrue}) _statement(_Pair p, {required bool truth}) {
    final item = p.item;
    if (truth) {
      return (text: p.sentence ?? item.word, isTrue: true);
    }
    final claims = _claims(item);
    final claim = claims[_rng.nextInt(claims.length)];
    final sentence = p.sentence;
    if (sentence == null) return (text: claim.word, isTrue: false);
    final swap = RegExp(
      r'(?:(?<![\p{L}\p{N}_])(an|a)(\s+))?' + _wordRe(item.word).pattern,
      caseSensitive: false,
      unicode: true,
    );
    final text = sentence.replaceAllMapped(swap, (m) {
      final article = m.group(1);
      final gap = m.group(2) ?? '';
      final matched = m[0]!.substring((article?.length ?? 0) + gap.length);
      var word = claim.word;
      if (matched.isNotEmpty && matched[0] != matched[0].toLowerCase()) {
        word = word[0].toUpperCase() + word.substring(1);
      }
      if (article == null) return word;
      var fixed = 'aeiou'.contains(claim.word[0].toLowerCase()) ? 'an' : 'a';
      if (article[0] != article[0].toLowerCase()) {
        fixed = fixed[0].toUpperCase() + fixed.substring(1);
      }
      return '$fixed$gap$word';
    });
    return (text: text, isTrue: false);
  }

  /// Distractors of [item] that can serve as a false claim: not the item
  /// itself, and their word does not contain the item's word (or the false
  /// statement would still show it).
  List<ContentItem> _claims(ContentItem item) {
    final re = _wordRe(item.word);
    final out = <ContentItem>[];
    final words = <String>{};
    for (final id in item.distractorIds) {
      final c = _repo.byId(id);
      if (c.id == item.id || c.word.isEmpty || re.hasMatch(c.word)) continue;
      if (words.add(c.word.toLowerCase())) out.add(c);
    }
    return out;
  }

  String _blank(_Pair p, String repl) =>
      p.sentence!.replaceFirst(_wordRe(p.item.word), repl);

  /// Whole-word, case-insensitive match of [w]. `\b` is ASCII-only and fails
  /// next to non-word characters, so the boundaries are Unicode lookarounds
  /// (not preceded / followed by a letter, digit or underscore) and [w] is
  /// escaped (it may contain spaces, hyphens, dots...).
  static RegExp _wordRe(String w) => RegExp(
    r'(?<![\p{L}\p{N}_])' + RegExp.escape(w) + r'(?![\p{L}\p{N}_])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _lettersOnly = RegExp(r'^\p{L}+$', unicode: true);

  static List<String> _letters(String w) => [
    for (final r in w.runes) String.fromCharCode(r),
  ];

  /// A permutation of [xs] that differs from [xs] (callers guarantee that one
  /// exists).
  List<String> _scramble(List<String> xs) {
    for (var t = 0; t < 30; t++) {
      final c = [...xs]..shuffle(_rng);
      if (!_same(c, xs)) return c;
    }
    final c = [...xs];
    for (var i = 1; i < c.length; i++) {
      if (c[i] != c[0]) {
        final t = c[0];
        c[0] = c[i];
        c[i] = t;
        break;
      }
    }
    return c;
  }

  bool _same(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<ContentItem> _distractors(
    ContentItem correct,
    QuestionForm form,
    LevelConfig level,
    CurriculumPosition pos, {
    int? need,
  }) {
    final want = need ?? level.choiceCount - 1;
    final tiers = <List<ContentItem>>[
      [for (final id in correct.distractorIds) _repo.byId(id)]..shuffle(_rng),
      [for (final u in unitsForLevel(_repo, pos, level.window)) ...u.items]
        ..shuffle(_rng),
      [for (final u in _repo.unitsFor(pos.grade)) ...u.items]..shuffle(_rng),
    ];
    final out = <ContentItem>[];
    final ids = <String>{correct.id};
    final words = <String>{correct.word.toLowerCase()};
    void fill(bool needImage) {
      for (final t in tiers) {
        for (final c in t) {
          if (out.length >= want) return;
          if (needImage && c.image == null) continue;
          if (ids.contains(c.id) || words.contains(c.word.toLowerCase())) {
            continue;
          }
          ids.add(c.id);
          words.add(c.word.toLowerCase());
          out.add(c);
        }
      }
    }

    final pic = form == QuestionForm.listenPickPicture;
    fill(pic);
    if (pic && out.length < want) fill(false);
    if (out.length < want) {
      throw StateError(
        'Not enough distractors for "${correct.id}" in grade ${pos.grade}: '
        'need $want, found ${out.length}',
      );
    }
    return out;
  }

  /// memoryMatch / popWord show 3-5 word choices whatever the level asks.
  static int _wordChoiceCount(LevelConfig level) =>
      level.choiceCount.clamp(3, 5);

  static const _popMaxDistance = 2;

  /// Other items of [grade] whose word is within [_popMaxDistance] edits of
  /// [item]'s (case-insensitive), one per distinct word.
  List<ContentItem> _popNeighbours(ContentItem item, int grade) {
    final me = item.word.toLowerCase();
    final seen = <String>{me};
    return [
      for (final u in _repo.unitsFor(grade))
        for (final c in u.items)
          if (seen.add(c.word.toLowerCase()) &&
              editDistance(c.word, item.word) <= _popMaxDistance)
            c,
    ];
  }

  /// popWord balloons: look-alike words of the same grade, own distractors
  /// first, then the level's unit window, then the rest of the grade.
  List<ContentItem> _popDistractors(
    ContentItem correct,
    LevelConfig level,
    CurriculumPosition pos,
  ) {
    final need = _wordChoiceCount(level) - 1;
    final near = _popNeighbours(correct, pos.grade);
    final own = correct.distractorIds.toSet();
    final window = {
      for (final u in unitsForLevel(_repo, pos, level.window))
        for (final i in u.items) i.id,
    };
    final tiers = [
      [
        for (final c in near)
          if (own.contains(c.id)) c,
      ],
      [
        for (final c in near)
          if (!own.contains(c.id) && window.contains(c.id)) c,
      ],
      [
        for (final c in near)
          if (!own.contains(c.id) && !window.contains(c.id)) c,
      ],
    ];
    final out = [for (final t in tiers) ...(t..shuffle(_rng))];
    if (out.length < 2) {
      throw StateError(
        'Not enough look-alike words for "${correct.id}" in grade '
        '${pos.grade}: found ${out.length}',
      );
    }
    return out.take(need).toList();
  }

  List<_Pair> _pool(List<Unit> units, int grade, Set<ModeKind> modes) {
    final pairs = <_Pair>[];
    for (final u in units) {
      for (final item in u.items) {
        for (final form in QuestionForm.values) {
          final hosts = [
            for (final m in _modeForms.keys)
              if (modes.contains(m) &&
                  item.modes.contains(m) &&
                  _modeForms[m]!.contains(form))
                m,
          ];
          if (hosts.isEmpty) continue;
          final ok = _eligible(item, form, grade);
          if (ok == null) continue;
          pairs.add(_Pair(item, form, hosts, ok.isEmpty ? null : ok));
        }
      }
    }
    return pairs;
  }

  /// Null when [item] cannot be asked as [form]; otherwise the sentence used
  /// (empty string when the form needs none).
  String? _eligible(ContentItem item, QuestionForm form, int grade) {
    final upper = grade >= 3;
    switch (form) {
      case QuestionForm.listenPickPicture:
      case QuestionForm.seePicturePickWord:
        return item.image == null ? null : '';
      case QuestionForm.listenPickWord:
        return '';
      case QuestionForm.fillBlank:
        if (!upper) return null;
        final re = _wordRe(item.word);
        // Exactly once: in "The orange is orange" only one occurrence is
        // blanked, so the prompt would show (and the voice would speak) the
        // answer. Such a pattern is skipped; an item with no other one
        // cannot be asked as fillBlank at all.
        final c = [
          for (final s in item.sentencePatterns)
            if (re.allMatches(s).length == 1) s,
        ];
        return c.isEmpty ? null : c[_rng.nextInt(c.length)];
      case QuestionForm.spellWord:
        final w = item.word;
        // Letters only: spaces, hyphens, digits... cannot be tile-spelled.
        if (!upper || !_lettersOnly.hasMatch(w)) return null;
        final letters = _letters(w);
        if (letters.length < 3 || letters.toSet().length < 2) return null;
        return '';
      case QuestionForm.memoryMatch:
        return item.image == null ? null : '';
      case QuestionForm.trueFalse:
        if (item.image == null || _claims(item).isEmpty) return null;
        final re = _wordRe(item.word);
        for (final s in item.sentencePatterns) {
          if (re.hasMatch(s)) return s;
        }
        return '';
      case QuestionForm.popWord:
        if (item.image == null) return null;
        return _popNeighbours(item, grade).length >= 2 ? '' : null;
      case QuestionForm.orderSentence:
        if (!upper) return null;
        final c = [
          for (final s in item.sentencePatterns)
            if (_orderable(s)) s,
        ];
        return c.isEmpty ? null : c[_rng.nextInt(c.length)];
    }
  }

  bool _orderable(String s) {
    final w = s.trim().split(RegExp(r'\s+'));
    return w.length >= 3 && w.length <= 6 && w.toSet().length >= 2;
  }

  List<ContentItem> sayItWords({
    required CurriculumPosition pos,
    required LevelConfig level,
    int count = 3,
    Set<String> exclude = const {},
  }) {
    final recent = _history.recentIds().toSet();
    final cands = <ContentItem>[
      for (final u in unitsForLevel(_repo, pos, level.window))
        for (final it in u.items)
          if (it.modes.contains(ModeKind.sayIt) &&
              !exclude.contains(it.id) &&
              (pos.grade >= 3 || it.syllables <= 2))
            it,
    ];
    final fresh = [
      for (final c in cands)
        if (!recent.contains(c.id)) c,
    ]..shuffle(_rng);
    final stale = [
      for (final c in cands)
        if (recent.contains(c.id)) c,
    ]..shuffle(_rng);
    return [...fresh, ...stale].take(count).toList();
  }
}
