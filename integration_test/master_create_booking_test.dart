// Phase 248 (originally) — the master «Мої записи» «+» add-booking entry
// point, end to end.
//
// Phase 264 — REWRITTEN onto the ROUTED walk-in chain. The single-screen
// wizard was made unreachable (its route builder was swapped in Phase 264
// D4) and deleted outright in Phase 265; this file drives the same
// end-to-end journey through the chain that replaced it:
//
//   /master/bookings/new           → WalkInGuestStepScreen
//   /master/bookings/new/services  → WalkInServiceStepScreen
//   /booking/slots                 → SlotDateScreen   (CLIENT screen, reused)
//   /booking/slots/time            → SlotTimeScreen    (CLIENT screen, reused)
//   /booking/confirm               → BookingConfirmScreen (walk-in branch)
//   /booking/success               → BookingSuccessScreen (walk-in variant)
//
// WHY THIS FILE STILL EXISTS
// --------------------------
// It is the only tier that proves the WHOLE routed chain together, through
// REAL `context.push` hops (never `router.go` — a pushed leaf collapses to
// its PARENT `fullPath` under this repo's go_router setup, the locked trap
// every other push-nav flow in this suite guards against) and the REAL
// `BookingRepository`/`SlotRepository` wire path (never the widget tier's
// hand-written fakes):
//   • the «+» button reaches [WalkInGuestStepScreen] through a real push;
//   • the guest step's «Далі» reaches [WalkInServiceStepScreen] through a
//     SECOND real push, carrying the minted `WalkInGuest` as `extra`;
//   • the service step's «Далі» reaches the CLIENT's own `SlotDateScreen` /
//     `SlotTimeScreen`, with the master identity hidden throughout
//     (`hideMasterIdentity: true`) and the availability request carrying
//     ALL selected service ids (HARD CONSTRAINT 4) — never `services.first`;
//   • `SlotTimeScreen`'s CTA reaches `BookingConfirmScreen`, whose walk-in
//     branch (Phase 262 D2/D3) submits through the SAME
//     `masterCreateBookingProvider` the retired wizard used;
//   • `POST /api/v1/masters/{masterId}/bookings` round-trips through the
//     REAL `BookingRepository.createMasterBooking`;
//   • the success screen's walk-in variant (Phase 263) returns the master to
//     their own «Мої записи» calendar via `context.go`, which mounts a
//     FRESH `MasterBookingsScreen` — no paused-consumer Riverpod trap here
//     (unlike the retired wizard's `context.pop()`-based return): a
//     `context.go` off a flat top-level route tears down the whole pushed
//     stack and builds a brand-new list screen, whose `bookingsDayProvider`
//     fetches fresh rather than resuming a disposed-while-covered one.
//
// For a STANDALONE local run (`flutter test
// integration_test/master_create_booking_test.dart -d flutter-tester`) this
// file is never batched with another integration_test file in the same
// invocation — this repo/toolchain kills the second file with a bogus "log
// reader failed" (see other flow files' headers for the same note). It IS
// still registered in `all_tests.dart` (or its part-2 sibling) as its own
// `testWidgets` inside ONE `flutter test` process/isolate.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_confirm_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/slot_picker_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_guest_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/walk_in_service_step_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart'
    show formatSlotTimeRange;
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

// PHASE 256 — the three seeded `_services` fixture names (`fake_backend
// .dart`) the 3-service walk-in run below asserts render on `done`. Named
// constants, not inline literals in `find.text(...)` — a raw Cyrillic
// literal there trips `scripts/forbid_cyrillic_finder.sh`.
const String _kSvc1Name = 'Манікюр класичний'; // assign-1
const String _kSvc2Name = 'Брови корекція'; // assign-2
const String _kSvcTypedName = 'Класичний манікюр'; // assign-typed

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

