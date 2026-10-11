#!/usr/bin/env bash
# Table-driven self-test of tool/ci/plan.sh and tool/ci/gate.sh (phase 397).
# Case = event x labels x changed paths (+ forced merge-base failure).
# Prints `SELF-TEST OK: plan_sh_test.sh` on success.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
plan="$repo/tool/ci/plan.sh"
gate="$repo/tool/ci/gate.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
rc=0

# case <name> <event> <labels> <expect_mode> <expect_native> <fail_mb 0|1> <paths...>
case_plan() {
  local name="$1" event="$2" labels="$3" emode="$4" enative="$5" failmb="$6"; shift 6
  local f="$tmp/changes.txt" out
  : >"$f"
  for p in "$@"; do printf 'M\t%s\n' "$p" >>"$f"; done
  out="$(env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY EVENT_NAME="$event" LABELS="$labels" \
    BASE_SHA=b HEAD_SHA=h PLAN_CHANGES_FILE="$f" PLAN_FORCE_MERGE_BASE_FAIL="$failmb" \
    PLAN_OUT_DIR="$tmp/out" bash "$plan")"
  local gmode gnative
  gmode="$(sed -n 's/^mode=//p' <<<"$out")"; gnative="$(sed -n 's/^native=//p' <<<"$out")"
  if [ "$gmode" = "$emode" ] && [ "$gnative" = "$enative" ]; then
    printf '  PASS  %s\n' "$name"
  else
    printf '  FAIL  %s (want mode=%s native=%s, got mode=%s native=%s)\n' "$name" "$emode" "$enative" "$gmode" "$gnative"
    rc=1
  fi
}

echo "plan_sh_test"
case_plan "push dev -> full"                      push              ""            full      false 0 lib/a.dart
case_plan "push main -> full"                     push              ""            full      false 0
case_plan "workflow_dispatch -> full"             workflow_dispatch ""            full      false 0
case_plan "unknown event -> full (fail-safe)"     schedule          ""            full      false 0
case_plan "PR + full-ci -> full"                  pull_request      "x,full-ci"   full      false 0 lib/a.dart
case_plan "PR plain -> selective"                 pull_request      "bug"         selective false 0 lib/a.dart
case_plan "PR label substring is not full-ci"     pull_request      "not-full-ci" selective false 0 lib/a.dart
case_plan "PR pubspec.yaml -> native"             pull_request      ""            selective true  0 pubspec.yaml
case_plan "PR android/ -> native"                 pull_request      ""            selective true  0 android/app/build.gradle
case_plan "PR nested AndroidManifest -> native"   pull_request      ""            selective true  0 foo/src/AndroidManifest.xml
case_plan "PR patrol test -> native"              pull_request      ""            selective true  0 integration_test/patrol/x_test.dart
case_plan "PR lib/routing -> native"              pull_request      ""            selective true  0 lib/routing/app_router.dart
case_plan "PR lib/main.dart -> native"            pull_request      ""            selective true  0 lib/main.dart
case_plan "PR workflow file -> native"            pull_request      ""            selective true  0 .github/workflows/pr-validate.yml
case_plan "PR other workflow -> not native"       pull_request      ""            selective false 0 .github/workflows/gitleaks.yml
case_plan "PR docs only -> not native"            pull_request      ""            selective false 0 docs/x.md lib/features/a.dart
case_plan "PR failed merge-base -> full"          pull_request      ""            full      true  1 lib/a.dart

# rename: both columns considered
printf 'R100\tlib/old.dart\tlib/routing/new.dart\n' >"$tmp/r.txt"
out="$(env -u GITHUB_OUTPUT EVENT_NAME=pull_request PLAN_CHANGES_FILE="$tmp/r.txt" PLAN_OUT_DIR="$tmp/o2" bash "$plan")"
if grep -q '^native=true$' <<<"$out"; then echo "  PASS  rename into lib/routing -> native"; else echo "  FAIL  rename native"; rc=1; fi

# run_all: selective stays run_all=true until SELECTIVE_ENABLED=true
out="$(env -u GITHUB_OUTPUT EVENT_NAME=pull_request PLAN_CHANGES_FILE="$tmp/r.txt" PLAN_OUT_DIR="$tmp/o3" bash "$plan")"
grep -q '^run_all=true$' <<<"$out" && echo "  PASS  selective + selection disabled -> run_all=true" || { echo "  FAIL  run_all default"; rc=1; }
out="$(env -u GITHUB_OUTPUT EVENT_NAME=pull_request SELECTIVE_ENABLED=true PLAN_CHANGES_FILE="$tmp/r.txt" PLAN_OUT_DIR="$tmp/o4" bash "$plan")"
grep -q '^run_all=false$' <<<"$out" && echo "  PASS  selective + selection enabled -> run_all=false" || { echo "  FAIL  run_all enabled"; rc=1; }

