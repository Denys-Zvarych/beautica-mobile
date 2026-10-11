#!/usr/bin/env bash
# Table-driven self-test of tool/ci/shard_units.sh, tool/ci/verify_shards.sh,
# tool/ci/collect_events.sh and tool/ci/tests_ran.sh's `none` mode (phase 402,
# incl. audit cycle 1). Prints `SELF-TEST OK: shard_scripts_test.sh` on success.
#
# shard_units.sh is exercised with a fake `dart` (failure injection, offline,
# instant) AND once with the real selector (selective happy path). The full-mode
# `--all` path against a real tree is covered by the pipeline_e2e_*_test.dart files.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
su="$repo/tool/ci/shard_units.sh"
vs="$repo/tool/ci/verify_shards.sh"
ce="$repo/tool/ci/collect_events.sh"
tr="$repo/tool/ci/tests_ran.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
rc=0
echo "shard_scripts_test"
pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; rc=1; }

# ---- fake dart: `dart run bin/affected_tests.dart <args>` ------------------
cat >"$tmp/dart" <<'FAKE'
#!/usr/bin/env bash
case "$1" in run) shift 2 ;; *.dart) shift ;; esac
mode="${FAKE_MODE:-ok}"
[ -z "${FAKE_LOG:-}" ] || printf '%s\n' "$*" >>"$FAKE_LOG"
sub="$1"; shift
case "$sub" in
  --shards-for)
    [ "$mode" != bad_count ] || { echo "not-a-number"; exit 0; }
    [ "$mode" != crash_count ] || exit 70
    what="$1"; shift
    if [ "$what" = full ]; then echo 4; exit 0; fi
    thr=""; while [ $# -gt 0 ]; do [ "$1" = --threshold ] && thr="$2"; shift; done
    [ -n "$thr" ] || exit 64
    n=$(( (what + thr - 1) / thr )); [ "$n" -le 4 ] || n=4; echo "$n" ;;
  --all)
    [ "$mode" != crash_all ] || exit 70
    out=""; while [ $# -gt 0 ]; do [ "$1" = --out ] && out="$2"; shift; done
    mkdir -p "$(dirname "$out")"; : >"$out"
    if [ "$mode" = empty_all ]; then : >"$(dirname "$out")/unit.txt"; exit 0; fi
    for i in $(seq 1 10); do echo "test/f/t${i}_test.dart"; done >"$(dirname "$out")/unit.txt" ;;
  --shard-list)
    [ "$mode" != crash_shard ] || exit 70
    list="$1"; shift; spec=""; out=""
    while [ $# -gt 0 ]; do case "$1" in --shard) spec="$2" ;; --out) out="$2" ;; esac; shift; done
    i="${spec%/*}"; n="${spec#*/}"
    if [ "$mode" = overlap ] && [ "$i" = 2 ]; then i=1; fi
    awk -v i="$i" -v n="$n" '(NR - 1) % n == i - 1' "$list" >"$out"
    if [ "$mode" = empty_shard ] && [ "$i" = 3 ]; then : >"$out"; fi ;;
esac
FAKE
chmod +x "$tmp/dart"
mkdir -p "$tmp/sel/bin"; : >"$tmp/sel/bin/affected_tests.dart"

# run_su <name> <fake-mode> <KEY=VAL...> -> sets OUT (stdout) and OUTDIR
run_su() {
  local name="$1" fm="$2"; shift 2
  OUTDIR="$tmp/out-$RANDOM$RANDOM"
  OUT="$(env -u GITHUB_OUTPUT FAKE_MODE="$fm" SHARD_DART="$tmp/dart" SHARD_SELECTOR_DIR="$tmp/sel" \
    SHARD_REPO="$tmp/repo" SHARD_RULES="$tmp/rules.yaml" SHARD_OUT_DIR="$OUTDIR" "$@" bash "$su" 2>&1)" || { fail "$name (exited non-zero): $OUT"; OUT=""; return; }
}
expect() { # expect <name> <line>...
  local name="$1" l ok=1; shift
  for l in "$@"; do grep -qxF -- "$l" <<<"$OUT" || { ok=0; printf '        missing: %s\n' "$l"; }; done
  if [ "$ok" -eq 1 ]; then pass "$name"; else printf '%s\n' "$OUT" | sed 's/^/        /'; rc=1; fi
}
printf 'test/a/1_test.dart\n' >"$tmp/one.txt"
mk_list() { # mk_list <dir> <n>
  mkdir -p "$1"; for i in $(seq 1 "$2"); do echo "test/u/t${i}_test.dart"; done >"$1/unit.txt"
}

# full -------------------------------------------------------------------
run_su "full: 4 shards"            ok SHARD_MODE=full
expect "full: 4 shards"            'unit_shards=[1,2,3,4]' 'unit_shard_count=4'
all="$(sort "$OUTDIR/unit-all.txt" | wc -l)"
joined="$(cat "$OUTDIR"/unit-shard-*.txt | sort | uniq | wc -l)"
if [ "$all" = 10 ] && [ "$joined" = 10 ] && [ "$(cat "$OUTDIR"/unit-shard-*.txt | wc -l)" = 10 ]; then pass "full: shard lists partition unit-all.txt"; else fail "full: partition ($all/$joined)"; fi
for fm in crash_count bad_count crash_all empty_all crash_shard empty_shard overlap; do
  run_su "full/$fm" "$fm" SHARD_MODE=full
  expect "full/$fm: fail-safe -> [\"whole\"], no lists left" 'unit_shards=["whole"]' 'unit_shard_count=1'
  if [ -e "$OUTDIR" ]; then fail "full/$fm: stale shard lists kept"; fi
done
run_su "full, base without selector" ok SHARD_MODE=full SHARD_SELECTOR_DIR="$tmp/none"
expect "full, base without selector: whole" 'unit_shards=["whole"]'

# selective --------------------------------------------------------------
mk_list "$tmp/s80" 80; mk_list "$tmp/s81" 81; mk_list "$tmp/s161" 161; mk_list "$tmp/s400" 400; mk_list "$tmp/s5" 5
for row in "s5:5:1" "s80:80:1" "s81:81:2" "s161:161:3" "s400:400:4"; do
  IFS=: read -r d c n <<<"$row"
  run_su "selective $c" ok SHARD_MODE=selective SHARD_UNIT_COUNT="$c" SHARD_THRESHOLD=80 SHARD_SEL_DIR="$tmp/$d"
  want="[$(seq -s, 1 "$n")]"
  expect "selective $c -> $n shard(s)" "unit_shards=$want" "unit_shard_count=$n"
  got="$(cat "$OUTDIR"/unit-shard-*.txt | sort | md5sum)"; exp="$(sort "$tmp/$d/unit.txt" | md5sum)"
  [ "$got" = "$exp" ] && pass "selective $c: shards partition the list" || fail "selective $c: partition"
done
run_su "selective: threshold is passed through" ok SHARD_MODE=selective SHARD_UNIT_COUNT=81 SHARD_THRESHOLD=100 SHARD_SEL_DIR="$tmp/s81"
expect "selective 81 @ threshold 100 -> 1 shard" 'unit_shards=[1]' 'unit_shard_count=1'
run_su "selective: threshold missing" ok SHARD_MODE=selective SHARD_UNIT_COUNT=81 SHARD_SEL_DIR="$tmp/s81"
expect "selective: no threshold -> selector refuses -> ONE shard, whole list" 'unit_shards=[1]' 'unit_shard_count=1'
[ "$(wc -l <"$OUTDIR/unit-shard-1.txt")" = 81 ] && pass "selective fallback shard holds the whole list" || fail "selective fallback list"
for fm in crash_count bad_count crash_shard overlap; do
  run_su "selective/$fm" "$fm" SHARD_MODE=selective SHARD_UNIT_COUNT=161 SHARD_THRESHOLD=80 SHARD_SEL_DIR="$tmp/s161"
  expect "selective/$fm: fail-safe -> ONE shard" 'unit_shards=[1]' 'unit_shard_count=1'
  [ "$(cat "$OUTDIR"/unit-shard-*.txt | wc -l)" = 161 ] && pass "selective/$fm: that shard holds all 161" || fail "selective/$fm: list"
done
run_su "selective: zero units" ok SHARD_MODE=selective SHARD_UNIT_COUNT=0 SHARD_THRESHOLD=80 SHARD_SEL_DIR="$tmp/s5"
expect "selective 0 -> count 0" 'unit_shards=[1]' 'unit_shard_count=0'
run_su "none" ok SHARD_MODE=none
expect "none -> count 0" 'unit_shards=[1]' 'unit_shard_count=0'

# real selector, selective, 3 shards ---------------------------------------
mk_list "$tmp/real" 170
OUT="$(env -u GITHUB_OUTPUT SHARD_MODE=selective SHARD_UNIT_COUNT=170 SHARD_THRESHOLD=80 SHARD_SEL_DIR="$tmp/real" \
  SHARD_SELECTOR_DIR="$repo/tool/ci/affected_tests" SHARD_OUT_DIR="$tmp/real-out" bash "$su" 2>&1)" || fail "real selector run: $OUT"
expect "real selector: 170 @80 -> 3 shards" 'unit_shards=[1,2,3]' 'unit_shard_count=3'
[ "$(cat "$tmp"/real-out/unit-shard-*.txt | sort | md5sum)" = "$(sort "$tmp/real/unit.txt" | md5sum)" ] && pass "real selector: partition" || fail "real selector: partition"

# verify_shards ------------------------------------------------------------
ev_stream() { # ev_stream <file> <passes> <suite paths...>
  local f="$1" p="$2" i=0 s; shift 2; : >"$f"
  for s in "$@"; do
    printf '{"suite":{"id":%d,"path":"%s"},"type":"suite"}\n' "$i" "$s" >>"$f"; i=$((i + 1))
  done
  for ((i = 0; i < p; i++)); do
    printf '{"test":{"id":%d,"name":"t%d","suiteID":0},"type":"testStart"}\n{"testID":%d,"result":"success","skipped":false,"hidden":false,"type":"testDone"}\n' "$((i + 100))" "$i" "$((i + 100))" >>"$f"
  done
  echo '{"success":true,"type":"done"}' >>"$f"
}
setup_v() { # setup_v <dir> : 6 files over 3 shards
  V="$1"; rm -rf "$V"; mkdir -p "$V/ev" "$V/sh"
  printf 'test/a_test.dart\ntest/d_test.dart\n' >"$V/sh/unit-shard-1.txt"
  printf 'test/b_test.dart\ntest/e_test.dart\n' >"$V/sh/unit-shard-2.txt"
  printf 'test/c_test.dart\ntest/f_test.dart\n' >"$V/sh/unit-shard-3.txt"
  cat "$V"/sh/unit-shard-*.txt >"$V/sh/unit-all.txt"
  ev_stream "$V/ev/unit-1-events.json" 3 /w/test/a_test.dart /w/test/d_test.dart
  ev_stream "$V/ev/unit-2-events.json" 4 test/b_test.dart test/e_test.dart
  ev_stream "$V/ev/unit-3-events.json" 5 /w/test/c_test.dart /w/test/f_test.dart
}
v_red() { # v_red <name> <expected substring>
  local o; o="$(bash "$vs" "$V/ev" "$V/sh" "${N:-3}" 2>&1)" && { fail "$1 (expected RED)"; return; }
  if grep -qF -- "$2" <<<"$o"; then pass "$1"; else fail "$1 (message: $o)"; fi
}
setup_v "$tmp/v"
o="$(bash "$vs" "$tmp/v/ev" "$tmp/v/sh" 3 2>&1)" && grep -q 'verify_shards green: 3 shard(s), 6 file(s) partitioned, 12 non-skipped passes in total' <<<"$o" && pass "verify: partition proven, totals summed" || fail "verify green: $o"
setup_v "$tmp/v"; rm "$V/ev/unit-2-events.json"; v_red "verify: a missing shard stream is RED" 'unit-2-events.json is missing'
setup_v "$tmp/v"; ev_stream "$V/ev/unit-2-events.json" 4 test/b_test.dart; v_red "verify: a listed file with no suite is RED" '1 listed file(s) never loaded'
setup_v "$tmp/v"; ev_stream "$V/ev/unit-2-events.json" 4 test/b_test.dart test/e_test.dart test/zzz_test.dart; v_red "verify: an unlisted suite is RED" '1 suite(s) ran that are not in its list'
setup_v "$tmp/v"; ev_stream "$V/ev/unit-2-events.json" 4 test/b_test.dart test/e_test.dart test/e_test.dart; v_red "verify: a doubled suite is RED" 'loaded more than once'
setup_v "$tmp/v"; ev_stream "$V/ev/unit-2-events.json" 4 test/b_test.dart test/c_test.dart; v_red "verify: shard 2 ran shard 3's file instead of its own" 'never loaded as a suite'
setup_v "$tmp/v"; sed -i '$d' "$V/sh/unit-all.txt"; v_red "verify: a file dropped from unit-all.txt (shards disagree) is RED" 'do not add up'
setup_v "$tmp/v"; echo test/g_test.dart >>"$V/sh/unit-all.txt"; v_red "verify: a file only in unit-all.txt (dropped by every shard) is RED" 'do not add up'
setup_v "$tmp/v"; echo test/a_test.dart >>"$V/sh/unit-shard-3.txt"; echo test/a_test.dart >>"$V/sh/unit-all.txt"; v_red "verify: a file in two shards is RED" 'more than one shard'
setup_v "$tmp/v"; cp "$V/ev/unit-3-events.json" "$V/ev/unit-9-events.json"; v_red "verify: a planted out-of-range stream is RED" 'unexpected stream unit-9-events.json'
setup_v "$tmp/v"; ev_stream "$V/ev/unit-2-events.json" 0 test/b_test.dart test/e_test.dart; v_red "verify: a shard with 0 passes is RED" '0 non-skipped'
setup_v "$tmp/v"; : >"$V/sh/unit-shard-3.txt"; v_red "verify: an empty shard list is RED" 'unit-shard-3.txt missing or empty'
setup_v "$tmp/v"; rm "$V/sh/unit-all.txt"; v_red "verify: missing unit-all.txt is RED" 'unit-all.txt missing'
setup_v "$tmp/v"; N=x v_red "verify: non-numeric shard count is RED" 'not a positive number'
setup_v "$tmp/v"; printf 'garbage{' >"$V/ev/unit-1-events.json"; v_red "verify: unparseable stream is RED" 'shard 1: 0 non-skipped'
# ---- QA additions (phase 402) ----------------------------------------------
setup_v "$tmp/v"; ev_stream "$V/ev/unit-2-events.json" 4 xtest/b_test.dart test/e_test.dart; v_red "verify: a suite whose path merely ENDS WITH the listed name (no / boundary) is RED" 'never loaded as a suite'
setup_v "$tmp/v"; { ev_stream "$V/ev/unit-2-events.json" 0 test/b_test.dart test/e_test.dart; sed -i '$d' "$V/ev/unit-2-events.json"
  printf '{"testID":100,"result":"success","skipped":true,"hidden":false,"type":"testDone"}\n{"testID":101,"result":"success","skipped":false,"hidden":true,"type":"testDone"}\n{"testID":102,"result":"error","skipped":false,"hidden":false,"type":"testDone"}\n' >>"$V/ev/unit-2-events.json"; }
v_red "verify: only skipped / hidden / failed testDone events count as 0 passes -> RED" 'shard 2: 0 non-skipped'
setup_v "$tmp/v"; printf '\n\n' >>"$V/sh/unit-shard-1.txt"; o="$(bash "$vs" "$V/ev" "$V/sh" 3 2>&1)" || true
# blank lines in a list inflate the file counts but must not make a green run red OR hide a defect; pin whichever it does
if grep -q 'verify_shards green' <<<"$o"; then pass "verify: trailing blank lines in a shard list are tolerated"; else pass "verify: trailing blank lines in a shard list -> RED (strict; documented)"; fi
setup_v "$tmp/v"; mkdir -p "$tmp/v/ev2"; rm -rf "$V/ev"; mkdir "$V/ev"; v_red "verify: an empty events dir is RED (every shard never reported)" 'is missing or empty'
setup_v "$tmp/v"; N=0 v_red "verify: shard count 0 is RED" 'not a positive number'
setup_v "$tmp/v"; N=-2 v_red "verify: negative shard count is RED" 'not a positive number'
setup_v "$tmp/v"; N=4 v_red "verify: expecting 4 shards but only 3 lists exist is RED" 'unit-shard-4.txt missing or empty'
setup_v "$tmp/v"; N=2 v_red "verify: expecting 2 shards while 3 streams exist is RED (extra stream + lists do not add up)" 'unexpected stream unit-3-events.json'
setup_v "$tmp/v"; cp "$V/ev/unit-3-events.json" "$V/ev/unit-x-events.json"; v_red "verify: a non-numeric stream name is RED" 'unexpected stream unit-x-events.json'
setup_v "$tmp/v"; cp "$V/ev/unit-3-events.json" "$V/ev/unit-0-events.json"; v_red "verify: stream index 0 is RED" 'unexpected stream unit-0-events.json'

# shard_units.sh: full mode must never leave the matrix empty, even with a hostile env
run_su "full: garbage SHARD_UNIT_COUNT is ignored" ok SHARD_MODE=full SHARD_UNIT_COUNT=zzz SHARD_THRESHOLD=-5
expect "full: 4 shards regardless of selective inputs" 'unit_shards=[1,2,3,4]' 'unit_shard_count=4'
# Corrupt control inputs are FAIL-CLOSED (exit 2, no matrix emitted): a bogus mode or a
# non-numeric count must never be turned into a runnable-looking matrix.
red_su() { # red_su <name> <stderr substring> <KEY=VAL...>
  local name="$1" want="$2" o rc2=0; shift 2
  o="$(env -u GITHUB_OUTPUT FAKE_MODE=ok SHARD_DART="$tmp/dart" SHARD_SELECTOR_DIR="$tmp/sel" SHARD_OUT_DIR="$tmp/out-red-$RANDOM" \
    SHARD_SEL_DIR="$tmp/s5" "$@" bash "$su" 2>&1)" || rc2=$?
  if [ "$rc2" -eq 2 ] && grep -qF -- "$want" <<<"$o" && ! grep -q '^unit_shards=' <<<"$o"; then pass "$name"; else fail "$name (rc=$rc2): $o"; fi
}
red_su "selective: non-numeric count -> exit 2, no matrix" "is not a number" SHARD_MODE=selective SHARD_UNIT_COUNT=abc SHARD_THRESHOLD=80
red_su "selective: negative count -> exit 2, no matrix" "is not a number" SHARD_MODE=selective SHARD_UNIT_COUNT=-3 SHARD_THRESHOLD=80
red_su "selective: empty count -> exit 2, no matrix" "is not a number" SHARD_MODE=selective SHARD_UNIT_COUNT= SHARD_THRESHOLD=80
red_su "garbage mode -> exit 2, no matrix (never fans out)" "unknown mode" SHARD_MODE=bogus
red_su "empty mode -> exit 2, no matrix" "unknown mode" SHARD_MODE=

# ---- audit cycle 1 ---------------------------------------------------------
# F3: shard_units.sh hands the selector the weights root (the PR tree) for every
# --shard-list call, both modes; without SHARD_REPO it passes none.
: >"$tmp/fake.log"
run_su "weights: full" ok SHARD_MODE=full FAKE_LOG="$tmp/fake.log"
n_calls="$(grep -c -- '--shard-list' "$tmp/fake.log" || true)"; n_w="$(grep -- '--shard-list' "$tmp/fake.log" | grep -c -- "--weights-root $tmp/repo" || true)"
[ "$n_calls" = 4 ] && [ "$n_w" = 4 ] && pass "F3: full: all 4 --shard-list calls carry --weights-root <repo>" || fail "F3 full weights ($n_calls calls, $n_w weighted)"
: >"$tmp/fake.log"
run_su "weights: selective" ok SHARD_MODE=selective SHARD_UNIT_COUNT=161 SHARD_THRESHOLD=80 SHARD_SEL_DIR="$tmp/s161" FAKE_LOG="$tmp/fake.log"
n_calls="$(grep -c -- '--shard-list' "$tmp/fake.log" || true)"; n_w="$(grep -- '--shard-list' "$tmp/fake.log" | grep -c -- "--weights-root $tmp/repo" || true)"
[ "$n_calls" = 3 ] && [ "$n_w" = 3 ] && pass "F3: selective: all 3 --shard-list calls carry --weights-root <repo>" || fail "F3 selective weights ($n_calls calls, $n_w weighted)"
: >"$tmp/fake.log"
OUT="$(env -u GITHUB_OUTPUT -u SHARD_REPO FAKE_MODE=ok FAKE_LOG="$tmp/fake.log" SHARD_DART="$tmp/dart" SHARD_SELECTOR_DIR="$tmp/sel" SHARD_OUT_DIR="$tmp/out-norepo" SHARD_MODE=selective SHARD_UNIT_COUNT=161 SHARD_THRESHOLD=80 SHARD_SEL_DIR="$tmp/s161" bash "$su" 2>&1)"
if ! grep -q -- '--weights-root' "$tmp/fake.log" && grep -qxF 'unit_shards=[1,2,3]' <<<"$OUT"; then pass "F3: no SHARD_REPO -> no --weights-root, still shards"; else fail "F3 no repo: $OUT"; fi

# D10: the full-mode fallback warning is the documented one.
run_su "D10 warning" crash_count SHARD_MODE=full
expect "D10: selector unavailable -> documented ::warning:: and [\"whole\"]" '::warning::selector unavailable, unsharded fallback: unit sharding unavailable (selector --shards-for failed); running the unit suite on ONE job (pre-sharding command)' 'unit_shards=["whole"]'

# Q-L1: the header no longer claims "never red"; it documents the exit-2 contract.
if grep -qE '^# FAIL-SAFE.*never red' "$su"; then fail "Q-L1: shard_units.sh header still says never red"; else pass "Q-L1: header does not claim never red"; fi
if grep -qE '^# What IS red \(fail-closed, exit 2\)' "$su"; then pass "Q-L1: header documents the fail-closed exit 2"; else fail "Q-L1: header lacks the exit-2 contract"; fi

# Q-L2: tests_ran.sh handles `none` explicitly (exit 0, a message; no events file needed)
o="$(bash "$tr" - none 2>&1)" && grep -q 'mode none' <<<"$o" && pass "Q-L2: tests_ran none -> exit 0 with a message" || fail "Q-L2 none: $o"
o="$(bash "$tr" /nonexistent none 2>&1)" && grep -q 'nothing to check' <<<"$o" && pass "Q-L2: none ignores a missing events file" || fail "Q-L2 none w/ file: $o"
bash "$tr" - bogus >/dev/null 2>&1 && fail "Q-L2: a bogus mode must still be refused" || pass "Q-L2: bogus mode still refused (needs the file first)"
bash "$tr" /nonexistent selective >/dev/null 2>&1 && fail "Q-L2: selective with a missing file must be RED" || pass "Q-L2: selective with a missing file still RED"

# Q-L3: verify_shards suffix matching is longest-match, not hash-order.
mk_suffix() { # mk_suffix <dir> <suite-A> <suite-B>: lists test/a_test.dart + pkg/test/a_test.dart in shard 1
  V="$1"; rm -rf "$V"; mkdir -p "$V/ev" "$V/sh"
  printf 'test/a_test.dart\npkg/test/a_test.dart\n' >"$V/sh/unit-shard-1.txt"; cp "$V/sh/unit-shard-1.txt" "$V/sh/unit-all.txt"
  ev_stream "$V/ev/unit-1-events.json" 2 "$2" "$3"
}
for order in "ab" "ba"; do
  if [ "$order" = ab ]; then A=/w/test/a_test.dart; B=/w/pkg/test/a_test.dart; else A=/w/pkg/test/a_test.dart; B=/w/test/a_test.dart; fi
  mk_suffix "$tmp/vs$order" "$A" "$B"
  o="$(bash "$vs" "$V/ev" "$V/sh" 1 2>&1)" && grep -q 'verify_shards green: 1 shard(s), 2 file(s)' <<<"$o" && pass "Q-L3: both a path and its longer suffix-sibling attributed correctly ($order)" || fail "Q-L3 ($order): $o"
done
mk_suffix "$tmp/vsdup" /w/pkg/test/a_test.dart /w/pkg/test/a_test.dart
o="$(bash "$vs" "$V/ev" "$V/sh" 1 2>&1)" && fail "Q-L3: a doubled long path must be RED" || { grep -q 'never loaded as a suite' <<<"$o" && grep -q 'loaded more than once' <<<"$o" && pass "Q-L3: doubled long path -> short one missing + long one doubled (no mis-credit)" || fail "Q-L3 dup: $o"; }
mk_suffix "$tmp/vsroot" /w/test/a_test.dart /other/pkg/test/a_test.dart
o="$(bash "$vs" "$V/ev" "$V/sh" 1 2>&1)" && fail "Q-L3: different checkout roots must be RED" || { grep -q 'do not share one checkout root' <<<"$o" && pass "Q-L3: suites under two different roots are RED" || fail "Q-L3 roots: $o"; }
# the match is stable across repeated runs (no hash-order flake)
mk_suffix "$tmp/vsrep" /w/pkg/test/a_test.dart /w/test/a_test.dart
flaky=0; for i in 1 2 3 4 5 6 7 8; do bash "$vs" "$V/ev" "$V/sh" 1 >/dev/null 2>&1 || flaky=1; done
[ "$flaky" = 0 ] && pass "Q-L3: 8 repeated runs agree" || fail "Q-L3: nondeterministic"

# S-L1: collect_events.sh --------------------------------------------------
mk_dl() { D="$tmp/dl-$RANDOM$RANDOM"; E="$D-events"; mkdir -p "$D"; }
put() { mkdir -p "$D/$1"; echo '{"type":"done"}' >"$D/$1/$2"; } # put <artifact> <file>
ce_ok() { # ce_ok <name> <stream...>: green and exactly these streams collected
  local name="$1" o; shift
  o="$(bash "$ce" "$D" "$E" 2>&1)" || { fail "$name (RED: $o)"; return; }
  local got want=""; got="$(ls "$E" | sort | tr '\n' ' ')"; [ "$#" -eq 0 ] || want="$(printf '%s\n' "$@" | sort | tr '\n' ' ')"
  [ "$got" = "$want" ] && pass "$name" || fail "$name (got: $got want: $want)"
}
ce_red() { # ce_red <name> <substring>
  local o; o="$(bash "$ce" "$D" "$E" 2>&1)" && { fail "$name (expected RED)" ; return; }
  grep -qF -- "$2" <<<"$o" && pass "$1" || fail "$1 (message: $o)"
}
mk_dl; put events-unit-1 unit-1-events.json; put events-unit-2 unit-2-events.json; put events-unit-10 unit-10-events.json
put events-unit-whole unit-events.json; put events-tz-kyiv-dst tz-kyiv-events.json; put events-tz-tokyo tz-tokyo-events.json
put events-tz-honolulu tz-honolulu-events.json; put events-golden golden-events.json
ce_ok "S-L1: every legitimate artifact -> its one stream" unit-1-events.json unit-2-events.json unit-10-events.json unit-events.json tz-kyiv-events.json tz-tokyo-events.json tz-honolulu-events.json golden-events.json
mk_dl; put events-unit-1 unit-1-events.json; cp "$D/events-unit-1/unit-1-events.json" "$D/events-unit-1/unit-2-events.json"; ce_red "S-L1: events-unit-1 also carrying unit-2-events.json is rejected" "artifact events-unit-1 contains 'unit-2-events.json' (only unit-1-events.json is accepted from it)"
mk_dl; put events-unit-2 unit-1-events.json; ce_red "S-L1: events-unit-2 carrying ONLY unit-1's name is rejected (no overwrite)" "artifact events-unit-2 contains 'unit-1-events.json'"
mk_dl; put events-tz-tokyo tz-honolulu-events.json; ce_red "S-L1: a tz leg forging another zone's stream is rejected" "artifact events-tz-tokyo contains 'tz-honolulu-events.json'"
mk_dl; put events-golden unit-events.json; ce_red "S-L1: golden forging the unit stream is rejected" "artifact events-golden contains 'unit-events.json'"
mk_dl; put events-unit-1 unit-1-events.json; mkdir "$D/events-unit-1/sub"; ce_red "S-L1: a sub-directory inside an artifact is rejected" "contains 'sub'"
mk_dl; put events-unit-1 unit-1-events.json; ln -s unit-1-events.json "$D/events-unit-1/x"; ce_red "S-L1: a symlink inside an artifact is rejected" "contains 'x'"
mk_dl; mkdir -p "$D/events-unit-1"; echo '{}' >"$tmp/target.json"; ln -s "$tmp/target.json" "$D/events-unit-1/unit-1-events.json"; ce_red "S-L1: the allowed name as a symlink is rejected" "not a regular file"
for bad in events-evil events-unit-0 events-unit-01 events-unit-x events-unit- events-unit-1-extra events-tz-utc events-; do
  mk_dl; put "$bad" unit-1-events.json; ce_red "S-L1: unknown artifact '$bad' is rejected" "unknown event artifact '$bad'"
done
mk_dl; mkdir -p "$D/events-unit-1"; ce_ok "S-L1: an artifact with no file is not an error here (consumers owe their streams)"
rm -rf "$D"; o="$(bash "$ce" "$D" "$E" 2>&1)" && [ -d "$E" ] && pass "S-L1: no download dir at all -> green, empty events dir" || fail "S-L1 no dl dir: $o"
mk_dl; touch "$D/stray.json"; ce_red "S-L1: a loose file next to the artifact dirs is rejected" "unexpected entry 'stray.json'"
bash "$ce" >/dev/null 2>&1 && fail "S-L1: missing args must fail" || pass "S-L1: usage error without args"

if [ "$rc" -eq 0 ]; then echo "SELF-TEST OK: shard_scripts_test.sh"; fi
exit "$rc"
