// Phase 241 — E2E: «Записатись» rebooks a BEAUTY WISH LIST entry straight
// into the existing booking flow, pre-seeded and slot-scoped, and the
// stale-service 404 surfaces as a NORMAL booking-flow failure that also
// drops the dead entry from the wish list.
//
// WHY THIS FILE EXISTS
// ---------------------
// `wishlist_rebook_test.dart` (widget tier, per the phase doc) proves
// `WishlistRebookHost.rebook` calls `context.push` with both ids and that the
// compact card / full row share one handler — against a hand-rolled router
// with `ServiceSelectorSheet` and the booking screens STUBBED. It cannot prove
// the two contracts the phase doc calls out explicitly:
//   1. the REAL `ServiceSelectorSheet.autoAdvance` extension point actually
//      resolves `preselectedServiceId` against a REAL, freshly-fetched
//      catalogue and skips straight to the slot picker, which then threads
//      that EXACT `masterServiceId` into the REAL `GET .../working-days` +
//      `GET .../slots` calls;
//   2. the stale-service race: a create that 404s must surface in the
//      booking flow's OWN failure language (never a bespoke wish-list error),
//      and backing all the way out must leave the wish list WITHOUT the dead
//      entry — proving `rebook`'s "invalidate only after the push returns"
//      design actually fires once the whole pushed stack unwinds, not merely
//      once the confirm screen fails.
//
// THE REAL JOURNEY, THE REAL ROUTE
// ---------------------------------
// Login → BEAUTY PASSPORT tab → the wish-list compact card's «Записатись» →
// `WishlistRebookHost.rebook` → `ServiceSelectorSheet` (autoAdvance, no visible
// Step 1) → `SlotDateScreen` → `SlotTimeScreen` → `BookingConfirmScreen`.
//
// `appointmentRepositoryProvider` is overridden with a hand-written fake for
// the 404 variant — never a real `POST /appointments` route on `FakeBackend`'s
// `DioAdapter` — mirroring `independent_multi_service_booking_flow_test.dart`'s
// precedent (avoids the generated client's real-Dio timer leak while
// exercising the REAL `AppointmentSubmit` notifier + confirm screen +
// router end to end).
//
// NO PATROL FLOW NEEDED: no native interaction anywhere in this journey.
//
// KEY POLICY (per AppHarness): every tap is key-based. Raw Ukrainian text
// appears only in CONTENT assertions (fixture data, never app copy).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

// ---------------------------------------------------------------------------
// Fixture — one wish-list entry pointing at master-aaa's REAL, resolvable
// `pub-assign-1` service (the same fixture `service_favourite_flow_test.dart`
// favourites), so `ServiceSelectorSheet.autoAdvance` genuinely resolves it
// against a real `publicMasterProfileProvider(master-aaa)` fetch.
// ---------------------------------------------------------------------------

const String _masterId = 'master-aaa';
const String _serviceId = 'pub-assign-1';
// i18n-finder-ok: backend fixture data (service name), not app UI copy.
const String _serviceName = 'Манікюр з покриттям';

List<Map<String, dynamic>> _wishlistRows() => <Map<String, dynamic>>[
  <String, dynamic>{
    'masterServiceId': _serviceId,
    'masterId': _masterId,
    'serviceName': _serviceName,
    'masterFirstName': 'Софія',
    'masterLastName': 'Бондар',
    'durationMinutes': 90,
    'priceType': 'FIXED',
    'priceMin': 500,
    'priceDisplay': '500 ₴',
  },
];

/// Scrolls the passport page to the bottom so the wish-list block — below the
/// fold on the 800x600 flutter-tester surface — is laid out and tappable.
/// Mirrors `wishlist_flow_test.dart`'s helper of the same name.
Future<void> _scrollToWishList(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
  await tester.pumpAndSettle();
}

Future<void> _openPassportAndScrollToWishlist(
  WidgetTester tester,
  FakeBackend fb,
  GoRouter router,
) async {
  await AppHarness.loginAs(tester, fb, UserRole.client);
  // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
  await tester.pumpAndSettle(const Duration(seconds: 1));
  AppHarness.expectLocation(router, RouteNames.clientHome);

  await tester.tap(find.byKey(const Key('client-nav-tile-4')));
  await tester.pumpAndSettle();
  AppHarness.expectLocation(router, RouteNames.clientPassport);
  expect(find.byType(PassportScreen), findsOneWidget);

  await _scrollToWishList(tester);
  expect(find.byType(WishlistCompactCard), findsOneWidget);
}

