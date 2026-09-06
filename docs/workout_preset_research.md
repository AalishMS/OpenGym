# Evidence-based workout preset catalog

Research reviewed: 2026-09-06

## Purpose

This document defines a first catalog of OpenGym workout presets. It records the
research decisions, complete workouts, progression rules, and model gaps needed
to turn the programs into product data later.

The programs target healthy adults who know the listed lifts or can learn them
with qualified coaching. They do not replace medical advice, injury assessment,
or individualized coaching. A user with pain, an injury, a medical condition,
or pregnancy needs advice suited to their situation.

## Main research conclusion

No split has a universal physiological advantage. A 2024 meta-analysis found
similar strength and hypertrophy from split and full-body routines when weekly
volume was matched. A split is a schedule for distributing useful training. The
best choice is the one that fits the user's available days, tolerable session
length, lift-practice needs, and recovery.[^split]

The prescriptions below use the variables that research supports more strongly:

- For strength, put the lift being improved near the start of the session, use
  heavy loads, and practice it at least twice per week when the schedule allows.
  The 2026 ACSM position stand found better voluntary-strength results with
  loads of at least 80% 1RM, a full range of motion, 2-3 sets, priority exercises
  first, and at least two sessions per week.[^acsm]
- For hypertrophy, use multiple hard sets and enough weekly volume. The same
  position stand found more growth with at least 10 weekly sets per muscle. A
  2025 dose-response meta-regression found that more weekly volume tends to
  produce more growth, with diminishing returns.[^acsm][^dose]
- A wide load range can build muscle if sets require enough effort. Heavier loads
  produce better 1RM strength, so these presets use moderate reps for hypertrophy
  and low reps on the main lifts for strength.[^load]
- Hypertrophy tends to improve as sets finish closer to failure. The exact best
  distance remains uncertain, and momentary failure has no consistent advantage.
  The presets use 1-3 repetitions in reserve (RIR) for hypertrophy work and avoid
  routine failure on compound lifts.[^rir][^failure]
- Resting more than 60 seconds may provide a small hypertrophy benefit by
  preserving work. Research found no appreciable hypertrophy difference among
  rests longer than 90 seconds, so the programs use 2-3 minutes for compounds
  and 1-2 minutes for smaller isolation exercises.[^rest]
- Strength improves most in exercises performed early in the session. Exercise
  order has little measured effect on hypertrophy, so hypertrophy sessions still
  start with demanding compound work for practical fatigue management.[^order]
- Use the largest pain-free range of motion the user can control. Full range of
  motion has produced better strength and lower-body hypertrophy than partial
  range in aggregate research.[^rom]

These findings support program variables, not the exact branded routines below.
Researchers have not run trials on every exercise menu and schedule in this
catalog. The workouts are conservative programming applications of the evidence.

## Catalog summary

| ID | Goal | Split | Days | Best fit | Typical session |
|---|---|---|---:|---|---:|
| `HYP-FB-3` | Hypertrophy | Full body | 3 | New or busy lifter | 55-75 min |
| `HYP-UL-4` | Hypertrophy | Upper/lower | 4 | General default | 60-80 min |
| `HYP-PPL-6` | Hypertrophy | Push/pull/legs | 6 | Shorter, frequent sessions | 50-70 min |
| `HYP-ARNOLD-6` | Hypertrophy | Arnold split | 6 | Experienced, arm/shoulder emphasis | 55-75 min |
| `STR-FB-3` | Strength | Full body | 3 | New strength trainee | 60-80 min |
| `STR-UL-4` | Strength | Upper/lower | 4 | General strength | 65-85 min |
| `STR-SBD-5` | Strength | Lift-practice split | 5 | Experienced squat/bench/deadlift focus | 50-75 min |
| `HYB-UL-4` | Strength + hypertrophy | Powerbuilding upper/lower | 4 | General default | 65-85 min |
| `HYB-PPLUL-5` | Strength + hypertrophy | Push/pull/legs + upper/lower | 5 | Experienced five-day lifter | 60-80 min |
| `HYB-PPL-6` | Strength + hypertrophy | Heavy/light push/pull/legs | 6 | Experienced high-frequency lifter | 55-75 min |

Start most users with `HYP-FB-3`, `HYP-UL-4`, `STR-FB-3`, or `HYB-UL-4`.
Six-day plans leave less room for missed sessions and recovery errors.

## Prescription notation

Every listed set is a working set. Warm-up sets do not count toward the table.

