// Track 14.x (booking auto-confirm + My Bookings + Booking Detail + Cancel) —
// E2E: the CLIENT «МОЇ ЗАПИСИ» → «Деталі запису» → «Скасувати запис» journey.
//
// WHY THIS FILE EXISTS (Step 2.7 Rule 3b — integration-test gate)
// --------------------------------------------------------------
// The widget/unit tier proves each surface in isolation: my_bookings_screen_test
// (tab partition, CANCELLED-vs-DECLINED copy), booking_detail_screen_test (the
// per-status state machine + cancel wiring), my_bookings_notifier_test
// (merge/pagination), booking_display_x_test (money/actor derivation). NONE of
// them proves the REAL journey wired together against a mutating backend:
//
//   1. CLIENT logs in and opens the Записи branch.
//   2. A booking created CONFIRMED (auto-confirm — no provider approval step)
//      is visible IMMEDIATELY in Майбутні («Підтверджено»).
//   3. Opening it lands on «Деталі запису» with the «Скасувати запис» action.
//   4. Cancelling WITH a note calls PATCH /bookings/{id}/cancel carrying that
//      note, and the booking transitions to CANCELLED.
//   5. The detail re-renders as a CLIENT cancellation — «Ви скасували», never
//      the provider-agency «Салон/Майстер скасував».
//   6. Back on the list the booking has left Майбутні and appears under
//      Скасовані.
//
// The FakeBackend seeds ONE booking (`booking-1`, CONFIRMED) and mutates it to
// CANCELLED on the cancel PATCH, so the list/detail re-fetch reflects the move.
//
// KEY POLICY (AppHarness): all TAPS are key-based; Ukrainian text appears in
// CONTENT ASSERTIONS only, and status copy is asserted through l10n.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_tab_bar.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

