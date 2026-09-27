// Phase 350 — E2E: «Записатись знову» on a PAST booking opens booking Step 1
// (ServiceSelectorSheet) for the SAME master with that booking's service
// already CHECKED but still EDITABLE — the client can add more services, or
// uncheck it and pick another, before advancing.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `booking_detail_interactions_test.dart` / `service_selector_sheet_test.dart`
// prove the two halves of this in isolation, against a hand-rolled router /
// hand-picked overrides: the CTA pushes the right `BookingEntryArgs`, and the
// sheet itself pre-checks + never auto-advances when seeded that way. NEITHER
// proves the REAL journey wired together against a mutating FakeBackend:
//
//   1. «Мої записи» → «Минулі» → a COMPLETED booking's own detail actually
//      offers «Записатись знову» and pushes the REAL `RouteNames.bookingNew`
//      leaf, which resolves the REAL `publicMasterProfileProvider` fetch.
//   2. The catalogue that comes back is genuinely THIS master's, the
//      previous service resolves against it and lands pre-checked, and
//      adding a second service (or swapping the pre-check for a different
//      service) threads the EXACT resulting `masterServiceId` set into the
//      REAL `GET .../working-days` and `GET .../slots` calls, all the way
//      to the time step — not just into `BookingSlotPickerArgs` at Step 1.
//   3. A SALON-master past booking rebooks the SAME master directly (D4's
//      user-decided "allow direct rebook" — no detour through the salon
//      flow's own step 1/step 2).
//   4. A service deactivated since the booking was made fails to resolve —
//      Step 1 renders with nothing pre-checked, never an error, and picking
//      a different service still proceeds normally. (mobile-security
//      cycle-1 LOW / D6): the client IS told why via a warning VelvetSnack.
//
// THE REAL JOURNEY, THE REAL ROUTE
// ---------------------------------
// Login → Записи branch → Минулі → the seeded booking's card → «Деталі
// запису» → «Записатись знову» → `ServiceSelectorSheet` (booking Step 1,
// pushed OUTSIDE the client shell — see `client_reschedule_flow_test.dart`'s
// header for why `AppHarness.expectLocation` applies directly here rather
// than the nested-push variant) → `SlotDateScreen` → `SlotTimeScreen`.
//
// NO PATROL FLOW NEEDED: no native interaction anywhere in this journey.
//
// KEY POLICY (per AppHarness): every tap is key-based, except the rebook CTA
// itself and the tab switch, which (like `client_leave_review_flow_test.dart`
// and every other booking-detail E2E) are located via `l10n` text finders —
// `BookingDetailScreen`'s footer buttons carry no `Key` of their own yet.
// Raw Ukrainian text appears only in CONTENT assertions (fixture data, never
// app copy).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_tab_bar.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import '../test/helpers/velvet_snack_matchers.dart';
import 'support/app_harness.dart';

/// Tile key for master-aaa's public catalogue services — same convention
/// `service_selector_sheet.dart`'s `_bookingTileKeyForId` uses.
Finder _tile(String masterServiceId) =>
    find.byKey(Key('booking_service_tile_$masterServiceId'));

/// Presence of the accordion's selected check-control face under [tile] —
/// mirrors `booking_preselection_seed_test.dart`'s `_checkedFace` helper.
Finder _checkedFace(Finder tile) =>
    find.descendant(of: tile, matching: find.byKey(const ValueKey<bool>(true)));

/// Both `master-aaa` public services (`_publicMasterServices` in
/// `fake_backend.dart`) share the SAME `NAILS` category, so this is the one
/// category key either scenario ever needs to expand.
const Key _kNailsCategory = Key('booking_category_NAILS');

/// Records every `createAppointment` call — mirrors
/// `independent_multi_service_booking_flow_test.dart`'s
/// `_FakeAppointmentRepository` (same precedent: a hand-written fake over
/// `appointmentRepositoryProvider`, never a real `POST /appointments` route
/// on `FakeBackend`'s `DioAdapter`). [onCreated] fires synchronously BEFORE
/// the request resolves, so a test can seed `FakeBackend`'s
/// `/bookings/me` dataset with the newly-created row before the confirm
/// screen's post-create `ref.invalidate` re-fetches it.
class _FakeRebookAppointmentRepository implements AppointmentRepository {
  _FakeRebookAppointmentRepository({this.onCreated});

