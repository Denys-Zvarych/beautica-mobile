#!/usr/bin/env bash
# Splits the `unit` test list into shard lists (phase 402 D2/D3/D3a). Runs in
# the `plan` job, from the BASE commit, with the BASE selector: the `unit`
# matrix jobs (which execute PR code) only ever CONSUME the lists written here.
#
#   shard_units.sh            (all input via env, like the other tool/ci scripts)
#
#   SHARD_MODE          full | selective | none        (plan's final verdict)
#   SHARD_UNIT_COUNT    selective: size of the unit list (resolve_selection.sh)
#   SHARD_THRESHOLD     selective: unit_warn_threshold from resolve_selection.sh
#                       (the single UNIT_WARN_THRESHOLD; never defaulted here)
#   SHARD_SEL_DIR       selective: dir holding the resolver's unit.txt
#   SHARD_SELECTOR_DIR  dir of the selector package (bin/affected_tests.dart)
#   SHARD_REPO          the PR tree (full: `--all` walks its test/ files; both
#                       modes: file sizes there are the shard weights, F3)
#   SHARD_RULES         rules.yaml of the BASE selector
#   SHARD_OUT_DIR       output dir (must not exist or be empty-able)
#   SHARD_DART          dart binary (default `dart`; test hook)
#
# Writes $SHARD_OUT_DIR/unit-shard-<i>.txt for i in 1..N plus unit-all.txt (the
# list the shards partition: tests-ran proves the partition from these files).
#
# Outputs (GITHUB_OUTPUT when set, always stdout):
#   unit_shards        JSON array, the `unit` matrix: [1,2,3] | ["whole"] | [1]
#   unit_shard_count   N (1 for ["whole"]; 0 when nothing is to run)
#
# Balance (audit F3): shard_units.sh asks the selector for longest-first greedy
# lists weighted by file size (`--shard-list ... --weights-root $SHARD_REPO`),
# not a count-only round-robin. The partition proof is unchanged: weights only
# move files between shards, verify_partition + tests-ran still prove the union.
#
# FAIL-SAFE (D7 spirit): an EXECUTION failure never turns the job red.
#   full       any failure (selector missing/crashing, empty shard, union
#              mismatch) -> ["whole"]: the single unit job runs the pre-400
#              whole-suite command, so the suite is never silently narrowed.
#   selective  any failure -> ONE shard holding the whole selected list.
#   none       -> [1] with count 0 (the unit job is skipped by its own `if`).
# What IS red (fail-closed, exit 2): a caller bug, i.e. SHARD_OUT_DIR unset, an
# unknown SHARD_MODE, a non-numeric SHARD_UNIT_COUNT, or a missing selective
# list file. plan then fails instead of silently running a wrong shape.
# In full mode the selector's Dart setup and pub get may have failed (phase 402
# D10, continue-on-error there): `dart` missing or unresolved is just another
# selector failure and ends in ["whole"] with the ::warning:: below.
set -uo pipefail
mode="${SHARD_MODE:-}"
out="${SHARD_OUT_DIR:-}"
dart_bin="${SHARD_DART:-dart}"
selector="${SHARD_SELECTOR_DIR:-}"
emit() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; fi
  printf '%s=%s\n' "$1" "$2"
}
# `dart bin/...` (not `dart run`): the plan job already ran `dart pub get
# --enforce-lockfile` in this package, so skip the per-call pub resolution.
sel() { (cd "$selector" && "$dart_bin" bin/affected_tests.dart "$@"); }
# split_lists <n> <fail-cmd>: shard unit-all.txt into unit-shard-1..n.txt, the n
# selector processes in parallel (each is a ~5 s JIT start); a failure of any
# one calls <fail-cmd> (which exits).
split_lists() {
  local n="$1" failcmd="$2" i pids=() bad=0
  for ((i = 1; i <= n; i++)); do
    sel --shard-list "$out/unit-all.txt" --shard "$i/$n" --out "$out/unit-shard-$i.txt" \
      ${SHARD_REPO:+--weights-root "$SHARD_REPO"} >/dev/null 2>&1 &
    pids+=($!)
  done
  for i in "${pids[@]}"; do wait "$i" || bad=1; done
  [ "$bad" -eq 0 ] || $failcmd "selector --shard-list failed"
}
seq_json() { local i s="["; for ((i = 1; i <= $1; i++)); do s+="$i"; [ "$i" -eq "$1" ] || s+=","; done; printf '%s]' "$s"; }