- `3 x 8-12` means three working sets. The user keeps one load until all three
  sets reach 12 reps at the target RIR, then increases the load.
- `Seed` is the exact rep value OpenGym can place in each `SetTemplate`. The app
  cannot store a rep range today.
- `RIR 2` means the user should finish with about two possible clean reps left.
- Rest starts after a working set. Users may take longer when breathing or
  technique has not recovered.
- Preset weights should be `0.0`. A safe useful weight depends on the user.
- For bodyweight exercises, users record added load when appropriate. Product
  handling of bodyweight itself needs a separate design decision.

## Shared operating rules

### Warm-up

Before the first heavy compound, complete several low-fatigue ramp-up sets. One
example is 8 reps with a light load, 5 reps with a moderate load, and 2-3 reps
near the work weight. Use fewer warm-ups for later exercises that train the same
muscles. Warm-up sets should never approach failure.

### Progression

Hypertrophy exercises use double progression:

1. Pick a load that reaches the low end of the range at the stated RIR.
2. Add reps across later sessions while keeping the same load.
3. Increase load after every set reaches the top of the range at the stated RIR.
4. Return to the low or middle part of the range after increasing load.

A 2-5% load increase works as a starting rule. Small upper-body isolation lifts
may need the smallest plate jump or an extra rep before more weight.

Strength exercises use load progression:

1. Start the first week near RIR 3, even if the table permits RIR 2.
2. Add 1-2.5 kg to upper-body lifts or 2.5-5 kg to lower-body lifts after the
   user completes all prescribed reps with stable technique at the target RIR.
3. Keep the load unchanged after a grind, a missed rep, or technique breakdown.
4. Reduce the load by about 5-10% after two failed exposures, then build again.

Rep ranges on secondary strength work use double progression.

### Effort and failure

RIR is an estimate. New lifters should err on the easier side until their
estimates improve. Stop a set when technique changes enough to alter the lift.
Failure is optional on the final set of a stable isolation exercise. The preset
should not instruct failure on Squat, Deadlift, Bench Press, Overhead Press, or
other free-weight compounds.

### Recovery and volume adjustment

Run a preset for at least 6-8 weeks before judging it, unless pain or recovery
problems require an earlier change. Sleep, food intake, training history, age,
and outside activity change the volume a user can recover from.

Reduce one set from the affected muscle's exercises when performance declines
across two exposures, soreness persists into the next session, or joint
irritation grows. Add one weekly set only after several weeks of recovery and
progress, and change one muscle group at a time. A fixed deload calendar is not
required. A practical deload keeps the exercises, cuts working sets by about
half, and uses RIR 4-5 for one week when accumulated fatigue calls for it.

## Pure hypertrophy presets

Hypertrophy presets use moderate rep ranges for time efficiency and joint
tolerance. Most sets finish at RIR 1-3. Direct work plus compound-lift overlap
puts major muscle groups near a moderate weekly dose.

### `HYP-FB-3`: Full-body hypertrophy

Schedule: Monday A, Wednesday B, Friday C, or any three nonconsecutive days.

#### Full body A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 6-10 | 8 | 2 | 3 min |
| Bench Press | 3 x 8-12 | 10 | 2 | 2-3 min |
| Seated Cable Row | 3 x 8-12 | 10 | 2 | 2 min |
| Romanian Deadlift | 2 x 8-12 | 10 | 2 | 2-3 min |
| Lateral Raise | 2 x 12-20 | 15 | 1-2 | 1-2 min |
| Bicep Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Tricep Pushdown | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Full body B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Leg Press | 3 x 10-15 | 12 | 2 | 2-3 min |
| Incline Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Lat Pulldown | 3 x 8-12 | 10 | 2 | 2 min |
| Leg Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Rear Delt Fly | 2 x 12-20 | 15 | 1-2 | 1-2 min |
| Hammer Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Overhead Tricep Extension | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Full body C

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bulgarian Split Squat | 3 x 8-12 | 10 | 2 | 2-3 min |
| Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Barbell Row | 3 x 6-10 | 8 | 2 | 2-3 min |
| Hip Thrust | 3 x 8-12 | 10 | 2 | 2 min |
| Calf Raise | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Cable Lateral Raise | 2 x 12-20 | 15 | 1-2 | 1-2 min |
| Cable Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |

### `HYP-UL-4`: Upper/lower hypertrophy

