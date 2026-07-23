// mobile-qa (multi-service booking rework) — widget tests for
// `BookingTimeScreen`, the independent-master flow's per-service time step: a
// horizontal `PageView`, one slide per selected service, each picking its OWN
// date + time.
//
// Covers the acceptance bar for the SCHEDULE half of the rework — the part the
// fake-backed `integration_test/independent_multi_service_booking_flow_test.dart`
// deliberately pushes PAST (it enters at `/booking/confirm` with the
// appointments already resolved, mirroring the salon partial-failure variant):
//   1. Two selected services render exactly two slides (two pager dots).
//   2. Completing a service's date+time AUTO-ADVANCES the slider to the next
//      unscheduled service (no manual tap).
//   3. Once BOTH slides carry a date + time, «Підтвердити» is enabled and
//      snapshots the picks into TWO `BookingAppointment`s — distinct serviceId,
//      distinct chosen `startAt`, and a distinct NON-EMPTY stable idempotency
//      key each (generated once here, per `BookingTimeScreen._confirm`).
//   4. Sibling pre-disable: once one service is scheduled on a date, the slot
//      chips on a SIBLING service's SAME-day time grid that would overlap that
//      chosen window are rendered UNAVAILABLE and are non-tappable — the app
//      computes availability so the client can never reach an overlapping
//      selection through the UI. The post-pick self-overlap guard
//      (`_hasOverlap`, pre-empting the backend's per-appointment
//      CLIENT_BOOKING_CONFLICT 409) stays in the code as a defensive backstop
//      but is no longer reachable via this two-slide flow. (The exhaustive
//      disable-logic matrix is authored separately by mobile-qa.)
//
// Strategy mirrors `salon_time_screen_test.dart`: mounts the REAL production
// screen via a test-local GoRouter whose `/booking/confirm` route is a STUB
// that captures the pushed `BookingConfirmArgs` (so no booking-creation
// provider is ever touched by this screen's tests), overriding
// `slotRepositoryProvider` with a hand-written fake so no real Dio request is
// made.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/slot_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking_appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/working_day.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_time_screen.dart';
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
  city: 'Київ',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  avgRating: 4.8,
  reviewCount: 47,
  type: MasterType.independentMaster,
);

const _svcA = MasterService(
  id: 'svc-a',
  serviceDefId: 'def-a',
  name: 'Манікюр з покриттям',
  durationMinutes: 60,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

const _svcB = MasterService(
  id: 'svc-b',
  serviceDefId: 'def-b',
  name: 'Педикюр апаратний',
  durationMinutes: 60,
  priceMin: 400,
  priceDisplay: '400 ₴',
  category: 'NAILS',
);

BookingSlotPickerArgs _args() => const BookingSlotPickerArgs(
  masterId: 'master-1',
  master: _kMaster,
  services: <MasterService>[_svcA, _svcB],
);

/// Tall surface so the slot-chip grid (below the calendar, reachable only after
/// the date phase swaps to the time phase) is fully on-screen without
/// scrolling — mirrors `salon_time_screen_test.dart`'s identical `_pumpTall`.
Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Every requested day resolves `working: true`; every `getMasterSlots` call
/// returns [slotsToReturn] regardless of service/date — the same shared list
/// for both slides (their `independent-slot-chip-<iso>` keys never collide
/// because every finder below is scoped to ONE slide's page key). Mirrors
/// `slot_picker_test.dart`'s `_FakeSlotRepository` shape.
class _FakeSlotRepository implements SlotRepository {
  _FakeSlotRepository(this.slotsToReturn);

  final List<BookingSlot> slotsToReturn;

  @override
  Future<List<BookingSlot>> getMasterSlots({
    required String masterId,
    required List<String> serviceIds,
    required DateTime date,
    CancelToken? cancelToken,
  }) async => slotsToReturn;

  @override
  Future<List<WorkingDay>> getWorkingDays({
    required String masterId,
    required DateTime from,
    required DateTime to,
    List<String>? serviceIds,
    CancelToken? cancelToken,
  }) async {
    final List<WorkingDay> days = <WorkingDay>[];
    for (
      DateTime d = from;
      !d.isAfter(to);
      d = d.add(const Duration(days: 1))
    ) {
      days.add(WorkingDay(date: d, working: true));
    }
    return days;
  }
}

/// Test-local router mirroring `app_router.dart`'s bookingSlotsTime →
/// bookingConfirm shape, capturing the `BookingConfirmArgs` that reaches the
/// confirm STUB so «Підтвердити»'s pure-forward-navigation payload can be
/// asserted precisely. The stub renders plain text (never the real
/// `BookingConfirmScreen`), so no `IndependentBookingSubmit` /
/// `bookingRepositoryProvider` is ever touched by this screen's tests.
GoRouter _router({
  required BookingSlotPickerArgs args,
  ValueChanged<BookingConfirmArgs>? onReachedConfirm,
}) => GoRouter(
  initialLocation: RouteNames.bookingSlotsTime,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.bookingSlotsTime,
      builder: (BuildContext context, GoRouterState state) =>
          BookingTimeScreen(args: args),
    ),
    GoRoute(
      path: RouteNames.bookingConfirm,
      builder: (BuildContext context, GoRouterState state) {
        onReachedConfirm?.call(state.extra! as BookingConfirmArgs);
        return const Scaffold(body: Text('confirm-reached'));
      },
    ),
  ],
);

