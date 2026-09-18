// Phase 341 (mobile-qa) — the SALON multi-service walk-in wizard, end to
// end, through the REAL Dio/repository/route wiring — for BOTH
// SALON_OWNER and SALON_ADMIN.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// Phases 335–340 closed a live data-loss defect: `SalonCreateBookingScreen`
// let a SALON_OWNER/SALON_ADMIN select up to `maxServicesPerVisit` services
// for a walk-in visit, showed all of them on confirm, and then
// `_submit` sent `masterServiceIds: <String>[assignmentId]` — ONE id. Pick
// three, see three, book one — a guest who was told they'd get a
// three-service visit got booked for the first service alone.
//
// `salon_create_booking_screen_test.dart` (widget tier) proves the wizard's
// own step mechanics against hand-built provider overrides — it cannot
// prove:
//   • the real `GET /salons/{salonId}/masters`/`.../services`/
//     `.../services/{serviceDefId}/masters` chain behind
//     `salonMastersRosterProvider`/`salonServiceCatalogProvider`/
//     `salonMasterServiceCoverageProvider`, wired through a real (fake) HTTP
//     backend;
//   • that the real `POST /api/v1/masters/{masterId}/bookings` body — not a
//     hand-shaped fake repository call — actually carries every selected
//     service's assignment id, in order;
//   • that the REAL board's «+» (`salon_bookings_screen.dart
//     ._openCreateBooking`, phase 340) reaches this wizard through a real
//     `context.push`, for BOTH roles that can open it — a SALON_ADMIN has no
//     master profile at all, and D4 of phase 337 explicitly requires the
//     masters step not assume one.
//
// THE ASSERTION THIS FILE EXISTS TO MAKE (and the widget tier cannot, on its
// own fake repository, make as convincingly): pick THREE services -> all
// THREE reach the wire request, in tap order -> the done step renders all
// THREE server-returned items. A run that only ever books one service proves
// nothing about the regression this track closes.
//
// 2026-09-18 DEVICE-PASS EXTENSION (mobile-qa) — three more real-user-
// reachable behaviours from the same device pass, proven here against the
// REAL Dio/repository/route wiring (the widget tier already proves each of
// these against a hand-mocked repository — see
// `salon_create_booking_screen_test.dart`'s "masters step" and "day-level
// gating" groups — this file adds the wire-level confirmation Rule 3b
// requires for a real-user-flow change):
//   • a master who does not cover EVERY selected service is ABSENT from the
//     masters list, not merely dimmed (`_expectPartialCoverageMasterIsAbsent`);
//   • a covering master with zero free time on the picked day renders
//     PRESENT, DISABLED, and labelled «Немає вільного часу»
//     (`_expectSlotlessMasterIsDisabled` — the new fixture master
//     `FakeBackend.kSalonWizardMasterSlotless`);
//   • the date step greys a day no covering master works, and leaves
//     tappable a day at least one does (`_expectDayGating` — unions
//     `master-aaa` and `kSalonWizardMasterSlotless`'s real working-days
//     responses via `FakeBackend.forceNonWorkingDate`).
//
// NO PATROL FLOW: this journey touches no OS permission dialog, no deep
// link / app link, no FCM or local notification, no WebView and no
// biometric prompt — a pure screen / route / provider / HTTP journey, so
// Step 2.7 Rule 3b's `integration_test/patrol/` requirement does not apply.
// Stated explicitly, not omitted.
//
// SCOPE DECISION — what this file does NOT re-prove:
//   • The exact `serviceIds=` query composition sent to
//     `salonMasterDaySlotsProvider` (phase 336's own id-space/tap-order
//     pins) — already proven precisely at the notifier/widget tier with a
//     hand-mocked repository, which can assert the exact query in a way an
//     HTTP path-only route match (this fake's `DioAdapter` ignores query
//     params) cannot improve on.
//   • `SALON_MASTER`'s denial — already proven at both tiers elsewhere
//     (`bookings_capability_test.dart`'s role matrix for the button;
//     `test/routing/auth_redirect_test.dart:738,771` for the route guard).
//     Re-deriving a third copy of that denial here, with its own session
//     fixture, would be scope creep on a diff that touches neither surface.
//   • Golden coverage for the masters/confirm steps' new multi-service
//     rendering (phase 341 D6) — out of this file's remit; flagged
//     separately as a gap, never faked here as "acceptance" (regenerating a
//     golden is self-referential, `feedback_golden_not_acceptance`).
//
// FIXTURE (`fake_backend.dart`'s `_wireSalonMultiServiceWizard` /
// `_wireSalonAdminBoard`, phase 341 mobile-qa addition) — THREE catalogue
// services (`wiz-svc-a/b/c`) and FOUR roster masters reusing existing
// `_salonMasters` identities:
//   • `master-aaa` — covers ALL THREE and HAS free time -> the one bookable
//     tile.
//   • `master-eee` — covers TWO of three (a, b — NOT c) -> the
//     DISCRIMINATING case an `any` filter would wrongly pass; ABSENT from
//     the rendered list (2026-09-18 device pass: hidden, not dimmed).
//   • `master-fff` — covers NONE -> absent from every coverage response.
//   • `master-ggg` (`FakeBackend.kSalonWizardMasterSlotless`, 2026-09-18
//     device-pass addition) — covers ALL THREE, same as `master-aaa`, but
//     its OWN `/slots` route always answers empty -> renders PRESENT,
//     DISABLED, «Немає вільного часу».
// Registered under BOTH `FakeBackend.kOwnerSalonId` and
// `FakeBackend.kAdminSalonId` — the two roles' own salons.
//
// CLOCK: `AppHarness.boot` pins `clockProvider` to `kFixedNow`
// (`e2e_boot_policy.dart`) for the whole tier; `_kyivToday`/`_kGreyDay`
// below are derived from that SAME injected clock, never the host clock
// (`project_test_clock_coherence_invariant`).
//
// FINDERS: widget Keys and widget TYPES, plus NAMED Cyrillic constants
// passed to `find.text(...)` (never a literal at the call site — see
// `FakeBackend.kSalonWizSvcAName`'s own doc, mirroring
// `master_create_booking_test.dart`'s `_kSvc1Name` precedent —
// `scripts/forbid_cyrillic_finder.sh` scans the call site's own text).
//
// For a STANDALONE local run this file is never batched with another
// `integration_test/*.dart` file in the same invocation — this repo's
// toolchain kills the second file with a bogus "log reader failed":
//
//   flutter test integration_test/salon_create_booking_test.dart -d flutter-tester

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/slot_chip.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_bookings_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/pump_app.dart';
import 'support/app_harness.dart';

