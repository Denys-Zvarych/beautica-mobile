# CI investigation — Integration tests (emulator) job failing on PRs

Overnight autonomous investigation, started 2026-07-06 on branch
`fix/ci-integration-emulator-teardown-crash` (off `dev`, which is last-merged
PR #32 `feat/otp-password-reset`). Logging steps/findings here as instructed,
so the trail survives even if this session is interrupted.

## Symptom

`Integration tests (emulator)` job in `.github/workflows/pr-validate.yml` has
failed on ~4 of the last 5 checked runs (dev push + feat/otp-password-reset +
feat/booking-data-foundation PRs, 2026-07-05/06). `Analyze & Test` job is
unaffected — always green.

Every failing run shows the SAME signature:
- Every flow's own `dart:developer log()` assertion prints `✅ ...` — the
  actual app/test logic never fails.
- The formal test reporter only ever acknowledges "🎉 1 test passed."
  (aggregator quirk, documented in `all_tests_part1.dart` header).
- Right at the very end: `adb: device offline`, `adb uninstall failed`,
  `emu kill: could not connect to TCP port 5554: Connection refused`.
- The job step exits 1 purely from this teardown crash, not from any
  failed assertion.

## Prior art (already in this repo — do NOT redo the full bisection)

- `pr-validate.yml` INCIDENT comment (above the `integration` job's "Run
  integration tests on emulator" step, dated 2026-07-01): git-bisected this
  exact symptom to commit `7307721` ("Phase 13.7 Home Hub"). Reproduces
  reliably on CI's headless emulator (`-gpu swiftshader_indirect`), but the
  SAME test file ran clean on a real connected emulator with live logcat
  monitoring — zero FATAL/ANR entries. Ruled out: RAM/heap, ensureSemantics()
  anti-pattern (fixed anyway, unrelated), emulator-runner version (bumped
  anyway), swiftshader_indirect→swiftshader (reverted, no benefit). Root
  mechanism inside GitHub's runner/headless-swiftshader stack was left
  **unidentified** — the PR (#29) was closed without a real fix, just
  documented, and the bug shipped as an accepted intermittent risk.
- `all_tests_part1.dart` / `all_tests_part2.dart` header comments (2026-07-01
  split): separately documented theory that a single `flutter test` process
  aggregating too many tests degrades the adb-forwarded VM-service result
  channel before its own clean shutdown. Split from 1 file (19 flows) → 2
  files, to "amortize" this. Flow count has since grown to 21 (2 new OTP
  flows), reopening the same failure class.

So there are two documented theories already on file, never reconciled:
  (A) cumulative test-count/relaunch-count degrades the channel
  (B) commit 7307721 / Home Hub screen specifically triggers a headless-GPU bug

## New evidence gathered this session (2026-07-06, run 28790349494, job 85367118175)

- `all_tests_part1.dart` currently aggregates **10 flows / 39 `testWidgets`
  app-relaunches** in one process. `all_tests_part2.dart`: 12 flows / 24
  relaunches. (Each `testWidgets` = one full app kill+relaunch inside the
  same `flutter test` process, per the file's own "RE-LAUNCH SAFETY" note.)
- New symptom not previously documented: `ERROR | Failed to find
  ColorBuffer: 150` (virtual-GPU surface-handle error, goldfish-opengl /
  swiftshader host-guest translation layer) logged right as
  `client_home_hub_flow` — the SAME screen from the 2026-07-01 bisection —
  starts (it's the 2nd group in part1's declared order, right after
  `auth_login_flow`).
- Checked 5 other recent CI runs directly via the GH API job logs: 4/5
  failed, 1/5 passed on the integration job — genuinely intermittent
  (~80% failure), not deterministic every time.
- This strongly corroborates theory (B) — Home Hub's rendering (gradients,
  staggered animations, several cards) is the trigger — while theory (A)
  (more flows added since the 19→21 split) plausibly explains why the
  failure rate went from "rare/tolerable" back to "almost every run":  more
  flows after the trigger = longer session after the corruption = higher
  chance the corrupted channel actually kills teardown before the process
  exits cleanly.

## Experiment 1 (this branch, via `workflow_dispatch`, NOT part of the fix)

Temporarily replaced the 2-line aggregator script in the `integration` job
with **one `flutter test <single-flow-file>.dart` invocation per flow**
(22 lines, same relative order as the two aggregators, each with an echo
marker). Rationale: `reactivecircus/android-emulator-runner`'s multi-line
`script:` runs each line in its own `sh -c` (already established elsewhere
in this same YAML, see the patrol job's re-approval-loop comment) — so one
line's process death does NOT abort subsequent lines. This isolates each
flow to its own process/teardown:
- If only `client_home_hub_flow_test.dart`'s own invocation fails →
  theory (B) confirmed, fix = isolate/harden that one flow.
- If failures appear on arbitrary/multiple flows regardless of position →
  theory (A) or a different shared-session mechanism; rebalance/isolate
  more broadly instead.
- Also added a background `adb logcat -b all` capture (mirrors the patrol
  job's pattern) uploaded as an artifact on failure, for native-level detail
  the Dart-level log can't show.

Result: **(fill in after the workflow_dispatch run completes)**
