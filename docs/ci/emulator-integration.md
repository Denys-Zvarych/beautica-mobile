
# CI: emulator integration (`integration`, `integration-profile`)

The 2026-07-07 root-cause notes below are the ONLY copy. The original comments cited
`docs/ci_investigation_notes.md`, which never existed in either repo.

<a id="enable-kvm"></a>

`Enable KVM` (KVM is required for hardware-accelerated emulator boot on the runner) is one
composite, `.github/actions/enable-kvm`, used by `integration`, `integration-profile` and `patrol`
(phase 402 D14). `workflow_wiring_test.dart` pins that and that no `udevadm` is left in the
workflow.

Moved verbatim from `pr-validate.yml` comments, in file order.

<a id="job-integration"></a>

### integration (Fix 4, 2026-06-02; phase 401)

End-to-end integration tests (Fix 4, 2026-06-02).

integration_test/ drives the REAL app widget tree (real screens + real
notifiers + real repository + real generated client + real serialization)
with ONLY the Dio transport socket faked by http_mock_adapter — no live
backend. IntegrationTestWidgetsFlutterBinding requires a device, so this job
boots a headless Android emulator (KVM-accelerated on the runner) and runs
the two aggregating files all_tests_part1.dart + all_tests_part2.dart.

Phase 401: on a `selective` PR only the flows whose own code path changed
run, through a generated, gitignored integration_test/ci_selected_tests.dart
(tool/ci/affected_tests/bin/gen_integration_entry.dart, run from the BASE
commit). D3: when the selection covers >= 70% of a part, or any hub changed,
the two part files run unchanged. FULL mode (push, dispatch, nightly, any
fail-safe) runs exactly the two part files, command lines unchanged.
D4: skipped when the selector found no flow (ci-gate treats a skip as ok).

Run locally against a connected emulator (see scripts/connect_adb.sh) with:
  flutter test integration_test/edit_profile_flow_test.dart

<a id="integration-timeout"></a>

### integration: job timeout

Backstop for the backstop. Each of the six invocations below is
individually `timeout`-bounded (see part 1 attempt 1), so this only has
to cover the case where the emulator action itself wedges outside the
`script:` block. Without it the job inherits GitHub's 6-HOUR default.

<a id="gradle-cache"></a>

### integration: Gradle cache (phase 401 P2, D6)

P2: Gradle's downloads/transforms for the app build. RESTORE ONLY on
pull_request: a PR can never write the cache other runs read (the save
step below runs on push/dispatch/nightly only). This feeds the APK build,
which is PR-controlled code anyway, never the selector (400 D8, see the
phase 401 doc D6). The key hashes the files that decide Gradle inputs.

<a id="choose-entry"></a>

### integration: choose entry (phase 401)

entry=selected only when the trusted generator ran cleanly and wrote
integration_test/ci_selected_tests.dart, and the trusted attempt script
exists. EVERYTHING else (generator or script missing on the base, crash,
no/odd entry= or count= line, `none`, D3/cap fallback) is `parts`: the
two part files, i.e. the pre-401 run. Fail-safe to FULL (400 D7).
S1: the target is removed first (a PR-committed dangling symlink would
redirect the write). S3: `--packages=<empty config>` makes the generator
ignore the PR's .dart_tool/package_config.json (it has no imports;
`/dev/null` itself is rejected by dart as an empty packages file).
P3: bound = clamp(420 + 45 * flows, 600, 1500) seconds.

<a id="root-cause-2026-07-07"></a>

### Root cause + fix (2026-07-07): emulator teardown crash

ROOT CAUSE + FIX (2026-07-07 — see docs/ci_investigation_notes.md for
the full overnight investigation trail). This step used to run once.
A 2026-07-01 incident found it crashing the emulator at final
teardown ("adb: device offline" right after the LAST flow's own
assertions all logged ✅) and bisected it to commit 7307721. The
2026-07-06/07 follow-up investigation falsified that bisection and
several other theories (Home-Hub-specific rendering, cumulative
relaunch count, API 34/35 instability, Flutter SDK drift) via
systematic isolation, then confirmed the real mechanism: GitHub's
headless emulator (goldfish-opengl / swiftshader_indirect) releases
an app relaunch's GL ColorBuffer handles ASYNCHRONOUSLY host-side; a
NEW relaunch starting before that cleanup finishes crashes the WHOLE
emulator (`Failed to find ColorBuffer` -> `adb: device offline`,
unrecoverable — `adb emu kill` itself can't connect) instead of just
logging a warning. This is a documented, UNRESOLVED upstream bug —
see ReactiveCircus/android-emulator-runner#358 and
flutter/flutter#153445/#140001/#146890 (Google's own LUCI CI hits the
identical crash class with no confirmed permanent fix).

