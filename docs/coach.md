# AI Coach

Status: **design settled. The pure-Dart parts, the proxy (deployed 2026-10-09,
`coach` v1 with `coach_usage` migrated), the UI, and the eval (2026-10-10) are
built. Model decision: keep Flash-Lite. A v1 prompt revision is proposed in
`tool/coach_eval/findings.md` and not yet deployed. Next: redeploy v1 with that
prompt, then the closed-test checklist under Eval.**

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

  Known gap, found by the eval: above 12 reps, a weight increase doesn't show.
  So a 15-rep Face Pull that gains 1 kg a week reads as `stalled`.
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
  - the next `position` after the split's highest, or `0` in an empty split.
    If any plan in the split has no position (legacy order), new plans get
    none either, as in the plan editor, so they sort after the positioned ones
  - the first `kPlanColors` slot the split isn't already using, cycling once
    every slot is taken
- **Removed plans** become tombstones with the same fields
  `HiveService.softDeletePlan` sets (`deletedAt`, `updatedAt`, `dirty`). They
  are written as copies, so rollback can put the originals back.
- **A new split** follows `WorkoutPresetInstaller.install`. The applier
  creates the split, writes its plans with positions 0 to n−1, and makes the
  split active. The "reuse an untouched default split" rule and the 24-character
  name limit carry over. Both use `SplitInstallTarget`, which the installer
  shares.
- Every write sets `updatedAt` and `dirty`. Afterwards
  `SyncService.instance.scheduleSync()` runs once. A stale proposal returns
  `CoachApplyStale` instead of throwing; other failures throw after rollback.
- The UI applies through `SplitProvider.applyCoachProposal`, which reloads the
  splits. That also reloads `WorkoutPlanProvider`, which listens to it.

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

### Implementation notes

Decisions the build added to the design above:

- **Layout.** `index.ts` only wires Supabase and the environment. The pipeline
  is `handler.ts`, with every dependency injected, so the order of checks is
  tested without Supabase or a model. Each contract version is one module,
  `contracts/v1.ts` (prompt and schema), registered in `contracts/mod.ts`, so
  version 2 is additive. Tests live in `supabase/functions/tests/`.
- **Order.** The version lives in the body, so the 32 KB cap is checked first
  and nothing larger is parsed. Then `contractVersion` is read alone and
  checked, and only then the rest of the shape. An old app whose body changed
  shape still gets 426, not 422. The last message must be from the user.
- **Where the context goes.** The prompt and the context are two parts of the
  system instruction, the context labelled as data. That keeps the turns
  strictly the user's conversation, which Gemini needs to alternate. The retry
  adds the previous output as a model turn and the errors as a user turn.
- **Endpoints.** The proxy speaks both styles, picked by `COACH_BASE_URL`: a
  URL ending in `/openai` uses `chat/completions` with a `json_schema`
  `response_format`; anything else uses the native
  `models/{model}:generateContent` with `responseJsonSchema`. The example env
  defaults to native, because there a schema is enforced or the call fails
  with a 400; it can't be dropped silently.
- **Smoke test, 2026-10-09:** both endpoints enforce the schema with
  `gemini-3.5-flash-lite`. The probe, which never mentions JSON, came back as
  `{"reply": "Hello!", "proposal": null}` on each, and the contract request
  parsed and matched v1 on each (about 1.5k tokens in, 200 out, 1.3 s).
  `gemini-3.5-flash` passed on native too, but spent about 1.3k output tokens
  on the same request because it thinks, at about 5.5 s. The OpenAI-compatible
  endpoint forwards `response_format` rather than dropping it: it returned the
  same 400 as native for an unsupported schema. Native stays the default.
- **No `maxItems` in the schema.** With `maxItems` on the nested `sets` and
  `exercises` arrays, Gemini answers a bare 400 `INVALID_ARGUMENT` on both
  endpoints. Every other bound (`minItems`, lengths, `minimum`/`maximum`,
  `enum`) is accepted. The prompt states the maximums and the Dart validator
  enforces them.
- **Models.** `gemini-2.5-flash-lite` and `gemini-2.5-flash` answer 404 "no
  longer available to new users", so the defaults are `gemini-3.5-flash-lite`
  with `gemini-3.5-flash` as the fallback.
- **Fallback** also covers a network error or the 40-second per-attempt
  timeout, which behave like a 5xx. After the fallback, the last attempt
  decides the status: 429 is `busy`, anything else `upstream`. An upstream 4xx
  other than 429 (a bad key, a rejected schema) never falls back.
- **Charging.** One charge per request, before the model call. The fallback
  call isn't charged again: it only runs after the primary was refused or
  failed. Failed calls aren't refunded. If the quota store itself fails, the
  answer is 503 `unavailable`, and the model isn't called.
