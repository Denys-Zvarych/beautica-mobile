// 2026-08-17 CRITICAL regression — E2E: closing ONE service from the master
// «Архів» must not complete its siblings, and must never complete a service
// whose own start time has not arrived.
//
// THE BUG THIS FILE PINS
// ----------------------
// On an INDEPENDENT_MASTER account the archive showed ONE elapsed service for
// today. Tapping its «Виконано» made EVERY service of that day's visit appear
// in the archive, all marked COMPLETED — including services whose start time
// had not arrived yet.
//
// Root cause: `master_archive_screen.dart`'s `_confirmComplete` routed an
// appointment child to the WHOLE-VISIT `PATCH /appointments/{id}/complete`.
// The backend transitions every child of the visit in lockstep, and evaluates
// `BookingTemporalGuard.assertElapsedForComplete` against the VISIT's
// `startsAt` (the FIRST service) — so a sibling starting hours later was
// closed with no temporal guard of its own. Those siblings then LEGITIMATELY
// entered the `HISTORY` partition the archive refetches, which is why the
// symptom read as "all of today's bookings suddenly appeared, all COMPLETED".
//
// The fix routes to the PER-SERVICE
// `PATCH /appointments/{appointmentId}/services/{bookingId}/complete`
// (`AppointmentRepository.completeAppointmentService`) — "siblings stay
// CONFIRMED" — and gates the button itself on
// `Booking.hasStartedAt(ref.watch(clockProvider)())`.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// `booking_detail_appointment_child_footer_test.dart` proves the DETAIL
// screen's call site against a mocked repository, and
// `master_appointment_child_booking_actions_flow_test.dart` proves the DETAIL
// screen end-to-end. NEITHER touches the ARCHIVE — and the archive is where
// the bug was reported, because it is the only surface that renders one row
// PER SERVICE of a visit and then REFETCHES the whole `HISTORY` partition
// after the write. The reported symptom (siblings materialising as new
// COMPLETED rows) is only observable on a surface that re-reads the list; a
// detail screen re-reads exactly one booking and can never show it.
//
// WHAT MAKES THIS A GENUINE GUARD RATHER THAN A SELF-REFERENTIAL PASS
// ------------------------------------------------------------------
// The hand-faked `AppointmentRepository` below models BOTH endpoints against
// the SAME seeded dataset the fake backend serves `/bookings/me` from:
//   • `completeAppointmentService` (the fix) flips ONLY the named child.
//   • `completeAppointment` (the bug) flips EVERY child of the visit — the
//     real backend's lockstep semantics, faithfully reproduced.
// So pointing `master_archive_screen.dart` back at `completeAppointment`
// genuinely makes `svc-b` materialise in the refetched list and turns the
// sibling assertion RED. If the whole-visit arm were a no-op recorder, this
// test would pass with the bug reinstated and would be worthless.
//
// `AppointmentRepository` stays hand-faked (no real `/appointments` adapter
// route on `FakeBackend`) — the established precedent in
// `master_appointment_child_booking_actions_flow_test.dart` and
// `client_visit_render_flow_test.dart`, which avoids the generated
// `AppointmentControllerApi`'s real-Dio timer leak against the fake adapter.
// The routing proof rests on three independent counters: the per-service
// counter climbing, the whole-visit counter staying 0, and
// `FakeBackend.completeBookingCalls` staying 0.
//
// CLOCK COHERENCE. Every fixture instant here is anchored to [kFixedNow] — the
// SAME instant `AppHarness` overrides `clockProvider` to, and the same instant
// `FakeBackend.serverNow` classifies partitions against. Both-pinned is the
// only coherent form now that the «Виконано» gate reads the injected clock:
// a `DateTime.now()`-anchored window would sit far after `kFixedNow` and read
// as not-yet-started, hiding the button and vacuously "passing".
//
// SCENARIO 2 IS NOT AN EXCEPTION TO THAT. It moves the APP's clock via
// `AppHarness.boot(clock:)` while leaving `FakeBackend.serverNow` at
// `kFixedNow`, so the two disagree — but BOTH remain explicitly pinned, and
// neither is a host-clock read. The forbidden shape is mixing a pin with a
// live `DateTime.now()`; two pins that disagree BY CONSTRUCTION are the only
// configuration that can observe WHICH clock the widget consulted, which is
// exactly what that scenario exists to prove. Scenario 1's fixture is in the
// past for the device clock too, so on its own it cannot tell an injected-clock
// read from a device-clock one.
//
// KEY POLICY (AppHarness): all TAPS are key-based; no raw Ukrainian literal
// appears in any finder.
//
// Run ALONE — batching two integration files in one `flutter test` invocation
// kills the second with a bogus "log reader failed":
//   TZ=UTC flutter test integration_test/master_archive_per_service_complete_flow_test.dart -d flutter-tester

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/create_appointment_request.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

