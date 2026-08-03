// mobile-qa (Phase 225 fix pass, mobile-perf MEDIUM #4) — direct unit
// coverage for `invalidateBookingViewsAfterExternalDecline`
// (`booking_calendar_invalidation.dart:83`), specifically its NEWEST fan-out
// target: `nextAppointmentProvider` (added at line 96 for Phase 225's Home
// Hub «Найближчий запис» card).
//
// The function's other four targets — `bookingDetailProvider(id)` (one per
// declined id), `bookingsDayProvider(day)` (one per affected date), and BOTH
// `myBookingsProvider` tabs (upcoming/cancelled) — are already asserted
// end-to-end via the REAL `DayHoursSheet` UI flow in
// `test/features/schedule/presentation/day_hours_sheet_test.dart`'s
// "booking-calendar invalidation is asserted directly" group. Only
// `nextAppointmentProvider` was left uncovered when it was added to the
// fan-out, so this file adds ONLY that assertion — at the cheapest tier that
// proves it directly: a bare `Consumer` button that calls the function with a
// real `WidgetRef` (mirrors `reschedule_navigation_test.dart`'s `_NavProbe`
// pattern), not a full `DayHoursSheet`/`OverridesNotifier` drive.
//
// TRAP AVOIDED: `ref.invalidate` on an already-loaded provider performs a
// SEAMLESS reload — the previous `.value` is retained while the new fetch is
// in flight (Riverpod 3.x). A null-then-value assertion would therefore never
// fire; the refetch COUNT (via a counting provider override, not a
// null-then-value comparison) is the only reliable signal — same technique
// `day_hours_sheet_test.dart`'s own invalidation group already uses.

import 'package:beautica_mobile/features/booking/application/booking_calendar_invalidation.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

void main() {
  testWidgets('invalidateBookingViewsAfterExternalDecline invalidates '
      'nextAppointmentProvider — a declined booking may have been the '
      "client's soonest upcoming appointment", (tester) async {
    int nextApptFetches = 0;

    await tester.pumpApp(
      Scaffold(
        body: Consumer(
          builder: (BuildContext context, WidgetRef ref, _) => TextButton(
            key: const Key('invalidate'),
            onPressed: () => invalidateBookingViewsAfterExternalDecline(
              ref,
              const <String>['booking-1'],
              // future-date-ok: arbitrary bookingsDayProvider invalidation target, never read through BookingDisplayX.isPast — the test only counts nextAppointmentProvider refetches, so this date's value is inconsequential.
              affectedDates: <DateTime>[DateTime.utc(2026, 7, 20)],
            ),
            child: const Text('invalidate'),
          ),
        ),
      ),
      overrides: <Object>[
        nextAppointmentProvider.overrideWith((ref) async {
          nextApptFetches++;
          return null;
        }),
      ],
    );

    // Hold a LIVE subscription so the invalidate triggers a genuine
    // refetch instead of Riverpod simply dropping an unwatched autoDispose
    // member.
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('invalidate'))),
      listen: false,
    );
    final ProviderSubscription<AsyncValue<Booking?>> sub = container.listen(
      nextAppointmentProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await container.read(nextAppointmentProvider.future);
    expect(
      nextApptFetches,
      1,
      reason: 'sanity: the provider must have fetched once before any tap',
    );

    await tester.tap(find.byKey(const Key('invalidate')));
    await tester.pumpAndSettle();

    await container.read(nextAppointmentProvider.future);
    expect(
      nextApptFetches,
      2,
      reason:
          'invalidateBookingViewsAfterExternalDecline must invalidate '
          'nextAppointmentProvider — this is the specific line the Phase '
          '225 fan-out added, and only a refetch proves it actually fires',
    );
  });
}
