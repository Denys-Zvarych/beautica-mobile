// Phase 351 — First pixel coverage for SalonMasterProfileScreen (there was no
// golden for it at all before this phase).
//
// SalonMasterProfileScreen is the SALON_MASTER role's own read-only profile.
// It renders the identity card (incl. `SalonAffiliationLine` +
// `_SalonAddressRows`), 3 stat cards (rating / reviews / services — «Досвід»
// removed, D9), the «Про майстра» / «Послуги» / «Відгуки» tab bar, and the
// active tab body.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} × {About, Services,
// Reviews tab} = 18 golden PNGs.
//
// Strategy:
//   • Override [salonMasterOwnProfileProvider] DIRECTLY with the fixed
//     (master, services, salon) tuple — bypasses the underlying
//     masterProfileProvider / publicServiceRepositoryProvider /
//     salonRepositoryProvider fan-out entirely, mirroring
//     `salon_master_profile_screen_test.dart`'s own `_overrides` helper.
//   • [salon] carries a BLANK oblastId/cityId (`@Default('')`), which makes
//     `resolvedLocalityProvider` short-circuit synchronously to
//     `ResolvedLocality()` with no network read — no `locationRepositoryProvider`
//     override needed (same fixture shape as that widget-test file's `_salon`).
//   • [approvedCategoriesProvider] overridden so the «Послуги» tab's
//     `ServiceCategoryCardList` resolves its label without a real API hit.
//   • [masterReviewSummaryProvider]/[masterReviewsProvider] overridden so the
//     «Відгуки» tab resolves without a real network read.
//   • [pumpWidget] uses [goldenPumpWidget] for ProviderScope + l10n.
//   • pumpAndSettle lets the animation controller quiesce; a Services/Reviews
//     cell then taps the matching tab.

import 'package:alchemist/alchemist.dart' show PumpWidget;
import 'package:beautica_mobile/features/master/application/master_review_summary_notifier.dart';
import 'package:beautica_mobile/features/master/application/master_reviews_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_review.dart';
import 'package:beautica_mobile/features/master/presentation/salon_master_profile_screen.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const Master _seedMaster = Master(
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
  city: 'Київ',
  street: 'Хрещатик',
  buildingNo: '1',
);

// ---------------------------------------------------------------------------
// Override factory
// ---------------------------------------------------------------------------

List<Object> _overrides() => <Object>[
  salonMasterOwnProfileProvider.overrideWith(
    (ref) async => (_seedMaster, _services, _salon),
  ),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[
      ServiceCategoryOption(name: 'HAIR', displayName: 'Стрижки'),
    ],
  ),
  masterReviewSummaryProvider(_seedMaster.id).overrideWith(
    (ref) async => MasterReviewSummary(
      avgRating: _seedMaster.avgRating,
      reviewCount: _seedMaster.reviewCount,
      distribution: const <int>[0, 1, 1, 2, 4],
    ),
  ),
  masterReviewsProvider(_seedMaster.id, MasterReviewSort.newest).overrideWith(
    (ref) async => <MasterReviewItem>[
      MasterReviewItem(
        id: 'rev-1',
        clientDisplayName: 'Марія К.',
        rating: 5,
        comment: 'Чудова майстриня!',
        createdAt: DateTime(2026, 6, 1),
      ),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Custom pumpWidget — settle, then (for Services/Reviews) tap the tab.
// ---------------------------------------------------------------------------

PumpWidget _pumpTab({required double width, int? tapTabIndex}) {
  final PumpWidget base = goldenPumpWidget(
    overrides: _overrides(),
    width: width,
  );
  if (tapTabIndex == null) return base;
  return (WidgetTester tester, Widget alchemistWidget) async {
    await base(tester, alchemistWidget);
    await tester.tap(find.byKey(Key('salon-master-profile-tab-$tapTabIndex')));
    await tester.pumpAndSettle();
  };
}

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'salon_master_profile About $suffix',
        fileName: 'salon_master_profile_about_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(width: width),
        builder: () => const SalonMasterProfileScreen(),
      );

      goldenTest(
        'salon_master_profile Services $suffix',
        fileName: 'salon_master_profile_services_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(width: width, tapTabIndex: 1),
        builder: () => const SalonMasterProfileScreen(),
      );

      goldenTest(
        'salon_master_profile Reviews $suffix',
        fileName: 'salon_master_profile_reviews_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: _pumpTab(width: width, tapTabIndex: 2),
        builder: () => const SalonMasterProfileScreen(),
      );
    }
  }
}
