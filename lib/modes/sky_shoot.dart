import 'dart:math';

import '../content/question_models.dart';
import '../input/game_input_event.dart';
import '../input/pose_types.dart';
import 'round.dart';

/// The sky of one SkyShoot question: the sweeping arrow and the drifting
/// answers, both pure functions of time (the same clock as the pose frames'
/// timestamps), so a shot can be scored at the instant the child saw.
///
/// The arrow sweeps between [arrowMin] and [arrowMax], bouncing at the ends,
/// in a random initial direction at a random speed within +-20% of
/// [sweepSpeed] (fractions of the width per second). Answer i drifts slowly
/// around its slot (i + 0.5) / n; the drift is small enough that neighbours
/// stay more than two hit radii apart.
class SkyField {
  SkyField({
    required Random rng,
    required this.answerCount,
    required this.sweepSpeed,
  }) : assert(
         answerCount >= 1 && answerCount <= 4,
         'neighbours stay > 2 hit radii apart only for up to 4 answers',
       ),
       _direction = rng.nextBool() ? 1 : -1,
       _speed = sweepSpeed * (0.8 + 0.4 * rng.nextDouble()),
       _start =
           arrowMin + (arrowMax - arrowMin) * (0.25 + 0.5 * rng.nextDouble()),
       _phase = [
         for (var i = 0; i < answerCount; i++) rng.nextDouble() * 2 * pi,
       ],
       _period = [
         for (var i = 0; i < answerCount; i++) 8 + 4 * rng.nextDouble(),
       ];

  static const double arrowMin = 0.1;
  static const double arrowMax = 0.9;

  /// Largest drift of an answer around its slot, as a fraction of the slot
  /// width (1 / answerCount).
  static const double driftOfSlot = 0.15;

  final int answerCount;
  final double sweepSpeed;

  final int _direction;
  final double _speed;
  final double _start;
  final List<double> _phase;
  final List<double> _period;

  double _seconds(Duration t) => t.inMicroseconds / 1e6;

  /// Arrow x (0..1) at [t]; defined for any [t] (a triangle wave).
  double arrowX(Duration t) {
    final span = arrowMax - arrowMin;
    final travelled = (_start - arrowMin) + _direction * _speed * _seconds(t);
    final m = travelled % (2 * span);
    return arrowMin + (m <= span ? m : 2 * span - m);
  }

  /// Centre x (0..1) of answer [i] at [t].
  double answerX(int i, Duration t) {
    final slot = 1 / answerCount;
    final drift =
        driftOfSlot * slot * sin(2 * pi * _seconds(t) / _period[i] + _phase[i]);
    return (i + 0.5) * slot + drift;
  }
}

enum SkyPhase { aiming, reeling, resolved }

/// SkyShoot (grades 3-5): shoot the arrow at the answer you think is right,
/// then pull it in with alternating hands.
///
/// - [Confirmed] shoots at `field.arrowX(at - castLatency)`: the child saw the
///   arrow as it was one display latency before the frame the event comes
///   from, so the shot is scored there, not where the arrow is when the
///   event arrives.
/// - A hit starts [SkyPhase.reeling] and stops the clock (the question time
///   limit no longer applies); instead [reelTimeout] without a counted pull
///   resolves the round as [RoundResult.timeout] (a retry, not a wrong
///   answer); a miss costs a shot and with none left
///   the question is wrong.
/// - [Pulled] counts only while reeling and only when the hand differs from
///   the last counted one; [pullsNeeded] pulls grade the hit answer.
/// - The clock runs only while aiming; before [start] and while the player is
///   lost, shots and pulls are ignored (not graded).
class SkyShootRound implements Round {
  SkyShootRound(
    this.question, {
    required this.timeLimit,
    required this.field,
    required this.castLatency,
    this.hitRadius = 0.08,
    this.shots = 3,
    this.pullsNeeded = 4,
    this.reelTimeout = const Duration(seconds: 20),
  }) : assert(question.choices.isNotEmpty, 'a question needs choices'),
       _shotsLeft = shots,
       _remaining = timeLimit;

