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
# It happened a SECOND time on 2026-07-21, in the tier this gate could not
# see: `integration_test/support/fake_backend.dart` seeded
# `bookingStartsAt = '2026-07-20T15:00:00Z'` — the very same expired instant —
# so every E2E flow asserting a CONFIRMED affordance (add-to-calendar,
# «Перенести», «Скасувати запис») started reading the seeded booking as
# ELAPSED. The gate existed and was green, because it only scanned
# `test/features/booking/`. Hence the two scan roots below.
#
# THE RULE
# --------
# No `DateTime.utc(YYYY, ...)` literal with YYYY >= the CURRENT year is
# allowed under EITHER scan root — `test/features/booking/` (widget/unit tier)
# or `integration_test/` (E2E tier). Use a `DateTime.now()`-relative offset
# instead — `futureBookingStart()` for the common case on the widget tier,
# `_futureInstant()` / the `FakeBackend.bookingStartsAt` fields on the E2E
# tier.
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

# Repo-relative directories scanned. Both tiers render booking affordances off
# `BookingDisplayX.isPast`, so both can carry the time bomb; `integration_test/`
# was the blind spot that let the 2026-07-21 recurrence through. Allow-list
# entries in `.stale_future_date_allow` are repo-relative too, so one flat
# allow-list serves both roots.
scan_dirs=(
  "test/features/booking"
  "integration_test"
)

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
# run_scan <tree_root> <current_year> [grandfathered-repo-relative-path ...]
#   Emits offenders across every *.dart file under each of ${scan_dirs[@]},
#   resolved relative to <tree_root>, skipping any path listed in the trailing
#   grandfathered-path arguments (repo-relative, e.g.
#   "test/features/booking/data/booking_mapper_test.dart" or
#   "integration_test/support/fake_backend.dart"). A scan dir that does not
#   exist under <tree_root> contributes nothing (lets the self-test synthesize
#   one root at a time).
# ---------------------------------------------------------------------------
run_scan() {
  local tree_root="$1"
  local cy="$2"
  shift 2
  declare -A skip=()
  local g
  for g in "$@"; do skip["$tree_root/$g"]=1; done
  local d f
  for d in "${scan_dirs[@]}"; do
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      [ -n "${skip[$f]:-}" ] && continue
      scan_file "$f" "$cy"
    done < <(find "$tree_root/$d" -type f -name '*.dart' 2>/dev/null | sort)
  done
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a tree carrying the SAME four-case fixture file in
# BOTH scan roots — a past literal, a current-year literal, an annotated
# far-future literal, and a commented-out literal. Assert that in each root
# only the un-annotated current-year literal is flagged, and that allow-listing
# a path silences it. Planting the probe in both roots is the point: it is what
# proves `integration_test/` is genuinely scanned and not merely listed in
# `scan_dirs` (the 2026-07-21 recurrence was a scan root that existed only in
# the gate's documentation).
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cy="$(date -u +%Y)"
  future_yr=$((cy + 1))

  # One probe file per scan root, at a realistic depth inside each.
  probe_paths=(
    "test/features/booking/presentation/fixture_test.dart"
    "integration_test/support/fake_backend.dart"
  )

  for probe in "${probe_paths[@]}"; do
    mkdir -p "$tmp/$(dirname "$probe")"
    cat > "$tmp/$probe" <<EOF
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
  done

  # (1) Both roots scanned: exactly one offender each, both on line 4.
  out="$(run_scan "$tmp" "$cy")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  if [ "$flagged" -ne "${#probe_paths[@]}" ]; then
    echo "SELF-TEST FAIL: expected exactly ${#probe_paths[@]} offenders (the"
    echo "                un-annotated current-year literal in each scan root),"
    echo "                got $flagged:"
    printf '%s\n' "$out"
    exit 1
  fi
  for probe in "${probe_paths[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^$tmp/$probe:4:"; then
      echo "SELF-TEST FAIL: scan root '$(dirname "$(dirname "$probe")")' did not"
      echo "                bite — no line-4 offender for '$probe'. Is it listed"
      echo "                in scan_dirs AND actually walked by run_scan?"
      printf '%s\n' "$out"
      exit 1
    fi
  done

  # (2) Grandfathering works in BOTH roots: allow-listing every probe path
  #     leaves zero offenders.
  out_grandfathered="$(run_scan "$tmp" "$cy" "${probe_paths[@]}")"
  flagged_grandfathered="$(printf '%s\n' "$out_grandfathered" | grep -c . || true)"
  if [ "$flagged_grandfathered" -ne 0 ]; then
    echo "SELF-TEST FAIL: grandfathered paths were still flagged:"
    printf '%s\n' "$out_grandfathered"
    exit 1
  fi

  # (3) Grandfathering is per-path, not global: allow-listing ONLY the first
  #     probe must still leave the other root's offender visible. Guards
  #     against an allow-list that accidentally swallows a whole tree.
  out_partial="$(run_scan "$tmp" "$cy" "${probe_paths[0]}")"
  flagged_partial="$(printf '%s\n' "$out_partial" | grep -c . || true)"
  if [ "$flagged_partial" -ne $((${#probe_paths[@]} - 1)) ]; then
    echo "SELF-TEST FAIL: allow-listing one path changed the offender count in"
    echo "                the other scan root(s); expected"
    echo "                $((${#probe_paths[@]} - 1)), got $flagged_partial:"
    printf '%s\n' "$out_partial"
    exit 1
  fi

  echo "SELF-TEST PASS: past / annotated-future / commented literals are clean;"
  echo "                the un-annotated current-year literal is flagged in"
  echo "                BOTH scan roots (${scan_dirs[*]});"
  echo "                allow-listed paths are skipped, and skipping one path"
  echo "                does not silence the other root."
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
  echo "Absolute future DateTime.utc(...) literal found under ${scan_dirs[*]}:"
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
