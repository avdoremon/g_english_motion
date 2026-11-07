import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/ui/mascot/space_pup_painter.dart';
import 'package:g_english_motion/ui/mascot/tin_tin.dart';

Future<Uint8List> _render(TinTinState s, double t) async {
  final rec = ui.PictureRecorder();
  SpacePupPainter(state: s, t: t).paint(Canvas(rec), const Size(96, 96));
  final img = await rec.endRecording().toImage(96, 96);
  final data = await img.toByteData();
  return data!.buffer.asUint8List();
}

void main() {
  const labels = {
    TinTinState.idle: 'Tin Tin đang chờ em',
    TinTinState.happy: 'Tin Tin đang vui',
    TinTinState.sad: 'Tin Tin đang buồn',
    TinTinState.cheer: 'Tin Tin đang reo mừng',
    TinTinState.dance: 'Tin Tin đang nhảy múa',
  };

  for (final s in TinTinState.values) {
    testWidgets('renders $s with semantics label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: TinTin(state: s, size: 96)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(labels[s]!), findsOneWidget);
      handle.dispose();
    });
  }

  testWidgets('no running animation when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Center(child: TinTin(state: TinTinState.cheer, size: 96)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 5));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('sad and happy paint different pixels', (tester) async {
    await tester.runAsync(() async {
      final a = await _render(TinTinState.sad, 0);
      final b = await _render(TinTinState.happy, 0);
      expect(a, isNot(equals(b)));
    });
  });
}
