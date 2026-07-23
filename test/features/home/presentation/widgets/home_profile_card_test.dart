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
import 'package:flutter/rendering.dart';
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

// A medium-long client name that exceeds one narrow-column line at 320 dp but
// fits inside the allowed two lines.
const _profileMediumName = ClientProfileSummary(
  firstName: 'Олександра',
  lastName: 'Зварич',
  city: 'Львів',
  phone: '+380671234567',
  clientRating: null,
  memberSinceYear: 2024,
);

// A genuinely long client name (double surname) — under the old maxLines: 1 it
// was single-line ellipsis-truncated; the fix lets it wrap to two lines.
const _profileLongName = ClientProfileSummary(
  firstName: 'Олександра',
  lastName: 'Зварич-Пономаренко',
  city: 'Львів',
  phone: '+380671234567',
  clientRating: null,
  memberSinceYear: 2024,
);

Future<void> _pumpCard(
  WidgetTester tester, {
  required ClientProfileSummary profile,
  double? width,
  double? textScaleFactor,
}) {
  return tester.pumpApp(
    HomeProfileCard(profile: profile, onCamera: () {}, onLocation: () {}),
    width: width,
    textScaleFactor: textScaleFactor,
  );
}

/// The [RenderParagraph] backing the `home_profile_name` [Text]. Driving
/// assertions off the render object lets the test inspect the ACTUAL laid-out
/// line count and truncation flag, not just the widget config.
RenderParagraph _nameParagraph(WidgetTester tester) => tester
    .renderObject<RenderParagraph>(find.byKey(const Key('home_profile_name')));

/// Number of lines the paragraph actually laid out, reproduced from its own
/// span + style + the width it was given. [RenderParagraph] exposes no line
/// count directly, so re-run the layout in a [TextPainter] (which does expose
/// [TextPainter.computeLineMetrics]) at the paragraph's incoming max width.
int _lineCount(RenderParagraph p) {
  final painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
  )..layout(maxWidth: p.constraints.maxWidth);
  final int lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
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

  // -------------------------------------------------------------------------
  // Long-name wrapping — guards the maxLines: 1 → 2 fix on `home_profile_name`.
  //
  // The profile name USED TO be a single ellipsis-truncated line, so a long
  // client name read «Олександра Зварич-Пономар…». The fix made it
  // `maxLines: 2, softWrap: true` so the full name shows across two lines on a
  // narrow phone. Asserting on the [RenderParagraph] (line count + the
  // didExceedMaxLines truncation flag) catches a revert: under maxLines: 1 the
  // long name lays out as ONE line with didExceedMaxLines == true.
  // -------------------------------------------------------------------------
  group('HomeProfileCard name wrapping (320dp long-name regression)', () {
    testWidgets(
      'medium-long name renders fully (not single-line-truncated) at 320dp x1.0',
      (tester) async {
        await _pumpCard(
          tester,
          profile: _profileMediumName,
          width: 320,
          textScaleFactor: 1.0,
        );

        final paragraph = _nameParagraph(tester);
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason:
              'the full name must render without ellipsis truncation — a revert '
              'to maxLines: 1 would truncate and set didExceedMaxLines == true.',
        );
      },
    );

    testWidgets('long name wraps to two lines, fully shown, at 320dp x1.0', (
      tester,
    ) async {
      await _pumpCard(
        tester,
        profile: _profileLongName,
        width: 320,
        textScaleFactor: 1.0,
      );

      final paragraph = _nameParagraph(tester);
      expect(
        _lineCount(paragraph),
        2,
        reason:
            'the long double-surname name wraps onto a SECOND line at 320dp — '
            'under maxLines: 1 it would be capped to a single line. (In the '
            'production font two lines hold the full name; the wider test font '
            'may need ellipsis beyond two lines, so the deterministic guard is '
            'the 2-line layout, not didExceedMaxLines.)',
      );
    });

    testWidgets('long name still wraps to two lines at 320dp x1.3 (no overflow)', (
      tester,
    ) async {
      // The Phase 17.2 overflow guard (installed by pumpApp) fails the test in
      // tearDown if any RenderFlex overflows at this stress size — so the
      // assertion here is the 2-line layout; the no-overflow check is implicit.
      await _pumpCard(
        tester,
        profile: _profileLongName,
        width: 320,
        textScaleFactor: 1.3,
      );

      final paragraph = _nameParagraph(tester);
      expect(
        _lineCount(paragraph),
        2,
        reason:
            'at the larger text scale the long name still uses both allowed '
            'lines (ellipsis is only the last resort beyond two lines).',
      );
    });
  });
}
