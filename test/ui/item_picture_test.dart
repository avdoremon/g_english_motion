import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/ui/screens/lane_jump_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

ContentItem item(String id, String word, String? image) => ContentItem(
  id: id,
  word: word,
  ttsText: word,
  image: image,
  modes: const [ModeKind.laneJump],
);

final ball = item('ball', 'ball', 'grade1/ball.png');
final boy = item('boy', 'boy', 'grade1/boy.png');
final items = {
  for (final i in [ball, boy]) i.id: i,
};

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(body: Center(child: child)),
);

ChoiceQuestion question(QuestionForm form) => ChoiceQuestion(
  itemId: 'ball',
  form: form,
  ttsText: 'ball',
  promptImageItemId: form == QuestionForm.seePicturePickWord ? 'ball' : null,
  choices: [
    for (final i in [ball, boy])
      ChoiceOption(
        itemId: i.id,
        showPicture: form == QuestionForm.listenPickPicture,
        showWord: form != QuestionForm.listenPickPicture,
      ),
  ],
  correctIndex: 0,
);

void main() {
  group('ItemPicture', () {
    testWidgets('draws the bundled PNG with the given semantic label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(ItemPicture(item: ball, size: 100, semanticLabel: 'ball')),
      );
      final img = tester.widget<Image>(find.byType(Image));
      final provider = img.image as AssetImage;
      expect(provider.assetName, 'assets/images/grade1/ball.png');
      expect(img.semanticLabel, 'ball');
      // No first-letter circle while the picture is the content.
      expect(find.text('B'), findsNothing);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });

    testWidgets('falls back to the letter circle when the asset is missing', (
      tester,
    ) async {
      final missing = item('x', 'zebra', 'grade1/does_not_exist.png');
      await tester.pumpWidget(host(ItemPicture(item: missing)));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('no semanticLabel: the picture says nothing about the word', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(ItemPicture(item: ball)));
      expect(tester.widget<Image>(find.byType(Image)).semanticLabel, isNull);
      expect(find.bySemanticsLabel('ball'), findsNothing);
      handle.dispose();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });

    testWidgets(
      'letter circle carries the label when given, never the letter',
      (tester) async {
        final handle = tester.ensureSemantics();
        final cat = item('c', 'cat', null);
        await tester.pumpWidget(
          host(ItemPicture(item: cat, semanticLabel: 'cat')),
        );
        expect(find.bySemanticsLabel('cat'), findsOneWidget);
        expect(find.bySemanticsLabel('C'), findsNothing);
        await tester.pumpWidget(host(ItemPicture(item: cat)));
        expect(find.bySemanticsLabel('cat'), findsNothing);
        expect(find.bySemanticsLabel('C'), findsNothing);
        handle.dispose();
      },
    );

    testWidgets('no image: letter circle, no Image widget', (tester) async {
      await tester.pumpWidget(host(ItemPicture(item: item('c', 'cat', null))));
      expect(find.byType(Image), findsNothing);
      expect(find.text('C'), findsOneWidget);
    });

    testWidgets('a picture lane uses the Image of its own item', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 260,
            child: LaneTile(
              option: question(QuestionForm.listenPickPicture).choices[1],
              item: boy,
              selected: false,
            ),
          ),
        ),
      );
      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect(
        (provider as AssetImage).assetName,
        'assets/images/grade1/boy.png',
      );
      expect(find.text('boy'), findsNothing, reason: 'picture only');
      expect(find.bySemanticsLabel('Hình boy'), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });

    testWidgets('a lane with a letter-circle fallback is announced by word', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final cat = item('c', 'cat', null);
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            height: 260,
            child: LaneTile(
              option: const ChoiceOption(
                itemId: 'c',
                showPicture: true,
                showWord: false,
              ),
              item: cat,
              selected: false,
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Hình cat'), findsOneWidget);
      expect(find.bySemanticsLabel('C'), findsNothing);
      handle.dispose();
    });
  });

  group('QuestionPrompt', () {
    ContentItem lookup(String id) => items[id]!;

    testWidgets('listenPickPicture shows no Text equal to the answer word', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          QuestionPrompt(
            question: question(QuestionForm.listenPickPicture),
            itemFor: lookup,
          ),
        ),
      );
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.text('ball'), findsNothing);
      expect(find.byType(Image), findsNothing);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data, isNot('ball'));
      }
    });

    testWidgets('listenPickPicture reveals the word in the feedback', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          QuestionPrompt(
            question: question(QuestionForm.listenPickPicture),
            itemFor: lookup,
            feedback: true,
          ),
        ),
      );
      expect(find.text('ball'), findsOneWidget);
    });

    testWidgets('seePicturePickWord shows the real picture, no word', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          QuestionPrompt(
            question: question(QuestionForm.seePicturePickWord),
            itemFor: lookup,
          ),
        ),
      );
      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect(
        (provider as AssetImage).assetName,
        'assets/images/grade1/ball.png',
      );
      expect(find.text('B'), findsNothing);
      expect(find.text('ball'), findsNothing);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });

    testWidgets('seePicturePickWord prompt does not announce the answer', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          QuestionPrompt(
            question: question(QuestionForm.seePicturePickWord),
            itemFor: lookup,
          ),
        ),
      );
      final sem = tester.getSemantics(
        find.byKey(const ValueKey('prompt-picture')),
      );
      expect(sem.label, 'Hình cần chọn');
      expect(sem.label, isNot(contains('ball')));
      expect(find.bySemanticsLabel(RegExp('ball')), findsNothing);
      handle.dispose();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });

    testWidgets('prompt letter-circle fallback is not announced as a letter', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final noPic = {'ball': item('ball', 'ball', null), 'boy': boy};
      await tester.pumpWidget(
        host(
          QuestionPrompt(
            question: question(QuestionForm.seePicturePickWord),
            itemFor: (id) => noPic[id]!,
          ),
        ),
      );
      expect(find.text('B'), findsOneWidget);
      expect(find.bySemanticsLabel('Hình cần chọn'), findsOneWidget);
      expect(find.bySemanticsLabel('B'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('ball')), findsNothing);
      handle.dispose();
    });
  });
}