/// Drives «+» → guest step → «Далі» — the shared first leg of every walk-in
/// run below. Asserts each of the two real `context.push` hops lands on the
/// right screen TYPE (never just a path string —
/// `project_gorouter_literal_before_dynamic_shadowing`).
Future<void> _openWizardAndFillGuest(
  WidgetTester tester,
  GoRouter router, {
  required String firstName,
  required String lastName,
}) async {
  await tester.tap(find.byKey(const Key('master-bookings-add')));
  await AppHarness.settle(tester);
  AppHarness.expectNestedPushLocation(router, RouteNames.masterBookingNew);
  expect(find.byType(WalkInGuestStepScreen), findsOneWidget);

  await tester.enterText(
    find.byKey(const Key('master-create-booking-first-name')),
    firstName,
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-last-name')),
    lastName,
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-phone')),
    '0501234567',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('master-create-booking-client-next')));
  await AppHarness.settle(tester);

  AppHarness.expectNestedPushLocation(
    router,
    RouteNames.masterBookingNewServices,
  );
  expect(find.byType(WalkInServiceStepScreen), findsOneWidget);
  expect(
    find.byType(WalkInGuestStepScreen),
    findsNothing,
    reason:
        'a real push mounts a NEW screen — the guest step is no longer '
        'the topmost route',
  );
}

