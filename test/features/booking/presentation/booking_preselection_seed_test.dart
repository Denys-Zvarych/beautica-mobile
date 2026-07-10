// Widget tests — the booking Step-1 catalogue PRE-CHECKS the search
// pre-selection by EXACT serviceTypeSlug match, AND does so WITHOUT tripping
// Riverpod's "modify a provider while the widget tree was building" crash.
//
// Pins the BOOKING half of the search→booking handoff (the discovery half is in
// test/features/discovery/presentation/widgets/result_card_preselection_test.dart):
//   • ServiceSelectorSheet (independent-master flow) and
//     SalonServiceSelectionScreen (salon flow) each PEEK (read-only) the pending
//     payload in initState and pre-check EVERY catalogue service whose
//     serviceTypeSlug exactly matches — matched tiles checked, siblings with a
//     different slug left unchecked (no false positives);
//   • the one-shot CLEAR is deferred to a post-frame callback, so after the
//     first frame the provider is null (backing out + re-entering does NOT
//     re-preselect);
//   • a payload whose targetId is a DIFFERENT provider pre-checks nothing.
//
// SEEDING — the REAL controller, deliberately (regression discipline):
//   The pending payload is seeded by calling the REAL
//   PendingServicePreselectionController.set(...) on a fresh ProviderContainer
//   BEFORE the screen mounts, then pumping the screen inside an
//   UncontrolledProviderScope over that same container. The screen therefore
//   exercises the TRUE production path: its initState `peekFor` reads real
//   state, and its deferred `clear()` performs a real `state = null` write.
//
//   This REPLACES a prior non-writing test double (`_SeededPreselection
//   Controller`) that overrode `consumeFor` to RETURN the seed WITHOUT the
//   one-shot `state = null` write. That double MASKED the very bug this file now
//   guards: the screens used to call `consumeFor` (which writes) from initState,
//   a provider mutation DURING the build phase that throws "Tried to modify a
//   provider while the widget tree was building" — but only on the matching-
//   payload branch, so the non-writing double never reproduced it. The fix
//   split `peekFor` (read-only, initState) from the deferred `clear()`; a test
//   that hides the write can never catch a regression of that split, so the
//   double is gone.
//
// THE REGRESSION ASSERTION: `expect(tester.takeException(), isNull)` after
// pump + settle on the matching-payload path. On the OLD code (consumeFor in
// initState) this FAILS with the provider-modified-during-build FlutterError;
// on the fixed code it PASSES. That is the "test for this type of error".
//
// "Checked" is asserted via the selected check-control face
// (`ValueKey<bool>(true)`) the accordion renders only when a tile is selected —
// the same idiom service_selector_sheet_test.dart / the salon booking E2E use.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/pending_service_preselection_provider.dart';
import 'package:beautica_mobile/features/booking/domain/pending_service_preselection.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_service_selection_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/service_selector_sheet.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/overflow_guard.dart';

// ---------------------------------------------------------------------------
// Auth stub — the REAL PendingServicePreselectionController.build()
// `ref.watch(authProvider)`s (to self-clear on a session flip), so the
// container must supply a settled auth graph. Mirrors
// pending_service_preselection_provider_test.dart's `_make` harness.
// ---------------------------------------------------------------------------
const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _session = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _session;
    return _session.value;
  }
}

/// Builds a fresh container wired with the auth stub + the screen's data
/// overrides, disposed in `addTearDown`. Retry is disabled so no failed-build
/// backoff Timer can leak (all overrides resolve successfully here, but this
/// keeps the harness robust).
ProviderContainer _makeContainer(List<Object> dataOverrides) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: <Object>[
      authProvider.overrideWith(_FixedAuthNotifier.new),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ...dataOverrides,
    ].cast(),
  );
  addTearDown(container.dispose);
  return container;
}

