# AI Coach

Status: **design settled. The pure-Dart parts are being built; the proxy and UI
don't exist yet.**

The Coach lets a signed-in user create and restructure workout plans by chatting.
It proposes changes; the user reviews a diff and applies or discards it. Nothing
is written to Hive until the user applies.

## Settled direction

- An in-app Coach, with no MCP server.
- Gemini through a Google AI Studio API key: Flash-Lite first, and Flash only
  if Flash-Lite's plans aren't good enough on the eval set.
- The key lives in a Supabase Edge Function proxy, never in the APK. The proxy
  authenticates the user, enforces a quota, holds the system prompt and the
  response schema, and forwards the request to the model. It does not run
  tools or touch workout data.
- Analysis happens in Dart on the phone. The model sees only a compact summary
  of the active split.
- Each turn produces one proposal. Gemini's response schema enforces its shape,
  Dart validates it again, and a failed proposal gets at most one retry.

## Flow of one turn

```text
user message
  -> CoachContextBuilder (Dart)       active split's plans + training summary + library names
  -> CoachClient -> Edge Function     auth, contract version, quota, prompt + schema, model call
  -> model returns {reply, proposal}  structured JSON, one call
  -> ProposalValidator (Dart)
       ok      -> ProposalDiff -> proposal card -> review screen -> Apply / Discard
       errors  -> one retry with the exact errors -> validate again
       errors  -> show the reply, explain the plan could not be used
```

A turn costs one model call, or two when the first proposal fails validation.

### Context is attached, not fetched

The model has no tools. The client attaches the training summary and the
exercise library to every request, and the model always answers in one fixed
`{reply, proposal}` JSON shape:

- Together the summary and library come to a few thousand tokens. Fetching them
  through tool calls would add a round trip, and so another request against the
  quota every user shares.
- A small model that has to decide *whether* to call a tool sometimes skips it
  and makes up data instead. Data that is always present can't be skipped.
- A response schema is more reliable on small models than a function call the
  model may or may not choose to make.

## Context sent to the model

`CoachContextBuilder` builds the context from the active split only. It reuses
`StatisticsAnalyticsService.eligibleSessions` and `estimatedOneRepMax`, plus
`ExerciseLibrary`. Alongside the JSON it returns a `CoachSnapshot`: the plan
list behind the refs, each plan's `updatedAt`, the split names, and the custom
exercises. The validator and the applier both work against that snapshot.

```json
{
  "today": "2026-10-09",
  "weightUnit": "kg",
  "split": { "name": "Push Pull Legs", "splitCount": 2, "maxSplits": 5 },
  "plans": [
    {
      "ref": "p1",
      "name": "Push",
      "exercises": [
        {
          "name": "Bench Press",
          "sets": [{ "reps": 8, "kg": 60 }, { "reps": 8, "kg": 60 }, { "reps": 6, "kg": 65 }],
          "note": "Pause the first rep"
        }
      ]
    }
  ],
  "training": {
    "sessionsLast4Weeks": 11,
    "sessionsPerWeek": 2.8,
    "firstWorkout": "2026-03-02",
    "lastWorkout": "2026-10-07"
  },
  "exercises": [
    {
      "name": "Squat",
      "lastDate": "2026-10-06",
      "lastTopSet": { "reps": 5, "kg": 100 },
      "sessions4w": 4,
      "metric": "e1rm",
      "bestRecent": 116.7,
      "bestEarlier": 116.7,
      "trend": "stalled"
    }
  ],
  "library": ["Ab Wheel Rollout", "Arnold Press", "..."],
  "customExercises": ["Landmine Press"]
}
```

- **Refs, not IDs.** Plans are labelled `p1` to `pN` in position order. Small
  models garble UUIDs, so the client maps refs back to plan IDs.
- **Weights are always kilograms.** The app stores and enters every weight in
  kg. The weight-unit setting only changes how History and Stats display them.
  The model reads and writes kg and never converts.
- **Missing targets.** An exercise that has fewer `setTargets` than `sets` is
  padded the way the plan editor shows it: 8 reps at 0 kg. A weight of 0 means
  "no weight target", which is how bundled presets store targets.
- **Trend.** Each exercise is measured over a 28-day window split into two
  halves. "Recent" is the last 14 days and "earlier" is the 14 days before
  that. The metric is the best estimated 1RM per session, or the best reps when
  the exercise has no 1RM (bodyweight work, or more than 12 reps).
  `bestRecent` and `bestEarlier` are the best values in each half. The trend is
  set as follows:
  - `not_recent`: the exercise wasn't trained in the window.
  - `new`: the first time it was ever trained falls inside the window.
  - `not_enough_data`: fewer than 3 sessions in the window, or one half has
    none.
  - `improving`: `bestRecent` is more than 2.5% above `bestEarlier`.
  - `declining`: `bestRecent` is more than 2.5% below `bestEarlier`.
  - `stalled`: anything else.
