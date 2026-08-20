// Phase 247 (part 1) — Visual regression golden for ServicesListScreen.
//
// Authored BEFORE the widget-promotion refactor lands (per the phase brief):
// this file and its baseline PNGs are captured against the CURRENT,
// unmodified `_CategoryGroup` / `_CategorySection` / `_CategoryCountBadge` /
// `_ServiceCard` / `_PhotoThumbnail` / `_ServiceInfo` / `_MetaLine` /
// `_MetaItem` widgets. After the promotion moves them (dropping the leading
// underscore) into `presentation/widgets/service_category_list.dart`, this
// test MUST pass unmodified and WITHOUT `--update-goldens` — that is the
// byte-identical proof the refactor is required to satisfy.
//
// One state goldened per matrix cell — the populated (DATA, non-empty) list:
//   • THREE categories: "Стрижка" (2 services, pre-expanded via
//     `initialExpandCategory`), "Манікюр" (1 service, starts collapsed) and
//     an uncategorized bucket (1 service, starts collapsed) — exercising the
//     count badge on every section header and both the expanded and
//     collapsed disclosure states in a single frame.
//   • Every card renders through the same [_PhotoThumbnail] placeholder —
//     real photo upload is deferred to Phase 9.x, so there is no
//     "with a photo" vs "without a photo" render branch to distinguish yet;
//     the placeholder icon is what every card shows today.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 6 golden PNGs.
//
// Clock: no date-bearing UI on this screen — no clock override needed.
//
// Strategy:
//   • [servicesListProvider] backed by the real [ServicesList] notifier via
//     [serviceRepositoryProvider] overridden with [FakeServiceRepository]
//     (mirrors `services_form_golden_test.dart`'s repo-fake pattern).
//   • [approvedCategoriesProvider] overridden directly to settled DATA — it
//     sources from `categoryRequestApiProvider` (real Dio), NOT the
//     repository, so the repo fake alone does not cover it (see that file's
//     header for the full rationale).
//   • `initialExpandCategory: 'HAIRCUT'` reproduces one expanded + two
//     collapsed sections deterministically.
//   • [pumpWidget] uses [goldenPumpWidget] for ProviderScope + l10n; no
//     GoRouter ancestor is needed — nothing in this golden taps a
//     navigating control.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_screen.dart';

import '../helpers/fakes/fake_service_repository.dart';
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Seed data
// ---------------------------------------------------------------------------

const _haircut1 = MasterService(
  id: 'svc-haircut-1',
  serviceDefId: 'def-haircut-1',
  name: 'Стрижка жіноча',
  category: 'HAIRCUT',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 750,
  priceDisplay: '750 ₴',
);

const _haircut2 = MasterService(
  id: 'svc-haircut-2',
  serviceDefId: 'def-haircut-2',
  name: 'Стрижка чоловіча',
  category: 'HAIRCUT',
  durationMinutes: 30,
  priceType: ServicePriceType.fixed,
  priceMin: 400,
  priceDisplay: '400 ₴',
);

const _manicure = MasterService(
  id: 'svc-manicure-1',
  serviceDefId: 'def-manicure-1',
  name: 'Манікюр класичний',
  category: 'MANICURE',
  durationMinutes: 90,
  priceType: ServicePriceType.range,
  priceMin: 350,
  priceMax: 600,
  priceDisplay: 'від 350 до 600 ₴',
);

const _uncategorized = MasterService(
  id: 'svc-uncategorized-1',
  serviceDefId: 'def-uncategorized-1',
  name: 'Консультація',
  durationMinutes: 15,
  priceType: ServicePriceType.fixed,
  priceMin: 0,
  priceDisplay: '0 ₴',
);

const _seedServices = <MasterService>[
  _haircut1,
  _haircut2,
  _manicure,
  _uncategorized,
];

const _seedCategories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
];

// ---------------------------------------------------------------------------
// Override factory
// ---------------------------------------------------------------------------

List<Object> _overrides() => <Object>[
  serviceRepositoryProvider.overrideWithValue(
    FakeServiceRepository(services: _seedServices, categories: _seedCategories),
  ),
  approvedCategoriesProvider.overrideWith((ref) async => _seedCategories),
];

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'services_list DATA ${width.toInt()}dp text-${scale}x',
        fileName: 'services_list_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () =>
            const ServicesListScreen(initialExpandCategory: 'HAIRCUT'),
      );
    }
  }
}