/// Seeds the REAL controller with [seed] (a real `set(...)` write) so the
/// screen's initState `peekFor` reads real state.
void _seed(ProviderContainer c, PendingServicePreselection seed) {
  c
      .read(pendingServicePreselectionControllerProvider.notifier)
      .set(
        targetId: seed.targetId,
        serviceTypeSlugs: seed.serviceTypeSlugs,
        serviceTypeLabels: seed.serviceTypeLabels,
      );
}

/// Current provider state (null once the one-shot clear has run).
PendingServicePreselection? _preselectionState(ProviderContainer c) =>
    c.read(pendingServicePreselectionControllerProvider);

/// Pumps [screen] inside an [UncontrolledProviderScope] over [c] with l10n +
/// the overflow guard — the real production wiring, minus a router (the
/// screens only touch go_router in tap callbacks, none of which these tests
/// fire).
Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer c,
  Widget screen,
) async {
  installOverflowGuard();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: screen,
      ),
    ),
  );
}

/// Presence of the accordion's selected check-control face under [tile].
Finder _checkedFace(Finder tile) =>
    find.descendant(of: tile, matching: find.byKey(const ValueKey<bool>(true)));

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ===========================================================================
// ServiceSelectorSheet (independent-master flow) fixtures
// ===========================================================================

const String _kMasterId = 'master-1';

const _kMaster = Master(
  id: _kMasterId,
  firstName: 'Софія',
  lastName: 'Бондар',
  avgRating: 4.9,
  reviewCount: 24,
  type: MasterType.independentMaster,
);

// Two services in the SAME category (NAILS) with DIFFERENT service-type slugs,
// so both tiles render once NAILS is expanded and the exact-slug match can be
// asserted positively AND negatively in one view.
const _kSvcMatch = MasterService(
  id: 'svc-match',
  serviceDefId: 'def-match',
  name: 'Манікюр класичний',
  durationMinutes: 60,
  priceMin: 400,
  priceDisplay: '400 грн',
  category: 'NAILS',
  serviceTypeSlug: 'CLASSIC_MANICURE',
  serviceTypeNameUk: 'Класичний манікюр',
);

const _kSvcOther = MasterService(
  id: 'svc-other',
  serviceDefId: 'def-other',
  name: 'Манікюр гель-лак',
  durationMinutes: 90,
  priceMin: 600,
  priceDisplay: '600 грн',
  category: 'NAILS',
  serviceTypeSlug: 'GEL_MANICURE',
  serviceTypeNameUk: 'Манікюр гель-лак',
);

PublicMasterProfileData get _masterData =>
    (_kMaster, const <MasterService>[_kSvcMatch, _kSvcOther]);

List<Object> get _masterDataOverrides => <Object>[
  publicMasterProfileProvider(_kMasterId).overrideWith((ref) => _masterData),
  // Footgun (approvedCategoriesProvider override): it sources from the real
  // Dio-backed request api, not the service repository — override it DIRECTLY
  // or it fires a real network request (and leaks a Dio timer).
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

const _kMasterMatchSeed = PendingServicePreselection(
  targetId: _kMasterId,
  serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
  serviceTypeLabels: <String>{'Класичний манікюр'},
);

final Finder _masterMatchTile = find.byKey(
  const Key('booking_service_tile_svc-match'),
);
final Finder _masterOtherTile = find.byKey(
  const Key('booking_service_tile_svc-other'),
);

// ===========================================================================
// SalonServiceSelectionScreen (salon flow) fixtures
// ===========================================================================

const String _kSalonId = 'salon-1';

const _kSalonMatch = SalonCatalogService(
  id: 'salon-match',
  name: 'Манікюр класичний',
  durationLabel: '1 год',
  priceDisplay: '400 грн',
  category: 'NAILS',
  serviceTypeSlug: 'CLASSIC_MANICURE',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 400,
);

const _kSalonOther = SalonCatalogService(
  id: 'salon-other',
  name: 'Манікюр гель-лак',
  durationLabel: '1 год 30 хв',
  priceDisplay: '600 грн',
  category: 'NAILS',
  serviceTypeSlug: 'GEL_MANICURE',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 600,
);

const _kSalonCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'NAILS',
    displayName: 'Манікюр',
    count: 2,
    services: <SalonCatalogService>[_kSalonMatch, _kSalonOther],
  ),
];