Mitigations, layered (see docs/ci_investigation_notes.md for the full
trail, including two rounds that turned out NOT to fully explain it):
  1. A 2s settle delay in `AppHarness.tearDownHarness()` /
     `PatrolHarness.tearDownHarness()` (integration_test/support/,
     integration_test/patrol/support/) — the ONE shared choke point
     every flow file already calls via
     `tearDown(AppHarness.tearDownHarness)`. Reduces (but does not
     eliminate) the incidence of the stall.
  2. `sleep 15` between the two `flutter test` invocations below —
     harmless, but confirmed NOT to be the deciding factor: the crash
     still fires WITHIN `all_tests_part1.dart` itself (the 1st→2nd
     relaunch transition inside that one process), never actually
     reaching this sleep.
  3. THE ACTUAL FIX — success detection by log content, not shell
     exit code. Confirmed on repeated samples: the 1st→2nd relaunch
     transition inside `all_tests_part1.dart` always logs `Failed to
     find ColorBuffer`, stalls ~35-40s, then EVERY ONE of the file's
     39 relaunches completes and logs ✅ — but the adb/emulator link
     is left wedged, so the file's OWN final teardown/uninstall then
     fails hard (`adb: device offline`, unrecoverable — `adb emu
     kill` itself can't connect), well AFTER every real assertion in
     the file already passed. This can ALSO kill `flutter test`
     itself before it prints its own `🎉 N tests passed.` summary
     (confirmed: a run with all 39 ✅ present had NO 🎉 in the log,
     so gating on that marker alone is too fragile — it depends on
     the process surviving long enough to flush it). A real
     assertion failure, by contrast, ALWAYS prints `EXCEPTION CAUGHT
     BY FLUTTER TEST FRAMEWORK` synchronously, at the moment of
     failure — unaffected by anything that happens later (confirmed
     via the unrelated logout_flow_test.dart bug found during this
     investigation, backlogged separately). So: capture each
     invocation's own output, and gate on the ABSENCE of that
     exception banner (plus a sanity check that at least one ✅ was
     logged at all, in case of a crash before any test could run) —
     not the process exit code, which is polluted by this separate,
     well-documented, UNRESOLVED upstream emulator bug
     (ReactiveCircus/android-emulator-runner#358,
     flutter/flutter#153445/#140001/#146890 — Google's own LUCI CI
     hits the identical crash class with no confirmed permanent fix)
     that fires strictly AFTER the tests it's supposedly reporting on.
Retry the WHOLE step (fresh emulator boot each attempt) up to 3 times
regardless, as defense-in-depth for the rarer case where the crash
happens mid-run rather than at final teardown (no ✅ ever logged, or
a real exception banner) — genuinely not masked by mitigation 3
and still fails the attempt).
DECOUPLED PART BOOTS (2026-07-07, round 6): part1 and part2 EACH get
their own independent emulator boot + 3x retry, instead of sharing
one boot with a sleep in between. Confirmed necessary: part1's crash
doesn't just wedge the adb link, it kills the WHOLE emulator process
(part2 then fails with flutter's own "No supported devices
connected" — no `sleep` duration fixes that, since there's no
device left to wait for). Splitting into separate boots means
part1's crash has zero effect on part2's own fresh attempts.

<a id="ram-size"></a>

### integration: ram-size / heap-size (2026-07-01)

ram-size/heap-size (2026-07-01): harmless baseline bump, kept even
though investigation showed memory pressure was never the actual
cause. cores is left at the action default (2) since GitHub-hosted
ubuntu-latest runners have 2 vCPUs.

<a id="external-timeout"></a>

### integration: aggregating files + EXTERNAL timeout (2026-08-17)

NOTE: directory-mode batching (`flutter test integration_test/`) does
NOT work — it launches the app once and cannot relaunch between files
("Unable to start the app on the device" after the first flow). Each
AGGREGATING FILE below works the same way the original single file
did: one isolate per invocation, harness re-launches per testWidgets.

The PROFILE-MODE drive leg that used to run here was split into the
separate `integration-profile` job below (2026-06-18, finding 6) so
its slow AOT compile no longer blocks every PR's critical path. This
fast debug pass stays per-PR.

EXTERNAL `timeout` (2026-08-17) — on every one of the six invocations
below, not just this one. An `integration_test/` flow CAN hang with
no bound whatsoever: `IntegrationTestWidgetsFlutterBinding` sets
`defaultTestTimeout = Timeout.none`, and every bound the harness owns
(`AppHarness.settle`'s `Future.timeout`, `pumpAndSettle`'s internal
deadline, the `pumpUntil*` poll deadlines, an explicit per-test
`Timeout`) is a TIMER — none of which tick once a synchronous
allocating build loop has starved the isolate's event loop. That is
not theoretical: `master_archive_flow_test.dart` scenario 2 ran
unbounded on 2026-08-17 and nothing in-isolate could stop it. A
bound OUTSIDE the process is the only kind that works, which is why
this is `timeout(1)` and not another Dart-side constant.

