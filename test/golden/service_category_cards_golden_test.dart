// mobile-qa gap-closure — first pixel coverage for [ServiceCategoryCard]'s
// 20dp leading category glyph (added to `service_category_cards.dart`, the
// widget SHARED by both `MasterProfileScreen` (owner) and
// `PublicMasterProfileScreen` (client) via `ServiceCategoryCardList`).
//
// ── WHY A WIDGET-LEVEL GOLDEN, NOT A SCREEN-LEVEL ONE ──────────────────────
//
// mobile-build-verifier's HIGH finding: `grep -a -rl "ServiceCategoryCard"
// test/golden/` returned NO hits before this file — `master_profile_golden_
// test.dart` overrides `serviceRepositoryProvider` with a bare
// `FakeServiceRepository()` that resolves to an empty service list, so
// `ServiceCategoryCardList.build` (`service_category_cards.dart:152`)
// short-circuits to `SizedBox.shrink()` before a single card mounts. There is
// also no `public_master_profile` golden at all.
//
// The icon lives ENTIRELY inside this shared widget — neither
// `master_profile_screen.dart` nor `public_master_profile_screen.dart` was
// touched to add it, and both consumers pick it up unmodified through
// `ServiceCategoryCardList`. That is exactly the shape `category_rail_
// golden_test.dart` and `beauty_timeline_rail_golden_test.dart` already
// established a precedent for in this codebase: a shared render widget that
// two-plus screens embed unchanged gets its OWN widget-level golden, not a
// screen-level one bolted onto every consumer. Adding a first `public_
// master_profile` golden here would (a) duplicate this coverage the moment
// the owner-side screen golden gets its empty-services gap closed too, and
// (b) still not be the honest boundary — a screen-level regression in
// `PublicMasterProfileScreen` layout has nothing to do with whether this
// glyph paints. So: ONE `ServiceCategoryCardList`-level golden, covering both
// the categorised (icon present) and uncategorized (icon absent, `_none`
// bucket) cards in a single capture, is the boundary this gap actually
// needs closed. The pre-existing `master_profile_golden_test.dart` empty-
// services gap is a separate, narrower finding — noted in the mobile
// backlog, not fixed here (fixing it would mean growing that screen's fixed
// entrance-animation matrix, out of scope for this icon-only change).
//
// ── MUTATION PROOF this golden actually sees the icon layer ───────────────
//
// Acceptance criterion per mobile-qa brief: NOT a green test — the baseline
// hash must move when the icon is removed or resized. Verified by mutation
// (`service_category_cards.dart`'s `AppIcon(...)` branch temporarily replaced
// with an unconditional `null` — i.e. every card, categorised or not, renders
// the empty 20×20 slot) and regenerating:
//
//   service_category_cards_360_1x    original sha256 00706b063f1a2d66d645563a92c0c1d6308c4e01db32166fc81ebaedde8bfe4d
//   service_category_cards_360_1x    mutated  sha256 468aefeef9e4b29f6f815ec796f816f14e632e1a7ba498d74c907601dd6b39b2
//   service_category_cards_360_1_3x  original sha256 8f3a591873d4f6eaedf7905746a4af42749e58f1e57bd7a12f63aa2922725c20
//   service_category_cards_360_1_3x  mutated  sha256 6c7a88fad33fc2f25d010c98dd65bf292a50389586a76453c5aa80c23445f34d
//
// Mutation reverted from a pre-edit `cp` backup (md5-confirmed identical to
// the pre-mutation source); regenerating again from the reverted source
// reproduced the ORIGINAL PNG bytes exactly (`cmp` clean) — the committed
// baselines above are the original, un-mutated render.
//
// Fixture: three services — two under `MANICURE` (proves the count badge and
// grouping still work with an icon present), one under `BROWS` (a second,
// visibly DIFFERENT glyph — proves the icon is category-specific, not a
// single hardcoded asset), and one with no category at all (the `_none`
// bucket — MUST render the empty same-size slot, label still left-aligned at
// the same 44dp offset as the iconed cards per the widget's own contract).
// `interactive: true` (owner) — the chevron is orthogonal to this gap but
// matches the real owner call site, `master_profile_screen.dart:883`.

import 'package:beautica_mobile/features/master/presentation/widgets/service_category_cards.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const List<MasterService> _fixtureServices = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Манікюр з покриттям',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'MANICURE',
  ),
  MasterService(
    id: 'svc-2',
    serviceDefId: 'def-2',
    name: 'Ще один манікюр',
    durationMinutes: 45,
    priceMin: 400,
    priceDisplay: '400 ₴',
    category: 'MANICURE',
  ),
  MasterService(
    id: 'svc-3',
    serviceDefId: 'def-3',
    name: 'Корекція брів',
    durationMinutes: 30,
    priceMin: 250,
    priceDisplay: '250 ₴',
    category: 'BROWS',
  ),
  MasterService(
    id: 'svc-4',
    serviceDefId: 'def-4',
    name: 'Без категорії',
    durationMinutes: 20,
    priceMin: 100,
    priceDisplay: '100 ₴',
    // category deliberately absent — exercises the icon-free `_none` card.
  ),
];

/// approvedCategoriesProvider is NOT sourced through serviceRepositoryProvider
/// (real Dio-backed categoryRequestApiProvider) — must be overridden directly
/// or pumpAndSettle hangs on a leaked real-network Timer (same trap documented
/// in `service_category_cards_test.dart`).
List<Object> _overrides() => <Object>[
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
];

Widget _host(double width) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: ServiceCategoryCardList(
        services: _fixtureServices,
        keyPrefix: 'golden-category',
        interactive: true,
      ),
    ),
  ),
);

void main() {
  const double width = 360;

  for (final double scale in kGoldenTextScales) {
    goldenTest(
      'service category cards — categorised + uncategorized ${width.toInt()}dp x$scale',
      fileName: 'service_category_cards_${widthScaleSuffix(width, scale)}',
      constraints: BoxConstraints.tight(const Size(width, 320)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
      builder: () => _host(width),
    );
  }
}