- **Caps.** The summary includes the 25 most recently trained exercises and
  every plan in the split. It counts only completed, non-deleted sessions.
- **Never sent:** session and set notes (free text the user wrote for
  themselves), other splits' contents, the user's email or ID, and individual
  session dates beyond those listed above. Plan notes *are* sent, because they
  are part of the plan the Coach may rewrite.
- **`customExercises`** lists names used in this split's plans or sessions that
  aren't in the library. The Coach can keep these in existing plans.

## Response contract (model output)

```json
{ "reply": "Short explanation shown in the chat.", "proposal": null }
```

or

```json
{
  "reply": "I split your week into upper and lower days...",
  "proposal": {
    "target": "active_split",
    "newSplitName": null,
    "plans": [
      {
        "ref": "p2",
        "name": "Push",
        "exercises": [
          {
            "name": "Incline Dumbbell Press",
            "sets": [{ "reps": 10, "kg": 22.5 }, { "reps": 10, "kg": 22.5 }],
            "note": null,
            "custom": false
          }
        ]
      },
      { "ref": null, "name": "Arms", "exercises": ["..."] }
    ],
    "removePlanRefs": ["p3"]
  }
}
```

- `proposal: null` is a valid answer, for questions such as "why has my squat
  stalled?" that don't need a plan change.
- `target` is `active_split`, or `new_split` together with a `newSplitName`.
- Each entry in `plans` is a **whole plan**. A `ref` means "replace this plan's
  name and exercises", and `ref: null` means "add this plan". Plans the
  proposal doesn't mention stay unchanged. In a new split every plan has
  `ref: null`.
- No field can describe a session, a date, a week, or a logged set. The schema
  can't express a `WorkoutSession`, so the Coach can't create one, and plan
  targets stay display-only.
- `custom: true` marks a name that isn't in the library. It's only valid when
  the user asked for it. The review screen labels custom exercises.

This shape is **contract version 1**. The proxy hands Gemini the matching
response schema, and the Dart validator checks the result again whatever the
model returned.

## Validation

`ProposalValidator` is pure Dart. It takes the model's output string and a
`CoachSnapshot`. It returns either a `CoachReply`, which holds the reply text
and an optional `ValidatedProposal`, or a list of errors written for the model
to fix. It never throws on bad model output.

| Check | Rule |
| --- | --- |
| Shape | Required keys and types are present. Unknown keys are ignored |
| Exercise name | Matches the library or `customExercises`, ignoring case and extra spaces, and is normalised to that casing. Otherwise it needs `custom: true` and 1–40 characters |
| Sets | 1–10 per exercise. Reps 1–100. Weight 0–500 kg, rounded to 0.25 |
| Exercises | 1–15 per plan, with no duplicate names in a plan |
| Plans | A new split has 1–7 plans. The active split keeps 1–10 plans after applying |
| Plan name | 1–40 characters, unique in the resulting split ignoring case |
| Refs | Each `ref` exists in the snapshot and appears once. Each `removePlanRefs` entry exists and isn't also edited |
| New split | Follows the `SplitProvider.nameError` rules, and fails when the user already has five splits |
| Notes | At most 200 characters. An empty note becomes null |
| No-op | A proposal that changes nothing is an error. The model should use `proposal: null` instead |

Errors name their path so that one retry can fix them, for example:
`proposal.plans[1].exercises[2].name: "Incline DB Press" is not in the library. Closest: "Incline Dumbbell Press".`
Closest matches come from token overlap, after expanding common gym
abbreviations such as DB, BB, and OHP.

The retry repeats the request with the previous output and the error list, and
asks for corrected JSON. If the second answer also fails, the chat shows the
reply text and says the plan couldn't be used.

## Proposal diff

`ProposalDiff.compute(validatedProposal)` returns one `PlanDiff` per affected
plan, marked `added`, `removed`, `changed`, or `unchanged`. For a changed plan
it reports a rename and, per exercise, whether it was `added`, `removed`,
`changed` (with old and new sets), or `unchanged`. It also flags exercises that
moved, and notes that changed. Exercises are matched by name, ignoring case.
The review screen renders the diff, and the same object supplies the summary on
the chat's proposal card ("2 plans changed, 1 added").

## Applying

