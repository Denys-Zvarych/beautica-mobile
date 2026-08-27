// Shared assertion for the PROVIDER footer's reschedule affordance on an
// underway/elapsed CONFIRMED booking.
//
// WHY THIS EXISTS
// ----------------
// `booking_detail_screen.dart`'s `_providerActions` (the
// `booking.hasStartedAt(now)` branch) used to keep
// «Перенести»/`booking-detail-provider-reschedule` VISIBLE but INERT
// (`onPressed: null`, plus a permanent caption keyed
// `booking-detail-reschedule-unavailable-reason`) once a booking has
// started, instead of omitting the button (`ef521cace`, 2026-08-20).
//
// USER-LOCKED REVERSAL (this session): the user overruled that — a button
// that can never be tapped is never shown, for both the underway and the
// fully-elapsed sub-cases `hasStartedAt` covers. `expectRescheduleAbsent`
// replaces the old `expectRescheduleVisibleButInert` (deleted, no other
// caller). Kept SHARED rather than inlined per REUSE-FIRST: both the
// plain-booking and the appointment-child E2E suites assert the same shape.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts the PROVIDER footer omits «Перенести» entirely — no button, no
/// unavailable-reason caption — on an underway/elapsed CONFIRMED booking.
/// Use on any such booking, plain or appointment-child alike —
/// `_providerActions` gates on `booking.hasStartedAt(now)` only, never on
/// `appointmentId`.
void expectRescheduleAbsent(WidgetTester tester) {
  expect(
    find.byKey(const Key('booking-detail-provider-reschedule')),
    findsNothing,
    reason:
        'a reschedule that can never succeed on this booking must not be '
        'offered at all — the vanished-CTA UX concern was overruled by the '
        'user for the underway/past case',
  );
  expect(
    find.byKey(const Key('booking-detail-reschedule-unavailable-reason')),
    findsNothing,
    reason: 'the caption is pointless once the button it explains is gone',
  );
}
