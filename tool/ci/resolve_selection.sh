#!/usr/bin/env bash
# Turns the selector's verdict into the `plan` job outputs (phase 400 D1/D7).
# Runs only for an effective mode=selective PR; every other event is FULL
# without asking the selector.
#
#   resolve_selection.sh <selector-exit-code> <selection.json>
#
# FAIL-SAFE (D7): a non-zero selector exit (64 bad usage, 70 internal error, or
# anything else), a missing/unreadable/invalid selection.json, an unknown mode,
# a non-string list entry, a path that is not a plain test path, or a
# self-contradicting verdict (none + non-empty lists, none with any non-`none:`
# reason, selective + all empty) => mode=full. It never falls through to
# selective or none.
#
# Unit-count warning (phase 400 P4): a selective unit list above
# UNIT_WARN_THRESHOLD files (default 80, ≈15-min edge: ~6.8 min non-unit + ~6 s/file (phase 400 D9))
# emits a ::warning:: and a summary line: it exceeds the 15-min selective
# budget (phase 402 shards such a list, D3a). Informational only, never a
# verdict. The SAME value is emitted as `unit_warn_threshold` and handed to the
# selector's `--shards-for` (phase 402 D3a): this is the only literal of it.
#
# On a valid selective/none verdict the four list files (unit.txt, golden.txt,
# tz_sweep.txt, integration.txt) are REWRITTEN from the JSON beside it, so the
# lists the unit / tz-sweeps / goldens jobs consume are exactly the counts emitted here.
#
# Outputs (GITHUB_OUTPUT when set, always stdout):
#   mode run_all unit_count golden_count tz_count integration_count
#   unit_warn_threshold   (the sanitised UNIT_WARN_THRESHOLD; selective only)
#   kyiv_count      (1 if the DST day-rail file is in the tz list, else 0;
#                   0 on every non-selective path): tests-ran owes a tz-kyiv
#                   stream from THIS base-owned value, never from PR-produced
#                   events
#   selection_count (all four lists; "unknown" for full)
#   test_count      (unit + golden + tz: what the unit, tz-sweeps and goldens jobs run; "unknown" for full)
# GITHUB_STEP_SUMMARY (when set): mode, counts, first 200 selected paths, and
# the reasons behind a full verdict.
# On PRs this script is executed from the BASE commit, never from the PR tree.
set -euo pipefail
unit_warn_default=80   # the ONE literal (phase 402 D3a)
UNIT_WARN_THRESHOLD="${UNIT_WARN_THRESHOLD:-$unit_warn_default}"
case "$UNIT_WARN_THRESHOLD" in '' | *[!0-9]* | 0) UNIT_WARN_THRESHOLD=$unit_warn_default ;; esac
# The one tz-list file the Kyiv (DST rail) step runs; must match that step.
KYIV_RAIL=test/features/booking/presentation/bookings_day_rail_test.dart
rc_in="${1:-}"; json="${2:-}"

emit() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; fi
  printf '%s=%s\n' "$1" "$2"
}
# Selector reasons and paths derive from PR-controlled file names.
md_escape() { printf '%s' "$1" | tr -c 'A-Za-z0-9._/:@ +,=>%()*-' '?' | cut -c1-200; }

