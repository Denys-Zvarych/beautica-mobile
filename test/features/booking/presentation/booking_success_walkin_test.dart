// Phase 263 — BookingSuccessScreen's walk-in variant.
//
// Covers the phase doc's test cases: the three-way title/subline/CTA-label
// copy switch (reschedule > walk-in > client create), the walk-in-only
// «Готово» destination (`/master/bookings`, pinned by page TYPE per
// `project_gorouter_literal_before_dynamic_shadowing` — never by matching
// the path string), that the client/reschedule destinations are untouched,
// and the negative pins (no review CTA, no visit-level transition CTA on
// ANY variant, back-block active on all three).
//
// Strategy mirrors `booking_confirm_test.dart`'s `BookingSuccessScreen`
// group: a test-local GoRouter rendering the REAL production screen, no
// mocktail. This file additionally registers `RouteNames.masterBookings`
// (which that file's shared `_router()` does not), so the walk-in
// destination test can assert on a REAL resolved page.

import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_success_scaffold.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const Master _kMaster = Master(
  id: 'master-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  reviewCount: 0,
  type: MasterType.independentMaster,
);

const MasterService _kService = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 500,
  priceDisplay: '500 ₴',
  category: 'NAILS',
);

// future-date-ok: fixed fixture; the instant IS the fixture's identity
final DateTime _kStartAt = DateTime.utc(2026, 7, 20, 11);

/// A stub landing screen for `RouteNames.masterBookings` — this file's own
/// router registers it (the shared `_router()` in `booking_confirm_test.dart`
/// does not), so the walk-in «Готово» destination test can assert a REAL
/// resolved page type rather than a bare location string.
class _MasterBookingsStub extends StatelessWidget {
  const _MasterBookingsStub();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('master-bookings-stub')));
}

class _ClientHomeStub extends StatelessWidget {
  const _ClientHomeStub();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('client-home-stub')));
}

GoRouter _router() => GoRouter(
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.bookingSuccess,
      builder: (context, state) =>
          BookingSuccessScreen(args: state.extra! as BookingSuccessArgs),
    ),
    GoRoute(
      path: RouteNames.masterBookings,
      builder: (context, state) => const _MasterBookingsStub(),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (context, state) => const _ClientHomeStub(),
    ),
  ],
);

/// Audit-fix cycle 2 (FIX 1) — the walk-in guest FIX 1 threads onto
/// `BookingSuccessArgs`.
const WalkInGuest _kGuest = WalkInGuest(
  name: 'Ірина',
  surname: 'Шевченко',
  phone: '+380501234567',
);

BookingSuccessArgs _args({
  bool isReschedule = false,
  bool isWalkIn = false,
  WalkInGuest? guest,
}) => BookingSuccessArgs(
  master: _kMaster,
  services: const <MasterService>[_kService],
  startAt: _kStartAt,
  isReschedule: isReschedule,
  isWalkIn: isWalkIn,
  guest: guest,
);

