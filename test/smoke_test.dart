import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/main.dart';

void main() {
  testWidgets('app shows the title', (tester) async {
    await tester.pumpWidget(const GEnglishMotionApp());
    expect(find.text('Tin Tin English'), findsOneWidget);
  });
}