1500 s is per INVOCATION (one aggregated part, ~15 flows in one
isolate) — generous against a healthy run, useless as a hang. It
also composes with the per-attempt retry design: a hung attempt 1
aborts at 25 min and attempt 2 still gets its own fresh emulator,
which a job-level bound alone could not give.

<a id="selected-attempts"></a>

### integration: selected-flow attempts (audit cycles 1, 4)

Selected-flow attempts (audit cycle 1). The pass/fail decision, the
scaled timeout (P3) and the deterministic-failure detection (P5) live in
ONE base-owned script, tool/ci/run_it_attempt.sh, run from trusted/ (P7).
Attempt 3 is skipped when attempts 1 and 2 failed with the SAME failing
tests (`deterministic=true` output of attempt 2); crash/hang/offline
flakes keep all three attempts. Pass/fail is judged from the host-side JSON
test protocol (`--file-reporter json:$RUNNER_TEMP/it-sel/events.json`, needs
jq) -- never from stdout, which a test's print() can forge (audit cycle 4).

<a id="job-integration-profile"></a>

### integration-profile (2026-06-18, finding 6)

Profile-mode integration drive (2026-06-18 debug↔release divergence
safeguard; finding 6).

`flutter test` ALWAYS runs JIT/debug with asserts ON; it has no
`--profile`/`--release` flag (verified: "Could not find an option named
--profile"). So the fast `integration` job above only catches "debug-fails /
release-works" (our logout CircularDependencyError). To ALSO catch the
INVERSE — "release-fails / debug-works", where a STRIPPED assert changes
behaviour on a critical flow — we re-run the logout/auth-cascade flow in
PROFILE mode via `flutter drive` (asserts stripped, AOT, release-like). It is
scoped to logout_flow_test (the critical auth-cascade flow) to keep the AOT
compile bounded.

WHAT THIS JOB ACTUALLY RE-GUARDS (corrected 2026-07-22 — the earlier
wording above overstated it). It does NOT re-guard the
CircularDependencyError that `logout_flow_test.dart` was written for:
Riverpod's `_debugAssertCanDependOn` is `kDebugMode`-only, so with asserts
stripped that specific regression CANNOT fire here — in profile this test
can never fail for its own stated reason. What the job legitimately is:
a "does the critical auth flow still work end-to-end with asserts OFF"
smoke test. Its value is the assert-stripping-changes-behaviour class in
general, and it has already paid for itself once — it is how the silent
`enterText` drop was found (`tester.enterText` no-ops in profile unless the
harness registers the text-input mock; see
`scripts/forbid_missing_test_text_input.sh`). Do not describe this job as
the profile-mode counterpart of the cyclic-invalidation guard; it isn't.

DO NOT ADD SCREENSHOT CAPTURE HERE — it will only ever produce black
frames. `LoginScreen.initState` acquires `screenProtectionProvider`, whose
`_enable()` starts with `if (kDebugMode) return;` (see
`lib/core/security/screen_protection.dart`). So FLAG_SECURE is set in
PROFILE but not in debug, and `adb shell screencap` on this job returns an
all-black image (confirmed on a physical device, 2026-07-22). Debug this
job from `adb logcat` / the driver's stdout, not from screenshots.

WHY THIS JOB IS GATED (not per-PR), matching the `patrol` job idiom exactly:
  The profile AOT compile adds ~1.5–3 min to the critical path on every PR.
  The inverse-divergence class it guards is rare and the auth flow changes
  seldom, so per-PR cost is not justified. It therefore runs only on:
    • the nightly (nightly.yml -> workflow_dispatch on dev),
    • manual `workflow_dispatch`,
    • PRs explicitly labelled `run-patrol` (the same opt-in label the patrol
      native-E2E job uses — both are the heavy emulator-AOT tier).
  It is a SEPARATE job, so it never blocks the fast `gates` /
  `integration` jobs, and the per-PR debug `flutter test integration_test/
  all_tests.dart` pass in `integration` is untouched.

<a id="profile-one-line"></a>

### integration-profile: one physical line

AOT, asserts stripped, release-like — the inverse of the debug
`flutter test` pass. Uses the standard host driver in
test_driver/integration_test.dart.

ONE PHYSICAL LINE, deliberately — do NOT reformat with backslash
continuations for readability. android-emulator-runner executes each
physical line of `script:` as its own `sh -c` invocation, so a
trailing `\` is passed as a literal argument rather than continuing
the command: `flutter drive \` alone yields `Target file "\" not
found.` and the job dies before the driver starts. The `integration`
job above follows the same rule (long single lines joined with `;`).
This bit us for real: the job is label-gated, so the break sat
undetected from 2026-07-07 until a `run-patrol` label first ran it.