`CoachApplier` writes a validated proposal inside
`SyncService.runExclusiveLocalMutation`. It uses the same compensating rollback
as `WorkoutPresetInstaller`.

- **Stale check first.** The snapshot records the active split and the
  `updatedAt` of every plan in it. If any of those changed between the request
  and the apply, through the user's own edit or a sync pull, the apply is
  refused and nothing is written. The proposal card then says "Plans changed.
  Ask again with the latest?" with an `Ask again` button. That button re-sends
  the same message with a fresh context as a new turn, and the old proposal is
  marked out of date. Last-write-wins never silently overwrites the newer
  plans.
- **Edited plans** keep their `id`, `position`, `planColor`, `splitId`, and
  `userId`. Only `name` and `exercises` change.
- **New plans** get:
  - a UUID
  - the target `splitId` and the user's ID
  - the next `position` after the split's highest
  - the first `kPlanColors` slot the split isn't already using, cycling once
    every slot is taken
- **Removed plans** go through `HiveService.softDeletePlan`, so they become
  tombstones.
- **A new split** follows `WorkoutPresetInstaller.install`. The applier
  creates the split, writes its plans with positions 0 to n−1, and makes the
  split active. The "reuse an untouched default split" rule and the 24-character
  name limit carry over.
- Every write sets `updatedAt` and `dirty`. Afterwards the providers reload, and
  `SyncService.instance.scheduleSync()` runs once.

`ExerciseTemplate.sets` equals the length of the proposal's `sets` list, and
`setTargets` holds those sets. `note` is the plan guidance that the workout
screen copies into exercise notes.

## Edge Function proxy

The proxy is `supabase/functions/coach/index.ts`, deployed with JWT
verification on.

### Request

```http
POST {SUPABASE_URL}/functions/v1/coach
Authorization: Bearer <user access token>
```

```json
{
  "contractVersion": 1,
  "context": { "...": "the context JSON above" },
  "messages": [
    { "role": "user", "content": "Build me a 4-day upper/lower" },
    { "role": "assistant", "content": "{\"reply\": \"...\", \"proposal\": null}" }
  ],
  "retry": { "previousOutput": "...", "errors": ["..."] }
}
```

`supabase_flutter`'s `functions.invoke` attaches the token. `retry` is present
only on the second attempt.

### Contract versioning

The app sends the contract version it was built for. The proxy keeps a prompt
and a response schema for each version it supports:

- **Supported:** the proxy answers in that version's shape and echoes
  `contractVersion` back. The client rejects a response stamped with any other
  version.
- **Older than the oldest supported version:** 426 `update_required`, and the
  app shows "Update OpenGym to keep using the Coach," linking to Settings →
  Check for updates.
- **Newer than the proxy knows:** 503 `unavailable`. This only happens if an
  app ships before its function is deployed.

Release rule: deploy the function that supports version N **before** shipping
an app that sends N. Keep N−1 in the function until most installs have updated.

### What the proxy does

1. Checks `COACH_ENABLED`, verifies the JWT, and reads the user ID.
2. Checks the contract version.
3. Rejects bodies over 32 KB, or more than 12 messages.
4. Charges the quota (see Quota). When the quota is used up, it returns 429
   without calling the model.
5. Builds the model request: the server-side system prompt for the version,
   then the context, then the messages. The same version's JSON schema is set
   as Gemini's response schema.
6. Calls `COACH_BASE_URL` with `COACH_MODEL`. On a 429 or 5xx it tries
   `COACH_FALLBACK_MODEL` once.
7. Returns the model's JSON string unparsed. Validation is the client's job.
8. Logs status, model, token counts, and latency. It **never logs prompt or
   response content**.

The system prompt and schema live on the server for two reasons: they can be
tuned without an app release, and the endpoint can't serve as a
general-purpose chat relay. The client sends data and conversation, not
instructions.

### Configuration

These are function secrets and environment values. Changing them needs no app
release:

| Name | Value |
| --- | --- |
| `COACH_API_KEY` | The AI Studio key (secret) |
| `COACH_BASE_URL` | The Gemini endpoint (see the smoke test under Risks) |
| `COACH_MODEL` | A Flash-Lite model ID |
| `COACH_FALLBACK_MODEL` | A Flash model ID, or empty |
| `COACH_USER_DAILY_LIMIT` | `20` |
| `COACH_GLOBAL_DAILY_LIMIT` | A little below the project's real daily request quota in AI Studio, about 90% |
| `COACH_ENABLED` | `true`. Set it to `false` to turn the Coach off for everyone |

Switching models or providers only means changing these values.

