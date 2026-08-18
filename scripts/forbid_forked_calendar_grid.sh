#!/usr/bin/env bash
# Calendar-grid single-implementation gate (mobile-qa, calendar-consolidation
# audit, 2026-08-14).
#
# WHAT THIS PINS
# ---------------
# The user's core requirement for the calendar-consolidation change
# (`lib/shared/widgets/calendar_grid.dart`, mobile-backlog D5) was that there
# be exactly ONE month/week calendar-grid implementation in the app, so a
# future fix lands everywhere at once. Before that change,
# `shared/widgets/period_range_picker.dart` had silently forked ~250 lines of
# `features/booking/presentation/widgets/month_calendar.dart`'s weekday-bar /
# week-row / day-cell logic — which is exactly why the D1–D4 fixes had to be
# applied there SEPARATELY once discovered. Nothing mechanical prevented that
# fork from happening, and nothing mechanical prevents a future one. This gate
# is that mechanism.
#
# THREE RULES, ALL GREP-SHAPED (no AST, matching this repo's existing
# scripts/forbid_*.sh idiom):
#
#   RULE A — the shared primitives (`CalendarWeekRow`, `CalendarDayCell`,
#   `CalendarWeekdayBar`, `isWeekendWeekday`, `calendarDayIsDeemphasized`,
#   `computeSelectedRuns`, `kCalendarDotColor`) may be DEFINED in exactly one
#   file: `lib/shared/widgets/calendar_grid.dart`. A second definition
#   anywhere else in `lib/` — even under a different name for the SAME
#   symbol, which this cannot catch, but a second definition of the same
#   name, which is the shape the pre-consolidation fork actually took (its
#   own private `_DayCell`/`_weekRow` reimplemented the same painting logic
#   inline rather than composing the shared widget) — is exactly the
#   "hand-rolled 7-column week row" the task brief calls out. Each pattern
#   below is anchored to the DEFINITION shape (a `class` declaration, or a
#   parameter-typed function signature) specifically so it does not also
#   trip on the many legitimate USE sites (`CalendarWeekRow(...)` as a
#   constructor call, `isWeekendWeekday(d.weekday)` as a call, etc.).
#
#   RULE B — `BrandColors.weekendMuted`'s hex literal (`0xFF5F5A55`) may
#   appear in exactly one file: `lib/core/theme/brand_colors.dart`, where the
#   token is defined. A second hardcoded copy of the same hex anywhere else
#   is a weekend color that bypassed the shared token — the literal
#   "hardcoded weekend color instead of reading the shared constant" case
#   the task brief names.
#
#   RULE C — the three calendar-grid CONSUMER files
#   (`month_calendar.dart`, `bookings_day_rail.dart`, `period_range_picker
#   .dart`) may contain NO raw `Color(0x...)` hex literal at all — every
#   color they paint (weekend tone, dot tone, ring tone, badge tone) must
#   route through a `BrandColors.*` token or a `calendar_grid.dart` constant
#   (`kCalendarDotColor`). A raw hex creeping back into any of these three is
#   exactly how a dot or weekend color could silently re-diverge between
#   surfaces without Rule B ever seeing it (Rule B only catches a COPY of
#   the *specific* weekendMuted hex; Rule C catches ANY hardcoded color in
#   the three known calendar-grid consumers, which is the wider net).
#
# WHAT THIS DOES NOT CATCH (documented, not silently assumed)
# -------------------------------------------------------------
# A rename-and-refork (a differently-named class that reimplements the same
# painting logic under a new identifier) is invisible to Rule A, which keys
# on the EXISTING symbol names. That is a real gap inherent to a grep-shaped
# gate with no AST; the mitigating fact is that the whole POINT of a fork is
# reusing an existing behaviour under a new name is strictly more code than
# calling the shared widget, so it is a much less likely failure mode than
# "copy the old file and keep going," which is what actually happened here
# and is what Rule A directly blocks.
#
# Self-test: ./scripts/forbid_forked_calendar_grid.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

