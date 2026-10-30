// Phase 309-311 — E2E: the SALON_MASTER's real «Графік» journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b)
// ----------------------------------------
// The dense unit/widget coverage for this track (`schedule_capability_test
// .dart`, the three `*_read_only_test.dart` files, `master_schedule_screen
// _test.dart`'s D4/role-gating groups, `salon_master_profile_screen_test
// .dart`'s nav group, `auth_redirect_test.dart`'s `/staff/*` matrix,
// `app_router_page_type_test.dart`'s PT-1/PT-2) all prove their slice in
// isolation: a bespoke `GoRouter` with two or three routes, a hand-built
// `ProviderContainer`/`ProviderScope` with `scheduleEditableProvider` (or the
// session it derives from) overridden directly, and — for the screen tests —
// a fake `ScheduleRepository` returning a canned fixture. None of that tier
// drives:
//   • the REAL post-login landing dispatch (`roleHomePath`) putting a
//     SALON_MASTER on `/staff/profile` in the first place;
//   • the REAL `VelvetBottomNavBar` on `SalonMasterProfileScreen`, built with
//     its Phase 310 `scheduleRoute` override, through a REAL tap;
//   • the REAL `auth_redirect.dart` gate admitting `/staff/schedule` and
//     leaving `/schedule` closed, both resolved by the ACTUAL redirect
//     callback wired into `appRouter`, not a hand-rolled substitute;
//   • the REAL `masterProfileProvider` → `GET /masters/me` →
//     `scheduleRepositoryProvider` → `GET .../weekly-schedules` /
//     `.../overrides` chain against a real (fake) HTTP backend, landing on a
//     row this role does not own by construction (`fake_backend.dart` keys
//     `GET /masters/me` off role-agnostic `_masterDetailEnvelope()` — proving
//     that is exactly the point, not an assumption);
//   • that the read-only rendering and the editable rendering are the SAME
//     widget tree reached through the SAME real navigation stack — the
//     screen-tier suites each construct their own router and never tap a
//     shared nav bar to get there.
//
// FIXTURE: `FakeBackend`'s default weekly template (`schedule-1`,
// `validFrom: 2026-06-14`) marks Monday/Tuesday (`dayOfWeek` 1/2) working and
// Wed-Sun (3-7) empty — see that class's `_weeklySchedule` doc. `kFixedNow`
// (`2026-06-14T12:00:00Z`, injected by `AppHarness.boot`) is a SUNDAY
// (`dayOfWeek` 7), so the screen's initial "today" selection lands on a day
// the template marks NOT working. That is exercised deliberately, not
// incidentally: it means the per-day `NoScheduleBanner` (and its
// `no-schedule-add-hours` CTA) is actually ON SCREEN for both roles below,
// so "the CTA is absent" is proven against a banner that is really rendered
// — not vacuously true because the banner never appears in the first place
// (M14: a negative assertion that can pass for the wrong reason). No
// overrides are seeded, so nothing but the template decides this.
//
// Until 2026-10-30 (mobile-qa, «Графік» booked-slots cycle 2) the screen read
// "today" from `DateTime.now()` and IGNORED `kFixedNow`, so the banner held
// only because the HOST day happened to be a non-working weekday too. The
// screen now reads the harness's `clockProvider`; the journeys below pin the
// selected strip day to `kFixedNow`'s Kyiv day before asserting the banner.
//
// NO PATROL FLOW: nothing in this journey touches an OS permission dialog, a
// deep link / app link, FCM or a local notification, a WebView, or a
// biometric prompt. It is a pure screen / route / provider / GET journey, so
// Step 2.7 Rule 3b's `integration_test/patrol/` requirement does not apply.
// Stated explicitly (mobile-qa), not omitted.
//
// FINDERS: widget Keys and widget TYPES only — never a Cyrillic UI string
// (`forbid_cyrillic_finder.sh`). `find.byType(MasterScheduleScreen)` (not a
// route-string assertion alone) pins the resolved page, per the go_router
// literal-before-dynamic-shadowing trap this repo has been bitten by before.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/master_schedule_screen.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/day_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/schedule_widgets.dart';
import 'package:beautica_mobile/features/schedule/presentation/widgets/slot_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:network_image_mock/network_image_mock.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  testWidgets(
    'SALON_MASTER taps «Графік» from /staff/profile, lands on the REAL '
    'read-only «Графік роботи» with their own hours loaded and zero edit '
    'affordances, then returns to /staff/profile',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.salonMaster);
        await AppHarness.settle(tester);

        // ── Landing ──────────────────────────────────────────────────────
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);

        // ── Tap the REAL «Графік» nav tile ──────────────────────────────
        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-2')),
        );
        await AppHarness.settle(tester);

        // Pin the resolved page TYPE, not the route string — a string
        // assertion alone passes under go_router's literal-before-dynamic
        // shadowing even if a different page happened to build.
        expect(find.byType(MasterScheduleScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.salonMasterSchedule);

        // No error state — the real wire calls succeeded (no 403/404 logged
        // as a rendered failure).
        expect(find.byKey(const Key('schedule-retry')), findsNothing);

        // The data came over the REAL wire, not a canned widget-tier fixture.
        expect(
          fb.getMasterCalls,
          greaterThanOrEqualTo(1),
          reason:
              'the screen must resolve its owning master through a real '
              'GET /masters/me round trip',
        );

        // ── Content renders: their own hours are visible ────────────────
        expect(
          find.byKey(const Key('schedule-today')),
          findsOneWidget,
          reason: 'the day rail must render with today marked',
        );
        expect(
          find.byType(WeekdayPillRow),
          findsOneWidget,
          reason: 'the weekly-template card must render its content',
        );
        expect(
          find.byType(SlotLegend),
          findsOneWidget,
          reason: 'the slot legend must render',
        );
        expect(
          tester
              .widgetList<WeekStripDay>(find.byType(WeekStripDay))
              .singleWhere((WeekStripDay c) => c.selected)
              .day,
          kyivToday(() => kFixedNow).day,
          reason:
              'the initial selection must be the harness\'s fixed day '
              '(kFixedNow → 2026-06-14), not the host clock\'s',
        );
        expect(
          find.byType(NoScheduleBanner),
          findsOneWidget,
          reason:
              'today (2026-06-14, Sunday) has no hours in the seeded '
              'template (dayOfWeek 3-7 are empty) — the per-day empty-state '
              'banner must actually be on screen, otherwise the missing-CTA '
              'assertion below would be vacuously true (M14)',
        );

        // ── Every edit affordance absent ─────────────────────────────────
        expect(
          find.byKey(const Key('schedule-weekly-card')),
          findsNothing,
          reason: 'the template card must not be tappable',
        );
        expect(
          find.byKey(const Key('schedule-day-pencil')),
          findsNothing,
          reason: 'no day pencil for a read-only viewer',
        );
        expect(
          find.byKey(const Key('no-schedule-add-hours')),
          findsNothing,
          reason:
              'the NO_SCHEDULE banner\'s CTA must be hidden for a read-only '
              'viewer even though the banner itself renders (see above)',
        );

        // ── Back returns to /staff/profile ───────────────────────────────
        //
        // NOT ASSERTED HERE — the "in ONE hop" half of D4. Verified by
        // mutation (mobile-qa): reverting `context.go(profileRoute)` back to
        // the pre-D4 `context.go(RouteNames.masterProfile)` literal in
        // `master_schedule_screen.dart` and re-running this test STAYED
        // GREEN — go_router resolves its whole `redirect` chain synchronously
        // before building any page, so the wrong-then-corrected 2-hop path
        // and the direct 1-hop path are indistinguishable at the WIDGET-TREE
        // level; both settle on the identical final frame. That is exactly
        // the "wrong destination, corrected by a guard, normalised as
        // correct" failure mode D4's own doc warns about, reproduced here.
        // The hop COUNT can only be observed by instrumenting the `redirect`
        // callback itself, which `test/features/schedule/presentation/
        // master_schedule_screen_test.dart`'s "back-fallback lands on role
        // home (Phase 309 D4)" group already does (a `redirectLog` wrapping
        // `authRedirectForLocation`, mutation-checked against this exact
        // regression). This E2E test's job — and the one thing that widget
        // tier structurally cannot prove — is that the REAL production
        // `app_router.dart` wiring (real `VelvetTopBar`, real `roleHomePath`,
        // real `auth_redirect.dart`) lands on the right FINAL screen; it
        // relies on the widget-tier test above for the hop count.
        await tester.tap(find.byType(NeumorphicIconButton));
        await AppHarness.settle(tester);

        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        expect(find.byType(MasterProfileScreen), findsNothing);
        AppHarness.expectLocation(router, RouteNames.salonMasterProfile);
      });
    },
  );

  testWidgets(
    'CONTROL — INDEPENDENT_MASTER\'s identical journey still lands on '
    '/schedule with every edit affordance PRESENT',
    (tester) async {
      await mockNetworkImagesFor(() async {
        final fb = FakeBackend();
        final GoRouter router = await AppHarness.boot(tester, fb);
        await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
        await AppHarness.settle(tester);

        expect(find.byType(MasterProfileScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.masterProfile);

        await AppHarness.tapVisible(
          tester,
          find.byKey(const Key('master-nav-tile-2')),
        );
        await AppHarness.settle(tester);

        expect(find.byType(MasterScheduleScreen), findsOneWidget);
        AppHarness.expectLocation(router, RouteNames.masterSchedule);

        // Same "today" (2026-06-14, Sunday, no seeded hours) as the
        // SALON_MASTER journey above — the banner is on screen here too,
        // so this is a true positive counterpart, not a different fixture.
        expect(
          tester
              .widgetList<WeekStripDay>(find.byType(WeekStripDay))
              .singleWhere((WeekStripDay c) => c.selected)
              .day,
          kyivToday(() => kFixedNow).day,
        );
        expect(find.byType(NoScheduleBanner), findsOneWidget);

        expect(
          find.byKey(const Key('schedule-weekly-card')),
          findsOneWidget,
          reason: 'an editable viewer CAN tap the template card',
        );
        expect(
          find.byKey(const Key('schedule-day-pencil')),
          findsOneWidget,
          reason: 'an editable viewer sees the day pencil',
        );
        expect(
          find.byKey(const Key('no-schedule-add-hours')),
          findsOneWidget,
          reason: 'an editable viewer sees the NO_SCHEDULE CTA',
        );
      });
    },
  );
  // ── Booked-slots overlay (2026-10-30, Step 2.7 Rule 3b) ──────────────────
  //
  // The widget tier (`master_schedule_screen_test.dart`) stubs
  // `bookingsDayProvider` wholesale, so it never proves the REAL
  // `scheduleBookingsQueryFor(OwnScheduleScope)` → `bookingsDayProvider` →
  // `BookingRepository.getMyBookings` → `GET /bookings/me?from=&to=&status=`
  // chain, nor the wire-to-domain mapping of `startsAt`/`endsAt` that
  // `buildDayCells` paints from. This journey does, over the fake backend.
  //
  // FIXTURE: today (kFixedNow → 2026-06-14, Kyiv) is seeded as a 09:00–18:00
  // working day through `seedEffectiveSchedule`, so the 18-cell grid (not the
  // NO_SCHEDULE banner) renders. Two rows on that day via
  // `seedManyBookingsDataset`: a CONFIRMED 16:00–17:00 Kyiv (13:00Z, UTC+3)
  // and a CANCELLED 10:00–11:00 Kyiv. Exactly the 16:00 and 16:30 cells must
  // read booked; the cancelled hour must stay free. Both clocks are the SAME
  // pinned clock (M15): fixture `kyivToday(() => kFixedNow)`, app `kFixedNow`.
  testWidgets(
    'INDEPENDENT_MASTER «Графік»: a CONFIRMED booking on the shown day paints '
    'its cells booked over GET /bookings/me, a CANCELLED one paints none, and '
    'the legend carries the booked entry',
    (tester) async {
      // Disposed inside the body (not `addTearDown`): flutter_test verifies
      // handles BEFORE tear-downs run.
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await mockNetworkImagesFor(() async {
          final fb = FakeBackend();
          final GoRouter router = await AppHarness.boot(tester, fb);
          // Seeded AFTER boot: `kyivToday` needs the tz database the boot
          // policy initialises, and every route reads its seed at REQUEST time
          // (nothing schedule- or booking-shaped is fetched before the tap).
          final DateTime today = kyivToday(() => kFixedNow);
          fb.seedEffectiveSchedule(<Map<String, dynamic>>[
            FakeBackend.seedEffectiveScheduleDay(today),
          ]);
          fb.seedManyBookingsDataset(<Map<String, dynamic>>[
            fb.datasetBookingRow(
              id: 'sched-booked-confirmed',
              status: 'CONFIRMED',
              startsAt: DateTime.utc(today.year, today.month, today.day, 13),
            ),
            fb.datasetBookingRow(
              id: 'sched-booked-cancelled',
              status: 'CANCELLED',
              startsAt: DateTime.utc(today.year, today.month, today.day, 7),
            ),
          ]);
          await AppHarness.loginAs(tester, fb, UserRole.independentMaster);
          await AppHarness.settle(tester);

          expect(find.byType(MasterProfileScreen), findsOneWidget);

          // Entered through the REAL `?date=` deep entry (the bookings
          // timeline's «Графік» CTA uses the same route), NOT the nav tile.
          // Since the 2026-10-30 cycle-2 fix the screen's "today" also comes
          // from the harness's `clockProvider` (`kFixedNow`); the explicit
          // `?date=` keeps this journey pinned to the fixture's day even if
          // that default ever regresses (M15: one clock for fixture + app).
          final String dateToken =
              '${today.year.toString().padLeft(4, '0')}-'
              '${today.month.toString().padLeft(2, '0')}-'
              '${today.day.toString().padLeft(2, '0')}';
          router.go('${RouteNames.masterSchedule}?date=$dateToken');
          await AppHarness.settle(tester);
          expect(find.byType(MasterScheduleScreen), findsOneWidget);
          AppHarness.expectLocation(router, RouteNames.masterSchedule);

          // The shown day is a seeded working day → the grid, not the banner, renders
          // (otherwise "no booked cell" below would be vacuous — M14).
          expect(find.byType(NoScheduleBanner), findsNothing);
          await tester.ensureVisible(find.byType(SlotLegend));
          await AppHarness.settle(tester);
          expect(find.byType(SlotChip), findsWidgets);

          // The booked state came over the REAL wire for THIS day.
          expect(fb.getMyBookingsCalls, greaterThanOrEqualTo(1));
          expect(fb.lastMyBookingsQuery?['from'].toString(), '2026-06-14');

          final List<TimeOfDay> booked = tester
              .widgetList<SlotChip>(find.byType(SlotChip))
              .where((SlotChip c) => c.cell.state == SlotState.booked)
              .map((SlotChip c) => c.cell.time)
              .toList();
          expect(
            booked,
            const <TimeOfDay>[
              TimeOfDay(hour: 16, minute: 0),
              TimeOfDay(hour: 16, minute: 30),
            ],
            reason:
                'exactly the CONFIRMED 16:00–17:00 Kyiv booking paints booked; '
                'the CANCELLED 10:00 row must not',
          );

          final AppLocalizations l10n = AppLocalizations.of(
            tester.element(find.byType(MasterScheduleScreen)),
          );
          // The chip's a11y label conveys the state without colour. The selected
          // day panel merges its descendants into ONE semantics node, so each
          // chip label is one LINE of that node's label — matched as a whole
          // line, never as a substring of a neighbouring cell's.
          expect(
            find.bySemanticsLabel(
              _labelLine(
                l10n,
                const SlotCell(
                  time: TimeOfDay(hour: 16, minute: 0),
                  state: SlotState.booked,
                ),
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(
              _labelLine(
                l10n,
                const SlotCell(
                  time: TimeOfDay(hour: 10, minute: 0),
                  state: SlotState.available,
                ),
              ),
            ),
            findsOneWidget,
            reason: 'the cancelled hour stays free',
          );

          // Legend: three entries, the booked one among them.
          expect(
            find.descendant(
              of: find.byType(SlotLegend),
              matching: find.text(l10n.scheduleSlotBooked),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(SlotLegend),
              matching: find.text(l10n.scheduleSlotWorking),
            ),
            findsOneWidget,
          );
        });
      } finally {
        semantics.dispose();
      }
    },
  );
}

/// [slotCellLabel] as a whole-LINE pattern inside a merged semantics label.
RegExp _labelLine(AppLocalizations l10n, SlotCell cell) =>
    RegExp('^${RegExp.escape(slotCellLabel(l10n, cell))}\$', multiLine: true);
