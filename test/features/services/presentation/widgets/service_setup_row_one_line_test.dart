// Regression guard — service-setup row keeps DURATION + PRICE on ONE LINE
// (Step 2.7 Rule 3). The user's explicit request: a genuine same-line guard.
//
// The one-line refactor of [PricingField]'s compact (service-setup) path:
//   • Deleted both _stackBreakpoint (360) and _rangeStackBreakpoint (220) —
//     there is NO width-conditional stacking anymore.
//   • The compact row is all-Expanded:
//       fixed = Row[ Expanded(duration) | gap | Expanded(price) ]
//       range = Row[ Expanded(duration) | gap | Expanded(min) | gap | Expanded(max) ]
//     All-Expanded cannot overflow at any phone width.
//
// This guard asserts, for FIXED and RANGE modes at 320 / 360 / 412 dp, that the
// duration well and the price well(s) genuinely share a single horizontal line:
//   • they share the same vertical band (equal centre.dy, ~1px tolerance), and
//   • they are side-by-side (each well's right edge is left of the next well's
//     left edge — never stacked / overlapping vertically), and
//   • there is NO RenderFlex overflow anywhere in the pumped row
//     (tester.takeException() == null) — including the mode toggle.
//
// Why this is a TRUE one-line guard: if any well were stacked below another
// (different top / centre.dy), the equal-centre assertion would FAIL and the
// "left of" assertion would no longer hold. A stacked layout cannot pass.
//
// Overflow scope: a fully clean takeException(). The previous revision of this
// guard tolerated (filtered out) a SEPARATE, PRE-EXISTING overflow in the
// `_PricingModeToggle` segment label (the "Фіксована"/"Діапазон" Row) that only
// manifested at 320 dp. That toggle overflow has since been FIXED (the segment
// label now ellipsizes via Flexible + TextOverflow.ellipsis — see
// pricing_field.dart `_Segment` and pricing_toggle_overflow_test.dart), so the
// tolerance is removed: this guard now asserts a clean takeException() with no
// special-casing of the toggle.
//
// Wells are located by stable keys only (service-setup-duration,
// pricing-fixed-amount, pricing-range-min, pricing-range-max).

import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sub-pixel slack for centre/edge comparisons (font/layout rounding).
const double _kEps = 1.0;

const Key _kDurationWell = Key('service-setup-duration');
const Key _kFixedWell = Key('pricing-fixed-amount');
const Key _kRangeMinWell = Key('pricing-range-min');
const Key _kRangeMaxWell = Key('pricing-range-max');

/// The phone widths the one-line invariant must hold across.
const List<double> _kWidths = <double>[320, 360, 412];

ServiceRowState _includedRow(
  WidgetTester tester, {
  required ServicePriceType mode,
}) {
  final row = ServiceRowState(serviceTypeId: 'st-1', nameUk: 'Манікюр')
    ..included = true
    ..pricingMode = mode;
  addTearDown(row.dispose);
  return row;
}

/// Pumps the row at [width]. Any layout error (RenderFlex overflow included)
/// surfaces through the normal test pipeline and is asserted clean by
/// [_assertOneLine] via `tester.takeException()`.
Future<void> _pumpRow(
  WidgetTester tester, {
  required ServiceRowState row,
  required double width,
}) async {
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
              child: ServiceTypeRowCard(
                row: row,
                resolveRangeError: (_) => null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Asserts every well in [wells] (left-to-right order) shares one horizontal
/// line: equal vertical centres AND strictly side-by-side (no overlap, no
/// stacking). Fails loudly against any stacked layout.
void _assertOneLine(
  WidgetTester tester,
  List<Key> wells, {
  required double width,
}) {
  final List<Rect> rects = <Rect>[
    for (final Key k in wells) tester.getRect(find.byKey(k)),
  ];

  // All wells share the same vertical band → genuinely one line.
  final double baseCentreY = rects.first.center.dy;
  for (int i = 0; i < wells.length; i++) {
    expect(
      rects[i].center.dy,
      closeTo(baseCentreY, _kEps),
      reason:
          'one-line @${width}dp: ${wells[i]} centre.dy (${rects[i].center.dy}) '
          'must equal the first well centre.dy ($baseCentreY) — a stacked '
          'layout would differ here',
    );
  }

  // Strictly side-by-side, in order: each well sits entirely left of the next.
  for (int i = 0; i + 1 < wells.length; i++) {
    expect(
      rects[i].right,
      lessThanOrEqualTo(rects[i + 1].left + _kEps),
      reason:
          'one-line @${width}dp: ${wells[i]} right (${rects[i].right}) must be '
          'left of ${wells[i + 1]} left (${rects[i + 1].left}) — side-by-side, '
          'not stacked',
    );
  }

  // No RenderFlex overflow ANYWHERE in the pumped row @${width}dp — the
  // all-Expanded duration/price line is overflow-proof, and the mode toggle's
  // segment label now ellipsizes instead of overflowing (the 320 dp toggle
  // overflow was fixed). No special-casing: a fully clean takeException().
  expect(
    tester.takeException(),
    isNull,
    reason:
        'no RenderFlex overflow anywhere in the service-setup row @${width}dp '
        '(all-Expanded duration/price line + ellipsizing mode toggle)',
  );
}

void main() {
  group('service-setup row — duration + price on ONE LINE', () {
    for (final double width in _kWidths) {
      testWidgets(
        'FIXED @${width.toInt()}dp: duration | price share one line, no overflow',
        (tester) async {
          final row = _includedRow(tester, mode: ServicePriceType.fixed);
          await _pumpRow(tester, row: row, width: width);

          expect(find.byKey(_kDurationWell), findsOneWidget);
          expect(find.byKey(_kFixedWell), findsOneWidget);

          _assertOneLine(tester, const <Key>[
            _kDurationWell,
            _kFixedWell,
          ], width: width);
        },
      );

      testWidgets(
        'RANGE @${width.toInt()}dp: duration | min | max share one line, no overflow',
        (tester) async {
          final row = _includedRow(tester, mode: ServicePriceType.range);
          await _pumpRow(tester, row: row, width: width);

          expect(find.byKey(_kDurationWell), findsOneWidget);
          expect(find.byKey(_kRangeMinWell), findsOneWidget);
          expect(find.byKey(_kRangeMaxWell), findsOneWidget);

          _assertOneLine(tester, const <Key>[
            _kDurationWell,
            _kRangeMinWell,
            _kRangeMaxWell,
          ], width: width);
        },
      );
    }
  });
}