/// Kyiv "today" as the app under test computes it — derived from the
/// harness's injected clock (`kFixedNow`), never the host device clock.
final DateTime _kyivToday = kyivToday(() => kFixedNow);

/// A day two days after [_kyivToday] — same visible month (`kFixedNow` is
/// 2026-06-14, so this is 2026-06-16), no month-nav needed. Forced
/// non-working via `FakeBackend.forceNonWorkingDate` in `_expectDayGating`.
final DateTime _kGreyDay = _kyivToday.add(const Duration(days: 2));

/// Drives login -> shell -> «Записи» tab -> «+» -> the wizard's `client`
/// step, filled and advanced. Shared by both role runs below — the ONLY
/// difference between them is [role]/[salonId] and the FakeBackend they are
/// handed.
Future<void> _loginAndOpenWizard(
  WidgetTester tester,
  FakeBackend fb,
  UserRole role,
) async {
  await AppHarness.boot(tester, fb);
  await AppHarness.loginAs(tester, fb, role);

  await AppHarness.pumpUntilFound(
    tester,
    find.byType(SalonShellScreen),
    timeout: const Duration(seconds: 20),
  );

  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const Key('salon-nav-tile-1')),
    timeout: const Duration(seconds: 20),
  );
  await tester.tap(find.byKey(const Key('salon-nav-tile-1')));
  await AppHarness.settle(tester);
  expect(find.byType(SalonBookingsScreen), findsOneWidget);

  await tester.tap(find.byKey(const Key('master-bookings-add')));
  await AppHarness.settle(tester);
  expect(
    find.byType(SalonCreateBookingScreen),
    findsOneWidget,
    reason: 'the board\'s «+» must reach the approved salon wizard (phase 340)',
  );

  await tester.enterText(
    find.byKey(const Key('master-create-booking-first-name')),
    'Марина',
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-last-name')),
    'Гончар',
  );
  await tester.enterText(
    find.byKey(const Key('master-create-booking-phone')),
    '0671234567',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('master-create-booking-client-next')));
  await AppHarness.settle(tester);
}

/// Selects all THREE fixture services, in catalogue order
/// (`FakeBackend.kSalonWizSvcA/B/C`), and advances.
Future<void> _selectThreeServices(WidgetTester tester) async {
  for (final String id in const <String>[
    FakeBackend.kSalonWizSvcA,
    FakeBackend.kSalonWizSvcB,
    FakeBackend.kSalonWizSvcC,
  ]) {
    final Finder card = find.byKey(Key('mcb_service_card_$id'));
    await AppHarness.pumpUntilFound(tester, card);
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('booking-summary-cta')));
  await AppHarness.settle(tester);
}

