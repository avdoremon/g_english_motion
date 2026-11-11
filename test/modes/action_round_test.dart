import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/action_detector.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/modes/action_round.dart';
import 'package:g_english_motion/modes/round.dart';

const _q = ActionQuestion(
  itemId: 'clap',
  ttsText: 'Puppy says: clap your hands!',
  command: 'Clap your hands!',
  hintVi: 'Vỗ tay nào!',
  action: PuppyAction.clap,
);

const _limit = Duration(seconds: 10);
const _clap = ActionPerformed(PuppyAction.clap, at: Duration.zero);
const _jump = ActionPerformed(PuppyAction.jump, at: Duration.zero);

ActionRound _round() => ActionRound(_q, timeLimit: _limit);

void main() {
  test('ActionQuestion is a doAction question', () {
    expect(_q.form, QuestionForm.doAction);
    expect(_q.itemId, 'clap');
  });

  test('the matching action is correct', () {
    final r = _round()..start();
    expect(r.clockRunning, isTrue);
    r.onEvent(_clap);
    expect(r.result, RoundResult.correct);
    expect(r.clockRunning, isFalse);
  });

  test('other actions are ignored, never wrong', () {
    final r = _round()..start();
    for (final a in [
      PuppyAction.jump,
      PuppyAction.handsUp,
      PuppyAction.squat,
    ]) {
      r.onEvent(ActionPerformed(a, at: Duration.zero));
    }
    expect(r.result, isNull);
    r.onEvent(_clap);
    expect(r.result, RoundResult.correct);
  });

  test('a wrong action then timeout is timeout, not wrong', () {
    final r = _round()..start();
    r.onEvent(_jump);
    r.tick(_limit);
    expect(r.result, RoundResult.timeout);
  });

  test('events before start are ignored', () {
    final r = _round();
    r.onEvent(_clap);
    expect(r.result, isNull);
    r.start();
    expect(r.result, isNull);
  });

  test('lost pauses the clock and ignores actions; found resumes', () {
    final r = _round()..start();
    r.onEvent(const PlayerLost(at: Duration.zero));
    expect(r.clockRunning, isFalse);
    r.tick(_limit);
    expect(r.result, isNull);
    expect(r.remaining, _limit);
    r.onEvent(_clap);
    expect(r.result, isNull);
    r.onEvent(const PlayerFound(at: Duration.zero));
    expect(r.clockRunning, isTrue);
    r.onEvent(_clap);
    expect(r.result, RoundResult.correct);
  });

  test('events after the result are ignored', () {
    final r = _round()..start();
    r.onEvent(_clap);
    r.onEvent(const PlayerLost(at: Duration.zero));
    r.tick(_limit);
    expect(r.result, RoundResult.correct);
    final t = _round()..start();
    t.tick(_limit);
    t.onEvent(_clap);
    expect(t.result, RoundResult.timeout);
  });

  test('clock and elapsedFraction', () {
    final r = _round()..start();
    expect(r.elapsedFraction, 0);
    r.tick(const Duration(seconds: 5));
    expect(r.remaining, const Duration(seconds: 5));
    expect(r.elapsedFraction, closeTo(0.5, 1e-9));
    r.tick(Duration.zero);
    r.tick(const Duration(seconds: -1));
    expect(r.remaining, const Duration(seconds: 5));
    expect(r.chosenIndex, isNull);
  });

  test('hand and lane events are ignored', () {
    final r = _round()..start();
    r.onEvent(const HandRaised(Hand.left, at: Duration.zero));
    expect(r.result, isNull);
  });
}
