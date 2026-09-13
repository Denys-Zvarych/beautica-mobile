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

/// Phase 324 (mobile-qa D1) — an empty catalogue, otherwise identical wiring
/// to [_overrides].
List<Object> _emptyOverrides() => <Object>[
  serviceRepositoryProvider.overrideWithValue(
    FakeServiceRepository(
      services: const <MasterService>[],
      categories: _seedCategories,
    ),
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

  // ─────────────────────────────────────────────────────────────────────────
  // MATRIX ASYMMETRY — DELIBERATE, and here is the argument (2026-09-13
  // audit, M16).
  //
  // The WRITABLE data matrix above is {320, 360, 414} dp × {1.0, 1.3} text
  // scale = 6 cells. Every variant BELOW this line is ONE cell: 414 dp at
  // text-1x. That asymmetry was previously incidental — nothing in this file
  // said whether it was a judgement or an oversight, so the next author had
  // no way to tell. It is a judgement, for two independent reasons:
  //
  //   1. PURE SUBTRACTION, NO REFLOW. `writable: false` removes widgets
  //      (the FAB, the empty-state CTA, each card's tap target) and adds
  //      none. Nothing below it changes width, wraps differently, or takes a
  //      different number of lines: the cards keep the exact geometry the
  //      writable baselines already pin at all three widths and both text
  //      scales. A width- or text-scale-dependent bug therefore shows up in
  //      the 6 writable cells FIRST — duplicating them read-only would pin
  //      the same layout twice and fail twice for one cause.
  //   2. THE EMPTY STATE HAS NO WIDTH-SENSITIVE LAYOUT AT ALL — no category
  //      disclosure rows, no count badges, no card grid. It is a centred
  //      medallion + two centred text blocks + an optional button.
  //
  // WHAT WOULD INVALIDATE THIS and require extending to the full matrix:
  // any change that makes a read-only or empty render differ STRUCTURALLY
  // from its writable counterpart rather than by subtraction — e.g. a
  // read-only banner, a reflowed header, different padding when the FAB is
  // absent, or copy long enough to wrap at 320 dp / text-1.3 but not at
  // 414 dp / text-1x. If you are about to add any of those, add the cells.
  // ─────────────────────────────────────────────────────────────────────────

  // Phase 320 (D3) — ONE read-only baseline, separate from the {320,360,414}
  // × {1x,1.3x} writable matrix above. Proves the FAB is gone and the cards
  // still render with no edit-pencil affordance, without touching (and
  // without ever needing to regenerate) a single writable baseline.
  goldenTest(
    'services_list READ-ONLY 414dp text-1x',
    fileName: 'services_list_readonly_414_1x',
    constraints: BoxConstraints.tight(const Size(414, kGoldenHeight)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(overrides: _overrides(), width: 414),
    builder: () => const ServicesListScreen(
      initialExpandCategory: 'HAIRCUT',
      writable: false,
    ),
  );

  // Phase 324 (mobile-qa D1) — the EMPTY-catalogue state, writable and
  // read-only. Neither existed before this file: the DATA matrix above and
  // the phase-320 read-only baseline both seed a NON-empty catalogue, so
  // `_EmptyState` (the medallion + headline + body + conditional CTA) had
  // never been golden-pinned. ONE cell each (414dp / text-1x), mirroring the
  // phase-320 read-only precedent above rather than the full DATA matrix —
  // this state has no category disclosure/count-badge layout to exercise
  // across widths.
  //
  //   • WRITABLE empty  → `onCreate` non-null → the "Додати послугу" CTA
  //     button renders below the headline/body text.
  //   • READ-ONLY empty → `onCreate` null (Phase 320 D3) → the CTA is
  //     OMITTED entirely (not disabled) — a greyed-out button would promise
  //     a write the backend refuses.
  goldenTest(
    'services_list EMPTY WRITABLE 414dp text-1x',
    fileName: 'services_list_empty_writable_414_1x',
    constraints: BoxConstraints.tight(const Size(414, kGoldenHeight)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(overrides: _emptyOverrides(), width: 414),
    builder: () => const ServicesListScreen(writable: true),
  );

  goldenTest(
    'services_list EMPTY READ-ONLY 414dp text-1x',
    fileName: 'services_list_empty_readonly_414_1x',
    constraints: BoxConstraints.tight(const Size(414, kGoldenHeight)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(overrides: _emptyOverrides(), width: 414),
    builder: () => const ServicesListScreen(writable: false),
  );
}