/// Picks [_kyivToday] on the date step and advances to `masters`.
Future<void> _pickDate(WidgetTester tester) async {
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const Key('salon-create-booking-date-calendar')),
  );
  await tester.tapCalendarDay(_kyivToday.day);
  await AppHarness.settle(tester);
  await tester.tap(find.byKey(const Key('salon-create-booking-date-next')));
  await AppHarness.settle(tester);
}

/// 2026-09-18 device-pass extension — the date step's day-level gating,
/// proven against the REAL `workingDaysProvider` fan-out (union across every
/// covering master): [_kGreyDay] is forced non-working for BOTH covering
/// masters (`master-aaa` and `FakeBackend.kSalonWizardMasterSlotless` — the
/// fixture's `forceNonWorkingDate` feeds the SAME shared `_workingDaysEnvelope`
/// both of their `/working-days` routes answer with), so a day genuinely
/// greyed here proves the union actually consulted BOTH masters' real wire
/// responses, not just one. [_kyivToday] is left alone, so it stays the
/// "at least one covering master works it" control.
///
/// Called BEFORE any date is picked (right after the date step first
/// mounts), so the CTA's "nothing selected yet" state doubles as the control
/// for "a tap on the grey cell selected nothing".
Future<void> _expectDayGating(WidgetTester tester) async {
  await AppHarness.pumpUntilFound(
    tester,
    find.byKey(const Key('salon-create-booking-date-calendar')),
  );

  final Finder greyCell = find.byKey(
    Key('booking-calendar-day-${_kGreyDay.day}'),
  );
  await tester.ensureVisible(greyCell);
  await AppHarness.settle(tester);
  expect(greyCell, findsOneWidget);
  expect(
    find.descendant(of: greyCell, matching: find.byType(GestureDetector)),
    findsNothing,
    reason:
        'no covering master works ${_kGreyDay.toIso8601String()} (forced '
        'via FakeBackend.forceNonWorkingDate on BOTH master-aaa and '
        'kSalonWizardMasterSlotless) — the union must grey it out: no '
        'GestureDetector under the cell (month_calendar.dart / '
        'calendar_grid.dart\'s CalendarDayCell renders a bare Semantics '
        'when onTap is null)',
  );

  final Finder todayCell = find.byKey(
    Key('booking-calendar-day-${_kyivToday.day}'),
  );
  await tester.ensureVisible(todayCell);
  await AppHarness.settle(tester);
  expect(
    find.descendant(of: todayCell, matching: find.byType(GestureDetector)),
    findsOneWidget,
    reason:
        'today is NOT the forced non-working day — at least one covering '
        'master works it, so the union must leave it tappable',
  );

  // The grey cell is genuinely inert, not merely unfound: a raw tap must not
  // select it. `warnIfMissed: false` — the tap lands cleanly on the
  // scroll view behind the cell (no GestureDetector to catch it), which is
  // the documented safe no-op (`tapCalendarDay`'s own doc in
  // `test/helpers/pump_app.dart`), not a genuine hit-test miss.
  await tester.tap(greyCell, warnIfMissed: false);
  await AppHarness.settle(tester);
  final NeumorphicButton dateNextButton = tester.widget<NeumorphicButton>(
    find.byKey(const Key('salon-create-booking-date-next')),
  );
  expect(
    dateNextButton.onPressed,
    isNull,
    reason:
        'the grey-day tap must not have selected a date — the CTA stays '
        'disabled exactly as it was before any pick',
  );
}

/// Case 4 of the phase-341 matrix — the DISCRIMINATING assertion: a master
/// covering TWO of the three selected services must be ABSENT from the
/// rendered list. 2026-09-18 device-pass fix: this used to render dimmed
/// and inert; it is hidden entirely now (`SalonMastersStep` drops
/// non-covering masters before ever building a tile — see
/// `salon_booking_wizard_steps.dart`'s header) — this replaces the old
/// "dimmed and inert" assertion (which would now fail: there is no tile to
/// scroll to or tap at all).
Future<void> _expectPartialCoverageMasterIsAbsent(WidgetTester tester) async {
  expect(
    find.byKey(
      const Key('salon-master-tile-${FakeBackend.kSalonWizardMasterPartial}'),
    ),
    findsNothing,
    reason:
        'a master covering only 2 of 3 selected services must be HIDDEN '
        'entirely (2026-09-18 device-pass fix), not merely dimmed — the '
        '"every", not "any", filter (phase 335 D2)',
  );
  expect(
    find.byKey(
      const Key('salon-master-tile-${FakeBackend.kSalonWizardMasterNone}'),
    ),
    findsNothing,
    reason: 'a master covering NONE of the selected services is hidden too',
  );
}

