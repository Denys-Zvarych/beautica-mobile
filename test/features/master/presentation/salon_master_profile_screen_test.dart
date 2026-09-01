// mobile-qa (2026-09-01) — widget tests for [SalonMasterProfileScreen].
//
// This screen shipped with ZERO direct tests (build-verifier MEDIUM, raised
// twice; ~649 lines across this file + `salon_master_own_profile_notifier
// .dart` with only incidental routing coverage). This file closes that gap:
//
//   • all three [AsyncValue] states — loading skeleton, error + working
//     retry, loaded body;
//   • the salon-name / salon-address rows are OMITTED ENTIRELY (a widget-list
//     gate, not an empty string) when `salon == null`, and rendered when
//     present — mutation-proved below, not merely asserted;
//   • bio / service-categories / contact sections each independently omitted
//     when empty, mirroring the sibling `master_profile_screen_test.dart`/
//     `owner_own_profile_screen_test.dart` convention;
//   • the trailing tune button pushes the SALON_MASTER settings route.
//
// `approvedCategoriesProvider` is overridden DIRECTLY — it bypasses
// `serviceRepositoryProvider` entirely (the established footgun documented in
// `owner_own_profile_notifier_test.dart` and `salon_staff_profile_screen
// _test.dart`).
//
// Finders use widget Keys, never localized/Cyrillic strings (M2).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/master/application/salon_master_own_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const Master _master = Master(
  id: 'm-9',
  firstName: 'Ірина',
  lastName: 'Бондар',
  bio: 'Працюю з клієнтами вже 5 років.',
  avgRating: 4.6,
  reviewCount: 8,
  type: MasterType.salonMaster,
  salonId: 'salon-1',
  phoneNumber: '+380 67 111 22 33',
);

const Master _masterBare = Master(
  id: 'm-10',
  firstName: 'Ірина',
  lastName: 'Бондар',
  reviewCount: 0,
  type: MasterType.salonMaster,
);

const List<MasterService> _services = <MasterService>[
  MasterService(
    id: 's-1',
    serviceDefId: 'd-1',
    name: 'Стрижка',
    durationMinutes: 45,
    priceMin: 400,
    priceDisplay: '400 ₴',
    category: 'HAIR',
  ),
];

const Salon _salon = Salon(
  id: 'salon-1',
  name: 'Beautica Studio',
  // `city` is the legacy free-text field — the backend stopped writing it at
  // Phase 10.6 (see `Salon.city`'s own doc) and the screen under test no
  // longer reads it at all (that was the bug this file's new "resolved
  // taxonomy" group below closes). Left populated here anyway: this fixture
  // carries a BLANK `oblastId`/`cityId` (the `@Default('')`), which is what
  // makes `resolvedLocalityProvider` short-circuit synchronously to
  // `ResolvedLocality()` with no network read — exactly the "no taxonomy on
  // this salon" case, distinct from the new fixture below.
  city: 'Київ',
  street: 'Хрещатик',
  buildingNo: '1',
);

// ---------------------------------------------------------------------------
// Resolved-taxonomy fixtures — mobile-dev fix (2026-09-01): the salon-master
// identity card used to read `Salon.city` directly (always `null` on real
// data since Phase 10.6), so the salon address rendered street-only with no
// locality at all. The fix resolves `oblastId`/`cityId`/`districtId` via
// `resolvedLocalityProvider` — the SAME shared provider
// `salon_management_profile_screen_test.dart`'s "resolved locality" group
// already drives with an identical `_FakeLocationRepository` shape (mirrored
// here rather than promoted to a shared test helper — REUSE-FIRST governs
// production code, not a single-fixture test double with no second Dart
// analyzer-visible caller yet).
// ---------------------------------------------------------------------------

const _taxonomyOblast = Oblast(
  id: 'ob-1',
  name: 'Львівська область',
  katotthCode: 'A',
);
const _taxonomyCity = City(
  id: 'ct-1',
  oblastId: 'ob-1',
  name: 'Львів',
  katotthCode: 'B',
  hasDistricts: true,
);
const _taxonomyDistrict = CityDistrict(
  id: 'd-1',
  cityId: 'ct-1',
  name: 'Галицький',
  katotthCode: 'C',
);

class _FakeLocationRepository implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => const <Oblast>[_taxonomyOblast];

  @override
  Future<List<City>> fetchCities(String oblastId) async => const <City>[
    _taxonomyCity,
  ];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      const <CityDistrict>[_taxonomyDistrict];
}

const Salon _salonWithTaxonomy = Salon(
  id: 'salon-2',
  name: 'Beautica Studio Lviv',
  oblastId: 'ob-1',
  cityId: 'ct-1',
  districtId: 'd-1',
  street: 'вул. Хрещатик',
  buildingNo: '1',
);

