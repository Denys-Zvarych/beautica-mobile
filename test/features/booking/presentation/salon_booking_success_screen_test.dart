// Phase 14.18 — Widget tests for SalonBookingSuccessScreen (salon booking
// flow step 4b: the confirmed N-appointment recap).
//
// Covers:
//   1. Lists exactly ONE SalonAppointmentCard per confirmed appointment
//      (`ValueKey('salon-success-appt-<masterId>')`) + the «Записано!»
//      headline.
//   2. Blocks back navigation (PopScope(canPop: false)).
//   3. The «На головну» CTA navigates to the CLIENT home (asserted via a
//      router sentinel, not Navigator).
//
// Strategy: real screen under a test-local GoRouter that stubs the CLIENT
// home destination — no providers needed (the success screen is a pure
// StatelessWidget-fed recap). Mirrors booking_confirm_test's success group.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_confirm_args.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_booking_success_screen.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/public_salon_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final DateTime _kStart = DateTime(2026, 7, 20, 14);
const String _kSalonId = 'salon-1';

const Salon _kSalon = Salon(
  id: _kSalonId,
  name: 'Салон «Вельвет»',
  street: 'вул. Хрещатик',
  buildingNo: '22',
  city: 'Київ',
);

SalonBookingAppointment _appt(String masterId, String firstName) =>
    SalonBookingAppointment(
      schedule: SalonMasterSchedule(
        masterId: masterId,
        firstName: firstName,
        lastName: 'Ковальчук',
        type: MasterType.independentMaster,
        services: <SalonCatalogService>[
          SalonCatalogService(
            id: 'svc-$masterId',
            name: 'Манікюр',
            durationLabel: '1 год',
            priceDisplay: '500 ₴',
            durationMinutes: 60,
            priceType: ServicePriceType.fixed,
            priceMin: 500,
          ),
        ],
        orderedMasterServiceIds: <String>['assign-$masterId'],
      ),
      startAt: _kStart,
      idempotencyKey: 'key-$masterId',
    );

SalonBookingSuccessArgs _args() => SalonBookingSuccessArgs(
  salonId: _kSalonId,
  appointments: <SalonBookingAppointment>[
    _appt('m1', 'Олена'),
    _appt('m2', 'Софія'),
  ],
);

/// A SINGLE-appointment args fixture — for pinning that the grand-total card
/// is SUPPRESSED at N == 1 (it would just repeat that one card's own
/// subtotal).
SalonBookingSuccessArgs _singleAppointmentArgs() => SalonBookingSuccessArgs(
  salonId: _kSalonId,
  appointments: <SalonBookingAppointment>[_appt('m1', 'Олена')],
);

/// mobile-qa gap fixture: `_appt`'s inline `SalonMasterSchedule` above carries
/// NO rating (avgRating defaults null, reviewCount defaults 0) — never
/// exercised the shared `MasterStrip`'s rating readout on THIS screen. Local
/// to the rating/per-master-recap test below; deliberately kept separate
/// from `_appt` so no existing assertion in this file is touched.
SalonBookingAppointment _ratedAppt(
  String masterId,
  String firstName, {
  required double avgRating,
  required int reviewCount,
}) => SalonBookingAppointment(
  schedule: SalonMasterSchedule(
    masterId: masterId,
    firstName: firstName,
    lastName: 'Ковальчук',
    type: MasterType.independentMaster,
    avgRating: avgRating,
    reviewCount: reviewCount,
    services: <SalonCatalogService>[
      SalonCatalogService(
        id: 'svc-$masterId',
        name: 'Манікюр',
        durationLabel: '1 год',
        priceDisplay: '500 ₴',
        durationMinutes: 60,
        priceType: ServicePriceType.fixed,
        priceMin: 500,
      ),
    ],
    orderedMasterServiceIds: <String>['assign-$masterId'],
  ),
  startAt: _kStart,
  idempotencyKey: 'key-$masterId',
);

SalonBookingSuccessArgs _ratedArgsTwoMasters() => SalonBookingSuccessArgs(
  salonId: _kSalonId,
  appointments: <SalonBookingAppointment>[
    _ratedAppt('m1', 'Олена', avgRating: 4.6, reviewCount: 9),
    _ratedAppt('m2', 'Софія', avgRating: 4.8, reviewCount: 15),
  ],
);

