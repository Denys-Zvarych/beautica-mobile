// Regression tests for [HomeProfileCard] — guards the location-marker icon swap.
//
// The home-hub profile block's locality line previously rendered a Material
// `Icon(Icons.location_on_rounded)`. It now renders the hoisted
// `static const _locationIcon` — an `AppIcon(BeauticaAssetIcons.locationMarker)`
// SVG sized to 16 px and tinted [BrandColors.accent] to match the glyph it
// replaced. This site had NO prior location-icon assertion (Rule 3).
//
// Red-against-revert reasoning: the predicate
//   w is AppIcon && w.asset == BeauticaAssetIcons.locationMarker
// finds 0 matches if the swap is reverted to `Icon(Icons.location_on_rounded)`
// (an Icon is not an AppIcon) or if a wrong/missing asset is used → the test
// fails. With the swap in place it finds exactly the location-line icon → passes.
//
// Layer: Widget. Finders are asset-invariant predicates, never localized
// strings (M2). The card is a plain StatelessWidget with no provider
// dependency, so it is pumped directly.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/home_profile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const _profileWithCity = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Коваль',
  city: 'Львів',
  phone: '+380671234567',
  clientRating: null,
  memberSinceYear: 2024,
);

const _profileNoCity = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Коваль',
  city: '',
  phone: '+380671234567',
  clientRating: null,
  memberSinceYear: 2024,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required ClientProfileSummary profile,
}) {
  return tester.pumpApp(
    HomeProfileCard(profile: profile, onCamera: () {}, onLocation: () {}),
  );
}

/// The location-marker SVG on the locality line. There is exactly one
/// location-marker AppIcon in this card.
Finder _locationMarker() => find.byWidgetPredicate(
  (w) => w is AppIcon && w.asset == BeauticaAssetIcons.locationMarker,
);

AppIcon _locationMarkerWidget(WidgetTester tester) =>
    tester.widget<AppIcon>(_locationMarker());

void main() {
  group('HomeProfileCard location marker', () {
    testWidgets(
      'renders the locationMarker AppIcon on the locality line (with city)',
      (tester) async {
        await _pumpCard(tester, profile: _profileWithCity);

        // City line is present and the SVG marker renders next to it.
        expect(find.byKey(const Key('home_profile_city')), findsOneWidget);
        expect(_locationMarker(), findsOneWidget);
      },
    );

    testWidgets(
      'renders the locationMarker AppIcon on the placeholder line (no city)',
      (tester) async {
        await _pumpCard(tester, profile: _profileNoCity);

        // Even without a city the placeholder line still carries the marker.
        expect(_locationMarker(), findsOneWidget);
      },
    );

    testWidgets(
      'the Material location_on Icon is NOT rendered (revert guard)',
      (tester) async {
        await _pumpCard(tester, profile: _profileWithCity);

        // A revert to Icon(Icons.location_on_rounded) would make this fail.
        expect(
          find.byWidgetPredicate(
            (w) => w is Icon && w.icon == Icons.location_on_rounded,
          ),
          findsNothing,
        );
      },
    );

    testWidgets('location marker keeps the 16px / accent tint and size', (
      tester,
    ) async {
      await _pumpCard(tester, profile: _profileWithCity);

      final icon = _locationMarkerWidget(tester);
      expect(icon.size, 16, reason: 'home meta marker must stay 16px');
      expect(
        icon.color,
        BrandColors.accent,
        reason: 'home meta marker must stay BrandColors.accent',
      );
    });
  });
}
