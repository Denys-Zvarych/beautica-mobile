
# CI: Patrol native E2E (`patrol` job)

Moved verbatim from `pr-validate.yml` comments, in file order. The text is the record as written at
the time, so some notes contradict later ones (the loop cadence history, for example). The current
rule is the one in the YAML: the re-approval loop runs every 1s.

<a id="job-patrol"></a>

### patrol (phase 17.5)

Patrol native E2E (Phase 17.5).

Covers OS-level surfaces integration_test cannot reach (deep-link intents,
permission dialogs, notifications, WebViews) via patrol's `$.native.*`.
Tests live under integration_test/patrol/ and run through native
instrumentation (PatrolJUnitRunner) driven by the patrol_cli global tool —
NOT `flutter test`. The headless `integration` job above is unaffected: the
all_tests.dart aggregator does not import anything under patrol/.

WHY THIS JOB IS GATED (not per-PR):
  The native compile builds the androidTest variant + AndroidX Test
  Orchestrator and boots a full emulator — materially slower than the fast
  jobs. Running it on every PR is not justified, so it runs only on:
    • the nightly (nightly.yml -> workflow_dispatch on dev),
    • manual `workflow_dispatch`,
    • PRs explicitly labelled `run-patrol`,
    • PRs that touch a native surface (see the `plan` job / tool/ci/plan.sh).
  It is a SEPARATE job, so it never blocks or merges into the fast
  `gates` / `integration` jobs.

  The last clause was added because label-only opt-in meant a PR that broke
  App Link routing merged green — nobody remembers to add a label for a
  regression they do not know they are introducing.

EXPECTED OUTCOME PER TRIGGER (all four cases the `if:` must get right):
  1. workflow_dispatch   -> RUNS (manual or nightly; never gated on a diff)
  2. PR + `run-patrol`   -> RUNS (clause 3, label branch)
  4. PR touching native  -> RUNS (clause 3, changed-paths branch)
  5. any other PR / push -> SKIPPED (no clause matches; `push` is
                            deliberately absent — its PR already covered it)

<a id="patrol-timeout"></a>

### patrol: job timeout (2026-07-22)

Bound the job. Without this it inherits GitHub's 6-hour default, and a
hung emulator burns six hours of runner time before anyone notices. On
2026-07-22 this job sat ~90 minutes on the test step before the emulator
died; a healthy run is well under 30. 45 gives generous headroom for a
cold native compile without letting a hang run away.

<a id="patrol-matrix"></a>

### patrol: API 34 only

Matrix axis: API 34 only. API 29 was dropped — its x86_64 system image
crashes with a native jemalloc SIGSEGV during native-thread creation
(art::Thread::CreateNativeThread → je_malloc) before any patrol test runs.
The same APK runs clean on API 34, so the crash is the emulator image, not
app code. The deep-link test asserts App Links routing, and the strict
path that can actually break is Android 12+ (API 31+) — already covered by
API 34. (minSdk is 26; re-add API 29 pinned to a known-good image on a
continue-on-error leg if pre-12 coverage is later needed.)

<a id="patrol-cli-pin"></a>

### patrol_cli exact pin (2026-07-22)

patrol_cli is a GLOBAL tool — intentionally not a repo dependency.

PIN THE EXACT VERSION. patrol_cli and the `patrol` package ship a
hard compatibility check: the CLI refuses to run against a package
version it does not declare support for, and the pairing is exact,
not semver-compatible. patrol_cli 4.5.x requires `patrol` 4.7.0
("This version requires version `4.7.0` of `patrol` package", CLI
4.5.0 changelog); 4.4.0 paired with patrol 4.6.x.

This line previously read `dart pub global activate patrol_cli` with
NO constraint, while the comment above it claimed a major-version
pin. It was unpinned in fact. On 2026-07-22 the CLI moved to 4.5.1
while pubspec still had `patrol: ^4.6.1`, and the job died with
"Patrol version 4.6.1 ... is not compatible with patrol_cli version
4.5.1". Because the job is `run-patrol`-gated it had never run on an
ordinary PR, so the break surfaced only when the label was applied.

Bump BOTH together, never one: this pin and `patrol:` in pubspec.yaml.

<a id="patrol-scope"></a>

### patrol: test scope

Scope to integration_test/patrol so patrol only bundles the
patrolTest flows. With test_directory: integration_test in
pubspec.yaml, a bare `patrol test` would also discover the 5
non-patrol flow files + all_tests.dart (testWidgets, not
patrolTest) — those stay on the fast headless `integration` job.
The FCM cases are skip-marked at the Dart level (Firebase deferred)
so they report as skipped, not failed.

<a id="patrol-logcat-capture"></a>

### patrol: background logcat capture

Capture full device logcat in the background so a crash stack
(Process crashed → FATAL EXCEPTION) survives — patrol/gradle only
surface "Process crashed", not the device-side stack. Backgrounded
on its own line so it survives this line's sh -c exit.

