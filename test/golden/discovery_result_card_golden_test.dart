// Phase 13.4 — Discovery result-card goldens (FIRST discovery goldens).
//
// Pins the pixel appearance of [MasterResultCard] and [SalonResultCard] with
// realistic data — 72dp thumbnail, name, locality (city · district), ★ rating +
// review count (master only — the salon DTO carries no rating), «від N грн» /
// price range, and the favourite heart. A regression that shifts the thumbnail,
// drops the rating row, or restyles the price reads as a pixel diff here.
//
// Captured across the three phone widths {320, 360, 414} at scale 1.0 so the
// Expanded text column's truncation/wrap is exercised at the narrow end.
//
// Capture height: the constraint is width-only (BoxConstraints.tightFor(width:))
// so each card is goldened at its NATURAL height — exactly as it lays out in the
// production discovery list, which is an UNCONSTRAINED vertical scroll view. A
// fixed-height box (the former Size(width, 200)) would clip a 2-line name and
// bake a RenderFlex-overflow stripe into the master; the unconstrained height
// lets a long name wrap to its allowed maxLines: 2 with no overflow.
//
// The cards watch [favoriteToggleProvider], which itself watches [authProvider];
// we override auth with a settled authenticated session so the card resolves
// deterministically and never touches a real Dio/auth path. The heart's
// post-frame `primeIfAbsent(false)` is a no-op (prune-on-false), so no favorite
// repo is needed.
//
// File names: discovery_master_card_{320,360,414}_1x.png
//             discovery_salon_card_{320,360,414}_1x.png

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/salon_result_card.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const MasterSearchItem _master = MasterSearchItem(
  masterId: 'master-1',
  firstName: 'Олена',
  lastName: 'Коваленко',
  avatarUrl:
      null, // null → ResultThumbnail renders its placeholder (no network).
  avgRating: 4.8,
  reviewCount: 124,
  cityLabel: 'Київ',
  districtLabel: 'Печерський район',
  minEffectivePrice: 350,
  priceMax: null,
  street: null,
  buildingNo: null,
  locationNote: null,
  serviceNames: <String>['Манікюр', 'Педикюр', 'Нарощування'],
  // Built directly (not via the mapper), so supply the pre-joined preview line
  // the mapper would compute — the card reads `servicesLine`, not serviceNames.
  servicesLine: 'Манікюр · Педикюр · Нарощування',
);

/// Same master, but with NO active priced services — the card must render no
/// services line at all (the empty-serviceNames branch). Pins the no-line layout
/// so a regression that injects a placeholder line, or leaks the previous
/// fixture's line, reads as a pixel diff.
const MasterSearchItem _masterNoServices = MasterSearchItem(
  masterId: 'master-2',
  firstName: 'Ірина',
  lastName: 'Мельник',
  avatarUrl: null,
  avgRating: 4.5,
  reviewCount: 31,
  cityLabel: 'Київ',
  districtLabel: 'Печерський район',
  minEffectivePrice: 280,
  priceMax: null,
  street: null,
  buildingNo: null,
  locationNote: null,
  serviceNames: <String>[],
);

const SalonSearchItem _salon = SalonSearchItem(
  salonId: 'salon-1',
  name: 'Beauty Studio «Камелія»',
  avatarUrl: null,
  avgRating: null, // salon DTO carries no rating — row omitted by the card.
  cityLabel: 'Львів',
  districtLabel: 'Галицький район',
  priceMin: 200,
  priceMax: 800,
  street: null,
  buildingNo: null,
  locationNote: null,
  serviceNames: <String>[],
);

/// Fixed authenticated session so [authProvider] settles synchronously.
class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'u1',
      email: 'client@example.com',
      role: UserRole.client,
      firstName: 'Test',
      lastName: 'Client',
    ),
    accessToken: 'token',
  );
}

List<Object> _overrides() => <Object>[
  authProvider.overrideWith(_FixedAuthNotifier.new),
];

/// Hosts [child] on the brand base with the discovery list's horizontal page
/// padding so the card lays out as it does on screen.
Widget _host(double width, Widget child) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: child,
    ),
  ),
);

void main() {
  for (final double width in kGoldenWidths) {
    final String w = width.toInt().toString();

    goldenTest(
      'discovery master card ${w}dp x1.0',
      fileName: 'discovery_master_card_${w}_1x',
      constraints: BoxConstraints.tightFor(width: width),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
      builder: () => _host(width, const MasterResultCard(master: _master)),
    );

    goldenTest(
      'discovery master card (no services) ${w}dp x1.0',
      fileName: 'discovery_master_card_no_services_${w}_1x',
      constraints: BoxConstraints.tightFor(width: width),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
      builder: () =>
          _host(width, const MasterResultCard(master: _masterNoServices)),
    );

    goldenTest(
      'discovery salon card ${w}dp x1.0',
      fileName: 'discovery_salon_card_${w}_1x',
      constraints: BoxConstraints.tightFor(width: width),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
      builder: () => _host(width, const SalonResultCard(salon: _salon)),
    );
  }
}
