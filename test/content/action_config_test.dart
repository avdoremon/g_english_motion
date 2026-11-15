import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/action_config.dart';
import 'package:g_english_motion/input/action_detector.dart';

import '../helpers/map_asset_bundle.dart';

Map<String, Object?> _a({
  String id = 'jump',
  String command = 'Jump!',
  String ttsText = 'Puppy says: jump!',
  String hintVi = 'Nhảy lên nào!',
  Object minGrade = 1,
  Object maxGrade = 2,
}) => {
  'id': id,
  'command': command,
  'ttsText': ttsText,
  'hintVi': hintVi,
  'minGrade': minGrade,
  'maxGrade': maxGrade,
};

Future<ActionConfig> _load(List<Map<String, Object?>> actions) =>
    ActionConfig.load(
      MapAssetBundle({
        ActionConfig.assetPath: jsonEncode({'actions': actions}),
      }),
    );

void main() {
  test(
    'the shipped actions.json has the four actions for grades 1-2',
    () async {
      final text = File('assets/config/actions.json').readAsStringSync();
      final c = await ActionConfig.load(
        MapAssetBundle({ActionConfig.assetPath: text}),
      );
      for (final g in [1, 2]) {
        expect(c.forGrade(g).map((a) => a.action), PuppyAction.values);
      }
      expect(c.forGrade(3), isEmpty);
      final hands = c.forGrade(1).firstWhere((a) => a.id == 'handsUp');
      expect(hands.command, 'Hands up!');
      expect(hands.action, PuppyAction.handsUp);
      final clap = c.forGrade(1).firstWhere((a) => a.id == 'clap');
      expect(clap.command, 'Clap your hands!');
      final squat = c.forGrade(2).firstWhere((a) => a.id == 'squat');
      expect(squat.command, 'Squat down!');
    },
  );

  test('forGrade filters by the grade range', () async {
    final c = await _load([_a(), _a(id: 'clap', minGrade: 2, maxGrade: 3)]);
    expect(c.forGrade(1).map((a) => a.id), ['jump']);
    expect(c.forGrade(2).map((a) => a.id), ['jump', 'clap']);
    expect(c.forGrade(3).map((a) => a.id), ['clap']);
    expect(c.forGrade(4), isEmpty);
  });

  Future<void> bad(List<Map<String, Object?>> actions, String part) =>
      expectLater(
        _load(actions),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('actions.json'), contains(part)),
          ),
        ),
      );

  test('strict parsing', () async {
    await bad([_a(id: 'fly')], 'fly');
    await bad([_a(), _a()], 'duplicate');
    await bad([_a(command: '')], 'command');
    await bad([_a(ttsText: '')], 'ttsText');
    await bad([_a(hintVi: '')], 'hintVi');
    await bad([_a(minGrade: 3, maxGrade: 2)], 'grade');
    await bad([_a(minGrade: '1')], 'minGrade');
    await bad([_a(maxGrade: 1.5)], 'maxGrade');
  });

  test('malformed roots throw FormatException with the file name', () async {
    for (final text in ['[]', '{}', '{"actions":3}', '{"actions":[1]}', 'x']) {
      await expectLater(
        ActionConfig.load(MapAssetBundle({ActionConfig.assetPath: text})),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('actions.json'),
          ),
        ),
        reason: text,
      );
    }
  });
}