summary_full() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  {
    echo "### Test selection"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| mode | \`full\` |"
    echo "| why | $(md_escape "$1") |"
    if [ -n "${2:-}" ]; then
      echo
      echo "Full reasons (selector):"
      echo
      while IFS= read -r r; do echo "- $(md_escape "$r")"; done <<<"$2"
    fi
  } >>"$GITHUB_STEP_SUMMARY"
}

full() {
  echo "::warning::test selection forced FULL: $1"
  emit mode full
  emit run_all true
  for k in unit_count golden_count tz_count integration_count selection_count test_count; do emit "$k" unknown; done
  emit kyiv_count 0
  summary_full "$1" "${2:-}"
  exit 0
}

case "$rc_in" in '' | *[!0-9]*) full "selector exit code unknown ('$(md_escape "$rc_in")')" ;; esac
[ "$rc_in" -eq 0 ] || full "selector exited $rc_in (64 = bad usage, 70 = internal error)"
[ -n "$json" ] && [ -f "$json" ] && [ ! -L "$json" ] && [ -r "$json" ] || full "selection.json missing or unreadable"
dir="$(dirname "$json")"

# Shape check in one pass; any jq error => full.
shape="$(jq -r '
  def strs: type == "array" and all(.[]; type == "string");
  if (type == "object") and (.mode | type == "string")
     and (.unit | strs) and (.golden | strs) and (.tz_sweep | strs) and (.integration | strs)
  then "ok \(.mode) \(.unit | length) \(.golden | length) \(.tz_sweep | length) \(.integration | length)"
  else "bad" end' "$json" 2>/dev/null)" || full "selection.json is not valid JSON"
read -r verdict mode nu ng nt ni <<<"$shape" || true
[ "$verdict" = "ok" ] || full "selection.json has an unexpected shape"

if [ "$mode" = "full" ]; then
  reasons="$(jq -r '.reasons // [] | map(select(.rule | test("^full|> *[0-9]+%"))) | .[] | "\(.path): \(.rule)"' "$json" 2>/dev/null || true)"
  full "selector verdict full" "$reasons"
fi
case "$mode" in none | selective) ;; *) full "selector mode '$(md_escape "$mode")' unknown" ;; esac

# Every path must be a plain test path (also enforced again by run_list.sh).
badpaths="$(jq -r '[.unit[], .golden[], .tz_sweep[], .integration[]]
  | map(select((test("^(test|integration_test)/[A-Za-z0-9_./-]+_test\\.dart$") | not) or contains("..")))
  | length' "$json")"
[ "$badpaths" = "0" ] || full "$badpaths selected path(s) are not plain test paths"

total=$((nu + ng + nt + ni))
if [ "$mode" = "none" ] && [ "$total" -ne 0 ]; then full "mode=none with $total selected path(s)"; fi
if [ "$mode" = "selective" ] && [ "$total" -eq 0 ]; then full "mode=selective with an empty selection"; fi
# D5: none = docs-only. Any reason that is not a `none:` path rule (a seed, a
# mapped/arb/golden rule, a full rule) contradicts it.
if [ "$mode" = "none" ]; then
  codereasons="$(jq -r '[.reasons // [] | .[] | select((.rule | type) != "string" or (.rule | startswith("none:") | not))] | length' "$json" 2>/dev/null || echo bad)"
  [ "$codereasons" = "0" ] || full "mode=none but $codereasons reason(s) are not docs-only (none:) rules"
fi

for k in unit golden tz_sweep integration; do
  rm -f "$dir/$k.txt"
  jq -r --arg k "$k" '.[$k][]' "$json" >"$dir/$k.txt"
done

emit mode "$mode"
emit run_all false
emit unit_count "$nu"
emit golden_count "$ng"
emit tz_count "$nt"
emit integration_count "$ni"
nk=0
if grep -qxF -- "$KYIV_RAIL" "$dir/tz_sweep.txt"; then nk=1; fi
emit kyiv_count "$nk"
emit selection_count "$total"
emit test_count "$((nu + ng + nt))"

emit unit_warn_threshold "$UNIT_WARN_THRESHOLD"
unit_warn=""
if [ "$mode" = "selective" ] && [ "$nu" -gt "$UNIT_WARN_THRESHOLD" ]; then
  unit_warn="selective unit list has $nu files (> $UNIT_WARN_THRESHOLD): the unit job is split into shards of at most this size (phase 402 D3a)"
  echo "::warning::$unit_warn"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Test selection"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| mode | \`$mode\` |"
    echo "| unit | $nu |"
    echo "| golden | $ng |"
    echo "| tz_sweep | $nt |"
    echo "| integration | $ni |"
    if [ -n "$unit_warn" ]; then
      echo
      echo "**Warning:** $unit_warn"
    fi
    if [ "$total" -gt 0 ]; then
      echo
      echo "<details><summary>Selected paths ($total; first 200 shown)</summary>"
      echo
      jq -r '(.unit | map("unit " + .)) + (.golden | map("golden " + .)) + (.tz_sweep | map("tz " + .))
             + (.integration | map("flow " + .)) | .[:200][]' "$json" |
        while IFS= read -r l; do echo "- $(md_escape "$l")"; done
      echo
      echo "</details>"
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi
