# Device spike: puppySays actions ("Theo Pup")

The four body actions of puppySays (jump, hands up, clap, squat) have only
been tested with synthetic pose sequences. Before the mode is switched on by
default, the owner measures them on a real phone. This page is the checklist.

Companion: the general measurement spike (jump miss rates, lanes, thermal run,
cast latency) is in [known-limitations.md](known-limitations.md).

## Setup

1. Install a debug or release build on the test phone (landscape, as played).
2. Parent area, turn on the switch "Trò Theo Pup (thử nghiệm)". It is off by
   default and also needs `assets/config/actions.json` to load.
3. Home, "Chọn trò chơi" (pick a game), choose grade 1 or 2, tile "Theo Pup".
   The mode plays alone; it is never part of the mix or the shuffle.
4. Prop the phone at the usual play distance (child fully visible, about 2 to
   3 m), same room light as a normal session. Run the calibration screen as a
   child would (stand still in the middle).
5. Test with at least two people: an adult first, then children aged 6 to 7.
   Keep the screen visible from the TV cast if that is how it will be played.

## What to do and what to count

Run each action 20 times per person, one command at a time, waiting for the
puppy's prompt to finish before acting. Keep a tally sheet per action:

| Action | What the tester does | Count |
| --- | --- | --- |
| Jump | Both feet off the floor, once | hits, misses |
| Hands up | Both hands above the head, held about half a second | hits, misses |
| Clap | Arms wide, then hands together in front of the chest | hits, misses |
| Squat | Hips down about a third of the body height, held a moment | hits, misses |

- **Miss**: the action was clearly performed while the clock ran and the round
  still ended as "Hết giờ" (timeout). Also note if it fired late (more than
  about 1 s after the action).
- **False detection**: an action registered that the tester did not do.
  Measure with the app in a puppySays round while the tester:
  - stands still for 3 minutes (count triggers of any action),
  - walks around, turns sideways, bends to pick something up, waves hello,
  - lets a second person walk through the frame.
  A false trigger only matters when it equals the current command (it would
  award a star), but note every one you see in the log.
- Also note: a command answered by the wrong action cannot happen (other
  actions are ignored), so a round that never ends correct is always either a
  miss or a child who did not act.

For each action record: person, distance, light, hits, misses, false triggers
per minute standing still, and any pattern (only fast jumps missed, only
children miss squats, and so on).

## Where to tune (all in `lib/input/`)

Only change one constant at a time and repeat the 20-try run.

| Symptom | Constant (default) | File |
| --- | --- | --- |
| Jump missed | `threshold` (0.12 torso heights) lower; `debounce` (600 ms) | `jump_detector.dart` |
| Jump false fires (leaning, walking) | `threshold` higher; drift limits `_driftRangeRatio` (0.7), `_stillRangeRatio` (0.35) | `jump_detector.dart` |
| Hands up missed | `hold` (500 ms) shorter; `grace` (150 ms) longer | `raise_hands_detector.dart` |
| Hands up fires early (stretching) | `hold` longer | `raise_hands_detector.dart` |
| Clap missed | `apartShoulderWidths` (1.5) lower; `togetherShoulderWidths` (0.25) higher; `window` (800 ms) longer; `maxDyTorso` (0.25) higher | `clap_detector.dart` |
| Clap false fires (arms waving) | `apartShoulderWidths` higher; `togetherShoulderWidths` lower; `debounce` (800 ms) | `clap_detector.dart` |
| Squat missed | `dropTorso` (0.25 torso heights) lower; `hold` (300 ms) shorter | `squat_detector.dart` |
| Squat false fires (bending down) | `dropTorso` higher; `hold` longer; `releaseTorso` (0.10) | `squat_detector.dart` |

Shared: `Pose.minConfidence` (landmark trust) in `pose_types.dart`. The
detectors are combined in `action_detector.dart`; the round that grades them
is `lib/modes/action_round.dart`. Keep the synthetic tests green after each
change (`flutter test test/input`) and add a test for a recorded failure.

If detection is poor only for squat and jump, check the calibration first:
both read the resting hip height from it (`ActionDetector.rebaseline` can
re-take the resting position).

## Go / no-go bar

Enable by default (and consider showing the tile without the parent switch)
only when, across at least 2 adults and 4 children, on the target phone:

- jump and hands up: detection of at least 90 % (hits / tries),
- clap and squat: detection of at least 80 %,
- fewer than 1 false trigger per minute standing still, for each action,
- no crash, camera loss or frame-rate drop below about 10 fps during a
  10-minute puppySays session.

Below the bar: tune once or twice using the table above. If an action still
cannot reach it, either remove that command from `actions.json` (the other
three keep working) or keep the mode behind the parent switch as experimental.
Record the measured numbers in the known-limitations page when done.

- Confirm on device that the clap pictogram (`Icons.sign_language`) does not read as sign language to children; swap the icon if it does.