# gate: case_gate <name> <expect_rc> <mode> <selection_count> <needs json>
case_gate() {
  local name="$1" erc="$2" mode="$3" cnt="$4" json="$5" got=0
  EXPECT_TESTS="${EXPECT_TESTS:-}" NEEDS_JSON="$json" PLAN_MODE="$mode" PLAN_SELECTION_COUNT="$cnt" bash "$gate" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$erc" ]; then printf '  PASS  gate: %s\n' "$name"; else printf '  FAIL  gate: %s (want rc=%s got %s)\n' "$name" "$erc" "$got"; rc=1; fi
}
ok='{"plan":{"result":"success"},"validate":{"result":"success"},"patrol":{"result":"success"}}'
case_gate "all success, full -> green"          0 full      unknown "$ok"
case_gate "selective -> green"                  0 selective unknown "$ok"
case_gate "test job failed -> red"              1 full      unknown '{"plan":{"result":"success"},"validate":{"result":"success"},"test":{"result":"failure"}}'
# EXPECT_TESTS unset (legacy callers): skipped test is a non-failure.
case_gate "test skipped, EXPECT_TESTS unset -> green" 0 full unknown '{"plan":{"result":"success"},"validate":{"result":"success"},"test":{"result":"skipped"}}'
t_ok='{"plan":{"result":"success"},"test":{"result":"success"},"tests-ran":{"result":"success"}}'
tr_skip='{"plan":{"result":"success"},"test":{"result":"success"},"tests-ran":{"result":"skipped"}}'
tr_fail='{"plan":{"result":"success"},"test":{"result":"success"},"tests-ran":{"result":"failure"}}'
tr_none='{"plan":{"result":"success"},"test":{"result":"success"}}'
t_skip='{"plan":{"result":"success"},"test":{"result":"skipped"}}'
t_fail='{"plan":{"result":"success"},"test":{"result":"failure"}}'
t_none='{"plan":{"result":"success"},"validate":{"result":"success"}}'
export EXPECT_TESTS=true
case_gate "EXPECT_TESTS, test success -> green"  0 full      unknown "$t_ok"
case_gate "EXPECT_TESTS, test skipped -> red"    1 full      unknown "$t_skip"
case_gate "EXPECT_TESTS, test skipped sel -> red" 1 selective unknown "$t_skip"
case_gate "EXPECT_TESTS, test failure -> red"    1 full      unknown "$t_fail"
case_gate "EXPECT_TESTS, tests-ran skipped -> red" 1 full      unknown "$tr_skip"
case_gate "EXPECT_TESTS, tests-ran failure -> red" 1 full      unknown "$tr_fail"
case_gate "EXPECT_TESTS, tests-ran missing -> red" 1 selective unknown "$tr_none"
case_gate "EXPECT_TESTS, tests-ran success -> green" 0 selective unknown "$t_ok"
case_gate "EXPECT_TESTS, test missing -> red"    1 full      unknown "$t_none"
export EXPECT_TESTS=false
case_gate "EXPECT_TESTS=false, test skipped -> green" 0 full unknown "$t_skip"
unset EXPECT_TESTS
case_gate "patrol skipped -> green"             0 full      unknown '{"plan":{"result":"success"},"validate":{"result":"success"},"patrol":{"result":"skipped"}}'
case_gate "plan failed -> red"                  1 ""        ""      '{"plan":{"result":"failure"},"validate":{"result":"skipped"},"patrol":{"result":"skipped"}}'
case_gate "plan skipped -> red"                 1 full      unknown '{"plan":{"result":"skipped"},"validate":{"result":"skipped"}}'
case_gate "a job failed -> red"                 1 full      unknown '{"plan":{"result":"success"},"validate":{"result":"failure"}}'
case_gate "a job cancelled -> red"              1 full      unknown '{"plan":{"result":"success"},"validate":{"result":"cancelled"}}'
case_gate "empty mode -> red (fail closed)"     1 ""        unknown "$ok"
case_gate "garbage mode -> red"                 1 skip      0       "$ok"
case_gate "mode=none with count 0 -> green"     0 none      0       "$ok"
case_gate "mode=none, count unknown -> red"     1 none      unknown "$ok"
case_gate "mode=none, count 3 -> red"           1 none      3       "$ok"
case_gate "mode=none, count missing -> red"     1 none      ""      "$ok"

