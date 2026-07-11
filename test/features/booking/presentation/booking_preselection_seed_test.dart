// Widget tests — the booking Step-1 catalogue PRE-CHECKS the search
// pre-selection by EXACT serviceTypeSlug match AND HOISTS the matched
// service's CATEGORY to the top of the accordion, all WITHOUT tripping
// Riverpod's "modify a provider while the widget tree was building" crash.
//
// Pins the BOOKING half of the search→booking handoff (the discovery half is in
// test/features/discovery/presentation/widgets/result_card_preselection_test.dart):
//   • ServiceSelectorSheet (independent-master flow) and
//     SalonServiceSelectionScreen (salon flow) each PEEK (read-only) the pending
//     payload in initState and pre-check EVERY catalogue service whose
//     serviceTypeSlug exactly matches — matched tiles checked, siblings with a
//     different slug left unchecked (no false positives);
//   • the CATEGORY that contains a matched service is HOISTED to the TOP of the
//     accordion (stable partition — matched categories first, in their original
//     relative order, then everything else) and auto-EXPANDED, so the searched
//     service is visible immediately IN ITS NORMAL CATEGORY ROW alongside all
//     its sibling services (the matched one merely pre-checked). This REPLACES
//     the removed "pinned «Обрана послуга» top section" behaviour — the matched
//     service is no longer pulled out into a separate pinned shelf;
//   • the one-shot CLEAR is deferred to a post-frame callback, so after the
//     first frame the provider is null (backing out + re-entering does NOT
//     re-preselect);
//   • a payload whose targetId is a DIFFERENT provider pre-checks nothing and
//     hoists nothing.
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
// "Hoisted to the top" is asserted via the vertical position of the category
// SECTION keys (`booking_category_<CAT>` / `salon_booking_category_<CAT>`).

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

/// Any selected check-control face anywhere in the tree — `findsNothing` proves
/// the whole catalogue pre-checked nothing.
final Finder _anyCheckedFace = find.byKey(const ValueKey<bool>(true));