/// 2026-09-18 device-pass addition — the THIRD tile state: a master who
/// covers EVERY selected service but has genuinely zero free time on the
/// picked day (`FakeBackend.kSalonWizardMasterSlotless`'s `/slots` route
/// always answers empty) renders PRESENT, DISABLED, and labelled «Немає
/// вільного часу» — known EAGERLY (no tap needed), and tapping it is a
/// no-op (it can never expand into a slot section).
Future<void> _expectSlotlessMasterIsDisabled(WidgetTester tester) async {
  final Finder slotlessTile = find.byKey(
    const Key('salon-master-tile-${FakeBackend.kSalonWizardMasterSlotless}'),
  );
  // `ListView.separated` is viewport-lazy — roster order puts `master-ggg`
  // right after the full-covering `master-aaa`, but flutter-tester's 800x600
  // surface plus the header content above the list can still leave it
  // outside the initial cache extent. `scrollUntilVisible` (not a bare
  // `pumpUntilFound`, which never scrolls) mirrors `_expandAndPickSlot`'s own
  // recipe (`project_integration_scroll_filter_into_view`).
  await tester.scrollUntilVisible(
    slotlessTile,
    120,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('salon-create-booking-masters-list')),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 30,
  );
  await tester.ensureVisible(slotlessTile);
  await AppHarness.settle(tester);
  expect(slotlessTile, findsOneWidget);

  final AppLocalizations l10n = AppLocalizations.of(
    tester.element(find.byType(SalonCreateBookingScreen)),
  );
  expect(
    find.descendant(
      of: slotlessTile,
      matching: find.text(l10n.bookingNoSlotsTitle),
    ),
    findsOneWidget,
    reason:
        'a covering master with zero free time on the picked day must '
        'render the «Немає вільного часу» pill without requiring a tap '
        '(eager fetch, 2026-09-18 device-pass fix)',
  );

  await tester.tap(slotlessTile);
  await tester.pumpAndSettle();
  expect(
    find.byKey(const Key('salon-master-tile-slots-empty')),
    findsNothing,
    reason:
        'a disabled tile must never expand — its own slot section must '
        'never mount',
  );
  expect(find.byType(SlotChip), findsNothing);
}

