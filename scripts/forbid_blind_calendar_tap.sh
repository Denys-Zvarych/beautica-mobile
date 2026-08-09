#!/usr/bin/env bash
# Blind calendar-cell tap gate (2026-07-31 — date-dependent-flake ratchet).
#
# THE BUG THIS GUARDS
# -------------------
# `MonthCalendar` renders inside a `SingleChildScrollView` on the booking
# slot-picker screens. On the 800x600 flutter_test surface the scroll fold sits
# at y ~= 419, while the last two grid rows centre at y ~= 440 and y ~= 490 —
# i.e. BELOW the fold.
#
# A blind tap on such a cell —
#
#     await tester.tap(find.byKey(Key('booking-calendar-day-$day')));
#
# — does NOT throw. The finder still resolves (the widget is laid out, merely
# clipped) and `tap()` still computes a centre point; the tap just lands on
# whatever is actually painted at that offset (the bottom summary bar) and is
# silently swallowed. The test then fails much later, on a downstream assertion
# that has nothing to do with scrolling.
#
# The killer property is that it is DATE-DEPENDENT. Tests that tap
# `DateTime.now().day` sit in the last two rows only in roughly the final ~12
# days of each month, so the suite is green for ~18 days and red for ~12 —
# a time bomb that reads as flake and gets re-run rather than fixed.
#
# The fix already ships: `TapCalendarDay.tapCalendarDay` in
# `test/helpers/pump_app.dart` calls `ensureVisible` + `pumpAndSettle` before
# tapping, exactly as a real user scrolls. The widget tests used it; the
# integration tests never did, which is how 4 tests across 2 flow files went
# red purely because of the calendar date.
#
# THE RULE
# --------
# A `tester.tap(...)` whose target is a `booking-calendar-day-*` key MUST go
# through `tester.tapCalendarDay(day)`.
#
# THE ONE LEGITIMATE EXCEPTION — and why it is not a loophole:
# tests that assert a cell is INERT (a disabled / out-of-range day with no
# `GestureDetector`) must keep tapping it directly, with `warnIfMissed: false`,
# and then assert `expect(fake.callCount, 0)`. Routing THOSE through
# `tapCalendarDay` would be actively wrong: `ensureVisible` on a cell that is
# already visible is a no-op, so the assertion would pass whether the cell
# correctly has no handler OR the tap was swallowed by scroll clipping — the
# precise false-pass the helper exists to prevent for the enabled case. See the
# extension's doc comment at `test/helpers/pump_app.dart:183-190`.
#
# `warnIfMissed: false` is therefore the exemption token: it is the explicit,
# self-documenting marker of "I know this tap may not land, that is the point",
# and it cannot be written by accident. Currently exempt:
#   integration_test/public_master_profile_flow_test.dart:443, :533
#
# Banned:   await tester.tap(find.byKey(Key('booking-calendar-day-$d')));
#           await tester.tap(cell);            // where `cell` is such a finder
# Allowed:  await tester.tapCalendarDay(d);
#           await tester.tap(cell, warnIfMissed: false);   // inert-cell proof
#
# COMPANION CHECK — helper wrappers (mode 2)
# -----------------------------------------
# The scan above is defeated by INDIRECTION: hide the tap in a helper
# (`Future<void> pickDay(WidgetTester t, int d) => t.tap(find.byKey(...)))`)
# and each individual call site reads as an innocent `pickDay(tester, 12)`.
# Mode 2 closes the common case: any file under `test/helpers/` that mentions a
# `booking-calendar-day-*` key AND performs a tap MUST also route through
# `tapCalendarDay`. `pump_app.dart` passes because it DEFINES it; a new helper
# that taps a calendar cell its own way is flagged. This deliberately matches
# bare `tap(` as well as `.tap(`, because inside a `WidgetTester` extension the
# receiver is implicit (`await tap(finder)` — exactly how `tapCalendarDay` is
# written).
#
# STATED RESIDUAL HOLE (bounded, and irreducible for a static grep)
# ----------------------------------------------------------------
# This gate is a grep, not a type-aware analysis, so three shapes remain
# invisible and are ACCEPTED as known limitations rather than silently missed:
#   1. A tap helper living OUTSIDE `test/helpers/` (e.g. a private function in
#      the flow file itself, or in `integration_test/support/`). Mode 1 catches
#      it only if the calendar key and the tap are in the same file, which is
#      the usual case but not guaranteed.
#   2. A calendar key built dynamically enough to hide the literal — e.g.
#      `find.byKey(Key('booking-calendar-' + kind + '-$d'))`. No grep can see
#      through string composition.
#   3. A tap on a Finder returned by a FUNCTION rather than held in a local
#      (`await tester.tap(cellFor(12));`) — mode 1's variable tracking only
#      follows `<Type> name = ...` bindings.
# The behavioural backstop for all three is `tapCalendarDay`'s own doc comment
# plus the fact that a swallowed tap still fails the flow's own downstream
# assertions — just less legibly. Widening the grep to cover them would trade
# these narrow holes for false positives on every unrelated `tap(`, which is
# the failure mode that gets a gate deleted.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_blind_calendar_tap.sh --self-test