- **Tokens** are recorded by a second service-role function,
  `coach_record_tokens(user_id, day, input_tokens, output_tokens)`, after a
  successful call. It takes the day `coach_charge` returned, so a call across
  Pacific midnight lands on the day it was charged. Thinking tokens count as
  output. A failure to record is logged and never fails the turn.
- **`coach_charge`** returns `allowed`, `used`, `blocked_by` (`user`,
  `global`, or null), `day`, and `resets_at` (the next Pacific midnight, which
  becomes `quota.resetsAt`). A refused call isn't counted. A per-day advisory
  lock serialises charges, so two requests can't both take the last global
  slot. Both functions are executable only by `service_role`.
- **Logs** are one JSON line per request: status, error code, contract
  version, each attempt's model and status, token counts, and latency. Not the
  user ID, not upstream error bodies (they can quote the request), and never
  content.
- **Defaults.** `COACH_USER_DAILY_LIMIT` falls back to 20 and
  `COACH_GLOBAL_DAILY_LIMIT` to a deliberately low 200 when unset or invalid.

### Local development

The function needs the Supabase CLI and Docker for a local stack. Copy
`supabase/functions/.env.example` to `supabase/functions/.env` or
`supabase/.env` (both git-ignored) and add the key.

`supabase/migrations/` holds the whole remote history: the four split
migrations were applied through the dashboard and pulled in with
`supabase migration fetch --linked`, so `db push` only sends new files.

```bash
supabase start                      # local Postgres, auth, and edge runtime
supabase db reset                   # applies supabase/migrations locally
supabase functions serve coach --env-file supabase/functions/.env
```

From `supabase/functions`, the unit tests, formatting, and lint run with Deno
alone (`npx deno@2.9.6` works without installing it):

```bash
deno test --allow-read tests/
deno fmt --check . && deno lint .
```

The schema smoke test calls the model API directly with the `.env` values. It
spends two requests per endpoint, and `--both` tries the native and the
OpenAI-compatible endpoints:

```bash
deno run --allow-net --allow-read --allow-env   --env-file=supabase/functions/.env supabase/functions/tests/coach_smoke.ts --both
```

`probe` sends a prompt that never mentions JSON, so only an enforced schema
makes it pass; `contract` sends the real v1 prompt and a fixture context.

## UI

- **Entry point:** a Coach button in the Home header, next to the split control.
  The app shell shows `CoachScreen` over Home inside the Home tab, so the bottom
  bar (or the desktop rail) stays on screen. The back arrow, system back, or a
  second tap on Home closes it. Switching to another tab keeps it open under
  Home.
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
- **Status strip:** under the title, on the app bar's ground, "Currently on
  gemini-3.5-flash-lite" names the model that answered last, and "14 of 20 left
  today" sits over a meter with one segment per request. Both are unknown until
  a user's first message, and the strip says so.
- **Chat:** the empty state says what the Coach reads ("your 4 plans in Push
  Pull Legs and your last four weeks of training") and lists three
  suggestions as plain rows between hairlines, each with a hint: "Build a 4-day
  upper/lower", "My squat has stalled", and "Swap exercises for a sore
  shoulder". The conversation reads like a log, not a messenger: each question
  is a line marked with the accent, and the answer follows under a "Coach"
  label. While a request is out, the send button and a "Reading your plans"
  line show progress.
- **Daily limit:** once no requests are left, the input, suggestions, `Try
  again`, and `Ask again` are disabled, and the input reads "Daily limit
  reached. Back at 1:45 PM" (the reset in local time). `Review` and `Apply`
  still work, because they don't call the model.
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

### UI implementation notes

Decisions the build added to the UI above:

- **Connection check.** There's no connectivity package. On open,
  `CoachScreen` resolves the Supabase host (`probeCoachConnection`, skipped on
  the web) and shows the notice if that fails. A request that fails with no
  connection raises the same notice, and the next answer clears it. The input
  stays usable either way.
- **Status decides the error.** `SupabaseCoachClient` maps by HTTP status, and
  reads `error` only to split 503 into `busy` and `unavailable`. The Supabase
  gateway rejects an expired JWT with its own 401 body, which has no `error`
  field. Any status the table doesn't name shows the `unavailable` copy. A 200
  stamped with another `contractVersion`, without an `output` string, or not
  JSON at all, shows the `upstream` copy. The client gives up after 100 seconds,
  longer than the proxy's two 40-second attempts, and that also shows the
  `upstream` copy.
- **History.** Each request sends up to five earlier turns as user/assistant
  pairs, plus the new message, so it stays under the proxy's 12. Failed turns
  are left out, so the roles keep alternating. The assistant side is the model
  output re-encoded as compact JSON: Flash-Lite answers with indented JSON, which
  is about three times larger (8.3 KB against 3 KB for one proposal on
  2026-10-10), and the history shares the 32 KB cap with the context. A turn whose plan failed twice is sent as
  `{"reply": ..., "proposal": null}`, so the model doesn't build on a plan the
  user never saw. If the body would exceed 30 KB, the oldest turns are dropped.
- **Failure lines.** A failed request shows its copy in the chat. `busy`,
  `unavailable`, `upstream`, and no connection add `Try again`, which re-sends
  the same message. A 426 adds `Check for updates`, which runs the Settings
  check where the user is rather than switching tabs.
- **Stale checks** run when the chat opens, whenever `SplitProvider` reloads
  (including after a sync pull), and when `Review` is tapped, so an out-of-date
  card usually shows "Plans changed" before the user opens it. `Apply` still
  checks again.
- **Usage and model** come from the proxy's answers (`quota` and `model`, and
  the `quota` on a 429). `CoachProvider` keeps the last of each per user in
  SharedPreferences (`coach_status_{userId}`), so the strip is filled as soon as
  the Coach opens. A count whose `resetsAt` has passed reads as unused until the
  next answer says otherwise, and a timer unlocks an open chat at the reset.
  The model is the one that actually answered, so a fallback shows as such.
  There's no endpoint to ask for usage without spending a request, so a user
  who has never sent one sees no count.
