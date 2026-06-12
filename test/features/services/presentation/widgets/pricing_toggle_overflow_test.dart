// Regression guard — pricing mode-toggle (fixed/range selector) does NOT
// overflow at 320 dp (Step 2.7 Rule 3, toggle-fix gate).
//
// The bug: each `_PricingModeToggle` segment is a fixed-width Expanded share
// (half the track). The segment's inner Row was
//     Row(min)[ Icon(16) | gap | Text("Фіксована"/"Діапазон") ]
// with the label as a BARE `Text`. Inside the service-setup row card (whose
// padding narrows the toggle track), the half-track share at 320 dp is too
// narrow for icon + gap + the full Ukrainian label, so the toggle's segment Row
// forced a horizontal RenderFlex overflow (~14 px reported as "RenderFlex
// overflowed by N pixels on the right") at pump time.
//
// The fix (pricing_field.dart `_Segment`):
//   • wrap the label `Text` in `Flexible` (so it yields to the segment width),
//   • `softWrap: false` + `overflow: TextOverflow.ellipsis` + `maxLines: 1`
//     (degrade to an ellipsis instead of overflowing),
//   • tighten the icon→label gap.
// At 320 dp the label now ellipsizes gracefully (no overflow); at 360 dp+ the
// full label still fits (no ellipsis) — the degrade is a smallest-width-only
// fallback.
//
// The toggle is pumped through the REAL service-setup row card
// (`ServiceTypeRowCard`) at the same 320 dp width as the production overflow,
// because the card's padding is what squeezes the toggle track to the failing
// width — pumping `PricingField` bare in a full-width 320 dp box gives the
// toggle ~14 px more room and does not reproduce the overflow.
//
// Pre-fix this guard FAILS at 320 dp: the segment Row overflows, surfaced via
// `tester.takeException()`. Post-fix it PASSES. Verified by reverting the
// Flexible/ellipsis change.
//
// Deterministic: no backend, no Dio; UK l10n; segments located by stable keys
// only (pricing-toggle-fixed, pricing-toggle-range). `tester.view` is reset in
// tearDown.

import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sub-pixel slack for edge/bounds comparisons (font/layout rounding).
const double _kEps = 1.0;

const Key _kFixedSegment = Key('pricing-toggle-fixed');
const Key _kRangeSegment = Key('pricing-toggle-range');

ServiceRowState _includedRow(WidgetTester tester) {
  final row = ServiceRowState(serviceTypeId: 'st-1', nameUk: 'Манікюр')
    ..included = true
    ..pricingMode = ServicePriceType.fixed;
  addTearDown(row.dispose);
  return row;
}

/// Pumps the real service-setup row card at a fixed [width]. The card frames the
/// pricing block (including the mode toggle) exactly as production does, so the
/// toggle track is squeezed to the same width that overflowed pre-fix.
Future<void> _pumpRow(WidgetTester tester, {required double width}) async {
  final row = _includedRow(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: ServiceTypeRowCard(row: row, resolveRangeError: (_) => null),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Whether the label `Text` under [segmentKey] was ellipsized — i.e. the
/// `RenderParagraph` reports its single line exceeded the available width.
/// Used to lock the "degrade only at the smallest width" intent: ellipsized at
/// 320 dp is acceptable; at 360 dp the full label must fit (no ellipsis).
bool _labelEllipsized(WidgetTester tester, Key segmentKey, String label) {
  final Finder textFinder = find.descendant(
    of: find.byKey(segmentKey),
    matching: find.text(label),
  );
  final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
    textFinder,
  );
  return paragraph.didExceedMaxLines;
}

void main() {
  group('pricing mode-toggle — no overflow at 320 dp', () {
    testWidgets(
      '320dp: toggle segments render with NO RenderFlex overflow',
      (tester) async {
        await _pumpRow(tester, width: 320);

        // The fix's core promise: pumping the toggle at 320 dp must not raise a
        // RenderFlex overflow. Pre-fix this is non-null (~14 px overflow from
        // the segment Row); post-fix it is null.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'pricing toggle must not overflow at 320 dp — the segment label '
              'must ellipsize, not force a RenderFlex overflow',
        );

        // Both segments are present and laid out.
        expect(find.byKey(_kFixedSegment), findsOneWidget);
        expect(find.byKey(_kRangeSegment), findsOneWidget);

        // Each segment stays within the 320 dp row's horizontal bounds (no
        // off-screen bleed). The row is centred in the test viewport, so compare
        // against the row card's own rect rather than absolute screen coords.
        final Rect card = tester.getRect(find.byType(ServiceTypeRowCard));
        expect(
          card.width,
          lessThanOrEqualTo(320 + _kEps),
          reason: 'precondition: the service-setup row is laid out at 320 dp',
        );
        for (final Key k in const <Key>[_kFixedSegment, _kRangeSegment]) {
          final Rect r = tester.getRect(find.byKey(k));
          expect(
            r.left,
            greaterThanOrEqualTo(card.left - _kEps),
            reason:
                'segment $k left edge ($r) must be within the 320 dp row '
                '($card) — no off-screen bleed',
          );
          expect(
            r.right,
            lessThanOrEqualTo(card.right + _kEps),
            reason:
                'segment $k right edge ($r) must be within the 320 dp row '
                '($card) — no off-screen bleed',
          );
        }
      },
    );

    testWidgets(
      '360dp: full toggle labels fit — not ellipsized (degrade is 320dp-only)',
      (tester) async {
        await _pumpRow(tester, width: 360);
        final l10n = AppLocalizations.of(
          tester.element(find.byKey(_kFixedSegment)),
        );

        expect(tester.takeException(), isNull);

        // At a comfortable phone width the full Ukrainian labels must render
        // WITHOUT ellipsis — locking the intent that the ellipsis fallback only
        // kicks in at the smallest supported width (320 dp).
        expect(
          _labelEllipsized(tester, _kFixedSegment, l10n.pricingModeFixed),
          isFalse,
          reason:
              'fixed-segment label "${l10n.pricingModeFixed}" must render in '
              'full at 360 dp (ellipsis is a 320dp-only fallback)',
        );
        expect(
          _labelEllipsized(tester, _kRangeSegment, l10n.pricingModeRange),
          isFalse,
          reason:
              'range-segment label "${l10n.pricingModeRange}" must render in '
              'full at 360 dp (ellipsis is a 320dp-only fallback)',
        );
      },
    );
  });
}
