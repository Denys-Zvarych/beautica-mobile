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

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart'
    show debugMediaCacheManager;
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/booking_success_args.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip_shell.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import 'package:beautica_mobile/features/booking/presentation/booking_success_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_wizard_steps.dart'
    show walkInGuestFrom;
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/success_secondary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fake_media_cache.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/rendered_image_url.dart';

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

/// Phase 383 — the owner master-mode «Записи» landing stub.
class _OwnerMasterBookingsStub extends StatelessWidget {
  const _OwnerMasterBookingsStub();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('owner-master-bookings-stub')));
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
    GoRoute(
      path: RouteNames.ownerMasterBookings,
      builder: (context, state) => const _OwnerMasterBookingsStub(),
    ),
    // M569 — the client-card stub the strips push (user + guest paths).
    GoRoute(
      path: '${RouteNames.masterClients}/:kind/:id',
      builder: (context, state) =>
          Scaffold(body: Text('card-stub:${state.uri}')),
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
  // mobile-qa (client-identity parity, 2026-08-22) — RESCHEDULE-only
  // counterpart of [guest]. Defaults to `null` so every PRE-EXISTING call
  // site above is unaffected.
  String? rescheduleClientName,
  String? rescheduleClientPhone,
  String? returnRoute,
}) => BookingSuccessArgs(
  master: _kMaster,
  services: const <MasterService>[_kService],
  startAt: _kStartAt,
  isReschedule: isReschedule,
  isWalkIn: isWalkIn,
  guest: guest,
  rescheduleClientName: rescheduleClientName,
  rescheduleClientPhone: rescheduleClientPhone,
  returnRoute: returnRoute,
);