### Response

```json
{
  "contractVersion": 1,
  "output": "{\"reply\": \"...\", \"proposal\": {...}}",
  "model": "gemini-…-flash-lite",
  "quota": { "used": 4, "limit": 20, "resetsAt": "2026-10-10T07:00:00Z" }
}
```

| Status | `error` | Client copy |
| --- | --- | --- |
| 401 | `unauthenticated` | Sign in again to use the Coach. |
| 413 / 422 | `bad_request` | Something went wrong. Try a shorter message. |
| 426 | `update_required` | Update OpenGym to keep using the Coach. |
| 429 | `user_quota` | You've used today's Coach requests. They reset tomorrow. |
| 503 | `busy` | The Coach is busy right now. Try again later. (The global cap or an upstream 429) |
| 503 | `unavailable` | The Coach is unavailable right now. |
| 502 | `upstream` | The Coach couldn't answer. Try again. |

### Quota

One migration adds:

```sql
create table public.coach_usage (
  user_id uuid not null references auth.users on delete cascade,
  day date not null,
  calls int not null default 0,
  input_tokens int not null default 0,
  output_tokens int not null default 0,
  primary key (user_id, day)
);
alter table public.coach_usage enable row level security;
-- No policies: only the function's service role reads or writes it.
```

A `security definer` function, `coach_charge(user_id, user_limit,
global_limit)`, upserts today's row and increments it atomically. "Today" is the
day in `America/Los_Angeles`, which matches Google's quota reset. The function
returns whether the call is allowed and the new count, and the global check sums
today's `calls`. Every model call counts, retries included, because every call
spends the shared project quota. Token counts are recorded after each call so
cost can be watched once billing is on.

## UI

- **Entry point:** a Coach button in the Home header, next to the split control.
  It opens `CoachScreen` as a pushed route. The tab bar doesn't change.
- **Availability:** in an offline-only build, or while signed out, the button is
  hidden. Without a connection, `CoachScreen` opens with a notice: "The Coach
  needs a connection. Your plans still work offline." Plan editing never waits
  on the Coach.
- **First use:** a disclosure sheet covers:
  - what is sent: this split's plans and a summary of recent training, not
    notes
  - that Google processes it
  - how free-tier data may be used
  - that the Coach is not medical advice

  It has an "I'm 18 or older" checkbox (see Risks), and `Continue` stays
  disabled until it is ticked. The other action is `Not now`. Acceptance is
  stored in SharedPreferences for each user and disclosure version, so changing
  the text asks again.
- **Chat:** an empty state offers three suggestions: "Build a 4-day
  upper/lower", "My squat has stalled", and "Swap exercises for a sore
  shoulder". Below it are the message list and the input. While a request is
  out, the send button shows progress. Once fewer than five requests are left,
  the remaining count appears quietly.
- **Proposal card:** a reply that carries a proposal shows a card under it, such
  as "Push Pull Legs · 2 plans changed, 1 added", with a `Review` button. A
  stale proposal shows "Plans changed. Ask again with the latest?" instead.
- **Review screen:** one card per affected plan:
  - added exercises in the accent ink
  - removed exercises struck through in the error colour
  - changed sets shown as old → new
  - a label on custom exercises

  The bottom bar has `Discard` and `Apply`. Apply shows progress, writes the
  changes, returns to Home, and shows "Plans updated".
- **Conversation memory:** the conversation is held in a `CoachProvider` for the
  whole app session, so leaving and reopening the Coach keeps it. It isn't
  saved to Hive, synced, or included in backups. It clears when the account
  changes, and a new conversation starts when the active split changes,
  because refs and proposals belong to one split.

All of this uses the theme helpers, radius tokens, and sentence-case copy from
`AGENTS.md`.

## Health guidance

The server-side prompt tells the model to:

- not diagnose or present anything as medical advice
- respond to pain or injury by avoiding painful movements, offering
  substitutions and lighter loading, and suggesting a professional for sharp,
  persistent, or worsening pain
- keep progression conservative: small load steps, and a deload when a lift
  stalls

The disclosure sheet states that the Coach is not medical advice.

## Code layout

