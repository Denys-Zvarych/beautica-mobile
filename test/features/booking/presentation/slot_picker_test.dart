// Phase 14.1 — Widget tests for SlotDateScreen + SlotTimeScreen.
//
// Covers the phase doc's acceptance criteria:
//   1. Day selection loads that day's slots via SlotRepository.
//   2. "Далі" only advances once a day is selected.
//   3. Unavailable slots are not tappable (selection stays unset).
//   4. Selecting an available slot navigates to /booking/confirm with the
//      correct (masterId, serviceId, startAt) extras, threading a non-null
//      rescheduleBookingId through when present (the Phase 14.8 extension
//      point).
//
// Strategy: mounts the REAL production routes/screens via a test-local
// GoRouter mirroring app_router.dart's shape (bookingSlots → nested "time" →
// bookingConfirm), overriding [slotRepositoryProvider] with a hand-written
// fake so no real Dio request is ever made.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  avgRating: 4.8,
  reviewCount: 12,
  type: MasterType.independentMaster,
);

const _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 грн',
  category: 'MANICURE',
);

BookingSlotPickerArgs _args({String? rescheduleBookingId}) =>
    BookingSlotPickerArgs(
      masterId: _kMaster.id,
      master: _kMaster,
      services: const <MasterService>[_kService],
      rescheduleBookingId: rescheduleBookingId,
    );

/// Records every call so the "loads slots on date change" criterion can be
/// asserted directly, and returns whatever [slotsToReturn] is configured —
/// or throws [errorToThrow] when set (mobile-qa M3: every screen's data
/// fetch needs a failure-path test, not just happy-path fixtures).
class _FakeSlotRepository implements SlotRepository {
  _FakeSlotRepository(this.slotsToReturn, {this.errorToThrow});

  List<BookingSlot> slotsToReturn;
  Object? errorToThrow;
  int callCount = 0;
  String? lastMasterId;
  String? lastServiceId;
  DateTime? lastDate;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required String serviceId,
    required DateTime date,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    lastMasterId = masterId;
    lastServiceId = serviceId;
    lastDate = date;
    final Object? err = errorToThrow;
    if (err != null) throw err;
    return slotsToReturn;
  }
}

/// Builds the test-local router mirroring `app_router.dart`'s bookingSlots /
/// bookingSlots/time / bookingConfirm shape, with the confirm route rendering
/// the received [BookingConfirmArgs] as plain text so tests can assert the
/// exact extras that arrived.
GoRouter _router({required Widget dateScreen}) => GoRouter(
  initialLocation: RouteNames.bookingSlots,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.bookingSlots,
      builder: (context, state) => dateScreen,
      routes: <RouteBase>[
        GoRoute(
          path: 'time',
          builder: (context, state) =>
              SlotTimeScreen(args: state.extra! as BookingSlotPickerArgs),
        ),
      ],
    ),
    GoRoute(
      path: RouteNames.bookingConfirm,
      builder: (context, state) {
        final BookingConfirmArgs args = state.extra! as BookingConfirmArgs;
        return Scaffold(
          body: Text(
            'confirm-stub:${args.masterId}:${args.serviceId}:'
            '${args.startAt.toIso8601String()}:${args.rescheduleBookingId}',
          ),
        );
      },
    ),
  ],
);