/// The visit both seeded services belong to.
const String kVisitId = 'appt-1';

/// The ELAPSED service of the visit — 10:00–10:30 against a 12:00 [kFixedNow].
/// `CONFIRMED` + `awaitingClosure: true`, so the archive offers «Виконано».
const String kElapsedServiceId = 'svc-a';

/// The NOT-YET-STARTED sibling — 16:00–17:00 against the same 12:00
/// [kFixedNow]. `CONFIRMED`, `awaitingClosure: false`. It classifies as
/// `UPCOMING`, so it must never appear in the archive's fixed `HISTORY` scope
/// — unless something wrongly completes it, which is precisely the bug.
const String kNotStartedServiceId = 'svc-b';

/// A hand-faked [AppointmentRepository] that mutates the SAME dataset row maps
/// `FakeBackend` serves `GET /bookings/me` from, so a write here is genuinely
/// visible to the archive's post-write refetch over the real HTTP boundary.
///
/// [seedManyBookingsDataset] copies the LIST but not the row maps, so holding
/// references to the maps and mutating them in place is what makes the refetch
/// observe the write.
class _FakeAppointmentRepository implements AppointmentRepository {
  _FakeAppointmentRepository(this._rows);

  /// Every seeded dataset row, by booking id — the same map instances the fake
  /// backend serves.
  final Map<String, Map<String, dynamic>> _rows;

  // ── PER-SERVICE complete (the FIX) ────────────────────────────────────────
  int completeServiceCalls = 0;
  String? lastCompleteServiceAppointmentId;
  String? lastCompleteServiceBookingId;

  // ── WHOLE-VISIT complete (the BUG) ────────────────────────────────────────
  int completeCalls = 0;
  String? lastCompleteId;

  void _close(Map<String, dynamic> row) {
    row['status'] = 'COMPLETED';
    // A COMPLETED booking is no longer awaiting closure — the real backend's
    // own derivation (`awaitingClosure` requires `status == CONFIRMED`). This
    // is what makes «Виконано» disappear from the row on the refetch, and is
    // therefore the signal `pumpUntilGone` waits on.
    row['awaitingClosure'] = false;
  }

  @override
  Future<void> completeAppointmentService(
    String appointmentId,
    String bookingId,
  ) async {
    completeServiceCalls++;
    lastCompleteServiceAppointmentId = appointmentId;
    lastCompleteServiceBookingId = bookingId;
    // "Siblings stay CONFIRMED" — exactly ONE row moves.
    final Map<String, dynamic>? row = _rows[bookingId];
    if (row != null) _close(row);
  }

  @override
  Future<void> completeAppointment(String id) async {
    completeCalls++;
    lastCompleteId = id;
    // THE BUG, FAITHFULLY MODELLED — the backend transitions EVERY child of
    // the visit in lockstep, with the temporal guard evaluated only against
    // the VISIT's `startsAt`. Reinstating the old call site in
    // `master_archive_screen.dart` must therefore genuinely flip `svc-b` and
    // turn this file's sibling assertions RED. Do NOT weaken this to a bare
    // counter: a no-op here would make the mutation check pass and the whole
    // suite worthless.
    for (final Map<String, dynamic> row in _rows.values) {
      if (row['appointmentId'] == id) _close(row);
    }
  }