  final ChoiceQuestion question;
  final SkyField field;
  final Duration castLatency;
  final double hitRadius;
  final int pullsNeeded;

  /// A hit answer that is not pulled in within this long (no beat counted
  /// since the hit or the last counted beat) ends the round as
  /// [RoundResult.timeout], never as wrong: the child may simply not have
  /// understood the pull. Runs only while the player is present.
  final Duration reelTimeout;

  Duration _reelIdle = Duration.zero;
  Duration _remaining;
  int _shotsLeft;
  bool _started = false;
  bool _playerPresent = true;
  SkyPhase _phase = SkyPhase.aiming;
  int? _hitIndex;
  double? _hitX;
  int _pulls = 0;
  Hand? _lastHand;
  RoundResult? _result;
  int? _chosenIndex;

  SkyPhase get phase => _phase;

  /// Shots at the start of the question.
  final int shots;
  int get shotsLeft => _shotsLeft;
  int? get hitIndex => _hitIndex;
  int get pulls => _pulls;

  /// Where (x, 0..1) the hit answer was when it was hit; it stays there while
  /// it is reeled in.
  double? get hitX => _hitX;

  @override
  RoundResult? get result => _result;

  @override
  int? get chosenIndex => _chosenIndex;

  @override
  Duration get remaining => _remaining;

  @override
  final Duration timeLimit;

  @override
  double get elapsedFraction {
    final limit = timeLimit.inMicroseconds;
    if (limit <= 0) return 1.0;
    return (1 - _remaining.inMicroseconds / limit).clamp(0.0, 1.0);
  }

  @override
  bool get clockRunning =>
      _started &&
      _playerPresent &&
      _result == null &&
      _phase == SkyPhase.aiming;

  @override
  void start() => _started = true;

  @override
  void onEvent(GameInputEvent e) {
    if (_result != null) return;
    switch (e) {
      case PlayerLost():
        _playerPresent = false;
      case PlayerFound():
        _playerPresent = true;
      case Confirmed(:final at):
        if (!_started || !_playerPresent || _phase != SkyPhase.aiming) return;
        _shoot(at);
      case Pulled(:final hand):
        if (!_started || !_playerPresent || _phase != SkyPhase.reeling) return;
        _pull(hand);
      case LaneChanged() || CursorMoved() || HandRaised() || ActionPerformed():
        break;
    }
  }

  void _shoot(Duration at) {
    final t = at - castLatency;
    final x = field.arrowX(t);
    int? best;
    var bestDist = double.infinity;
    for (var i = 0; i < question.choices.length; i++) {
      final d = (field.answerX(i, t) - x).abs();
      if (d <= hitRadius && d < bestDist) {
        best = i;
        bestDist = d;
      }
    }
    if (best != null) {
      _hitIndex = best;
      _hitX = field.answerX(best, t);
      _phase = SkyPhase.reeling;
      _reelIdle = Duration.zero;
      return;
    }
    _shotsLeft--;
    if (_shotsLeft <= 0) {
      _shotsLeft = 0;
      _phase = SkyPhase.resolved;
      _result = RoundResult.wrong;
    }
  }

  void _pull(Hand hand) {
    if (hand == _lastHand) return;
    _lastHand = hand;
    _pulls++;
    _reelIdle = Duration.zero;
    if (_pulls >= pullsNeeded) {
      _phase = SkyPhase.resolved;
      _chosenIndex = _hitIndex;
      _result = _hitIndex == question.correctIndex
          ? RoundResult.correct
          : RoundResult.wrong;
    }
  }

  @override
  void tick(Duration dt) {
    if (dt <= Duration.zero) return;
    if (_started &&
        _playerPresent &&
        _result == null &&
        _phase == SkyPhase.reeling) {
      _reelIdle += dt;
      if (_reelIdle >= reelTimeout) {
        _phase = SkyPhase.resolved;
        _result = RoundResult.timeout;
      }
      return;
    }
    if (!clockRunning) return;
    _remaining -= dt;
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      _phase = SkyPhase.resolved;
      _result = RoundResult.timeout;
    }
  }
}