/// Top-of-widget Y coordinate — used to assert accordion category ORDER (a
/// hoisted category sits above the others). Both flows key the whole category
/// SECTION, so `getTopLeft` of the section key is the section's top.
double _topY(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

/// Asserts [upper] renders strictly ABOVE [lower] (smaller Y). Both must exist.
void _expectAbove(
  WidgetTester tester,
  Finder upper,
  Finder lower, {
  required String reason,
}) {
  expect(upper, findsOneWidget, reason: reason);
  expect(lower, findsOneWidget, reason: reason);
  expect(_topY(tester, upper) < _topY(tester, lower), isTrue, reason: reason);
}

void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ===========================================================================
// ServiceSelectorSheet (independent-master flow) fixtures
//
// THREE categories in first-appearance order — HAIR, NAILS, BROWS — so hoisting
// the matched service's category to the TOP visibly REORDERS the accordion
// (HAIR is naturally first; matching a NAILS/BROWS service must lift it above
// HAIR). NAILS holds two DIFFERENT-slug services so the exact-slug match can be
// asserted positively (svc-match) AND negatively (its unchecked sibling
// svc-other) inside the same auto-expanded category.
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

// Category HAIR (first in natural order) — never matched by the seeds; proves
// the hoist actually reorders (HAIR drops below the matched categories).
const _kSvcHair = MasterService(
  id: 'svc-hair',
  serviceDefId: 'def-hair',
  name: 'Стрижка жіноча',
  durationMinutes: 45,
  priceMin: 300,
  priceDisplay: '300 грн',
  category: 'HAIR',
  serviceTypeSlug: 'WOMENS_HAIRCUT',
  serviceTypeNameUk: 'Жіноча стрижка',
);

// Category NAILS — the exact-slug MATCH plus its different-slug sibling.
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

// Category BROWS — matched only by the multi-category seed (proves multiple
// matched categories BOTH hoist).
const _kSvcBrow = MasterService(
  id: 'svc-brow',
  serviceDefId: 'def-brow',
  name: 'Корекція брів',
  durationMinutes: 30,
  priceMin: 250,
  priceDisplay: '250 грн',
  category: 'BROWS',
  serviceTypeSlug: 'BROW_SHAPE',
  serviceTypeNameUk: 'Корекція брів',
);

PublicMasterProfileData get _masterData => (
  _kMaster,
  const <MasterService>[_kSvcHair, _kSvcMatch, _kSvcOther, _kSvcBrow],
);

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

// Two slugs in DIFFERENT categories (NAILS + BROWS) → both categories hoist.
const _kMasterMultiSeed = PendingServicePreselection(
  targetId: _kMasterId,
  serviceTypeSlugs: <String>{'CLASSIC_MANICURE', 'BROW_SHAPE'},
  serviceTypeLabels: <String>{},
);

final Finder _masterMatchTile = find.byKey(
  const Key('booking_service_tile_svc-match'),
);
final Finder _masterOtherTile = find.byKey(
  const Key('booking_service_tile_svc-other'),
);
final Finder _masterBrowTile = find.byKey(
  const Key('booking_service_tile_svc-brow'),
);
final Finder _masterHairTile = find.byKey(
  const Key('booking_service_tile_svc-hair'),
);

// Category SECTION finders (master flow: `booking_category_<UPPERCASE-SLUG>`).
final Finder _masterCatHair = find.byKey(const Key('booking_category_HAIR'));
final Finder _masterCatNails = find.byKey(const Key('booking_category_NAILS'));
final Finder _masterCatBrows = find.byKey(const Key('booking_category_BROWS'));

// ===========================================================================
// SalonServiceSelectionScreen (salon flow) fixtures — same 3-category shape.
// ===========================================================================

const String _kSalonId = 'salon-1';

const _kSalonHair = SalonCatalogService(
  id: 'salon-hair',
  name: 'Стрижка жіноча',
  durationLabel: '45 хв',
  priceDisplay: '300 грн',
  category: 'HAIR',
  serviceTypeSlug: 'WOMENS_HAIRCUT',
  serviceTypeNameUk: 'Жіноча стрижка',
  durationMinutes: 45,
  priceType: ServicePriceType.fixed,
  priceMin: 300,
);

const _kSalonMatch = SalonCatalogService(
  id: 'salon-match',
  name: 'Манікюр класичний',
  durationLabel: '1 год',
  priceDisplay: '400 грн',
  category: 'NAILS',
  serviceTypeSlug: 'CLASSIC_MANICURE',
  serviceTypeNameUk: 'Класичний манікюр',
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
  serviceTypeNameUk: 'Манікюр гель-лак',
  durationMinutes: 90,
  priceType: ServicePriceType.fixed,
  priceMin: 600,
);

const _kSalonBrow = SalonCatalogService(
  id: 'salon-brow',
  name: 'Корекція брів',
  durationLabel: '30 хв',
  priceDisplay: '250 грн',
  category: 'BROWS',
  serviceTypeSlug: 'BROW_SHAPE',
  serviceTypeNameUk: 'Корекція брів',
  durationMinutes: 30,
  priceType: ServicePriceType.fixed,
  priceMin: 250,
);

const _kSalonCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'HAIR',
    displayName: 'Волосся',
    count: 1,
    services: <SalonCatalogService>[_kSalonHair],
  ),
  SalonServiceCategoryEntry(
    category: 'NAILS',
    displayName: 'Манікюр',
    count: 2,
    services: <SalonCatalogService>[_kSalonMatch, _kSalonOther],
  ),
  SalonServiceCategoryEntry(
    category: 'BROWS',
    displayName: 'Брови',
    count: 1,
    services: <SalonCatalogService>[_kSalonBrow],
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

// Two slugs in DIFFERENT categories (NAILS + BROWS) → both categories hoist.
const _kSalonMultiSeed = PendingServicePreselection(
  targetId: _kSalonId,
  serviceTypeSlugs: <String>{'CLASSIC_MANICURE', 'BROW_SHAPE'},
  serviceTypeLabels: <String>{},
);

final Finder _salonMatchTile = find.byKey(
  const Key('salon_booking_service_tile_salon-match'),
);
final Finder _salonOtherTile = find.byKey(
  const Key('salon_booking_service_tile_salon-other'),
);
final Finder _salonBrowTile = find.byKey(
  const Key('salon_booking_service_tile_salon-brow'),
);
final Finder _salonHairTile = find.byKey(
  const Key('salon_booking_service_tile_salon-hair'),
);

// Category SECTION finders (salon flow: `salon_booking_category_<RAW-SLUG>`).
final Finder _salonCatHair = find.byKey(
  const Key('salon_booking_category_HAIR'),
);
final Finder _salonCatNails = find.byKey(
  const Key('salon_booking_category_NAILS'),
);
final Finder _salonCatBrows = find.byKey(
  const Key('salon_booking_category_BROWS'),
);

// ===========================================================================
// SalonServiceSelectionScreen — serviceTypeNameUk LABEL-FALLBACK regression
// ===========================================================================
//
// The FIXED bug: a salon service whose `serviceTypeSlug` is NULL (the
// service-type picker is optional, so this is common) must still pre-match a
// search filter via its `serviceTypeNameUk` — the underlying PLATFORM
// service-type name, the SAME namespace as `serviceTypeLabels`. The old code's
// fallback compared the salon's CUSTOM `name` ("Нарощення 2д класика") against
// the payload labels ("2д"), a namespace mismatch that never matched.
//
// A leading UNMATCHED category (HAIR) precedes the LASHES category so that
// hoisting LASHES to the top is OBSERVABLE (LASHES must sit above HAIR once a
// LASHES service matches). LASHES holds the exact-slug, name-fallback, and
// no-match branches in one auto-expanded view.

const String _kSalonFbId = 'salon-fb';

// Leading category — proves the matched LASHES category hoists above it.
const _kSalonFbLead = SalonCatalogService(
  id: 'salon-fb-lead',
  name: 'Стрижка',
  durationLabel: '45 хв',
  priceDisplay: '300 грн',
  category: 'HAIR',
  serviceTypeSlug: 'WOMENS_HAIRCUT',
  serviceTypeNameUk: 'Жіноча стрижка',
  durationMinutes: 45,
  priceType: ServicePriceType.fixed,
  priceMin: 300,
);

// (a) EXACT-SLUG branch — matches on serviceTypeSlug 'nc-2d'.
const _kSalonFbSlug = SalonCatalogService(
  id: 'salon-fb-slug',
  name: 'Нарощення 2д преміум',
  durationLabel: '2 год',
  priceDisplay: '900 грн',
  category: 'LASHES',
  serviceTypeSlug: 'nc-2d',
  serviceTypeNameUk: '2д',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 900,
);

// (b) THE FIXED BRANCH — slug is NULL; only the serviceTypeNameUk '2д' can
// match. Its CUSTOM name deliberately DIFFERS from the label, so the old
// `s.name`-based fallback ("Нарощення 2д класика" != "2д") would NOT match →
// this service would be left unchecked on the pre-fix code.
const _kSalonFbName = SalonCatalogService(
  id: 'salon-fb-name',
  name: 'Нарощення 2д класика',
  durationLabel: '2 год',
  priceDisplay: '850 грн',
  category: 'LASHES',
  serviceTypeSlug: null,
  serviceTypeNameUk: '2д',
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 850,
);

// (c) NO-MATCH — a DIFFERENT slug AND a DIFFERENT serviceTypeNameUk.
const _kSalonFbNone = SalonCatalogService(
  id: 'salon-fb-none',
  name: 'Ламінування вій',
  durationLabel: '1 год',
  priceDisplay: '500 грн',
  category: 'LASHES',
  serviceTypeSlug: 'lash-lam',
  serviceTypeNameUk: 'Ламінування',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
);

const _kSalonFbCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'HAIR',
    displayName: 'Волосся',
    count: 1,
    services: <SalonCatalogService>[_kSalonFbLead],
  ),
  SalonServiceCategoryEntry(
    category: 'LASHES',
    displayName: 'Нарощення вій',
    count: 3,
    services: <SalonCatalogService>[
      _kSalonFbSlug,
      _kSalonFbName,
      _kSalonFbNone,
    ],
  ),
];