whole() {
  echo "::warning::selector unavailable, unsharded fallback: unit sharding unavailable ($1); running the unit suite on ONE job (pre-sharding command)"
  rm -rf "$out"
  emit unit_shards '["whole"]'
  emit unit_shard_count 1
  exit 0
}
one_shard() { # selective fallback: the whole selected list as shard 1
  echo "::warning::unit sharding unavailable ($1); running the selected unit list on ONE shard"
  rm -f "$out"/unit-shard-*.txt
  cp "$list" "$out/unit-shard-1.txt"
  emit unit_shards '[1]'
  emit unit_shard_count 1
  exit 0
}

[ -n "$out" ] || { echo "shard_units: SHARD_OUT_DIR is required" >&2; exit 2; }
case "$mode" in
  none)
    emit unit_shards '[1]'
    emit unit_shard_count 0
    exit 0 ;;
  full | selective) ;;
  *) echo "shard_units: unknown mode '$mode'" >&2; exit 2 ;;
esac
rm -rf "$out"; mkdir -p "$out"

# Verifies shards 1..n partition $out/unit-all.txt: each non-empty, together
# exactly the input, nothing doubled. Returns non-zero on any violation.
verify_partition() {
  local n="$1" i
  for ((i = 1; i <= n; i++)); do
    [ -s "$out/unit-shard-$i.txt" ] || return 1
  done
  cat "$out"/unit-shard-*.txt | LC_ALL=C sort >"$out/.joined" || return 1
  LC_ALL=C sort "$out/unit-all.txt" >"$out/.all" || return 1
  cmp -s "$out/.joined" "$out/.all" || return 1
  [ -z "$(LC_ALL=C sort "$out/.joined" | uniq -d)" ] || return 1
  rm -f "$out/.joined" "$out/.all"
}

if [ "$mode" = full ]; then
  [ -f "$selector/bin/affected_tests.dart" ] || whole "base commit has no selector"
  n="$(sel --shards-for full 2>/dev/null)" || whole "selector --shards-for failed"
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || whole "selector printed shard count '$n'"
  mkdir -p "$out/all"
  sel --all --repo "${SHARD_REPO:?}" --rules "${SHARD_RULES:?}" --out "$out/all/selection.json" >/dev/null 2>&1 \
    || whole "selector --all failed"
  [ -s "$out/all/unit.txt" ] || whole "selector --all produced an empty unit list"
  cp "$out/all/unit.txt" "$out/unit-all.txt"
  split_lists "$n" whole
  verify_partition "$n" || whole "shards do not partition the unit list"
  emit unit_shards "$(seq_json "$n")"
  emit unit_shard_count "$n"
  exit 0
fi

# selective
count="${SHARD_UNIT_COUNT:-}"
list="${SHARD_SEL_DIR:-}/unit.txt"
case "$count" in '' | *[!0-9]*) echo "shard_units: SHARD_UNIT_COUNT '$count' is not a number" >&2; exit 2 ;; esac
if [ "$count" -eq 0 ]; then
  emit unit_shards '[1]'
  emit unit_shard_count 0
  exit 0
fi
[ -f "$list" ] || { echo "shard_units: $list not found" >&2; exit 2; }
cp "$list" "$out/unit-all.txt"
[ -f "$selector/bin/affected_tests.dart" ] || one_shard "base commit has no selector"
n="$(sel --shards-for "$count" --threshold "${SHARD_THRESHOLD:-}" 2>/dev/null)" || one_shard "selector --shards-for failed"
[[ "$n" =~ ^[1-9][0-9]*$ ]] || one_shard "selector printed shard count '$n'"
if [ "$n" -eq 1 ]; then
  cp "$list" "$out/unit-shard-1.txt"
else
  split_lists "$n" one_shard
  verify_partition "$n" || one_shard "shards do not partition the unit list"
fi
emit unit_shards "$(seq_json "$n")"
emit unit_shard_count "$n"