Schedule: Monday upper A, Tuesday lower A, Thursday upper B, Friday lower B.

#### Upper A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 6-10 | 8 | 2 | 3 min |
| Seated Cable Row | 3 x 8-12 | 10 | 2 | 2 min |
| Incline Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Lat Pulldown | 3 x 8-12 | 10 | 2 | 2 min |
| Lateral Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Bicep Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Tricep Pushdown | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Lower A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 6-10 | 8 | 2 | 3 min |
| Romanian Deadlift | 3 x 8-12 | 10 | 2 | 2-3 min |
| Leg Press | 3 x 10-15 | 12 | 2 | 2 min |
| Leg Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Calf Raise | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Ab Wheel Rollout | 2 x 8-15 | 10 | 2 | 1-2 min |

#### Upper B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Pull-ups | 3 x 6-10 | 8 | 2 | 2-3 min |
| Dumbbell Shoulder Press | 3 x 8-12 | 10 | 2 | 2 min |
| Dumbbell Row | 3 x 8-12 | 10 | 2 | 2 min |
| Cable Fly | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Rear Delt Fly | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Hammer Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Overhead Tricep Extension | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Lower B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Front Squat | 3 x 8-12 | 10 | 2 | 3 min |
| Hip Thrust | 3 x 8-12 | 10 | 2 | 2 min |
| Bulgarian Split Squat | 3 x 8-12 | 10 | 2 | 2 min |
| Leg Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Seated Calf Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Leg Raise | 2 x 10-15 | 12 | 2 | 1-2 min |

### `HYP-PPL-6`: Push/pull/legs hypertrophy

Schedule: push A, pull A, legs A, rest, push B, pull B, legs B, rest. This is an
eight-day rotation rather than a rigid calendar week. Users who need a seven-day
calendar can train Monday through Saturday and rest Sunday.

#### Push A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 6-10 | 8 | 2 | 3 min |
| Incline Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Dumbbell Shoulder Press | 3 x 8-12 | 10 | 2 | 2 min |
| Cable Fly | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Lateral Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Tricep Pushdown | 3 x 10-15 | 12 | 1-2 | 1-2 min |

#### Pull A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Pull-ups | 3 x 6-10 | 8 | 2 | 2-3 min |
| Barbell Row | 3 x 6-10 | 8 | 2 | 2-3 min |
| Seated Cable Row | 3 x 8-12 | 10 | 2 | 2 min |
| Rear Delt Fly | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Bicep Curl | 3 x 8-12 | 10 | 1-2 | 1-2 min |
| Hammer Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Legs A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 6-10 | 8 | 2 | 3 min |
| Romanian Deadlift | 3 x 8-12 | 10 | 2 | 2-3 min |
| Leg Press | 3 x 10-15 | 12 | 2 | 2 min |
| Leg Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Calf Raise | 4 x 10-15 | 12 | 1-2 | 1-2 min |
| Ab Wheel Rollout | 2 x 8-15 | 10 | 2 | 1-2 min |

#### Push B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Overhead Press | 3 x 6-10 | 8 | 2 | 3 min |
| Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Chest Dips | 3 x 8-12 | 10 | 2 | 2 min |
| Cable Lateral Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Overhead Tricep Extension | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Tricep Pushdown | 2 x 12-20 | 15 | 1-2 | 1-2 min |

#### Pull B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Lat Pulldown | 3 x 8-12 | 10 | 2 | 2 min |
| T-Bar Row | 3 x 8-12 | 10 | 2 | 2 min |
| Single Arm Row | 3 x 10-15 | 12 | 2 | 2 min |
| Face Pull | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Preacher Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Cable Curl | 2 x 12-20 | 15 | 1-2 | 1-2 min |

#### Legs B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Front Squat | 3 x 8-12 | 10 | 2 | 3 min |
| Hip Thrust | 3 x 8-12 | 10 | 2 | 2 min |
| Bulgarian Split Squat | 3 x 8-12 | 10 | 2 | 2 min |
| Leg Extension | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Leg Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Seated Calf Raise | 4 x 12-20 | 15 | 1-2 | 1-2 min |

### `HYP-ARNOLD-6`: Arnold-style hypertrophy

Schedule: chest/back A, shoulders/arms A, legs A, rest, chest/back B,
shoulders/arms B, legs B, rest. Pairing opposing muscles can keep the session
moving, but users should still take the listed rest before repeating work for
the same muscle.

