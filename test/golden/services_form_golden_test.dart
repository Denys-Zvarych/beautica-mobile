// Phase 17.4 — Visual regression goldens for ServiceForm widget.
//
// ServiceForm is the highest-traffic write surface in the services feature —
// it handles both CREATE (blank) and EDIT (pre-filled) modes and embeds
// PricingField (the overflow-prone widget from the 17.2 phase).
//
// Two states are goldened per matrix cell:
//   • CREATE mode  — blank form (no initial service).
//   • EDIT mode    — pre-filled with a FIXED-priced service.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 12 golden PNGs.
// Clock: no date-bearing UI.
//
// Strategy:
//   • [serviceRepositoryProvider] is overridden with [FakeServiceRepository]
//     for any repo-routed read the form performs.
//   • [approvedCategoriesProvider] is overridden directly to settled empty
//     DATA. It does NOT flow through [serviceRepositoryProvider] — it sources
//     from [categoryRequestApiProvider] → the real authenticated Dio — so the
//     repo fake alone does NOT cover it. Without this override the provider
//     hits the real Dio (no backend under `flutter test`), resolves to an
//     ERROR AsyncValue, and [_CategoryDropdown] paints the category field with
//     [SelectFieldState.error] (red error tint AT REST) — a fixture artifact,
//     not the form's true resting state. Settling it to empty data renders the
//     intended neutral "no categories" idle state the goldens are meant to
//     guard (layout, not live data).
//   • [serviceTypesProvider] family resolves from the same fake (empty types).
//   • [onSubmit] is a no-op future — ServiceForm is purely visual here.
//   • No routing context needed: ServiceForm never calls context.go().

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';

import '../helpers/fakes/fake_service_repository.dart';
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Override factory
// ---------------------------------------------------------------------------

List<Object> _overrides() => <Object>[
  serviceRepositoryProvider.overrideWithValue(FakeServiceRepository()),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

// ---------------------------------------------------------------------------
// Seed data for EDIT mode
// ---------------------------------------------------------------------------

const _editSeed = MasterService(
  id: 's1',
  serviceDefId: 'def1',
  name: 'Манікюр класичний',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 350,
  priceDisplay: '350 ₴',
);

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      // CREATE mode — blank form
      goldenTest(
        'service_form CREATE ${width.toInt()}dp text-${scale}x',
        fileName: 'service_form_create_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () => ServiceForm(onSubmit: (_) async {}),
      );

      // EDIT mode — pre-filled with a fixed-price service
      goldenTest(
        'service_form EDIT ${width.toInt()}dp text-${scale}x',
        fileName: 'service_form_edit_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () => ServiceForm(
          initial: _editSeed,
          submitLabel: 'Зберегти зміни',
          onSubmit: (_) async {},
        ),
      );
    }
  }
}
