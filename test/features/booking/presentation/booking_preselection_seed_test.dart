// Widget tests — the booking Step-1 catalogue PRE-CHECKS the search
// pre-selection by EXACT serviceTypeSlug match.
//
// Pins the BOOKING half of the search→booking handoff (the discovery half is in
// test/features/discovery/presentation/widgets/result_card_preselection_test.dart):
//   • ServiceSelectorSheet (independent-master flow) and
//     SalonServiceSelectionScreen (salon flow) each consume the pending payload
//     in initState and pre-check EVERY catalogue service whose serviceTypeSlug
//     exactly matches — matched tiles checked, siblings with a different slug
//     left unchecked (no false positives);
//   • a payload whose targetId is a DIFFERENT provider is not consumed → the
//     catalogue opens with nothing pre-checked (no-match degrades to nothing).
//
// SEEDING — a test double, deliberately:
//   pendingServicePreselectionControllerProvider is overridden with a subclass
//   whose consumeFor(targetId) RETURNS the seeded payload for a matching target
//   but does NOT perform the one-shot `state = null` write. That write is what
//   the screen calls from initState; doing it while the screen mounts under the
//   test's own ProviderScope build trips Riverpod's "modify a provider during
//   build" assert (a COLD-graph widget-test artifact — the production graph is
//   already warm from the result-card `set()`, so the real push tolerates it).
//   The one-shot / auth-clear semantics of the REAL controller are covered
//   exhaustively by pending_service_preselection_provider_test.dart; THIS tier
//   only needs the payload handed to the screen so the pre-check seeding —
//   `_seedOnce`'s exact-slug matching — can be asserted end to end in the tree.
//
// "Checked" is asserted via the selected check-control face
// (`ValueKey<bool>(true)`) the accordion renders only when a tile is selected —
// the same idiom service_selector_sheet_test.dart / the salon booking E2E use.

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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Seeded preselection double — see the file header. build() returns the seed
// (no auth watch); consumeFor returns the payload for a matching target WITHOUT
// the one-shot state write (that write is unit-tested separately).
// ---------------------------------------------------------------------------
class _SeededPreselectionController
    extends PendingServicePreselectionController {
  _SeededPreselectionController(this._seed);

  final PendingServicePreselection? _seed;

  @override
  PendingServicePreselection? build() => _seed;

  @override
  PendingServicePreselection? consumeFor(String targetId) {
    final PendingServicePreselection? s = _seed;
    if (s == null || s.targetId != targetId) return null;
    return s;
  }
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
// ServiceSelectorSheet (independent-master flow)
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

List<Object> _masterOverrides(PendingServicePreselection? seed) => <Object>[
  publicMasterProfileProvider(_kMasterId).overrideWith((ref) => _masterData),
  // Footgun: sources from the real Dio-backed request api, not the service
  // repository — override directly or it fires a real request.
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
  pendingServicePreselectionControllerProvider.overrideWith(
    () => _SeededPreselectionController(seed),
  ),
];

// ===========================================================================
// SalonServiceSelectionScreen (salon flow)
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

List<Object> _salonOverrides(PendingServicePreselection? seed) => <Object>[
  salonServiceCatalogProvider(
    _kSalonId,
  ).overrideWith((ref) async => _kSalonCatalog),
  pendingServicePreselectionControllerProvider.overrideWith(
    () => _SeededPreselectionController(seed),
  ),
];

void main() {
  group('ServiceSelectorSheet — search pre-selection seeding', () {
    testWidgets(
      'pre-checks ONLY the master service whose serviceTypeSlug matches; the '
      'sibling with a different slug stays unchecked',
      (tester) async {
        _tallSurface(tester);

        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: _kMasterId),
          overrides: _masterOverrides(
            const PendingServicePreselection(
              targetId: _kMasterId,
              serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
              serviceTypeLabels: <String>{'Класичний манікюр'},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The matched service's category (NAILS) was auto-expanded, so BOTH
        // tiles render …
        final Finder matchTile = find.byKey(
          const Key('booking_service_tile_svc-match'),
        );
        final Finder otherTile = find.byKey(
          const Key('booking_service_tile_svc-other'),
        );
        expect(matchTile, findsOneWidget);
        expect(otherTile, findsOneWidget);

        // … the exact-slug match is CHECKED …
        expect(
          _checkedFace(matchTile),
          findsOneWidget,
          reason: 'CLASSIC_MANICURE matched svc-match → it must be pre-checked',
        );
        // … and the different-slug sibling is NOT.
        expect(
          _checkedFace(otherTile),
          findsNothing,
          reason:
              'GEL_MANICURE did not match the filter → svc-other must '
              'stay unchecked (exact-slug, no false positive)',
        );
      },
    );

    testWidgets(
      'a payload targeting a DIFFERENT master pre-checks nothing (no-match '
      'degrades to nothing)',
      (tester) async {
        _tallSurface(tester);

        await tester.pumpApp(
          const ServiceSelectorSheet(masterId: _kMasterId),
          overrides: _masterOverrides(
            const PendingServicePreselection(
              targetId: 'some-other-master',
              serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
              serviceTypeLabels: <String>{},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The mismatched payload was never consumed → no category was
        // auto-expanded. Expand NAILS manually to bring the tiles into view.
        await tester.tap(find.byKey(const Key('booking_category_NAILS')));
        await tester.pumpAndSettle();

        expect(
          _checkedFace(find.byKey(const Key('booking_service_tile_svc-match'))),
          findsNothing,
        );
        expect(
          _checkedFace(find.byKey(const Key('booking_service_tile_svc-other'))),
          findsNothing,
          reason: 'a payload for a different target must pre-check nothing',
        );
      },
    );
  });

  group('SalonServiceSelectionScreen — search pre-selection seeding', () {
    testWidgets(
      'pre-checks ONLY the salon service whose serviceTypeSlug matches; the '
      'sibling with a different slug stays unchecked',
      (tester) async {
        _tallSurface(tester);

        await tester.pumpApp(
          const SalonServiceSelectionScreen(salonId: _kSalonId),
          overrides: _salonOverrides(
            const PendingServicePreselection(
              targetId: _kSalonId,
              serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
              serviceTypeLabels: <String>{'Класичний манікюр'},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Finder matchTile = find.byKey(
          const Key('salon_booking_service_tile_salon-match'),
        );
        final Finder otherTile = find.byKey(
          const Key('salon_booking_service_tile_salon-other'),
        );
        expect(matchTile, findsOneWidget);
        expect(otherTile, findsOneWidget);

        expect(
          _checkedFace(matchTile),
          findsOneWidget,
          reason:
              'CLASSIC_MANICURE matched salon-match → it must be pre-checked',
        );
        expect(
          _checkedFace(otherTile),
          findsNothing,
          reason:
              'GEL_MANICURE did not match → salon-other must stay '
              'unchecked',
        );
      },
    );

    testWidgets(
      'a payload targeting a DIFFERENT salon pre-checks nothing (no-match '
      'degrades to nothing)',
      (tester) async {
        _tallSurface(tester);

        await tester.pumpApp(
          const SalonServiceSelectionScreen(salonId: _kSalonId),
          overrides: _salonOverrides(
            const PendingServicePreselection(
              targetId: 'some-other-salon',
              serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
              serviceTypeLabels: <String>{},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Nothing consumed → the salon flow falls back to its default of
        // expanding the FIRST category (NAILS), so both tiles are visible …
        final Finder matchTile = find.byKey(
          const Key('salon_booking_service_tile_salon-match'),
        );
        final Finder otherTile = find.byKey(
          const Key('salon_booking_service_tile_salon-other'),
        );
        expect(matchTile, findsOneWidget);
        expect(otherTile, findsOneWidget);

        // … and NEITHER is pre-checked.
        expect(_checkedFace(matchTile), findsNothing);
        expect(
          _checkedFace(otherTile),
          findsNothing,
          reason: 'a payload for a different salon must pre-check nothing',
        );
      },
    );
  });
}