#### Chest and back A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 6-10 | 8 | 2 | 3 min |
| Pull-ups | 3 x 6-10 | 8 | 2 | 2-3 min |
| Incline Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Seated Cable Row | 3 x 8-12 | 10 | 2 | 2 min |
| Cable Fly | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Lat Pulldown | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Shoulders and arms A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Overhead Press | 3 x 6-10 | 8 | 2 | 3 min |
| Lateral Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Rear Delt Fly | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Bicep Curl | 3 x 8-12 | 10 | 1-2 | 1-2 min |
| Skull Crusher | 3 x 8-12 | 10 | 1-2 | 1-2 min |
| Hammer Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Tricep Pushdown | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Legs A

Use the `HYP-PPL-6` Legs A workout.

#### Chest and back B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Barbell Row | 3 x 6-10 | 8 | 2 | 2-3 min |
| Incline Bench Press | 3 x 8-12 | 10 | 2 | 2 min |
| Lat Pulldown | 3 x 8-12 | 10 | 2 | 2 min |
| Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Single Arm Row | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Cable Crossover | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Shoulders and arms B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Arnold Press | 3 x 8-12 | 10 | 2 | 2 min |
| Cable Lateral Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Face Pull | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Preacher Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Overhead Tricep Extension | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Cable Curl | 2 x 12-20 | 15 | 1-2 | 1-2 min |
| Tricep Pushdown | 2 x 12-20 | 15 | 1-2 | 1-2 min |

#### Legs B

Use the `HYP-PPL-6` Legs B workout.

## Pure strength presets

These programs build general strength in the listed lifts. Main lifts use heavy
sets, long rest, low reps, and RIR 2-3. They do not peak a powerlifter for a
competition and do not prescribe maximal singles.

### `STR-FB-3`: Full-body strength

Schedule: Monday A, Wednesday B, Friday C, or any three nonconsecutive days.

#### Strength A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 3 | 3 | 2-3 | 3-5 min |
| Bench Press | 3 x 3 | 3 | 2-3 | 3-5 min |
| Barbell Row | 3 x 5 | 5 | 2 | 3 min |
| Romanian Deadlift | 2 x 5 | 5 | 2-3 | 3 min |
| Ab Wheel Rollout | 3 x 8-12 | 10 | 2 | 1-2 min |

#### Strength B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Deadlift | 2 x 3 | 3 | 2-3 | 4-5 min |
| Overhead Press | 3 x 3 | 3 | 2-3 | 3-5 min |
| Front Squat | 3 x 5 | 5 | 2-3 | 3 min |
| Pull-ups | 3 x 5-8 | 6 | 2 | 2-3 min |
| Face Pull | 3 x 10-15 | 12 | 2 | 1-2 min |

#### Strength C

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 3 | 3 | 2-3 | 3-5 min |
| Squat | 3 x 3 | 3 | 2-3 | 3-5 min |
| Close Grip Bench Press | 3 x 5 | 5 | 2 | 3 min |
| Seated Cable Row | 3 x 5-8 | 6 | 2 | 2-3 min |
| Hip Thrust | 2 x 5-8 | 6 | 2 | 2-3 min |

### `STR-UL-4`: Upper/lower strength

Schedule: Monday upper A, Tuesday lower A, Thursday upper B, Friday lower B.

#### Upper strength A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 3 | 3 | 2-3 | 3-5 min |
| Overhead Press | 3 x 5 | 5 | 2-3 | 3 min |
| Barbell Row | 3 x 5 | 5 | 2 | 3 min |
| Pull-ups | 3 x 5-8 | 6 | 2 | 2-3 min |
| Tricep Pushdown | 2 x 8-12 | 10 | 2 | 1-2 min |

#### Lower strength A

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 3 | 3 | 2-3 | 3-5 min |
| Romanian Deadlift | 3 x 5 | 5 | 2-3 | 3 min |
| Bulgarian Split Squat | 2 x 6-8 | 6 | 2 | 2-3 min |
| Calf Raise | 3 x 8-12 | 10 | 2 | 1-2 min |
| Ab Wheel Rollout | 3 x 8-12 | 10 | 2 | 1-2 min |

#### Upper strength B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Overhead Press | 3 x 3 | 3 | 2-3 | 3-5 min |
| Close Grip Bench Press | 3 x 5 | 5 | 2-3 | 3 min |
| T-Bar Row | 3 x 5-8 | 6 | 2 | 2-3 min |
| Chin-ups | 3 x 5-8 | 6 | 2 | 2-3 min |
| Bicep Curl | 2 x 8-12 | 10 | 2 | 1-2 min |