<a id="approve-loop"></a>

### patrol: background App Link re-approval loop

BACKGROUND RE-APPROVAL LOOP (load-bearing fix). patrol test rebuilds +
reinstalls the app right before running, which WIPES App Link approval,
so a one-shot pre-approval is gone by the time openUrl fires (deep-link
test runs 3rd). This loop re-asserts STATE_APPROVED for both default
and user scope, so whenever patrol's reinstall lands the domain is
re-approved before the intent is fired.

CADENCE IS 5s, NOT 1s — do not tighten it back. On 2026-07-22, the
first run in which this job ever reached the tests (a CLI version
mismatch had killed it earlier, so the loop had never actually run in
anger), the emulator died mid-suite with
`device 'emulator-5554' not found` and
`[EmulatorConsole]: Failed to start Emulator console for 5554` BEFORE
any test started. Patrol reported 0 test failures — 1 passed, 2
skipped, and the run simply lost its device. In that SAME workflow
run, on the same runner image, same emulator-runner action and same
API 34, the `integration` job — which runs NO adb loop — passed a
15-minute suite on its own emulator.

CADENCE IS 1s AND MUST STAY 1s. It was introduced at 1s by
3e7dc9c ("keep App Link approved during patrol run") precisely to
win the race against patrol's reinstall, and it is the reason the
deep-link test passes at all.

DO NOT SLOW IT DOWN. On 2026-07-22 it was cut 5x (1s -> 5s) on a
hypothesis that adb contention from this loop was killing the
emulator. That hypothesis was TESTED AND DISPROVEN — the next run
failed byte-for-byte identically, same test, ~87s, same
`device 'emulator-5554' not found`. The device loss is unrelated
to this loop (it is bisect-confirmed to be the CLIENT test's
client-shell mount; see auth_login_patrol_test.dart).

But the slowdown was not free: the deep-link test failed on every
run while the cadence was 5s. Losing the approval race means the
URL opens in a BROWSER, the app is backgrounded, and the Flutter
engine stops producing frames — so the test does not fail fast, it
HANGS, because `pump()` blocks forever waiting for a frame that
never comes. That is what the `patrol test` `timeout` below (900s then, 1200s now) caught.

Lesson worth keeping: this loop is load-bearing for the deep-link
test, and it was slowed to chase a defect in a different test.

What the evidence actually shows, for whoever picks this up: the
failure is DETERMINISTIC, not the intermittent flake this repo has
classified it as since 2026-07-01. Two runs on two commits both
died at the same point — test 1 passes in 6s, test 2 kills the
device — with patrol reporting ZERO failed assertions. The captured
logcat contains no `beautica` lines at all and ends during boot
chatter, so the background `adb logcat` lost the device before the
app even started, and `[EmulatorConsole]: Failed to start Emulator
console for 5554` prints before any test runs. `patrol doctor` also
reports `Program adb not found` while $ANDROID_HOME is set, so
patrol_cli, the emulator-runner action and Gradle's ddmlib may not
all be resolving the same adb. That mismatch is UNVERIFIED — it is
a direction, not a diagnosis.

It STOPS the instant patrol finishes, via the sentinel file written on
the patrol line below — the emulator-runner action waits for backgrounded
children, so a loop that kept spinning would hang the step for minutes
after the tests already passed (observed). Each adb call is `timeout`-
bounded so a call can never wedge, and the loop is iteration-capped as a
final backstop. NOT pkill'd — `pkill -f` would match its own argv and
SIGTERM the cleanup shell ("exit code null"). Must be ONE self-contained
line so the `&` background survives this line's own sh -c.

<a id="pre-test-app-links"></a>

### patrol: pre-test App Link diagnostic

DIAGNOSTIC: the real domain-verification state, right before the
suite runs. If the deep-link test still routes to a browser, this
is the line that says why — look for the domain under "Selection
state" / whether it reads as approved for user 0.

<a id="gallery-seed"></a>

### patrol: gallery seed (PR #79)