set -euo pipefail

cell_key='booking-calendar-day-'
exemption='warnIfMissed:[[:space:]]*false'

# ---------------------------------------------------------------------------
# scan <root> → prints `file:line:text` for each blind calendar tap.
#
# The unit of analysis is the PAREN-BALANCED EXTENT of the `.tap(` call, not a
# fixed lookahead window: `dart format` wraps long calls across lines, but a
# fixed window also swallows the NEXT statement, which produced false positives
# on `tap(find.byKey(Key('booking-calendar-next-month')))` merely because a
# calendar-day key appeared two lines later. Accumulating from `.tap(` until
# parens balance makes the match exact.
#
# Two offender shapes:
#   (A) INLINE  — the cell key appears inside the tap call's own extent.
#   (B) VIA VAR — `final Finder <name> = find.byKey(...booking-calendar-day-…)`
#                 bound earlier, then `tester.tap(<name>)`.
#
# Comment lines are stripped before analysis: this repo documents the banned
# shape in prose (pump_app.dart's own doc comment shows it), and a guard that
# trips on its own explanation is a guard that gets deleted.
# ---------------------------------------------------------------------------
scan() {
  local root="$1"
  [ -d "$root" ] || return 0
  local f
  while IFS= read -r f; do
    grep -q "$cell_key" "$f" || continue

    awk -v key="$cell_key" -v exempt="$exemption" -v file="$f" '
      {
        raw[NR] = $0
        # Blank out pure-comment lines so prose never counts as code.
        line = $0
        if (line ~ /^[[:space:]]*\/\//) line = ""
        code[NR] = line
      }
      END {
        # --- pass 1: Finder variables bound to a calendar-day key -----------
        for (i = 1; i <= NR; i++) {
          if (code[i] !~ /=/) continue
          # a binding may wrap; look at its own paren-balanced extent
          ext = code[i]; depth = gsub(/\(/, "(", ext) - gsub(/\)/, ")", ext)
          ext = code[i]; j = i
          while (depth > 0 && j < NR) {
            j++; ext = ext "\n" code[j]
            depth += gsub(/\(/, "(", code[j]) - gsub(/\)/, ")", code[j])
          }
          if (ext !~ key) continue
          if (match(code[i], /[A-Za-z_?<>]+[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=/, m)) {
            vars[m[1]] = 1
          }
        }

        # --- pass 2: every .tap( call, matched over its balanced extent -----
        for (i = 1; i <= NR; i++) {
          if (code[i] !~ /\.tap\(/) continue
          if (code[i] ~ /tapCalendarDay/) continue

          # Accumulate from the `.tap(` onward until parens balance.
          start = index(code[i], ".tap(")
          seg = substr(code[i], start)
          ext = seg
          depth = gsub(/\(/, "(", seg) - gsub(/\)/, ")", seg)
          j = i
          while (depth > 0 && j < NR) {
            j++
            ext = ext "\n" code[j]
            depth += gsub(/\(/, "(", code[j]) - gsub(/\)/, ")", code[j])
          }

          if (ext ~ exempt) continue           # inert-cell proof: allowed

          hit = 0
          if (ext ~ key) hit = 1               # (A) inline
          else if (match(ext, /\.tap\([[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*[,)]/, t)) {
            if (t[1] in vars) hit = 1          # (B) via variable
          }
          if (!hit) continue

          printf "%s:%d:%s\n", file, i, raw[i]
        }
      }
    ' "$f"
  done < <(find "$root" -type f -name '*.dart' 2>/dev/null | sort)
}

# ---------------------------------------------------------------------------
# scan_helpers <helpers-dir> → mode 2. Prints `file: <message>` for any helper
# that taps a calendar-day cell without routing through `tapCalendarDay`.
#
# Whole-file granularity on purpose: the key literal and the tap are usually a
# few lines apart inside one small helper, and the required token
# (`tapCalendarDay`) may be the enclosing extension's own name.
# ---------------------------------------------------------------------------
scan_helpers() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  local f
  while IFS= read -r f; do
    # Strip comments so a doc comment describing the pattern never trips this.
    local code
    code="$(grep -vE '^[[:space:]]*//' "$f" || true)"
    printf '%s' "$code" | grep -q "$cell_key" || continue
    printf '%s' "$code" | grep -qE '(^|[^A-Za-z0-9_.])tap\(|\.tap\(' || continue
    printf '%s' "$code" | grep -q 'tapCalendarDay' && continue
    echo "$f: taps a booking-calendar-day-* cell without routing through tapCalendarDay"
  done < <(find "$dir" -type f -name '*.dart' 2>/dev/null | sort)
}

# ---------------------------------------------------------------------------
# Self-test mode: assert the verdicts on pinned fixture snippets.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # (1) the exact shape that shipped broken — inline blind tap → OFFENDER
  cat > "$tmp/bad_inline.dart" <<'EOF'
void main() {
  testWidgets('picks today', (tester) async {
    await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
    await tester.pumpAndSettle();
  });
}
EOF

  # (2) blind tap through a Finder variable → OFFENDER
  cat > "$tmp/bad_via_var.dart" <<'EOF'
void main() {
  testWidgets('picks today', (tester) async {
    final Finder todayCell = find.byKey(
      Key('booking-calendar-day-${today.day}'),
    );
    expect(todayCell, findsOneWidget);
    await tester.tap(todayCell);
  });
}
EOF

  # (3) routed through the helper → OK
  cat > "$tmp/good_helper.dart" <<'EOF'
void main() {
  testWidgets('picks today', (tester) async {
    final Finder todayCell = find.byKey(
      Key('booking-calendar-day-${today.day}'),
    );
    expect(todayCell, findsOneWidget);
    await tester.tapCalendarDay(today.day);
  });
}
EOF

  # (4) inert-cell proof, exempt via warnIfMissed:false → OK
  #     (this is public_master_profile_flow_test.dart:443 / :533)
  cat > "$tmp/good_inert.dart" <<'EOF'
void main() {
  testWidgets('disabled day is inert', (tester) async {
    final Finder todayCell = find.byKey(
      Key('booking-calendar-day-${todayDateOnly.day}'),
    );
    expect(
      find.descendant(of: todayCell, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    await tester.tap(todayCell, warnIfMissed: false);
    expect(fb.getMasterSlotsCalls, 0);
  });
}
EOF

  # (5) exemption on a wrapped call → OK (dart format splits long calls)
  cat > "$tmp/good_inert_wrapped.dart" <<'EOF'
void main() {
  testWidgets('disabled day is inert', (tester) async {
    final Finder cell = find.byKey(const Key('booking-calendar-day-29'));
    await tester.tap(
      cell,
      warnIfMissed: false,
    );
  });
}
EOF

  # (6) taps something else entirely in a file that also names the key → OK
  cat > "$tmp/good_other_tap.dart" <<'EOF'
void main() {
  testWidgets('cta', (tester) async {
    expect(find.byKey(const Key('booking-calendar-day-15')), findsOneWidget);
    await tester.tap(find.byKey(const Key('booking-summary-cta')));
  });
}
EOF

  # (7) taps the next-month ARROW, with a calendar-day key on a nearby line →
  #     OK. This is the regression fixture for the fixed-lookahead-window false
  #     positive that a naive `grep -A6` implementation produced against
  #     slot_picker_test.dart:548 / :629.
  cat > "$tmp/good_next_month.dart" <<'EOF'
void main() {
  testWidgets('advances a month', (tester) async {
    await tester.tap(find.byKey(const Key('booking-calendar-next-month')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('booking-calendar-day-15')),
      findsOneWidget,
    );
  });
}
EOF

  # (8) the banned shape quoted in a DOC COMMENT (pump_app.dart does this) → OK
  cat > "$tmp/good_doc_comment.dart" <<'EOF'
/// A blind `tester.tap(find.byKey(Key('booking-calendar-day-3')))` on such a
/// cell doesn't throw — the finder still resolves.
extension TapCalendarDay on WidgetTester {}
EOF

  flagged=""
  for snip in bad_inline bad_via_var good_helper good_inert \
              good_inert_wrapped good_other_tap good_next_month \
              good_doc_comment; do
    out="$(scan "$tmp" | grep "/$snip.dart:" || true)"
    [ -n "$out" ] && flagged="$flagged $snip"
  done
  flagged="$(printf '%s' "$flagged" | tr -s ' ' | sed 's/^ //')"

  if [ "$flagged" != "bad_inline bad_via_var" ]; then
    echo "SELF-TEST FAIL: expected 'bad_inline bad_via_var', got: '$flagged'"
    exit 1
  fi

  # ── mode 2: helper-wrapper indirection ──────────────────────────────────
  helpers="$tmp/helpers"
  mkdir -p "$helpers"

  # (H1) a NEW helper that taps a calendar cell its own way → OFFENDER.
  #      This is the indirection that defeats mode 1 entirely: every call site
  #      reads as an innocent `pickDay(tester, 12)`.
  cat > "$helpers/bad_wrapper.dart" <<'EOF'
extension PickDay on WidgetTester {
  Future<void> pickDay(int day) async {
    await tap(find.byKey(Key('booking-calendar-day-$day')));
    await pumpAndSettle();
  }
}
EOF

  # (H2) the real pump_app.dart shape: DEFINES tapCalendarDay → OK.
  cat > "$helpers/good_definition.dart" <<'EOF'
extension TapCalendarDay on WidgetTester {
  Future<void> tapCalendarDay(int day) async {
    final Finder finder = find.byKey(Key('booking-calendar-day-$day'));
    await ensureVisible(finder);
    await pumpAndSettle();
    await tap(finder);
  }
}
EOF

  # (H3) a helper that DELEGATES to tapCalendarDay → OK.
  cat > "$helpers/good_delegating.dart" <<'EOF'
Future<void> pickToday(WidgetTester tester) async {
  await tester.tapCalendarDay(DateTime.now().day);
}
EOF

  # (H4) a helper that names the key only in a doc comment → OK.
  cat > "$helpers/good_doc_only.dart" <<'EOF'
// Helpers for booking-calendar-day-* assertions.
Future<void> expectDayPresent(WidgetTester tester, int d) async {
  expect(find.byKey(Key('x')), findsOneWidget);
}
EOF

  hflagged=""
  for snip in bad_wrapper good_definition good_delegating good_doc_only; do
    out="$(scan_helpers "$helpers" | grep "/$snip.dart:" || true)"
    [ -n "$out" ] && hflagged="$hflagged $snip"
  done
  hflagged="$(printf '%s' "$hflagged" | tr -s ' ' | sed 's/^ //')"

  if [ "$hflagged" != "bad_wrapper" ]; then
    echo "SELF-TEST FAIL (mode 2): expected 'bad_wrapper', got: '$hflagged'"
    exit 1
  fi

  echo "SELF-TEST PASS: both blind-tap shapes flagged (inline and via-variable);"
  echo "                helper-routed / warnIfMissed:false / unrelated-tap clean;"
  echo "                mode 2 flags a wrapper helper that bypasses tapCalendarDay."
  exit 0
fi

offenders="$({ scan integration_test; scan test; } | sort -u)"
helper_offenders="$(scan_helpers test/helpers)"

if [ -n "$helper_offenders" ]; then
  echo "Calendar-tap helper that bypasses tapCalendarDay:"
  echo "$helper_offenders"
  echo
  echo "A helper wrapping the tap defeats the per-call-site check entirely —"
  echo "every call reads as an innocent pickDay(tester, 12). Any helper that"
  echo "taps a booking-calendar-day-* cell must route through"
  echo "tester.tapCalendarDay(day), which ensureVisible()s first."
  exit 1
fi

if [ -n "$offenders" ]; then
  echo "Blind tap on a booking-calendar-day-* cell:"
  echo "$offenders"
  echo
  echo "MonthCalendar sits in a SingleChildScrollView; on the 800x600 test"
  echo "surface the scroll fold is at y~419 while the last two grid rows centre"
  echo "at y~440/490. A blind tap on a below-the-fold cell does NOT throw — it"
  echo "lands on the summary bar and is silently swallowed, failing later on an"
  echo "unrelated assertion. It is DATE-DEPENDENT: red only in roughly the last"
  echo "~12 days of each month, so it reads as flake and gets re-run."
  echo
  echo "Use the helper, which ensureVisible()s first (test/helpers/pump_app.dart):"
  echo "    await tester.tapCalendarDay(day);"
  echo
  echo "ONLY tests proving a cell is INERT (disabled day, no GestureDetector,"
  echo "asserting the call count stays 0) may tap directly — and they must say so:"
  echo "    await tester.tap(cell, warnIfMissed: false);"
  exit 1
fi

exit 0
