import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/models.dart';

import '../helpers/map_asset_bundle.dart';

const _u01 = '''
{"grade":1,"unit":"u01","index":1,"title":"Hello","items":[
 {"id":"g1u01-ball","word":"ball","ttsText":"ball","image":"ball.png","syllables":1,
  "distractorIds":["g1u01-bag"],"modes":["laneJump","sayIt"]},
 {"id":"g1u01-bag","word":"bag","ttsText":"bag","modes":["dragSpell"],
  "sentencePatterns":["It is a bag."],"spokenVariants":["bag","bug"]}
]}''';

Future<ContentRepository> _load(Map<String, String> files) =>
    ContentRepository.loadFromAssets(
      MapAssetBundle(files),
      listAssets: (_) async => files.keys.toList(),
    );

void main() {
  test('loads units and resolves items by id', () async {
    final r = await _load({'assets/content/grade1/u01.json': _u01});
    expect(r.byId('g1u01-ball').word, 'ball');
    expect(r.byId('g1u01-ball').modes, [ModeKind.laneJump, ModeKind.sayIt]);
    expect(r.byId('g1u01-bag').image, isNull);
    expect(r.byId('g1u01-bag').syllables, 1);
    expect(r.byId('g1u01-bag').spokenVariants, ['bag', 'bug']);
    expect(r.unitsFor(1).single.title, 'Hello');
    expect(r.unitsFor(2), isEmpty);
  });

  test('byId throws StateError for unknown id', () async {
    final r = await _load({'assets/content/grade1/u01.json': _u01});
    expect(() => r.byId('nope'), throwsStateError);
  });

  test('missing id -> FormatException naming the file', () async {
    const bad =
        '{"grade":1,"unit":"u01","index":1,"title":"t","items":'
        '[{"word":"x","ttsText":"x","modes":[]}]}';
    expect(
      _load({'assets/content/grade1/bad.json': bad}),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('bad.json'),
        ),
      ),
    );
  });

  test('malformed json -> FormatException naming the file', () async {
    expect(
      _load({'assets/content/grade1/broken.json': '{oops'}),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('broken.json'),
        ),
      ),
    );
  });

  test('unknown distractor id is rejected', () {
    const u = Unit(
      grade: 1,
      index: 1,
      id: 'u01',
      title: 't',
      items: [
        ContentItem(
          id: 'a',
          word: 'a',
          ttsText: 'a',
          distractorIds: ['zzz'],
          modes: [],
        ),
      ],
    );
    expect(() => ContentRepository([u]), throwsArgumentError);
  });

  test('duplicate ids are rejected', () {
    const item = ContentItem(id: 'a', word: 'a', ttsText: 'a', modes: []);
    const u = Unit(
      grade: 1,
      index: 1,
      id: 'u01',
      title: 't',
      items: [item, item],
    );
    expect(() => ContentRepository([u]), throwsArgumentError);
  });

  test(
    'loads only json under assets/content from default-style list',
    () async {
      final r = await ContentRepository.loadFromAssets(
        MapAssetBundle({'assets/content/grade1/u01.json': _u01}),
        listAssets: (_) async => [
          'assets/content/grade1/u01.json',
          'assets/content/grade1/.gitkeep',
          'assets/config/levels.json',
        ],
      );
      expect(r.unitsFor(1), hasLength(1));
    },
  );
}