  final void Function(CreateAppointmentRequest req)? onCreated;
  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    onCreated?.call(req);
    const Duration duration = Duration(minutes: 60);
    final DateTime end = req.startAt.add(duration);
    return Appointment(
      id: 'appt-rebook-1',
      status: BookingStatus.confirmed,
      masterId: req.masterId,
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterType: 'INDEPENDENT_MASTER',
      startAt: req.startAt,
      endAt: end,
      totalDurationMinutes: duration.inMinutes,
      totalPrice: 500,
      items: <AppointmentItem>[
        for (final String id in req.masterServiceIds)
          AppointmentItem(
            bookingId: 'booking-created-rebook-1',
            masterServiceId: id,
            serviceName: 'Манікюр з покриттям',
            startAt: req.startAt,
            endAt: end,
            durationMinutes: duration.inMinutes,
            price: 500,
          ),
      ],
    );
  }

  @override
  Future<Appointment> getAppointment(String id) => throw UnimplementedError();

  @override
  Future<Appointment> rescheduleAppointmentItem(
    String appointmentId,
    String bookingId,
    DateTime newStartAt, {
    bool allowClientOverlap = false,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<void> completeAppointment(String id) => throw UnimplementedError();

  @override
  Future<void> completeAppointmentService(
    String appointmentId,
    String bookingId,
  ) => throw UnimplementedError();

  @override
  Future<void> declineAppointment(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) => throw UnimplementedError();
}

/// Logs in as CLIENT, opens «Мої записи» → the tab [tabLabel] selects
/// («Минулі» — COMPLETED/NOT_COMPLETED — by default; a CANCELLED/DECLINED
/// booking lives under «Скасовані» instead, see `booking_tab.dart`'s
/// `BookingTabX.statuses`), opens the seeded booking's own detail, and taps
/// «Записатись знову» — landing on the REAL `ServiceSelectorSheet` pushed by
/// the REAL `RouteNames.bookingNew` route. Every test below starts from this
/// exact point.
Future<GoRouter> _openPastBookingAndRebook(
  WidgetTester tester,
  FakeBackend fb, {
  List<Object> extraOverrides = const <Object>[],
  String Function(AppLocalizations)? tabLabel,
}) async {
  final GoRouter router = await AppHarness.boot(
    tester,
    fb,
    extraOverrides: extraOverrides,
  );

  await AppHarness.loginAs(tester, fb, UserRole.client);
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.clientHome);

  await tester.tap(find.byKey(const Key('client-nav-tile-3')));
  await AppHarness.settle(tester);
  AppHarness.expectLocation(router, RouteNames.clientBookings);
  expect(find.byType(MyBookingsScreen), findsOneWidget);

  final AppLocalizations tabsL10n = AppLocalizations.of(
    tester.element(find.byType(MyBookingsScreen)),
  );
  final String Function(AppLocalizations) resolveLabel =
      tabLabel ?? (AppLocalizations l) => l.myBookingsTabPast;
  await tester.tap(
    find.descendant(
      of: find.byType(MyBookingsTabBar),
      matching: find.text(resolveLabel(tabsL10n)),
    ),
  );
  await AppHarness.settle(tester);

  expect(
    find.byKey(const ValueKey<String>('service-booking-1')),
    findsOneWidget,
    reason: 'the seeded booking must appear under the selected tab',
  );

  await tester.tap(find.byType(BookingCard));
  await AppHarness.settle(tester);
  // `/bookings/:bookingId` is a child GoRoute INSIDE the client shell's
  // bookings branch — same nested-push caveat `client_leave_review_flow_
  // test.dart`'s header documents.
  AppHarness.expectNestedPushLocation(
    router,
    RouteNames.bookingDetail('booking-1'),
  );
  expect(find.byType(BookingDetailScreen), findsOneWidget);

  final AppLocalizations detailL10n = AppLocalizations.of(
    tester.element(find.byType(BookingDetailScreen)),
  );
  final Finder rebook = find.text(detailL10n.bookingDetailRebookCta);
  await tester.ensureVisible(rebook);
  await AppHarness.settle(tester);
  await tester.tap(rebook);
  await AppHarness.settle(tester);

  // Pushed OUTSIDE the client shell — plain `expectLocation` applies
  // directly (see this file's header).
  AppHarness.expectLocation(router, RouteNames.bookingNew);
  expect(find.byType(ServiceSelectorSheet), findsOneWidget);
  expect(find.byType(BookingDetailScreen), findsNothing);

  return router;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // =========================================================================
  // Test 1 — ACCEPTANCE: the previous service lands pre-checked; adding a
  // second service requests availability for BOTH masterServiceIds all the
  // way to the time step.
  // =========================================================================
  testWidgets(
    'CLIENT rebooks a COMPLETED independent-master booking: the previous '
    'service is pre-checked, and adding a second service requests '
    'availability for BOTH masterServiceIds through the date AND time steps',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED';

      final GoRouter router = await _openPastBookingAndRebook(tester, fb);

      // Pre-checked: the booking's own service, editable (not locked).
      expect(
        _checkedFace(_tile('pub-assign-1')),
        findsOneWidget,
        reason: 'Step 1 must land with the booked service already checked',
      );

      expect(fb.getWorkingDaysCalls, 0);

      // Add a second service — same NAILS category, already auto-expanded
      // by the seed, so no header tap is needed.
      await tester.tap(_tile('pub-assign-2'));
      await AppHarness.settle(tester);
      expect(_checkedFace(_tile('pub-assign-1')), findsOneWidget);
      expect(_checkedFace(_tile('pub-assign-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.bookingSlots);
      expect(find.byType(SlotDateScreen), findsOneWidget);
      expect(
        fb.lastMasterAaaWorkingDaysServiceIds,
        <String>['pub-assign-1', 'pub-assign-2'],
        reason:
            'BOTH ids must ride into the working-days availability query, '
            'in catalogue order',
      );

      // One step further: the TIME step also requests slots scoped to the
      // SAME two ids.
      final DateTime today = kyivToday(() => kFixedNow);
      await tester.tapCalendarDay(today.day);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.bookingSlotsTime);
      expect(find.byType(SlotTimeScreen), findsOneWidget);
      expect(
        fb.lastMasterAaaSlotsServiceIds,
        <String>['pub-assign-1', 'pub-assign-2'],
        reason: 'BOTH ids must ride into the slots availability query too',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // =========================================================================
  // Test 2 — the client UNCHECKS the pre-checked service and picks a
  // different one instead — availability is requested for the NEW id only.
  // =========================================================================
  testWidgets(
    'CLIENT rebooks the same booking but unchecks the pre-checked service '
    'and picks another instead — availability is requested for the NEW id '
    'only',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED';

      final GoRouter router = await _openPastBookingAndRebook(tester, fb);

      expect(_checkedFace(_tile('pub-assign-1')), findsOneWidget);

      await tester.tap(_tile('pub-assign-1'));
      await AppHarness.settle(tester);
      expect(_checkedFace(_tile('pub-assign-1')), findsNothing);

      await tester.tap(_tile('pub-assign-2'));
      await AppHarness.settle(tester);
      expect(_checkedFace(_tile('pub-assign-1')), findsNothing);
      expect(_checkedFace(_tile('pub-assign-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.bookingSlots);
      expect(
        fb.lastMasterAaaWorkingDaysServiceIds,
        <String>['pub-assign-2'],
        reason: 'the unchecked seeded service must NOT ride into the query',
      );

      final DateTime today = kyivToday(() => kFixedNow);
      await tester.tapCalendarDay(today.day);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.bookingSlotsTime);
      expect(fb.lastMasterAaaSlotsServiceIds, <String>['pub-assign-2']);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // =========================================================================
  // Test 3 — D4 PROOF: a SALON-master past booking rebooks the SAME master
  // directly, never detouring through the salon booking flow.
  // =========================================================================
  testWidgets(
    'CLIENT rebooks a COMPLETED SALON-master booking: Step 1 opens for the '
    'SAME master with the service pre-checked — never the salon flow (D4)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..bookingMasterType = 'SALON_MASTER'
        ..bookingSalonId = 'salon-xyz'
        ..bookingSalonName = 'Студія Краси «Камелія»';

      await _openPastBookingAndRebook(tester, fb);

      // The catalogue that resolved is genuinely THIS master's — a real
      // `GET /masters/master-aaa/services` round trip, not a stub.
      expect(fb.lastGetPublicMasterServicesId, 'master-aaa');
      expect(_checkedFace(_tile('pub-assign-1')), findsOneWidget);

      // D4 — never the salon flow's own step 1.
      expect(find.byType(SalonServiceSelectionScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // =========================================================================
  // Test 4 — D6: the booked service was deactivated since — Step 1 renders
  // with NOTHING pre-checked (no error), and picking another proceeds.
  // =========================================================================
  testWidgets(
    'CLIENT rebooks a booking whose service was deactivated since: Step 1 '
    'renders with nothing checked, and picking another proceeds normally',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        ..publicMasterServiceRemoved = true;

      final GoRouter router = await _openPastBookingAndRebook(tester, fb);

      expect(
        find.byKey(const ValueKey<bool>(true)),
        findsNothing,
        reason:
            'the stale (deactivated) service must fail to match — nothing '
            'pre-checked, and no error is thrown',
      );
      expect(tester.takeException(), isNull);

      // mobile-security cycle-1 LOW / Phase 350 D6 — the client is told WHY
      // nothing is pre-checked, via the same warning snack the D7
      // (empty-serviceId) fallback in `booking_detail_screen.dart` shows.
      final AppLocalizations sheetL10n = AppLocalizations.of(
        tester.element(find.byType(ServiceSelectorSheet)),
      );
      expectVelvetSnack(
        sheetL10n.bookingRebookServiceUnavailable,
        variant: VelvetSnackVariant.warning,
      );
      // Drain the dwell Timer BEFORE interacting further — a still-showing
      // snack is bottom-anchored and would otherwise sit over the pinned
      // «Далі» summary bar this test taps below (velvet_snack_matchers.dart's
      // header explains the hit-test hazard).
      await pumpPastVelvetSnack(tester);

      // Not auto-expanded (nothing matched) — expand the category, then pick
      // the one remaining service.
      await tester.tap(find.byKey(_kNailsCategory));
      await AppHarness.settle(tester);
      await tester.tap(_tile('pub-assign-2'));
      await AppHarness.settle(tester);
      expect(_checkedFace(_tile('pub-assign-2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.bookingSlots);
      expect(find.byType(SlotDateScreen), findsOneWidget);
      expect(fb.lastMasterAaaWorkingDaysServiceIds, <String>['pub-assign-2']);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // =========================================================================
  // Test 5 — QASE CASE #24 STEP 3, END TO END: the client rides the rebook
  // ALL THE WAY through date → time → confirm → submit, and the created
  // booking carries the pre-checked service. The OLD booking stays visible
  // (COMPLETED) in Минулі while the NEW one shows «Підтверджено» in Майбутні.
  //
  // Tests 1-4 above prove the CTA pushes the right args and the sheet seeds
  // correctly; NONE of them reach an actual `POST /appointments` or check
  // what `GET /bookings/me` reports afterwards — which is exactly what the
  // Qase case's own step 3 asserts. `appointmentRepositoryProvider` is
  // overridden with a hand-written fake (mirrors `independent_multi_service_
  // booking_flow_test.dart`'s precedent), never a real `POST /appointments`
  // route on `FakeBackend`'s `DioAdapter`.
  // =========================================================================
  testWidgets(
    'CLIENT rebooks a COMPLETED booking end to end: the submitted request '
    'carries the pre-checked masterServiceId, and afterwards the OLD booking '
    'stays COMPLETED in Минулі while the NEW one is «Підтверджено» in '
    'Майбутні (Qase case #24 step 3)',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'COMPLETED'
        // A slot AFTER `kFixedNow` (12:00 UTC) — the default fixture window
        // ((7,0),(11,0)) sits BEFORE noon, so a booking created against it
        // would classify as PAST by `_partitionOf`'s `endsAt < now` rule
        // (mirrors the backend), never showing on Майбутні. 13:00 UTC is
        // safely after `kFixedNow` on the SAME `kyivToday` calendar day.
        ..availableSlotUtcStarts = const <(int, int)>[(13, 0)];
      final DateTime pastStart = kyivToday(
        () => kFixedNow,
      ).subtract(const Duration(days: 10));
      // Dataset mode (not the single-row `bookingStatus` envelope) so the OLD
      // COMPLETED row and the NEW CONFIRMED row can coexist on `GET
      // /bookings/me` — `_openPastBookingAndRebook`'s own detail fetch (`GET
      // /bookings/booking-1`) is unaffected: it is driven by `bookingStatus`
      // independently of this dataset.
      fb.seedManyBookingsDataset(<Map<String, dynamic>>[
        fb.datasetBookingRow(
          id: 'booking-1',
          status: 'COMPLETED',
          startsAt: pastStart,
        ),
      ]);

      const String newBookingId = 'booking-created-rebook-1';
      final repo = _FakeRebookAppointmentRepository(
        onCreated: (CreateAppointmentRequest req) {
          fb.seedManyBookingsDataset(<Map<String, dynamic>>[
            fb.datasetBookingRow(
              id: 'booking-1',
              status: 'COMPLETED',
              startsAt: pastStart,
            ),
            fb.datasetBookingRow(
              id: newBookingId,
              status: 'CONFIRMED',
              startsAt: req.startAt,
            ),
          ]);
        },
      );

      final GoRouter router = await _openPastBookingAndRebook(
        tester,
        fb,
        extraOverrides: <Object>[
          appointmentRepositoryProvider.overrideWithValue(repo),
        ],
      );

      // Step 1 lands pre-checked — the only service on this booking.
      expect(_checkedFace(_tile('pub-assign-1')), findsOneWidget);

      // Далі → date → Далі → time → pick a slot → Підтвердити (bookingConfirm).
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.bookingSlots);

      final DateTime today = kyivToday(() => kFixedNow);
      await tester.tapCalendarDay(today.day);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.bookingSlotsTime);
      expect(find.byType(SlotTimeScreen), findsOneWidget);

      final Finder availableChip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      await tester.ensureVisible(availableChip);
      await AppHarness.settle(tester);
      await tester.tap(availableChip);
      await AppHarness.settle(tester);

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);

      // Submit → ONE createAppointment, carrying THIS booking's service only.
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      AppHarness.expectLocation(router, RouteNames.bookingSuccess);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(repo.requests, hasLength(1));
      expect(
        repo.requests.single.masterServiceIds,
        <String>['pub-assign-1'],
        reason:
            'the created booking must carry the rebook CTA\'s pre-checked '
            'service — the exact link Qase case #24 step 3 is pinning',
      );
      expect(tester.takeException(), isNull);

      // Back to «Мої записи» — the OLD booking stays in Минулі (COMPLETED);
      // the NEW one shows «Підтверджено» in the default Майбутні tab.
      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientHome);

      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      // The bookings BRANCH's own nested Navigator never popped
      // `BookingDetailScreen` (`_openPastBookingAndRebook` pushed it, then
      // rebook pushed OUTSIDE the shell on top of everything — real user
      // behaviour: coming back to this tab lands wherever it was left, same
      // as it would for a real user). Pop it to reach the list.
      expect(find.byType(BookingDetailScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      final AppLocalizations listL10n = AppLocalizations.of(
        tester.element(find.byType(MyBookingsScreen)),
      );
      // The Мої записи branch stayed mounted underneath the whole rebook push
      // chain (IndexedStack), and `_openPastBookingAndRebook` above left it on
      // Минулі — so the tab selection does NOT reset on return. Select
      // Майбутні explicitly rather than assume it is the default here.
      await tester.tap(
        find.descendant(
          of: find.byType(MyBookingsTabBar),
          matching: find.text(listL10n.myBookingsTabUpcoming),
        ),
      );
      await AppHarness.settle(tester);
      expect(
        find.byKey(const ValueKey<String>('service-$newBookingId')),
        findsOneWidget,
        reason: 'the freshly-created visit must appear on the Майбутні tab',
      );
      expect(find.text(listL10n.bookingStatusConfirmed), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(MyBookingsTabBar),
          matching: find.text(listL10n.myBookingsTabPast),
        ),
      );
      await AppHarness.settle(tester);
      expect(
        find.byKey(const ValueKey<String>('service-booking-1')),
        findsOneWidget,
        reason: 'the OLD booking must still be visible, unaffected, in Минулі',
      );
      expect(find.text(listL10n.bookingStatusCompleted), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // =========================================================================
  // Test 6 — CTA STATUS MATRIX, IN AN E2E: Tests 1-5 above all seed a
  // COMPLETED booking (the «Минулі» tab — `BookingTab.past`, statuses
  // {COMPLETED, NOT_COMPLETED}). `booking_detail_interactions_test.dart`
  // proves EVERY rebook-eligible status (COMPLETED/CANCELLED/DECLINED/
  // unknown) pushes the right args at the widget tier, but that is a
  // hand-rolled router — this pins that a genuinely CANCELLED booking
  // (`BookingTab.cancelled`'s «Скасовані» tab — statuses {CANCELLED,
  // DECLINED}; confirmed via `booking_tab.dart`'s `BookingTabX.statuses` —
  // CANCELLED/DECLINED do NOT live under «Минулі») ALSO reaches the REAL
  // Step 1 pre-checked through the full app + FakeBackend wiring, not just
  // COMPLETED.
  // =========================================================================
  testWidgets(
    'CLIENT rebooks a CANCELLED booking from «Скасовані»: Step 1 still lands '
    'with the service pre-checked — the rebook path is not COMPLETED-only',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..bookingStatus = 'CANCELLED';

      await _openPastBookingAndRebook(
        tester,
        fb,
        tabLabel: (AppLocalizations l) => l.myBookingsTabCancelled,
      );

      expect(
        _checkedFace(_tile('pub-assign-1')),
        findsOneWidget,
        reason:
            'CANCELLED is one of the three rebook-eligible statuses '
            '(COMPLETED/CANCELLED/DECLINED) — preselection must not be '
            'COMPLETED-only',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