# Workflow guard (`is_forced` in pr-validate.yml `plan` job): extracted verbatim
# and table-tested, so the inline CI-machinery guard cannot silently lose a path.
wf="$repo/.github/workflows/pr-validate.yml"
# extract_fn <name>: pull one shell function out of the workflow and LOAD it.
# Fails loudly (returns 1, prints why) when the extraction cannot be trusted: a
# reformat/rename that makes sed match nothing, a truncated range, a duplicate
# definition, a syntax error, or a body that does not define <name>.
extract_fn() {
  local name="$1" out="$tmp/$1.sh" n
  n="$(grep -cE "^ *${name}\(\) \{\$" "$wf" || true)"
  if [ "$n" != "1" ]; then echo "  FAIL  extract: expected exactly 1 '$name() {' in pr-validate.yml, found $n"; return 1; fi
  sed -n "/^ *${name}() {\$/,/^ *}\$/p" "$wf" >"$out"
  if [ ! -s "$out" ]; then echo "  FAIL  extract: $name() extracted EMPTY"; return 1; fi
  if [ "$(wc -l <"$out")" -lt 3 ]; then echo "  FAIL  extract: $name() extracted <3 lines"; return 1; fi
  local first last arms
  first="$(head -n1 "$out")"
  last="$(tail -n1 "$out")"
  if ! [[ "$first" =~ ^\ *${name}\(\)\ \{$ ]]; then echo "  FAIL  extract: $name() first line is not its definition"; return 1; fi
  if ! [[ "$last" =~ ^\ *\}$ ]]; then echo "  FAIL  extract: $name() last line is not a closing brace"; return 1; fi
  # A truncated-but-parsable range would still pass bash -n: require the body to
  # keep at least the current number of case arms (is_forced has 6; floor = 6).
  if [ "$name" = is_forced ]; then
    arms="$(grep -cE '\) return [01] ;;$' "$out" || true)"
    if [ "$arms" -lt 6 ]; then echo "  FAIL  extract: $name() has $arms case arms, expected >= 6 (truncated?)"; return 1; fi
  fi
  if ! bash -n "$out" 2>/dev/null; then echo "  FAIL  extract: $name() does not parse (truncated range?)"; return 1; fi
  # shellcheck disable=SC1090
  . "$out"
  if ! declare -F "$name" >/dev/null; then echo "  FAIL  extract: sourcing did not define $name"; return 1; fi
  echo "  PASS  extract: $name() loaded from pr-validate.yml"
}
if extract_fn is_forced; then
  case_forced() { # <name> <want 0|1> <path>
    local got=0; is_forced "$3" || got=$?
    if [ "$got" -eq "$2" ]; then printf '  PASS  guard: %s\n' "$1"; else printf '  FAIL  guard: %s (%s want %s got %s)\n' "$1" "$3" "$2" "$got"; rc=1; fi
  }
  case_forced "workflow forces full"       0 .github/workflows/pr-validate.yml
  case_forced "CODEOWNERS forces full"     0 .github/CODEOWNERS
  case_forced "tool/ci forces full"        0 tool/ci/plan.sh
  case_forced "scripts forces full"        0 scripts/forbid_x.sh
  case_forced "scripts/perf exempt"        1 scripts/perf/measure_startup.sh
  case_forced "analysis_options forces"    0 analysis_options.yaml
  case_forced "pubspec.yaml forces"        0 pubspec.yaml
  case_forced "pubspec.lock forces"        0 pubspec.lock
  case_forced "dart_test.yaml forces"      0 dart_test.yaml
  case_forced "build.yaml forces"          0 build.yaml
  case_forced "flutter_test_config forces" 0 test/flutter_test_config.dart
  case_forced "test/helpers forces"        0 test/helpers/fake_clock.dart
  case_forced "integration_test/support forces" 0 integration_test/support/app_harness.dart
  case_forced "test/ci forces"             0 test/ci/x_test.dart
  case_forced "gradle wrapper forces"      0 android/gradle/wrapper/gradle-wrapper.properties
  case_forced "gradle.properties forces"   0 android/gradle.properties
  case_forced "non-ASCII path (plain) does not" 1 lib/маршрут.dart
  case_forced "test_driver forces"         0 test_driver/integration_test.dart
  case_forced "plain lib file does not"    1 lib/features/a.dart
  case_forced "plain test file does not"   1 test/features/a_test.dart
  case_forced "docs do not"                1 docs/x.md
  # is_forbidden: committed build output / tool cache fails the plan (fail closed).
  if extract_fn is_forbidden; then
    case_forbidden() { # <name> <want 0|1> <path>
      local got=0; is_forbidden "$3" || got=$?
      if [ "$got" -eq "$2" ]; then printf '  PASS  forbidden: %s\n' "$1"; else printf '  FAIL  forbidden: %s (%s want %s got %s)\n' "$1" "$3" "$2" "$got"; rc=1; fi
    }
    case_forbidden "build/ci/changes.txt forbidden" 0 build/ci/changes.txt
    case_forbidden "build/ itself forbidden"        0 build/x
    case_forbidden ".dart_tool forbidden"           0 .dart_tool/package_config.json
    case_forbidden "lib/build_x.dart ok"            1 lib/build_x.dart
    case_forbidden "api/.dart_tool nested ok (tracked)" 1 api/.dart_tool/package_config.json
    case_forbidden "plain lib file ok"              1 lib/a.dart
  else
    rc=1
  fi
  # The guard must fail (exit 1) on a forbidden path, before any force-full.
  grep -qE 'is_forbidden "\$f"' "$wf" && echo "  PASS  guard calls is_forbidden" || { echo "  FAIL  guard does not call is_forbidden"; rc=1; }
else
  rc=1
fi

# Every actions/checkout step must set `persist-credentials: false` (the token
# must not sit in .git/config readable by PR code). No allow-list: no job here
# needs authenticated git after checkout (plan uses merge-base/diff on fetched history).
for cf in "$repo/.github/workflows/pr-validate.yml" "$repo/.github/workflows/nightly.yml"; do
  [ -f "$cf" ] || continue
  total="$(grep -c 'uses: actions/checkout@' "$cf" || true)"
  # a step ends at the next `      - ` list item; count checkout steps whose block has the flag
  okc="$(awk '
    function flush() { if (inco && flag) good++; inco=0; flag=0 }
    /^      - / { flush() }
    /uses: actions\/checkout@/ { inco=1 }
    inco && /^ +persist-credentials: false[[:space:]]*$/ { flag=1 }
    END { flush(); print good+0 }' "$cf")"
  if [ "$total" -eq "$okc" ]; then echo "  PASS  persist-credentials: false on all $total checkouts: $(basename "$cf")"
  else echo "  FAIL  persist-credentials: only $okc of $total checkouts in $(basename "$cf")"; rc=1; fi
done

# Label gating: only full-ci / run-patrol labelled events may run anything.
# Extract the relevance condition from the workflow and require it everywhere
# a job could start heavy work.
rel="(github.event.action != 'labeled' || github.event.label.name == 'full-ci' || github.event.label.name == 'run-patrol')"
for job in plan validate test integration integration-profile; do
  body="$(awk -v j="  $job:" '$0==j{f=1;next} f&&/^  [a-z-]+:$/{exit} f' "$wf")"
  if grep -qF "$rel" <<<"$body"; then
    echo "  PASS  label gate on job: $job"
  else echo "  FAIL  label gate missing on job: $job"; rc=1; fi
done
# ci-gate must NEVER be skipped (a skipped required check reads as passing and
# can mask a red real one): `if: always()` with no label condition.
cg_if="$(awk '/^  ci-gate:/{f=1;next} f&&/^    if:/{print;exit}' "$wf")"
[ "$cg_if" = "    if: always()" ] && echo "  PASS  ci-gate is never skipped" || { echo "  FAIL  ci-gate if: '$cg_if'"; rc=1; }
cg_body="$(awk '/^  ci-gate:/{f=1} f' "$wf")"
grep -qF "actions: read" <<<"$cg_body" && echo "  PASS  ci-gate has actions: read" || { echo "  FAIL  ci-gate actions: read"; rc=1; }
grep -qF "run-name:" "$wf" && grep -qF "label-noop PR" "$wf" && echo "  PASS  noop run-name title" || { echo "  FAIL  noop run-name"; rc=1; }
grep -qE 'EXPECT_TESTS: \$\{\{' <<<"$cg_body" && echo "  PASS  ci-gate passes EXPECT_TESTS" || { echo "  FAIL  EXPECT_TESTS env"; rc=1; }
grep -qF 'mirror.sh verdict' <<<"$cg_body" && echo "  PASS  ci-gate mirrors via mirror.sh" || { echo "  FAIL  mirror wiring"; rc=1; }
grep -qF 'mirror.sh select "$PR_NUMBER"' <<<"$cg_body" && grep -qF 'attempt" -eq 6' <<<"$cg_body" && grep -qF 'sleep 30' <<<"$cg_body" && echo "  PASS  mirror polls 6x30s, PR-scoped" || { echo "  FAIL  mirror poll loop / PR scoping"; rc=1; }
grep -qF -- '--interval 60' <<<"$cg_body" && grep -qF 'timeout --signal=KILL 12000' <<<"$cg_body" && grep -qF 'timeout-minutes: 205' <<<"$cg_body" && echo "  PASS  mirror watch 200 min / gate 205 min" || { echo "  FAIL  mirror/gate timeouts"; rc=1; }
for j in integration integration-profile; do
  body="$(awk -v j="  $j:" '$0==j{f=1;next} f&&/^  [a-z-]+:$/{exit} f' "$wf")"
  grep -qE '^    timeout-minutes: [0-9]+' <<<"$body" && echo "  PASS  timeout-minutes on job: $j" || { echo "  FAIL  timeout-minutes missing on job: $j"; rc=1; }
done
test_body="$(awk '$0=="  test:"{f=1;next} f&&/^  [a-z-]+:$/{exit} f' "$wf")"
grep -qF 'file-reporter=json:build/ci/unit-events.json' <<<"$test_body" && grep -qF 'name: unit-events' <<<"$test_body" && echo "  PASS  test job: json reporter + stream upload" || { echo "  FAIL  test job stream wiring"; rc=1; }
grep -qE '^    timeout-minutes: [0-9]+' <<<"$test_body" && echo "  PASS  timeout-minutes on job: test" || { echo "  FAIL  timeout-minutes missing on job: test"; rc=1; }
# N2/N3: no trusted tooling inside the PR workspace; the verdict lives in a job that never checks out PR code.
if grep -qF '.ci-trusted' "$wf" || grep -qF 'tests_ran.sh' <<<"$test_body"; then echo "  FAIL  .ci-trusted / tests_ran.sh reachable from the test job"; rc=1; else echo "  PASS  no .ci-trusted in the test job"; fi
tr_body="$(awk '$0=="  tests-ran:"{f=1;next} f&&/^  [a-z-]+:$/{exit} f' "$wf")"
if [ -n "$tr_body" ] && [ "$(grep -c 'uses: actions/checkout@' <<<"$tr_body")" -eq 1 ] && grep -qF 'ref: ${{ github.event.pull_request.base.sha || github.sha }}' <<<"$tr_body" && grep -qF 'tool/ci/tests_ran.sh' <<<"$tr_body" && grep -qF 'needs: [plan, test]' <<<"$tr_body" && grep -qF 'contents: read' <<<"$tr_body"; then echo "  PASS  tests-ran job: base-only checkout, read-only"; else echo "  FAIL  tests-ran job shape (single base checkout / needs / perms)"; rc=1; fi
# no expression interpolation inside any ci-gate run: block
if [ -n "$(awk '/^        run: \|/{r=1;next} /^      - name:/{r=0} r&&/\$\{\{/' <<<"$cg_body")" ]; then echo "  FAIL  \${{ }} inside ci-gate run:"; rc=1; else echo "  PASS  no \${{ }} in ci-gate run:"; fi
grep -qF "&& '-noop')" "$wf" && ! grep -qF "format('-noop-" "$wf" && echo "  PASS  noop label group is fixed per PR" || { echo "  FAIL  noop label group"; rc=1; }
grep -qF "format('-{0}', github.run_id)" "$wf" && echo "  PASS  dispatch group is unique" || { echo "  FAIL  dispatch group"; rc=1; }
# ci-gate must require every job it required before the split, plus `test`.
gate_body="$(awk '/^  ci-gate:/{f=1} f' "$wf")"
for j in plan validate test tests-ran integration integration-profile patrol; do
  grep -qE "^    needs: \[.*\b$j\b.*\]" <<<"$gate_body" && echo "  PASS  ci-gate needs $j" || { echo "  FAIL  ci-gate needs $j"; rc=1; }
done

# mirror.sh (noop-label mirror mode): case_sel <name> <want id|""> <current> <json>
mirror="$repo/tool/ci/mirror.sh"
case_sel() { # <name> <want id|""> <current> <pr> <json>
  local got; got="$(printf '%s' "$5" | CURRENT_RUN_ID="$3" bash "$mirror" select "$4")"
  if [ "$got" = "$2" ]; then printf '  PASS  mirror select: %s\n' "$1"; else printf '  FAIL  mirror select: %s (want %s got %s)\n' "$1" "$2" "$got"; rc=1; fi
}
case_verdict() { # <name> <want rc> <status> <conclusion>
  local got=0; bash "$mirror" verdict "$3" "$4" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$2" ]; then printf '  PASS  mirror verdict: %s\n' "$1"; else printf '  FAIL  mirror verdict: %s (want %s got %s)\n' "$1" "$2" "$got"; rc=1; fi
}
# run <id> <event> <title> <pr numbers, comma-sep or empty> [path]
run() {
  local prs="" sep="" n
  IFS=, read -ra arr <<<"$4"
  for n in "${arr[@]}"; do [ -n "$n" ] || continue; prs+="$sep{\"number\":$n}"; sep=","; done
  printf '{"id":%s,"event":"%s","display_title":"%s","path":"%s","status":"completed","conclusion":"success","pull_requests":[%s]}' \
    "$1" "$2" "$3" "${5:-.github/workflows/pr-validate.yml}" "$prs"
}
mk() { local out="" sep=""; for r in "$@"; do out+="$sep$r"; sep=","; done; printf '{"workflow_runs":[%s]}' "$out"; }
r1="$(run 10 pull_request "Fix x" 7)"
r2="$(run 20 pull_request "Fix x" 7)"
rn="$(run 30 pull_request "label-noop PR 7" 7)"
rc_="$(run 40 pull_request "Fix x" 7)"
rp="$(run 50 push "Fix x" "")"
ro="$(run 60 pull_request "Fix x" 8)"
rw="$(run 70 pull_request "Fix x" 7 .github/workflows/other.yml)"
rm_="$(run 80 pull_request "Fix x" "7,8")"
rf="$(run 90 pull_request "Fix x" "")"
case_sel "no runs -> none"                    ""   99 7 '{"workflow_runs":[]}'
case_sel "missing key -> none"                ""   99 7 '{}'
case_sel "picks latest real run"              20   99 7 "$(mk "$r1" "$r2")"
case_sel "excludes noop runs"                 20   99 7 "$(mk "$r1" "$r2" "$rn")"
case_sel "excludes current run"               20   40 7 "$(mk "$r1" "$r2" "$rc_")"
case_sel "only noop + current -> none"        ""   40 7 "$(mk "$rn" "$rc_")"
case_sel "excludes non-pull_request events"   20   99 7 "$(mk "$r1" "$r2" "$rp")"
case_sel "only a push run -> none"            ""   99 7 "$(mk "$rp")"
case_sel "PR scoping: other PR's run ignored" 20   99 7 "$(mk "$r1" "$r2" "$ro")"
case_sel "PR scoping: only other PR -> none"  ""   99 7 "$(mk "$ro")"
case_sel "PR scoping: run shared by two PRs"  80   99 7 "$(mk "$r2" "$rm_")"
case_sel "other workflow ignored"             ""   99 7 "$(mk "$rw")"
case_sel "empty pull_requests (fork) -> none" ""   99 7 "$(mk "$rf")"
bad=0; echo '{}' | CURRENT_RUN_ID=1 bash "$mirror" select 'x;1' >/dev/null 2>&1 || bad=$?
[ "$bad" -eq 2 ] && echo "  PASS  mirror select: non-numeric PR rejected" || { echo "  FAIL  mirror select: non-numeric PR (rc $bad)"; rc=1; }
case_verdict "completed success -> green"     0 completed success
case_verdict "completed failure -> red"       1 completed failure
case_verdict "cancelled -> red"               1 completed cancelled
case_verdict "in_progress -> red"             1 in_progress ""
case_verdict "skipped -> red"                 1 completed skipped
case_verdict "empty -> red"                   1 "" ""

# L2: non-ASCII / hostile paths through the REAL git diff (no fixture hook).
g="$tmp/repo"; mkdir -p "$g/lib/routing"; git -C "$g" init -q
git -C "$g" config user.email t@t; git -C "$g" config user.name t
echo a >"$g/a.txt"; git -C "$g" add -A; git -C "$g" commit -qm base
git -C "$g" tag base
mkdir -p "$g/lib/routing"; echo x >"$g/lib/routing/маршрут.dart"; echo y >"$g/docs ü.md"
git -C "$g" add -A; git -C "$g" commit -qm head
out="$(cd "$g" && env -u GITHUB_OUTPUT EVENT_NAME=pull_request BASE_SHA="$(git rev-parse base)" HEAD_SHA="$(git rev-parse HEAD)" PLAN_OUT_DIR="$tmp/o6" bash "$plan")"
if grep -q '^native=true$' <<<"$out" && grep -q '^mode=selective$' <<<"$out" && grep -qF $'A\tlib/routing/маршрут.dart' "$tmp/o6/changes.txt"; then
  echo "  PASS  non-ASCII path under lib/routing -> native (unquoted)"; else echo "  FAIL  non-ASCII path"; cat "$tmp/o6/changes.txt"; rc=1; fi
git -C "$g" mv "docs ü.md" "lib/routing/ё.md"; git -C "$g" commit -qm ren
out="$(cd "$g" && env -u GITHUB_OUTPUT EVENT_NAME=pull_request BASE_SHA="$(git rev-parse HEAD~1)" HEAD_SHA="$(git rev-parse HEAD)" PLAN_OUT_DIR="$tmp/o7" bash "$plan")"
grep -qF $'R100\tdocs ü.md\tlib/routing/ё.md' "$tmp/o7/changes.txt" && grep -q '^native=true$' <<<"$out" && echo "  PASS  non-ASCII rename recorded with both paths" || { echo "  FAIL  non-ASCII rename"; cat "$tmp/o7/changes.txt"; rc=1; }
printf 'z' >"$g/tab"$'\t'"name"; git -C "$g" add -A; git -C "$g" commit -qm tab
out="$(cd "$g" && env -u GITHUB_OUTPUT EVENT_NAME=pull_request BASE_SHA="$(git rev-parse HEAD~1)" HEAD_SHA="$(git rev-parse HEAD)" PLAN_OUT_DIR="$tmp/o8" bash "$plan")"
grep -q '^mode=full$' <<<"$out" && echo "  PASS  TAB in path -> fail-safe full" || { echo "  FAIL  TAB path"; rc=1; }

# tests_ran.sh: all-skipped -> red, normal -> green, floor, selective.
tr_="$repo/tool/ci/tests_ran.sh"
td() { printf '{"type":"testDone","testID":%s,"result":"%s","skipped":%s,"hidden":%s,"time":1}\n' "$1" "$2" "$3" "$4"; }
{ td 1 success true false; td 2 success true false; td 3 success false true; echo 'noise'; } >"$tmp/skipped.json"
{ td 1 success false false; td 2 success false false; td 3 success true false; td 4 error false false; td 5 success false true; } >"$tmp/normal.json"
: >"$tmp/empty.json"
echo 2 >"$tmp/floor2"; echo 3 >"$tmp/floor3"; echo abc >"$tmp/floorbad"
case_tr() { # <name> <want rc> <args...>
  local n="$1" w="$2" got=0; shift 2
  bash "$tr_" "$@" >/dev/null 2>&1 || got=$?
  if [ "$got" -eq "$w" ]; then printf '  PASS  tests_ran: %s\n' "$n"; else printf '  FAIL  tests_ran: %s (want %s got %s)\n' "$n" "$w" "$got"; rc=1; fi
}
case_tr "all skipped (full) -> red"          1 "$tmp/skipped.json" full "$tmp/floor2"
case_tr "all skipped (selective) -> red"     1 "$tmp/skipped.json" selective
case_tr "empty stream -> red"                1 "$tmp/empty.json" selective
case_tr "missing file -> red"                1 "$tmp/nope.json" selective
case_tr "normal, floor met (2) -> green"     0 "$tmp/normal.json" full "$tmp/floor2"
case_tr "normal, below floor (3) -> red"     1 "$tmp/normal.json" full "$tmp/floor3"
case_tr "normal selective -> green"          0 "$tmp/normal.json" selective
case_tr "bad floor file -> red"              1 "$tmp/normal.json" full "$tmp/floorbad"
case_tr "missing floor file -> red"          1 "$tmp/normal.json" full "$tmp/nofloor"
case_tr "bad mode -> usage"                  2 "$tmp/normal.json" bogus
[ -s "$repo/tool/ci/min_tests.txt" ] && [ -z "$(tr -d '0-9\n' <"$repo/tool/ci/min_tests.txt")" ] && echo "  PASS  min_tests.txt is a number" || { echo "  FAIL  min_tests.txt"; rc=1; }

# Output-path hardening (security F1): plan.sh never writes inside the PR tree.
case_planrc() { # <name> <want rc 0|1> <cwd> <outdir env or UNSET>
  local n="$1" w="$2" cwd="$3" od="$4" got=0
  if [ "$od" = UNSET ]; then
    (cd "$cwd" && env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY -u PLAN_OUT_DIR EVENT_NAME=push bash "$plan") >/dev/null 2>&1 || got=$?
  else
    (cd "$cwd" && env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY EVENT_NAME=push PLAN_OUT_DIR="$od" bash "$plan") >/dev/null 2>&1 || got=$?
  fi
  if [ "$got" -eq "$w" ]; then printf '  PASS  out-dir: %s\n' "$n"; else printf '  FAIL  out-dir: %s (want rc=%s got %s)\n' "$n" "$w" "$got"; rc=1; fi
}
tree="$tmp/tree"; mkdir -p "$tree/build" "$tmp/trusted" "$tmp/okout"
echo 'KEEP' >"$tmp/trusted/plan.sh"
# (a) symlinked output path -> plan fails and the target is untouched
ln -s "$tmp/trusted/plan.sh" "$tree/build/changes.txt"
mkdir -p "$tmp/linkdir"; ln -s "$tmp/linkdir" "$tree/build/ci"
case_planrc "symlinked out dir -> fail"           1 "$tree" "$tree/build/ci"
case_planrc "out dir inside the tree -> fail"     1 "$tree" "$tree/build/real"
case_planrc "PLAN_OUT_DIR unset -> fail"          1 "$tree" UNSET
ln -s "$tmp/trusted/plan.sh" "$tmp/okout/changes.txt"
case_planrc "symlinked changes.txt -> link replaced, target intact" 0 "$tree" "$tmp/okout"
[ "$(cat "$tmp/trusted/plan.sh")" = KEEP ] && echo "  PASS  out-dir: symlink target not written through" || { echo "  FAIL  out-dir: wrote through symlink"; rc=1; }
[ ! -L "$tmp/okout/changes.txt" ] && echo "  PASS  out-dir: changes.txt is a plain file after run" || { echo "  FAIL  out-dir: changes.txt still a symlink"; rc=1; }
# (b) normal run writes only to the out dir, nothing under the tree
mkdir -p "$tmp/clean"; : >"$tmp/clean/.keep"
rm -rf "$tmp/okout2"
(cd "$tmp/clean" && env -u GITHUB_OUTPUT EVENT_NAME=push PLAN_OUT_DIR="$tmp/okout2" bash "$plan") >/dev/null
[ -f "$tmp/okout2/changes.txt" ] && [ "$(find "$tmp/clean" -mindepth 1 | wc -l)" -eq 1 ] && echo "  PASS  out-dir: normal run writes outside the tree only" || { echo "  FAIL  out-dir: normal run"; rc=1; }
# plan exposes the dir for phase 400
out="$(cd "$tmp/clean" && env -u GITHUB_OUTPUT EVENT_NAME=push PLAN_OUT_DIR="$tmp/okout2" bash "$plan")"
grep -q "^changes_dir=$(cd -P "$tmp/okout2" && pwd -P)$" <<<"$out" && echo "  PASS  out-dir: changes_dir emitted" || { echo "  FAIL  out-dir: changes_dir"; rc=1; }

# md_escape: PR-controlled text must not reach the summary raw.
out="$(env -u GITHUB_OUTPUT GITHUB_STEP_SUMMARY="$tmp/sum.md" EVENT_NAME=pull_request BASE_SHA='a`$(x)|<b>' HEAD_SHA=h PLAN_FORCE_MERGE_BASE_FAIL=1 PLAN_CHANGES_FILE="$tmp/r.txt" PLAN_OUT_DIR="$tmp/o5" bash "$plan")"
val="$(grep 'base (merge-base)' "$tmp/sum.md" | sed 's/^[^`]*`//; s/`[^`]*$//')"
if [ -n "$val" ] && [[ "$val" != *'`'* && "$val" != *'$'* && "$val" != *'<'* && "$val" != *'|'* && "$val" != *'('* ]]; then echo "  PASS  summary escapes hostile base value"; else echo "  FAIL  summary escaping ($val)"; rc=1; fi

if [ "$rc" -eq 0 ]; then echo "SELF-TEST OK: plan_sh_test.sh"; fi
exit "$rc"