#### Lower strength B

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Deadlift | 2 x 3 | 3 | 2-3 | 4-5 min |
| Front Squat | 3 x 5 | 5 | 2-3 | 3 min |
| Hip Thrust | 3 x 5-8 | 6 | 2 | 2-3 min |
| Leg Curl | 3 x 8-12 | 10 | 2 | 1-2 min |
| Seated Calf Raise | 3 x 8-12 | 10 | 2 | 1-2 min |

### `STR-SBD-5`: Squat, bench, and deadlift practice

Schedule: Monday squat, Tuesday bench, Wednesday rest, Thursday deadlift,
Friday bench/upper, Saturday squat/lower, Sunday rest. This plan suits users who
already tolerate five training days.

#### Squat strength

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 3 | 3 | 2-3 | 3-5 min |
| Bench Press | 3 x 5 | 5 | 3 | 3 min |
| Romanian Deadlift | 3 x 5 | 5 | 2-3 | 3 min |
| Barbell Row | 3 x 5 | 5 | 2 | 3 min |

#### Bench strength

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 3 | 3 | 2-3 | 3-5 min |
| Overhead Press | 3 x 5 | 5 | 2-3 | 3 min |
| Pull-ups | 3 x 5-8 | 6 | 2 | 2-3 min |
| Close Grip Bench Press | 2 x 5-8 | 6 | 2 | 2-3 min |
| Face Pull | 3 x 10-15 | 12 | 2 | 1-2 min |

#### Deadlift strength

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Deadlift | 2 x 3 | 3 | 2-3 | 4-5 min |
| Front Squat | 3 x 5 | 5 | 3 | 3 min |
| Seated Cable Row | 3 x 5-8 | 6 | 2 | 2-3 min |
| Leg Curl | 3 x 8-12 | 10 | 2 | 1-2 min |
| Ab Wheel Rollout | 3 x 8-12 | 10 | 2 | 1-2 min |

#### Bench and upper practice

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 5 | 5 | 3 | 3 min |
| Barbell Row | 3 x 5 | 5 | 2 | 3 min |
| Dumbbell Shoulder Press | 3 x 6-10 | 8 | 2 | 2-3 min |
| Lat Pulldown | 3 x 6-10 | 8 | 2 | 2-3 min |
| Tricep Pushdown | 2 x 8-12 | 10 | 2 | 1-2 min |
| Bicep Curl | 2 x 8-12 | 10 | 2 | 1-2 min |

#### Squat and lower practice

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 5 | 5 | 3 | 3 min |
| Hip Thrust | 3 x 5-8 | 6 | 2 | 2-3 min |
| Bulgarian Split Squat | 2 x 6-8 | 6 | 2 | 2-3 min |
| Leg Curl | 3 x 8-12 | 10 | 2 | 1-2 min |
| Calf Raise | 3 x 8-12 | 10 | 2 | 1-2 min |

## Strength and hypertrophy presets

Hybrid presets put low-rep strength work first, then use moderate and high reps
to accumulate muscle-building volume. Main-lift practice remains specific while
the accessories cover muscle groups that low-rep barbell work may underserve.

### `HYB-UL-4`: Powerbuilding upper/lower

Schedule: Monday upper strength, Tuesday lower strength, Thursday upper
hypertrophy, Friday lower hypertrophy.

#### Upper strength

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 3 | 3 | 2-3 | 3-5 min |
| Overhead Press | 3 x 5 | 5 | 2-3 | 3 min |
| Barbell Row | 3 x 5 | 5 | 2 | 3 min |
| Pull-ups | 3 x 5-8 | 6 | 2 | 2-3 min |
| Lateral Raise | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Tricep Pushdown | 2 x 8-12 | 10 | 1-2 | 1-2 min |
| Bicep Curl | 2 x 8-12 | 10 | 1-2 | 1-2 min |

#### Lower strength

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 3 | 3 | 2-3 | 3-5 min |
| Deadlift | 2 x 3 | 3 | 2-3 | 4-5 min |
| Leg Press | 3 x 8-12 | 10 | 2 | 2 min |
| Leg Curl | 3 x 8-12 | 10 | 2 | 1-2 min |
| Calf Raise | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Ab Wheel Rollout | 2 x 8-15 | 10 | 2 | 1-2 min |