GALLERY SEED (PR #79): avatar_pick_patrol_test selects a photo in the
system Photo Picker, and a device test cannot write MediaStore — the
host must seed it. Unseeded, the picker grid is empty: the test fails
«no photo cell found», the picker stays in front with the app
backgrounded, and the NEXT test hangs to the 1200s bound. Fail the step
here (not 15 min later) if the seed or its MediaStore row is missing.

<a id="patrol-exit"></a>

### patrol: exit code on one line

Run patrol, capture its exit, signal the loop to stop, then exit with
patrol's real code — all on ONE line so the exit status carries
(android-emulator-runner runs each line in its own sh -c, so a separate
CODE=$?/exit would not). This makes the step's result equal patrol's.

<a id="sdk-preinstall"></a>

### patrol: SDK platform preinstall (2026-10-17)

`:add_2_calendar` compiles against `platforms;android-33`, which the runner
image does not ship. Gradle then downloads it mid-build, and on PR #95
attempt 3 that download failed 8s into `patrol build` ("Failed to install the
following SDK components"). The `.github/actions/android-sdk-platform`
composite runs `sdkmanager --install` first: skipped if `android.jar` is already
present, 3 attempts with 10 s / 30 s backoff (download cache and partial dir
cleared between), the log tail always printed on failure, loud failure after
the last attempt. It runs in every
job whose Gradle build happens on an emulator runner: `integration`,
`integration-profile`, `patrol`. `apk` is excluded: it is not an emulator job,
and a failed download there fails a plain build that is simply re-run.

<a id="patrol-retry"></a>

### patrol: retry once on a lost device only (2026-10-17)

The emulator process occasionally dies mid-suite (the ColorBuffer crash in
`docs/ci/emulator-integration.md`), showing up as `device 'emulator-5554' not
found` / `AdbCommandRejectedException`. Attempt 1 runs with
`continue-on-error` and its output goes to `patrol-attempt-1.log`. The
`patrol-gate` step runs `scripts/ci/patrol_retry_gate.sh` on that log: exit 0
(retry) only for a lost-device signature (`device 'emulator-N' not found`,
`AdbCommandRejectedException`, `device offline` AFTER the seed line, or a
Gradle SDK-install failure). Veto markers come in two groups. HARD assertion
markers (`EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK`, `TestFailure`,
`Expected:`/`Actual:`, `AssertionError`, `Unhandled Exception`) always win over
a signature, so a real failure is never retried. `Unhandled Exception` is the
capital-E Dart engine form only: the lowercase `Unhandled exception:` is
patrol_cli itself crashing on a dead adb link, which is infrastructure noise.
`PATROL TIMED OUT` (a hang) vetoes UNLESS a hard device-lost signature
(`device 'emulator-N' not found` or `AdbCommandRejectedException`, nothing else:
not `device offline`) is also present: then the emulator died (ColorBuffer
crash) and patrol hung on the dead link, so it is retried. A timeout alone, or
timeout plus a hard assertion marker, is never retried. Attempt 2 is a fresh emulator-runner step. The
`Verify patrol passed` step judges attempt 2 when it ran, else attempt 1.
The gate's fixture matrix is `scripts/ci/patrol_retry_gate.sh --self-test`,
run in the `gates-fast` job. The step log is replayed with `cat` after each
command (no `| tee`: a lingering adb/gradle daemon holding the pipe would
hang the step).

<a id="patrol-test-bound"></a>

### patrol: `patrol test` bound (1200s, raised 2026-10-15)

The `timeout` on the `patrol test` line is a HANG detector, not a budget:
a healthy suite is ~10min for the 12 cases that existed before 2026-10-15.
`services_fab_cold_start_patrol_test.dart` (the flutter_riverpod 3.1.0
frame-scheduler freeze regression) adds 5 cases, each a separate cold
start under the orchestrator. Estimate per case: the comparable
fake-backend `auth_login_patrol_test` case passes in ~6s of test body,
plus ~10-15s of per-case orchestrator process start and three real-frame
navigations — ~20-25s, so ~2min for the five. 900s would have left ~3min
of headroom over a ~12min healthy run; 1200s restores ~8min while still
catching a hang long before the 45-minute job bound
(#patrol-timeout). If the five cases ever need trimming, 3 cases still
catch a 50%-per-run regression 87.5% of the time (5 cases: 97%).

<a id="host-diagnostics"></a>

### patrol: emulator host-side diagnostics

The gfxstream/swiftshader ColorBuffer race this repo has chased for
weeks announces itself on the EMULATOR PROCESS's own stdout
("Failed to find ColorBuffer"), which is NOT reachable from here: the
emulator is launched by android-emulator-runner, so its stdout goes to
that action's log group and there is nothing to tee. Do not add a
`| tee` to the script expecting to catch it — it will silently capture
nothing, which is worse than not trying.

What IS reachable is collected below: the emulator's host-side log and
crash files, plus the GL/gfxstream chatter that does reach logcat
(EGL_emulation / emuglGLESv2 / gralloc tags). Combined with the always-
uploaded device logcat, that is the best evidence available without
patching the action itself.

<a id="logcat-always"></a>

### patrol: logcat upload on always()

`always()`, NOT `failure()`. This gate cost a real investigation:
runs #292/#293 lost the emulator mid-suite, but `patrol test` HUNG on
its post-run uninstall and the jobs were cancelled rather than failing.
`failure()` is FALSE on cancellation, so neither run uploaded anything,
and the newest artifact on the shelf was from #291 — a run that had
died on a CLI version check before any test executed. Its logcat held
ten seconds of boot chatter and zero app lines, which was then read as
evidence about a failure it had never observed.

A diagnostic artifact must survive the failure modes it exists to
diagnose. Cancellation and timeout are exactly when it is needed most.
