// Prod hotfix (Sentry, 1.9.0+12) — DAY-family twin of
// `master_bookings_week_reschedule_return_flow_test.dart`.
//
//   Salon owner «Записи» board (the real `bookingsDayProvider` consumer, a
//   `SalonDayQuery`) → card → detail → «Перенести» → date → time → confirm
//   (the reschedule fans out `invalidateBookingsDayAfterAppointmentItemReschedule`
//   while the board is covered) → success → «На головну» (the board is
//   replaced) → back to «Записи» → the board renders and survives a rebuild.
//
// NAVIGATION GUARD ONLY — this flow does NOT pin
// `DayKeepAliveLru.forget` in `BookingsDayNotifier.build`'s onDispose
// (falsified 2026-11-15: staying GREEN with that line removed, also with a
// status filter applied). The real salon board cannot reach the dead-link
// state: (a) the invalidated, covered board member is recomputed by the app
// within ~3 frames (fetch count 1 -> 2 with the board's TickerMode off), so no
// dead link is left; (b) a filtered member cannot be the remount key — the
// filter is `State` of the discovery view and resets on unmount. The
// deterministic repro stays
// `test/features/booking/presentation/bookings_day_header_closed_subscription_test.dart`.
//
// Headless: `flutter test integration_test/
// salon_board_reschedule_return_flow_test.dart -d flutter-tester`.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_timeline_grid.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';
import 'support/kyiv_wall_clock.dart';

const Key _kCard = ValueKey<String>('timeline-card-booking-1');

Future<void> _openBoard(WidgetTester tester) async {
  final Finder bookingsTab = find.byKey(const Key('salon-nav-tile-1'));
  await AppHarness.pumpUntilFound(
    tester,
    bookingsTab.hitTestable(),
    timeout: const Duration(seconds: 20),
  );
  await tester.tap(bookingsTab);
  await tester.pump();
  await AppHarness.pumpUntilFound(
    tester,
    find.byType(BookingsTimelineGrid),
    timeout: const Duration(seconds: 20),
  );
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(_kCard).hitTestable(),
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _pickNewDateAndTime(WidgetTester tester) async {
  expect(find.byType(SlotDateScreen), findsOneWidget);
  await AppHarness.settle(tester);
  await tester.tapCalendarDay(kyivToday(() => kFixedNow).day);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);
  expect(find.byType(SlotTimeScreen), findsOneWidget);
  final Finder chip = find.byWidgetPredicate(
    (Widget w) => w is SlotChip && w.available,
  );
  expect(chip, findsWidgets);
  await tester.tap(chip.first);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'salon «Записи» board → reschedule a booking → home → back to «Записи»: '
    'the day board renders and survives a rebuild (no closed-subscription '
    'StateError)',
    (WidgetTester tester) async {
      await mockNetworkImagesFor(() async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = UserRole.salonOwner
          ..bookingMasterType = 'SALON_MASTER'
          ..bookingProviderCanReviewClient = false;
        await AppHarness.boot(tester, fb);

        // 16:00 Kyiv on the board's own day, later than `kFixedNow`, so the
        // fan-out's `affectedDays` hits the live board member.
        final DateTime start = kyivWallClockUtc(
          kyivToday(() => kFixedNow),
          16,
          0,
        );
        fb
          ..bookingStartsAt = start.toIso8601String()
          ..bookingEndsAt = start
              .add(const Duration(minutes: 60))
              .toIso8601String()
          ..salonBoardBookings = <Map<String, dynamic>>[
            fb.salonBoardBookingRow(
              id: 'booking-1',
              masterId: 'master-aaa',
              masterFirstName: 'Софія',
              masterLastName: 'Бондар',
              startsAt: start,
            ),
          ];
        await AppHarness.loginAs(tester, fb, UserRole.salonOwner);
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(SalonShellScreen),
          timeout: const Duration(seconds: 20),
        );
        await _openBoard(tester);
        expect(find.byType(SalonBookingsScreen), findsOneWidget);

        await tester.tap(find.byKey(_kCard));
        await tester.pump();
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingDetailScreen),
          timeout: const Duration(seconds: 20),
        );
        await AppHarness.settle(tester);

        await tester.tap(
          find.byKey(const Key('booking-detail-provider-reschedule')),
        );
        await AppHarness.settle(tester);
        await _pickNewDateAndTime(tester);
        expect(find.byType(BookingConfirmScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
        await AppHarness.settle(tester);
        expect(find.byType(BookingSuccessScreen), findsOneWidget);
        expect(fb.rescheduleBookingCalls, 1);

        await tester.tap(find.byKey(const Key('booking-success-home-cta')));
        await AppHarness.settle(tester);
        expect(find.byType(BookingSuccessScreen), findsNothing);

        // Back to the board (reaching it from wherever «home» landed).
        if (find.byType(BookingsTimelineGrid).evaluate().isEmpty) {
          await _openBoard(tester);
        }
        await AppHarness.pumpUntilFound(
          tester,
          find.byType(BookingsTimelineGrid),
          timeout: const Duration(seconds: 20),
        );
        expect(find.byType(SalonBookingsScreen), findsOneWidget);

        // A header rebuild after the return: the month-calendar toggle
        // `setState`s the discovery view, re-running the day Consumer's
        // `ref.watch(bookingsDayProvider(liveQuery))` — the read that threw
        // "ProviderSubscription.read on a subscription that was closed".
        final Finder monthToggle = find.byKey(
          const Key('bookings-month-calendar-toggle'),
        );
        await tester.tap(monthToggle);
        await AppHarness.settle(tester);
        await tester.tap(monthToggle);
        await AppHarness.settle(tester);
        expect(find.byType(BookingsTimelineGrid), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    },
  );
}
