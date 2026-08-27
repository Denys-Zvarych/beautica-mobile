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
//   • [approvedCategoriesProvider] is overridden directly to a settled ONE-
//     ENTRY list (`NAIL_SERVICE` → "Манікюр" — see the mobile-qa note below).
//     It does NOT flow through [serviceRepositoryProvider] — it sources
//     from [categoryRequestApiProvider] → the real authenticated Dio — so the
//     repo fake alone does NOT cover it. Without an override the provider
//     hits the real Dio (no backend under `flutter test`), resolves to an
//     ERROR AsyncValue, and [_CategoryDropdown] paints the category field with
//     [SelectFieldState.error] (red error tint AT REST) — a fixture artifact,
//     not the form's true resting state. CREATE mode's dropdown never selects
//     a category regardless of this list's contents, so its idle "no
//     categories chosen yet" rendering is unaffected by the entry below.
//   • [serviceTypesProvider] family resolves from the same fake (empty types).
//   • [onSubmit] is a no-op future — ServiceForm is purely visual here.
//   • No routing context needed: ServiceForm never calls context.go().
//
// ── mobile-qa gap-closure (2026-08-26): EDIT mode never exercised the
//    category icon ──────────────────────────────────────────────────────
//
// Before this change `_editSeed` carried no `category`, so
// `_selectedCategory` (`service_form.dart:386`) was null in every EDIT-mode
// cell and `_CategoryDropdown`'s `categoryIconOrNullFor(categoryKey:
// selected)` branch (`service_form.dart:1461`) never painted — all 12
// pre-existing baselines were correctly unchanged by the category-icon
// rollout and proved nothing about it. `_editSeed.category` is now
// `'NAIL_SERVICE'`, paired with the matching `ServiceCategoryOption` above so
// the closed field resolves the REAL display label ("Манікюр"), not the
// `humanizeCategorySlug` fallback. This also reveals the
// `_ServiceTypeDropdown` section (gated on a non-blank `_selectedCategory`),
// which resolves to its idle empty-options state via
// `FakeServiceRepository.fetchServiceTypes` — verified this does not
// overflow at any of the 6 EDIT cells (320–414dp × 1.0–1.3x).
//
// MUTATION PROOF (all 6 EDIT baselines; CREATE is untouched by this seed
// change and was not touched by the mutation):
// `_CategoryDropdown`'s `leadingIcon:` temporarily forced to `null`
// (`service_form.dart`, reverted from a pre-edit `cp` backup, md5-confirmed
// identical to the pre-mutation source) and regenerated
// (`flutter test --update-goldens --plain-name "service_form EDIT"
// test/golden/services_form_golden_test.dart`):
//   service_form_edit_320_1x    original sha256 f33cb1bf4f397605ec4570a166739d8f9d36164b0337d421ccd618723e70c26c
//   service_form_edit_320_1x    mutated  sha256 96383b0c233d40776581b69e43cf5c6a7906ccc1d5a874799770372d497c87b1
//   service_form_edit_320_1_3x  original sha256 7551867682c9d0f06b9ae4e367758b4784a2105240199191f468058492e2706a
//   service_form_edit_320_1_3x  mutated  sha256 eedaa4f0e6b631684f661f008dc2d57662f2f9041108e53cbf7aee522443951f
//   service_form_edit_360_1x    original sha256 42c3e7a5bab55adf4ebef7d4635a34fd75703c4d25140c09693eae4f658d9a59
//   service_form_edit_360_1x    mutated  sha256 3cc542cb9df4a3e3a0ea5f574bd3947395e362d6a06371f5cce348ceb16f5f1c
//   service_form_edit_360_1_3x  original sha256 3e9795449001332132d7ec0a76bf459219afd5a6b5fc091166d70d091ebf8126
//   service_form_edit_360_1_3x  mutated  sha256 ff4854d9810f8b27f059b1597da06528cc5fc506021ed13f83307816a1fed002
//   service_form_edit_414_1x    original sha256 2bd35e01b2af152b3e48bc2bc2974cd60d372e8dad5390884c449a816e377e8d
//   service_form_edit_414_1x    mutated  sha256 57d4736f00bcab63b23b0db6c0cb31ad44013b7ddac36401bdd4920a7034a7b9
//   service_form_edit_414_1_3x  original sha256 d0ea23674c916bfbf3d127f2bea16717b5c944bd70594405e4f61ba78280b2df
//   service_form_edit_414_1_3x  mutated  sha256 915608de23754523f6bf9d98f624cb620991361f0e72819106ce258941586375
// Mutation reverted; regenerating again from the reverted source reproduced
// the ORIGINAL sha256 hashes byte-for-byte — the committed baselines above
// are the original, un-mutated render.

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
  // mobile-qa gap-closure (2026-08-26): includes the EDIT seed's own
  // 'NAIL_SERVICE' slug so `_CategoryDropdown._selectedLabel` resolves it
  // to a real Ukrainian display name ("Манікюр") instead of falling back to
  // `humanizeCategorySlug` — see `_editSeed` below. CREATE mode's dropdown
  // is unaffected (`_selectedCategory` stays null there regardless of what
  // this list contains).
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[
      ServiceCategoryOption(name: 'NAIL_SERVICE', displayName: 'Манікюр'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Seed data for EDIT mode
// ---------------------------------------------------------------------------

// mobile-qa gap-closure (2026-08-26): `category` was previously absent here,
// so `_selectedCategory` (`service_form.dart:386`,
// `_selectedCategory = initial?.category`) was null in EVERY EDIT-mode cell
// and `_CategoryDropdown.selected` never left null — the 20dp leading-icon
// branch (`categoryIconOrNullFor(categoryKey: selected)`,
// `service_form.dart:1461`) never painted in any of the 12 pre-existing
// baselines. Seeding a real approved slug here (paired with the matching
// `ServiceCategoryOption` in `_overrides()` above) exercises it. This also
// reveals the `_ServiceTypeDropdown` section (gated on
// `_selectedCategory != null && isNotEmpty`,
// `service_form.dart:1000-1001`) — `FakeServiceRepository.fetchServiceTypes`
// resolves it to a settled empty list, so it renders its idle empty state
// rather than hanging or erroring.
const _editSeed = MasterService(
  id: 's1',
  serviceDefId: 'def1',
  name: 'Манікюр класичний',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 350,
  priceDisplay: '350 ₴',
  category: 'NAIL_SERVICE',
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
