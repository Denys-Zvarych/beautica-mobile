#!/usr/bin/env bash
# Self-test of tool/ci/run_list.sh + tool/ci/report_failures.sh (phase 400 D2).
#
#   T1  one passing file                          -> exit 0            (real flutter)
#   T2  passing + planted failing file, | cat     -> exit != 0 and the
#       failing test's name is on stdout (non-TTY)                     (real flutter)
#   T3  list containing a missing path            -> exit != 0, flutter never runs
# plus stub-flutter cases for the exit-code combination and the stream parser
# (fast, no SDK): flutter 0 + failing stream, flutter 1 + clean stream,
# truncated stream, load error, empty list, bad path, missing stream,
# all-skipped stream, listed file with no suite event.
#   T5  one file whose only test is skipped       -> exit != 0           (real flutter)
#   T4  stale test/.run_list_selftest_<pid> dirs from a DEAD pid are swept
#       (a live pid's dir is kept)
# Real-flutter fixtures live in a throwaway Flutter package under mktemp
# (OUTSIDE the repo), so a SIGKILL that skips the EXIT trap can never leave a
# planted failing test under test/. Older versions of this script used
# test/.run_list_selftest_<pid>; those leaks are swept at startup.
# Prints `SELF-TEST OK: run_list_test.sh` on success.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
run_list="$repo/tool/ci/run_list.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp" "$repo/test/.run_list_selftest_t4_$$"' EXIT
rc=0
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }

# Removes test/.run_list_selftest_<pid> dirs whose <pid> is no longer running
# (leaked by a SIGKILLed run of an older version of this script). A leaked dir
# would be picked up by any whole-dir `flutter test`, and it holds a planted
# FAILING test. Dirs of a live pid are left alone (a concurrent run).
sweep_stale_fixtures() { # [root] (default: $repo)
  local root="${1:-$repo}" d pid
  for d in "$root"/test/.run_list_selftest_*; do
    [ -d "$d" ] || continue
    pid="${d##*_}"
    if [[ "$pid" =~ ^[0-9]+$ ]] && ps -p "$pid" >/dev/null 2>&1; then continue; fi
    rm -rf -- "$d"
    echo "  swept stale fixture dir ${d#"$root"/}"
  done
}

echo "run_list_test"
cd "$repo"
sweep_stale_fixtures

# ---- stub flutter: writes the canned stream named by $STUB_STREAM to the
# --file-reporter path, prints nothing useful, exits $STUB_RC; records argv.
stub="$tmp/flutter"
cat >"$stub" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_ARGS"
for a in "$@"; do case "$a" in --file-reporter=json:*) out="${a#--file-reporter=json:}" ;; esac; done
[ -n "${STUB_STREAM:-}" ] && cp "$STUB_STREAM" "$out"
exit "${STUB_RC:-0}"
EOF
chmod +x "$stub"

ok_stream="$tmp/ok.json"
cat >"$ok_stream" <<'EOF'
{"suite":{"id":0,"path":"test/a_test.dart"},"type":"suite"}
{"test":{"id":1,"name":"loading test/a_test.dart","suiteID":0},"type":"testStart"}
{"testID":1,"result":"success","skipped":false,"hidden":true,"type":"testDone"}
{"test":{"id":2,"name":"adds","suiteID":0},"type":"testStart"}
{"testID":2,"result":"success","skipped":false,"hidden":false,"type":"testDone"}
{"success":true,"type":"done"}
EOF
bad_stream="$tmp/bad.json"
cat >"$bad_stream" <<'EOF'
{"suite":{"id":0,"path":"test/b_test.dart"},"type":"suite"}
{"test":{"id":2,"name":"stub explodes","suiteID":0},"type":"testStart"}
{"testID":2,"error":"Expected: <2>\n  Actual: <1>","stackTrace":"b_test.dart 3:4","isFailure":true,"type":"error"}
{"testID":2,"result":"failure","skipped":false,"hidden":false,"type":"testDone"}
{"success":false,"type":"done"}
EOF
load_stream="$tmp/load.json"
cat >"$load_stream" <<'EOF'
{"suite":{"id":0,"path":"test/c_test.dart"},"type":"suite"}
{"test":{"id":1,"name":"loading test/c_test.dart","suiteID":0},"type":"testStart"}
{"testID":1,"error":"Failed to load: compile error","stackTrace":"","isFailure":false,"type":"error"}
{"testID":1,"result":"error","skipped":false,"hidden":true,"type":"testDone"}
{"success":false,"type":"done"}
EOF
# A failing test is a failure even if the `done` event claims success.
fail_done_ok_stream="$tmp/faildoneok.json"
sed 's/"success":false/"success":true/' "$bad_stream" >"$fail_done_ok_stream"
trunc_stream="$tmp/trunc.json"
head -n 5 "$ok_stream" >"$trunc_stream"
lie_stream="$tmp/lie.json"
sed 's/"success":true/"success":false/' "$ok_stream" >"$lie_stream"

