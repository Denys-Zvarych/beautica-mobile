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
# A fixed PAST literal is exempt from (a)/(b) automatically as far as the
# TIME-BOMB rule goes: it can never become "upcoming" again. It is NOT exempt
# from rule (c) below.
#
#   (c) FAR-PAST CONSTRUCTOR form, `integration_test/` ONLY. No
#       `DateTime.utc(YYYY, ...)` literal with YYYY < the CURRENT year.
#
# WHY (c) EXISTS — a DIFFERENT bug with the same spelling (2026-08-17)
# --------------------------------------------------------------------
# `integration_test/master_archive_flow_test.dart` seeded a booking at
# `DateTime.utc(2020, 1, 1, 10)`. Rules (a) and (b) both passed it clean — it is
# firmly in the past, so it is not a time bomb — and it hung that file's
# scenario 2 UNBOUNDEDLY. `MasterBookingsScreen` mounts on the way to the
# archive and fetches ONE Kyiv day; the 2020 row reached its single-day
# timeline, which builds one `TimelineHourRuler` row per hour and so tried to
# build ~56 500 of them. That is a synchronous, allocating loop: it starves the
# Dart event loop, and every bound the harness owns (`Future.timeout`,
# `pumpAndSettle`'s deadline, the `pumpUntil*` poll deadlines, a per-test
# `Timeout`) is a TIMER, so none of them can fire. Nothing failed; the run just
# never ended.
#
# The fixture was wrong for a plain reason: this tier injects a FIXED clock
# (`kFixedNow`, `integration_test/support/fake_backend.dart`), and every E2E
# instant is supposed to be derived from it (`kFixedNow.subtract(...)`, a local
# `elapsedStart(n)` helper, `fb.bookingStartsAt`). An absolute literal is
# unanchored from the injected clock by construction, so how far it lands from
# "now" is accidental — which is how one ended up six years off a day-scoped
# screen. (a)/(b) already push the FUTURE side onto anchored helpers; (c) closes
# the past side.
#
# SCOPE: `integration_test/` ONLY, deliberately. `kFixedNow` is an E2E-tier
# concept; `test/features/booking/` has no injected-clock convention to point a
# violator at, and carries 16 legitimate far-past literals (timezone math,
# mapper round-trips, lane layout) that (c) would flag as pure noise. Widening
# (c) to that root would mean allow-listing most of it, which is how a guard
# stops meaning anything.
#
# Rule (c) is unblocked with `// past-date-ok: <reason>` — or with the existing
# `// future-date-ok:`, since both spell the identical claim ("this fixed
# instant is deliberate"). Accepting either also keeps `kFixedNow`'s own
# declaration silent once the current year moves past 2026: it is already
# annotated `future-date-ok:` as the injected clock itself.
#
# (c) has NO string-literal counterpart on purpose. A year-granular past-string
# rule would flag every ordinary `'createdAt': '2026-05-20T09:00:00Z'` fixture
# in `fake_backend.dart`, and blanket-allow-listing that file is exactly the
# blind spot rule (b)'s own doc warns against rebuilding.
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
# Rule (c)'s annotation: EITHER marker unblocks a far-past literal. `past-date-
# ok:` is the semantically-correct spelling for new sites; `future-date-ok:` is
# accepted because it is the same claim, and because `kFixedNow`'s own
# declaration already carries it (see the header's rule-(c) section).
past_annotation='[/][/][[:space:]]*(future|past)-date-ok:'
# Rule (c)'s scan root — a SUBSET of `scan_dirs`. See the header on why the
# widget tier is deliberately excluded.
past_scan_dirs=(
  "integration_test"
)

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
# scan_file_past <path> <current_year>
#   Rule (c). Emits "<path>:<line>:<text>" for each un-annotated
#   `DateTime.utc(YYYY, ...)` literal whose YYYY < <current_year>.
#
#   Structurally the MIRROR of [scan_file] — same `strip_strings` masking, same
#   comment handling, same this-line-or-line-above annotation lookup — with the
#   year comparison flipped and a wider annotation pattern. Kept as its own
#   function rather than a parameterised [scan_file] because the two rules do
#   not share a scan root, an annotation set, or an allow-list, so the only
#   thing a merged version would share is the awk boilerplate.
# ---------------------------------------------------------------------------
scan_file_past() {
  awk -v file="$1" -v cy="$2" -v pat="$pattern" -v ann="$past_annotation" '
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
      firsttok = $0
      sub(/^[[:space:]]+/, "", firsttok)
      if (firsttok ~ /^[/][/]/) { prev = $0; next }

      codeonly = strip_strings($0)
      where = match(codeonly, pat)
      if (where > 0) {
        before = substr(codeonly, 1, where - 1)
        if (before ~ /[/][/]/) { prev = $0; next }

        matched = substr(codeonly, where, RLENGTH)
        yr = matched
        gsub(/[^0-9]/, "", yr)
        yr = yr + 0
        if (yr < cy) {
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
# run_scan_past <tree_root> <current_year>
#   Rule (c)'s walk, over ${past_scan_dirs[@]} only.
#
#   TAKES NO GRANDFATHERED PATHS, ON PURPOSE — same reasoning as
#   [run_scan_strings]: `.stale_future_date_allow` is the legacy baseline for
#   the FUTURE constructor rule, and every file it lists is under
#   `test/features/booking/`, which rule (c) does not scan at all. Sharing it
#   could only ever create a blind spot.
# ---------------------------------------------------------------------------
run_scan_past() {
  local tree_root="$1"
  local cy="$2"
  local d f
  for d in "${past_scan_dirs[@]}"; do
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      scan_file_past "$f" "$cy"
    done < <(find "$tree_root/$d" -type f -name '*.dart' 2>/dev/null | sort)
  done
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
#   Far-past rule (c): the un-annotated `DateTime.utc(2000, …)` on line 2 — the
#                      2026-08-17 hang's exact shape, and a literal BOTH other
#                      rules deliberately pass clean — plus two annotated
#                      far-past literals (`past-date-ok:` and `future-date-ok:`,
#                      either of which must silence it). Because (c) scans
#                      `integration_test/` only, line 2 must be flagged in the
#                      E2E probe and NOT in the widget-tier one; the asymmetric
#                      counts below are what prove that scoping is real rather
#                      than merely documented.
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
  # Rule (c) fires on the un-annotated far-past literal, in the E2E probe only.
  past_offender_line=2
  past_probe="integration_test/support/fake_backend.dart"
  widget_probe="test/features/booking/presentation/fixture_test.dart"

  for probe in "${probe_paths[@]}"; do
    mkdir -p "$tmp/$(dirname "$probe")"
    cat > "$tmp/$probe" <<EOF
// Fixed PAST: no time bomb, so rules (a)/(b) pass it — but rule (c) MUST flag
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
// ---- FAR-PAST constructor literals (rule (c), integration_test/ only) ----
// An annotated far-past literal — deliberate, must NOT be flagged.
// past-date-ok: pinned twin of a far-future instant, see group header
final DateTime pinnedPast = DateTime.utc(2001, 1, 1);
// future-date-ok unblocks rule (c) too — same claim, must NOT be flagged.
// future-date-ok: the injected fixed clock itself
final DateTime pinnedPast2 = DateTime.utc(2002, 1, 1);
EOF
  done

  # Both rules, one offender list — mirrors what a real run reports.
  scan_both() {
    run_scan "$@"
    run_scan_strings "$1" "$today"
    run_scan_past "$1" "$cy"
  }

  # (1) Both roots, both rules: three offenders per probe file, on the exact
  #     lines above. Everything else in the probe must stay clean.
  out="$(scan_both "$tmp" "$cy")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"
  # +1: rule (c)'s single offender, which fires in the E2E probe ONLY.
  expected=$((${#probe_paths[@]} * offenders_per_probe + 1))
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

  # (1c) Rule (c) bit in the E2E root — and did NOT bite in the widget tier,
  #      where the identical literal sits on the identical line. That asymmetry
  #      IS the scoping guarantee; a (c) that walked `scan_dirs` would flag both.
  if ! printf '%s\n' "$out" | grep -q "^$tmp/$past_probe:$past_offender_line:"; then
    echo "SELF-TEST FAIL: the FAR-PAST rule did not bite on line"
    echo "                $past_offender_line of '$past_probe'. That literal is"
    echo "                the 2026-08-17 unbounded-hang fixture's exact shape,"
    echo "                and rules (a)/(b) both pass it clean by design — (c)"
    echo "                is the only thing standing between it and the corpus."
    printf '%s\n' "$out"
    exit 1
  fi
  if printf '%s\n' "$out" | grep -q "^$tmp/$widget_probe:$past_offender_line:"; then
    echo "SELF-TEST FAIL: the FAR-PAST rule bit in 'test/features/booking/'."
    echo "                It is scoped to \${past_scan_dirs[*]} on purpose — that"
    echo "                tree has no injected-clock convention to point a"
    echo "                violator at and 16 legitimate far-past literals. See"
    echo "                the header's rule-(c) section."
    printf '%s\n' "$out"
    exit 1
  fi

  # (2) Grandfathering silences the CONSTRUCTOR rule in both roots — and
  #     DELIBERATELY DOES NOT silence the STRING rule. `.stale_future_date_allow`
  #     is the legacy baseline for `DateTime.utc` only; if it also swallowed
  #     string dates, any grandfathered file could quietly acquire the exact
  #     fixture that expired on 2026-07-21.
  out_grandfathered="$(scan_both "$tmp" "$cy" "${probe_paths[@]}")"
  flagged_grandfathered="$(printf '%s\n' "$out_grandfathered" | grep -c . || true)"
  # +1: rule (c) has no allow-list either, so its offender must SURVIVE too.
  expected_grandfathered=$((${#probe_paths[@]} * ${#str_offender_lines[@]} + 1))
  if [ "$flagged_grandfathered" -ne "$expected_grandfathered" ]; then
    echo "SELF-TEST FAIL: after allow-listing every probe path, expected the"
    echo "                $expected_grandfathered STRING + FAR-PAST offenders to REMAIN (the"
    echo "                allow-list covers the future DateTime.utc rule only), got"
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

  echo "SELF-TEST PASS: annotated / commented / string-quoted literals are clean"
  echo "                under ALL THREE rules;"
  echo "                the un-annotated current-year DateTime.utc literal AND"
  echo "                both future ISO-8601 STRING dates are flagged in BOTH"
  echo "                scan roots (${scan_dirs[*]});"
  echo "                the un-annotated FAR-PAST DateTime.utc literal is flagged"
  echo "                in ${past_scan_dirs[*]} and NOT in the widget tier, and"
  echo "                either // past-date-ok: or // future-date-ok: silences it;"
  echo "                allow-listed paths are skipped by the future DateTime.utc"
  echo "                rule ONLY (neither the string rule nor the far-past rule"
  echo "                has a baseline), and skipping one path does not silence"
  echo "                the other root."
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
past_offenders="$(run_scan_past "$root" "$current_year")"

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

if [ -n "$past_offenders" ]; then
  echo "Absolute FAR-PAST DateTime.utc(...) literal found under ${past_scan_dirs[*]}:"
  echo "$past_offenders"
  echo
  echo "This is NOT the stale-future time bomb above — it is the 2026-08-17"
  echo "unbounded-hang shape, which rules (a) and (b) both pass clean by design."
  echo "integration_test/master_archive_flow_test.dart seeded"
  echo "    startsAt: DateTime.utc(2020, 1, 1, 10)"
  echo "and a fake that ignored the request's from/to handed that row to a"
  echo "SINGLE-DAY timeline. BookingsTimelineGrid builds one hour row per hour of"
  echo "its extent, so it tried to build ~56 500 of them — a synchronous,"
  echo "allocating loop that starves the Dart event loop. Every bound the harness"
  echo "owns is a Timer (Future.timeout, pumpAndSettle's deadline, the pumpUntil*"
  echo "poll deadlines, a per-test Timeout), and timers do not tick on a starved"
  echo "loop, so nothing failed — the run simply never ended."
  echo
  echo "This tier injects a FIXED clock. Anchor the instant to it:"
  echo "    kFixedNow.subtract(const Duration(days: 40))   // fake_backend.dart"
  echo "    fb.bookingStartsAt"
  echo "or a local elapsedStart(n)-style helper derived from kFixedNow. An"
  echo "absolute literal is unanchored from the injected clock by construction,"
  echo "so how far it lands from \"now\" is accidental."
  echo
  echo "If the instant is genuinely PINNED (e.g. the deliberate far-past twin of"
  echo "a far-future instant, where the PAIR is the assertion), annotate it:"
  echo "    // past-date-ok: <why a fixed far-past instant is correct here>"
  echo "(// future-date-ok: is accepted too — it is the same claim.)"
  echo
fi

if [ -n "$offenders" ] || [ -n "$str_offenders" ] || [ -n "$past_offenders" ]; then
  exit 1
fi

exit 0