- **A new-split proposal** makes the new split active when it's applied, so the
  conversation starts over, as it does for any split change.
- **Disclosure** acceptance is the SharedPreferences key
  `coach_disclosure_v{version}_{userId}`. `kCoachDisclosureVersion` lives in
  `lib/services/coach/coach_disclosure.dart`.
- **Tests.** In `test/coach_ui_test.dart`, Hive writes started inside a widget
  test's fake-async zone leave the plans box unable to close in `tearDownAll`.
  So the review test's applier defers, and the test runs the real
  `CoachApplier` inside `tester.runAsync`. The UI path through progress,
  outcome, navigation, and the snackbar is unchanged.

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
| `lib/services/coach/coach_request.dart` | The request body, free of Flutter so the eval can use it |
| `lib/services/coach/coach_client.dart` | Proxy call, contract version, and error mapping |
| `lib/providers/coach_provider.dart` | App-session conversation and the turn loop |
| `lib/screens/coach_screen.dart`, `coach_review_screen.dart` | Chat and review |
| `lib/services/coach/coach_disclosure.dart` | Per-user, per-version disclosure acceptance |
| `lib/services/coach/coach_status_store.dart` | Last reported usage and model, per user |
| `lib/widgets/coach/` | Home button, open flow, and `CoachHost` (the shell's hook), disclosure sheet, status strip, chat entries and proposal card, diff cards |
| `supabase/functions/coach/` | The Edge Function; `contracts/` holds one prompt and schema per version |
| `supabase/functions/tests/` | Deno unit tests and the schema smoke test |
| `supabase/migrations/` | `coach_usage`, `coach_charge`, and `coach_record_tokens` |
| `tool/coach_eval/` | Eval cases, runner, Deno model-call helper, report, grades, and results |

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
4. **Eval:** 15–20 realistic requests with fixture histories, run against
   Flash-Lite and Flash through the proxy's own request code (see Eval; the
   deployed proxy was skipped to spare the per-user quota and the secrets). Each model is scored on the
   validator pass rate first time, the pass rate after a retry, and a manual
   quality grade.

## Eval

`tool/coach_eval/` scores a model on 20 realistic requests (build step 4).

### Method