#### Upper hypertrophy

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Incline Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Seated Cable Row | 3 x 8-12 | 10 | 2 | 2 min |
| Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Lat Pulldown | 3 x 8-12 | 10 | 2 | 2 min |
| Cable Lateral Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Overhead Tricep Extension | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Hammer Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |

#### Lower hypertrophy

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Front Squat | 3 x 8-12 | 10 | 2 | 3 min |
| Romanian Deadlift | 3 x 8-12 | 10 | 2 | 2-3 min |
| Bulgarian Split Squat | 3 x 8-12 | 10 | 2 | 2 min |
| Leg Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Seated Calf Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Leg Raise | 2 x 10-15 | 12 | 2 | 1-2 min |

### `HYB-PPLUL-5`: Push/pull/legs + upper/lower

Schedule: Monday push, Tuesday pull, Wednesday legs, Thursday rest, Friday
upper, Saturday lower, Sunday rest. The first three days emphasize strength; the
last two distribute hypertrophy work.

#### Push strength

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Bench Press | 3 x 3 | 3 | 2-3 | 3-5 min |
| Overhead Press | 3 x 5 | 5 | 2-3 | 3 min |
| Incline Dumbbell Press | 3 x 6-10 | 8 | 2 | 2 min |
| Lateral Raise | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Tricep Pushdown | 3 x 8-12 | 10 | 1-2 | 1-2 min |

#### Pull strength

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Deadlift | 2 x 3 | 3 | 2-3 | 4-5 min |
| Barbell Row | 3 x 5 | 5 | 2 | 3 min |
| Pull-ups | 3 x 5-8 | 6 | 2 | 2-3 min |
| Face Pull | 3 x 10-15 | 12 | 2 | 1-2 min |
| Bicep Curl | 3 x 8-12 | 10 | 1-2 | 1-2 min |

#### Legs strength

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Squat | 3 x 3 | 3 | 2-3 | 3-5 min |
| Romanian Deadlift | 3 x 5 | 5 | 2-3 | 3 min |
| Leg Press | 3 x 8-12 | 10 | 2 | 2 min |
| Leg Curl | 3 x 8-12 | 10 | 2 | 1-2 min |
| Calf Raise | 3 x 10-15 | 12 | 1-2 | 1-2 min |

#### Upper hypertrophy

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Incline Bench Press | 3 x 8-12 | 10 | 2 | 2 min |
| Seated Cable Row | 3 x 8-12 | 10 | 2 | 2 min |
| Dumbbell Shoulder Press | 3 x 8-12 | 10 | 2 | 2 min |
| Lat Pulldown | 3 x 8-12 | 10 | 2 | 2 min |
| Cable Fly | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Cable Lateral Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Hammer Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Overhead Tricep Extension | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Lower hypertrophy

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Front Squat | 3 x 8-12 | 10 | 2 | 3 min |
| Hip Thrust | 3 x 8-12 | 10 | 2 | 2 min |
| Bulgarian Split Squat | 3 x 8-12 | 10 | 2 | 2 min |
| Leg Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Seated Calf Raise | 4 x 12-20 | 15 | 1-2 | 1-2 min |
| Ab Wheel Rollout | 2 x 8-15 | 10 | 2 | 1-2 min |

### `HYB-PPL-6`: Heavy/light push/pull/legs

Schedule: push strength, pull strength, legs strength, rest, push hypertrophy,
pull hypertrophy, legs hypertrophy, rest. This eight-day rotation controls
fatigue better than forcing six consecutive sessions.

#### Push strength

Use the `HYB-PPLUL-5` Push strength workout.

#### Pull strength

Use the `HYB-PPLUL-5` Pull strength workout.

#### Legs strength

Use the `HYB-PPLUL-5` Legs strength workout.

#### Push hypertrophy

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Incline Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Dumbbell Press | 3 x 8-12 | 10 | 2 | 2 min |
| Dumbbell Shoulder Press | 3 x 8-12 | 10 | 2 | 2 min |
| Cable Fly | 2 x 10-15 | 12 | 1-2 | 1-2 min |
| Cable Lateral Raise | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Overhead Tricep Extension | 3 x 10-15 | 12 | 1-2 | 1-2 min |

#### Pull hypertrophy

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Lat Pulldown | 3 x 8-12 | 10 | 2 | 2 min |
| Seated Cable Row | 3 x 8-12 | 10 | 2 | 2 min |
| Single Arm Row | 3 x 10-15 | 12 | 2 | 2 min |
| Rear Delt Fly | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Preacher Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Hammer Curl | 2 x 10-15 | 12 | 1-2 | 1-2 min |

