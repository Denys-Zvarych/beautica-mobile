
# CI: emulator integration (`integration`, `integration-shard`, `integration-verify`, `integration-profile`)

The 2026-07-07 root-cause notes below are the ONLY copy. The original comments cited
`docs/ci_investigation_notes.md`, which never existed in either repo.

<a id="enable-kvm"></a>

`Enable KVM` (KVM is required for hardware-accelerated emulator boot on the runner) is one
composite, `.github/actions/enable-kvm`, used by `integration`, `integration-shard`, `integration-profile` and `patrol`
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
boots a headless Android emulator (KVM-accelerated on the runner).

Three jobs (2026-11-06, see [integration-shards](#integration-shards)):

| Job | Name | Does |
|---|---|---|
| `integration` | Integration entry + selected flows (emulator) | chooses the entry; on `selected` runs the selected flows; publishes `entry` (FULL mode: always `parts`, nothing built) |
| `integration-shard` | Integration shard K/8 (emulator) | `entry=parts` only: 8 matrix legs, each one generated shard of the FULL suite |
| `integration-verify` | Integration tests (emulator) | fan-in verdict: `selected` needs `integration`; `parts` needs EVERY shard |

Phase 401: on a `selective` PR only the flows whose own code path changed
run, through a generated, gitignored integration_test/ci_selected_tests.dart
(tool/ci/affected_tests/bin/gen_integration_entry.dart, run from the BASE
commit). D3: when the selection covers >= 70% of a part (all_tests_part1/2.dart,
kept as the D3 reference only), or any hub changed, the entry is `parts` = the
full sharded suite. FULL mode (push, dispatch, nightly, any fail-safe) runs the
shards. D4: skipped when the selector found no flow (ci-gate treats a skip as ok).

Run locally against a connected emulator (see scripts/connect_adb.sh) with:
  flutter test integration_test/edit_profile_flow_test.dart

<a id="integration-timeout"></a>

### integration: job timeout

Backstop for the backstop. Every attempt is individually `timeout`-bounded
inside run_it_attempt.sh, so the job timeouts only cover the emulator action
wedging outside the `script:` block (else GitHub's 6-HOUR default).
`integration` 120 min (setup ~8 min + pre-build <= 15 min + 3 selected
attempts x (boot <= 5 min + <= 1500 s bound)); each `integration-shard` leg
120 min (same sum with the fixed 1500 s bound). Worst case ~8 + 15 + 3 x 30
= 113 min, so three attempts that EACH burn the full bound still fit.
`emulator-boot-timeout: 300` on every attempt (the action's default is
600 s) keeps three boots inside the ceiling. The shard matrix runs
`max-parallel: 8`, so all 8 legs start in ONE wave and the critical path is
the entry job + one 120-min shard, under the ci-gate mirror wait (205 min);
with 6, two waves (2 x 120 min) could exceed it. When the account-wide
limit of 20 concurrent jobs is reached, some legs may briefly queue;
queueing does not fail a job or count toward its timeout.
`fail-fast: false`.

<a id="gradle-cache"></a>

### integration: Gradle cache (phase 401 P2, D6)

P2: Gradle's downloads/transforms for the app build. RESTORE ONLY on
pull_request: a PR can never write the cache other runs read (the save
step runs on push/dispatch/nightly only, from shard leg 1 only so 8 legs
never race for one key). It saves on a red shard too (`!cancelled()` and
attempt 1 not skipped, i.e. the pre-build succeeded; a cancelled run
never saves): a failing test does
not make the warm cache any less valid, and gating on green left the cache
cold for as long as the suite was red. This feeds the APK build,
which is PR-controlled code anyway, never the selector (400 D8, see the
phase 401 doc D6). The key hashes the files that decide Gradle inputs.

<a id="choose-entry"></a>

### integration: choose entry (phase 401)

entry=selected only when the trusted generator ran cleanly and wrote
integration_test/ci_selected_tests.dart, and the trusted attempt script
and pre-build scripts exist. EVERYTHING else (generator or a script missing
on the base, crash, no/odd entry= / count= / tests= line, `none`, D3/cap
fallback) is `parts`: the full sharded suite. Fail-safe to FULL (400 D7).
S1: the target is removed first (a PR-committed dangling symlink would
redirect the write). S3: `--packages=<empty config>` makes the generator
ignore the PR's .dart_tool/package_config.json (it has no imports;
`/dev/null` itself is rejected by dart as an empty packages file).
P4 cap (mobile-perf cycle 2, P1): at most ONE shard's size, 19 flows AND
74 testWidgets (`maxSelectedFlows` / `maxSelectedTests` in the generator,
the same numbers in the YAML, pinned by workflow_wiring_test.dart). Above
it the 8 parallel shards finish sooner than one serial selected run, so
the generator answers `parts`.
P3: bound = clamp(480 + 20 * tests, 600, 1500) seconds, `tests` = the
generator's `tests=` line (the testWidgets of the selected flows). The APK
is pre-built ([prebuild-apk](#prebuild-apk)), so the bound covers the tests:
~13 s/test healthy, 20 s/test ≈ 1.5x, plus 480 s for install, the warm
incremental build (~1–2 min) and app boots. The upper clamp is the shard
bound (1500 s): the selection cap is one shard (74 tests), so the largest
selection is the largest shard's workload (~17 min healthy, 1500 s ≈ 1.5x);
the 480 s offset only pads small selections. It also keeps 3 attempts
inside the 120-min job ([integration-timeout](#integration-timeout)). The old clamp(420 + 45 * flows,
600, 1500) timed out healthy selections of 10+ flows (~3.95 tests/flow:
40 flows needed ~2450 s).

<a id="prebuild-apk"></a>

### integration: pre-built debug APK (mobile-perf cycle 2, P2)

`flutter test` has no `--use-application-binary`, so every attempt asks
Gradle for the APK. tool/ci/prebuild_it_apk.sh builds it ONCE before
attempt 1, outside the attempt `timeout`, with the inputs `flutter test
<entry>` uses on the x86_64 emulator: debug, the default flavor, the
ABSOLUTE entry path as `-t` (flutter test passes `path.absolute`),
`--target-platform android-x64` and the define flutter test adds for
integration runs (`INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false`).
Each attempt is then a warm incremental build (Dart recompile + repack,
~1 min) — counted inside the attempt bound — not a cold build. It is NOT
up to date, and exact flag parity is impossible (PR #137 decision): the
tool's `getBuildInfo` (runner/flutter_command.dart) appends
`FLUTTER_APP_FLAVOR`, the `FLUTTER_VERSION` family and the feature-flag
define after every user define and refuses user-set copies, while `flutter
test` appends its define last, so `-Pdart-defines` always differs and
`compileFlutterBuildDebug` (the kernel compile) re-runs every attempt.
Parity would not buy time anyway: on PR #137, attempts 2 and 3 (inputs
identical to attempt 1's) still spent 52-54 s in `assembleStagingDebug`,
the same as attempt 1 after the 128 s cold pre-build. So the pre-build
stays: it keeps the cold part (dependency download, plugin/Kotlin compile,
resource merge) out of the bound. Two tries
(a dependency download can fail mid-build; the attempts used to retry the
build implicitly); a failed pre-build skips every attempt and the verify
step fails. The selected family runs the base-owned copy from trusted/
(absent on the base => `parts`); the shards run the PR-tree copy.

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
  (2026-10-17 update: the Patrol job now runs `-gpu guest`, which avoids this
  host-side crash class: 10/10 passes. See docs/ci/patrol.md#patrol-gpu-guest.
  This job's part and selected attempts use `-gpu guest` too, since
  2026-11-06.)
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
(2026-11-06: superseded by the JSON verdict and `-gpu guest`, see
[part-attempts](#part-attempts) and [integration-shards](#integration-shards).
The stdout gate passed runs whose tests were cancelled.)
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
cause of the 2026-07 crash (the 2026-11 shard device loss reopens the
question: [emulator-device-loss](#emulator-device-loss)). cores is left at the action default (2) since GitHub-hosted
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

The bound is per INVOCATION (one aggregated entry in one isolate). It
composes with the per-attempt retry design: a hung attempt 1 aborts at
the bound and attempt 2 still gets its own fresh emulator, which a
job-level bound alone could not give. Set it to 1.2-1.5x the measured
healthy test time of that entry (the APK is pre-built; shards: 1500 s, see
[integration-shards](#integration-shards); selected: P3 clamp). A
timeout means slowness OR a hang: the TIMED OUT line prints the elapsed
time and the last fully finished group. Two timeouts in a row set
`deterministic=true` (a third attempt would only burn the bound again).

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

Cancelled tests (2026-11-06). When the emulator dies mid-run (device loss,
see [emulator-device-loss](#emulator-device-loss)), package:test emits `testDone
result=error` with NO `error` event for every remaining test, and the
GitHub reporter still prints those tests with a ✅, so a ✅ in the log can
mean the test was cancelled. run_it_attempt.sh counts them as cancelled,
not failed: if there are no real failures it prints `SELECTED FLOWS:
CRASHED after <last passing test>; N tests cancelled ... — retryable` and
clears the failset, so a crash point that repeats never triggers the
deterministic skip. The failset holds real failures only. The selected
attempts run with `-gpu guest`, same as Patrol (see
[patrol.md#patrol-gpu-guest](patrol.md#patrol-gpu-guest)).

<a id="part-attempts"></a>

### integration: part attempts (2026-11-06, replaced the same day)

The six full-mode part attempts (`all_tests_part1/2.dart`) used to gate on
stdout: no `EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK` banner and at least
one ✅. That gate passed runs the emulator had killed partway, because the
GitHub reporter prints ✅ for cancelled tests (PR #135 full run: part 1 ran 1
test, part 2 ran 82 of about 300; PR #134 was similar). They also ran
without `-gpu guest`, so the host-GPU ColorBuffer crash was what killed them.
With the JSON verdict and `-gpu guest` every test really runs, and ~300
tests per part at ~12-14 s each (PR #134) need 60-70 min: the 1500 s bound
and the 180-min job could not hold them. Replaced by the shards below.

<a id="integration-shards"></a>

### integration-shard: the FULL suite as 8 shards (2026-11-06)

Source of flows: `integration_test/all_tests.dart` (the meta test proves it
imports every flow on disk). Each matrix leg runs
`gen_integration_entry.dart --shard K/8` (PR tree, `--packages=<empty>`),
which writes the gitignored `integration_test/ci_shard_tests.dart`:

- partition: deterministic greedy LPT by `testWidgets(` count per flow
  (heaviest first, ties by name; into the least-loaded shard). Every flow is
  in exactly one shard. 2026-11-06: 149 flows, 588 testWidgets, shards of
  73-74 testWidgets (18-19 flows);
- fail closed: bad K/N, unreadable `all_tests.dart`, a missing or symlinked
  flow, or an empty shard prints `entry=error` and exits 1, so the leg fails;
- `integrationShards` (= 8) in the generator and the YAML matrix `[1..8]` /
  `IT_SHARDS` are pinned equal by `workflow_wiring_test.dart`.

Each leg: fresh emulator per attempt, `-gpu guest`, `bash tool/ci/run_it_attempt.sh
integration_test/ci_shard_tests.dart shard.log 1500 "$RUNNER_TEMP/it-shard"
"SHARD $IT_SHARD"`, 3 attempts with the deterministic skip (same real failing
set twice, or two timeouts in a row), after the one pre-build
([prebuild-apk](#prebuild-apk)). Bound: tests only, ~74 tests x ~13 s ≈
16 min + install ≈ 17 min healthy; 1500 s ≈ 1.5x (a self-test pins bound
>= 1.2 x the largest real shard's testWidgets x 12 s). Margin policy: every
bound (shard and selected) sits at 1.2-1.5x the healthy time, the selected
one capped at the shard bound 1500 s; these are estimates
until the first green full run, when the bounds are re-measured from the
real per-shard / per-test times and reset into that band.
`fail-fast: false`: one failing leg never cancels the others.

The script and the generator come from the PR tree, not `trusted/`: FULL mode
has no trusted checkout, and an edit under `tool/ci/**` forces FULL mode
(rules.yaml), so in a selective fallback the PR copy equals the base.

<a id="emulator-device-loss"></a>

### integration-shard: mid-run device loss + memory hypothesis (PR #137)

What the data shows (PR #137 full run, all 8 shards x 3 attempts, and the
same on dev before the JSON verdict made it visible): the emulator dies 1-3
min into EVERY attempt — `adb: device offline`, then `CRASHED after <test>;
N tests cancelled` — often before the first test passes, with `-gpu guest`
on, and NOT at an app relaunch. So it is not the 2026-07 host-GPU ColorBuffer
crash on relaunch ([root-cause-2026-07-07](#root-cause-2026-07-07)); that
explanation no longer fits.

Leading hypothesis (unconfirmed): host memory pressure. The pre-build leaves
the Gradle daemon (`-Xmx3g` + metaspace, android/gradle.properties) and the
Kotlin daemon (`-Xmx1536m`) alive next to the 4 GB emulator (+ its own host
overhead) on the runner, and each attempt's `flutter test` build used to
reuse/re-grow them while the emulator runs. Mitigation, all in the shard job:

- `Gradle without lingering daemons` writes `org.gradle.daemon=false` and
  `kotlin.compiler.execution.strategy=in-process` to `~/.gradle/gradle.properties`
  (user home wins over the project file), so the pre-build and every
  attempt's `flutter test` build run in a single-use JVM that exits with the
  build (a few seconds of JVM start inside the bound);
- `tool/ci/it_diag.sh stop-build-daemons` after the pre-build and again at
  the start of each attempt (`gradlew --stop` + `pkill -f KotlinCompileDaemon`).

Diagnostics, so the next run confirms or refutes it: each attempt runs
under `it_diag.sh run "$RUNNER_TEMP/it-diag/attempt-$IT_ATTEMPT" -- ...`,
which streams `adb logcat` (logcat.txt), samples `free -m` + top RSS every
15 s (host-mem.txt), dumps `adb logcat -d -t 2000` (logcat-tail.txt) and
records `free -m`, the kernel OOM-killer lines (`sudo dmesg -T`) and top RSS
(host.txt) at the end. It always exits with the attempt's own code. The
directory is uploaded as artifact `it-diag-shard-K`. Read it as: OOM lines
naming `qemu-system-x86_64` / `java` or `available` near 0 in host-mem.txt
=> memory; neither => look at logcat.txt's last lines for a guest-side
crash (kernel panic, system_server death) instead.

Run 42230622003 (2026-11-06, commit 94418332) — what it settled:

- **The post-verdict hang.** All 8 shards printed `SHARD K: CRASHED ...
  retryable` at ~14:15, then hung 52 min until cancelled; none printed
  host.txt's `=== free -m`, so the hang sat between the attempt's exit and
  `host`: `adb logcat -d -t 2000`. adb's shell commands (logcat included)
  loop on "- waiting for device -" while the device is offline, forever.
  Fixed: every post-run adb call is `timeout`-bounded (`IT_DIAG_ADB_TIMEOUT`,
  20 s), the background jobs are SIGKILLed, `host` is bounded (60 s), and each
  shard attempt step has `timeout-minutes: 35` (boot 5 + 1500 s bound + 60 s
  kill-after + diagnostics; 15 + 3 x 35 <= 120). Self-test: ci_scripts_test
  `it_diag.sh run returns ... when adb blocks forever` (hangs against the old
  script).
- **The daemon memory hypothesis is refuted as the trigger.** The daemons were
  stopped and Gradle ran daemon-less, and every shard still lost its device.
- **`-gpu guest` is not in effect.** The api-34 `default` image has no guest
  renderer: `Falling back to 'lavapipe' mode ... vulkan lavapipe gles
  swangle`, i.e. host-CPU rendering (Patrol's 10/10 experiment ran the same
  fallback, so its result still stands as "lavapipe+swangle is stable for
  Patrol").
- **Timing.** Each attempt rebuilds `assembleStagingDebug` (73-100 s) with the
  emulator up; `qemu ... I/O thread spun for 1000 iterations` appears 4-11 s
  after the APK install (= app launch) in 7 of 8 shards; 5 shards then pass 0
  tests, 3 pass 1-11. The device stays `offline` (not gone) for the ~80 s the
  tool keeps running.
- **Not settled:** emulator alive-but-stalled vs dead, swap, OOM, guest
  logcat — the hang ate host.txt and the cancel skipped the artifact upload.
  `it_diag.sh run` now also prints three lines to the step log: `adb devices`
  state, the emulator process (alive / `<gone>`), and min MemAvailable / max
  swap used. Read them as: emulator `<gone>` + OOM lines or available near 0
  => lower `ram-size` (3072M); alive + swap used => same; alive, no swap,
  available healthy => a guest/render stall, try `-gpu swangle_indirect`
  (Patrol runner-up, 10/10) and check logcat.txt; `<gone>` without OOM => a
  host renderer crash, same lever.

<a id="integration-verdict"></a>

### integration-verify: the verdict (fan-in)

Named `Integration tests (emulator)` (the old single job's check name). It
runs unless the run is cancelled or `integration` was skipped (no flow), and
fails closed: `integration` must be `success`; `entry=selected` needs nothing
more; `entry=parts` needs `integration-shard` = `success` (a matrix result is
`success` only if EVERY leg passed; skipped is RED); any other entry is RED.
`ci-gate` (the only required check) needs `integration`, `integration-shard`
and `integration-verify`.

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
