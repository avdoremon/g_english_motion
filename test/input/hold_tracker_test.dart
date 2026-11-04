import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/hold_tracker.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// Feeds [target] every 50 ms from [from] to [to] (inclusive).
List<HoldProgress> feed(HoldTracker h, String? target, int from, int to) => [
  for (var t = from; t <= to; t += 50) h.update(target, ms(t)),
];

void main() {
  test('holding a target for 1 s completes exactly once', () {
    final h = HoldTracker();
    final res = feed(h, 'a', 0, 1500);
    expect(res.where((r) => r.completed), hasLength(1));
    expect(res[20].completed, isTrue, reason: 'at 1000 ms');
    expect(res[21].completed, isFalse);
    expect(res.last.targetId, 'a');
  });

  test('progress follows the time on target', () {
    final h = HoldTracker();
    feed(h, 'a', 0, 450);
    final r = h.update('a', ms(500));
    expect(r.targetId, 'a');
    expect(r.progress, closeTo(0.5, 1e-9));
    expect(r.completed, isFalse);
  });

  test('a 1 s stall on the target (no updates) does not complete the hold', () {
    final h = HoldTracker();
    h.update('a', ms(0));
    final r = h.update('a', ms(1000));
    expect(r.completed, isFalse);
    expect(r.progress, 0);
    // A normal hold afterwards still works.
    expect(feed(h, 'a', 1050, 2100).where((r) => r.completed), hasLength(1));
  });

  test('a stall in the middle of a hold restarts it', () {
    final h = HoldTracker();
    feed(h, 'a', 0, 500);
    final r = h.update('a', ms(1500));
    expect(r.completed, isFalse);
    expect(r.progress, 0);
  });

  test('leaving for 150 ms keeps the progress', () {
    final h = HoldTracker();
    feed(h, 'a', 0, 500);
    expect(h.update(null, ms(550)).progress, closeTo(0.5, 1e-9));
    h.update(null, ms(650));
    final back = h.update('a', ms(650));
    expect(back.progress, closeTo(0.5, 1e-9), reason: 'away time not counted');
    expect(feed(h, 'a', 700, 1150).where((r) => r.completed), hasLength(1));
  });

  test('leaving for 300 ms resets', () {
    final h = HoldTracker();
    feed(h, 'a', 0, 500);
    expect(h.update(null, ms(800)).progress, 0);
    final back = h.update('a', ms(850));
    expect(back.progress, 0);
    expect(back.completed, isFalse);
  });

  test('returning after a long silence resets even without an away update', () {
    final h = HoldTracker();
    feed(h, 'a', 0, 300);
    h.update(null, ms(350));
    expect(h.update('a', ms(900)).progress, 0);
  });

  test('another target starts over', () {
    final h = HoldTracker();
    feed(h, 'a', 0, 700);
    final r = h.update('b', ms(750));
    expect(r.targetId, 'b');
    expect(r.progress, 0);
    expect(feed(h, 'b', 800, 1800).where((r) => r.completed), hasLength(1));
  });

  test('after completing, the same target does not complete again', () {
    final h = HoldTracker();
    feed(h, 'a', 0, 1000);
    expect(feed(h, 'a', 1050, 3000).where((r) => r.completed), isEmpty);
    // Leave, come back: completes again.
    h.update(null, ms(3050));
    h.update(null, ms(3300));
    feed(h, 'a', 3350, 4300);
    expect(h.update('a', ms(4350)).completed, isTrue);
  });

  test('reset clears everything', () {
    final h = HoldTracker();
    feed(h, 'a', 0, 700);
    h.reset();
    final r = h.update('a', ms(750));
    expect(r.progress, 0);
  });
}