#### Legs hypertrophy

| Exercise | Prescription | Seed | RIR | Rest |
|---|---:|---:|---:|---:|
| Front Squat | 3 x 8-12 | 10 | 2 | 3 min |
| Hip Thrust | 3 x 8-12 | 10 | 2 | 2 min |
| Bulgarian Split Squat | 3 x 8-12 | 10 | 2 | 2 min |
| Leg Extension | 3 x 12-20 | 15 | 1-2 | 1-2 min |
| Leg Curl | 3 x 10-15 | 12 | 1-2 | 1-2 min |
| Seated Calf Raise | 4 x 12-20 | 15 | 1-2 | 1-2 min |

## Substitution rules

Presets need substitutions because equipment, anatomy, and skill differ. Keep
the movement role and rep intent when swapping. A substitution should not cause
pain and should let the user progress with stable technique.

| Role | Primary choice | Suitable library substitutions |
|---|---|---|
| Horizontal press | Bench Press | Dumbbell Press, Incline Bench Press, Push-ups |
| Vertical press | Overhead Press | Dumbbell Shoulder Press, Arnold Press |
| Vertical pull | Pull-ups | Chin-ups, Lat Pulldown |
| Horizontal pull | Barbell Row | Seated Cable Row, T-Bar Row, Dumbbell Row |
| Squat pattern | Squat | Front Squat, Hack Squat, Leg Press |
| Hip hinge | Romanian Deadlift | Deadlift, Hip Thrust, Glute Bridge |
| Single-leg squat | Bulgarian Split Squat | Lunges, Leg Press |
| Knee flexion | Leg Curl | Romanian Deadlift if no curl machine exists |
| Chest isolation | Cable Fly | Dumbbell Fly, Cable Crossover |
| Rear delts | Rear Delt Fly | Reverse Fly, Face Pull |
| Elbow flexion | Bicep Curl | Cable Curl, Hammer Curl, Preacher Curl |
| Elbow extension | Tricep Pushdown | Overhead Tricep Extension, Skull Crusher |

A user who substitutes a main strength lift changes the lift they will become
stronger at. Keep that substitute stable through the training block.

## Product implementation notes

### Current model mapping

Each workout day maps to one `WorkoutPlan`. Each exercise maps to an
`ExerciseTemplate`. Create one `SetTemplate` per working set with:

```text
SetTemplate(
  reps: <Seed column>,
  weight: 0.0,
)
```

Use the exact exercise strings in this document; they all exist in
`lib/data/exercise_library.dart`. Shared workout references such as “use Legs A”
should be expanded into complete copied plan data during preset creation. Do not
make one stored plan depend on another preset at runtime.

### Data the current model cannot represent

`SetTemplate` stores one rep value and one weight. It cannot store:

- lower and upper rep bounds;
- target RIR or RPE;
- rest time;
- exercise substitutions;
- warm-up instructions;
- progression rules;
- weekly schedule or ordered rest days;
- preset goal, experience level, duration, or version.

A first release can seed the exact `Seed` reps and show the shared rules in the
preset description. A stronger preset format should keep prescription metadata
separate from logged sets. Do not overload `weight: 0.0` or exercise notes with
encoded control data.

### Suggested preset schema

```text
WorkoutPreset
  id: stable machine identifier
  version: integer
  name: user-facing split name
  goal: hypertrophy | strength | hybrid
  experience: beginner | intermediate | experienced
  schedule: ordered workout-day and rest-day references
  sourceReviewDate: date
  plans[]
    name
    exercises[]
      exerciseName
      sets
      repMin
      repMax
      seedReps
      targetRirMin
      targetRirMax
      restSeconds
      substitutions[]
```

Copy a preset into ordinary user-owned plans when selected. Store the preset ID
and version as optional provenance if the product needs update notices. Never
overwrite a user's edited copy when the catalog changes.

### Selection flow

Ask for goal and available days first. Experience and preferred session length
can break ties:

| Goal | 3 days | 4 days | 5 days | 6 days |
|---|---|---|---|---|
| Hypertrophy | `HYP-FB-3` | `HYP-UL-4` | Use `HYP-UL-4` plus optional specialization later | `HYP-PPL-6` or `HYP-ARNOLD-6` |
| Strength | `STR-FB-3` | `STR-UL-4` | `STR-SBD-5` | Prefer `STR-SBD-5`; a sixth day adds little lift-practice value |
| Both | Use `HYB-UL-4` across a rolling schedule | `HYB-UL-4` | `HYB-PPLUL-5` | `HYB-PPL-6` |

