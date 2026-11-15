// Prod hotfix (Sentry, 1.9.0+12) — «Записи» week header after a reschedule.
//
//   «Записи» (week) → booking card → detail → «Перенести» → date → time →
//   confirm → success (the reschedule fans out invalidations while «Записи»
//   is covered) → «На головну» (`go(/master/profile)`, the bookings screen is
//   replaced) → back to «Записи» → a header rebuild («День» toggle).
//
// Pre-fix: `KeepAliveLru` kept a dead keep-alive link; on return `touch`
// closed it and Riverpod disposed the NEW live week element, so the header
// threw "ProviderSubscription.read on a subscription that was closed".
//
// FALSIFIABILITY: the exact prod failure needs the covered week to be
// invalidated WITHOUT an evict, then dropped to zero listeners. See the
// result recorded in the QA report for whether this real-screen flow went
// red against the unfixed notifier; the deterministic repros are
// `test/features/booking/presentation/bookings_{week,day}_header_closed_
// subscription_test.dart`.
//
// Headless: `flutter test integration_test/
// master_bookings_week_reschedule_return_flow_test.dart -d flutter-tester`.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/application/master_bookings_view_mode.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/week_time_grid.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/api_date.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';
import 'support/week_grid_driver.dart';

/// `booking-1` later TODAY (injected clock, 12:00 UTC) so it sits in the
/// landing week and is not yet started — «Перенести» stays live.
void _seedBookingLaterToday(FakeBackend fb) {
  final DateTime today = dateOnly(toBeauticaTime(kFixedNow));
  final DateTime start = DateTime.utc(today.year, today.month, today.day, 15);
  fb
    ..bookingStartsAt = start.toIso8601String()
    ..bookingEndsAt = start.add(const Duration(minutes: 60)).toIso8601String();
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
    '«Записи» week → reschedule a booking → home → back to «Записи»: the week '
    'header renders and survives a rebuild (no closed-subscription StateError)',
    (WidgetTester tester) async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.independentMaster;
      final GoRouter router = await AppHarness.boot(tester, fb);
      _seedBookingLaterToday(fb);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      final Finder card = find.byKey(WeekTimeGrid.cardKey('booking-1'));
      await tester.ensureVisible(card);
      await AppHarness.settle(tester);
      await tester.tap(card);
      await AppHarness.settle(tester);
      expect(find.byType(BookingDetailScreen), findsOneWidget);

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

      // «На головну» → go(/master/profile): «Записи» is replaced.
      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterProfileScreen), findsOneWidget);
      expect(find.byType(MasterBookingsScreen), findsNothing);

      // Back to «Записи»: a fresh week element must be live.
      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      await AppHarness.pumpUntilFound(tester, find.byType(WeekTimeGrid));
      AppHarness.expectLocation(router, RouteNames.masterBookings);
      expect(find.byType(WeekTimeGrid), findsOneWidget);
      expect(find.byKey(WeekTimeGrid.cardKey('booking-1')), findsWidgets);

      // Header rebuild: the view toggle re-runs the header's `ref.watch`.
      await switchViewMode(
        tester,
        BookingsWeekViewMode.day,
        settle: AppHarness.settle,
      );
      await switchViewMode(
        tester,
        BookingsWeekViewMode.threeDays,
        settle: AppHarness.settle,
      );
      expect(find.byType(WeekTimeGrid), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