# Fixtures for the stub cases must look like real test paths: run_list only
# accepts test/... or integration_test/... paths. Use a real tracked file that
# always exists; the stub never executes it.
real_file="test/ci/verify_guards_runner_test.dart"
[ -f "$real_file" ] || { echo "  FAIL  fixture $real_file missing"; exit 1; }
printf '%s\n' "$real_file" >"$tmp/one.txt"

# The clean stream's suite must be the listed file (report_failures checks
# every listed file loaded as a suite).
sed -i "s#test/a_test.dart#$real_file#g" "$ok_stream" "$trunc_stream" "$lie_stream"
skip_stream="$tmp/skip.json"
sed 's/"skipped":false,"hidden":false/"skipped":true,"hidden":false/' "$ok_stream" >"$skip_stream"
nosuite_stream="$tmp/nosuite.json"
sed "s#$real_file#test/other_test.dart#g" "$ok_stream" >"$nosuite_stream"

stub_case() { # <name> <expect: 0|nonzero> <stream|-> <stub_rc> <list> [grep-needle]
  local name="$1" want="$2" stream="$3" src="$4" list="$5" needle="${6:-}" got=0 out
  out="$(FLUTTER="$stub" STUB_ARGS="$tmp/args" STUB_RC="$src" STUB_STREAM="$([ "$stream" = - ] || echo "$stream")" \
    RUN_LIST_OUT_DIR="$tmp/out" bash "$run_list" "$list" stubrun 2>&1 | cat)" || true
  # re-run for the exit code without the pipe (set -o pipefail is not on the subshell above)
  FLUTTER="$stub" STUB_ARGS="$tmp/args" STUB_RC="$src" STUB_STREAM="$([ "$stream" = - ] || echo "$stream")" \
    RUN_LIST_OUT_DIR="$tmp/out" bash "$run_list" "$list" stubrun >/dev/null 2>&1 || got=$?
  if { [ "$want" = 0 ] && [ "$got" -eq 0 ]; } || { [ "$want" = nonzero ] && [ "$got" -ne 0 ]; }; then
    if [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$out"; then fail "$name (exit ok, '$needle' not on stdout)"; else pass "$name"; fi
  else
    fail "$name (want $want, got $got)"; printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

stub_case "stub: clean stream + flutter 0 -> 0"            0       "$ok_stream"    0 "$tmp/one.txt"
stub_case "stub: failing stream + flutter 0 -> != 0, named" nonzero "$bad_stream"   0 "$tmp/one.txt" "FAILED: test/b_test.dart: stub explodes"
stub_case "stub: failing test, done.success=true -> != 0"   nonzero "$fail_done_ok_stream" 0 "$tmp/one.txt" "FAILED: test/b_test.dart: stub explodes"
stub_case "stub: clean stream + flutter 1 -> != 0"          nonzero "$ok_stream"    1 "$tmp/one.txt"
stub_case "stub: load error (hidden test) -> != 0, named"   nonzero "$load_stream"  1 "$tmp/one.txt" "Failed to load"
stub_case "stub: truncated stream (no done) -> != 0"        nonzero "$trunc_stream" 0 "$tmp/one.txt" "no 'done' event"
stub_case "stub: done.success=false, no failing test -> != 0" nonzero "$lie_stream" 0 "$tmp/one.txt"
stub_case "stub: no stream written -> != 0"                 nonzero -               0 "$tmp/one.txt" "missing or empty"

stub_case "stub: every test skipped -> != 0"                nonzero "$skip_stream"  0 "$tmp/one.txt" "0 non-skipped tests passed"
stub_case "stub: listed file has no suite event -> != 0"    nonzero "$nosuite_stream" 0 "$tmp/one.txt" "never loaded as a suite: $real_file"
printf '%s\n' "$real_file" >"$tmp/abs_stream_list.txt"
abs_stream="$tmp/abs.json"
sed "s#\"path\":\"$real_file\"#\"path\":\"$repo/$real_file\"#" "$ok_stream" >"$abs_stream"
stub_case "stub: absolute suite path matches the listed file" 0      "$abs_stream"   0 "$tmp/abs_stream_list.txt"

: >"$tmp/empty.txt"
stub_case "empty list -> != 0 (never the whole suite)"      nonzero "$ok_stream"    0 "$tmp/empty.txt" "is empty"
printf '%s\n' "--coverage" >"$tmp/flag.txt"
stub_case "option-looking entry rejected"                   nonzero "$ok_stream"    0 "$tmp/flag.txt" "rejected path"
printf '%s\n' "test/../lib/main_test.dart" >"$tmp/dots.txt"
stub_case "'..' entry rejected"                             nonzero "$ok_stream"    0 "$tmp/dots.txt" "rejected path"
stub_case "list file missing -> != 0"                       nonzero "$ok_stream"    0 "$tmp/nope.txt" "not found"
printf '%s\n' "test/.run_list_selftest_1/planted_fail_test.dart" >"$tmp/dotdir.txt"
stub_case "dot-dir entry rejected"                          nonzero "$ok_stream"    0 "$tmp/dotdir.txt" "rejected path"

# Extra args reach flutter, files come last, every listed file is passed once.
printf '%s\n%s\n' "$real_file" "test/ci/dst_rail_ci_coverage_test.dart" >"$tmp/two.txt"
FLUTTER="$stub" STUB_ARGS="$tmp/args" STUB_RC=0 STUB_STREAM="$ok_stream" RUN_LIST_OUT_DIR="$tmp/out" \
  bash "$run_list" "$tmp/two.txt" stubrun --exclude-tags golden >/dev/null 2>&1 || true
want_args="$(printf '%s\n' test --reporter=expanded "--file-reporter=json:$tmp/out/stubrun.json" --exclude-tags golden "$real_file" test/ci/dst_rail_ci_coverage_test.dart)"
if [ "$(cat "$tmp/args")" = "$want_args" ]; then pass "argv: one invocation, extra args, all files"; else fail "argv mismatch:"; diff <(echo "$want_args") "$tmp/args" | sed 's/^/        /' || true; fi

# ---- T3: missing path -> != 0 before flutter is ever invoked.
rm -f "$tmp/args"
printf '%s\n%s\n' "$real_file" "test/definitely/not_there_test.dart" >"$tmp/missing.txt"
got=0
out="$(FLUTTER="$stub" STUB_ARGS="$tmp/args" STUB_STREAM="$ok_stream" RUN_LIST_OUT_DIR="$tmp/out" \
  bash "$run_list" "$tmp/missing.txt" t3 2>&1)" || got=$?
if [ "$got" -ne 0 ] && [ ! -e "$tmp/args" ] && grep -qF "test/definitely/not_there_test.dart" <<<"$out"; then
  pass "T3 missing path -> != 0, flutter not run, path named"
else
  fail "T3 missing path (exit $got, flutter ran: $([ -e "$tmp/args" ] && echo yes || echo no))"
fi

# ---- T4: a stale fixture dir of a DEAD pid is swept; a LIVE pid's (this
# shell's own, so a SIGKILL here leaves only a dir the next run sweeps) is kept.
true & dead_pid=$!; wait "$dead_pid" || true
dead_dir="$repo/test/.run_list_selftest_t4_$dead_pid"
live_dir="$repo/test/.run_list_selftest_t4_$$"
mkdir -p "$dead_dir" "$live_dir"
printf 'void main() {}\n' >"$dead_dir/planted_fail_test.dart"
printf 'void main() {}\n' >"$live_dir/planted_fail_test.dart"
sweep_stale_fixtures >/dev/null
if [ ! -e "$dead_dir" ] && [ -d "$live_dir" ]; then
  pass "T4 stale dir of dead pid swept, live pid's kept"
else
  fail "T4 sweep (dead kept: $([ -e "$dead_dir" ] && echo yes || echo no), live kept: $([ -d "$live_dir" ] && echo yes || echo no))"
fi
rm -rf "$live_dir"

# ---- T1 / T2: the real `flutter test` (the D2 contract is about ITS exit
# code and its non-TTY output, so a stub cannot prove it).
if ! command -v flutter >/dev/null 2>&1; then
  fail "T1/T2 need flutter on PATH"
else
  # Fixtures go in a throwaway Flutter package under $tmp (outside the repo):
  # run_list only accepts test/... paths relative to the cwd, and the files
  # resolve package:flutter_test through this package's own package config.
  pkg="$tmp/pkg"
  mkdir -p "$pkg/test"
  cat >"$pkg/pubspec.yaml" <<'EOT'
name: run_list_selftest
publish_to: none
environment:
  sdk: ^3.0.0
dev_dependencies:
  flutter_test:
    sdk: flutter
EOT
  cat >"$pkg/test/pass_test.dart" <<'EOT'
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('run_list selftest passes', () => expect(1 + 1, 2));
}
EOT
  cat >"$pkg/test/planted_fail_test.dart" <<'EOT'
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('run_list selftest PLANTED FAILURE', () => expect(1 + 1, 3));
}
EOT
  if ! (cd "$pkg" && { timeout --signal=KILL 120 flutter pub get --offline >"$tmp/pub.out" 2>&1 ||
        timeout --signal=KILL 120 flutter pub get >>"$tmp/pub.out" 2>&1; }); then
    fail "fixture package pub get"; sed 's/^/        /' "$tmp/pub.out" | tail -20
  fi
  printf 'test/pass_test.dart\n' >"$tmp/t1.txt"
  got=0
  (cd "$pkg" && timeout --signal=KILL 170 bash "$run_list" "$tmp/t1.txt" t1) >"$tmp/t1.out" 2>&1 || got=$?
  if [ "$got" -eq 0 ] && grep -q "report_failures green: 1 passed" "$tmp/t1.out"; then
    pass "T1 one passing file -> 0"
  else
    fail "T1 one passing file (exit $got)"; sed 's/^/        /' "$tmp/t1.out" | tail -20
  fi

  printf 'test/pass_test.dart\ntest/planted_fail_test.dart\n' >"$tmp/t2.txt"
  got=0
  set +o pipefail
  (cd "$pkg" && timeout --signal=KILL 170 bash "$run_list" "$tmp/t2.txt" t2) 2>&1 | cat >"$tmp/t2.out"
  got="${PIPESTATUS[0]}"
  set -o pipefail
  if [ "$got" -ne 0 ] && grep -q "^FAILED: .*planted_fail_test.dart: run_list selftest PLANTED FAILURE" "$tmp/t2.out"; then
    pass "T2 planted failure -> != 0, name on piped stdout"
  else
    fail "T2 planted failure (exit $got)"; sed 's/^/        /' "$tmp/t2.out" | tail -20
  fi

  # ---- T5: a file whose only test is skipped runs (flutter exits 0) but
  # proves nothing: RED per stream.
  cat >"$pkg/test/all_skipped_test.dart" <<'EOT'
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('run_list selftest skipped', () {}, skip: 'self-test');
}
EOT
  printf 'test/all_skipped_test.dart\n' >"$tmp/t5.txt"
  got=0
  (cd "$pkg" && timeout --signal=KILL 170 bash "$run_list" "$tmp/t5.txt" t5) >"$tmp/t5.out" 2>&1 || got=$?
  if [ "$got" -ne 0 ] && grep -q "0 non-skipped tests passed" "$tmp/t5.out"; then
    pass "T5 all-skipped file -> != 0"
  else
    fail "T5 all-skipped file (exit $got)"; sed 's/^/        /' "$tmp/t5.out" | tail -20
  fi
fi

if [ "$rc" -eq 0 ]; then echo "SELF-TEST OK: run_list_test.sh"; fi
exit "$rc"