| File | Role |
| --- | --- |
| `lib/models/coach_proposal.dart` | Plain (non-Hive) proposal, snapshot, and reply types |
| `lib/services/coach/coach_context_builder.dart` | Training summary, context JSON, and snapshot |
| `lib/services/coach/proposal_validator.dart` | Parsing, validation, and error messages |
| `lib/services/coach/proposal_diff.dart` | Diff between the snapshot and the proposal |
| `lib/services/coach/coach_applier.dart` | Exclusive write with rollback |
| `lib/services/coach/coach_client.dart` | Proxy call, contract version, and error mapping |
| `lib/providers/coach_provider.dart` | App-session conversation and the turn loop |
| `lib/screens/coach_screen.dart`, `coach_review_screen.dart` | Chat and review |
| `lib/widgets/coach/` | Message bubbles, proposal card, diff rows |
| `supabase/functions/coach/` | The Edge Function |
| `supabase/migrations/` | `coach_usage` and `coach_charge` |
| `tool/coach_eval/` | Eval cases and runner |

There are no Hive model changes, so there's no adapter regeneration and no
backup format change.

## Build order

1. **Pure Dart, no model:** the context builder, validator, and diff, each with
   unit tests. Then the applier, tested against real boxes with
   `hive_test_harness`, covering the stale check, rollback, and the new-split
   path.
2. **Proxy:** the migration, the Edge Function, the response-schema smoke test,
   and a local run with the Supabase CLI.
3. **UI:** `CoachProvider`, the chat, the proposal card, and the review screen,
   with widget tests that use a fake `CoachClient`.
4. **Eval:** 15–20 realistic requests with fixture histories, run through the
   real proxy against Flash-Lite and Flash. Each model is scored on the
   validator pass rate first time, the pass rate after a retry, and a manual
   quality grade.

## Risks and terms

Checked against Google's pages on 2026-10-09: the
[Gemini API terms](https://ai.google.dev/gemini-api/terms),
[pricing](https://ai.google.dev/gemini-api/docs/pricing),
[rate limits](https://ai.google.dev/gemini-api/docs/rate-limits),
[billing](https://ai.google.dev/gemini-api/docs/billing), and
[OpenAI compatibility](https://ai.google.dev/gemini-api/docs/openai). Read the
exact wording on those pages before relying on any of it.

- **Free-tier data use.** On unpaid services Google uses prompts and responses
  to improve its products, and human reviewers may read them. The terms also
  say not to submit personal information to unpaid services, and training
  history is arguably personal. So the free tier is for development and a small
  closed test with informed testers only. A public launch needs the paid tier,
  where prompts aren't used for improvement and are logged only for abuse
  detection.
- **EEA, UK, and Switzerland.** "You may use only Paid Services when making API
  Clients available to users in the European Economic Area, Switzerland, or the
  United Kingdom." The app has no region signal, so the rule is simple: **no
  public release ships the Coach before billing is on.**
- **Age.** The terms forbid API clients that are "directed towards or … likely
  to be accessed by individuals under the age of 18". A gym app may well have
  teenage users, so the disclosure asks the user to confirm they are 18 or
  older. Without that confirmation the Coach stays unavailable. Whether a
  self-declared age gate is enough is a judgement call; it's the minimum.
- **Free-tier limits.** They apply per project, not per key, and reset at
  midnight Pacific time. The rate-limits page no longer publishes the numbers,
  so read them in AI Studio and set `COACH_GLOBAL_DAILY_LIMIT` a little below
  the daily request quota.
- **Cost on the paid tier**, at about 5k input and 1.5k output tokens per call:
  roughly $0.001 per call on 2.5 Flash-Lite ($0.10 / $0.40 per million tokens),
  $0.005 on 3.5 Flash-Lite, and $0.02 on 3.5 Flash. Prices vary widely between
  generations, so choose the model with the eval set, not by its name.
- **Spend control.** AI Studio's monthly project spend cap is labelled
  experimental. Billing data can lag by about 10 minutes, so the cap can
  overshoot. Prepaid credits are the hard stop: at a zero balance the keys stop
  working. Either way, the proxy's global daily cap is the first line of
  defence.
- **Cloud credit.** Google AI Pro includes $10 a month of Google Cloud credit
  through the Google Developer Program, and Google says it can be spent on the
  Gemini API. The billing page suggests eligible credits only apply after a
  Prepay purchase ($5 minimum). Confirm this in the console.
- **Schema enforcement.** The OpenAI-compatible endpoint is in beta and silently
  ignores parameters it doesn't support. If it dropped `response_format`, the
  model would answer in free text with no error. The first proxy milestone is
  therefore a smoke test that the schema is actually enforced. If it isn't, the
  proxy calls the native Gemini endpoint with `responseSchema` instead. The
  client contract doesn't change, so this stays a server-only decision. Dart
  validation runs in both cases.
- **Account and network.** The Coach needs a session and a connection. Both are
  checked before a request, and failures map to the copy in the error table.
  Nothing else in the app depends on the Coach.
