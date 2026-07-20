#!/usr/bin/env bash
# Stale-future-date fixture gate (booking-detail time-bomb safeguard,
# 2026-07-20 incident).
#
# THE FRAGILITY THIS GUARDS
# --------------------------
# `DateTime.utc(2026, 7, 20, 15)`-style ABSOLUTE literals used as a booking's
# `startAt`/`start`/`startsAt` fixture look deterministic but are actually a
# TIME BOMB: `BookingDisplayX.isPast` compares against the REAL wall clock
# (`DateTime.now()`), so the instant the literal's instant passes, every
# assertion that depends on the booking reading as "upcoming"
# (reschedule/cancel/add-to-calendar visible, the forward-looking subline,
# etc.) silently flips from a real assertion to a false negative — the suite
# goes red on a DATE, not a code change, and stays red on every run after.
#
# This happened for real on 2026-07-20: four booking-detail specs had each
# independently hand-rolled the same expired `DateTime.utc(2026, 7, 20, 15)`
# literal (16 failures). The fix anchors "upcoming" fixtures to
# `DateTime.now()` plus an offset via the shared
# `futureBookingStart()` helper (test/helpers/booking_fixture_dates.dart)
# instead — this gate stops the next hand-rolled absolute future literal from
# re-entering the corpus.
#
# THE RULE
# --------
# No `DateTime.utc(YYYY, ...)` literal with YYYY >= the CURRENT year is
# allowed under `test/features/booking/`. Use a `DateTime.now()`-relative
# offset instead — `futureBookingStart()` for the common case.
#
# A fixed PAST literal (YYYY < current year, e.g. `DateTime.utc(2000, 1, 1)`)
# is exempt automatically: it can never become "upcoming" again, so it isn't
# a time bomb.
#
# A small number of sites deliberately need a fixed FAR-future instant rather
# than a now-relative one (e.g. a suite proving BOTH sides of `isPast`'s
# boundary need to stay deterministic relative to EACH OTHER, not just to
# "now"). Those are unblocked with a `// future-date-ok: <reason>` comment on
# the same line or the line directly above — same convention as
# `forbid_fixed_wait.sh`'s `fixed-wait-ok`.
#
# LEGACY BASELINE (ratchet, not a big-bang rewrite)
# -------------------------------------------------
# `test/features/booking/` predates this gate and carries a large body of
# fixed-future-instant fixtures written before the rule existed — most of
# them anchor unrelated logic (lane layout, slot repositories, timezone
# math) that never reads `isPast`, so they aren't live time bombs today, but
# rewriting ~30 files in one pass is out of scope and risky here. So this
# gate is a RATCHET, same shape as `forbid_fixed_wait.sh`: the file list in
# `scripts/.stale_future_date_allow` GRANDFATHERS the existing offending
# files; the gate enforces on every OTHER file in the scan root. When a
# grandfathered file is next meaningfully touched, drop it from the
# allow-list and convert its literal(s) to `futureBookingStart()` (or
# annotate a genuinely-deliberate fixed instant with `future-date-ok`). New
# files are gated from line one; the baseline only ever shrinks.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_stale_future_date_fixture.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
allow_file="$here/.stale_future_date_allow"

# Match: DateTime.utc(  followed by a 4-digit year. POSIX ERE: literal `(` is
# `[(]`. `[0-9][0-9][0-9][0-9]` (not `{4}`) for portability across awk
# implementations that don't support interval regex by default.
pattern='DateTime[.]utc[(][[:space:]]*[0-9][0-9][0-9][0-9]'
# Annotation: `// future-date-ok:` (any leading whitespace before the `//`).
annotation='[/][/][[:space:]]*future-date-ok:'