List<Object> get _salonDataOverrides => <Object>[
  salonServiceCatalogProvider(
    _kSalonId,
  ).overrideWith((ref) async => _kSalonCatalog),
];

const _kSalonMatchSeed = PendingServicePreselection(
  targetId: _kSalonId,
  serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
  serviceTypeLabels: <String>{'Класичний манікюр'},
);

final Finder _salonMatchTile = find.byKey(
  const Key('salon_booking_service_tile_salon-match'),
);
final Finder _salonOtherTile = find.byKey(
  const Key('salon_booking_service_tile_salon-other'),
);

void main() {
  group('ServiceSelectorSheet — search pre-selection seeding (real provider)', () {
    testWidgets(
      'seeding a matching payload does NOT throw a provider-modified-during-'
      'build error, and pre-checks ONLY the matching-slug service (regression)',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_masterDataOverrides);
        _seed(c, _kMasterMatchSeed);

        await _pumpScreen(
          tester,
          c,
          const ServiceSelectorSheet(masterId: _kMasterId),
        );
        await tester.pumpAndSettle();

        // CORE REGRESSION GUARD: the OLD code called consumeFor (a provider
        // WRITE) from initState → Riverpod's "modify a provider while the
        // widget tree was building" FlutterError. With peekFor + deferred
        // clear this stays null.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'peekFor in initState must NOT mutate the provider during the '
              'build phase (the consumeFor-in-initState crash this guards)',
        );

        // The matched service\'s category (NAILS) was auto-expanded, so BOTH
        // tiles render …
        expect(_masterMatchTile, findsOneWidget);
        expect(_masterOtherTile, findsOneWidget);
        // … the exact-slug match is CHECKED …
        expect(
          _checkedFace(_masterMatchTile),
          findsOneWidget,
          reason: 'CLASSIC_MANICURE matched svc-match → it must be pre-checked',
        );
        // … and the different-slug sibling is NOT.
        expect(
          _checkedFace(_masterOtherTile),
          findsNothing,
          reason:
              'GEL_MANICURE did not match the filter → svc-other must stay '
              'unchecked (exact-slug, no false positive)',
        );
      },
    );

    testWidgets(
      'the deferred one-shot clear nulls the provider after the first frame',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_masterDataOverrides);
        _seed(c, _kMasterMatchSeed);

        await _pumpScreen(
          tester,
          c,
          const ServiceSelectorSheet(masterId: _kMasterId),
        );
        await tester.pumpAndSettle();

        expect(
          _preselectionState(c),
          isNull,
          reason:
              'the post-frame clear() must consume the payload exactly once so '
              'a later booking never re-reads it',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      're-mounting the booking screen does not re-preselect (payload already '
      'consumed by the deferred clear)',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_masterDataOverrides);
        _seed(c, _kMasterMatchSeed);

        // First mount consumes the payload …
        await _pumpScreen(
          tester,
          c,
          const ServiceSelectorSheet(masterId: _kMasterId),
        );
        await tester.pumpAndSettle();
        expect(_preselectionState(c), isNull);

        // … unmount, then re-mount a FRESH screen instance over the SAME
        // (now-cleared) container.
        await _pumpScreen(tester, c, const SizedBox.shrink());
        await tester.pumpAndSettle();
        await _pumpScreen(
          tester,
          c,
          const ServiceSelectorSheet(masterId: _kMasterId),
        );
        await tester.pumpAndSettle();

        // Nothing pending → no category auto-expanded. Expand NAILS manually
        // to bring the tiles into view and confirm NEITHER is pre-checked.
        await tester.tap(find.byKey(const Key('booking_category_NAILS')));
        await tester.pumpAndSettle();
        expect(_checkedFace(_masterMatchTile), findsNothing);
        expect(
          _checkedFace(_masterOtherTile),
          findsNothing,
          reason: 're-entry after a consumed payload must pre-check nothing',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a payload targeting a DIFFERENT master pre-checks nothing (no-match '
      'degrades to nothing)',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_masterDataOverrides);
        _seed(
          c,
          const PendingServicePreselection(
            targetId: 'some-other-master',
            serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
            serviceTypeLabels: <String>{},
          ),
        );

        await _pumpScreen(
          tester,
          c,
          const ServiceSelectorSheet(masterId: _kMasterId),
        );
        await tester.pumpAndSettle();

        // The mismatched payload was never captured → no category was
        // auto-expanded. Expand NAILS manually to bring the tiles into view.
        await tester.tap(find.byKey(const Key('booking_category_NAILS')));
        await tester.pumpAndSettle();

        expect(_checkedFace(_masterMatchTile), findsNothing);
        expect(
          _checkedFace(_masterOtherTile),
          findsNothing,
          reason: 'a payload for a different target must pre-check nothing',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('SalonServiceSelectionScreen — search pre-selection seeding (real '
      'provider)', () {
    testWidgets(
      'seeding a matching payload does NOT throw a provider-modified-during-'
      'build error, and pre-checks ONLY the matching-slug service (regression)',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_salonDataOverrides);
        _seed(c, _kSalonMatchSeed);

        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonId),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'peekFor in initState must NOT mutate the provider during the '
              'build phase (the consumeFor-in-initState crash this guards)',
        );

        expect(_salonMatchTile, findsOneWidget);
        expect(_salonOtherTile, findsOneWidget);
        expect(
          _checkedFace(_salonMatchTile),
          findsOneWidget,
          reason:
              'CLASSIC_MANICURE matched salon-match → it must be pre-checked',
        );
        expect(
          _checkedFace(_salonOtherTile),
          findsNothing,
          reason:
              'GEL_MANICURE did not match → salon-other must stay unchecked',
        );
      },
    );

    testWidgets(
      'the deferred one-shot clear nulls the provider after the first frame',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_salonDataOverrides);
        _seed(c, _kSalonMatchSeed);

        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonId),
        );
        await tester.pumpAndSettle();

        expect(
          _preselectionState(c),
          isNull,
          reason:
              'the post-frame clear() must consume the payload exactly once so '
              'a later booking never re-reads it',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      're-mounting the salon booking screen does not re-preselect (payload '
      'already consumed by the deferred clear)',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_salonDataOverrides);
        _seed(c, _kSalonMatchSeed);

        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonId),
        );
        await tester.pumpAndSettle();
        expect(_preselectionState(c), isNull);

        await _pumpScreen(tester, c, const SizedBox.shrink());
        await tester.pumpAndSettle();
        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonId),
        );
        await tester.pumpAndSettle();

        // No pre-selection → the salon flow falls back to expanding the FIRST
        // category (NAILS), so both tiles render …
        expect(_salonMatchTile, findsOneWidget);
        expect(_salonOtherTile, findsOneWidget);
        // … and NEITHER is pre-checked on re-entry.
        expect(_checkedFace(_salonMatchTile), findsNothing);
        expect(
          _checkedFace(_salonOtherTile),
          findsNothing,
          reason: 're-entry after a consumed payload must pre-check nothing',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a payload targeting a DIFFERENT salon pre-checks nothing (no-match '
      'degrades to nothing)',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_salonDataOverrides);
        _seed(
          c,
          const PendingServicePreselection(
            targetId: 'some-other-salon',
            serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
            serviceTypeLabels: <String>{},
          ),
        );

        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonId),
        );
        await tester.pumpAndSettle();

        // Nothing captured → the salon flow falls back to expanding the FIRST
        // category (NAILS), so both tiles are visible …
        expect(_salonMatchTile, findsOneWidget);
        expect(_salonOtherTile, findsOneWidget);
        // … and NEITHER is pre-checked.
        expect(_checkedFace(_salonMatchTile), findsNothing);
        expect(
          _checkedFace(_salonOtherTile),
          findsNothing,
          reason: 'a payload for a different salon must pre-check nothing',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
