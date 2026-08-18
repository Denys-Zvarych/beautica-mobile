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
# Zero `BookingsDayQuery.masterOwn(` under lib/ and test/, except in the
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
    cd "$scan_root" && grep -rEn 'BookingsDayQuery\.masterOwn\(' \
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

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  if [ "$flagged" -ne 2 ] ||
    ! printf '%s' "$out" | grep -q 'leaky_test.dart:1' ||
    ! printf '%s' "$out" | grep -q 'leaky_e2e_test.dart:1'; then
    echo "SELF-TEST FAIL: expected the leaky_test.dart AND leaky_e2e_test.dart"
    echo "                sites flagged (and nothing else), got:"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: the declaring file and .freezed.dart codegen are exempt;"
  echo "                the BookingsDayQuery.masterOwn( calls under test/ AND"
  echo "                integration_test/ are both flagged."
  echo "SELF-TEST OK: forbid_raw_bookings_query.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root")"

if [ -n "$offenders" ]; then
  echo "BookingsDayQuery.masterOwn( used outside its declaring file:"
  echo "$offenders"
  echo
  echo ".masterOwn() is the freezed pass-through constructor — it skips ALL"
  echo "normalisation. In particular it does NOT truncate day to date-only,"
  echo "so two taps on the same calendar day at 09:14 and 09:15 become two"
  echo "different bookingsDayProvider family members: two fetches for one day"
  echo "the user sees as identical."
  echo
  echo "Use the normalising factory instead:"
  echo "    BookingsDayQuery.of(day: ..., statuses: ..., serviceIds: ...)"
  echo
  echo "It takes Sets and a plain DateTime and canonicalises both — see the"
  echo "file header of lib/features/booking/domain/bookings_day_query.dart."
  exit 1
fi

exit 0
