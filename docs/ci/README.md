
# CI: `pr-validate.yml`

Mobile CI is ONE workflow file, `.github/workflows/pr-validate.yml` (phase 402 D14: no reusable
workflows). This folder holds the narratives that used to live in its comments. Each YAML comment
points here with `# why: docs/ci/<topic>.md#<anchor>`.

| Topic | File |
|---|---|
| Job map, trust, comment policy, plan / apk / coverage / tests-ran / ci-gate notes | this file |
| Kyiv DST leg, Tokyo and Honolulu sweeps | [`tz-sweeps.md`](tz-sweeps.md) |
| `integration` + `integration-profile` (emulator, 2026-07-07 root cause, external timeout) | [`emulator-integration.md`](emulator-integration.md) |
| `patrol` native E2E | [`patrol.md`](patrol.md) |
| `forbid_*` static guards in `gates-fast` / `gates` | [`static-guards.md`](static-guards.md) |

## Job map

15 jobs. Required checks: `ci-gate` (this workflow) and `Scan for secrets` (gitleaks).

| Job id | Check name | needs | Runs when | Notes |
|---|---|---|---|---|
| `plan` | Plan (mode + diff) | none | every non-noop event | [plan](#job-plan) |
| `gates-fast` | Static guards (no Flutter) | none | every non-noop event | [gates-fast](#job-gates-fast) |
| `gates` | Analyze & Gates | none | every non-noop event | [gates](#job-gates) |
| `selector-tests` | Selector tests (leg) | none | every non-noop event | [selector-tests](#job-selector-tests) |
| `unit` | Unit tests (shard N) | plan | full, or selective with units | [unit](#job-unit) |
| `tz-sweeps` | TZ sweep (zone) | plan | full, or selective with tz files | [tz-sweeps.md](tz-sweeps.md#job-tz-sweeps) |
| `goldens` | Golden regression tests | plan | full, or selective with goldens | [goldens](#goldens-step) |
| `apk` | Build APKs (variant) | plan, gates-fast | full, or a native-surface PR | [apk](#job-apk) |
| `coverage` | Coverage (merge shards) | plan, unit | whole-suite runs; non-blocking | [coverage](#job-coverage) |
| `test` | Test & Build (aggregate) | unit, tz-sweeps, goldens, apk | always (bootstrap bridge) | [test](#job-test-aggregate) |
| `tests-ran` | Tests actually ran | plan, unit, tz-sweeps, goldens | plan ok, mode != none | [tests-ran](#job-tests-ran) |
| `integration` | Integration tests (emulator) | plan | full, or selected flows | [emulator-integration.md](emulator-integration.md#job-integration) |
| `integration-profile` | Integration profile drive (emulator) | none | dispatch, or `run-patrol` | [emulator-integration.md](emulator-integration.md#job-integration-profile) |
| `patrol` | Patrol native E2E (emulator) (API N) | plan | dispatch, `run-patrol`, native PR | [patrol.md](patrol.md#job-patrol) |
| `ci-gate` | ci-gate | all of the above | always | [ci-gate](#job-ci-gate) |

<a id="trust"></a>

## Trust summary

- **Base-owned** (checked out from the PR base commit as `trusted/` or by a base-only sparse
  checkout): the planner, CI-paths guard, selector, resolver and shard script (`plan`; the guard
  falls back to the PR copy only while the base lacks it), the integration entry
  generator and `run_it_attempt.sh` (`integration`), the tests-ran checker and floor
  (`tests-ran`), and `gate.sh` / `mirror.sh` (`ci-gate`). A PR cannot edit the code that judges it.
- **PR head**: the workflow file itself (protect `.github/**` with CODEOWNERS / required review),
  every local `uses: ./…` composite (they load from the PR head), and all app and test code.
- **Rule (D14):** a local `uses: ./…` never appears in `plan`, `tests-ran` or `ci-gate`, and never
  holds selection or verdict logic.
- **Secrets:** only on non-PR events, through the `ci-trusted-secrets` Environment (branch policy
  dev/main). A pull_request run gets none.
- **Follow-up trigger (D14):** once phase 402 is on BOTH `dev` and `main`, move the `tests-ran` /
  integration verdict glue into base-owned `tool/ci/` scripts with a fail-safe-to-FULL bootstrap.

<a id="comment-policy"></a>

## Comment policy (phase 402 D14)

- A comment in `pr-validate.yml` is at most 3 lines: what / why, then
  `# why: docs/ci/<topic>.md#<anchor>`.
- `workflow_wiring_test.dart` fails on any run of more than 4 consecutive comment lines.
- Longer narratives, incident notes and measurements go in this folder, verbatim, under a stable
  `<a id="…"></a>` anchor. Renaming an anchor means updating every pointer to it.
- Do not edit the `run:` bodies of the pre-400-pinned steps (unit `Test`, goldens, DST, Tokyo,
  Honolulu) to change comments: `pipeline_e2e_test.dart` compares them line by line.
- Test-pinned phrases stay in the YAML: `PR coverage is BEST-EFFORT`, `dev / main runs`, and the
  `# End-to-end integration tests` header.

## Narratives

Moved verbatim from `pr-validate.yml` comments, in file order.

<a id="triggers-no-schedule"></a>

### Triggers: no `schedule:` (phase 396)

Phase 396 — NO `schedule:` here, deliberately. A `schedule` event always runs
the workflow file from the DEFAULT branch (main) but the nightly wants to
test dev's code; the resulting workflow/code skew broke the patrol job for
four nights running. The nightly is now `.github/workflows/nightly.yml`,
which dispatches THIS workflow on `dev` so workflow and code come from the
same branch. Guarded by scripts/forbid_schedule_in_pr_validate.sh.

<a id="concurrency"></a>

### Concurrency groups (phase 396 D4, audit 2026-10-10)

Phase 396 D4 — a superseded PR push stops burning 50-114 min of runner time.
Only pull_request runs are cancellable; dev/main pushes, manual and nightly
dispatches are never cancelled by a newer run.

Group suffixes (audit 2026-10-10):
  * `labeled` events for labels other than full-ci / run-patrol get their OWN
    fixed `-noop` group per PR, so adding e.g. `bug` never cancels the
    in-flight real run; a newer noop run cancels the older one (one mirror
    poller per PR, not one per label). The run itself is a no-op (every job
    below is gated on the same condition).
  * workflow_dispatch gets run_id, so a manual dispatch can never replace the
    pending nightly (a group holds one running + one pending run).

<a id="job-plan"></a>

### plan (phase 397, 400, 401, 402)

Plan (phase 397) — the ONE place that owns the diff and the run mode.

  mode   full       push (dev/main), workflow_dispatch (manual + nightly),
                    PRs labelled `full-ci`, any failed diff computation,
                    any CI-machinery change (guard), a selector FULL
                    verdict, or ANY selector/selection failure (phase 400 D7)
         selective  the selector's explicit lists (unit / golden / tz /
                    integration), consumed by the unit / tz-sweeps / goldens jobs (phases 400, 402)
         none       nothing selectable changed (docs-only): gates only (D5)
  native true|false PR touches a native surface (patrol gate; the globs of
                    the retired `changes` job)
  *_count           list sizes, so consumers decide with `if:` (D1)

Only THIS job does a full-history checkout (fetch-depth: 0, pull_request
only); every other job keeps its shallow checkout. (Phase 401 audit P1: a
bounded window was measured and dropped, see the phase 401 doc D7.) All logic lives in tool/ci/plan.sh and is
table-tested by scripts/test/plan_sh_test.sh (run by verify_guards.sh).
Phase 400 added the selector steps (base-owned, from trusted/); 402 adds
the unit shard lists + matrix outputs (tool/ci/shard_units.sh, base-owned).

<a id="plan-unit-shards-output"></a>

### plan outputs: unit_shards / unit_shard_count (phase 402 D2/D3/D3a)

Phase 402 D2/D3/D3a: the `unit` matrix. JSON array fed to
fromJSON(): [1,2,3,4] (full), [1..N] (selective, N = ceil(count/80),
max 4), [1] (nothing to run: the job is skipped by its own `if`) or
["whole"] (sharding unavailable: ONE job runs the pre-sharding command).
unit_shard_count is N (1 for "whole", 0 when nothing runs). Both come
from the base-owned tool/ci/shard_units.sh; tests-ran re-proves them.

<a id="plan-trust-model"></a>

### plan trust model (security review 2026-10-10)

TRUST MODEL (security review 2026-10-10). On pull_request the PR can
edit any file in its own checkout, including this planner and (phase
400) the selector + rules.yaml; a PR that makes the selector say
"none" would pass ci-gate with zero tests. So the planner/selector run
from `trusted/` = the BASE commit, against the PR tree in `pr/`.
(The workflow file itself is the PR's own on pull_request; protect it
with CODEOWNERS / required review on .github/**.)
For push / workflow_dispatch both checkouts are the same trusted ref.

<a id="plan-guard"></a>

### plan guard: `tool/ci/ci_paths_guard.sh` (phase 402 D14)

Independent of the planner/selector (which a PR could try to subvert):
plain workflow shell, base-owned diff. Any change to CI machinery forces
FULL regardless of what the planner decided.

Phase 402 D14 moved the step body into `tool/ci/ci_paths_guard.sh`. The step keeps its name and
`id: guard`. Like the planner and the selector in the same job, the guard is **base-owned**: the
step runs `$GITHUB_WORKSPACE/trusted/tool/ci/ci_paths_guard.sh` (the base-commit checkout). Only
when the base commit does not have the script yet (bootstrap: the PR that introduces it) does it
fall back to the `pr/` copy, with
`::warning::ci_paths_guard bootstrap: base lacks the script, using PR copy`. `trusted/` is the base
SHA, so a PR cannot choose the branch. The PR tree is data only: `BASE_SHA` / `HEAD_SHA` arrive by
env and the working directory is `pr/`. Sourcing the script only defines `is_forced` /
`is_forbidden`; `scripts/test/plan_sh_test.sh` table-tests both and runs the step body against
both branches, and `guard_parity_test.dart` checks `is_forced` against `rules.yaml`. Changes to
the script (and to `.github/actions/**`) force FULL through the `tool/ci/*` and `.github/*` arms.

<a id="plan-guard-forbidden"></a>

### plan guard: is_forbidden

Paths that must never appear in a PR diff: build output / tool cache
(gitignored; a committed one is a planted file or symlink aimed at
CI output paths) and a top-level trusted/ (the integration job checks
the base commit out at that name; a PR-made one would shadow it). Fail the plan rather than force-full: there is no
legitimate case, so red is the right signal. Also table-tested.

<a id="plan-selector-setup"></a>

### plan selector setup (phase 400 D1/D8, phase 402 D10)

Phase 400 D1 — the affected-test selector (phase 398), run from the
BASE commit (trusted/) against the PR tree, only when plan + guard
still say `selective`. Plain `dart` (no Flutter): the selector is its
own package so analyzer never constrains the app's codegen toolchain.
D8: no cache feeds the selector (PR-scope cache poisoning); uncached dart pub get from trusted/.
Phase 402: unconditional (was selective-only). A FULL run now needs the
selector too: `--all` + `--shard-list` produce the 4 unit shard lists.

Phase 402 D10 (architect 2026-10-11): these two steps run on EVERY plan
because a FULL run needs `--all` + `--shards-for full`. In FULL mode a
failure here (a transient pub.dev / setup-dart outage) must not turn
`plan` red: the shard step then finds no usable selector and degrades to
`unit_shards=["whole"]` (a strict superset of the tests, so it cannot
under-select) with a ::warning::. In SELECTIVE (and none) mode the
expression is false: a failed Dart setup stays a hard failure, because a
selector that cannot run must never be papered over there. `guard` only
exists on pull_request; elsewhere its output is empty and the plan's own
mode decides. Both expressions are pinned in workflow_wiring_test.dart.

<a id="plan-selector-pubget"></a>

### plan selector pub get: bootstrap + D7 fail-safe

Bootstrap (base predates the selector): nothing to fetch; the next
step then finds no base selector and forces FULL.
D7 fail-safe: a failed fetch must not turn the job red; the
selector then exits non-zero and the next step forces FULL (and
the shard step falls back to one whole-suite unit job).

<a id="plan-select-verdict"></a>

### plan Select tests: the one final verdict (phase 400 D7)

The ONE final verdict (job outputs read only this step). D7 fail-safes:
selector exit != 0 (64 usage / 70 internal / anything), missing or
invalid selection.json, or a base without the selector/resolver =>
mode=full. --base-ref is the plan's MERGE-BASE, never the branch tip.

<a id="plan-shard"></a>

### plan Shard unit tests (phase 402 D2/D3/D3a)

Phase 402 D2/D3/D3a — the unit shard lists, from the BASE commit's
tool/ci/shard_units.sh + selector (the `unit` jobs run PR code, so they
only CONSUME these lists). Full: `--all` split 4 ways. Selective:
ceil(unit_count / UNIT_WARN_THRESHOLD) shards, max 4; the threshold is
the resolver's own output, never a second literal here. FAIL-SAFE: every
failure ends in a runnable shape (full -> one whole-suite job,
selective -> one shard with the whole list); this step never goes red.

<a id="job-gates-fast"></a>

### gates-fast (audit F1, phase 402)

gates-fast (audit F1, phase 402) — the grep/awk-only static guards, with NO
Flutter, Dart or Java: checkout and go. A forbid_* violation goes red here
in ~1 min instead of waiting behind the ~3 min Flutter setup + codegen +
OpenAPI check of `gates` (acceptance 3: gate violation red in <= 6 min).
Every guard here was verified to give the same verdict on a tree WITHOUT
generated files and on a PATH with no dart/flutter; the two that cannot
(forbid_raw_ui_strings runs `dart`, forbid_bare_keepalive_family_invalidation
reads *.g.dart) and verify_guards.sh --self-test stay in `gates`.
Starts at once like `gates` (D6: no `needs: plan`).

<a id="job-gates"></a>

### gates (phase 402 D1)

gates (phase 402 D1; was `validate`) — static checks only: codegen verify,
OpenAPI --check, format, analyze and every forbid_*.sh. No tests and no APK,
so it goes red in ~5 min instead of after the whole run. The grep-only forbid_* guards moved to `gates-fast` (audit F1) so they go red in ~1 min; what stays here needs the Flutter toolchain or the generated *.g.dart files. Starts at once
(needs nothing): the cheap checks never wait for `plan`.

<a id="job-selector-tests"></a>

### selector-tests (phase 400 L1, audit F6)

Selector tests (phase 400 audit L1): `dart test` for the affected-test
selector package, including the D8 wiring pins in workflow_wiring_test.dart
(no actions/cache in `plan`, exact selector-step conditions). Own job, off
the `plan` critical path (needs nothing), so a red here never delays the
selection. Runs on EVERY non-noop event like `gates` (no path gate:
a path filter is one more thing a PR could route around, and the run is
~1 min). Same uncached Dart as the plan's selector step (D8): SHA-pinned
setup-dart, the same pinned SDK, no actions/cache, no PUB_* overrides.
ci-gate needs this job; a failure is `result=failure` => RED (gate.sh).

Audit F6: the job sits on ci-gate's path (it is required), and one serial
`dart test` was its longest pole (~10 min on 4 cores). Now THREE parallel
legs of the SAME job id, split by test tag (dart_test.yaml): `fast` runs
everything not tagged `e2e` (-x e2e), `e2e-a` / `e2e-b` run the four
pipeline_e2e_*_test.dart files (the CPU-bound scenarios that execute the real
workflow steps), two files each (-t e2e-a / -t e2e-b). A test file lands in
exactly one leg by construction (new files are `fast` unless tagged), and
every leg runs `--concurrency=$(nproc)`.

<a id="selector-tests-pre400-fetch"></a>

### selector-tests: fetch the pre-400 parity commit

pipeline_e2e_test.dart (parity group) diffs the full branches against the last
pre-400 workflow; the depth-1 checkout lacks that commit, so fetch
exactly it (public repo, anonymous; on dev via PR #81). A failed fetch
is RED: the parity test fails on CI instead of skipping.

<a id="job-unit"></a>

### unit (phase 402 D1/D2/D3/D3a)

Test & build, split (phase 402 D1; was the single `test` job): `unit`,
`tz-sweeps`, `goldens` and `apk` run in parallel, each `needs: plan`
(run_all / the selection / `native`), each with the shared flutter-setup.
`apk` also needs `gates-fast`, an ordering-only dependency (audit cycle 2 N2).
mode=none (docs-only) skips all but `apk`, which a native-surface PR still
needs (phase 400 D4/D5).

unit (D2/D3/D3a): FILE-level shards by our selector, never Flutter's
--total-shards (that splits test cases after every shard compiled every
suite). The lists are written by `plan` (base-owned) and run through
run_list.sh (phase 400), which fails on a missing/empty list, a listed file
that never loads, a failing test or 0 passes. Full = 4 shards of
`--all`; selective = ceil(count / 80), max 4. `tests-ran` re-proves from the
base side that the shards partition the universe (tool/ci/verify_shards.sh).

<a id="unit-test-step"></a>

### unit Test step: parity with pre-sharding

--file-reporter writes the JSON event stream alongside the unchanged
console reporter; `tests-ran` proves real (non-skipped) tests passed.
Per-shard command parity with the pre-sharding step: `--coverage
--exclude-tags golden` in full mode (selective: no --coverage, coverage
is only uploaded for whole-suite runs), over the shard's file list.
The "whole" branch is the pre-400 command byte for byte.

<a id="unit-events-handoff"></a>

### unit: event stream hand-off

The "tests actually ran" verdict is NOT computed here: this job runs PR
test code, which could delete/replace any checker on disk. The event
stream is handed to the `tests-ran` job (no PR code, base-owned script).
always() so a failed Test still hands over its stream.

<a id="goldens-step"></a>

### goldens (phase 17.4)

Phase 17.4 — Golden regression suite.
Runs the alchemist CI goldens (obscureText=true, renderShadows=false)
against the committed masters in test/golden/goldens/.
On failure, golden-diff PNGs are collected from the framework's default
failures/ subdirectory (alchemist writes isolatedDiff, maskedDiff,
masterImage, testImage to <test-file-dir>/failures/) and uploaded so
reviewers can inspect regressions without pulling the branch locally.

<a id="job-apk"></a>

### apk (phase 402 D1, phase 400 D4/D5, audit F5)

apk (D1): native packaging only (~9.5 min); Analyze already proves Dart
compiles. Always in full mode, in selective/none mode only when the PR
touches a native surface (plan.native covers android/**, pubspec.yaml,
lib/main.dart, routing, patrol, this workflow) — phase 400 D4/D5. The
job-level `if` carries that condition, so Java and every build step need none.

Audit F5: a 2-leg matrix (debug | release), one APK build per runner, so the
two ~9 min builds run side by side. The JOB id stays `apk` (ci-gate, gate.sh,
the `test` aggregator and jobRuns() all read needs.apk.result, which is red
if either leg fails). Signing secrets stay on the release leg of non-PR
events only: the debug leg never touches them.

<a id="apk-needs-gates-fast"></a>

### apk: ordering dependency on gates-fast (audit cycle 2 N2)

Audit cycle 2 N2: `gates-fast` (checkout + greps, ~1 min) is a cheap
ordering dependency. ~16 jobs start at once and the account caps
concurrent runners at 20, so without it the off-critical-path APK legs
compete with the unit shards for the first runners; with it they are
claimed only after the unit shards (which need `plan`, ~2 min) are
already running. `apk` stays required by ci-gate (gate.sh), and a failed
gates-fast skips it, which is RED through gates-fast anyway.

<a id="apk-environment"></a>

### apk: ci-trusted-secrets Environment (audit cycle 2 N-L2)

Audit cycle 2 N-L2: the signing secrets live in the `ci-trusted-secrets`
Environment (branch policy dev/main), so a workflow_dispatch from any
other branch cannot read them. ONLY the signed release leg off
pull_request names it: a pull_request run (and the debug leg) evaluates
to the empty string = no environment, so it neither waits for approval
nor fails the branch policy. One-time setup: phase doc 402, "Manual
setup required".

<a id="apk-keystore"></a>

### apk: decode keystore (security audit 2026-10-10)

Decode the release keystore from the base64 secret. NEVER on
pull_request: PR-controlled Gradle runs in the release build below and
must not see signing secrets (security audit 2026-10-10). Real signing
happens only on push (dev/main) and workflow_dispatch.

<a id="apk-build-debug"></a>

### apk builds (phase 400 D4)

Phase 400 D4 — the APK builds (~9.5 min) prove native packaging, not
Dart logic (Analyze already proves Dart compiles): always in full mode,
in selective/none mode only when the PR touches a native surface
(plan.native covers android/**, pubspec.yaml, lib/main.dart, routing,
patrol, this workflow).

<a id="apk-base-url"></a>

### apk: BEAUTICA_BASE_URL has no /api/v1 suffix

NO /api/v1 suffix — the generated OpenAPI client and raw Dio calls
already prepend /api/v1/. A suffix here double-prefixes every URL
(.../api/v1/api/v1/...) → 404. Contract pinned by
test/core/config/app_config_path_test.dart.

<a id="apk-release-compile-check"></a>

### apk: PR release compile check

PRs: compile-only release build, NO secrets. android/app/build.gradle.kts
falls back to the debug key; BEAUTICA_ALLOW_DEBUG_SIGNED_RELEASE=1 tells
its CI distribution guard that this artifact is never distributed
(APK uploads are disabled), so release-only breakage (R8, proguard) is
still caught on PRs.

<a id="apk-uploads-disabled"></a>

### apk: artifact uploads disabled (2026-07-06)

APK artifact uploads are intentionally disabled (2026-07-06) to save
GitHub Actions artifact storage quota — the builds above already
confirm the debug/release APKs compile cleanly, which is all this job
needs pre-release. Re-enable both `actions/upload-artifact` steps
(see git history for this file) once we're close to a release and
need a downloadable build.

<a id="job-coverage"></a>

### coverage (phase 402 D4, audit F2)

coverage (D4): full mode only (a partial run would report false coverage
drops, phase 397 D5). Merges the per-shard lcov files the `unit` shards
uploaded and sends ONE report to codecov. The merged line totals are written
to the job summary: the acceptance check compares them with the pre-phase
single run (within +-0.5 %).

NON-BLOCKING (audit F2): this job only produces an informational codecov
report (fail_ci_if_error: false), so it must never be what ci-gate waits
for. It needs only `unit` (not tz-sweeps / goldens), so it runs side by side
with `tests-ran`; it has no checkout (nothing in the tree is read: the
inputs are the lcov artifacts), installs lcov at a PINNED version without
recommended packages, and `continue-on-error: true` makes its job result
`success` even when a step fails, so neither an old nor the new base
gate.sh can be turned red by it (the new gate.sh also demotes a
failed / cancelled / skipped coverage to a ::warning::).

<a id="coverage-environment"></a>

### coverage: ci-trusted-secrets Environment (audit cycle 2 N-L2)

Audit cycle 2 N-L2: CODECOV_TOKEN lives in the `ci-trusted-secrets`
Environment (branch policy dev/main), so a workflow_dispatch from another
branch cannot read it. A pull_request run evaluates to '' = no
environment (never waits for approval, never trips the branch policy).
One-time setup: phase doc 402, "Manual setup required".

<a id="coverage-upload"></a>

### coverage upload (audit N-L1, S-L2; phase 397 D5)

Audit cycle 2 N-L1: PR coverage is BEST-EFFORT. codecov-action v4
needs a token for a tokenless upload to be accepted for most
repositories; on a pull_request we deliberately pass none (S-L2), so
that upload is likely rejected. `fail_ci_if_error: false` keeps it
harmless. The authoritative coverage numbers are the dev / main runs
(push + dispatch), which upload WITH the token. Do not bump to an
unpinned v5: a bump must SHA-pin a released tag verified with
`git ls-remote https://github.com/codecov/codecov-action <tag>`.

Phase 397 D5 — partial (selective) runs would report false coverage
drops, so only whole-suite runs upload (this job runs only for those).
Audit S-L2: the upload token is passed ONLY on trusted events (push to
dev/main, manual / nightly dispatch). A pull_request run uploads
tokenless: a PR's own workflow/tree can never be handed the secret (the
step does not run its `with: token`, and fork PRs get no secrets anyway).

<a id="job-test-aggregate"></a>

### test aggregate (phase 402 bootstrap bridge)

Bootstrap bridge, REMOVE once the base commit's tool/ci/gate.sh checks the
split jobs (phase 402 follow-up): an OLD base gate.sh still demands a `test`
job with result=success when tests are expected, and on the PR that
introduces the split the gate script comes from the OLD base. The real
verdicts are unit / tz-sweeps / goldens / apk / tests-ran (`coverage` is
non-blocking since audit F2 and deliberately NOT a need of this job).

<a id="job-tests-ran"></a>

### tests-ran (audit N2/N3, phase 402)

tests-ran (audit 2026-10-10, N2/N3; phase 402): proves the split test jobs
executed real (non-skipped) tests. Deliberately a SEPARATE job: the test
jobs run PR test code, which can rewrite anything in its workspace, so the
checker, its floor and the verdict must live where no PR code ever
executes. This job checks out ONLY the BASE commit (three scripts +
floor), downloads every event stream and the base-owned shard lists, and
judges them. No PR checkout, read-only token, no secrets.
Bootstrap (base lacks the script) is decided from the base checkout alone;
script present on base but stream missing/empty => RED (fail closed).

Phase 402: the unit streams arrive PER SHARD (events-unit-<i>), merged here
by artifact. Count invariant (full AND selective): tool/ci/verify_shards.sh
proves the shards ran a partition of the base-computed list; in full mode
the joined streams must also clear the min_tests.txt floor.

<a id="tests-ran-download"></a>

### tests-ran: per-artifact intake (audit S-L1)

Audit S-L1: NOT merge-multiple. Each `events-*` artifact lands in its
own sub-directory of events-dl/, and the base-owned collect_events.sh
(in the verify step) accepts from it only the ONE file name derived from
the artifact's own name. A shard that uploads another job's stream name
is rejected, never merged over it.

<a id="tests-ran-full-floor"></a>

### tests-ran: full-mode floor

Full: the SUM over all shards against the base-owned floor
(unchanged by phases 400/402; never relaxed for selective runs).
Joined only for that floor; verify_unit already judged each
stream on its own.

<a id="tests-ran-selective"></a>

### tests-ran: selective streams

Selective: the floor would always trip on a subset, so the
check is ">= 1 real test passed" PER selective stream (unit
shards, golden, Kyiv rail, Tokyo, Honolulu): an all-skipped list
is RED even when another stream passed (run_list.sh also checks
each list at run time, incl. every listed file loading as a suite).

<a id="job-ci-gate"></a>

### ci-gate (phase 397)

ci-gate (phase 397) — the ONLY required status check on dev and main.

`if: always()` so it reports even when upstream jobs are skipped. A skipped
job reports success, so a failed `plan` (which skips everything downstream)
would otherwise leave a green PR: the gate turns that red. `skipped` jobs
(patrol off, selective jobs with an empty list) are NOT failures, EXCEPT
when EXPECT_TESTS=true: then `tests-ran`, `gates-fast` and `gates` must be
success and, in a FULL run, so must unit / tz-sweeps / goldens / apk (phase
402). `coverage` is non-blocking (audit F2): a failed one is a warning. The
`test` aggregator exists only for an old base gate.sh and is not consulted
by the new one. Verdict logic lives in tool/ci/gate.sh (table-tested).
Every new job MUST be added to `needs:`.

NEVER SKIPPED, not even on an irrelevant-label (noop) event: a skipped
required check counts as passing and the newest same-named check wins, so a
skipped ci-gate could mask a red/pending real one. On noop events every other
job is skipped and ci-gate MIRRORS the real run for the same head SHA
(tool/ci/mirror.sh, base-owned), waiting for it and passing only on success.

<a id="ci-gate-timeout"></a>

### ci-gate: timeout

Normally seconds; a noop-label event waits for the real run it mirrors:
up to 3 min polling for it to appear + the watch below (200 min =
the slowest real job, `integration` at 180, plus runner QUEUE time, which
the job timeout does not cover) + verdict. Must stay
ABOVE both, or the gate dies before the thing it is mirroring.
