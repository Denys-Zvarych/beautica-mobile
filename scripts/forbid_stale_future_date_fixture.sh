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
# THE RULE — TWO SPELLINGS OF THE SAME BOMB
# ------------------------------------------
# Under EITHER scan root — `test/features/booking/` (widget/unit tier) or
# `integration_test/` (E2E tier):
#
#   (a) CONSTRUCTOR form. No `DateTime.utc(YYYY, ...)` literal with
#       YYYY >= the CURRENT year.
#
#   (b) STRING form. No ISO-8601 date opening a string literal
#       (`'2026-07-20T15:00:00Z'`, `"2026-12-05"`) whose date is >= TODAY.
#
# (b) was added because the 2026-07-21 recurrence was invisible to (a) for a
# second, independent reason beyond the scan root: `scan_file` matches over
# `strip_strings($0)`, which ERASES quoted content before matching, so a date
# living inside a string literal was structurally unreachable by the
# constructor pattern in EITHER root. Widening the scan roots alone did not
# close it. See `scan_file_strings` for why (b) is a separate scan rather than
# a looser `pattern`, and why it compares full DATES while (a) compares years.
#
# Use a `DateTime.now()`-relative offset instead — `futureBookingStart()` for
# the common case on the widget tier, `_futureInstant()` / the
# `FakeBackend.bookingStartsAt` fields on the E2E tier.
#
# A fixed PAST literal (YYYY < current year for (a), date < today for (b),
# e.g. `DateTime.utc(2000, 1, 1)` / `'2000-01-01T15:00:00Z'`) is exempt
# automatically: it can never become "upcoming" again, so it isn't a time bomb.
#
# A small number of sites deliberately need a fixed FAR-future instant rather
# than a now-relative one (e.g. a suite proving BOTH sides of `isPast`'s
# boundary need to stay deterministic relative to EACH OTHER, not just to
# "now"; or a query-serialisation test whose fixed input⇄output pair IS the
# assertion). Those are unblocked with a `// future-date-ok: <reason>` comment
# on the same line or the line directly above — same convention as
# `forbid_fixed_wait.sh`'s `fixed-wait-ok`, and it serves BOTH rules.
#
# GOTCHA: "the line directly above" means the LAST comment line before the
# code. Putting `future-date-ok:` on the first line of a multi-line rationale
# block does NOT unblock it — end the block with the marker.
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
# The allow-list covers rule (a) ONLY. Rule (b) has NO baseline and is enforced
# on every file in both roots — when it was added the corpus was already clean
# of future-dated string literals apart from five deliberately date-pinned
# query-serialisation assertions in
# `test/features/booking/data/booking_repository_master_query_test.dart`, each
# annotated in place. A shared allow-list would mean a file grandfathered for a
# `DateTime.utc` literal could quietly acquire the exact string fixture that
# expired on 2026-07-21 — the same two-tier blind spot, rebuilt.
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
# Match: an ISO-8601 date opening a STRING literal — `'2026-07-20T15:00:00Z'`,
# `"2026-12-05"`. Anchored on the opening quote so prose dates in comments and
# in ordinary sentences ("…the 2026-07-21 recurrence…") cannot match.
sq="'"
str_pattern="[\"${sq}][0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"
# Annotation: `// future-date-ok:` (any leading whitespace before the `//`).
# ONE annotation serves both patterns — a deliberate fixed instant is the same
# claim whether it is spelled as a constructor call or as a wire string.
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
# scan_file_strings <path> <today-yyyy-mm-dd>
#   Emits "<path>:<line>:<text>" for each un-annotated ISO-8601 date STRING
#   literal whose date part is >= <today>.
#
#   WHY THIS IS A SEPARATE SCAN, NOT A WIDER `pattern`
#   --------------------------------------------------
#   `scan_file` runs its match over `strip_strings($0)` — quoted content
#   ERASED — on purpose: it stops a `DateTime.utc(2999, …)` that appears INSIDE
#   a string (a doc snippet, an error message, a `reason:`) from being reported
#   as a live fixture. That protection is exactly wrong for this pattern, whose
#   whole subject matter is what is inside the quotes. So this scan reads the
#   RAW line and re-derives comment position itself via `comment_start`, rather
#   than loosening `strip_strings` and blinding the constructor rule.
#
#   PRECISION: DATE, NOT YEAR
#   -------------------------
#   The constructor rule is deliberately coarse (`YYYY >= current year`) —
#   parsing `DateTime.utc(2026, 7, 20, 15)`'s argument list in awk is not worth
#   it. An ISO-8601 string needs no parsing at all: `YYYY-MM-DD` is
#   lexicographically ordered, so this rule compares the FULL date against
#   today and flags only instants that are still in the future. That precision
#   is what makes the rule affordable — a year-granular string rule would flag
#   every `'createdAt': '2026-05-20T09:00:00Z'` review fixture in
#   `integration_test/support/fake_backend.dart`, and blanket-allow-listing
#   that file to make the gate pass would rebuild the blind spot this rule
#   exists to close.
#
#   It also means the rule cannot go stale: a literal is flagged for exactly as
#   long as it is capable of expiring, and a PR introducing one is always
#   flagged (it is future ON THE DAY IT IS WRITTEN — that is the whole point of
#   writing it). Prevention at the gate, which is where the 2026-07-21
#   recurrence needed to be stopped.
# ---------------------------------------------------------------------------
scan_file_strings() {
  awk -v file="$1" -v today="$2" -v pat="$str_pattern" -v ann="$annotation" '
    # Index of the `//` that starts a line comment, ignoring `//` inside a
    # string literal (so a URL fixture is not mistaken for a comment); 0 if the
    # line has no comment.
    function comment_start(s,   i, c, q, esc) {
      q = ""; esc = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") {
          if (esc) { esc = 0; continue }
          if (c == "\\") { esc = 1; continue }
          if (c == q) { q = "" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; continue }
        if (c == "/" && substr(s, i + 1, 1) == "/") { return i }
      }
      return 0
    }
    {
      cs = comment_start($0)
      rest = $0; consumed = 0; hit = 0
      while (match(rest, pat) > 0) {
        pos = consumed + RSTART
        # Match sits at or past the `//` -> it is commented out, and so is
        # every later match on this line.
        if (cs > 0 && pos >= cs) { break }
        # Skip the opening quote; take the YYYY-MM-DD head.
        d = substr(rest, RSTART + 1, 10)
        # Force a STRING comparison (both sides concatenated with "") so awk
        # cannot decide to compare these numerically.
        if ((d "") >= (today "")) { hit = 1; break }
        consumed += RSTART + RLENGTH - 1
        rest = substr(rest, RSTART + RLENGTH)
      }
      if (hit) {
        if ($0 ~ ann)   { prev = $0; next }
        if (prev ~ ann) { prev = $0; next }
        printf "%s:%d:%s\n", file, NR, $0
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
# run_scan_strings <tree_root> <today-yyyy-mm-dd>
#   Same walk as [run_scan], for the ISO-8601 string-literal rule.
#
#   TAKES NO GRANDFATHERED PATHS, ON PURPOSE. `.stale_future_date_allow` is the
#   legacy baseline for the CONSTRUCTOR rule — files that predate that rule. The
#   string rule has no such legacy: at the moment it was added the entire corpus
#   under both scan roots was already clean of future-dated string literals
#   except five deliberately date-pinned query-serialisation assertions, and
#   those were annotated in place. Sharing the allow-list would mean a file
#   grandfathered for a `DateTime.utc` literal could silently acquire a stale
#   STRING date — precisely the two-tier blind spot the 2026-07-21 recurrence
#   was made of.
# ---------------------------------------------------------------------------
run_scan_strings() {
  local tree_root="$1"
  local today="$2"
  local d f
  for d in "${scan_dirs[@]}"; do
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      scan_file_strings "$f" "$today"
    done < <(find "$tree_root/$d" -type f -name '*.dart' 2>/dev/null | sort)
  done
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a tree carrying the SAME probe file in BOTH scan
# roots, covering BOTH rules.
#
#   Constructor rule : a past literal, a current-year literal, an annotated
#                      far-future literal, a commented-out literal, and a
#                      `DateTime.utc(...)` written INSIDE a string (which
#                      `strip_strings` must keep hiding).
#   String rule      : a past ISO instant, a future ISO instant (the exact
#                      shape of the 2026-07-21 incident fixture), a bare future
#                      calendar date, an annotated future date, a commented-out
#                      future date, and a quoted future date sitting after a
#                      `//` on a line of real code.
#
# Planting the probe in BOTH roots is the point: it is what proves
# `integration_test/` is genuinely scanned and not merely listed in `scan_dirs`
# (the 2026-07-21 recurrence was a scan root that existed only in the gate's
# documentation) — and now, that the STRING rule reaches it too, which is the
# tier the recurrence actually landed in.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cy="$(date -u +%Y)"
  today="$(date -u +%F)"
  future_yr=$((cy + 1))

  # One probe file per scan root, at a realistic depth inside each.
  probe_paths=(
    "test/features/booking/presentation/fixture_test.dart"
    "integration_test/support/fake_backend.dart"
  )

  # Lines each rule must flag, and the total per probe file.
  dt_offender_line=4
  str_offender_lines=(17 19)
  offenders_per_probe=3

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
// A constructor call quoted INSIDE a string: strip_strings must keep hiding
// it from the constructor rule.
const String doc = 'call DateTime.utc($future_yr, 1, 1) for a pinned instant';
// ---- ISO-8601 STRING literals (the 2026-07-21 recurrence's shape) ----
// A PAST string instant — can never read as "upcoming" again; NOT flagged.
const String pastStart = '2000-01-01T15:00:00Z';
// The incident fixture's exact shape, in the future — MUST be flagged.
const String staleStart = '$future_yr-07-20T15:00:00Z';
// A bare future calendar DATE, no time part — same bomb, MUST be flagged.
const String staleDay = '$future_yr-12-05';
// An annotated future date — deliberately pinned, must NOT be flagged.
// future-date-ok: pinned INPUT/OUTPUT pair, no wall-clock read
const String pinned = '$future_yr-09-09';
// A commented-out future date — must NOT be flagged.
// const String example2 = '$future_yr-01-01';
// A quoted future date sitting AFTER a // on a line of real code — the comment
// wins, must NOT be flagged.
const String benign = 'ok'; // e.g. '$future_yr-08-01'
EOF
  done

  # Both rules, one offender list — mirrors what a real run reports.
  scan_both() {
    run_scan "$@"
    run_scan_strings "$1" "$today"
  }

  # (1) Both roots, both rules: three offenders per probe file, on the exact
  #     lines above. Everything else in the probe must stay clean.
  out="$(scan_both "$tmp" "$cy")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  expected=$((${#probe_paths[@]} * offenders_per_probe))
  if [ "$flagged" -ne "$expected" ]; then
    echo "SELF-TEST FAIL: expected exactly $expected offenders"
    echo "                ($offenders_per_probe per probe file ×"
    echo "                ${#probe_paths[@]} scan roots), got $flagged:"
    printf '%s\n' "$out"
    exit 1
  fi
  for probe in "${probe_paths[@]}"; do
    if ! printf '%s\n' "$out" | grep -q "^$tmp/$probe:$dt_offender_line:"; then
      echo "SELF-TEST FAIL: the DateTime.utc rule did not bite in scan root"
      echo "                '$(dirname "$(dirname "$probe")")' — no line-$dt_offender_line"
      echo "                offender for '$probe'. Is it listed in scan_dirs AND"
      echo "                actually walked by run_scan?"
      printf '%s\n' "$out"
      exit 1
    fi
    for ln in "${str_offender_lines[@]}"; do
      if ! printf '%s\n' "$out" | grep -q "^$tmp/$probe:$ln:"; then
        echo "SELF-TEST FAIL: the ISO-8601 STRING rule did not bite in scan root"
        echo "                '$(dirname "$(dirname "$probe")")' — no line-$ln"
        echo "                offender for '$probe'. A stale STRING date is the"
        echo "                form that caused the 2026-07-21 recurrence; a gate"
        echo "                that cannot see it in EVERY scan root is the same"
        echo "                blind spot wearing a different hat."
        printf '%s\n' "$out"
        exit 1
      fi
    done
  done

  # (2) Grandfathering silences the CONSTRUCTOR rule in both roots — and
  #     DELIBERATELY DOES NOT silence the STRING rule. `.stale_future_date_allow`
  #     is the legacy baseline for `DateTime.utc` only; if it also swallowed
  #     string dates, any grandfathered file could quietly acquire the exact
  #     fixture that expired on 2026-07-21.
  out_grandfathered="$(scan_both "$tmp" "$cy" "${probe_paths[@]}")"
  flagged_grandfathered="$(printf '%s\n' "$out_grandfathered" | grep -c . || true)"
  expected_grandfathered=$((${#probe_paths[@]} * ${#str_offender_lines[@]}))
  if [ "$flagged_grandfathered" -ne "$expected_grandfathered" ]; then
    echo "SELF-TEST FAIL: after allow-listing every probe path, expected the"
    echo "                $expected_grandfathered STRING offenders to REMAIN (the allow-list"
    echo "                covers the DateTime.utc rule only), got"
    echo "                $flagged_grandfathered:"
    printf '%s\n' "$out_grandfathered"
    exit 1
  fi
  if printf '%s\n' "$out_grandfathered" | grep -q ":$dt_offender_line:"; then
    echo "SELF-TEST FAIL: a grandfathered path was still flagged by the"
    echo "                DateTime.utc rule:"
    printf '%s\n' "$out_grandfathered"
    exit 1
  fi

  # (3) Grandfathering is per-path, not global: allow-listing ONLY the first
  #     probe must still leave the other root's constructor offender visible.
  #     Guards against an allow-list that accidentally swallows a whole tree.
  out_partial="$(scan_both "$tmp" "$cy" "${probe_paths[0]}")"
  flagged_partial="$(printf '%s\n' "$out_partial" | grep -c . || true)"
  expected_partial=$((expected - 1))
  if [ "$flagged_partial" -ne "$expected_partial" ]; then
    echo "SELF-TEST FAIL: allow-listing one path changed the offender count in"
    echo "                the other scan root(s); expected"
    echo "                $expected_partial, got $flagged_partial:"
    printf '%s\n' "$out_partial"
    exit 1
  fi

  echo "SELF-TEST PASS: past / annotated / commented / string-quoted literals"
  echo "                are clean under BOTH rules;"
  echo "                the un-annotated current-year DateTime.utc literal AND"
  echo "                both future ISO-8601 STRING dates are flagged in BOTH"
  echo "                scan roots (${scan_dirs[*]});"
  echo "                allow-listed paths are skipped by the DateTime.utc rule"
  echo "                ONLY (the string rule has no baseline), and skipping one"
  echo "                path does not silence the other root."
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
today="$(date -u +%F)"
offenders="$(run_scan "$root" "$current_year" "${grandfathered[@]:-}")"
str_offenders="$(run_scan_strings "$root" "$today")"

if [ -n "$str_offenders" ]; then
  echo "Future-dated ISO-8601 STRING literal found under ${scan_dirs[*]}:"
  echo "$str_offenders"
  echo
  echo "This is the SAME time bomb as an absolute DateTime.utc(...) fixture,"
  echo "just spelled as a wire string — and it is the form that actually bit us"
  echo "on 2026-07-21: integration_test/support/fake_backend.dart seeded"
  echo "    bookingStartsAt = '2026-07-20T15:00:00Z'"
  echo "which expired and made a CONFIRMED booking read as ELAPSED, silently"
  echo "dropping add-to-calendar / «Перенести» / «Скасувати запис» from the"
  echo "detail screen in every E2E flow that asserted them."
  echo
  echo "Anchor it to now instead:"
  echo "    futureBookingStart()   // test/helpers/booking_fixture_dates.dart"
  echo "    fb.bookingStartsAt     // FakeBackend, E2E tier"
  echo
  echo "If the date is genuinely PINNED (it is an INPUT whose fixed"
  echo "serialisation is the assertion, and nothing reads the wall clock),"
  echo "annotate it:"
  echo "    // future-date-ok: <why a fixed date is correct here>"
  echo
fi

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
  echo "(That allow-list covers the DateTime.utc rule ONLY; the ISO-8601 string"
  echo "rule above has no baseline and is enforced on every file.)"
fi

if [ -n "$offenders" ] || [ -n "$str_offenders" ]; then
  exit 1
fi

exit 0
