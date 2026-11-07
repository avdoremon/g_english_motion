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

  Widget host({required bool disable}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: disable),
      child: child!,
    ),
    home: const Center(child: TinTin(state: TinTinState.cheer, size: 96)),
  );

  testWidgets('no running animation when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(host(disable: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('control: cheer animates for 3 cycles then rests', (
    tester,
  ) async {
    await tester.pumpWidget(host(disable: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('pixel output differs across states and phases', (tester) async {
    await tester.runAsync(() async {
      final sad = await _render(TinTinState.sad, 0);
      final happy = await _render(TinTinState.happy, 0);
      final idle = await _render(TinTinState.idle, 0);
      expect(sad, isNot(equals(happy)));
      expect(idle, isNot(equals(happy)));
      expect(
        await _render(TinTinState.cheer, 0.25),
        isNot(equals(await _render(TinTinState.cheer, 0.75))),
      );
      var opaque = 0;
      for (var i = 3; i < idle.length; i += 4) {
        if (idle[i] > 0) opaque++;
      }
      expect(opaque, greaterThan(0));
    });
  });
}