// The add_2_calendar plugin's platform boundary. On a real device this would
// open the OS calendar sheet — a native OS-sheet interaction is NOT patrol-
// testable headlessly, so this flow mocks it at the CHANNEL boundary and
// asserts the handler fired with the booking's data. (An actual on-device
// calendar-sheet render is intentionally out of scope, NOT a skipped case.)
const MethodChannel _kCalendarChannel = MethodChannel('add_2_calendar');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(installOverflowGuard);
  tearDown(AppHarness.tearDownHarness);

  AppLocalizations l10nOf(WidgetTester tester, Type screen) =>
      AppLocalizations.of(tester.element(find.byType(screen)));

  testWidgets(
    'CLIENT opens My Bookings, cancels a CONFIRMED booking with a note, and it '
    'moves to Скасовані as «Скасовано»',
    (tester) async {
      final fb = FakeBackend()..currentRole = UserRole.client;
      final GoRouter router = await AppHarness.boot(tester, fb);

      // Cold start → /login.
      expect(find.byKey(const ValueKey<String>('login_email')), findsOneWidget);

      await AppHarness.loginAs(tester, fb, UserRole.client);

      // ── 1. Open the Записи branch (bottom-nav tile 3). ────────────────────
      await tester.tap(find.byKey(const Key('client-nav-tile-3')));
      await AppHarness.settle(tester);
      // Branch SWITCH (not a push) — the shell's own match list moves, so the
      // router location is genuinely readable here. Goes through
      // `AppHarness.expectLocation` rather than a local reader so the
      // ImperativeRouteMatch unwrapping stays in one place
      // (`scripts/forbid_naive_router_location.sh` gates the naive form).
      AppHarness.expectLocation(router, RouteNames.clientBookings);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      // ── 2. Auto-confirm: the booking is visible immediately in Майбутні. ──
      expect(
        find.byType(BookingCard),
        findsOneWidget,
        reason:
            'a CONFIRMED booking must show in Майбутні immediately — there is '
            'no PENDING approval step (auto-confirm)',
      );
      expect(
        find.byKey(const ValueKey<String>('service-booking-1')),
        findsOneWidget,
      );
      final AppLocalizations listL10n = l10nOf(tester, MyBookingsScreen);
      expect(
        find.text(listL10n.bookingStatusConfirmed),
        findsOneWidget,
        reason: 'the card must carry the «Підтверджено» status badge',
      );

      // Feature B — on the Записи LIST the CLIENT bottom nav is present (both
      // chrome bars mounted by the shell).
      expect(
        find.byType(ClientBottomNav),
        findsOneWidget,
        reason: 'the bottom nav must be present on the /bookings list',
      );
      expect(find.byType(ClientTopBar), findsOneWidget);

      // ── 3. Open «Деталі запису». ──────────────────────────────────────────
      await tester.tap(find.byType(BookingCard));
      await AppHarness.settle(tester);
      // NAVIGATION IS ASSERTED BY SCREEN, NOT BY ROUTE STRING — deliberately,
      // and this used to be the opposite. «Деталі запису» is pushed with
      // `context.push` from INSIDE the client `StatefulShellRoute` branch, so
      // the push lands on that branch's own nested Navigator: go_router
      // excludes `ImperativeRouteMatch` entries from `RouteMatchList.uri` /
      // `.fullPath`, and `currentConfiguration.matches` still holds exactly one
      // top-level entry — the branch root «/bookings». The assertion that stood
      // here (`…currentConfiguration.uri` startsWith «/bookings/booking-1»)
      // therefore CANNOT hold while the detail screen is genuinely mounted; it
      // was measured reporting «/bookings». `AppHarness.location` does not
      // rescue it either — that helper unwraps a TOP-LEVEL
      // ImperativeRouteMatch, and there is none here.
      //
      // The mounted screen is the fact this step actually needs, so assert it
      // directly (same treatment, same reason, as
      // `booking_price_band_flow_test.dart`). The route STRING for this push is
      // owned by the widget tier, which can observe the pushed leaf via
      // `leaf.matches.fullPath`.
      expect(find.byType(BookingDetailScreen), findsOneWidget);

      // Feature B — the bottom nav is SUPPRESSED on the booking-detail route
      // (/bookings/:bookingId) so it reads as a focused, full-height surface;
      // the top bar is intentionally KEPT.
      expect(
        find.byType(ClientBottomNav),
        findsNothing,
        reason:
            'the bottom nav must be hidden on the booking-detail page '
            '(/bookings/:bookingId)',
      );
      expect(
        find.byType(ClientTopBar),
        findsOneWidget,
        reason: 'the top bar stays on the booking-detail page',
      );
      expect(
        find.byKey(const Key('booking-detail-cancel')),
        findsOneWidget,
        reason: 'a CONFIRMED booking must offer «Скасувати запис»',
      );

      // ── 3b. Add-to-calendar wires the CONFIRMED booking to the OS sheet. ──
      // Intercept the plugin so no real OS calendar opens, then tap the HEADER
      // calendar icon (change #4 relocated it out of the scroll-body pill) and
      // assert the platform INSERT fired with THIS booking's service·master
      // title, venue location and instants — that the STRUCTURED description is
      // populated (change #3) and that no free-text note / PII leaked into it.
      final List<MethodCall> calendarCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kCalendarChannel, (MethodCall call) async {
            calendarCalls.add(call);
            return true; // pretend a calendar app opened
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_kCalendarChannel, null),
      );

      final Finder calendarButton = find.byKey(
        const Key('booking-detail-add-calendar'),
      );
      expect(
        calendarButton,
        findsOneWidget,
        reason:
            'a CONFIRMED booking must offer «Додати в календар» as the header '
            'icon',
      );
      await tester.ensureVisible(calendarButton);
      await AppHarness.settle(tester);
      await tester.tap(calendarButton);
      await AppHarness.settle(tester);

      final AppLocalizations calL10n = l10nOf(tester, BookingDetailScreen);
      expect(calendarCalls, hasLength(1), reason: 'add2Cal must have fired');
      expect(calendarCalls.single.method, 'add2Cal');
      final Map<Object?, Object?> calArgs =
          calendarCalls.single.arguments as Map<Object?, Object?>;
      expect(
        calArgs['title'],
        calL10n.bookingCalendarEventTitle(
          'Манікюр з покриттям',
          'Софія Бондар',
        ),
      );
      expect((calArgs['location'] as String?) ?? '', contains('Хрещатик'));
      expect(calArgs['timeZone'], 'Europe/Kyiv');
      // The structured description is now populated (change #3): the service,
      // provider and status facts are present via their l10n label keys…
      final String calDesc = calArgs['desc'] as String;
      expect(calDesc, contains(calL10n.bookingCalendarNoteService));
      expect(calDesc, contains(calL10n.bookingCalendarNoteStatus));
      expect(calDesc, contains('Манікюр з покриттям'));
      expect(calDesc, contains(calL10n.bookingStatusConfirmed));
      // …but the pre-cancel booking carries no free-text note, and none of the
      // note fields can ride into the event regardless (privacy boundary).
      expect(calDesc, isNot(contains('Захворіла')));

      // Firing the calendar sheet must NOT mutate the booking.
      expect(fb.bookingStatus, 'CONFIRMED');

      // Stop intercepting so the rest of the flow is unaffected.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_kCalendarChannel, null);

      // ── 4. Cancel WITH a note. ────────────────────────────────────────────
      await tester.tap(find.byKey(const Key('booking-detail-cancel')));
      await AppHarness.settle(tester);
      expect(find.byKey(const Key('cancel-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Захворіла, вибачте.',
      );
      await AppHarness.settle(tester);
      await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
      await AppHarness.settle(tester);

      // The PATCH fired, carrying the exact note.
      expect(fb.cancelBookingCalls, 1);
      expect(fb.lastCancelComment, 'Захворіла, вибачте.');
      expect(fb.bookingStatus, 'CANCELLED');

      // ── 5. The detail re-rendered as a cancellation. ──────────────────────
      // Client-cancelled and provider-declined now share the single neutral
      // «Скасовано» label (locked product decision), so there is no longer a
      // distinct provider-decline string to assert the absence of.
      final AppLocalizations detailL10n = l10nOf(tester, BookingDetailScreen);
      expect(
        find.text(detailL10n.bookingStatusCancelled),
        findsWidgets,
        reason: 'the detail must now say «Скасовано»',
      );

      // ── 6. Back on the list: it has left Майбутні, and shows in Скасовані. ─
      await tester.tap(find.byKey(const Key('booking-detail-back')));
      await AppHarness.settle(tester);
      expect(find.byType(MyBookingsScreen), findsOneWidget);

      // Feature B — back on the list the bottom nav is restored (the off → on
      // toggle is driven by the shell's location listener as the detail pops).
      expect(
        find.byType(ClientBottomNav),
        findsOneWidget,
        reason:
            'the bottom nav must return once the detail is popped and the '
            '/bookings list is shown again',
      );

      // Майбутні (the tab we return to) is now empty.
      expect(
        find.byType(BookingCard),
        findsNothing,
        reason: 'the cancelled booking must have left Майбутні',
      );

      // Switch to Скасовані.
      final AppLocalizations tabsL10n = l10nOf(tester, MyBookingsScreen);
      await tester.tap(
        find.descendant(
          of: find.byType(MyBookingsTabBar),
          matching: find.text(tabsL10n.myBookingsTabCancelled),
        ),
      );
      await AppHarness.settle(tester);

      expect(
        find.byKey(const ValueKey<String>('service-booking-1')),
        findsOneWidget,
        reason: 'the cancelled booking must now appear under Скасовані',
      );
      expect(
        find.text(tabsL10n.bookingStatusCancelled),
        findsOneWidget,
        reason: 'and it must be labelled «Скасовано»',
      );
    },
  );
}