/// Counts acquire()/release() calls — mirrors
/// `home_hub_supplemental_test.dart`'s identical `_CountingScreenProtection`
/// (the established pattern for pinning a PII screen's FLAG_SECURE
/// lifecycle).
class _CountingScreenProtection extends ScreenProtectionManager {
  int acquireCount = 0;
  int releaseCount = 0;

  @override
  void acquire() => acquireCount++;

  @override
  void release() => releaseCount++;

  @override
  void reset() {}
}

String _locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

GoRouter _router() => GoRouter(
  initialLocation: '/root',
  routes: <RouteBase>[
    GoRoute(
      path: '/root',
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.clientHome,
      builder: (context, state) => const SizedBox.shrink(),
    ),
    GoRoute(
      path: RouteNames.salonBookingSuccess,
      builder: (context, state) => SalonBookingSuccessScreen(
        args: state.extra! as SalonBookingSuccessArgs,
      ),
    ),
  ],
);

Future<GoRouter> _pump(WidgetTester tester) async {
  final GoRouter router = _router();
  await tester.pumpRoutedApp(
    router,
    // The screen's secondary salon-address read must never hit a real Dio
    // network call.
    overrides: <Object>[
      publicSalonProfileProvider(
        _kSalonId,
      ).overrideWith((ref) => (_kSalon, const <SalonMasterSummary>[])),
    ],
  );
  router.go(RouteNames.salonBookingSuccess, extra: _args());
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'lists one card per confirmed appointment + the success headline',
    (tester) async {
      await _pumpTall(tester);
      await _pump(tester);

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonBookingSuccessScreen)),
      );

      expect(find.text(l10n.salonBookingSuccessTitle), findsOneWidget);
      // Page 0 (m1) is showing; m2's card is on an un-built page.
      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-m2')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('appointment-pager-next')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-m2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('blocks back navigation (PopScope canPop false)', (tester) async {
    await _pumpTall(tester);
    await _pump(tester);

    final PopScope popScope = tester.widget<PopScope>(
      find.byType(PopScope).first,
    );
    expect(popScope.canPop, isFalse);
  });

  testWidgets('«На головну» navigates to the CLIENT home', (tester) async {
    await _pumpTall(tester);
    final GoRouter router = await _pump(tester);

    await tester.tap(find.byKey(const Key('salon-success-home-cta')));
    await tester.pumpAndSettle();

    expect(_locationOf(router), RouteNames.clientHome);
  });

  // ===========================================================================
  // mobile-qa gap (salon confirm/success rework, KNOWN COVERAGE GAPS):
  //   - the shared salon-address card's real value + its loading/error
  //     fallback (must never block the confirmed-appointment list);
  //   - the grand-total card (renders with N > 1, suppressed at N == 1);
  //   - the shared MasterStrip's ★rating on THIS screen;
  //   - per-master services/price/subtotal actually rendering.
  // ===========================================================================

  group('salon address card', () {
    testWidgets(
      'renders the REAL resolved salon address (street/buildingNo/city) '
      'once publicSalonProfileProvider resolves',
      (tester) async {
        await _pumpTall(tester);
        await _pump(tester);

        final Finder addressCard = find.byKey(
          const Key('salon-success-address-card'),
        );
        expect(addressCard, findsOneWidget);
        expect(
          find.descendant(
            of: addressCard,
            // i18n-finder-ok: address is fixture data (_kSalon), not translated UI copy.
            matching: find.text('вул. Хрещатик, 22, Київ'),
          ),
          findsOneWidget,
          reason:
              'must render the resolved Salon.street/buildingNo/city, not '
              'the l10n fallback, once the secondary read succeeds',
        );
      },
    );

    testWidgets('falls back to l10n.bookingAddressUnknown WHILE '
        'publicSalonProfileProvider is still loading, and the confirmed '
        'appointment cards render anyway — the address read is secondary and '
        'must never block the screen', (tester) async {
      await _pumpTall(tester);
      final GoRouter router = _router();

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          // Never resolves -> the family instance stays in AsyncLoading.
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => Completer<PublicSalonProfileData>().future),
        ],
      );
      router.go(RouteNames.salonBookingSuccess, extra: _args());
      await tester.pump();
      await tester.pump();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonBookingSuccessScreen)),
      );
      final Finder addressCard = find.byKey(
        const Key('salon-success-address-card'),
      );
      expect(addressCard, findsOneWidget);
      expect(
        find.descendant(
          of: addressCard,
          matching: find.text(l10n.bookingAddressUnknown),
        ),
        findsOneWidget,
      );
      // Page 0's (m1's) card is unaffected by the secondary read.
      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-m1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to l10n.bookingAddressUnknown when '
        'publicSalonProfileProvider ERRORS, and the confirmed appointment '
        'cards still render', (tester) async {
      await _pumpTall(tester);
      final GoRouter router = _router();

      await tester.pumpRoutedApp(
        router,
        // Disables Riverpod's default retry so the error stays put through
        // pumpAndSettle and leaves no pending backoff Timer at test end.
        retry: (_, _) => null,
        overrides: <Object>[
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) async => throw Exception('boom')),
        ],
      );
      router.go(RouteNames.salonBookingSuccess, extra: _args());
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonBookingSuccessScreen)),
      );
      final Finder addressCard = find.byKey(
        const Key('salon-success-address-card'),
      );
      expect(addressCard, findsOneWidget);
      expect(
        find.descendant(
          of: addressCard,
          matching: find.text(l10n.bookingAddressUnknown),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-m1')),
        findsOneWidget,
      );
    });
  });

  // ===========================================================================
  // FEATURE A — the «Салон» identity row (l10n key `bookingSalonLabel`) renders
  // the resolved salon.name ABOVE the address, INSIDE the shared address card
  // on the confirmed recap; suppressed (address-only, no crash) while the
  // secondary salon read is loading / absent.
  // ===========================================================================
  group('salon name row (Feature A)', () {
    testWidgets(
      'renders the «Салон» label + resolved salon.name INSIDE the address '
      'card, positioned ABOVE the address, once the profile resolves',
      (tester) async {
        await _pumpTall(tester);
        await _pump(tester);

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(SalonBookingSuccessScreen)),
        );
        final Finder addressCard = find.byKey(
          const Key('salon-success-address-card'),
        );
        final Finder salonNameRow = find.byKey(
          const Key('salon-success-salon-name'),
        );

        expect(
          find.descendant(of: addressCard, matching: salonNameRow),
          findsOneWidget,
          reason: 'the «Салон» row must render inside the address card',
        );
        expect(
          find.descendant(
            of: salonNameRow,
            matching: find.text(l10n.bookingSalonLabel),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: salonNameRow,
            // i18n-finder-ok: salon name is fixture data (_kSalon), not translated UI copy.
            matching: find.text('Салон «Вельвет»'),
          ),
          findsOneWidget,
          reason: 'the row must bind salon.name, not a placeholder',
        );

        final double salonNameTop = tester.getTopLeft(salonNameRow).dy;
        final double addressLabelTop = tester
            .getTopLeft(
              find.descendant(
                of: addressCard,
                matching: find.text(l10n.bookingAddressLabel),
              ),
            )
            .dy;
        expect(
          salonNameTop,
          lessThan(addressLabelTop),
          reason: 'the «Салон» row must sit ABOVE the address inside the card',
        );
      },
    );

    testWidgets(
      'is SUPPRESSED while the salon profile is still loading, and the recap '
      'renders address-only (fallback) with the confirmed appointment cards — '
      'no crash',
      (tester) async {
        await _pumpTall(tester);
        final GoRouter router = _router();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            // Never resolves -> the family instance stays in AsyncLoading.
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) => Completer<PublicSalonProfileData>().future),
          ],
        );
        router.go(RouteNames.salonBookingSuccess, extra: _args());
        await tester.pump();
        await tester.pump();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(SalonBookingSuccessScreen)),
        );

        expect(
          find.byKey(const Key('salon-success-salon-name')),
          findsNothing,
          reason:
              'while the secondary salon read is loading the «Салон» row must '
              'be suppressed rather than showing an empty/placeholder value',
        );
        final Finder addressCard = find.byKey(
          const Key('salon-success-address-card'),
        );
        expect(addressCard, findsOneWidget);
        expect(
          find.descendant(
            of: addressCard,
            matching: find.text(l10n.bookingAddressUnknown),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('salon-success-appt-m1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'is SUPPRESSED when the salon profile ERRORS — recap still renders '
      'address-only with the confirmed appointment cards (no crash)',
      (tester) async {
        await _pumpTall(tester);
        final GoRouter router = _router();

        await tester.pumpRoutedApp(
          router,
          retry: (_, _) => null,
          overrides: <Object>[
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) async => throw Exception('boom')),
          ],
        );
        router.go(RouteNames.salonBookingSuccess, extra: _args());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-success-salon-name')),
          findsNothing,
          reason:
              'a failed salon read must suppress the «Салон» row, not crash',
        );
        expect(
          find.byKey(const ValueKey<String>('salon-success-appt-m1')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ===========================================================================
  // The visit-wide grand total («Разом за візит») was REMOVED (owner
  // decision, 2026-08-23) — see `salon_booking_success_screen.dart`'s file
  // header. This is a regression guard, not the removed feature's coverage.
  // ===========================================================================
  group('grand-total card (removed)', () {
    testWidgets(
      'never renders — N > 1 shows only each master\'s own «Разом» subtotal, '
      'paged one master at a time',
      (tester) async {
        await _pumpTall(tester);
        await _pump(tester);

        expect(
          find.byKey(const Key('salon-success-grand-total-card')),
          findsNothing,
        );
        // m1's own subtotal — one 500 ₴ / 60 min service. Not the 1000 ₴/2
        // год the removed grand total would have summed across both masters.
        // i18n-finder-ok: subtotal is fixture-derived data, not translated UI copy.
        expect(find.text('500 ₴'), findsNWidgets(2)); // service row + Разом
        expect(find.text('1000 ₴'), findsNothing);

        await tester.tap(find.byKey(const Key('appointment-pager-next')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-success-grand-total-card')),
          findsNothing,
        );
        expect(find.text('500 ₴'), findsNWidgets(2));
      },
    );

    testWidgets('never renders at N == 1 either', (tester) async {
      await _pumpTall(tester);
      final GoRouter router = _router();
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => (_kSalon, const <SalonMasterSummary>[])),
        ],
      );
      router.go(
        RouteNames.salonBookingSuccess,
        extra: _singleAppointmentArgs(),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('salon-success-appt-m1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-success-grand-total-card')),
        findsNothing,
      );
    });
  });

  testWidgets("each confirmed appointment card's shared MasterStrip renders that "
      "master's OWN ★rating(reviewCount), and the card lists its own service "
      'name/price with a matching subtotal (card-unification + '
      'information-parity gap)', (tester) async {
    await _pumpTall(tester);
    final GoRouter router = _router();
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        publicSalonProfileProvider(
          _kSalonId,
        ).overrideWith((ref) => (_kSalon, const <SalonMasterSummary>[])),
      ],
    );
    router.go(RouteNames.salonBookingSuccess, extra: _ratedArgsTwoMasters());
    await tester.pumpAndSettle();

    // Page 0 (m1).
    final Finder m1Card = find.byKey(
      const ValueKey<String>('salon-success-appt-m1'),
    );

    // ★rating(reviewCount) — the whole point of the card-unification
    // change: the confirmed recap's identity card now shows it too.
    expect(
      find.descendant(of: m1Card, matching: find.text('4.6')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: m1Card, matching: find.text('(9)')),
      findsOneWidget,
    );

    // Per-master service name + price, each with a matching subtotal — one
    // service each, so its own price ("500 ₴") renders TWICE inside the
    // card: once on the service row, once on the "Разом" subtotal.
    expect(
      // i18n-finder-ok: service name is fixture data (_ratedAppt), not translated UI copy.
      find.descendant(of: m1Card, matching: find.text('Манікюр')),
      findsOneWidget,
    );
    expect(
      // i18n-finder-ok: price is fixture-derived data, not translated UI copy.
      find.descendant(of: m1Card, matching: find.text('500 ₴')),
      findsNWidgets(2),
    );

    // Page to m2 — same assertions, its own card.
    await tester.tap(find.byKey(const Key('appointment-pager-next')));
    await tester.pumpAndSettle();

    final Finder m2Card = find.byKey(
      const ValueKey<String>('salon-success-appt-m2'),
    );
    expect(
      find.descendant(of: m2Card, matching: find.text('4.8')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: m2Card, matching: find.text('(15)')),
      findsOneWidget,
    );
    expect(
      // i18n-finder-ok: service name is fixture data (_ratedAppt), not translated UI copy.
      find.descendant(of: m2Card, matching: find.text('Манікюр')),
      findsOneWidget,
    );
    expect(
      // i18n-finder-ok: price is fixture-derived data, not translated UI copy.
      find.descendant(of: m2Card, matching: find.text('500 ₴')),
      findsNWidgets(2),
    );
  });

  // ===========================================================================
  // «Додати в календар» — ONE CalendarButton per BOOKING (1 service = 1
  // booking; owner decision, 2026-08-23). Smoke coverage proving the count
  // and the reused shared widget; full behavioural coverage (the actual
  // add_2_calendar call) is a mobile-qa follow-up.
  // ===========================================================================
  testWidgets(
    'shows exactly one CalendarButton per booking, on the master\'s own page',
    (tester) async {
      await _pumpTall(tester);
      await _pump(tester);

      // m1 (page 0) has exactly ONE service -> exactly ONE calendar button.
      expect(
        find.byKey(const ValueKey<String>('salon-success-add-calendar-0-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('salon-success-add-calendar-0-1')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('appointment-pager-next')));
      await tester.pumpAndSettle();

      // m2 (page 1) — its own single button.
      expect(
        find.byKey(const ValueKey<String>('salon-success-add-calendar-1-0')),
        findsOneWidget,
      );
    },
  );

  // ===========================================================================
  // ScreenProtectionManager lifecycle (SEC — this screen renders the salon's
  // address, PII). Mirrors `home_hub_supplemental_test.dart`'s established
  // acquire/release pattern; standing backlog row notes 11 auth screens lack
  // exactly this test — this pass must not extend that debt onto the two NEW
  // salon booking screens.
  // ===========================================================================
  group('ScreenProtectionManager lifecycle', () {
    testWidgets(
      'acquire() is called exactly once when the success screen mounts',
      (tester) async {
        await _pumpTall(tester);
        final GoRouter router = _router();
        final _CountingScreenProtection counting = _CountingScreenProtection();

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            publicSalonProfileProvider(
              _kSalonId,
            ).overrideWith((ref) => (_kSalon, const <SalonMasterSummary>[])),
            screenProtectionProvider.overrideWithValue(counting),
          ],
        );
        router.go(RouteNames.salonBookingSuccess, extra: _args());
        await tester.pumpAndSettle();

        expect(
          counting.acquireCount,
          1,
          reason:
              'initState must call acquire() exactly once to enable '
              'FLAG_SECURE for the PII-bearing salon success screen',
        );
      },
    );

    testWidgets('release() is called exactly once when the success screen is '
        'disposed (navigating away via «На головну») — acquire/release stay '
        'symmetric', (tester) async {
      await _pumpTall(tester);
      final GoRouter router = _router();
      final _CountingScreenProtection counting = _CountingScreenProtection();

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          publicSalonProfileProvider(
            _kSalonId,
          ).overrideWith((ref) => (_kSalon, const <SalonMasterSummary>[])),
          screenProtectionProvider.overrideWithValue(counting),
        ],
      );
      router.go(RouteNames.salonBookingSuccess, extra: _args());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-success-home-cta')));
      await tester.pumpAndSettle();

      expect(
        counting.releaseCount,
        1,
        reason:
            'dispose() must call release() exactly once so FLAG_SECURE is '
            'cleared once the success screen is navigated away from',
      );
      expect(counting.acquireCount, counting.releaseCount);
    });
  });
}