# ---------------------------------------------------------------------------
# scan_file <path> <current_year>
#   Emits "<path>:<line>:<text>" for each un-annotated `DateTime.utc(YYYY,...)`
#   literal whose YYYY >= <current_year>. A line is skipped when it is a
#   genuine `//` comment line, when a `//` precedes the match in
#   string-stripped text, or when the `// future-date-ok:` annotation is on
#   the line itself or the line directly above.
# ---------------------------------------------------------------------------
scan_file() {
  awk -v file="$1" -v cy="$2" -v pat="$pattern" -v ann="$annotation" '
    function strip_strings(s,   out, c, i, q, esc) {
      out = ""; q = ""; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (esc) { esc = 0; continue }
          if (c == "\\") { esc = 1; continue }
          if (c == q) { q = "" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        out = out c
      }
      return out
    }
    {
      # (1a) Genuine comment line? First non-space token is `//`.
      firsttok = $0
      sub(/^[[:space:]]+/, "", firsttok)
      if (firsttok ~ /^[/][/]/) { prev = $0; next }

      codeonly = strip_strings($0)
      where = match(codeonly, pat)
      if (where > 0) {
        # (1b) `//` comment after CODE masking the call?
        before = substr(codeonly, 1, where - 1)
        if (before ~ /[/][/]/) { prev = $0; next }

        matched = substr(codeonly, where, RLENGTH)
        yr = matched
        gsub(/[^0-9]/, "", yr)
        yr = yr + 0
        if (yr >= cy) {
          # (2) Annotated future-date-ok on this line or the line above.
          if ($0 ~ ann)   { prev = $0; next }
          if (prev ~ ann) { prev = $0; next }
          printf "%s:%d:%s\n", file, NR, $0
        }
      }
      prev = $0
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# run_scan <scan_root> <current_year> [grandfathered-repo-relative-path ...]
#   Emits offenders across every *.dart file under
#   <scan_root>/test/features/booking/, skipping any path listed in the
#   trailing grandfathered-path arguments (repo-relative, e.g.
#   "test/features/booking/data/booking_mapper_test.dart").
# ---------------------------------------------------------------------------
run_scan() {
  local scan_root="$1"
  local cy="$2"
  shift 2
  declare -A skip=()
  local g
  for g in "$@"; do skip["$scan_root/$g"]=1; done
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -n "${skip[$f]:-}" ] && continue
    scan_file "$f" "$cy"
  done < <(find "$scan_root/test/features/booking" -type f -name '*.dart' 2>/dev/null | sort)
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a tree with a past literal, a current-year
# literal, an annotated far-future literal, and a commented-out literal;
# assert only the un-annotated current-year literal is flagged.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/test/features/booking/presentation"
  cy="$(date -u +%Y)"
  future_yr=$((cy + 1))

  cat > "$tmp/test/features/booking/presentation/fixture_test.dart" <<EOF
// A fixed PAST instant — safe forever, must NOT be flagged.
final DateTime past = DateTime.utc(2000, 1, 1);
// An un-annotated CURRENT-year literal — the real bug pattern, MUST be flagged.
final DateTime stale = DateTime.utc($cy, 7, 20, 15);
// An annotated far-future literal — deliberate, must NOT be flagged.
// future-date-ok: fixed twin of a firmly-past instant, see group header
final DateTime deliberate = DateTime.utc($future_yr, 1, 1);
// A commented-out example — must NOT be flagged.
// final DateTime example = DateTime.utc($future_yr, 1, 1);
EOF

  out="$(run_scan "$tmp" "$cy")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  if [ "$flagged" -ne 1 ] || ! printf '%s' "$out" | grep -q "fixture_test.dart:4"; then
    echo "SELF-TEST FAIL: expected exactly 1 offender (line 4, the un-annotated"
    echo "                current-year literal), got:"
    printf '%s\n' "$out"
    exit 1
  fi

  # Grandfathering: the same file, passed as an allow-listed path, must
  # produce zero offenders.
  out_grandfathered="$(run_scan "$tmp" "$cy" "test/features/booking/presentation/fixture_test.dart")"
  flagged_grandfathered="$(printf '%s\n' "$out_grandfathered" | grep -c . || true)"
  if [ "$flagged_grandfathered" -ne 0 ]; then
    echo "SELF-TEST FAIL: grandfathered path was still flagged:"
    printf '%s\n' "$out_grandfathered"
    exit 1
  fi

  echo "SELF-TEST PASS: past / annotated-future / commented literals are clean;"
  echo "                the un-annotated current-year literal is flagged;"
  echo "                a grandfathered path is skipped entirely."
  exit 0
fi

# Load the grandfathered file allow-list (one repo-relative path per line;
# `#` comments and blank lines ignored). Missing file → empty allow-list.
grandfathered=()
if [ -f "$allow_file" ]; then
  while IFS= read -r raw; do
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && grandfathered+=("$line")
  done < "$allow_file"
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
current_year="$(date -u +%Y)"
offenders="$(run_scan "$root" "$current_year" "${grandfathered[@]:-}")"

if [ -n "$offenders" ]; then
  echo "Absolute future DateTime.utc(...) literal found under test/features/booking/:"
  echo "$offenders"
  echo
  echo "isPast (lib/features/booking/domain/booking_display_x.dart) reads the"
  echo "REAL wall clock. An absolute future literal passes today and silently"
  echo "expires later, turning 'upcoming' assertions into false negatives on a"
  echo "date, not a code change — exactly what happened on 2026-07-20."
  echo
  echo "Use a now-relative offset instead:"
  echo "    futureBookingStart()  // test/helpers/booking_fixture_dates.dart"
  echo
  echo "If a FIXED far-future instant is genuinely required (e.g. proving both"
  echo "sides of isPast's boundary stay deterministic relative to each other),"
  echo "annotate it:"
  echo "    // future-date-ok: <why a fixed instant is correct here>"
  echo "    final DateTime start = DateTime.utc(2999, 1, 1);"
  echo
  echo "Legacy files predating this gate are grandfathered in"
  echo "scripts/.stale_future_date_allow — the baseline only shrinks, never grows."
  exit 1
fi

exit 0