List<Object> get _salonFbDataOverrides => <Object>[
  salonServiceCatalogProvider(
    _kSalonFbId,
  ).overrideWith((ref) async => _kSalonFbCatalog),
];

// Payload: slug 'nc-2d' matches (a); label '2д' matches (b) via the fallback.
const _kSalonFbSeed = PendingServicePreselection(
  targetId: _kSalonFbId,
  serviceTypeSlugs: <String>{'nc-2d'},
  serviceTypeLabels: <String>{'2д'},
);

final Finder _salonFbSlugTile = find.byKey(
  const Key('salon_booking_service_tile_salon-fb-slug'),
);
final Finder _salonFbNameTile = find.byKey(
  const Key('salon_booking_service_tile_salon-fb-name'),
);
final Finder _salonFbNoneTile = find.byKey(
  const Key('salon_booking_service_tile_salon-fb-none'),
);
final Finder _salonFbCatHair = find.byKey(
  const Key('salon_booking_category_HAIR'),
);
final Finder _salonFbCatLashes = find.byKey(
  const Key('salon_booking_category_LASHES'),
);

// Negative fixture — the ONLY service has slug null AND serviceTypeNameUk null,
// so NEITHER branch can match. The label fallback needs a non-empty name.
const _kSalonFbBlank = SalonCatalogService(
  id: 'salon-fb-blank',
  name: 'Нарощення 2д класика',
  durationLabel: '2 год',
  priceDisplay: '850 грн',
  category: 'LASHES',
  serviceTypeSlug: null,
  serviceTypeNameUk: null,
  durationMinutes: 120,
  priceType: ServicePriceType.fixed,
  priceMin: 850,
);

