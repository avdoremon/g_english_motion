import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/app.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/ui/shell/game_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/game_harness.dart';

class _NoWakelock implements Wakelock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

void main() {
  late ProgressStore store;
  late FakePoseFrameSource source;

  Future<void> pumpApp(
    WidgetTester tester, {
    bool content = true,
    bool safetyAcked = true,
    PermissionOutcome permission = PermissionOutcome.granted,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (safetyAcked) 'progress.safetyAck': true,
    });
    store = ProgressStore(await SharedPreferences.getInstance());
    source = FakePoseFrameSource.fromStream(
      const Stream<Never>.empty(),
      outcome: permission,
    );
    final audio = AudioService(
      HarnessTts([]),
      HarnessClips(),
      assetExists: (_) => false,
    );
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GEnglishMotionApp(
        deps: AppDependencies(
          store: store,
          audio: audio,
          repo: ContentRepository(content ? [harnessUnit()] : []),
          levels: const [harnessLevel],
          sourceFactory: () => source,
          ticker: () => const Stream<Duration>.empty(),
          wakelock: _NoWakelock(),
        ),
      ),
    );
  }

  testWidgets(
    'home renders without any content; Play shows "Chưa có bài học"',
    (tester) async {
      await pumpApp(tester, content: false);
      expect(find.byKey(const ValueKey('play')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      expect(find.text('Chưa có bài học'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(source.started, isFalse);
      await tester.tap(find.text('Đóng'));
      await tester.pump();
      expect(find.text('Chưa có bài học'), findsNothing);
      expect(find.byKey(const ValueKey('play')), findsOneWidget);
    },
  );

  testWidgets('first Play shows the safety screen, then asks for the camera', (
    tester,
  ) async {
    await pumpApp(tester, safetyAcked: false);
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    expect(find.text('Đã hiểu'), findsOneWidget);
    await tester.tap(find.text('Đã hiểu'));
    await tester.pump();
    await tester.pump();
    expect(source.started, isTrue);
    expect(find.textContaining('Giữ yên'), findsOneWidget);
  });

  testWidgets('camera denied shows the permission screen; exit goes home', (
    tester,
  ) async {
    await pumpApp(tester, permission: PermissionOutcome.denied);
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Thử lại'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('exit')));
    await tester.pump();
    expect(find.byKey(const ValueKey('play')), findsOneWidget);
  });

  testWidgets('parent button opens the gate', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('parent-button')));
    await tester.pumpAndSettle();
    expect(find.text('Dành cho bố mẹ'), findsWidgets);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('play')), findsOneWidget);
  });
}