void main() {
  group('SlotDateScreen', () {
    testWidgets('tapping an available day loads that day\'s slots', (
      tester,
    ) async {
      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      final router = _router(dateScreen: SlotDateScreen(args: _args()));

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      final DateTime today = DateTime.now();
      final Finder todayCell = find.byKey(
        Key('booking-calendar-day-${today.day}'),
      );
      expect(todayCell, findsOneWidget);

      await tester.tap(todayCell);
      await tester.pumpAndSettle();

      expect(fake.callCount, 1);
      expect(fake.lastMasterId, _kMaster.id);
      expect(fake.lastServiceId, _kService.id);
      expect(fake.lastDate, DateTime(today.year, today.month, today.day));
    });

    testWidgets('«Далі» does not advance before a day is selected, and '
        'advances to the time screen once one is', (tester) async {
      final fake = _FakeSlotRepository(const <BookingSlot>[]);
      final router = _router(dateScreen: SlotDateScreen(args: _args()));

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      final Finder cta = find.byKey(const Key('booking-summary-cta'));
      expect(cta, findsOneWidget);

      // No day selected yet: tapping "Далі" must not navigate.
      await tester.tap(cta);
      await tester.pumpAndSettle();
      expect(find.byType(SlotTimeScreen), findsNothing);

      // Select today, then advance.
      final DateTime today = DateTime.now();
      await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(SlotTimeScreen), findsOneWidget);
    });
  });

  group('SlotTimeScreen', () {
    final BookingSlot available = BookingSlot(
      startAt: DateTime(2026, 7, 20, 10),
      endAt: DateTime(2026, 7, 20, 11),
      available: true,
    );
    final BookingSlot unavailable = BookingSlot(
      startAt: DateTime(2026, 7, 20, 12),
      endAt: DateTime(2026, 7, 20, 13),
      available: false,
    );

    /// Pumps the date screen (so its notifier stays mounted underneath), then
    /// pushes straight to the time screen with a FIXED [SlotPickerState] —
    /// avoids re-deriving the fixture through a real `loadSlots` round-trip.
    Future<GoRouter> pumpTimeScreen(
      WidgetTester tester, {
      required BookingSlotPickerArgs args,
    }) async {
      final fake = _FakeSlotRepository(<BookingSlot>[available, unavailable]);
      final router = _router(dateScreen: SlotDateScreen(args: args));

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      // Tap "today" — always available regardless of which real-world date
      // the test runs on. The fake repository returns the SAME pre-seeded
      // fixture list ([available], [unavailable]) no matter which date is
      // requested, so the exact tapped day-of-month is irrelevant to the
      // fixture that ends up in `slotPickerProvider.slots`.
      final DateTime today = DateTime.now();
      await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      return router;
    }

    // mobile-qa M3 / coverage gap closed 2026-07-02: neither this file nor
    // any prior QA pass exercised `SlotRepository.getMasterSlots` FAILING —
    // only empty/available/unavailable happy-path fixtures. `_SlotsSection`
    // deliberately renders the SAME soft "no slots" copy for both an empty
    // result and a fetch error (no scary error banner — see
    // `slot_picker_screen.dart`'s `_SlotsSection.build`), so this pins that
    // a failure never crashes the screen or leaves a stuck spinner, and that
    // «Підтвердити» stays disabled (no slot can ever be selected).
    testWidgets(
      'when the slots fetch fails, the day-unavailable message renders '
      'instead of crashing or leaving a spinner, and «Підтвердити» stays '
      'disabled',
      (tester) async {
        final fake = _FakeSlotRepository(
          const <BookingSlot>[],
          errorToThrow: const NetworkFailure(),
        );
        final router = _router(dateScreen: SlotDateScreen(args: _args()));

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
        );
        await tester.pumpAndSettle();

        final DateTime today = DateTime.now();
        await tester.tap(find.byKey(Key('booking-calendar-day-${today.day}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();

        expect(find.byType(SlotTimeScreen), findsOneWidget);
        expect(fake.callCount, 1);

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SlotTimeScreen)),
        );
        expect(find.text(l10n.bookingDayUnavailableState), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SlotChip), findsNothing);

        // No slot can be selected from an empty/failed render — the CTA
        // must never fire a navigation.
        await tester.tap(find.byKey(const Key('booking-summary-cta')));
        await tester.pumpAndSettle();
        expect(find.textContaining('confirm-stub:'), findsNothing);
      },
    );

    testWidgets('unavailable slot chips are not tappable — selecting one '
        'does not enable «Підтвердити»', (tester) async {
      await pumpTimeScreen(tester, args: _args());

      expect(find.byType(SlotTimeScreen), findsOneWidget);

      final Finder unavailableChip = find.byWidgetPredicate(
        (Widget w) => w is SlotChip && !w.available,
      );
      expect(unavailableChip, findsOneWidget);

      await tester.tap(unavailableChip, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Still on the time screen: the disabled CTA never fired a push.
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();
      expect(find.textContaining('confirm-stub:'), findsNothing);
    });

    testWidgets('selecting an available slot enables «Підтвердити» and '
        'navigates to /booking/confirm with the correct extras', (
      tester,
    ) async {
      await pumpTimeScreen(
        tester,
        args: _args(rescheduleBookingId: 'booking-99'),
      );

      final Finder availableChip = find.byWidgetPredicate(
        (Widget w) => w is SlotChip && w.available,
      );
      expect(availableChip, findsOneWidget);

      await tester.tap(availableChip);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('confirm-stub:${_kMaster.id}:${_kService.id}:'),
        findsOneWidget,
      );
      expect(find.textContaining(':booking-99'), findsOneWidget);
    });
  });
}