/// Hierarchy-ordered, exactly as `buildFullAddressLine` composes it — city
/// -> district -> street -> building. The oblast (`_taxonomyOblast`) is
/// resolved to drive the city cascade but must NEVER appear in this string
/// (same product decision `salon_management_profile_screen_test.dart`'s
/// `_expectedResolvedAddress` documents).
const String _expectedResolvedSalonAddress =
    'Львів, Галицький, вул. Хрещатик, 1';

// ---------------------------------------------------------------------------
// Partial-resolution fixture (item 4, mobile-qa 2026-09-01) — the district
// lookup fails AFTER the city already matched.
// `resolved_locality_provider.dart`'s own doc: "Partial results survive a
// failure that happens after an earlier stage already resolved... the
// matched-so-far variables are declared outside the try block and returned
// regardless." This fixture drives exactly that branch for THIS screen: city
// resolves, district throws, and the salon still carries a `districtId` (so
// the provider actually attempts the district fetch instead of skipping it).
// ---------------------------------------------------------------------------

class _FakeLocationRepositoryDistrictFailure implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => const <Oblast>[_taxonomyOblast];

  @override
  Future<List<City>> fetchCities(String oblastId) async => const <City>[
    _taxonomyCity,
  ];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      throw const ServerFailure();
}

/// city-only — the district segment never resolved, so it must be absent
/// from every composed line (not blank, not a dangling comma).
const String _expectedPartialResolvedSalonAddress = 'Львів, вул. Хрещатик, 1';

/// The three mutually-exclusive keys [MasterAddressBlock] can render under
/// `keyPrefix: 'salon-master-profile-salon'`, depending on measured layout
/// width (split two-row vs. collapsed one-row) — see that widget's own doc.
/// Exactly one of these renders when a salon carries a visible address; none
/// render when it does not.
final List<Finder> _salonAddressFinders = <Finder>[
  find.byKey(const Key('salon-master-profile-salon-locality-text')),
  find.byKey(const Key('salon-master-profile-salon-address-text')),
  find.byKey(const Key('salon-master-profile-salon-address-combined-text')),
];

List<Object> _overrides(SalonMasterOwnProfileData data) => <Object>[
  salonMasterOwnProfileProvider.overrideWith((Ref ref) async => data),
  approvedCategoriesProvider.overrideWith(
    (Ref ref) async => const <ServiceCategoryOption>[],
  ),
];