  @override
  Future<void> declineAppointment(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> declineAppointmentService(
    String appointmentId,
    String bookingId, {
    String? comment,
  }) => throw UnimplementedError();

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
  Future<Appointment> createAppointment(CreateAppointmentRequest req) =>
      throw UnimplementedError();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  /// Seeds the two-service visit and returns the row maps by id, so the fake
  /// repository can mutate exactly what the backend serves.
  Map<String, Map<String, dynamic>> seedVisit(FakeBackend fb) {
    // ELAPSED: 10:00–10:30 UTC vs a 12:00 UTC `kFixedNow`. CONFIRMED with
    // `endsAt` before `serverNow` → `_partitionOf` = PAST → inside the
    // archive's fixed `HISTORY` scope.
    final Map<String, dynamic> elapsed = <String, dynamic>{
      ...fb.datasetBookingRow(
        id: kElapsedServiceId,
        status: 'CONFIRMED',
        startsAt: kFixedNow.subtract(const Duration(hours: 2)),
        duration: const Duration(minutes: 30),
      ),
      // Server-computed (Phase 29.1/29.2); `BookingMapper` reads it straight
      // off the wire, and `datasetBookingRow` omits it, so a row that needs
      // «Виконано» must add it explicitly.
      'awaitingClosure': true,
      'appointmentId': kVisitId,
    };

    // NOT STARTED: 16:00–17:00 UTC vs the same 12:00 UTC `kFixedNow`.
    // CONFIRMED with `endsAt` after `serverNow` → UPCOMING → deliberately
    // OUTSIDE the archive's HISTORY scope. Its only route into the archive is
    // being wrongly transitioned to COMPLETED.
    final Map<String, dynamic> notStarted = <String, dynamic>{
      ...fb.datasetBookingRow(
        id: kNotStartedServiceId,
        status: 'CONFIRMED',
        startsAt: kFixedNow.add(const Duration(hours: 4)),
        duration: const Duration(minutes: 60),
      ),
      'awaitingClosure': false,
      'appointmentId': kVisitId,
    };

    fb.seedManyBookingsDataset(<Map<String, dynamic>>[elapsed, notStarted]);
    return <String, Map<String, dynamic>>{
      kElapsedServiceId: elapsed,
      kNotStartedServiceId: notStarted,
    };
  }

  /// Cold start → login as the fixture INDEPENDENT_MASTER → «Мої записи» →
  /// header archive button → [MasterArchiveScreen]. Mirrors
  /// `master_archive_flow_test.dart`'s `openArchive`.
  Future<GoRouter> openArchive(
    WidgetTester tester,
    FakeBackend fb,
    _FakeAppointmentRepository fakeAppt, {
    // Moves the APP's injected `clockProvider` instant away from [kFixedNow]
    // WITHOUT touching `FakeBackend.serverNow` — the one lever that can make
    // the two disagree, which is exactly what scenario 2 needs. Passed through
    // `AppHarness.boot`'s own `clock:` parameter, never via `extraOverrides`
    // (that would double-override `clockProvider` and throw).
    DateTime Function()? clock,
  }) async {
    final GoRouter router = await AppHarness.boot(
      tester,
      fb,
      clock: clock,
      extraOverrides: <Object>[
        appointmentRepositoryProvider.overrideWithValue(fakeAppt),
      ],
    );
    expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    await tester.tap(find.byKey(const Key('master-nav-tile-1')));
    await AppHarness.settle(tester);
    AppHarness.expectLocation(router, RouteNames.masterBookings);
    expect(find.byType(MasterBookingsScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('master-bookings-open-archive')));
    await AppHarness.settle(tester);
    AppHarness.expectNestedPushLocation(
      router,
      RouteNames.masterBookingsArchive,
    );
    expect(find.byType(MasterArchiveScreen), findsOneWidget);
    return router;
  }

  /// Every rendered `MasterBookingCard` — the cardinality probe the reported
  /// symptom needs. "svc-b is absent" alone would not catch a variant that
  /// surfaced OTHER siblings under different ids; "exactly one card" does.
  ///
  /// By TYPE rather than by key prefix on purpose: `master-booking-card-` also
  /// prefixes the card's INTERNAL element keys (`-divider-<id>`,
  /// `-complete-<id>`), so a prefix predicate counts parts of one card as
  /// several cards. `MasterBookingCard` is the project's own widget, not a
  /// framework one, so typing off it is exact.
  Finder allBookingCards() => find.byType(MasterBookingCard);

  // ==========================================================================
  // 1. THE REPORTED BUG — completing one archive row must not touch siblings
  // ==========================================================================
  testWidgets(
    'MASTER «Архів»: completing ONE elapsed service of a multi-service visit '
    'routes to the PER-SERVICE '
    'PATCH /appointments/{apptId}/services/{bookingId}/complete — never the '
    'whole-visit PATCH /appointments/{apptId}/complete — and the '
    'not-yet-started sibling neither completes nor materialises in the '
    'refetched HISTORY list',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final Map<String, Map<String, dynamic>> rows = seedVisit(fb);
      final fakeAppt = _FakeAppointmentRepository(rows);

      await openArchive(tester, fb, fakeAppt);

      // ── Landing: EXACTLY ONE card. The elapsed service is in HISTORY; the
      //    16:00 sibling is UPCOMING and must not be here. This is the "one
      //    service showed" half of the report, and it is the anti-vacuity
      //    baseline for every absence assertion below — without it, "svc-b is
      //    absent afterwards" could be satisfied by an empty list. ──────────
      expect(
        find.byKey(const Key('master-booking-card-$kElapsedServiceId')),
        findsOneWidget,
        reason:
            'the elapsed CONFIRMED/awaitingClosure service must be served '
            'under the archive\'s fixed partition:HISTORY scope',
      );
      expect(
        find.byKey(const Key('master-booking-card-$kNotStartedServiceId')),
        findsNothing,
        reason:
            'a CONFIRMED sibling whose endsAt is after serverNow classifies '
            'as UPCOMING — it has no business in the archive',
      );
      expect(allBookingCards(), findsOneWidget);

      // ── The «Виконано» affordance exists for the ELAPSED row only. The
      //    sibling has no row at all here, so its gate is proven at the widget
      //    tier (`master_booking_card_complete_gate_test.dart`); what this
      //    asserts is that no OTHER complete button is reachable on this
      //    screen. ─────────────────────────────────────────────────────────
      expect(
        find.byKey(
          const Key('master-booking-card-complete-$kElapsedServiceId'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('master-booking-card-complete-$kNotStartedServiceId'),
        ),
        findsNothing,
      );

      final int fetchesBeforeWrite = fb.getMyBookingsCalls;
      expect(fb.completeBookingCalls, 0);
      expect(fakeAppt.completeCalls, 0);
      expect(fakeAppt.completeServiceCalls, 0);

      // ── Close the elapsed service. ─────────────────────────────────────
      await tester.tap(
        find.byKey(
          const Key('master-booking-card-complete-$kElapsedServiceId'),
        ),
      );
      await AppHarness.settle(tester);
      expect(
        find.byKey(const Key('complete-booking-dialog')),
        findsOneWidget,
        reason: 'the SAME CompleteBookingDialog the detail screen uses',
      );

      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await AppHarness.settle(tester);

      // `MasterArchiveNotifier` is autoDispose per filter combination and the
      // modal dialog COVERS the list, so Riverpod 3 pauses the covered
      // consumer and the post-write `ref.invalidate` resolves on RESUME, not
      // immediately. Wait for the row's «Виконано» to genuinely leave the
      // rebuilt list rather than reading a stale pre-write frame — never gate
      // this on `value == null`, which `invalidate` does not produce.
      await AppHarness.pumpUntilGone(
        tester,
        find.byKey(
          const Key('master-booking-card-complete-$kElapsedServiceId'),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('complete-booking-dialog')),
        findsNothing,
        reason: 'the dialog closed on confirm',
      );

      // ── THE ASSERTION THAT WOULD HAVE CAUGHT THE ORIGINAL BUG. ──────────
      expect(
        fakeAppt.completeServiceCalls,
        1,
        reason:
            'the write must land on PATCH /appointments/{apptId}/services/'
            '{bookingId}/complete',
      );
      expect(fakeAppt.lastCompleteServiceAppointmentId, kVisitId);
      expect(
        fakeAppt.lastCompleteServiceBookingId,
        kElapsedServiceId,
        reason:
            'the tapped ROW\'s own booking id — not the visit id, not a '
            'sibling\'s',
      );
      expect(
        fakeAppt.completeCalls,
        0,
        reason:
            'the whole-visit PATCH /appointments/{apptId}/complete closes '
            'every child in lockstep and guards only the VISIT startsAt — an '
            'archive row must never reach it',
      );
      expect(
        fb.completeBookingCalls,
        0,
        reason:
            'an appointment child must never reach the bare per-booking '
            'PATCH /bookings/{id}/complete either',
      );

      // ── A REAL refetch happened. Without this, every absence assertion
      //    below is vacuous — an archive that simply never re-read the list
      //    would also "not show" the sibling. ──────────────────────────────
      expect(
        fb.getMyBookingsCalls,
        greaterThan(fetchesBeforeWrite),
        reason:
            'the archive must genuinely re-read partition:HISTORY over the '
            'HTTP boundary after the write',
      );

      // ── SIBLING IMMUTABILITY, on the wire and on screen. ────────────────
      expect(
        rows[kNotStartedServiceId]!['status'],
        'CONFIRMED',
        reason:
            'the 16:00 service never started — completing the 10:00 one must '
            'leave it CONFIRMED on the backend',
      );
      expect(
        find.byKey(const Key('master-booking-card-$kNotStartedServiceId')),
        findsNothing,
        reason:
            'THE REPORTED SYMPTOM: the not-yet-started sibling must not '
            'materialise as a fresh COMPLETED row in the refetched archive',
      );
      expect(
        allBookingCards(),
        findsOneWidget,
        reason:
            'still exactly ONE card — "all of today\'s bookings appeared" is '
            'exactly the regression this cardinality check exists to catch',
      );

      // ── The tapped row itself IS now closed (the write was not a no-op).
      //    It stays in HISTORY as COMPLETED — only its «Виконано» is gone. ──
      expect(rows[kElapsedServiceId]!['status'], 'COMPLETED');
      expect(
        find.byKey(const Key('master-booking-card-$kElapsedServiceId')),
        findsOneWidget,
      );
    },
  );

  // ==========================================================================
  // 2. THE GATE READS THE INJECTED CLOCK — not the device clock
  // ==========================================================================
  //
  // Scenario 1 cannot prove this. Its fixture is anchored to `kFixedNow`
  // (2026-06-14), which is in the past for the DEVICE clock too, so a screen
  // that wrongly read `DateTime.now()` would compute the SAME answer and
  // scenario 1 would still pass. That is the M15 trap in its purest form: a
  // gate the test cannot pin is a gate the test cannot prove.
  //
  // The lever is `AppHarness.boot(clock:)`, which moves the APP's clock ONLY
  // — `FakeBackend.serverNow` stays at `kFixedNow`, so the server still
  // classifies the 10:00 service into HISTORY and still serves it. The row
  // therefore RENDERS (the anti-vacuity half) while the app's own clock says
  // it has not started yet, so «Виконано» must be withheld. This models the
  // real conditions the local gate exists for: a device clock behind the
  // server's, or a page rendered from a stale partition.
  //
  // Both clocks are still explicitly PINNED — this is not a mixed
  // pinned/host-clock fixture. It is two pins that deliberately DISAGREE,
  // which is the only configuration that can observe which one the widget
  // actually consulted.
  testWidgets(
    'MASTER «Архів»: the «Виконано» gate is evaluated against the INJECTED '
    'clockProvider instant, not the device clock — a row the SERVER still '
    'classifies into HISTORY renders, but offers no close action while the '
    'app\'s own clock says the service has not started',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.independentMaster;
      final Map<String, Map<String, dynamic>> rows = seedVisit(fb);
      final fakeAppt = _FakeAppointmentRepository(rows);

      // One hour BEFORE the elapsed service's 10:00 start. `serverNow` is left
      // at `kFixedNow` (12:00), so partition classification is unchanged.
      final DateTime beforeServiceStart = kFixedNow.subtract(
        const Duration(hours: 3),
      );

      await openArchive(tester, fb, fakeAppt, clock: () => beforeServiceStart);

      // ANTI-VACUITY: the row is genuinely on screen. Without this, "no
      // «Виконано»" would be satisfied by an empty list — the single most
      // likely way this assertion could rot into proving nothing.
      expect(
        find.byKey(const Key('master-booking-card-$kElapsedServiceId')),
        findsOneWidget,
        reason:
            'serverNow is untouched, so the backend still serves this row '
            'under partition:HISTORY — only the APP clock moved',
      );
      expect(allBookingCards(), findsOneWidget);

      expect(
        find.byKey(
          const Key('master-booking-card-complete-$kElapsedServiceId'),
        ),
        findsNothing,
        reason:
            'the app clock says this service has not started — a screen '
            'reading DEVICE time instead of clockProvider would still offer '
            '«Виконано» here, which is precisely what this case detects',
      );

      // And nothing was written, because there was no affordance to write it.
      expect(fakeAppt.completeServiceCalls, 0);
      expect(fakeAppt.completeCalls, 0);
      expect(fb.completeBookingCalls, 0);
      expect(rows[kElapsedServiceId]!['status'], 'CONFIRMED');
    },
  );
}
