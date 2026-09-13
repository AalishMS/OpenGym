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
| `STR-UL-4` | Strength | Upper/lower | 4 | Intermediate general strength | 65-85 min |
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
- `1 x 1 + 1 x 3 + 1 x 5` means three working sets with different loads. The
  first set is one controlled heavy rep, followed by lighter sets of three and
  five. The user must reduce the load between sets; this is not one weight taken
  through three rep targets.
- `Seed` is the exact rep value OpenGym can place in each `SetTemplate`. The app
  cannot store a rep range today. `1 / 3 / 5` maps to three set targets in that
  order.
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

For a `1 / 3 / 5` main lift, the single is practice with heavy weight rather
than a one-repetition maximum test. Start near RIR 3 on the single, remove
weight for the triple, then remove weight again for the set of five. Approximate
starting zones are 88-92% 1RM for the single, 80-87% for the triple, and 75-82%
for the set of five. RIR and stable technique take priority over percentages.
Increase the three loads only after all three sets meet their targets. Beginners
should use straight sets until they can choose loads and estimate RIR with
consistent technique.

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


## Production prescriptions

The canonical program IDs, schedules, exercises, set targets, rest periods,
RIR values, and user-facing guidance are stored in
[`lib/data/workout_presets.dart`](../lib/data/workout_presets.dart). Keep changes
to individual presets in that production data file so the catalog has one source
of truth.

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
- Treat every `1 / 3 / 5` single as submaximal. Preset copy must call it a heavy
  practice rep and must not label it a max attempt.
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
