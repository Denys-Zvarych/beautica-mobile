// Phase 248 — the master «Мої записи» «+» add-booking entry point, end to
// end.
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 247 built the wizard (`MasterCreateBookingScreen`) and Phase 246 its
// data layer, but neither shipped an integration test — both were proven
// only at the widget tier, against hand-written mocktail fakes
// (`test/features/booking/presentation/master_create_booking_screen_test
// .dart`). Phase 248 wires the «+» button that was still a "coming soon"
// VelvetSnack to `context.push(RouteNames.masterBookingNew)`, which makes
// this the FIRST journey that proves:
//   • the button genuinely reaches the wizard through a REAL `context.push`
//     (never `router.go` — a pushed leaf collapses to its PARENT `fullPath`
//     in this repo's go_router setup, the locked trap every other push-nav
//     flow in this suite guards against);
//   • the wizard's OWN date/time picker resolves against the MASTER'S OWN
//     `masters/{masterId}/{working-days,slots}` — a route pair this fake
//     backend did not carry before this phase (see `fake_backend.dart`'s
//     Phase 248 section, mirroring the pre-existing `master-ccc`/`master-ddd`
//     salon-flow pair one level up: the master here books THEMSELVES, not a
//     roster colleague);
//   • `POST /api/v1/masters/{masterId}/bookings` round-trips through the REAL
//     `BookingRepository.createMasterBooking` → the follow-up
//     `GET /bookings/{id}` it makes before returning — a route this fake
//     backend also did not carry before this phase;
//   • the wizard's own Phase 246 success invalidation
//     (`ref.invalidate(bookingsDayProvider)`) actually refreshes the list —
//     THE PAUSED-CONSUMER RIVERPOD TRAP: the wizard is a fullscreen route
//     COVERING the list, so the list's `bookingsDayProvider` consumer is
//     PAUSED for the whole submit. Invalidating an autoDispose provider whose
//     only listener is paused DISPOSES it outright rather than refetching —
//     the refetch only fires once the consumer RESUMES on pop. This flow
//     therefore asserts the new card ONLY after the pop has fully settled,
//     never at the moment of invalidation/pop — see the inline comment at
//     that assertion for why asserting earlier would be a race, not a proof.
//
// For a STANDALONE local run (`flutter test
// integration_test/master_create_booking_test.dart -d flutter-tester`) this
// file is never batched with another integration_test file in the same
// invocation — this repo/toolchain kills the second file with a bogus "log
// reader failed" (see other flow files' headers for the same note). It IS
// still registered in `all_tests.dart` and `all_tests_part2.dart` (beside
// `master_bookings_flow`, whose login/router scaffolding it shares —
// `master_bookings_flow` itself is not in `all_tests_part1.dart` either, so
// this mirrors that split rather than deviating from it) — those aggregators
// run every flow's `main()` as its own `testWidgets` inside ONE
// `flutter test` process/isolate, which is the supported re-launch model
// those files document, not the one-file-per-process split this note is
// about.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_create_booking_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';
import 'support/fake_backend.dart';

/// Kyiv "today" **as the app under test computes it** — derived from the
/// harness's injected clock (`kFixedNow`), never the host device clock.
/// Mirrors `master_bookings_flow_test.dart`'s identically-derived
/// `_kyivToday` — see that file's doc for the full rationale.
final DateTime _kyivToday = kyivToday(() => kFixedNow);