/// Expands the full-covering master's tile, picks the first available slot,
/// and returns once `confirm` is reached (the masters step auto-advances on
/// slot pick — phase 337 D4, no «Далі» CTA on this step).
Future<void> _expandAndPickSlot(WidgetTester tester) async {
  final Finder fullTile = find.byKey(
    const Key('salon-master-tile-${FakeBackend.kSalonWizardMasterFull}'),
  );
  // `_expectSlotlessMasterIsDisabled` (run just above) scrolls the SAME
  // `ListView` DOWN to `master-ggg`'s tile (roster order puts the full-
  // covering `master-aaa` FIRST, above it), so it must be scrolled back
  // into view — a bare `find.byKey` defaults `skipOffstage: true` and finds
  // nothing once it has scrolled out
  // (`project_integration_scroll_filter_into_view`).
  await tester.scrollUntilVisible(
    fullTile,
    -120,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('salon-create-booking-masters-list')),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 30,
  );
  // `scrollUntilVisible` stops the instant the finder is FOUND, which can
  // leave it only PARTIALLY inside the viewport's clip (edge-aligned, not
  // centered) — `getCenter()` then derives an offset outside the clipped
  // region, landing the tap on whatever sits behind it instead
  // (`project_integration_scroll_filter_into_view`). `ensureVisible` computes
  // the exact scroll needed to bring the WHOLE widget on screen, which a
  // stepwise drag-until-found does not guarantee.
  await tester.ensureVisible(fullTile);
  await AppHarness.settle(tester);
  await tester.tap(fullTile);
  await AppHarness.settle(tester);

  final Finder availableChip = find
      .byWidgetPredicate((Widget w) => w is SlotChip && w.available)
      .first;
  await AppHarness.pumpUntilFound(tester, availableChip);
  await tester.ensureVisible(availableChip);
  await AppHarness.settle(tester);
  await tester.tap(availableChip);
  await AppHarness.settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Shared journey body — [role]/[salonId] are the only per-run variables.
  /// Runs BOTH roles through the IDENTICAL sequence of real UI interactions
  /// (phase 341 D4).
  Future<void> runJourney(
    WidgetTester tester, {
    required UserRole role,
    required String salonId,
  }) async {
    await mockNetworkImagesFor(() async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = role
        ..salonBoardBookings = <Map<String, dynamic>>[];

      await _loginAndOpenWizard(tester, fb, role);

      // 2026-09-18 device-pass extension — forces BOTH covering masters'
      // (`master-aaa`/`kSalonWizardMasterSlotless`) `/working-days`
      // response to report [_kGreyDay] non-working, so `_expectDayGating`
      // below can prove the date step's real union, not just its fail-open
      // default. Set AFTER `AppHarness.boot` (inside `_loginAndOpenWizard`)
      // has run `initBeauticaTimeZones()` — [_kGreyDay] is derived from
      // [_kyivToday], which reads `beauticaZone` on first access and throws
      // if read any earlier — and BEFORE the date step ever mounts (the
      // wizard is still on `client` here).
      fb.forceNonWorkingDate = _kGreyDay;

      await _selectThreeServices(tester);

      // Day-level gating (2026-09-18 device-pass extension) — proven right
      // as the date step mounts, before any date is picked.
      await _expectDayGating(tester);

      await _pickDate(tester);

      // The discriminating coverage case (phase 341 D3) — proven BEFORE
      // picking the bookable master, so a regression that makes the
      // partial-coverage master render again is caught independently of
      // whichever master the flow goes on to book.
      await _expectPartialCoverageMasterIsAbsent(tester);

      // The zero-free-time case (2026-09-18 device-pass extension) — same
      // ordering rationale as the coverage case just above.
      await _expectSlotlessMasterIsDisabled(tester);

      await _expandAndPickSlot(tester);

      // `masters` auto-advances straight to `confirm` on slot pick — no
      // intermediate CTA (phase 337 D4, pinned here structurally: the next
      // widget found below IS the confirm step's own submit button).
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('salon-create-booking-submit-cta')),
      );
      await tester.tap(
        find.byKey(const Key('salon-create-booking-submit-cta')),
      );
      await AppHarness.settle(tester);

      // ── THE assertion this file exists to make ──────────────────────────
      expect(
        fb.createSalonWizardBookingCalls,
        1,
        reason: 'the confirm CTA must submit exactly one visit',
      );
      expect(
        fb.lastSalonWizardBookingRequestBody?['masterServiceIds'],
        const <String>[
          'assign-${FakeBackend.kSalonWizardMasterFull}-${FakeBackend.kSalonWizSvcA}',
          'assign-${FakeBackend.kSalonWizardMasterFull}-${FakeBackend.kSalonWizSvcB}',
          'assign-${FakeBackend.kSalonWizardMasterFull}-${FakeBackend.kSalonWizSvcC}',
        ],
        reason:
            'all THREE selected services\' assignment ids must reach the '
            'wire request, in tap order — the pre-335 wizard would have '
            'sent a ONE-element list here '
            '(salon_create_booking_screen.dart, the deleted _primaryService '
            'shim)',
      );
      expect(
        fb.lastSalonWizardBookingRequestBody?['masterServiceIds'],
        isNot(contains(FakeBackend.kSalonWizSvcA)),
        reason:
            'the id-space pin — the wire ids are the master\'s OWN '
            'assignment ids, never the salon-catalog serviceDefId '
            '(SalonMastersStep.onPick\'s own doc)',
      );

      // ── done renders the SERVER's three items ───────────────────────────
      await AppHarness.pumpUntilFound(
        tester,
        find.byKey(const Key('salon-create-booking-done-card')),
      );
      expect(find.text(FakeBackend.kSalonWizSvcAName), findsOneWidget);
      expect(find.text(FakeBackend.kSalonWizSvcBName), findsOneWidget);
      expect(find.text(FakeBackend.kSalonWizSvcCName), findsOneWidget);

      await tester.tap(find.byKey(const Key('salon-create-booking-done-cta')));
      await AppHarness.settle(tester);
      expect(
        find.byType(SalonBookingsScreen),
        findsOneWidget,
        reason: '«Готово» must return to the board',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Phase 341: SALON_OWNER books a THREE-service walk-in visit through the '
    'approved wizard — one POST, three ordered masterServiceIds, the done '
    'step renders all three',
    (tester) => runJourney(
      tester,
      role: UserRole.salonOwner,
      salonId: FakeBackend.kOwnerSalonId,
    ),
  );

  testWidgets(
    'Phase 341: SALON_ADMIN books the SAME THREE-service walk-in visit — '
    'the masters step must not assume the caller has a master profile',
    (tester) => runJourney(
      tester,
      role: UserRole.salonAdmin,
      salonId: FakeBackend.kAdminSalonId,
    ),
  );
}