canonical_file="lib/shared/widgets/calendar_grid.dart"
brand_colors_file="lib/core/theme/brand_colors.dart"

# Rule C — every known month/week calendar-grid CONSUMER. Grows only when a
# new calendar surface is added; `calendar_grid.dart` itself is exempt (it is
# where the tokens are legitimately defined/used).
rule_c_files=(
  "lib/features/booking/presentation/widgets/month_calendar.dart"
  "lib/features/booking/presentation/widgets/bookings_day_rail.dart"
  "lib/shared/widgets/period_range_picker.dart"
)

# Rule A — definition-shaped patterns for each shared primitive. Anchored so
# a normal CALL site (a constructor invocation, a function call with no type
# annotation) never matches — only see this file's header for why each shape
# was picked.
rule_a_patterns=(
  'class[[:space:]]+CalendarWeekRow'
  'class[[:space:]]+CalendarDayCell'
  'class[[:space:]]+CalendarWeekdayBar'
  'bool[[:space:]]+isWeekendWeekday\(int'
  'calendarDayIsDeemphasized\(\{'
  'computeSelectedRuns\(List<bool>'
  'Color[[:space:]]+kCalendarDotColor[[:space:]]*='
)

weekend_hex='0xFF5F5A55'

# ---------------------------------------------------------------------------
# scan <tree_root>
#   Emits one "RULE-X (...): <path>:<line>:<text>" line per offender found
#   under <tree_root>/lib.
# ---------------------------------------------------------------------------
scan() {
  local tree_root="$1"
  local pat f line path rel

  [ -d "$tree_root/lib" ] || return 0

  for pat in "${rule_a_patterns[@]}"; do
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      path="${line%%:*}"
      rel="${path#"$tree_root"/}"
      if [ "$rel" != "$canonical_file" ]; then
        printf 'RULE-A (forked primitive definition): %s\n' "$line"
      fi
    done < <(grep -rnE "$pat" --include='*.dart' "$tree_root/lib" 2>/dev/null || true)
  done

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line%%:*}"
    rel="${path#"$tree_root"/}"
    if [ "$rel" != "$brand_colors_file" ]; then
      printf 'RULE-B (weekendMuted hex hardcoded outside brand_colors.dart): %s\n' "$line"
    fi
  done < <(grep -rnF "$weekend_hex" --include='*.dart' "$tree_root/lib" 2>/dev/null || true)

  for f in "${rule_c_files[@]}"; do
    [ -f "$tree_root/$f" ] || continue
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      printf 'RULE-C (raw Color hex literal in a calendar-grid consumer — use a BrandColors/calendar_grid token): %s\n' "$line"
    done < <(grep -nHE 'Color\(0x' "$tree_root/$f" 2>/dev/null || true)
  done
}

# ---------------------------------------------------------------------------
# Self-test mode.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # Legit canonical file — defines every Rule A primitive. Must NOT be
  # flagged by Rule A.
  mkdir -p "$tmp/$(dirname "$canonical_file")"
  cat > "$tmp/$canonical_file" <<'EOF'
class CalendarWeekdayBar {}
class CalendarWeekRow {}
class CalendarDayCell {}
bool isWeekendWeekday(int weekday) => false;
bool calendarDayIsDeemphasized({required bool selected, required bool deemphasize}) => false;
List<Object> computeSelectedRuns(List<bool> selectedByColumn) => <Object>[];
const Color kCalendarDotColor = Color(0xFFB89A7A);
EOF

  # A legit CALL site (constructor + function calls, no type annotations) —
  # must NOT be flagged by Rule A even though it mentions every symbol name.
  mkdir -p "$tmp/lib/features/booking/presentation/widgets"
  cat > "$tmp/lib/features/booking/presentation/widgets/month_calendar.dart" <<'EOF'