void main() {
  // Slot fixtures — two non-overlapping windows offered on every day. Built off
  // DateTime.now() (the screen's own `_today`), so "today" is always inside the
  // 3-month calendar horizon.
  final DateTime today = DateTime.now();
  DateTime at(int hour) => DateTime(today.year, today.month, today.day, hour);
  final BookingSlot morning = BookingSlot(
    startAt: at(10),
    endAt: at(11),
    available: true,
  );
  final BookingSlot afternoon = BookingSlot(
    startAt: at(14),
    endAt: at(15),
    available: true,
  );

  /// A finder scoped to ONE slide's `ServiceSchedulePage` (by service id), so
  /// the two slides' shared `booking-calendar-day-<n>` /
  /// `independent-slot-chip-<iso>` keys are never ambiguous. Default
  /// `skipOffstage: true` — every interaction below targets the CURRENT
  /// (on-screen) slide, which is exactly what auto-advance is meant to bring
  /// into view.
  Finder inSlide(String serviceId, Finder matching) => find.descendant(
    of: find.byKey(Key('service-schedule-page-$serviceId')),
    matching: matching,
  );

  Finder calendarDay(String serviceId) =>
      inSlide(serviceId, find.byKey(Key('booking-calendar-day-${today.day}')));

  Finder slotChip(String serviceId, DateTime start) => inSlide(
    serviceId,
    find.byKey(Key('independent-slot-chip-${start.toIso8601String()}')),
  );

  NeumorphicButton confirmCta(WidgetTester tester) =>
      tester.widget<NeumorphicButton>(
        find.byKey(const Key('booking-time-confirm-cta')),
      );

  testWidgets('renders one slide per selected service, each with a pager dot', (
    tester,
  ) async {
    final fake = _FakeSlotRepository(<BookingSlot>[morning, afternoon]);
    await tester.pumpRoutedApp(
      _router(args: _args()),
      overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
    );
    await tester.pumpAndSettle();

    // The first (unscheduled) service's slide is current; the pager reports
    // both services.
    expect(
      find.byKey(const Key('service-schedule-page-svc-a')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('booking-time-pager-dot-0')), findsOneWidget);
    expect(find.byKey(const Key('booking-time-pager-dot-1')), findsOneWidget);

    // Two selected services → the «Підтвердити» CTA starts disabled (nothing
    // scheduled yet).
    expect(confirmCta(tester).onPressed, isNull);
  });

  testWidgets(
    'scheduling service A auto-advances the slider to service B, and once '
    'BOTH are scheduled «Підтвердити» snapshots two appointments with distinct '
    'serviceIds, distinct starts, and distinct non-empty stable idempotency '
    'keys',
    (tester) async {
      await _pumpTall(tester);
      final fake = _FakeSlotRepository(<BookingSlot>[morning, afternoon]);
      BookingConfirmArgs? captured;
      await tester.pumpRoutedApp(
        _router(
          args: _args(),
          onReachedConfirm: (BookingConfirmArgs a) => captured = a,
        ),
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      // ── Slide A: pick today's date, then the 10:00 window ────────────────
      await tester.tap(calendarDay('svc-a'));
      await tester.pumpAndSettle();
      await tester.tap(slotChip('svc-a', at(10)));

      // AUTO-ADVANCE: completing service A's date+time must slide the PageView
      // onto service B with NO manual tap. Pump-until (not a fixed wait) —
      // service B's calendar only becomes on-screen once the 360 ms
      // auto-advance delay + the page animation have both elapsed. This also
      // drains service A's post-slot auto-advance timer. Settle afterwards so
      // the page-transition animation finishes before B's slide is tapped
      // (mid-flight, its cells are still clipped outside the viewport).
      await tester.pumpUntilFound(calendarDay('svc-b'));
      await tester.pumpAndSettle();

      // ── Slide B: pick today's date, then the NON-overlapping 14:00 window ─
      await tester.tap(calendarDay('svc-b'));
      await tester.pumpAndSettle();
      await tester.tap(slotChip('svc-b', at(14)));
      // Drain service B's own 360 ms post-slot auto-advance timer (a no-op here
      // — B is the last unscheduled service — but the Timer must fire before
      // teardown or flutter_test reports it as pending).
      // fixed-wait-ok: advancing past ServiceSchedulePage's known 360 ms auto-advance TTL so no Timer is left pending; there is no widget/state signal to pump-until here.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Every service scheduled → the CTA enables.
      expect(confirmCta(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('booking-time-confirm-cta')));
      await tester.pumpUntilFound(find.text('confirm-reached'));
      await tester.pumpAndSettle();

      // Landed on the confirm stub with a fully-resolved two-appointment
      // payload — never a booking-creation call from this screen.
      expect(captured, isNotNull);
      final BookingConfirmArgs args = captured!;
      expect(args.masterId, 'master-1');
      expect(
        args.appointments,
        hasLength(2),
        reason: 'one appointment per selected service (svc-a, svc-b)',
      );

      final BookingAppointment apptA = args.appointments[0];
      final BookingAppointment apptB = args.appointments[1];

      // Distinct serviceId, in slide order.
      expect(apptA.serviceId, 'svc-a');
      expect(apptB.serviceId, 'svc-b');

      // Distinct chosen starts — each service carries ITS OWN picked window.
      expect(apptA.startAt, at(10));
      expect(apptB.startAt, at(14));
      expect(apptA.startAt, isNot(apptB.startAt));

      // Distinct, non-empty stable idempotency keys (one minted per
      // appointment at confirm — never shared, never blank).
      expect(apptA.idempotencyKey, isNotEmpty);
      expect(apptB.idempotencyKey, isNotEmpty);
      expect(
        apptA.idempotencyKey,
        isNot(apptB.idempotencyKey),
        reason:
            'each appointment gets its OWN stable key so a retry of one never '
            'de-duplicates against the other',
      );
    },
  );

  testWidgets(
    'a sibling service scheduled on the same date pre-disables the overlapping '
    'slot chips so an overlap can never be selected through the UI',
    (tester) async {
      await _pumpTall(tester);
      // Both windows offered on every day: 10:00–11:00 and 14:00–15:00. Both
      // services are 60 min, so scheduling A at 10:00 must disable B's 10:00
      // chip (10:00–11:00 overlaps) while leaving B's 14:00 chip free.
      final fake = _FakeSlotRepository(<BookingSlot>[morning, afternoon]);
      BookingConfirmArgs? captured;
      await tester.pumpRoutedApp(
        _router(
          args: _args(),
          onReachedConfirm: (BookingConfirmArgs a) => captured = a,
        ),
        overrides: <Object>[slotRepositoryProvider.overrideWith((_) => fake)],
      );
      await tester.pumpAndSettle();

      // Slide A → 10:00 (window 10:00–11:00). Auto-advances to slide B.
      await tester.tap(calendarDay('svc-a'));
      await tester.pumpAndSettle();
      await tester.tap(slotChip('svc-a', at(10)));
      await tester.pumpUntilFound(calendarDay('svc-b'));
      await tester.pumpAndSettle();

      // Slide B, same date: the 10:00 chip is now pre-disabled (overlaps A's
      // 10:00–11:00), the non-overlapping 14:00 chip stays available.
      await tester.tap(calendarDay('svc-b'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SlotChip>(slotChip('svc-b', at(10))).available,
        isFalse,
        reason: "B's 10:00 window overlaps A's 10:00–11:00 → pre-disabled",
      );
      expect(
        tester.widget<SlotChip>(slotChip('svc-b', at(14))).available,
        isTrue,
        reason: "B's 14:00 window is clear of A → still selectable",
      );

      // Tapping the disabled chip does nothing: B stays unscheduled, so the CTA
      // stays disabled and the overlap can never be pushed to confirm.
      await tester.tap(slotChip('svc-b', at(10)));
      await tester.pumpAndSettle();
      expect(
        confirmCta(tester).onPressed,
        isNull,
        reason: 'the disabled overlapping chip must not schedule service B',
      );

      // Picking the clear 14:00 window schedules B and enables the CTA — the
      // pre-disable steers the client to a valid, non-overlapping selection.
      await tester.tap(slotChip('svc-b', at(14)));
      await tester.pumpAndSettle();
      expect(confirmCta(tester).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('booking-time-confirm-cta')));
      await tester.pumpUntilGone(find.byType(BookingTimeScreen));

      // No overlap → the flow navigates to confirm with two non-overlapping
      // appointments; the backstop snackbar never appears.
      expect(find.text('confirm-reached'), findsOneWidget);
      expect(captured, isNotNull);
      final l10n = AppLocalizations.of(
        tester.element(find.text('confirm-reached')),
      );
      expect(find.text(l10n.bookingServiceOverlapError), findsNothing);
    },
  );
}