/// Drives date → slot on the CLIENT's own `SlotDateScreen`/`SlotTimeScreen`
/// (reused unchanged by the walk-in chain), ending on `BookingConfirmScreen`.
/// Asserts the master identity is hidden on both intermediate screens
/// (test case 17 — `hideMasterIdentity`).
Future<void> _pickDateAndSlot(WidgetTester tester) async {
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(Key('booking-calendar-day-${_kyivToday.day}')),
  );
  expect(
    find.byType(MasterStrip),
    findsNothing,
    reason:
        'the walk-in date screen must hide the master identity card — '
        'the viewer IS the master',
  );
  await tester.tapCalendarDay(_kyivToday.day);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);

  expect(find.byType(SlotTimeScreen), findsOneWidget);
  expect(
    find.byType(MasterStrip),
    findsNothing,
    reason: 'the walk-in time screen must hide the master identity card too',
  );
  final Finder availableChip = find
      .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
      .first;
  await tester.ensureVisible(availableChip);
  await AppHarness.settle(tester);
  await tester.tap(availableChip);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);

  expect(find.byType(BookingConfirmScreen), findsOneWidget);
  expect(
    find.byType(MasterStrip),
    findsNothing,
    reason:
        'the walk-in confirm screen must hide the master identity card '
        'too (Phase 261)',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Phase 264: «+» → guest step → service step → date/slot (CLIENT screens) '
    '→ confirm → success → «Готово» → the walk-in booking is visible in '
    '«Мої записи»',
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
      // post-navigation assertion.
      fb.availableSlotUtcStarts = const <(int, int)>[(7, 0)];

      final GoRouter router = await AppHarness.boot(tester, fb);

      // `_kyivToday` (module-level, lazily-initialised) is read for the
      // FIRST time here, AFTER `AppHarness.boot` — never before. `boot`'s
      // own `applyE2eBootPolicy` is what primes the timezone database
      // (`e2e_boot_policy.dart`'s own doc), and `_kyivToday` reads through
      // `kyivToday` → `toBeauticaTime` → `beauticaZone`, which THROWS
      // ("initBeauticaTimeZones() must be called... before beauticaZone is
      // read") if evaluated first.
      _seedWorkingHours(fb, _kyivToday);

      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      // mobile-qa regression guard (this track) — `getMyBookingsCalls` is a
      // GLOBAL `/bookings/me` counter, but `BookingsDiscoveryView` holds
      // exactly ONE `bookingsDayProvider` `Consumer` in production
      // (`bookings_discovery_view.dart:876`) and this run never scrubs the
      // day rail, so every hit below is for the SAME single tracked day —
      // this counter is a clean proxy for
      // `invalidateBookingViewsAfterBookingCreated`'s eager-read gate.
      // Landing here is the ONE fetch that must have already happened.
      final int callsAtLanding = fb.getMyBookingsCalls;
      expect(
        callsAtLanding,
        1,
        reason: 'the initial day-list mount must have fetched exactly once',
      );

      // ── «+» → guest step → «Далі» → service step ────────────────────────
      const String guestFirst = 'Ірина';
      const String guestLast = 'Шевченко';
      await _openWizardAndFillGuest(
        tester,
        router,
        firstName: guestFirst,
        lastName: guestLast,
      );

      // ── service step — ONE fixture service, the FakeBackend's default ───
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('mcb_service_card_assign-1')),
      );
      await tester.tap(find.byKey(const Key('mcb_service_card_assign-1')));
      await AppHarness.settle(tester);
      // SELECTION NEVER NAVIGATES (2026-08-20 UX fix) — the card tap only
      // marks the service chosen; the pinned `BookingSummaryBar` footer
      // (`booking-summary-cta`) is what advances, exactly as it does one
      // step later on `SlotDateScreen`/`SlotTimeScreen` — the routed chain
      // now uses the SAME shared footer at every step.
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      // ── date + slot, on the CLIENT's own screens ────────────────────────
      await _pickDateAndSlot(tester);

      // ── confirm → submit ─────────────────────────────────────────────
      expect(
        find.byKey(const Key('booking-confirm-visit-card')),
        findsOneWidget,
        reason: "the time step's «Далі» must land on BookingConfirmScreen",
      );
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      expect(
        fb.createStaffBookingCalls,
        1,
        reason: 'the confirm CTA must submit exactly one walk-in booking',
      );
      expect(fb.lastStaffBookingRequestBody?['masterServiceIds'], <String>[
        'assign-1',
      ]);
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

      // THE FIX THIS RUN GUARDS — `invalidateBookingViewsAfterBookingCreated`
      // (`booking_calendar_invalidation.dart:405-430`). At this exact point
      // the day-list route is still COVERED by the whole pushed wizard
      // chain (guest → service → date → time → confirm, all still on the
      // stack) — Riverpod 3 PAUSES that Consumer's subscription rather than
      // dropping it, so its listener count stays > 0 and `isWatched` reads
      // `true`. The fix's gate (`!lru.isWatched(query)`) must therefore SKIP
      // the eager `ref.read` for this one day — the tautological pre-fix
      // `lru.contains(query)` check could never do that (every `liveQueries`
      // member is trivially `contains`-true), so it fired an extra
      // synchronous `/bookings/me` GET here, one call this assertion would
      // catch as `callsAtLanding + 1`.
      expect(
        fb.getMyBookingsCalls,
        callsAtLanding,
        reason:
            'submitting while the day list is COVERED (paused, not '
            'unwatched) must NOT eagerly refetch it — that day recovers on '
            'its own resume/remount, not here',
      );

      // ── success → «Готово» returns to «Мої записи» ─────────────────────
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('booking-success-visit-card')),
      );
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await AppHarness.settle(tester);

      // `context.go(RouteNames.masterBookings)` (Phase 263 D3) tears down
      // the whole pushed walk-in chain and mounts a FRESH
      // `MasterBookingsScreen` — no paused-consumer Riverpod trap here
      // (unlike the retired wizard's `context.pop()`-based return): a fresh
      // mount's `bookingsDayProvider` fetches on build, it is never
      // resuming a disposed-while-covered instance.
      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(find.byType(WalkInGuestStepScreen), findsNothing);
      expect(find.byType(WalkInServiceStepScreen), findsNothing);
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('master-booking-card-$kWalkInBookingId')),
      );
      expect(
        find.text('$guestFirst $guestLast'),
        findsOneWidget,
        reason:
            'the refetched day list must name the guest the routed chain '
            'just submitted — proving the card is the NEW booking, not a '
            'stale coincidence',
      );
      // Exactly ONE genuine refetch happened overall — the fresh
      // `MasterBookingsScreen` mount's own `ref.watch`, picking up the
      // `_mustRecomputeState` flag `ref.invalidate` left behind. NOT two:
      // that would mean the eager read the assertion above already proved
      // absent fired anyway and this is merely re-fetching a SECOND time on
      // top of it — a spurious-refetch regression the skeleton could show
      // as a flicker even if the final data ends up correct either way.
      expect(
        fb.getMyBookingsCalls,
        callsAtLanding + 1,
        reason:
            'the covered day must be refetched exactly ONCE — on the fresh '
            'post-`context.go` mount — never twice',
      );
      expect(tester.takeException(), isNull);
    },
  );

  // PHASE 256 (rewritten Phase 264 onto the routed chain) — a THREE-service
  // walk-in run, end to end through the REAL
  // `BookingRepository.createMasterBooking` → `AppointmentMapper.fromDto`
  // path (never the widget tier's hand-written fakes). Proves what the
  // widget-tier `should_renderServerVisitWindow_when
  // _multiServiceVisitCreated` test cannot on its own: that the ACTUAL wire
  // contract (`masterServiceIds`, a real `AppointmentDetailResponse` body)
  // round-trips correctly, not just a fake repository shaped to match it.
  //
  // HARD CONSTRAINT 4 — also proves the slot-AVAILABILITY request itself
  // carries all three ordered ids (`serviceId=` repeated N times), not just
  // the eventual POST: [FakeBackend.lastMasterOwnSlotsServiceIds].
  //
  // `FakeBackend`'s `/masters/{id}/bookings` handler (own doc, `fake_backend
  // .dart`) still chains the three requested items with a fixed 10-minute
  // buffer between them server-side (60 + 10 + 45 + 10 + 60 = 185 minutes
  // total, vs. the naive local sum of 165) — that server chaining is still
  // exercised and still the correct wire behaviour, but (Phase 264
  // deviation, see the assertion below) the routed chain's shared
  // `BookingSuccessScreen` no longer has the created `Appointment` in hand
  // to render it from, so this run asserts the ordering/id-fidelity
  // guarantees the wire round-trip proves, not a rendered server window.
  testWidgets(
    'Phase 256/264: a 3-service walk-in visit requests availability for ALL '
    'three services and submits all three ordered ids in ONE POST',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      fb.seedManyBookingsDataset(const <Map<String, dynamic>>[]);
      fb.availableSlotUtcStarts = const <(int, int)>[(7, 0)];

      final GoRouter router = await AppHarness.boot(tester, fb);
      _seedWorkingHours(fb, _kyivToday);
      await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

      await tester.tap(find.byKey(const Key('master-nav-tile-1')));
      await AppHarness.settle(tester);
      expect(find.byType(MasterBookingsScreen), findsOneWidget);

      const String guestFirst = 'Оксана';
      const String guestLast = 'Мельник';
      await _openWizardAndFillGuest(
        tester,
        router,
        firstName: guestFirst,
        lastName: guestLast,
      );

      // ── service step — THREE services, tapped in a fixed order ─────────
      // `assign-1` (Манікюр класичний, 60 min), `assign-2` (Брови корекція,
      // RANGE 200-350, 45 min), `assign-typed` (Класичний манікюр, 60 min) —
      // three DISTINCT seeded assignments (`fake_backend.dart`'s `_services`
      // fixture), tapped in this order so every downstream ordered
      // assertion (`lastMasterOwnSlotsServiceIds`, `masterServiceIds`) is
      // pinned, not incidental.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('mcb_service_card_assign-1')),
      );
      await tester.tap(find.byKey(const Key('mcb_service_card_assign-1')));
      await AppHarness.settle(tester);
      final Finder assign2Card = find.byKey(
        const Key('mcb_service_card_assign-2'),
      );
      await tester.ensureVisible(assign2Card);
      await AppHarness.settle(tester);
      await tester.tap(assign2Card);
      await AppHarness.settle(tester);
      final Finder assignTypedCard = find.byKey(
        const Key('mcb_service_card_assign-typed'),
      );
      await tester.ensureVisible(assignTypedCard);
      await AppHarness.settle(tester);
      await tester.tap(assignTypedCard);
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('booking-summary-cta')));
      await AppHarness.settle(tester);

      // ── date + slot ──────────────────────────────────────────────────
      await _pickDateAndSlot(tester);

      // HARD CONSTRAINT 4 — the availability request the date/time screens
      // fired against `SlotRepository.getMasterSlots` carried ALL three
      // ordered ids as repeated `serviceId=` params, never `services.first`
      // alone.
      expect(
        fb.lastMasterOwnSlotsServiceIds,
        <String>['assign-1', 'assign-2', 'assign-typed'],
        reason:
            'the slot-availability request must be computed against the '
            'WHOLE chained visit, not just the first tapped service',
      );

      // ── confirm → submit ─────────────────────────────────────────────
      expect(
        find.byKey(const Key('booking-confirm-visit-card')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('booking-confirm-submit-cta')));
      await AppHarness.settle(tester);

      expect(
        fb.createStaffBookingCalls,
        1,
        reason:
            'the confirm CTA must submit exactly ONE visit for all 3 '
            'services, never one call per service',
      );
      expect(
        fb.lastStaffBookingRequestBody?['masterServiceIds'],
        <String>['assign-1', 'assign-2', 'assign-typed'],
        reason:
            'the ORDERED list the master actually tapped, on the wire '
            'key `masterServiceIds`',
      );

      // ── success renders every service in the visit ──────────────────
      //
      // Phase 264 DEVIATION from the retired wizard's own `_DoneStep`: that
      // widget rendered the SERVER's created `Appointment.endAt` (a real
      // chained/buffered window), because it had the POST response in hand.
      // The routed chain's `BookingSuccessScreen` is the SAME CLIENT screen
      // the MO-3 client flow uses (`booking_success_screen.dart`'s
      // `_totalDurationMinutes` — a plain fold over `widget.args.services`,
      // `formatTimeRange(startAt, _totalDurationMinutes)`), and per HARD
      // CONSTRAINT 1 it must render byte-identically for the client, so it
      // is not special-cased for the walk-in path either. This is therefore
      // a NAIVE LOCAL SUM window (no backend inter-service buffer) on
      // purpose — the D3 "server window, not local sum" guarantee the
      // retired wizard's own test pinned no longer has a screen to hold it
      // on this path; see this file's own header and the phase-264/265
      // hand-off notes for the recorded deviation.
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('booking-success-visit-card')),
      );

      // `_kyivToday` at 07:00Z, the SAME slot start `_availableSlotsEnvelope`
      // emits for `availableSlotUtcStarts = [(7, 0)]` — see that fixture's
      // own doc.
      final DateTime slotStart = DateTime.utc(
        _kyivToday.year,
        _kyivToday.month,
        _kyivToday.day,
        7,
        0,
      );
      // The client-computed naive sum: 60 + 45 + 60 = 165 minutes, no
      // backend inter-service buffer — see the deviation note above.
      final DateTime naiveLocalSumEnd = slotStart.add(
        const Duration(minutes: 165),
      );

      expect(
        find.text(formatSlotTimeRange(slotStart, naiveLocalSumEnd)),
        findsOneWidget,
        reason:
            'BookingSuccessScreen renders startAt + Σ(local durations) — '
            'the same computation the CLIENT flow uses on this shared '
            'screen (HARD CONSTRAINT 1)',
      );

      // Every service in the visit, not just the first tap-ordered pick.
      // Named constants (mirrors `_kGuestFirstName`/`_kGuestLastName`'s own
      // pattern above) rather than inline literals — `find.text('<Cyrillic
      // literal>')` trips `scripts/forbid_cyrillic_finder.sh`.
      expect(find.text(_kSvc1Name), findsOneWidget);
      expect(find.text(_kSvc2Name), findsOneWidget);
      expect(find.text(_kSvcTypedName), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );
}