Widget build() {
  return CalendarWeekRow(
    cells: <Widget>[CalendarDayCell()],
    selectedRuns: computeSelectedRuns(<bool>[true]),
  );
}
bool w(DateTime d) => isWeekendWeekday(d.weekday);
Color dotColor = kCalendarDotColor;
EOF

  # A FORKED primitive definition outside calendar_grid.dart — MUST be
  # flagged by Rule A.
  mkdir -p "$tmp/lib/shared/widgets"
  cat > "$tmp/lib/shared/widgets/period_range_picker.dart" <<'EOF'
class CalendarWeekRow extends StatelessWidget {}
EOF

  # The real brand_colors.dart — defines weekendMuted. Must NOT be flagged by
  # Rule B.
  mkdir -p "$tmp/$(dirname "$brand_colors_file")"
  cat > "$tmp/$brand_colors_file" <<'EOF'
static const Color weekendMuted = Color(0xFF5F5A55);
EOF

  # A rogue hardcoded copy of the same hex — MUST be flagged by Rule B.
  mkdir -p "$tmp/lib/features/booking/presentation/widgets"
  cat > "$tmp/lib/features/booking/presentation/widgets/bookings_day_rail.dart" <<'EOF'
final Color muted = Color(0xFF5F5A55);
EOF

  out="$(scan "$tmp")"

  fail=0
  check_present() {
    if ! printf '%s\n' "$out" | grep -qF "$1"; then
      echo "SELF-TEST FAIL: expected an offender matching: $1"
      fail=1
    fi
  }
  check_absent() {
    if printf '%s\n' "$out" | grep -qF "$1"; then
      echo "SELF-TEST FAIL: did NOT expect an offender matching: $1"
      fail=1
    fi
  }

  check_present "RULE-A (forked primitive definition): $tmp/lib/shared/widgets/period_range_picker.dart:1:class CalendarWeekRow extends StatelessWidget {}"
  check_absent "$tmp/$canonical_file:1"
  check_absent "month_calendar.dart:2:  return CalendarWeekRow("

  check_present "RULE-B (weekendMuted hex hardcoded outside brand_colors.dart): $tmp/lib/features/booking/presentation/widgets/bookings_day_rail.dart:1"
  check_absent "$tmp/$brand_colors_file:1"

  # Rule C: bookings_day_rail.dart ALSO now contains a raw Color(0x...) hex
  # (the same probe line doubles as the Rule C fixture) — MUST be flagged by
  # Rule C too, independently of Rule B.
  check_present "RULE-C (raw Color hex literal in a calendar-grid consumer — use a BrandColors/calendar_grid token): $tmp/lib/features/booking/presentation/widgets/bookings_day_rail.dart:1"

  if [ "$fail" -ne 0 ]; then
    echo "--- full scan output ---"
    printf '%s\n' "$out"
    exit 1
  fi

  echo "SELF-TEST PASS: a forked primitive definition, a hardcoded weekendMuted"
  echo "                hex copy, and a raw hex literal in a calendar-grid"
  echo "                consumer are all flagged; the canonical file's own"
  echo "                definitions and ordinary call sites are not."
  echo "SELF-TEST OK: forbid_forked_calendar_grid.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(scan "$root")"

if [ -n "$offenders" ]; then
  echo "Calendar-grid single-implementation gate failed:"
  echo "$offenders"
  echo
  echo "The calendar-consolidation change (mobile-backlog D5) collapsed every"
  echo "month/week calendar surface onto lib/shared/widgets/calendar_grid.dart"
  echo "so a future fix lands everywhere at once. This file reintroduces a"
  echo "forked primitive definition, a hardcoded weekendMuted color copy, or a"
  echo "raw color literal in a known calendar-grid consumer — any of which is"
  echo "exactly how PeriodRangePicker silently drifted from MonthCalendar"
  echo "before this consolidation existed. Compose the shared widget/token"
  echo "instead of reimplementing or hardcoding it."
  exit 1
fi

exit 0