Future<GoRouter> _pump(
  WidgetTester tester,
  BookingSuccessArgs args, {
  List<Object> overrides = const <Object>[],
}) async {
  final GoRouter router = _router();
  await tester.pumpRoutedApp(router, overrides: overrides);
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
      // Copy regression (fix/booking-success-copy): auto-approved booking —
      // never "the master will confirm". i18n-finder-ok: retired-copy probe.
      expect(find.textContaining('підтвердить'), findsNothing);
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

    // Phase 383 QA (INFO security) — FAILING-FIRST spec. `returnRoute` is an
    // unconstrained String handed straight to `context.go`; only the two
    // walk-in landings may ever be honoured. Any other value must fall back
    // to the independent master's «Записи». Observed RED before the fix
    // (landed on the client home stub).
    testWidgets(
      'should_ignoreReturnRoute_when_notOnAllowList — an arbitrary route '
      'falls back to /master/bookings',
      (tester) async {
        await _pump(
          tester,
          _args(isWalkIn: true, returnRoute: RouteNames.clientHome),
        );

        await tester.tap(find.byKey(const Key('booking-success-home-cta')));
        await tester.pumpAndSettle();

        expect(find.byType(_ClientHomeStub), findsNothing);
        expect(find.byType(_MasterBookingsStub), findsOneWidget);
      },
    );

    // Phase 383 QA — `returnRoute` is read ONLY on the walk-in branch; a
    // client success that somehow carried one still lands on the role home.
    // MUTATION: hoisted `returnRoute ??` above the `isWalkIn` guard → this
    // test landed on the owner stub and went red. Restored.
    testWidgets(
      'should_ignoreReturnRoute_when_notWalkIn — the client branch never '
      'reads it',
      (tester) async {
        await _pump(tester, _args(returnRoute: RouteNames.ownerMasterBookings));

        await tester.tap(find.byKey(const Key('booking-success-home-cta')));
        await tester.pumpAndSettle();

        expect(find.byType(_OwnerMasterBookingsStub), findsNothing);
        expect(find.byType(_ClientHomeStub), findsOneWidget);
      },
    );

    // Phase 383 (24.1f) — the owner master-mode walk-in chain sets
    // `returnRoute`; `go(masterBookings)` would bounce a SALON_OWNER.
    testWidgets(
      'should_goToReturnRoute_when_walkInDoneTappedWithReturnRoute — the '
      'owner chain lands on /owner/master/bookings, never /master/bookings',
      (tester) async {
        await _pump(
          tester,
          _args(isWalkIn: true, returnRoute: RouteNames.ownerMasterBookings),
        );

        await tester.tap(find.byKey(const Key('booking-success-home-cta')));
        await tester.pumpAndSettle();

        expect(find.byType(_OwnerMasterBookingsStub), findsOneWidget);
        expect(find.byType(_MasterBookingsStub), findsNothing);
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

    // mobile-qa (client-identity parity, 2026-08-22) — the RESCHEDULE-path
    // counterpart of the guest-identity-card group above. REUSE-FIRST: same
    // client card (`BookingClientStrip`, 2026-11-14), same
    // key-naming convention (`booking-success-client-card` mirrors
    // `booking-success-guest-card`), gated the same way (present only when
    // its own arg is non-null). Both groups are independent `if`s on the
    // production screen (not else-if — see `booking_success_screen.dart`),
    // so they are tested independently too; a walk-in card and a client
    // card never legitimately co-occur in practice (a guest booking never
    // carries a registered client name), but nothing in the widget itself
    // enforces that — it is `reschedule_navigation.dart`'s job, covered by
    // `reschedule_navigation_test.dart`'s own `rescheduleClientName` group.
    group('client identity card (client-identity parity, 2026-08-22)', () {
      testWidgets('should_showClientCard_when_rescheduleClientNamePresent — a '
          'PROVIDER-initiated reschedule of a real client\'s booking echoes '
          'the client name on the done screen', (tester) async {
        await _pump(
          tester,
          _args(isReschedule: true, rescheduleClientName: 'Олена Ковальчук'),
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BookingSuccessScreen)),
        );
        expect(
          find.byKey(const Key('booking-success-client-card')),
          findsOneWidget,
        );
        expect(find.text(l10n.bookingClientLabel), findsOneWidget);
        // i18n-finder-ok: client name is fixture data, not localized copy.
        expect(find.text('Олена Ковальчук'), findsOneWidget);
      });

      testWidgets('should_showClientAvatarAndRating_when_providerReschedule — '
          'the done screen renders the SAME BookingClientStrip «Деталі запису» '
          'uses: monogram avatar fallback + ★ rating readout', (tester) async {
        await _pump(
          tester,
          _args(
            isReschedule: true,
            rescheduleClientName: 'Олена Ковальчук',
          ).copyWith(
            rescheduleClientInitials: 'ОК',
            rescheduleClientRating: 4.6,
            rescheduleClientReviewCount: 7,
          ),
        );

        final Finder card = find.byKey(
          const Key('booking-success-client-card'),
        );
        expect(card, findsOneWidget);
        expect(tester.widget(card), isA<BookingClientStrip>());
        expect(
          // i18n-finder-ok: fixture initials, locale-invariant data.
          find.descendant(of: card, matching: find.text('ОК')),
          findsOneWidget,
        );
        final Finder readout = find.descendant(
          of: card,
          matching: find.byType(MasterRatingReadout),
        );
        expect(readout, findsOneWidget);
        expect(
          find.descendant(of: readout, matching: find.text('4.6')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: readout, matching: find.text('(7)')),
          findsOneWidget,
        );
      });

      testWidgets(
        'should_notShowClientPhone_when_rescheduleClientPhonePresent',
        (tester) async {
          await _pump(
            tester,
            _args(
              isReschedule: true,
              rescheduleClientName: 'Олена Ковальчук',
              rescheduleClientPhone: '+380671112233',
            ),
          );

          // i18n-finder-ok: phone is fixture data, not localized copy.
          expect(
            find.text('+380671112233'),
            findsNothing,
            reason:
                'the reschedule client card carries no phone line (security '
                'LOW, 2026-11-14) — production never seeds one either',
          );
        },
      );

      testWidgets(
        'should_hideClientCard_when_rescheduleClientNameNull — the ordinary '
        'client-create path is completely unaffected',
        (tester) async {
          await _pump(tester, _args());

          expect(
            find.byKey(const Key('booking-success-client-card')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'should_hideClientCard_when_plainReschedule — a CLIENT rescheduling '
        'their own booking (rescheduleClientName stays null all the way '
        'through — see reschedule_navigation_test.dart) never renders the '
        'client card either',
        (tester) async {
          await _pump(tester, _args(isReschedule: true));

          expect(
            find.byKey(const Key('booking-success-client-card')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'should_showBothCards_never — walk-in guest card and reschedule '
        'client card are independent `if`s; probing the (never-produced-in-'
        'practice) combination proves neither gates on the other',
        (tester) async {
          await _pump(
            tester,
            _args(
              isWalkIn: true,
              guest: _kGuest,
              rescheduleClientName: 'Олена Ковальчук',
            ),
          );

          expect(
            find.byKey(const Key('booking-success-guest-card')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('booking-success-client-card')),
            findsOneWidget,
          );
        },
      );
    });
  });

  // 2026-11-25 (BOOK-79/80) — the done screen's walk-in card is the shared
  // `BookingClientStrip.walkIn`: a picked client's photo + ★, and the
  // monogram + «—» once the typed identity diverged from the pick
  // (`walkInGuestFrom`, the same composition the guest step routes on).
  group('walk-in client strip — picked vs typed (2026-11-25)', () {
    const ClientPrefill picked = ClientPrefill(
      firstName: _kPickedFirst,
      lastName: _kPickedLast,
      phone: _kPickedPhone,
      avatarUrl: _kPickedAvatar,
      rating: _kPickedRating,
      ratingCount: _kPickedRatingCount,
    );
    final Finder card = find.byKey(const Key('booking-success-guest-card'));
    Finder inReadout(String text) => find.descendant(
      of: find.descendant(of: card, matching: find.byType(MasterRatingReadout)),
      matching: find.text(text),
    );

    setUp(() {
      MediaConfig.debugAllowedHosts = <String>{'media.test'};
      debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
    });
    tearDown(() {
      debugMediaCacheManager = null;
      MediaConfig.debugAllowedHosts = null;
    });

    testWidgets('a picked client shows its photo and ★ rating', (tester) async {
      final WalkInGuest guest = walkInGuestFrom(
        firstName: _kPickedFirst,
        lastName: _kPickedLast,
        phone: _kPickedPhone,
        picked: picked,
      );
      await _pump(tester, _args(isWalkIn: true, guest: guest));

      expect(tester.widget(card), isA<BookingClientStrip>());
      expect(renderedImageUrls(tester, within: card), <String>[_kPickedAvatar]);
      expect(inReadout(_kPickedRating.toStringAsFixed(1)), findsOneWidget);
      expect(inReadout('($_kPickedRatingCount)'), findsOneWidget);
    });

    testWidgets('a typed name that diverged from the pick shows initials and '
        '«—», no photo', (tester) async {
      final WalkInGuest guest = walkInGuestFrom(
        firstName: _kTypedFirst,
        lastName: _kPickedLast,
        phone: _kPickedPhone,
        picked: picked,
      );
      await _pump(tester, _args(isWalkIn: true, guest: guest));

      expect(card, findsOneWidget);
      expect(renderedImageUrls(tester, within: card), isEmpty);
      expect(
        find.descendant(of: card, matching: find.text(_kTypedInitials)),
        findsOneWidget,
      );
      expect(inReadout(MasterStrip.noRatingLabel), findsOneWidget);
      expect(inReadout(_kPickedRating.toStringAsFixed(1)), findsNothing);
    });

    // M569 (CLI-D20) — the card handle the review / confirm strips tap into
    // rides the SAME «still the picked client» gate as the photo + ★: an
    // edited name or phone has no card yet, so the strip must go inert.
    test('clientRef survives only while name, surname and phone are '
        'unchanged', () {
      const ClientPrefill withRef = ClientPrefill(
        firstName: _kPickedFirst,
        lastName: _kPickedLast,
        phone: _kPickedPhone,
        ref: ClientRef.registered('u-oksana'),
      );
      ClientRef? refOf({
        String first = _kPickedFirst,
        String phone = _kPickedPhone,
      }) => walkInGuestFrom(
        firstName: first,
        lastName: _kPickedLast,
        phone: phone,
        picked: withRef,
      ).clientRef;

      expect(refOf(), const ClientRef.registered('u-oksana'));
      expect(refOf(first: _kTypedFirst), isNull, reason: 'edited name');
      expect(refOf(phone: '+380671234568'), isNull, reason: 'edited phone');
    });
  });
  // M569 (CLI-101 / CLI-D20) — the done screen's client strips: ★ for a
  // walk-in reschedule target, and the tap into the client card.
  group('M569 done-screen client strip', () {
    Booking createdBooking({String? clientId}) {
      final DateTime start = DateTime.utc(2020, 7, 14, 12);
      return Booking(
        id: 'b-new',
        masterId: _kMaster.id,
        masterFirstName: _kMaster.firstName,
        masterLastName: _kMaster.lastName,
        masterType: 'INDEPENDENT_MASTER',
        clientId: clientId,
        clientFirstName: _kGuest.name,
        clientLastName: _kGuest.surname,
        serviceId: _kService.id,
        serviceName: _kService.name,
        durationMinutes: 60,
        price: 500,
        startAt: start,
        endAt: start.add(const Duration(minutes: 60)),
        status: BookingStatus.confirmed,
        canReview: false,
      );
    }

    String cardText(ClientRef ref) =>
        'card-stub:${switch (ref) {
          RegisteredClientRef(:final String userId) => RouteNames.clientCardUser(RouteNames.masterClients, userId),
          GuestClientRef(:final String bookingId) => RouteNames.clientCardGuest(RouteNames.masterClients, bookingId),
        }}';

    testWidgets('reschedule done for a walk-in shows its ★ (CLI-101)', (
      tester,
    ) async {
      await _pump(
        tester,
        _args(
          isReschedule: true,
          isWalkIn: true,
          rescheduleClientName: 'Марта Дяченко',
        ).copyWith(rescheduleClientRating: 4.6, rescheduleClientReviewCount: 2),
      );
      final Finder strip = find.byKey(
        const Key('booking-success-client-strip'),
      );
      expect(find.descendant(of: strip, matching: find.text('4.6')), findsOne);
    });

    testWidgets('reschedule done: tap pushes the card, back returns here', (
      tester,
    ) async {
      final GoRouter router = await _pump(
        tester,
        _args(
          isReschedule: true,
          rescheduleClientName: 'Марта Дяченко',
        ).copyWith(
          clientCardBase: RouteNames.masterClients,
          clientCardRef: const ClientRef.registered('c-42'),
        ),
      );
      await tester.tap(find.byKey(const Key('booking-success-client-strip')));
      await tester.pumpAndSettle();
      expect(
        find.text(cardText(const ClientRef.registered('c-42'))),
        findsOneWidget,
      );
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
    });

    testWidgets('walk-in done: a picked client opens their own card', (
      tester,
    ) async {
      await _pump(
        tester,
        _args(
          isWalkIn: true,
          guest: _kGuest.copyWith(clientRef: const ClientRef.guest('b-old')),
        ).copyWith(
          clientCardBase: RouteNames.masterClients,
          createdBookingId: 'b-new',
        ),
      );
      await tester.tap(find.byKey(const Key('booking-success-guest-strip')));
      await tester.pumpAndSettle();
      expect(
        find.text(cardText(const ClientRef.guest('b-old'))),
        findsOneWidget,
      );
    });

    testWidgets('walk-in done: a hand-typed phone attached to an account '
        '(CLI-62) opens the USER card, read from the created booking only on '
        'tap (owner 2026-11-28)', (tester) async {
      int reads = 0;
      await _pump(
        tester,
        _args(isWalkIn: true, guest: _kGuest).copyWith(
          clientCardBase: RouteNames.masterClients,
          createdBookingId: 'b-new',
        ),
        overrides: <Object>[
          bookingDetailProvider('b-new').overrideWith((ref) async {
            reads++;
            return createdBooking(clientId: 'u-7');
          }),
        ],
      );
      expect(reads, 0, reason: 'no GET /bookings/{id} on mount');
      await tester.tap(find.byKey(const Key('booking-success-guest-strip')));
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(
        find.text(cardText(const ClientRef.registered('u-7'))),
        findsOneWidget,
      );
    });

    testWidgets('walk-in done: a double tap reads the booking once and opens '
        'one card', (tester) async {
      int reads = 0;
      final Completer<Booking> pending = Completer<Booking>();
      await _pump(
        tester,
        _args(isWalkIn: true, guest: _kGuest).copyWith(
          clientCardBase: RouteNames.masterClients,
          createdBookingId: 'b-new',
        ),
        overrides: <Object>[
          bookingDetailProvider('b-new').overrideWith((ref) {
            reads++;
            return pending.future;
          }),
        ],
      );
      final Finder strip = find.byKey(const Key('booking-success-guest-strip'));
      await tester.tap(strip);
      await tester.pump();
      expect(
        tester.widget<MasterStripShell>(strip).onTap,
        isNull,
        reason: 'busy while the booking is read',
      );
      await tester.tap(strip, warnIfMissed: false);
      pending.complete(createdBooking());
      await tester.pumpAndSettle();
      expect(reads, 1);
      expect(
        find.text(cardText(const ClientRef.guest('b-new'))),
        findsOneWidget,
      );
    });

    // mobile-perf (M569) — `ref.read(bookingDetailProvider(id).future)` is a
    // one-off read of an autoDispose family with no listener: the card must
    // still open when the GET spans many frames (a slow network), not only
    // when it resolves within the frame of the tap.
    testWidgets('walk-in done: a slow read (many frames) still opens the card '
        'exactly once', (tester) async {
      int reads = 0;
      final Completer<Booking> pending = Completer<Booking>();
      await _pump(
        tester,
        _args(isWalkIn: true, guest: _kGuest).copyWith(
          clientCardBase: RouteNames.masterClients,
          createdBookingId: 'b-new',
        ),
        overrides: <Object>[
          bookingDetailProvider('b-new').overrideWith((ref) {
            reads++;
            return pending.future;
          }),
        ],
      );
      await tester.tap(find.byKey(const Key('booking-success-guest-strip')));
      for (int i = 0; i < 10; i++) {
        // fixed-wait-ok: deliberately spans many frames while the GET is
        // pending — the point is that the read outlives an autoDispose pass.
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      pending.complete(createdBooking(clientId: 'u-9'));
      await tester.pumpAndSettle();
      expect(reads, 1, reason: 'one GET, no re-read after an autoDispose');
      expect(
        find.text(cardText(const ClientRef.registered('u-9'))),
        findsOneWidget,
      );
    });

    testWidgets('walk-in done: a failed read shows the error snack and stays '
        'on the done screen', (tester) async {
      await _pump(
        tester,
        _args(isWalkIn: true, guest: _kGuest).copyWith(
          clientCardBase: RouteNames.masterClients,
          createdBookingId: 'b-new',
        ),
        overrides: <Object>[
          bookingDetailProvider(
            'b-new',
          ).overrideWith((ref) async => throw const NotFoundFailure()),
        ],
      );
      await tester.tap(find.byKey(const Key('booking-success-guest-strip')));
      await tester.pumpAndSettle();
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(BookingSuccessScreen)),
      );
      expect(find.text(l10n.errNotFound), findsOneWidget);
      expect(find.byType(BookingSuccessScreen), findsOneWidget);
      expect(
        tester
            .widget<MasterStripShell>(
              find.byKey(const Key('booking-success-guest-strip')),
            )
            .onTap,
        isNotNull,
        reason: 'tappable again after the failure',
      );
      // Wait until the snack has dismissed itself (its dwell timer fired),
      // so no timer is pending at teardown.
      await tester.pumpUntilGone(find.text(l10n.errNotFound));
      await tester.pumpAndSettle();
    });

    testWidgets('walk-in done: an unattached hand-typed guest opens the guest '
        'card anchored on the created booking', (tester) async {
      await _pump(
        tester,
        _args(isWalkIn: true, guest: _kGuest).copyWith(
          clientCardBase: RouteNames.masterClients,
          createdBookingId: 'b-new',
        ),
        overrides: <Object>[
          bookingDetailProvider(
            'b-new',
          ).overrideWith((ref) async => createdBooking()),
        ],
      );
      await tester.tap(find.byKey(const Key('booking-success-guest-strip')));
      await tester.pumpAndSettle();
      expect(
        find.text(cardText(const ClientRef.guest('b-new'))),
        findsOneWidget,
      );
    });

    testWidgets('no card base → the strip stays inert', (tester) async {
      await _pump(tester, _args(isWalkIn: true, guest: _kGuest));
      expect(
        tester
            .widget<MasterStripShell>(
              find.byKey(const Key('booking-success-guest-strip')),
            )
            .onTap,
        isNull,
      );
    });
  });
}

// Fixture data for the picked-vs-typed group (named, never a literal at a
// finder call site).
const String _kPickedFirst = 'Оксана';
const String _kPickedLast = 'Мельник';
const String _kPickedPhone = '+380671234567';
const String _kPickedAvatar = 'https://media.test/avatars/u-oksana.png';
const double _kPickedRating = 4.5;
const int _kPickedRatingCount = 3;
const String _kTypedFirst = 'Олена';
const String _kTypedInitials = 'ОМ';