- **Cases** (`cases.dart`): each has a fixture split, plans, and a generated
  six-week log (`fixtures.dart`) whose trends come out as the case needs, for
  example a stalled bench. Each case also notes what a good answer looks like.
  The context comes from the real `CoachContextBuilder` with "today" fixed at
  2026-10-10. The cases cover a new program from nothing, a new split, edits,
  adding and removing plans, a stalled lift as a question and as a fix, pain
  in the shoulder and the knee, custom exercises, abbreviations, the
  five-split and ten-plan limits, two follow-ups that need the history, a
  vague request, logging, rescheduling and editing history (which the
  contract can't express), load progression, and an out-of-scope request.
- **Transport**: the model is called directly, not through the deployed proxy.
  The per-user limit and the function secrets stay untouched.
  `model_call.ts` (Deno) imports the proxy's own `bodyTooLarge`,
  `parseCoachRequest`, `buildConversation`, and `attempt`, together with
  `contracts/v1.ts`. So the request is what the proxy would send, minus auth,
  quota, and the fallback. `run.dart` builds the body with the app's
  `CoachRequest` (`lib/services/coach/coach_request.dart`, kept free of
  Flutter for this), fits the history the way `CoachProvider` does, validates
  with the real `ProposalValidator`, and retries once with `{previousOutput,
  errors}`. History is sent as compact JSON, as the app sends it.
- **Plain Dart.** The context builder, validator, and diff only need
  `package:hive`, so the eval runs with `dart run`. It isn't a `_test.dart`
  file and it reads the git-ignored `supabase/.env`, so `flutter test` and CI
  never run it.
- **Recorded per turn**: whether it passed first time and after the retry, the
  validator errors, latency around the model call, input and output tokens
  (thinking counts as output), the reply, and the diff rendered the way the
  review screen shows it. `--prompt FILE` tries a candidate system prompt
  without deploying it.
- **Results** are committed: each run's JSON and the generated
  `results/report.md` in `tool/coach_eval/results/`. The fixtures are
  synthetic, so nothing personal is in them, and the report is the evidence
  behind the model choice. The manual grades are in `grades.json`, and the
  findings are in `findings.md`.
- **Grading.** Each turn gets 0–2 on correctness, sensible loads, minimal
  change, health guidance (pain cases only), and reply clarity. The grades
  recorded on 2026-10-10 are Claude's provisional ones, for the owner to
  confirm.

Free-tier limits read in AI Studio on 2026-10-10: `gemini-3.5-flash-lite`
500 requests a day, `gemini-3.5-flash` **2** a day. Pass `--max-calls` for any
model with a small limit.

```bash
dart run tool/coach_eval/run.dart --dry-run                  # contexts only
dart run tool/coach_eval/run.dart --model gemini-3.5-flash-lite --repeat 2
dart run tool/coach_eval/run.dart --model gemini-3.5-flash \
  --cases sore_shoulder --max-calls 2                        # spend-capped
dart run tool/coach_eval/report.dart                         # re-render only
```

### Results, 2026-10-10

| Model · prompt | Pass first / after retry | Median call | Tokens in / out | Paid cost per call | Grade |
| --- | --- | --- | --- | --- | --- |
| Flash-Lite · v1 (deployed) | 35/40 · 39/40 | 2.8 s | 3228 / 734 | $0.0028 | 1.60 / 2 |
| Flash · v1 | 1/2 · 1/2 (one 503) | 4.9 s | 3216 / 660 | ≈$0.0049 | 1 turn graded |
| Flash-Lite · candidate 2 | 38/40 · 40/40 | 2.3 s | 3571 / 489 | $0.0023 | 1.82 / 2 |

Medians per call, from 40 turns (20 cases, each run twice). Costs use the
paid-tier prices: Flash-Lite $0.30 / $2.50 per million tokens. 3.5 Flash is
no longer on the pricing page, so its cost uses the current 3.6/3.8 Flash
price of $0.75 / $3.75.

- **Decision: keep `gemini-3.5-flash-lite` and revise the prompt.** Its
  failures were judgement, not schema, and they repeated across runs:
  - one set per exercise for a beginner
  - a target edited to stand in for a logged workout
  - a stalled lift made heavier
  - whole plans rewritten at the split and plan limits

  Prompt candidate 2 fixes most of them. Flash can't be compared fairly on
  the free tier (2 requests a day), costs more, is slower, and the 3.5
  generation is off the price list.
- **Validator fix (in the app).** At five splits, the retry error used to say
  "Use target "active_split" instead", and on the retry the model rewrote the
  whole active split. It now asks for `"proposal": null`, and 8 of 8 reruns
  answered that way.
- **Open issues:**
  - "Log today's bench at 82.5 kg" still edits the bench target in 1 of 2
    runs on candidate 2.
  - After a retry, the reply describes the correction rather than the plan.
    A `retryInstruction` change is proposed but untested.
  - High-rep work that progresses by weight reads as `stalled` (see Context
    sent to the model, Trend).
  - The free-tier fallback (`gemini-3.5-flash`, 2 a day) is nearly empty.

  The details and the exact prompt diff are in `tool/coach_eval/findings.md`.

### Before a closed test

- Redeploy `coach` v1 with the candidate 2 prompt and the `retryInstruction`
  change, after one more eval pass. The contract version and schema are
  unchanged.
- Consider `COACH_FALLBACK_MODEL=gemini-3.1-flash-lite`, which has its own
  quota. Check its daily limit in AI Studio first.
- Device checks still pending from step 3:
  - the Android offline notice
  - the keyboard and the input bar
  - a 401 after an expired session
- Testers are informed adults only: the free tier lets Google use prompts.
  Before any public release, turn billing on (EEA/UK/Switzerland rule) and
  set a spend control. See Risks and terms.

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
