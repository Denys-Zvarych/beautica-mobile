#!/usr/bin/env bash
# BookingsDayQuery.masterOwn() containment gate (perf finding P4, Phase 7.1;
# retargeted Phase 7.9 from the retired `MasterBookingsQuery.raw`).
#
# THE REGRESSION THIS GUARDS
# --------------------------
# `BookingsDayQuery` is the family key for `bookingsDayProvider`. Its `.of()`
# factory is the ONLY normalising path: it sorts `statuses`/`serviceIds`
# canonically and — the part that actually bites — truncates `day` to
# date-only via `dateOnly`.
#
# That truncation is what stops a family leak. `day` is conceptually a DATE,
# but a `DateTime` is an INSTANT. A rail tap or date picker handing back
# `DateTime.now()`-derived values makes two taps on the same calendar day at
# 09:14:22 and 09:15:07 two DIFFERENT keys — two family members, two network
# fetches, for one day the user sees as identical. Repeat per tap and the
# family grows without bound.
#
# `.masterOwn()` is the freezed pass-through constructor for the query's
# single (for now) union member and skips all of it. It has to be public
# (freezed derives `map`/`when` parameter names from the factory name, so a
# leading underscore is illegal there) — so nothing but convention keeps
# callers off it. A single `BookingsDayQuery.masterOwn(day: picked, ...)`
# would reintroduce exactly the leak the class exists to prevent. No test and
# no lint would catch it: the screen would look and behave correctly, just
# issuing a fresh request per tap.
#
# This invariant OUTLIVES the class rename — `MasterBookingsQuery` retired
# the identical guard around its own `.raw()` constructor and a `from`/`to`
# pair; the leak vector here is the single `day` field instead, but the shape
# of the bug (and the fix) is unchanged.
#
# THE RULE
# --------
# Zero `BookingsDayQuery.masterOwn(` / `BookingsDayQuery.salon(` under lib/
# and test/, except in the
# declaring file itself (which must name it) and `.freezed.dart` codegen
# output (which generates it). Build queries with
# `BookingsDayQuery.of(...)`.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_raw_bookings_query.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# The declaring file — it necessarily contains both the `.masterOwn` factory
# declaration and the `.of` factory's own call to it.
declaring_file='lib/features/booking/domain/bookings_day_query.dart'

