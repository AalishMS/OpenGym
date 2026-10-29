# Training blocks: manual device checks

Use a test split with two simple plans, Push and Pull. Keep an untouched copy
of any backup you import. The offline phone build cannot verify sign-in, Coach
generation, or cross-device sync; those need a separately configured backend.

## Phone checklist

- [ ] **Block management and navigation.** Tap the block name and use its menu to
  create, rename, and reorder blocks. Create one with four intended weeks and
  confirm that only Week 1 appears. Extend it only after the fourth completion.
  The selected block shows its reached weeks inline, and scrolling reaches
  every available week. Labels update after reorder
  without changing which log belongs to which week.
- [ ] **Independent progress.** Start Push and Pull at Block 1 / Week 1.
  Complete Push: it reveals and advances to its next week while Pull keeps only
  Week 1. Complete Pull and confirm it advances independently. Reopening,
  browsing, leaving a draft, or discarding it must not advance either plan.
- [ ] **Boundary choices.** Complete the intended final week. On the next
  ordinary workout entry, check Add week and either Move to next block or
  Create block, depending on whether another block exists. Dismiss the choice:
  the completed result remains visible with Choose next week. Reopen the
  choice and try each action on separate test plans. Only the choosing plan
  moves; other plans keep their active week and existing available tabs.
- [ ] **Sequential values and block starts.** Log distinct values in Block 1, such as
  Week 1 = 60 × 8 and Week 2 = 65 × 6. Move the same plan into Block 2.
  Its Week 1 starts from Block 1's Week 1 values. Log new values there, such as
  70 × 5; Block 2 Week 2 must inherit 70 × 5 rather than Block 1 Week 2 or plan
  targets. New sessions must have fresh completion/timer state.
- [ ] **Same-number weeks and past logs.** Give Block 1 / Week 1 and Block 2 /
  Week 1 visibly different results. Open both through the strip and History:
  each must show its own log. Opening an old log must not move active progress
  or show a next-block prompt. Completed logs are read-only in the logger;
  explicit History editing still works.
- [ ] **Drafts and saving before navigation.** Change reps/weight, then switch
  weeks, plans, or leave the screen. Return and check the values were saved.
  Browsing another incomplete week may save a draft, but a new timer and Log
  workout are available only for the active week.
- [ ] **Starting slot selection.** Add and duplicate a plan. Check the visible
  default is the first week of the first block, then choose a different block
  and week. Start the new plan and confirm that destination. Editing an
  existing plan must retain its current progress.
- [ ] **Timer and Android notifications.** Start a timer, background the app,
  and lock/unlock the phone. Check the block/week label and elapsed time.
  Exercise notification Pause, Resume, and Stop. Tapping the notification must
  open the exact workout session, including while another sheet is open;
  stopping must follow the app's confirmation flow without losing set edits.
- [ ] **Cold restart.** With edited values and a paused timer, force-stop the
  app from Android Settings and reopen it. Enter the plan: block/week, values,
  and elapsed time must survive. Repeat with a running timer and check elapsed
  time remains sensible. Completed History and plan progress must also survive.
- [ ] **Backup round trip.** Export a backup containing multiple blocks,
  different active weeks for Push/Pull, and a draft. Restore that backup into
  the test installation and compare structure, logs, progress, and draft
  values. Reopen the app and compare again.
- [ ] **Legacy migration, if an old backup is available.** Import a copy of a
  pre-block backup, ideally containing sparse week numbers and an unfinished
  workout. Verify one initial block per split, preserved week numbers/gaps,
  historical sets, durations, and recoverable drafts. Reopen and confirm no
  duplicated structure or lost history.
- [ ] **Real-phone usability.** Try light/dark mode, keyboard entry, Back,
  long names, and a block with 52 weeks. Scroll and expand blocks while a timer
  runs. Look for clipped controls, gesture conflicts, delayed taps, jumps,
  freezes, and notification problems. This is a usability check, not measured
  frame profiling.

## Separate checks

- Full browser workout interaction needs the web build.
- Account switching, two-device offline convergence, competing appends, and
  late legacy synchronization need two installations and a configured test
  backend. They cannot be verified by the offline phone build.

For any failure, record the test item, exact taps, expected/actual result,
block/week and plan, whether the timer was running, and a screenshot or video.