Future<GoRouter> _pump(WidgetTester tester, BookingSuccessArgs args) async {
  final GoRouter router = _router();
  await tester.pumpRoutedApp(router);
  router.go(RouteNames.bookingSuccess, extra: args);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('BookingSuccessScreen — walk-in variant (phase-263)', () {
    testWidgets('should_showClientCopy_when_neitherFlagSet', (tester) async {
      await _pump(tester, _args());

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      expect(find.text(l10n.bookingSuccessTitle), findsOneWidget);
      expect(find.text(l10n.bookingSuccessSubline), findsOneWidget);
      expect(find.text(l10n.bookingSuccessHomeCta), findsOneWidget);
    });

    testWidgets('should_showRescheduleCopy_when_isRescheduleTrue', (
      tester,
    ) async {
      await _pump(tester, _args(isReschedule: true));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      expect(find.text(l10n.bookingRescheduleSuccessTitle), findsOneWidget);
      expect(find.text(l10n.bookingRescheduleSuccessSubline), findsOneWidget);
      // D4 — reschedule keeps the ordinary «На головну» label, unlike walk-in.
      expect(find.text(l10n.bookingSuccessHomeCta), findsOneWidget);
    });

    testWidgets('should_showWalkInSubline_when_isWalkInTrue', (tester) async {
      await _pump(tester, _args(isWalkIn: true));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      // Title is the ORDINARY success title reused — only the subline and
      // CTA change on the walk-in arm (D1).
      expect(find.text(l10n.bookingSuccessTitle), findsOneWidget);
      expect(find.text(l10n.masterCreateBookingDoneSubline), findsOneWidget);
      expect(find.text(l10n.bookingSuccessSubline), findsNothing);
    });

    testWidgets(
      'should_preferRescheduleCopy_when_bothFlagsSet — D1 precedence: '
      'reschedule > walk-in',
      (tester) async {
        await _pump(tester, _args(isReschedule: true, isWalkIn: true));

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingSuccessScreen)),
        );
        expect(find.text(l10n.bookingRescheduleSuccessTitle), findsOneWidget);
        expect(find.text(l10n.bookingRescheduleSuccessSubline), findsOneWidget);
        expect(find.text(l10n.masterCreateBookingDoneSubline), findsNothing);
      },
    );

    testWidgets('should_showGotovoCta_when_isWalkInTrue', (tester) async {
      await _pump(tester, _args(isWalkIn: true));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      expect(find.text(l10n.masterCreateBookingDoneCta), findsOneWidget);
      expect(find.text(l10n.bookingSuccessHomeCta), findsNothing);
    });

    testWidgets(
      'should_goToMasterBookings_when_walkInDoneTapped — page TYPE pin, '
      'not path',
      (tester) async {
        await _pump(tester, _args(isWalkIn: true));

        await tester.tap(find.byKey(const Key('booking-success-home-cta')));
        await tester.pumpAndSettle();

        expect(find.byType(_MasterBookingsStub), findsOneWidget);
        expect(find.byType(BookingSuccessScreen), findsNothing);
      },
    );

    testWidgets('should_goToRoleHome_when_clientDoneTapped — the unchanged pin '
        '(no session resolved → clientHome fallback)', (tester) async {
      await _pump(tester, _args());

      await tester.tap(find.byKey(const Key('booking-success-home-cta')));
      await tester.pumpAndSettle();

      expect(find.byType(_ClientHomeStub), findsOneWidget);
      expect(find.byType(_MasterBookingsStub), findsNothing);
    });

    testWidgets('should_renderNoMasterCardOrAddress_when_isWalkInTrue', (
      tester,
    ) async {
      await _pump(tester, _args(isWalkIn: true));

      // i18n-finder-ok: master name is fixture data (_kMaster).
      expect(find.text('Олена Ковальчук'), findsNothing);
      expect(find.textContaining('вул.'), findsNothing);
    });

    // AUDIT-FIX CYCLE 3 (FIX 2, 2026-08-21) — inverted. Was
    // `should_keepCalendarButton_when_isWalkInTrue`: the walk-in done screen
    // used to keep the SAME «Додати в календар» pill the client path shows.
    // User-reported (2026-08-21): remove it on the walk-in path — the master
    // is standing with the client right there, "add to MY calendar" doesn't
    // apply the way it does for a client booking their own future visit.
    // Gated on `isWalkIn` ONLY (never touches `booking_success_calendar_test
    // .dart`'s CLIENT-path assertions, which never set `isWalkIn: true`).
    testWidgets('should_hideCalendarButton_when_isWalkInTrue', (tester) async {
      await _pump(tester, _args(isWalkIn: true));

      expect(find.byType(CalendarButton), findsNothing);
      expect(
        find.byKey(const Key('booking-success-add-calendar')),
        findsNothing,
      );
    });

    testWidgets(
      'should_keepCalendarButton_when_isWalkInFalse — the CLIENT/reschedule '
      'paths are completely unaffected by FIX 2',
      (tester) async {
        for (final BookingSuccessArgs args in <BookingSuccessArgs>[
          _args(),
          _args(isReschedule: true),
        ]) {
          await _pump(tester, args);

          expect(find.byType(CalendarButton), findsOneWidget);
          expect(
            find.byKey(const Key('booking-success-add-calendar')),
            findsOneWidget,
          );
        }
      },
    );

    // «Додати в календар» removal on WALK-IN RESCHEDULE (2026-08-21) —
    // `reschedule_navigation.dart` now seeds `rescheduleTargetIsWalkIn` from
    // `Booking.isGuestBooking`, and `BookingConfirmScreen._submit` folds it
    // into this screen's existing `isWalkIn` gate. A walk-in reschedule seed
    // therefore reaches THIS screen with BOTH `isReschedule: true` AND
    // `isWalkIn: true` — this is the shape that flag combination now takes.
    testWidgets('should_hideCalendarButton_when_walkInReschedule — a master '
        'rescheduling an existing WALK-IN booking hides the calendar button '
        'too, via the SAME isWalkIn gate as walk-in CREATE', (tester) async {
      await _pump(tester, _args(isReschedule: true, isWalkIn: true));

      expect(find.byType(CalendarButton), findsNothing);
      expect(
        find.byKey(const Key('booking-success-add-calendar')),
        findsNothing,
      );
    });

    // THE REGRESSION GUARD FOR THE LOCKED CLIENT PATH — matters more than
    // the new assertion above. A CLIENT rescheduling their own booking (or a
    // provider rescheduling a real client's booking) reaches this screen with
    // `isReschedule: true, isWalkIn: false` — `rescheduleTargetIsWalkIn` only
    // ever becomes `true` for a booking with no registered client
    // (`booking.isGuestBooking`), so a real client's reschedule is COMPLETELY
    // UNAFFECTED by this fix.
    testWidgets(
      'REGRESSION GUARD — should_keepCalendarButton_when_clientReschedule — '
      'a CLIENT (or provider-on-behalf-of-a-client) reschedule STILL SHOWS '
      'the calendar button; only the walk-in-target case above is hidden',
      (tester) async {
        await _pump(tester, _args(isReschedule: true));

        expect(find.byType(CalendarButton), findsOneWidget);
        expect(
          find.byKey(const Key('booking-success-add-calendar')),
          findsOneWidget,
        );
      },
    );

    // The doneLabel/onPressed switches were widened alongside `isWalkIn`
    // (see `booking_success_screen.dart`'s "«Додати в календар» removal"
    // comments) so this new co-occurring flag combination does not ALSO
    // change the CTA label or destination — only the calendar button changes.
    testWidgets(
      'should_keepRescheduleCtaAndDestination_when_walkInReschedule — the '
      'CTA label and «На головну» destination are UNCHANGED for a walk-in '
      'reschedule; only the calendar button is affected',
      (tester) async {
        await _pump(tester, _args(isReschedule: true, isWalkIn: true));

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingSuccessScreen)),
        );
        expect(find.text(l10n.bookingSuccessHomeCta), findsOneWidget);
        expect(find.text(l10n.masterCreateBookingDoneCta), findsNothing);

        await tester.tap(find.byKey(const Key('booking-success-home-cta')));
        await tester.pumpAndSettle();

        // No session resolved in this bare fixture → falls to the
        // `roleHomePath`/`clientHome` branch, NOT `RouteNames.masterBookings`
        // — same as the ordinary (non-walk-in) reschedule destination.
        expect(find.byType(_ClientHomeStub), findsOneWidget);
        expect(find.byType(_MasterBookingsStub), findsNothing);
      },
    );

    testWidgets('should_offerNoReviewCta_when_isWalkInTrue — no leave-review / '
        'rate-client entry point on ANY variant', (tester) async {
      for (final BookingSuccessArgs args in <BookingSuccessArgs>[
        _args(),
        _args(isReschedule: true),
        _args(isWalkIn: true),
      ]) {
        await _pump(tester, args);

        expect(
          find.byKey(const Key('booking-detail-leave-client-feedback')),
          findsNothing,
        );
        // The screen offers exactly ONE secondary action (the pinned
        // done/home CTA) — a review affordance would be a second one.
        expect(find.byType(SuccessSecondaryButton), findsOneWidget);
      }
    });

    testWidgets('should_offerNoVisitLevelTransitionCta_when_isWalkInTrue — no '
        'complete / decline / cancel affordance on ANY variant', (
      tester,
    ) async {
      for (final BookingSuccessArgs args in <BookingSuccessArgs>[
        _args(),
        _args(isReschedule: true),
        _args(isWalkIn: true),
      ]) {
        await _pump(tester, args);

        for (final String key in <String>[
          'booking-detail-complete',
          'booking-detail-decline',
          'booking-detail-cancel',
          'booking-detail-reschedule',
          'booking-detail-provider-reschedule',
        ]) {
          expect(find.byKey(Key(key)), findsNothing);
        }
      }
    });

    testWidgets(
      'should_blockBack_when_isWalkInTrue — PopScope still prevents pop, '
      'on all three variants',
      (tester) async {
        for (final BookingSuccessArgs args in <BookingSuccessArgs>[
          _args(),
          _args(isReschedule: true),
          _args(isWalkIn: true),
        ]) {
          await _pump(tester, args);

          final PopScope popScope = tester.widget<PopScope>(
            find.byType(PopScope),
          );
          expect(popScope.canPop, isFalse);
        }
      },
    );

    // Audit-fix cycle 2 (FIX 1, 2026-08-21) — the restored guest-identity
    // card. REUSE-FIRST: the card is the shipped `LabelledRow` +
    // `masterCreateBookingGuestLabel` (no new widget, no new ARB key) —
    // these tests pin its presence/absence, not a bespoke rendering.
    testWidgets('should_showGuestCard_when_isWalkInTrueAndGuestPresent', (
      tester,
    ) async {
      await _pump(tester, _args(isWalkIn: true, guest: _kGuest));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      expect(
        find.byKey(const Key('booking-success-guest-card')),
        findsOneWidget,
      );
      expect(find.text(l10n.masterCreateBookingGuestLabel), findsOneWidget);
      // i18n-finder-ok: guest name/phone are fixture data (_kGuest), not
      // localized copy.
      expect(find.text('Ірина Шевченко'), findsOneWidget);
      expect(find.text('+380501234567'), findsOneWidget);
    });

    testWidgets('should_hideGuestCard_when_isWalkInFalse — the CLIENT path is '
        'completely unaffected', (tester) async {
      await _pump(tester, _args());

      expect(find.byKey(const Key('booking-success-guest-card')), findsNothing);
    });

    testWidgets(
      'should_hideGuestCard_when_rescheduleTrue — reschedule never carries a '
      'guest',
      (tester) async {
        await _pump(tester, _args(isReschedule: true));

        expect(
          find.byKey(const Key('booking-success-guest-card')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'should_hideGuestCard_when_isWalkInTrueButGuestNull — gates on BOTH '
      'isWalkIn AND guest, never isWalkIn alone',
      (tester) async {
        await _pump(tester, _args(isWalkIn: true));

        expect(
          find.byKey(const Key('booking-success-guest-card')),
          findsNothing,
        );
      },
    );
  });
}