Do not label six days as more advanced because it builds more muscle by itself.
The label reflects schedule complexity, recovery demand, and the cost of missed
sessions.

## Quality checks before shipping presets

- Expand shared-day references and verify every generated workout independently.
- Confirm every exercise name exists in `ExerciseLibrary.allExercises`.
- Count direct and indirect weekly sets by muscle group. Treat a compound set as
  one set for its prime mover and about half a set for a major secondary mover
  when auditing the catalog, matching the fractional method favored in the 2025
  dose-response analysis.[^dose]
- Flag sessions above about 25 working sets for a manual fatigue and duration
  review. This is a product guardrail, not a proven biological cutoff.
- Keep main strength lifts first and avoid consecutive heavy exposures for the
  same lift.
- Set all initial weights to `0.0`; never guess a user's strength.
- Show RIR, rest, progression, warm-up, and safety guidance before plan creation.
- Let users preview and remove days or exercises before saving.
- Version the catalog and preserve user edits.
- Test plan creation, duplicate-name handling, offline persistence, sync, export,
  and import.

## Evidence boundaries

The evidence base contains short studies, mixed training histories, varied
exercise selections, and imprecise estimates of effort. Group averages cannot
identify one user's recoverable volume. Research supports the principles used
here more strongly than any exact set count in a single workout.

The programs omit Olympic lifts, maximal singles, accommodating resistance,
velocity tracking, and peaking blocks. Those need different exercise data and a
more specialized audience. Nutrition and sleep affect results but sit outside
the workout-preset data model.

## Sources

[^acsm]: Currier BS, et al. (2026). [Resistance Training Prescription for Muscle
    Function, Hypertrophy, and Physical Performance in Healthy Adults: An
    Overview of Reviews](https://pubmed.ncbi.nlm.nih.gov/41843416/). American
    College of Sports Medicine position stand. Synthesized 137 systematic reviews
    and more than 30,000 participants.

[^split]: Ramos-Campo DJ, et al. (2024). [Efficacy of Split Versus Full-Body
    Resistance Training on Strength and Muscle Growth](https://pubmed.ncbi.nlm.nih.gov/38595233/).
    Systematic review and meta-analysis of 14 studies and 392 participants.

[^dose]: Pelland JC, et al. (2025). [The Resistance Training Dose Response:
    Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on
    Muscle Hypertrophy and Strength Gains](https://doi.org/10.1007/s40279-025-02344-w).
    The analysis found positive dose-response relationships with diminishing
    returns and favored counting indirect sets as half-sets.

[^load]: Refalo MC, et al. (2021). [Influence of Resistance Training Load on
    Measures of Skeletal Muscle Hypertrophy and Improvements in Maximal Strength
    and Neuromuscular Task Performance](https://pubmed.ncbi.nlm.nih.gov/33874848/).
    Systematic review and meta-analysis of 45 studies.

[^rir]: Robinson ZP, et al. (2024). [Exploring the Dose-Response Relationship
    Between Estimated Resistance Training Proximity to Failure, Strength Gain,
    and Muscle Hypertrophy](https://pubmed.ncbi.nlm.nih.gov/38970765/).

[^failure]: Refalo MC, et al. (2023). [Influence of Resistance Training
    Proximity-to-Failure on Skeletal Muscle Hypertrophy](https://pubmed.ncbi.nlm.nih.gov/36334240/).
    Systematic review and meta-analysis.

[^rest]: Singer A, et al. (2024). [Give It a Rest: The Effect of Inter-set Rest
    Interval Duration on Muscle Hypertrophy](https://pubmed.ncbi.nlm.nih.gov/39205815/).
    Systematic review with Bayesian meta-analysis.

[^order]: Nunes JP, et al. (2021). [What Influence Does Resistance Exercise
    Order Have on Muscular Strength Gains and Muscle Hypertrophy?](https://pubmed.ncbi.nlm.nih.gov/32077380/).
    Systematic review and meta-analysis.

[^rom]: Pallarés JG, et al. (2021). [Effects of Range of Motion on Resistance
    Training Adaptations](https://pubmed.ncbi.nlm.nih.gov/34170576/). Systematic
    review and meta-analysis.
