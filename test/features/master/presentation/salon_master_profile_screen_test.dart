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
import 'dart:io';

import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/core/media/pick/media_pick_service.dart';
import 'package:beautica_mobile/core/media/upload/avatar_upload_controller.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/notifications/presentation/unread_notifications_notifier.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/application/salon_master_own_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/master_reviews_body.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../core/media/pick/scripted_pick_gateway.dart';
import '../../../helpers/avatar_badge_geometry.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
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

  /// Phase 346 — the settlement autocomplete. Unused by this fixture: the
  /// surfaces under test here render no settlement field, so an unimplemented
  /// stub asserts that rather than silently returning an empty list a caller
  /// could mistake for "no matches".
  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
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

  /// Phase 346 — the settlement autocomplete. Unused by this fixture: the
  /// surfaces under test here render no settlement field, so an unimplemented
  /// stub asserts that rather than silently returning an empty list a caller
  /// could mistake for "no matches".
  @override
  Future<List<Settlement>> searchSettlements(
    String query, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
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

/// The settled `GET /masters/me` the identity card's avatar reads (Phase
/// 367: the loader record is avatar-stripped, so the photo comes from
/// `masterProfileProvider` directly).
class _SettledMasterProfile extends MasterProfile {
  _SettledMasterProfile(this.master);
  final Master master;

  @override
  Future<Master> build() async => master;
}

Object _settledMaster(Master master) =>
    masterProfileProvider.overrideWith(() => _SettledMasterProfile(master));

List<Object> _overrides(SalonMasterOwnProfileData data) => <Object>[
  salonMasterOwnProfileProvider.overrideWith((Ref ref) async => data),
  _settledMaster(data.$1),
  approvedCategoriesProvider.overrideWith(
    (Ref ref) async => const <ServiceCategoryOption>[],
  ),
];

/// Phase 363 — a global unread count of two, so the header bell shows its dot.
class _TwoUnread extends UnreadNotifications {
  @override
  FutureOr<int> build() => 2;
}

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
          _settledMaster(_master),
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
          _settledMaster(_master),
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

    // Audit 2026-09-24 (MEDIUM) — the taxonomy lookup resolves CITY-type
    // settlements only, so a village salon's address had NO locality.
    testWidgets('a village salon renders its prefixed name (no oblast)', (
      tester,
    ) async {
      final AppLocalizations uk = lookupAppLocalizations(const Locale('uk'));
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: <Object>[
          ..._overrides((
            _master,
            _services,
            _salonWithTaxonomy.copyWith(
              cityId: 'v-ivanivka',
              districtId: null,
              city: 'Іванівка',
              region: 'Полтавська',
              citySettlementType: 'VILLAGE',
            ),
          )),
          locationRepositoryProvider.overrideWith(
            (_) => _FakeLocationRepository(),
          ),
        ],
      );
      await tester.pumpAndSettle();

      final String village = '${uk.settlementVillagePrefix} Іванівка';
      final Finder combined = find.byKey(
        const Key('salon-master-profile-salon-address-combined-text'),
      );
      final String? rendered = combined.evaluate().isNotEmpty
          ? tester.widget<Text>(combined).data
          : tester
                .widget<Text>(
                  find.byKey(
                    const Key('salon-master-profile-salon-locality-text'),
                  ),
                )
                .data;
      expect(rendered, startsWith(village));
      expect(rendered, isNot(contains('Полтавська')));
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

    // Phase 351 (U-locked "Both rows" empty-state decision) — an empty bio
    // on the salon master's OWN profile no longer omits the section: it now
    // shows the promoted `AddLink` «Додати опис» (opens
    // RouteNames.salonMasterEditPersonal) instead of the bio card.
    testWidgets(
      'no bio shows the «Додати опис» AddLink (section not omitted)',
      (tester) async {
        await tester.pumpApp(
          const SalonMasterProfileScreen(),
          overrides: _overrides((_masterBare, const <MasterService>[], null)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('salon-master-profile-bio')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('salon-master-profile-add-bio')),
          findsOneWidget,
        );
      },
    );

    testWidgets('services present renders «Мої категорії» (on the «Послуги» '
        'tab, Phase 351)', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-master-profile-tab-1')));
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

    testWidgets('empty services omits «Мої категорії» and shows the '
        '"ask the owner/admin" empty state (on the «Послуги» tab)', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_masterBare, const <MasterService>[], null)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-master-profile-tab-1')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-master-profile-service-categories')),
        findsNothing,
      );

      // ServicesEmptyState (promoted, REUSE-FIRST, from the read-only
      // `/staff/services` screen) — heading + the read-only "ask the salon
      // owner/admin" hint, NOT `servicesEmptyBody`'s "add your first
      // service" (this viewer cannot add services themselves).
      expect(
        find.byKey(const Key('salon-master-profile-services-empty')),
        findsOneWidget,
      );
      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonMasterProfileScreen)),
      );
      // i18n-finder-ok: asserting the exact localized copy shown to a
      // read-only viewer, not merely widget presence.
      expect(find.text(l10n.servicesEmpty), findsOneWidget);
      // i18n-finder-ok: see above.
      expect(find.text(l10n.salonMasterServicesEmptyHint), findsOneWidget);
      // i18n-finder-ok: the writable-audience copy must NOT appear here.
      expect(find.text(l10n.servicesEmptyBody), findsNothing);
      // No CTA — this viewer cannot add services.
      expect(find.byKey(const Key('btn-create-service-empty')), findsNothing);
    });

    testWidgets(
      'services present shows no empty-state hint (on the «Послуги» tab)',
      (tester) async {
        await tester.pumpApp(
          const SalonMasterProfileScreen(),
          overrides: _overrides((_master, _services, _salon)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-master-profile-tab-1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-master-profile-services-empty')),
          findsNothing,
        );
      },
    );

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

  // ──────────────────────────────────────────────────────────────────────────
  // User decision 2026-09-26 — the stat cards are DISPLAY-ONLY. Superseded
  // Phase 351's card → tab mechanism (D15): 3 cards (rating / reviews /
  // services — «Досвід» removed, D9), a tap on any of them must leave the
  // selected tab and route unchanged, and expose no button semantics. The
  // «Про майстра» / «Послуги» / «Відгуки» tabs are the only way to switch.
  // ──────────────────────────────────────────────────────────────────────────
  group('stat cards are display-only (user decision 2026-09-26)', () {
    List<Object> overridesWithReviews(SalonMasterOwnProfileData data) =>
        <Object>[
          ..._overrides(data),
          masterReviewSummaryProvider(data.$1.id).overrideWith(
            (Ref ref) async => MasterReviewSummary(
              avgRating: data.$1.avgRating,
              reviewCount: data.$1.reviewCount,
              distribution: const <int>[0, 0, 0, 0, 0],
            ),
          ),
          masterReviewsProvider(
            data.$1.id,
            MasterReviewSort.newest,
          ).overrideWith((Ref ref) async => const <MasterReviewItem>[]),
        ];

    testWidgets('no «Досвід» card renders anywhere on the screen', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: overridesWithReviews((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(SalonMasterProfileScreen)),
      );
      expect(find.text(l10n.publicMasterExperienceLabel), findsNothing);
    });

    testWidgets('default tab is «Про майстра»; affiliation + address render '
        'above the cards', (tester) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: overridesWithReviews((_master, _services, _salon)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('salon-master-profile-bio')), findsOneWidget);
      expect(find.byType(MasterReviewsBody), findsNothing);
      expect(
        find.byKey(const Key('salon-master-profile-service-categories')),
        findsNothing,
      );

      // Affiliation/address sit in the identity card, ABOVE the stat-card
      // row and the tab bar — assert the vertical order.
      final double nameY = tester
          .getTopLeft(find.byKey(const Key('salon-master-profile-salon-name')))
          .dy;
      final double tabBarY = tester
          .getTopLeft(find.byKey(const Key('salon-master-profile-tab-0')))
          .dy;
      expect(nameY, lessThan(tabBarY));
    });

    for (final String cardKey in <String>[
      'salon-master-profile-rating-tile',
      'salon-master-profile-reviews-tile',
      'salon-master-profile-services-tile',
    ]) {
      testWidgets(
        'tapping $cardKey leaves the «Про майстра» tab and route unchanged',
        (tester) async {
          await tester.pumpApp(
            const SalonMasterProfileScreen(),
            overrides: overridesWithReviews((_master, _services, _salon)),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('salon-master-profile-bio')),
            findsOneWidget,
          );
          expect(find.byType(MasterReviewsBody), findsNothing);

          // No InkWell/GestureDetector on the card — warnIfMissed would flag
          // a real interactive target the tap failed to land on.
          await tester.tap(find.byKey(Key(cardKey)), warnIfMissed: false);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('salon-master-profile-bio')),
            findsOneWidget,
            reason: 'a card tap must never switch the screen\'s own tab',
          );
          expect(find.byType(MasterReviewsBody), findsNothing);
          expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        },
      );

      testWidgets('$cardKey exposes no button semantics', (tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pumpApp(
          const SalonMasterProfileScreen(),
          overrides: overridesWithReviews((_master, _services, _salon)),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getSemantics(find.byKey(Key(cardKey))),
          isNot(isSemantics(isButton: true)),
        );

        handle.dispose();
      });
    }

    testWidgets(
      'the «Послуги» tab (reached via the tab bar) stays read-only: a '
      'category card there does NOT navigate (D12)',
      (tester) async {
        await tester.pumpApp(
          const SalonMasterProfileScreen(),
          overrides: overridesWithReviews((_master, _services, _salon)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-master-profile-tab-1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('salon-master-profile-service-categories')),
          findsOneWidget,
        );
        final Finder card = find.byKey(
          const Key('salon-master-profile-category-HAIR'),
        );
        expect(card, findsOneWidget);

        await tester.tap(card);
        await tester.pumpAndSettle();

        // Still the same screen — a read-only card has no navigation target.
        expect(find.byType(SalonMasterProfileScreen), findsOneWidget);
        expect(
          find.byKey(const Key('salon-master-profile-service-categories')),
          findsOneWidget,
        );
      },
    );

    testWidgets('AddLink «Додати опис» opens salonMasterEditPersonal', (
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
            path: RouteNames.salonMasterEditPersonal,
            builder: (_, _) =>
                const Scaffold(body: SizedBox(key: Key('stub-edit-personal'))),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpRoutedApp(
        router,
        overrides: overridesWithReviews((
          _masterBare,
          const <MasterService>[],
          null,
        )),
      );
      await tester.pumpAndSettle();

      final Finder addLink = find.byKey(
        const Key('salon-master-profile-add-bio'),
      );
      expect(addLink, findsOneWidget);
      await tester.tap(addLink);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-edit-personal')), findsOneWidget);
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

  // Phase 363 — the global notification bell, left of the tune button. «Мій
  // профіль» is this role's landing tab and carries the only bell; nothing else
  // on the header moves.
  group('notification bell in the header (phase 363)', () {
    GoRouter bellRouter() => GoRouter(
      initialLocation: RouteNames.salonMasterProfile,
      routes: <RouteBase>[
        GoRoute(
          path: RouteNames.salonMasterProfile,
          builder: (_, _) => const SalonMasterProfileScreen(),
        ),
        GoRoute(
          path: RouteNames.notifications,
          builder: (_, _) => const Scaffold(body: Text('feed-stub')),
        ),
      ],
    );

    Future<void> pumpBell(
      WidgetTester tester,
      GoRouter router, {
      List<Object> extra = const <Object>[],
    }) async {
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          ..._overrides((_master, _services, _salon)),
          ...extra,
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'should_sitLeftOfTheTuneButton_with12dpGap_andNothingElseMoves',
      (tester) async {
        final GoRouter router = bellRouter();
        addTearDown(router.dispose);
        await pumpBell(tester, router);

        final Rect bell = tester.getRect(
          find.byKey(const Key('salon_master_profile_bell_button')),
        );
        final Rect tune = tester.getRect(
          find.byKey(const Key('btn-menu-salon-master')),
        );
        final double width = tester.getSize(find.byType(MaterialApp)).width;

        expect(bell.right, lessThan(tune.left));
        expect(tune.left - bell.right, VelvetSpacing.sm + 4);
        // The tune button stays pinned to the right gutter, as before.
        expect(tune.right, width - VelvetSpacing.lg);
        // The Stack-centred title does not shift for the wider trailing slot.
        final String title = AppLocalizations.of(
          tester.element(find.byType(SalonMasterProfileScreen)),
        ).masterProfileTitle;
        expect(tester.getCenter(find.text(title)).dx, closeTo(width / 2, 1));
      },
    );

    testWidgets('should_showTheUnreadDot_fromTheGlobalCount', (tester) async {
      final GoRouter router = bellRouter();
      addTearDown(router.dispose);
      await pumpBell(
        tester,
        router,
        extra: <Object>[
          unreadNotificationsProvider.overrideWith(_TwoUnread.new),
        ],
      );

      expect(
        tester
            .widget<AppIcon>(find.byKey(NotificationBellButton.bellIconKey))
            .asset,
        BeauticaAssetIcons.notificationUnread,
      );
    });

    testWidgets('should_pushTheFeed_andKeepABackStack_whenTheBellIsTapped', (
      tester,
    ) async {
      final GoRouter router = bellRouter();
      addTearDown(router.dispose);
      await pumpBell(tester, router);

      await tester.tap(
        find.byKey(const Key('salon_master_profile_bell_button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('feed-stub'), findsOneWidget);
      expect(router.canPop(), isTrue, reason: 'push, never go');
    });

    testWidgets('should_keepTheTuneButtonNavigating_toSettings', (
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
                const Scaffold(body: SizedBox(key: Key('stub-settings'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpBell(tester, router);

      await tester.tap(find.byKey(const Key('btn-menu-salon-master')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-settings')), findsOneWidget);
    });
  });

  // Phase 310 — the REAL production wiring at this screen's own call site
  // (`salon_master_profile_screen.dart:232`'s `scheduleRoute:` param), as
  // opposed to `salon_master_bottom_nav_redirect_test.dart`'s synthetic
  // router (which reconstructs its own `VelvetBottomNavBar` call and would
  // NOT catch a regression at THIS file's actual call site). Mutation-tested
  // 2026-09-06: reverting this screen's `scheduleRoute:` param to the
  // omitted default turned this test red (tile 2 landed on the
  // INDEPENDENT_MASTER-only `/schedule` stub instead of `/staff/schedule`).
  group('bottom nav — Графік tile (Phase 310)', () {
    testWidgets(
      'tapping master-nav-tile-2 lands on RouteNames.salonMasterSchedule, '
      'NOT the default RouteNames.masterSchedule',
      (tester) async {
        final GoRouter router = GoRouter(
          initialLocation: RouteNames.salonMasterProfile,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.salonMasterProfile,
              builder: (_, _) => const SalonMasterProfileScreen(),
            ),
            GoRoute(
              path: RouteNames.salonMasterSchedule,
              builder: (_, _) => const Scaffold(
                body: SizedBox(key: Key('stub-staff-schedule')),
              ),
            ),
            GoRoute(
              path: RouteNames.masterSchedule,
              builder: (_, _) => const Scaffold(
                body: SizedBox(key: Key('stub-master-schedule')),
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: _overrides((_master, _services, _salon)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-2')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('stub-staff-schedule')), findsOneWidget);
        expect(find.byKey(const Key('stub-master-schedule')), findsNothing);
      },
    );
  });

  // Phase 321 — same shape as the Графік group above, for tile 0 instead of
  // tile 2: the REAL production wiring at this screen's own call site
  // (`salon_master_profile_screen.dart:232`'s `servicesRoute:` param), as
  // opposed to `salon_master_bottom_nav_redirect_test.dart`'s synthetic
  // router (which reconstructs its own `VelvetBottomNavBar` call and would
  // NOT catch a regression at THIS file's actual call site). Mutation-tested:
  // deleting this screen's `servicesRoute:` param turned this test red (tile
  // 0 landed on the INDEPENDENT_MASTER-only `/services` stub instead of
  // `/staff/services`), and the phase 321 integration flow independently red
  // on the same mutation.
  group('bottom nav — Послуги tile (Phase 321)', () {
    testWidgets(
      'tapping master-nav-tile-0 lands on RouteNames.salonMasterServices, '
      'NOT the default RouteNames.services',
      (tester) async {
        final GoRouter router = GoRouter(
          initialLocation: RouteNames.salonMasterProfile,
          routes: <RouteBase>[
            GoRoute(
              path: RouteNames.salonMasterProfile,
              builder: (_, _) => const SalonMasterProfileScreen(),
            ),
            GoRoute(
              path: RouteNames.salonMasterServices,
              builder: (_, _) => const Scaffold(
                body: SizedBox(key: Key('stub-staff-services')),
              ),
            ),
            GoRoute(
              path: RouteNames.services,
              builder: (_, _) =>
                  const Scaffold(body: SizedBox(key: Key('stub-services'))),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpRoutedApp(
          router,
          overrides: _overrides((_master, _services, _salon)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('master-nav-tile-0')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('stub-staff-services')), findsOneWidget);
        expect(find.byKey(const Key('stub-services')), findsNothing);
      },
    );
  });

  // Phase 367 fix — the own-avatar camera badge (and its 12 dp shadow blur)
  // ran into the salon / pin rows at 320 dp × 1.3 once the column grew down
  // to it.
  group('identity card — avatar badge clears the text column', () {
    testWidgets('salon name + address at 320dp × textScaler 1.3', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: _overrides((_master, _services, _salon)),
        width: 320,
        textScaleFactor: 1.3,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-master-profile-salon-name')),
        findsOneWidget,
        reason:
            'the salon row must render, or the column is too short to '
            'reach the badge and the guard is vacuous',
      );
      expectBadgeClearsTextColumn(
        tester,
        editorKey: const Key('salon-master-profile-avatar-editor'),
        nameKey: const Key('salon-master-profile-name'),
      );
    });
  });

  _avatarUploadNoReloadTests();
}

// ---------------------------------------------------------------------------
// Phase 367 fix — an own-avatar upload must NOT reload the salon-master
// loader. Mirrors `owner_own_profile_screen_test.dart`'s frame-by-frame test;
// here the photo itself is read from the master row (`masterProfileProvider`),
// so the test also pins that the NEW photo renders.
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _MockSalonRepository extends Mock implements SalonRepository {}

const User _salonMasterUser = User(
  id: 'u-9',
  email: 'master@beautica.test',
  role: UserRole.salonMaster,
  firstName: 'Ірина',
  lastName: 'Бондар',
);

class _AvatarAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _salonMasterUser, accessToken: 't');
}

/// `/masters/me` that records every build — a refetch shows up in [log].
class _CountingMasterProfile extends MasterProfile {
  _CountingMasterProfile(this.log, this.master);

  final List<String> log;
  final Master master;

  @override
  Future<Master> build() async {
    log.add('masters/me');
    return master;
  }
}

/// `POST /media/avatar` whose result the test completes by hand.
class _HeldUploads implements MediaUploadRepository {
  final List<File> uploaded = <File>[];
  final Completer<String> result = Completer<String>();

  @override
  UploadTask<String> uploadAvatar(File file) {
    uploaded.add(file);
    return UploadTask<String>(
      progress: const Stream<double>.empty(),
      result: result.future,
      onCancel: () {},
    );
  }

  @override
  Future<void> deleteAvatar() async {}

  // Phase 369 — salon logo / cover: not exercised by this file.
  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) =>
      throw UnimplementedError();
}

void _avatarUploadNoReloadTests() {
  const String oldUrl = 'https://media.test/avatars/u9/old.jpg';
  const String newUrl = 'https://media.test/avatars/u9/new.jpg';

  group('own-avatar upload keeps the loaded body (Phase 367 fix)', () {
    testWidgets('the skeleton never appears between the upload completing and '
        'the new photo rendering; nothing is refetched', (tester) async {
      final Directory scratch = Directory.systemTemp.createTempSync('sm_av');
      final Directory outside = Directory.systemTemp.createTempSync('sm_av_o');
      addTearDown(() {
        scratch.deleteSync(recursive: true);
        outside.deleteSync(recursive: true);
      });
      final ScriptedPickGateway gw = ScriptedPickGateway(
        scratch: scratch,
        outside: outside,
      );
      final _HeldUploads uploads = _HeldUploads();
      final List<String> log = <String>[];

      // FALSIFIER: the first services / salon read answers; any later one
      // PARKS forever. A loader rebuilt by the avatar patch would re-issue
      // them and sit in `AsyncLoading` — the skeleton — on every frame below.
      final serviceRepo = _MockServiceRepository();
      var servicesCalls = 0;
      when(() => serviceRepo.getMasterServices(any())).thenAnswer((_) {
        servicesCalls++;
        return servicesCalls == 1
            ? Future<List<MasterService>>.value(_services)
            : Completer<List<MasterService>>().future;
      });
      final salonRepo = _MockSalonRepository();
      var salonCalls = 0;
      when(() => salonRepo.getSalonById(any())).thenAnswer((_) {
        salonCalls++;
        return salonCalls == 1
            ? Future<Salon>.value(_salon)
            : Completer<Salon>().future;
      });

      await tester.pumpApp(
        const SalonMasterProfileScreen(),
        overrides: <Object>[
          authProvider.overrideWith(_AvatarAuth.new),
          // cycle-stub-ok: leaf data dep of the loader under test.
          masterProfileProvider.overrideWith(
            () => _CountingMasterProfile(
              log,
              _master.copyWith(avatarUrl: oldUrl),
            ),
          ),
          publicServiceRepositoryProvider.overrideWithValue(serviceRepo),
          salonRepositoryProvider.overrideWithValue(salonRepo),
          approvedCategoriesProvider.overrideWith(
            (ref) async => const <ServiceCategoryOption>[],
          ),
          mediaPickServiceProvider.overrideWithValue(
            MediaPickService(gw, tempDir: () async => scratch),
          ),
          mediaUploadRepositoryProvider.overrideWithValue(uploads),
          secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-master-profile-name')),
        findsOneWidget,
      );
      expect((servicesCalls, salonCalls), (1, 1));
      expect(log.where((String e) => e == 'masters/me'), hasLength(1));

      final Finder editor = find.descendant(
        of: find.byKey(const Key('salon-master-profile-avatar-editor')),
        matching: find.byType(NeumorphicAvatarEditor),
        matchRoot: true,
      );
      expect(
        tester.widget<NeumorphicAvatarEditor>(editor).imageUrl,
        oldUrl,
        reason:
            'the photo is read from masterProfileProvider, not the '
            'avatar-stripped loader record',
      );

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(SalonMasterProfileScreen)),
      );
      final List<AsyncValue<SalonMasterOwnProfileData>> states =
          <AsyncValue<SalonMasterOwnProfileData>>[];
      final ProviderSubscription<AsyncValue<SalonMasterOwnProfileData>> sub =
          container.listen(
            salonMasterOwnProfileProvider,
            (_, AsyncValue<SalonMasterOwnProfileData> next) => states.add(next),
          );
      addTearDown(sub.close);

      // The pick / crop / compress steps do real file IO, so the flow runs
      // in the real zone; frames are pumped between its event-loop turns.
      AvatarChangeResult? result;
      await tester.runAsync(() async {
        unawaited(
          container
              .read(avatarUploadControllerProvider.notifier)
              .change(ImageSourceChoice.gallery)
              .then((AvatarChangeResult r) => result = r),
        );
        for (var i = 0; i < 5000 && uploads.uploaded.isEmpty; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      expect(uploads.uploaded, hasLength(1), reason: 'sanity: upload started');
      await tester.pump();

      uploads.result.complete(newUrl);

      var frames = 0;
      while (true) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        // fixed-wait-ok: one 16 ms FRAME per iteration — the test asserts on
        // every frame; the loop itself waits on the condition below.
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        expect(
          find.byType(SkeletonBlock),
          findsNothing,
          reason: 'frame $frames: the loading skeleton flashed',
        );
        expect(find.byType(ErrorState), findsNothing);
        expect(
          find.byKey(const Key('salon-master-profile-name')),
          findsOneWidget,
        );
        final NeumorphicAvatarEditor e = tester.widget(editor);
        if (result != null && e.imageUrl == newUrl && e.previewFile == null) {
          break;
        }
        if (frames > 400) fail('the new photo never rendered');
      }

      expect(result, isA<AvatarChangeSucceeded>());
      expect(
        container.read(masterProfileProvider).value?.avatarUrl,
        newUrl,
        reason: 'the cached master row is patched in place',
      );
      expect(
        states.where((AsyncValue<SalonMasterOwnProfileData> s) => s.isLoading),
        isEmpty,
        reason: 'an avatar-only patch must not rebuild the salon-master loader',
      );
      expect((servicesCalls, salonCalls), (1, 1), reason: 'no refetch');
      expect(log.where((String e) => e == 'masters/me'), hasLength(1));
    });
  });
}
