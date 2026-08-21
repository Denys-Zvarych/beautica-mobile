// Shared assertion for the PROVIDER footer's "reschedule visible but inert"
// state on an underway/elapsed CONFIRMED booking.
//
// WHY THIS EXISTS
// ----------------
// `booking_detail_screen.dart`'s `_providerActions` (the
// `booking.hasStartedAt(now)` branch) deliberately keeps
// «Перенести»/`booking-detail-provider-reschedule` VISIBLE but INERT
// (`onPressed: null`, plus a permanent caption keyed
// `booking-detail-reschedule-unavailable-reason`) once a booking has
// started, instead of omitting the button — a vanished CTA read to a master
// as "the app can't reschedule this" rather than "this booking specifically
// can't move" (fix landed in `ef521cace`, 2026-08-20).
//
// Originally a private closure duplicated inline in
// `master_booking_provider_actions_flow_test.dart`. Per this repo's
// REUSE-FIRST rule, promoted here so BOTH the plain-booking and the
// appointment-child E2E suites assert the exact same three-part shape
// instead of each carrying (and independently drifting) their own copy —
// which is exactly how `master_appointment_child_booking_actions_flow_test
// .dart` went stale for a full commit cycle: it kept the OLD `findsNothing`
// shape the private closure had already been fixed away from in its sibling
// file.
//
// Asserting the INERT shape (present + null handler + caption) is strictly
// stronger than a bare `findsNothing`/`findsOneWidget`: it pins the exact
// three-part state the UX fix specifies, not merely the button's presence.
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts the PROVIDER footer's «Перенести» button is rendered VISIBLE but
/// INERT — present, `onPressed: null`, and paired with its permanent
/// unavailable-reason caption. Use on any underway/elapsed CONFIRMED
/// booking, plain or appointment-child alike — `_providerActions` gates on
/// `booking.hasStartedAt(now)` only, never on `appointmentId`.
void expectRescheduleVisibleButInert(WidgetTester tester) {
  final Finder reschedule = find.byKey(
    const Key('booking-detail-provider-reschedule'),
  );
  expect(
    reschedule,
    findsOneWidget,
    reason:
        'an underway booking keeps «Перенести» VISIBLE — omitting it reads '
        'as an app limitation rather than a fact about this booking',
  );
  expect(
    tester.widget<NeumorphicButton>(reschedule).onPressed,
    isNull,
    reason:
        '…but INERT: the backend still rejects a reschedule once the '
        'booking has started',
  );
  expect(
    find.byKey(const Key('booking-detail-reschedule-unavailable-reason')),
    findsOneWidget,
    reason:
        'the reason renders as a permanent caption — a hidden explanation '
        'is the same silent-omission bug in a new costume',
  );
}