void main() {
  group('AsyncValue states', () {
    testWidgets('loading — skeleton renders; neither body nor error does', (
      tester,
    ) async {
      final Completer<SalonMasterOwnProfileData> pending =
          Completer<SalonMasterOwnProfileData>();
      addTearDown(() {
        if (!pending.isCompleted) {
          pending.complete((_master, _services, _salon));
        }
      });

      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: <Object>[
          salonMasterOwnProfileProvider.overrideWith(
            (Ref ref) => pending.future,
          ),
          approvedCategoriesProvider.overrideWith(
            (Ref ref) async => const <ServiceCategoryOption>[],
          ),
        ],
      );
      // `pump`, never `pumpAndSettle` — the skeleton runs a repeating shimmer
      // that never settles.
      await tester.pump();

      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.byKey(const Key('salon-master-profile-name')), findsNothing);
      expect(find.byType(ErrorState), findsNothing);
    });

    testWidgets('error — ErrorState with a working retry renders', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: <Object>[
          // ASYNC throw — a synchronous throw would bypass the AsyncValue
          // error path entirely (short-circuits Riverpod's own machinery).
          salonMasterOwnProfileProvider.overrideWith(
            (Ref ref) async => throw const ServerFailure(),
          ),
          approvedCategoriesProvider.overrideWith(
            (Ref ref) async => const <ServiceCategoryOption>[],
          ),
        ],
        // Disabled so the assertion lands on the TERMINAL error, not on
        // `AsyncLoading(retrying: true)` (which still satisfies `hasError`).
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
      expect(find.byKey(const Key('salon-master-profile-name')), findsNothing);
    });

    testWidgets('error — tapping retry re-invalidates the loader and the '
        'recovered body renders', (tester) async {
      int attempt = 0;
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: <Object>[
          salonMasterOwnProfileProvider.overrideWith((Ref ref) async {
            attempt++;
            if (attempt == 1) throw const ServerFailure();
            return (_master, _services, _salon);
          }),
          approvedCategoriesProvider.overrideWith(
            (Ref ref) async => const <ServiceCategoryOption>[],
          ),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget, reason: 'sanity');
      expect(attempt, 1);

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(attempt, 2);
      expect(find.byType(ErrorState), findsNothing);
      expect(
        find.byKey(const Key('salon-master-profile-name')),
        findsOneWidget,
      );
    });
  });

  group('loaded body — salon affiliation rows', () {
    testWidgets('salon present — name and address rows render', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-master-profile-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-master-profile-role-chip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-master-profile-salon-name')),
        findsOneWidget,
        reason: 'a present salon must render the affiliation line',
      );
      final int addressWidgetsFound = _salonAddressFinders
          .map((Finder f) => f.evaluate().length)
          .fold<int>(0, (int a, int b) => a + b);
      expect(
        addressWidgetsFound,
        1,
        reason:
            'exactly one of the three MasterAddressBlock renderings must be '
            'present for a salon with a visible address',
      );
    });

    testWidgets(
      'salon present with a resolved oblastId/cityId/districtId — the '
      'RESOLVED city/district names render, not just street/building '
      '(regression test for the "address renders street-only, no city" bug '
      '— `Salon.city` is null on this endpoint and must never be read)',
      (tester) async {
        await tester.pumpApp(
          const SalonMasterProfileScreen(),
          overrides: <Object>[
            ..._overrides((_master, _services, _salonWithTaxonomy)),
            locationRepositoryProvider.overrideWith(
              (_) => _FakeLocationRepository(),
            ),
          ],
        );
        await tester.pumpAndSettle();

        final Finder combined = find.byKey(
          const Key('salon-master-profile-salon-address-combined-text'),
        );
        final Finder localityOnly = find.byKey(
          const Key('salon-master-profile-salon-locality-text'),
        );
        final Finder streetOnly = find.byKey(
          const Key('salon-master-profile-salon-address-text'),
        );

        // MasterAddressBlock picks the collapsed-one-line or split-two-row
        // rendering based on MEASURED width — either is a correct render of
        // the same resolved data, so accept whichever the layout produced
        // (mirrors this file's own `_salonAddressFinders` ambiguity) and
        // assert the actual TEXT CONTENT either way, not just presence.
        if (combined.evaluate().isNotEmpty) {
          expect(localityOnly, findsNothing);
          expect(streetOnly, findsNothing);
          expect(
            tester.widget<Text>(combined).data,
            _expectedResolvedSalonAddress,
            reason:
                'city -> district -> street -> building, the hierarchy '
                'order buildFullAddressLine composes — the resolved '
                'locality must replace the previously-blank line, not '
                'leave the address street-only',
          );
        } else {
          expect(localityOnly, findsOneWidget);
          expect(streetOnly, findsOneWidget);
          expect(
            tester.widget<Text>(localityOnly).data,
            'Львів, Галицький',
            reason:
                'the split path\'s locality row is the resolved city + '
                'district, composed via buildStreetLine(cityName, '
                'districtName) — this is the exact regression the fix '
                'closes',
          );
          expect(tester.widget<Text>(streetOnly).data, 'вул. Хрещатик, 1');
        }
      },
    );

    // Item 4 (mobile-qa 2026-09-01) — "no cityId" partial state, strengthened
    // beyond the earlier "salon present" test's presence-only assertion
    // (`addressWidgetsFound == 1`) to assert the actual TEXT. `_salon`'s
    // blank `oblastId`/`cityId` trips `resolvedLocalityProvider`'s own
    // synchronous "nothing to resolve" short-circuit (no network read at
    // all), so `resolved.city`/`.district` are both `null`. With `locality`
    // null and `street` non-null, `MasterAddressBlock`'s `(null, road)`
    // switch arm is taken DETERMINISTICALLY — no width measurement, no
    // combined/split ambiguity — so this assertion needs no branch, unlike
    // the resolved-taxonomy test above.
    testWidgets(
      'salon present with NO oblastId/cityId — renders street-only via the '
      'single-field address-text row, never the locality or combined key',
      (tester) async {
        await tester.pumpApp(
          const SalonMasterProfileScreen(),
          overrides: _overrides((_master, _services, _salon)),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-master-profile-salon-locality-text')),
          findsNothing,
          reason: 'no cityId to resolve — there is no locality to render',
        );
        expect(
          find.byKey(
            const Key('salon-master-profile-salon-address-combined-text'),
          ),
          findsNothing,
          reason:
              'MasterAddressBlock only reaches the combined/split choice '
              'when BOTH locality and street are non-null — with locality '
              'null this is the deterministic single-field branch instead',
        );
        final Finder streetOnly = find.byKey(
          const Key('salon-master-profile-salon-address-text'),
        );
        expect(streetOnly, findsOneWidget);
        expect(
          tester.widget<Text>(streetOnly).data,
          'Хрещатик, 1',
          reason:
              'street + buildingNo, unchanged from the pre-fix rendering — '
              'this fixture never had a city to lose',
        );
      },
    );

    // Item 4 (mobile-qa 2026-09-01) — "resolution failed" partial state.
    // Distinct from the "no cityId" case above: here oblastId/cityId ARE
    // present and the OBLAST + CITY stages succeed, but the DISTRICT stage
    // throws. `resolved_locality_provider.dart`'s own doc promises the
    // matched-so-far city survives a later-stage failure — this proves that
    // contract end-to-end through this screen, not just at the provider
    // unit level.
    testWidgets(
      'salon present with oblastId/cityId/districtId but the DISTRICT fetch '
      'fails — the resolved CITY still renders, the district silently '
      'drops (no dangling comma, no crash, no error UI)',
      (tester) async {
        await tester.pumpApp(
          const SalonMasterProfileScreen(),
          overrides: <Object>[
            ..._overrides((_master, _services, _salonWithTaxonomy)),
            locationRepositoryProvider.overrideWith(
              (_) => _FakeLocationRepositoryDistrictFailure(),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(ErrorState),
          findsNothing,
          reason:
              'resolvedLocalityProvider catches internally and never '
              'rethrows — a failed district lookup must never surface as '
              'a screen-level error state',
        );

        final Finder combined = find.byKey(
          const Key('salon-master-profile-salon-address-combined-text'),
        );
        final Finder localityOnly = find.byKey(
          const Key('salon-master-profile-salon-locality-text'),
        );
        final Finder streetOnly = find.byKey(
          const Key('salon-master-profile-salon-address-text'),
        );

        if (combined.evaluate().isNotEmpty) {
          expect(localityOnly, findsNothing);
          expect(streetOnly, findsNothing);
          expect(
            tester.widget<Text>(combined).data,
            _expectedPartialResolvedSalonAddress,
            reason:
                'the CITY must still appear (partial success survives), '
                'and the district must be OMITTED, not rendered blank or '
                'with a dangling separator',
          );
        } else {
          expect(localityOnly, findsOneWidget);
          expect(streetOnly, findsOneWidget);
          expect(
            tester.widget<Text>(localityOnly).data,
            'Львів',
            reason:
                'city-only locality line — buildStreetLine(cityName, null) '
                'drops the district segment entirely rather than leaving a '
                'trailing comma',
          );
          expect(tester.widget<Text>(streetOnly).data, 'вул. Хрещатик, 1');
        }
      },
    );

    testWidgets('salon NULL — the salon-name and salon-address rows are '
        'OMITTED ENTIRELY, never rendered empty', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, null)),
      );
      await tester.pumpAndSettle();

      // Sanity: the rest of the identity card still renders.
      expect(
        find.byKey(const Key('salon-master-profile-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-master-profile-role-chip')),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('salon-master-profile-salon-name')),
        findsNothing,
        reason:
            'salon == null must OMIT the affiliation line — not render it '
            'with an empty/placeholder name',
      );
      for (final Finder f in _salonAddressFinders) {
        expect(
          f,
          findsNothing,
          reason:
              'salon == null must omit the MasterAddressBlock entirely — '
              'none of its three possible renderings may appear',
        );
      }
    });
  });

  group('loaded body — optional sections', () {
    testWidgets('bio present renders the bio section', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-master-profile-bio')), findsOneWidget);
    });

    testWidgets('no bio omits the bio section', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_masterBare, const <MasterService>[], null)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-master-profile-bio')), findsNothing);
    });

    testWidgets('services present renders «Мої категорії»', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-service-categories')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-master-profile-category-HAIR')),
        findsOneWidget,
      );
    });

    testWidgets('empty services omits «Мої категорії»', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_masterBare, const <MasterService>[], null)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-service-categories')),
        findsNothing,
      );
    });

    testWidgets('phone present renders the contact tile', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-contact-phone')),
        findsOneWidget,
      );
    });

    testWidgets('no phone omits the contact tile', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_masterBare, const <MasterService>[], null)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-contact-phone')),
        findsNothing,
      );
    });

    testWidgets('services stat value reflects the loaded services count', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('salon-master-profile-services-value')),
            )
            .data,
        '1',
      );
    });
  });

  group('trailing tune — pushes settings', () {
    testWidgets('tapping the tune icon pushes RouteNames.salonMasterSettings', (
      tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: RouteNames.salonMasterProfile,
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.salonMasterProfile,
            builder: (_, _) => const SalonMasterProfileScreen(),
          ),
          GoRoute(
            path: RouteNames.salonMasterSettings,
            builder: (_, _) =>
                const Scaffold(body: SizedBox(key: Key('stub-staff-settings'))),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-menu-salon-master')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-staff-settings')), findsOneWidget);
    });
  });
}