/// Publishes a wide 09:00–21:00 Kyiv working window for [day].
///
/// Phase 244 gates the master timeline behind PUBLISHED working hours —
/// `FakeBackend`'s default is an empty `effective-schedule` (NO_SCHEDULE for
/// every day) — so the LANDING day this flow never navigates away from needs
/// one, or the screen renders the gray "no published hours" CTA state
/// instead of a timeline this test could ever find a card in. Mirrors
/// `master_bookings_flow_test.dart`'s `_seedWorkingHours` (private to that
/// file — Dart has no cross-file access to it, so this is a deliberate
/// re-declaration of the same two-line call, not a fork of any logic).
void _seedWorkingHours(FakeBackend fb, DateTime day) {
  fb.seedEffectiveSchedule(<Map<String, dynamic>>[
    FakeBackend.seedEffectiveScheduleDay(
      day,
      intervals: const <(String, String)>[('09:00:00', '21:00:00')],
    ),
  ]);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Phase 248: «+» → fill client → pick service → pick date/slot → confirm '
    '→ done → pop → the walk-in booking is visible in «Мої записи» — '
    'asserted AFTER the pop settles',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;

      // Switches `/bookings/me` onto the REAL (statuses, sort, page, day
      // window) slice over an in-memory table (`_slicedBookingsPageEnvelope`)
      // instead of the legacy single-seeded-`booking-1` fallback — see
      // `seedManyBookingsDataset`'s own doc. Starts EMPTY: the walk-in POST
      // below is the only row this flow needs, and an empty starting list
      // makes "the card appears" an unambiguous signal rather than "a count
      // went from 1 to 2".
      fb.seedManyBookingsDataset(const <Map<String, dynamic>>[]);
      // `_availableSlotsEnvelope` always dates its slots on
      // `kyivDayOf(serverNow)` — i.e. the SAME Kyiv day the timeline lands
      // on — so picking this slot needs no rail/day navigation before the
      // post-pop assertion.
      fb.availableSlotUtcStarts = const <(int, int)>[(7, 0)];

      final GoRouter router = await AppHarness.boot(tester, fb);

      // `_kyivToday` (module-level, lazily-initialised) is read for the
      // FIRST time here, AFTER `AppHarness.boot` — never before. `boot`'s
      // own `applyE2eBootPolicy` is what primes the timezone database
      // (`e2e_boot_policy.dart`'s own doc), and `_kyivToday` reads through
      // `kyivToday` → `toBeauticaTime` → `beauticaZone`, which THROWS
      // ("initBeauticaTimeZones() must be called... before beauticaZone is
      // read") if evaluated first. `master_bookings_flow_test.dart`'s own
      // identically-shaped `_kyivToday` gets away with a bare top-level read
      // because SOME earlier test in that large aggregated file has already
      // booted the harness (the tz-db init is a one-time, process-global side
      // effect); this file has exactly one test, so the ordering has to be
      // explicit rather than inherited.
      _seedWorkingHours(fb, _kyivToday);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      // ── «+» → the wizard ────────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('master-bookings-add')));
      await AppHarness.settle(tester);

      // `context.push`, not `router.go` — read through the SAME
      // `matches`-based nested-push resolver every other push-navigation
      // flow in this suite uses, because a pushed leaf collapses to its
      // PARENT `fullPath` under this repo's go_router setup.
      AppHarness.expectNestedPushLocation(router, RouteNames.masterBookingNew);
      expect(find.byType(MasterCreateBookingScreen), findsOneWidget);

      // ── Step 1 — client ─────────────────────────────────────────────────
      const String guestFirst = 'Ірина';
      const String guestLast = 'Шевченко';
      await tester.enterText(
        find.byKey(const Key('master-create-booking-first-name')),
        guestFirst,
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-last-name')),
        guestLast,
      );
      await tester.enterText(
        find.byKey(const Key('master-create-booking-phone')),
        '0501234567',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('master-create-booking-client-next')),
      );
      await AppHarness.settle(tester);

      // ── Step 2 — service (the FakeBackend's default fixture assignment) ──
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('mcb_service_card_assign-1')),
      );
      await tester.tap(find.byKey(const Key('mcb_service_card_assign-1')));
      await AppHarness.settle(tester);
      // SELECTION NEVER NAVIGATES (2026-08-20 UX fix) — the card tap only
      // marks the service chosen; the pinned «Далі» footer is what advances.
      // Same for the date and the slot below.
      await tester.tap(
        find.byKey(const Key('master-create-booking-service-next')),
      );
      await AppHarness.settle(tester);

      // ── Step 3 — date + slot, each committed by its own «Далі» ──────────
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(Key('booking-calendar-day-${_kyivToday.day}')),
      );
      await tester.tapCalendarDay(_kyivToday.day);
      await AppHarness.settle(tester);
      await tester.tap(
        find.byKey(const Key('master-create-booking-date-next')),
      );
      await AppHarness.settle(tester);

      final Finder availableChip = find
          .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
          .first;
      await tester.ensureVisible(availableChip);
      await AppHarness.settle(tester);
      await tester.tap(availableChip);
      await AppHarness.settle(tester);
      await tester.tap(
        find.byKey(const Key('master-create-booking-time-next')),
      );
      await AppHarness.settle(tester);

      // ── Step 4 — confirm → submit ─────────────────────────────────────
      expect(
        find.byKey(const Key('master-create-booking-confirm-card')),
        findsOneWidget,
        reason: 'the time step\'s «Далі» must land the wizard on `confirm`',
      );
      await tester.tap(
        find.byKey(const Key('master-create-booking-submit-cta')),
      );
      await AppHarness.settle(tester);

      expect(
        fb.createStaffBookingCalls,
        1,
        reason: 'the confirm CTA must submit exactly one walk-in booking',
      );
      expect(fb.lastStaffBookingRequestBody?['masterServiceId'], 'assign-1');
      final Map<String, dynamic>? guest =
          (fb.lastStaffBookingRequestBody?['guest'] as Map<String, dynamic>?);
      expect(
        guest,
        <String, dynamic>{
          'name': guestFirst,
          'surname': guestLast,
          'phone': '+380501234567',
        },
        reason:
            'the wire guest payload must carry exactly what was typed, '
            'normalised to E.164',
      );

      // ── Step 5 — done → «Готово» pops the wizard ──────────────────────
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-create-booking-done-card')),
      );
      // The done step re-shows WHO was booked (2026-08-20, mobile-security
      // F7's PII surface): the master's one chance to catch a mistyped client
      // before walking away. Asserted here rather than only at the widget tier
      // because the values come from the wizard's own controllers, and this is
      // the only tier that types them through the real keyboard path.
      expect(
        find.byKey(const Key('master-create-booking-done-guest-card')),
        findsOneWidget,
        reason: 'the done screen must name the guest just booked',
      );
      expect(
        find.text('$guestFirst $guestLast'),
        findsWidgets,
        reason:
            'and name the RIGHT one — the same guest the confirm step showed '
            'and the POST above carried',
      );
      await tester.tap(find.byKey(const Key('master-create-booking-done-cta')));
      await AppHarness.settle(tester);

      // ── The paused-consumer Riverpod trap — Phase 248's own point ──────
      //
      // `AppHarness.settle` above pumps every frame the pop itself produces,
      // which is what lets the covered list's `bookingsDayProvider` consumer
      // RESUME and the disposed-then-rebuilt provider actually refetch. Only
      // AFTER that settle has returned is the refreshed card guaranteed to
      // exist — asserting any earlier (e.g. right after the invalidation
      // that `MasterCreateBookingNotifier.submit` fires on success, before
      // the pop) would be racing the resume: it could false-pass on a slow
      // CI runner that happens to finish the refetch inside the same pump
      // burst, or false-fail on a fast one that genuinely hasn't resumed
      // yet. This is deliberately checked here, once, after the fact.
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(find.byType(MasterCreateBookingScreen), findsNothing);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-booking-card-$kWalkInBookingId')),
      );
      expect(
        find.text('$guestFirst $guestLast'),
        findsOneWidget,
        reason:
            'the refetched day list must name the guest the wizard just '
            'submitted — proving the card is the NEW booking, not a stale '
            'coincidence',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
