import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/ui/shell/game_shell.dart';
import 'package:g_english_motion/ui/shell/pose_camera_host.dart';

class _Tts implements SpeechEngine {
  @override
  Future<bool> isEnglishAvailable() async => false;
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _Clips implements ClipPlayer {
  @override
  Future<bool> play(String assetPath) async => false;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _Wakelock implements Wakelock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

Timer _timer(Duration d, void Function() cb) => Timer(d, cb);

void main() {
  final created = <Map<Object?, Object?>>[];
  final disposed = <Object?>[];

  setUp(() {
    created.clear();
    disposed.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          switch (call.method) {
            case 'create':
              created.add(call.arguments as Map<Object?, Object?>);
              return 1; // texture id
            case 'dispose':
              disposed.add(call.arguments);
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  testWidgets('hosts the plugin preview view, non-zero, invisible, inert', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: PoseCameraHost()),
      ),
    );
    await tester.pump();

    final view = tester.widget<AndroidView>(find.byType(AndroidView));
    expect(view.viewType, PoseCameraHost.viewType);
    expect(PoseCameraHost.viewType, 'camera_preview_view');
    // Zero size would defer the platform view's creation forever, so the
    // camera preview surface would never exist.
    final size = tester.getSize(find.byType(AndroidView));
    expect(size.width, greaterThan(0));
    expect(size.height, greaterThan(0));
    expect(size.width, lessThanOrEqualTo(1));
    // Opacity 0 would skip painting the view; nearly-transparent keeps it.
    final opacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.byType(AndroidView),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, greaterThan(0));
    expect(opacity.opacity, lessThan(0.05));
    expect(
      find.ancestor(
        of: find.byType(AndroidView),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
    expect(created, hasLength(1));
    expect(created.single['viewType'], 'camera_preview_view');
  });

  testWidgets('renders nothing off Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: PoseCameraHost(),
      ),
    );
    expect(find.byType(AndroidView), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('GameShell keeps one host for the whole play flow', (
    tester,
  ) async {
    final audio = AudioService(_Tts(), _Clips(), assetExists: (_) => false);
    Widget shell(String label) => Directionality(
      textDirection: TextDirection.ltr,
      child: GameShell(
        events: const Stream<GameInputEvent>.empty(),
        audio: audio,
        wakelock: _Wakelock(),
        timerFactory: _timer,
        cameraHost: const PoseCameraHost(),
        child: Text(label),
      ),
    );
    await tester.pumpWidget(shell('level 1'));
    await tester.pump();
    expect(find.byType(PoseCameraHost), findsOneWidget);
    // Next level: same shell, same platform view (the plugin hands out ONE
    // preview view; a second live one would need it in two parents).
    await tester.pumpWidget(shell('level 2'));
    await tester.pump();
    expect(find.byType(PoseCameraHost), findsOneWidget);
    expect(created, hasLength(1));
    expect(disposed, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(disposed, hasLength(1));
  });

  testWidgets('GameShell without a host has no platform view', (tester) async {
    final audio = AudioService(_Tts(), _Clips(), assetExists: (_) => false);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GameShell(
          events: const Stream<GameInputEvent>.empty(),
          audio: audio,
          wakelock: _Wakelock(),
          timerFactory: _timer,
          child: const SizedBox(),
        ),
      ),
    );
    expect(find.byType(AndroidView), findsNothing);
  });
}
