// Regression guard — service-setup row field-height parity (Step 2.7 Rule 3).
//
// The bug: inside an INCLUDED [ServiceTypeRowCard] the DURATION input well
// rendered ~45dp tall while the PRICE well was 49dp. The duration well sat
// below Material's 48dp minimum tap target and read as visibly "short".
//
// The fix has since been folded into the one-line refactor: the duration well
// is no longer a separate VelvetField — [PricingField] renders it itself as an
// inner `_PricingInputField` (compact mode) keyed `service-setup-duration`,
// sharing the SAME NeumorphicInset + ConstrainedBox(minHeight) composition as
// the price well(s). Both wells therefore derive their height from the same
// `VelvetSizes.field - 2 * (VelvetSpacing.sm + 2)` (=29 → 49dp well) constraint,
// clearing the 48dp tap-target floor with identical heights.
//
// One-line layout (NO width-conditional stacking — _stackBreakpoint and
// _rangeStackBreakpoint were deleted):
//   fixed = Row[ Expanded(duration) | gap | Expanded(price) ]
//   range = Row[ Expanded(duration) | gap | Expanded(min) | gap | Expanded(max) ]
// Every slot is an Expanded, so the Row is overflow-proof at any phone width.
//
// This guard:
//   • Pumps an INCLUDED row so both the duration well and the price well(s)
//     render on one line.
//   • Asserts the duration well and the price well are the SAME height AND each
//     is >= 48dp.
//   • Re-runs across phone widths (wide / 412 / 360 / 320) and a narrow range
//     row, asserting no RenderFlex overflow at any width.
//
// Text is asserted via stable widget keys only (no localised string finders).

import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Material's documented minimum interactive (tap-target) dimension.
const double _kMinTapTarget = 48.0;

/// The stable key on the duration well's [NeumorphicInset] (rendered by
/// [PricingField] as a compact `_PricingInputField`). After the one-line
/// refactor this key sits directly on the well, exactly like the price wells.
const Key _kDurationWellKey = Key('service-setup-duration');

/// The fixed-price well is the [NeumorphicInset] keyed by [PricingField].
const Key _kFixedPriceWellKey = Key('pricing-fixed-amount');

/// Builds an INCLUDED [ServiceRowState] in the requested [mode]. Controllers
/// are disposed via the row's own [dispose] (registered as a tearDown).
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

/// Pumps a single [ServiceTypeRowCard] constrained to [width] logical px, wide
/// enough vertically that nothing is clipped. Returns after the expand/switch
/// animations settle.
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

/// Height of the duration well — the keyed [NeumorphicInset] rendered by
/// [PricingField] in compact mode. The key is on the well itself, so it is
/// measured directly (no ancestor lookup).
double _durationWellHeight(WidgetTester tester) {
  final Finder well = find.byKey(_kDurationWellKey);
  expect(well, findsOneWidget, reason: 'duration well present');
  return tester.getSize(well).height;
}

/// Height of the fixed-price well — the keyed [NeumorphicInset].
double _fixedPriceWellHeight(WidgetTester tester) {
  final Finder well = find.byKey(_kFixedPriceWellKey);
  expect(well, findsOneWidget, reason: 'fixed-price well present');
  return tester.getSize(well).height;
}

void main() {
  group('service-setup row — duration/price well height parity (>= 48dp)', () {
    // ── WIDE — one-line layout (duration | price share one Row) ──────────────
    testWidgets(
      'wide row: duration well == price well height and each >= 48dp',
      (tester) async {
        final row = _includedRow(tester, mode: ServicePriceType.fixed);
        await _pumpRow(tester, row: row, width: 600);

        final double duration = _durationWellHeight(tester);
        final double price = _fixedPriceWellHeight(tester);

        expect(
          duration,
          price,
          reason:
              'duration well must match the price well height (pre-fix: 45 vs '
              '49); both derive from the same NeumorphicInset + '
              'ConstrainedBox(minHeight) composition',
        );
        expect(
          duration,
          greaterThanOrEqualTo(_kMinTapTarget),
          reason: 'duration well must clear the 48dp tap-target floor',
        );
        expect(price, greaterThanOrEqualTo(_kMinTapTarget));
        expect(tester.takeException(), isNull);
      },
    );

    // ── 412dp — narrow phone; one-line all-Expanded layout (no stacking) ─────
    testWidgets(
      '412dp row: one-line layout keeps well parity >= 48dp, no overflow',
      (tester) async {
        final row = _includedRow(tester, mode: ServicePriceType.fixed);
        await _pumpRow(tester, row: row, width: 412);

        final double duration = _durationWellHeight(tester);
        final double price = _fixedPriceWellHeight(tester);

        expect(duration, price);
        expect(duration, greaterThanOrEqualTo(_kMinTapTarget));
        expect(price, greaterThanOrEqualTo(_kMinTapTarget));
        expect(
          tester.takeException(),
          isNull,
          reason: 'no RenderFlex overflow at 412dp',
        );
      },
    );

    // ── 360dp — the deleted _stackBreakpoint boundary; still one line ────────
    testWidgets('360dp row: well parity >= 48dp holds, no overflow', (
      tester,
    ) async {
      final row = _includedRow(tester, mode: ServicePriceType.fixed);
      await _pumpRow(tester, row: row, width: 360);

      final double duration = _durationWellHeight(tester);
      final double price = _fixedPriceWellHeight(tester);

      expect(duration, price);
      expect(duration, greaterThanOrEqualTo(_kMinTapTarget));
      expect(tester.takeException(), isNull);
    });

    // ── 320dp — smallest common phone; still one line, all-Expanded ──────────
    testWidgets('320dp row: well parity >= 48dp holds, no overflow', (
      tester,
    ) async {
      final row = _includedRow(tester, mode: ServicePriceType.fixed);
      await _pumpRow(tester, row: row, width: 320);

      final double duration = _durationWellHeight(tester);
      final double price = _fixedPriceWellHeight(tester);

      expect(duration, price);
      expect(duration, greaterThanOrEqualTo(_kMinTapTarget));
      expect(tester.takeException(), isNull);
    });

    // ── Narrow RANGE — duration | min | max all on one line (no stacking) ────
    // Range mode at a narrow width is the worst case for one-line: three wells
    // (duration + min + max). Every slot is an Expanded, so the Row is
    // overflow-proof; the duration and range wells must still clear 48dp with
    // identical heights.
    testWidgets(
      'narrow range row (300dp): duration/min/max parity >= 48dp, no overflow',
      (tester) async {
        final row = _includedRow(tester, mode: ServicePriceType.range);
        await _pumpRow(tester, row: row, width: 300);

        final double duration = _durationWellHeight(tester);

        expect(
          duration,
          greaterThanOrEqualTo(_kMinTapTarget),
          reason:
              'duration well must clear the 48dp floor even in the three-well '
              'range row',
        );

        // Both range wells render side-by-side and clear the same floor.
        final double minWell = tester
            .getSize(find.byKey(const Key('pricing-range-min')))
            .height;
        final double maxWell = tester
            .getSize(find.byKey(const Key('pricing-range-max')))
            .height;
        expect(duration, minWell, reason: 'duration well matches range wells');
        expect(minWell, maxWell);
        expect(minWell, greaterThanOrEqualTo(_kMinTapTarget));

        expect(
          tester.takeException(),
          isNull,
          reason: 'no RenderFlex overflow in the narrow three-well range row',
        );
      },
    );
  });
}
