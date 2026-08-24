#!/usr/bin/env bash
# Phase 271 D5 — structural guard: the deleted per-master salon submit
# notifier must never come back under lib/.
#
# THE REGRESSION THIS GUARDS
# --------------------------
# `lib/features/booking/application/salon_booking_submit_notifier.dart` (231
# lines, `SalonBookingSubmit` notifier + `SalonAppointmentSubmitStatus` enum)
# implemented a PER-MASTER booking write: N assigned masters -> N separate
# `POST /bookings` calls, each carrying `serviceId:
# a.schedule.primaryServiceAssignmentId` — the master's FIRST assigned
# service only. A master with 2+ assigned services silently dropped every
# service after the first: no error, no warning, the success screen reported
# success. This track's locked model is PER SERVICE (Phase 267 D1): 1 service
# = 1 booking, 1 reschedule, 1 cancellation, 1 completion, 1 feedback.
#
# The file was deleted once already by MO-4, then RESURRECTED by a
# `git checkout` of an ancestor commit during Phase 268's restore (done
# deliberately, to read what its 573-line test pinned — see Phase 271's doc).
# A gate that has never actually run cannot be trusted to catch a repeat of
# that same `git checkout` move — this guard exists so a future restore is
# caught mechanically instead of shipping.
#
# THE RULE
# --------
# Zero occurrences under lib/ of:
#   - the filename `salon_booking_submit_notifier` (source file or import)
#   - the symbol `SalonBookingSubmit` (the notifier class + its generated
#     provider name `salonBookingSubmitProvider`, its state class
#     `SalonBookingSubmitState`)
#   - the symbol `SalonAppointmentSubmitStatus` (its per-appointment status
#     enum)
#
# Phase 277's replacement (`SalonMultiBookingSubmit`, composed over the
# shared `AppointmentSubmit.submitBooking`) uses a DIFFERENT name by design
# (Phase 271 D1's rejected runner-up was reviving this exact file under its
# existing name) — so this guard does not need an allow-list carve-out for
# a legitimate successor.
#
# CI hard-gate (run from `.github/workflows/pr-validate.yml`); also runnable
# locally before pushing.
# Self-test:  ./scripts/forbid_salon_booking_submit_notifier.sh --self-test

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

# ---------------------------------------------------------------------------
# run_scan <scan_root>
#   Emits "<path>:<line>:<text>" for every forbidden occurrence under
#   <scan_root>/lib. `grep -a` is deliberate: at least one test-adjacent file
#   in this repo contains a control character and reads as binary, silently
#   skipping under a plain `grep -r` (see forbid_cyrillic_finder.sh's own
#   note on the same footgun) — lib/ is smaller but there is no reason to
#   trust it can't happen there too.
# ---------------------------------------------------------------------------
run_scan() {
  local scan_root="$1"
  (
    cd "$scan_root" && grep -a -rEn \
      'salon_booking_submit_notifier|SalonBookingSubmit|SalonAppointmentSubmitStatus' \
      lib/ 2>/dev/null | sort || true
  )
}

# ---------------------------------------------------------------------------
# Self-test mode: synthesize a tree with one clean file and one offender
# (a bare re-import, mirroring the exact mutation this guard exists to catch
# — see Phase 271's mutation check), assert only the offender is flagged.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/lib/features/booking/presentation"

  # A clean, unrelated file — must NOT be flagged.
  cat > "$tmp/lib/features/booking/presentation/salon_booking_confirm_screen.dart" <<'EOF'
import '../application/booking_notifier.dart';
class SalonBookingConfirmScreen {}
EOF

  # The offending re-import — must be flagged.
  cat > "$tmp/lib/features/booking/presentation/salon_time_screen.dart" <<'EOF'
import '../application/salon_booking_submit_notifier.dart';
EOF

  out="$(run_scan "$tmp")"
  flagged="$(printf '%s\n' "$out" | grep -c . || true)"

  if [ "$flagged" -ne 1 ] ||
    ! printf '%s' "$out" | grep -q 'salon_time_screen.dart:1'; then
    echo "SELF-TEST FAIL: expected exactly 1 hit (salon_time_screen.dart),"
    echo "                got:"
    printf '%s\n' "$out"
    exit 1
  fi
  echo "SELF-TEST PASS: the clean confirm-screen file is not flagged; the"
  echo "                re-imported salon_booking_submit_notifier.dart is."
  echo "SELF-TEST OK: forbid_salon_booking_submit_notifier.sh"
  exit 0
fi

# ---------------------------------------------------------------------------
# Real run over the working tree.
# ---------------------------------------------------------------------------
offenders="$(run_scan "$root")"
count="$(printf '%s\n' "$offenders" | grep -c . || true)"

if [ "$count" -ne 0 ]; then
  echo "salon_booking_submit_notifier / SalonBookingSubmit / SalonAppointmentSubmitStatus found under lib/ ($count hit(s)):"
  echo "$offenders"
  echo
  echo "This is the deleted PER-MASTER salon booking notifier (Phase 271)."
  echo "It builds one CreateBookingRequest per MASTER (serviceId ="
  echo "a.schedule.primaryServiceAssignmentId), silently dropping every"
  echo "service after a master's first assigned one. The locked model is"
  echo "PER SERVICE (Phase 267 D1)."
  echo
  echo "Do not restore this file. The replacement is Phase 277's"
  echo "SalonMultiBookingSubmit, composed over the shared"
  echo "AppointmentSubmit.submitBooking — see docs/mobile-phases/"
  echo "phase-277-multi-booking-submit-orchestration.md."
  exit 1
fi

exit 0