/// Records every `createAppointment` call and, when [failOnceWith] is set,
/// throws it on the FIRST call (invoking [onFailed] first, synchronously, so a
/// flow can mutate `FakeBackend` state exactly as a real stale-service 404
/// would leave it — mirrors
/// `independent_multi_service_booking_flow_test.dart`'s `_FakeAppointmentRepository`).
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository({this.failOnceWith, this.onFailed});

  final Failure? failOnceWith;
  final void Function()? onFailed;

  final List<CreateAppointmentRequest> requests = <CreateAppointmentRequest>[];

  @override
  Future<Appointment> createAppointment(CreateAppointmentRequest req) async {
    requests.add(req);
    final Failure? typed = failOnceWith;
    if (typed != null) {
      onFailed?.call();
      throw typed;
    }
    final DateTime end = req.startAt.add(const Duration(minutes: 90));
    return Appointment(
      id: 'appt-rebook-1',
      status: BookingStatus.confirmed,
      masterId: req.masterId,
      masterFirstName: 'Софія',
      masterLastName: 'Бондар',
      masterType: 'INDEPENDENT_MASTER',
      startAt: req.startAt,
      endAt: end,
      totalDurationMinutes: 90,
      totalPrice: 500,
      items: <AppointmentItem>[
        for (final String id in req.masterServiceIds)
          AppointmentItem(
            bookingId: 'booking-$id',
            masterServiceId: id,
            serviceName: _serviceName,
            startAt: req.startAt,
            endAt: end,
            durationMinutes: 90,
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
    DateTime newStartAt,
  ) => throw UnimplementedError();

  @override
  Future<void> cancelAppointment(String id, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<void> completeAppointment(String id) => throw UnimplementedError();

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  // =========================================================================
  // Test 1 — ACCEPTANCE: «Записатись» pre-seeds the REAL booking flow and
  // slots are requested for the EXACT masterServiceId, all the way to the
  // time step.
  // =========================================================================
  testWidgets(
    'CLIENT taps «Записатись» on a wish-list compact card → the existing '
    'booking flow opens with the service already selected (no Step 1) and '
    'slots are requested for that exact masterServiceId',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..favoriteServiceRows = _wishlistRows();
      final GoRouter router = await AppHarness.boot(tester, fb);

      await _openPassportAndScrollToWishlist(tester, fb, router);

      expect(fb.getWorkingDaysCalls, 0);

      await tester.tap(find.byKey(const Key('wishlist_card_book_$_serviceId')));
      // autoAdvance resolves off a post-frame callback once the catalogue
      // fetch lands — settle generously rather than assume one frame.
      // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Landed DIRECTLY on the date step — Step 1 was never shown to the
      // client, exactly what pre-seeding + autoAdvance promise.
      AppHarness.expectLocation(router, RouteNames.bookingSlots);
      expect(find.byType(SlotDateScreen), findsOneWidget);

      expect(
        fb.getWorkingDaysCalls,
        greaterThanOrEqualTo(1),
        reason: 'the date step must fetch real working-days availability',
      );
      expect(
        fb.lastMasterAaaWorkingDaysServiceId,
        _serviceId,
        reason:
            'the pre-selected service must ride into GET .../working-days — '
            'a bare masterId with no service would fall back to '
            'schedule-shape availability instead of this exact service\'s',
      );

      // ── One step further: the TIME step also requests slots scoped to the
      // SAME masterServiceId — proving the pre-selection survives the whole
      // sub-flow, not just its first fetch. ─────────────────────────────────
      final DateTime today = kyivToday(() => kFixedNow);
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();

      AppHarness.expectLocation(router, RouteNames.bookingSlotsTime);
      expect(find.byType(SlotTimeScreen), findsOneWidget);
      expect(fb.getMasterSlotsCalls, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // =========================================================================
  // Test 2 — THE STALE-SERVICE RACE: the create 404s → a NORMAL booking-flow
  // failure (never a bespoke wish-list error) → backing all the way out
  // drops the dead entry from the wish list.
  // =========================================================================
  testWidgets(
    'CLIENT rebooks a wish-list entry whose service was deactivated in the '
    'meantime → the create 404s as an ORDINARY booking-flow failure → backing '
    'all the way out to the passport drops the dead entry from the wish list',
    (tester) async {
      final fb = FakeBackend()
        ..currentRole = UserRole.client
        ..favoriteServiceRows = _wishlistRows();
      final _FakeAppointmentRepository repo = _FakeAppointmentRepository(
        failOnceWith: const NotFoundFailure(),
        // The real backend's `is_active` filter (phase 247) is what actually
        // excludes a deactivated service from the NEXT `GET
        // /favorites/services` — simulated here by dropping the row the
        // instant the create discovers it is gone, exactly when a real 404
        // would have been raised.
        onFailed: () => fb.favoriteServiceRows = fb.favoriteServiceRows
            .where(
              (Map<String, dynamic> r) => r['masterServiceId'] != _serviceId,
            )
            .toList(),
      );
      final GoRouter router = await AppHarness.boot(
        tester,
        fb,
        extraOverrides: <Object>[
          appointmentRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await _openPassportAndScrollToWishlist(tester, fb, router);

      await tester.tap(find.byKey(const Key('wishlist_card_book_$_serviceId')));
      // fixed-wait-ok: settles a real async route-push + provider-load step; not a total-wait guess.
      await tester.pumpAndSettle(const Duration(seconds: 1));
      AppHarness.expectLocation(router, RouteNames.bookingSlots);

      final DateTime today = kyivToday(() => kFixedNow);
      await tester.tapCalendarDay(today.day);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();
      AppHarness.expectLocation(router, RouteNames.bookingSlotsTime);

      final Finder availableChip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      await tester.ensureVisible(availableChip);
      await tester.pumpAndSettle();
      await tester.tap(availableChip);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await tester.pumpAndSettle();
      AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);

      // ── Submit → 404 ──────────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await tester.pumpAndSettle();

      // The flow's OWN failure language — never a bespoke wish-list banner,
      // never a dialog, never a crash. Confirm screen STAYS.
      AppHarness.expectShellLocation(router, RouteNames.bookingConfirm);
      expect(find.byType(BookingConfirmScreen), findsOneWidget);
      expect(
        find.byKey(const Key('booking-confirm-submit-error')),
        findsOneWidget,
      );
      expect(repo.requests, hasLength(1));
      expect(tester.takeException(), isNull);

      // ── Back ALL the way out. autoAdvance pushed the slot picker ON TOP of
      // ServiceSelectorSheet rather than replacing it, so unwinding the whole
      // stack takes FOUR pops: confirm → time → date → Step 1 (the route
      // `rebook`'s own `context.push` is awaiting) → passport. Only the LAST
      // one resolves that await and fires the deferred `ref.invalidate`. ────
      await tester.tap(find.byKey(const Key('booking-confirm-back')));
      await tester.pumpAndSettle();
      expect(find.byType(SlotTimeScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('slot-picker-back')));
      await tester.pumpAndSettle();
      expect(find.byType(SlotDateScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('slot-picker-back')));
      await tester.pumpAndSettle();
      // Back at Step 1 — ServiceSelectorSheet itself, the route `rebook`'s
      // OWN `context.push` is still awaiting (autoAdvance only ever pushed
      // FORWARD past it, never replaced it).
      AppHarness.expectLocation(router, RouteNames.bookingNew);

      await tester.tap(find.byKey(const Key('service-selector-back')));
      await tester.pumpAndSettle();

      AppHarness.expectLocation(router, RouteNames.clientPassport);
      expect(find.byType(PassportScreen), findsOneWidget);

      // ── The dead entry is gone — a REAL refetch, not a client-side guess.
      await _scrollToWishList(tester);
      expect(
        find.byType(WishlistCompactCard),
        findsNothing,
        reason:
            'rebook() invalidates wishlistProvider only once the WHOLE '
            'pushed stack has unwound back to this surface — a real refetch '
            'against the fake backend\'s now-`is_active:false`-filtered list',
      );
      expect(
        fb.listServiceFavoritesCalls,
        greaterThanOrEqualTo(2),
        reason:
            'one fetch on the first passport visit, one more on the '
            'post-rebook refresh',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