# ---------------------------------------------------------------------------
# run_scan <scan_root>
#   Emits "<path>:<line>:<text>" for every `BookingsDayQuery.masterOwn(`
#   occurrence under <scan_root>/lib and <scan_root>/test, excluding the
#   declaring file and freezed codegen output.
# ---------------------------------------------------------------------------
run_scan() {
  local scan_root="$1"
  local h loc
  while IFS= read -r h; do
    [ -z "$h" ] && continue
    loc="${h%%:*}"                       # repo-relative path
    [ "$loc" = "$declaring_file" ] && continue
    case "$loc" in
      *.freezed.dart) continue ;;        # codegen emits the raw ctor
    esac
    printf '%s\n' "$h"
  done < <(
    # `integration_test/` is scanned alongside lib/ and test/ — an E2E test
    # driving a date picker or rail tap is exactly the place a
    # `.masterOwn(day: picked)` shortcut gets written. Matches the scan roots
    # of the sibling gates (`forbid_cyrillic_finder.sh`, `forbid_fixed_wait
    # .sh`), which already cover all three.
    # Phase 21.12 — `.salon(` joined `.masterOwn(`: it is the SECOND
    # pass-through constructor of the same sealed union, skips the same
    # `dateOnly` truncation, and leaks the family in exactly the same way. Its
    # normalising entry points are `BookingsDayQuery.salonOf` /
    # `BookingsDayQuery.salonDayList`.
    cd "$scan_root" && grep -rEn 'BookingsDayQuery\.(masterOwn|salon)\(' \
      lib/ test/ integration_test/ 2>/dev/null | sort || true
  )
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a tree with one legitimate site (the declaring
# file), one codegen site, and one real offender; assert only the offender is
# flagged.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/booking/domain" "$tmp/test/features/booking" \
    "$tmp/integration_test"

  # The declaring file — exempt.
  cat > "$tmp/$declaring_file" <<'EOF'
  const factory BookingsDayQuery.masterOwn({
    return BookingsDayQuery.masterOwn(
EOF

  # Codegen output — exempt.
  cat > "$tmp/lib/features/booking/domain/bookings_day_query.freezed.dart" <<'EOF'
    return BookingsDayQuery.masterOwn(statuses: statuses);
EOF

  # A real offender in a test — must be flagged.
  cat > "$tmp/test/features/booking/leaky_test.dart" <<'EOF'
    final q = BookingsDayQuery.masterOwn(day: DateTime.now(), statuses: s);
EOF

  # A real offender in an E2E test — must be flagged too. This is the case the
  # gate MISSED before `integration_test/` joined the scan roots.
  cat > "$tmp/integration_test/leaky_e2e_test.dart" <<'EOF'
    final q = BookingsDayQuery.masterOwn(day: picked, statuses: s);
EOF

  # ── The SALON half of the regex (Phase 21.12) ────────────────────────────
  # The verifier's V1 finding: the scan regex gained `|salon` but the
  # self-test synthesized ONLY `.masterOwn(` sites, so deleting `|salon` from
  # the regex left this self-test GREEN — a ratchet protecting half of what it
  # claims to. Both halves are synthesized from here on: one `.salon(`
  # offender under lib/ (the scope the master half never exercised either) and
  # one under integration_test/.
  mkdir -p "$tmp/lib/features/salon/presentation"
  cat > "$tmp/lib/features/salon/presentation/leaky_board.dart" <<'EOF'
    final q = BookingsDayQuery.salon(day: picked, salonId: id, statuses: s);
EOF
  cat > "$tmp/integration_test/leaky_salon_e2e_test.dart" <<'EOF'
    final q = BookingsDayQuery.salon(day: picked, salonId: id, statuses: s);
EOF

  # The salon declaring-file / codegen exemptions must hold for `.salon(` too,
  # not only for `.masterOwn(` — otherwise "exempt" could silently mean
  # "invisible to the regex".
  cat >> "$tmp/$declaring_file" <<'EOF'
  const factory BookingsDayQuery.salon({
    return BookingsDayQuery.salon(day: dateOnly(day), salonId: salonId);
EOF
  cat >> "$tmp/lib/features/booking/domain/bookings_day_query.freezed.dart" <<'EOF'
    return BookingsDayQuery.salon(salonId: salonId);
EOF

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  if [ "$flagged" -ne 4 ] ||
    ! grep -q -- 'leaky_test.dart:1' <<< "$out" ||
    ! grep -q -- 'leaky_e2e_test.dart:1' <<< "$out" ||
    ! grep -q -- 'leaky_board.dart:1' <<< "$out" ||
    ! grep -q -- 'leaky_salon_e2e_test.dart:1' <<< "$out"; then
    echo "SELF-TEST FAIL: expected the .masterOwn( offenders (leaky_test.dart,"
    echo "                leaky_e2e_test.dart) AND the .salon( offenders"
    echo "                (leaky_board.dart, leaky_salon_e2e_test.dart) flagged"
    echo "                — and nothing else. Got:"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: the declaring file and .freezed.dart codegen are exempt"
  echo "                for BOTH pass-through constructors; the"
  echo "                BookingsDayQuery.masterOwn( AND BookingsDayQuery.salon("
  echo "                calls under lib/, test/ AND integration_test/ are all"
  echo "                flagged."
  echo "SELF-TEST OK: forbid_raw_bookings_query.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root")"

if [ -n "$offenders" ]; then
  # Verifier finding V2 — NAME THE ACTUAL OFFENDER. The banner used to say
  # `.masterOwn(` unconditionally, so a `.salon(` violation was reported under
  # the wrong constructor's name and pointed at the wrong normalising factory.
  # Both are derived from what was really matched.
  hit_master=0
  hit_salon=0
  grep -q -- 'BookingsDayQuery\.masterOwn(' <<< "$offenders" &&
    hit_master=1
  grep -q -- 'BookingsDayQuery\.salon(' <<< "$offenders" && hit_salon=1

  if [ "$hit_master" -eq 1 ] && [ "$hit_salon" -eq 1 ]; then
    named='BookingsDayQuery.masterOwn( and BookingsDayQuery.salon('
  elif [ "$hit_salon" -eq 1 ]; then
    named='BookingsDayQuery.salon('
  else
    named='BookingsDayQuery.masterOwn('
  fi

  echo "$named used outside its declaring file:"
  echo "$offenders"
  echo
  echo ".masterOwn() / .salon() are the freezed pass-through constructors of"
  echo "the same sealed union — they skip ALL normalisation. In particular"
  echo "neither truncates day to date-only, so two taps on the same calendar"
  echo "day at 09:14 and 09:15 become two different bookingsDayProvider family"
  echo "members: two fetches for one day the user sees as identical."
  echo
  echo "Use the normalising factory for the member you are building:"
  if [ "$hit_master" -eq 1 ]; then
    echo "    BookingsDayQuery.of(day: ..., statuses: ..., serviceIds: ...)"
  fi
  if [ "$hit_salon" -eq 1 ]; then
    echo "    BookingsDayQuery.salonOf(day: ..., salonId: ..., ...)"
    echo "    BookingsDayQuery.salonDayList(day: ..., salonId: ..., ...)"
  fi
  echo
  echo "It takes Sets and a plain DateTime and canonicalises both — see the"
  echo "file header of lib/features/booking/domain/bookings_day_query.dart."
  exit 1
fi

exit 0