const _kSalonFbBlankCatalog = <SalonServiceCategoryEntry>[
  SalonServiceCategoryEntry(
    category: 'LASHES',
    displayName: 'Нарощення вій',
    count: 1,
    services: <SalonCatalogService>[_kSalonFbBlank],
  ),
];

List<Object> get _salonFbBlankDataOverrides => <Object>[
  salonServiceCatalogProvider(
    _kSalonFbId,
  ).overrideWith((ref) async => _kSalonFbBlankCatalog),
];

final Finder _salonFbBlankTile = find.byKey(
  const Key('salon_booking_service_tile_salon-fb-blank'),
);

void main() {
  group(
    'ServiceSelectorSheet — search pre-selection seeding (real provider)',
    () {
      testWidgets(
        'seeding a matching payload does NOT throw a provider-modified-during-'
        'build error, and pre-checks ONLY the matching-slug service inside its '
        'hoisted category (regression)',
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

          // CLASSIC_MANICURE matched svc-match → its NAILS category is HOISTED
          // above the naturally-first HAIR category and auto-EXPANDED, so the
          // matched tile renders IN its category (not a pinned section),
          // pre-checked, WITHOUT any manual tap.
          _expectAbove(
            tester,
            _masterCatNails,
            _masterCatHair,
            reason: 'the matched NAILS category must hoist above HAIR',
          );
          expect(_masterMatchTile, findsOneWidget);
          expect(
            _checkedFace(_masterMatchTile),
            findsOneWidget,
            reason:
                'CLASSIC_MANICURE matched svc-match → it must be pre-checked',
          );
          // The different-slug sibling renders in the SAME auto-expanded NAILS
          // category (proving the whole category is shown, not just the match)
          // and is NOT falsely pre-checked (exact-slug, no false positive).
          expect(
            _masterOtherTile,
            findsOneWidget,
            reason:
                'svc-other is a NAILS sibling of the match → it renders in the '
                'auto-expanded category without a manual tap',
          );
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

          // Nothing pending → no category is hoisted or auto-expanded (master
          // default collapses all), so NOTHING is pre-checked anywhere.
          expect(
            _masterCatNails,
            findsOneWidget,
            reason: 'the catalogue still renders its category accordion',
          );
          expect(
            _anyCheckedFace,
            findsNothing,
            reason: 're-entry after a consumed payload must pre-check nothing',
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'a payload targeting a DIFFERENT master pre-checks nothing and hoists '
        'nothing (no-match degrades to nothing)',
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

          // The mismatched payload was never captured → the accordion keeps its
          // natural order (HAIR first) and pre-checks nothing.
          _expectAbove(
            tester,
            _masterCatHair,
            _masterCatNails,
            reason: 'no match → natural order preserved (HAIR stays first)',
          );
          expect(
            _anyCheckedFace,
            findsNothing,
            reason: 'a payload for a different target must pre-check nothing',
          );
          expect(tester.takeException(), isNull);
        },
      );
    },
  );

  // =========================================================================
  // HOISTED category — master flow (replaces the removed pinned top section)
  // =========================================================================
  group('ServiceSelectorSheet — hoisted category pre-selection', () {
    testWidgets(
      'hoists the matched service category to the TOP, auto-expanded, with the '
      'matched service checked ALONGSIDE its rendered siblings',
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

        // NAILS hoisted above BOTH other categories (natural order was HAIR,
        // NAILS, BROWS → hoisted order NAILS, HAIR, BROWS).
        _expectAbove(
          tester,
          _masterCatNails,
          _masterCatHair,
          reason: 'matched NAILS must hoist above HAIR',
        );
        _expectAbove(
          tester,
          _masterCatNails,
          _masterCatBrows,
          reason: 'matched NAILS must hoist above BROWS',
        );

        // Auto-expanded: the matched tile AND its sibling both render with no
        // manual tap; the match is checked, the sibling is not.
        expect(_masterMatchTile, findsOneWidget);
        expect(_masterOtherTile, findsOneWidget);
        expect(_checkedFace(_masterMatchTile), findsOneWidget);
        expect(_checkedFace(_masterOtherTile), findsNothing);

        // The non-matched categories stay COLLAPSED (their tiles are not built).
        expect(_masterHairTile, findsNothing);
        expect(_masterBrowTile, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'multiple matches across categories → ALL matched categories hoist to the '
      'top, auto-expanded, and every unmatched category falls below',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_masterDataOverrides);
        _seed(c, _kMasterMultiSeed);

        await _pumpScreen(
          tester,
          c,
          const ServiceSelectorSheet(masterId: _kMasterId),
        );
        await tester.pumpAndSettle();

        // NAILS + BROWS both hoist above the unmatched HAIR (stable partition
        // keeps NAILS before BROWS — their original relative order).
        _expectAbove(
          tester,
          _masterCatNails,
          _masterCatBrows,
          reason: 'matched categories keep their original relative order',
        );
        _expectAbove(
          tester,
          _masterCatNails,
          _masterCatHair,
          reason: 'matched NAILS must hoist above unmatched HAIR',
        );
        _expectAbove(
          tester,
          _masterCatBrows,
          _masterCatHair,
          reason: 'matched BROWS must hoist above unmatched HAIR',
        );

        // Both matched services checked in their auto-expanded categories.
        expect(_checkedFace(_masterMatchTile), findsOneWidget);
        expect(_checkedFace(_masterBrowTile), findsOneWidget);
        // NAILS sibling rendered but unchecked; HAIR stays collapsed.
        expect(_masterOtherTile, findsOneWidget);
        expect(_checkedFace(_masterOtherTile), findsNothing);
        expect(_masterHairTile, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'no search pre-selection → normal category order, default (collapsed) '
      'expansion, nothing force-hoisted',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_masterDataOverrides);
        // Deliberately NOT seeded.

        await _pumpScreen(
          tester,
          c,
          const ServiceSelectorSheet(masterId: _kMasterId),
        );
        await tester.pumpAndSettle();

        // Natural first-appearance order, unchanged.
        _expectAbove(
          tester,
          _masterCatHair,
          _masterCatNails,
          reason: 'no preselection → HAIR keeps its natural first position',
        );
        _expectAbove(
          tester,
          _masterCatNails,
          _masterCatBrows,
          reason: 'no preselection → NAILS keeps its natural middle position',
        );
        // Master default collapses every category → no tiles built at all.
        expect(_masterMatchTile, findsNothing);
        expect(_anyCheckedFace, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'un-checking the matched service KEEPS its category hoisted + expanded '
      '(hoist = "your searched category", not check-state)',
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
        expect(_checkedFace(_masterMatchTile), findsOneWidget);

        // Tap the matched tile (in its hoisted category) to un-check it.
        await tester.tap(_masterMatchTile);
        await tester.pumpAndSettle();

        // Still hoisted to the top + still expanded (its sibling still renders)
        // …
        _expectAbove(
          tester,
          _masterCatNails,
          _masterCatHair,
          reason: 'un-checking must NOT un-hoist the category',
        );
        expect(
          _masterOtherTile,
          findsOneWidget,
          reason: 'un-checking must NOT collapse the category',
        );
        // … but the tile is now unchecked.
        expect(_checkedFace(_masterMatchTile), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('SalonServiceSelectionScreen — search pre-selection seeding (real '
      'provider)', () {
    testWidgets(
      'seeding a matching payload does NOT throw a provider-modified-during-'
      'build error, and pre-checks ONLY the matching-slug service inside its '
      'hoisted category (regression)',
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

        // CLASSIC_MANICURE matched salon-match → its NAILS category is HOISTED
        // above the naturally-first HAIR category and auto-EXPANDED, so the
        // matched tile renders IN its category, pre-checked, without a tap.
        _expectAbove(
          tester,
          _salonCatNails,
          _salonCatHair,
          reason: 'the matched NAILS category must hoist above HAIR',
        );
        expect(_salonMatchTile, findsOneWidget);
        expect(
          _checkedFace(_salonMatchTile),
          findsOneWidget,
          reason:
              'CLASSIC_MANICURE matched salon-match → it must be pre-checked',
        );
        // The different-slug sibling renders in the same auto-expanded NAILS
        // category and is NOT falsely pre-checked.
        expect(_salonOtherTile, findsOneWidget);
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
        // category (HAIR) in natural order, and NOTHING is pre-checked.
        _expectAbove(
          tester,
          _salonCatHair,
          _salonCatNails,
          reason: 're-entry keeps the natural category order (HAIR first)',
        );
        expect(
          _salonHairTile,
          findsOneWidget,
          reason: 'the default first-category expansion renders HAIR',
        );
        expect(
          _anyCheckedFace,
          findsNothing,
          reason: 're-entry after a consumed payload must pre-check nothing',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a payload targeting a DIFFERENT salon pre-checks nothing and hoists '
      'nothing (no-match degrades to nothing)',
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

        // Nothing captured → natural order + first-category default expansion,
        // nothing pre-checked.
        _expectAbove(
          tester,
          _salonCatHair,
          _salonCatNails,
          reason: 'a different-target payload leaves the natural order intact',
        );
        expect(_salonHairTile, findsOneWidget);
        expect(
          _anyCheckedFace,
          findsNothing,
          reason: 'a payload for a different salon must pre-check nothing',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  // =========================================================================
  // HOISTED category — salon flow (replaces the removed pinned top section)
  // =========================================================================
  group('SalonServiceSelectionScreen — hoisted category pre-selection', () {
    testWidgets(
      'hoists the matched service category to the TOP, auto-expanded, with the '
      'matched service checked ALONGSIDE its rendered siblings',
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

        _expectAbove(
          tester,
          _salonCatNails,
          _salonCatHair,
          reason: 'matched NAILS must hoist above HAIR',
        );
        _expectAbove(
          tester,
          _salonCatNails,
          _salonCatBrows,
          reason: 'matched NAILS must hoist above BROWS',
        );

        expect(_salonMatchTile, findsOneWidget);
        expect(_salonOtherTile, findsOneWidget);
        expect(_checkedFace(_salonMatchTile), findsOneWidget);
        expect(_checkedFace(_salonOtherTile), findsNothing);
        // Non-matched categories stay collapsed.
        expect(_salonHairTile, findsNothing);
        expect(_salonBrowTile, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'multiple matches across categories → ALL matched categories hoist to the '
      'top, auto-expanded, and every unmatched category falls below',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_salonDataOverrides);
        _seed(c, _kSalonMultiSeed);

        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonId),
        );
        await tester.pumpAndSettle();

        _expectAbove(
          tester,
          _salonCatNails,
          _salonCatBrows,
          reason: 'matched categories keep their original relative order',
        );
        _expectAbove(
          tester,
          _salonCatNails,
          _salonCatHair,
          reason: 'matched NAILS must hoist above unmatched HAIR',
        );
        _expectAbove(
          tester,
          _salonCatBrows,
          _salonCatHair,
          reason: 'matched BROWS must hoist above unmatched HAIR',
        );

        expect(_checkedFace(_salonMatchTile), findsOneWidget);
        expect(_checkedFace(_salonBrowTile), findsOneWidget);
        expect(_salonOtherTile, findsOneWidget);
        expect(_checkedFace(_salonOtherTile), findsNothing);
        expect(_salonHairTile, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'no search pre-selection → normal category order with the default '
      'first-category expansion, nothing force-hoisted',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_salonDataOverrides);
        // Deliberately NOT seeded.

        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonId),
        );
        await tester.pumpAndSettle();

        // Natural order preserved; the salon default expands the FIRST category
        // (HAIR), so its tile renders and NOTHING is pre-checked.
        _expectAbove(
          tester,
          _salonCatHair,
          _salonCatNails,
          reason: 'no preselection → HAIR keeps its natural first position',
        );
        expect(_salonHairTile, findsOneWidget);
        expect(_checkedFace(_salonHairTile), findsNothing);
        // NAILS is not force-expanded → its match tile is not built.
        expect(_salonMatchTile, findsNothing);
        expect(_anyCheckedFace, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'un-checking the matched service KEEPS its category hoisted + expanded',
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
        expect(_checkedFace(_salonMatchTile), findsOneWidget);

        await tester.tap(_salonMatchTile);
        await tester.pumpAndSettle();

        _expectAbove(
          tester,
          _salonCatNails,
          _salonCatHair,
          reason: 'un-checking must NOT un-hoist the category',
        );
        expect(
          _salonOtherTile,
          findsOneWidget,
          reason: 'un-checking must NOT collapse the category',
        );
        expect(_checkedFace(_salonMatchTile), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // =========================================================================
  // REGRESSION — salon serviceTypeNameUk LABEL FALLBACK (slug-null services)
  //
  // The just-fixed bug: a searched service whose salon catalogue entry has NO
  // serviceTypeSlug was never pre-checked because the fallback compared the
  // salon's CUSTOM `name` against the payload's service-type labels — a
  // namespace mismatch. The fix carries `serviceTypeNameUk` on
  // SalonCatalogService and falls back on IT (mirroring the master path). The
  // matched service now lands (checked) inside its HOISTED, auto-expanded
  // category, no longer a pinned section.
  // =========================================================================
  group('SalonServiceSelectionScreen — serviceTypeNameUk label-fallback '
      'preselection (slug-null regression)', () {
    testWidgets(
      'a slug-NULL salon service matches on serviceTypeNameUk (NOT its custom '
      'name) → checked inside the hoisted LASHES category alongside the '
      'exact-slug match; the no-match sibling stays unchecked',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_salonFbDataOverrides);
        _seed(c, _kSalonFbSeed);

        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonFbId),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'peekFor in initState must not mutate during build',
        );

        // LASHES (holding both matched services) hoists above the naturally-
        // first, unmatched HAIR category and auto-expands (all three LASHES
        // tiles render without a manual tap).
        _expectAbove(
          tester,
          _salonFbCatLashes,
          _salonFbCatHair,
          reason: 'the matched LASHES category must hoist above HAIR',
        );

        // (a) EXACT-SLUG branch: nc-2d matched → checked in-category.
        expect(_salonFbSlugTile, findsOneWidget);
        expect(_checkedFace(_salonFbSlugTile), findsOneWidget);

        // (b) THE FIXED BRANCH: slug is null; the '2д' label matched the
        // serviceTypeNameUk ('2д'), NOT the custom name ('Нарощення 2д
        // класика'). On the OLD code (which compared `s.name`) this tile
        // would NOT match → BOTH expects below would FAIL.
        expect(
          _salonFbNameTile,
          findsOneWidget,
          reason:
              'slug-null service must render in the auto-expanded LASHES '
              'category',
        );
        expect(
          _checkedFace(_salonFbNameTile),
          findsOneWidget,
          reason:
              'slug-null service must match via serviceTypeNameUk "2д" (the '
              'fixed fallback), not its custom name "Нарощення 2д класика" — '
              'this is the exact branch the bug broke and this assertion FAILS '
              'on the old s.name code',
        );

        // (c) NO-MATCH sibling renders in the same auto-expanded category but
        // stays UNCHECKED (no false positive) — no manual expand needed now.
        expect(_salonFbNoneTile, findsOneWidget);
        expect(
          _checkedFace(_salonFbNoneTile),
          findsNothing,
          reason: 'lash-lam / "Ламінування" matched neither slug nor label',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a slug-NULL service whose serviceTypeNameUk is ALSO null matches '
      'nothing → no category is hoisted and nothing is pre-checked (label '
      'fallback needs a non-empty name)',
      (tester) async {
        _tallSurface(tester);
        final ProviderContainer c = _makeContainer(_salonFbBlankDataOverrides);
        _seed(c, _kSalonFbSeed);

        await _pumpScreen(
          tester,
          c,
          const SalonServiceSelectionScreen(salonId: _kSalonFbId),
        );
        await tester.pumpAndSettle();

        // slug null AND serviceTypeNameUk null → the fallback label is empty →
        // nothing matches → no forced hoist; the flow falls back to expanding
        // the first category, so the blank service renders — and stays
        // unchecked.
        expect(
          _salonFbBlankTile,
          findsOneWidget,
          reason: 'the default first-category expansion renders the service',
        );
        expect(
          _anyCheckedFace,
          findsNothing,
          reason: 'nothing matched → nothing must be pre-checked',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
