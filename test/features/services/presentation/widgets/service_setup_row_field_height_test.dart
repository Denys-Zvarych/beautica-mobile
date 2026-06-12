// Regression guard — service-setup row field-height parity (Step 2.7 Rule 3).
//
// The bug: inside an INCLUDED [ServiceTypeRowCard] the DURATION input well
// rendered ~45dp tall while the PRICE well was 49dp. The duration well sat
// below Material's 48dp minimum tap target and read as visibly "short".
//
// The fix (lib/core/widgets/velvet_field.dart): the single-line well minHeight
// was changed from `VelvetSizes.field - 24` (=25 → 45dp well) to
// `VelvetSizes.field - 2 * (VelvetSpacing.sm + 2)` (=29 → 49dp well), matching
// the pricing field's well and clearing the 48dp floor.
//
// This guard:
//   • Pumps an INCLUDED row so both the duration VelvetField well and the
//     fixed-price `_PricingInputField` well render.
//   • Asserts the two wells are the SAME height AND each is >= 48dp.
//   • Re-runs across the responsive branches that reshape the row — wide
//     (single-line), <360dp (duration stacks above price), <220dp (range
//     min/max stacked) — and asserts no RenderFlex overflow at 320/360/412dp.
//
// Against the pre-fix 45dp duration well the parity + >=48dp assertions FAIL;
// post-fix they PASS. Text is asserted via l10n keys / stable widget keys only.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Material's documented minimum interactive (tap-target) dimension.
const double _kMinTapTarget = 48.0;

/// The stable key forwarded to the duration field's inner [TextField] by
/// [ServiceTypeRowCard]. Used to locate the duration well's [NeumorphicInset]
/// ancestor for measurement.
const Key _kDurationFieldKey = Key('service-setup-duration');

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

/// Height of the duration well — the [NeumorphicInset] that is the nearest
/// ancestor of the keyed duration [TextField]. (The bug lived in this well's
/// inner min-height constraint, so measuring the well is the faithful target.)
double _durationWellHeight(WidgetTester tester) {
  final Finder well = find.ancestor(
    of: find.byKey(_kDurationFieldKey),
    matching: find.byType(NeumorphicInset),
  );
  expect(well, findsOneWidget, reason: 'duration well NeumorphicInset present');
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
    // ── WIDE — single-line layout (duration | price share one Row) ───────────
    testWidgets(
      'wide row: duration well == price well height and each >= 48dp',
      (tester) async {
        final row = _includedRow(tester, mode: ServicePriceType.fixed);
        // 600dp is comfortably above PricingField._stackBreakpoint (360) once
        // padding/gaps are subtracted, so the one-line layout is exercised.
        await _pumpRow(tester, row: row, width: 600);

        final double duration = _durationWellHeight(tester);
        final double price = _fixedPriceWellHeight(tester);

        expect(
          duration,
          price,
          reason:
              'duration well must match the price well height (pre-fix: 45 vs '
              '49); both derive from VelvetSizes.field (49) minus equal padding',
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

    // ── 412dp — narrow phone; PricingField stacks duration above price ───────
    testWidgets(
      '412dp row: stacked layout keeps well parity >= 48dp, no overflow',
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

    // ── 360dp — at the stack breakpoint boundary ─────────────────────────────
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

    // ── 320dp — smallest common phone; stacked layout ────────────────────────
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

    // ── <220dp — range mode with min/max stacked ─────────────────────────────
    // Range mode at a very narrow width forces BOTH the duration↑price stack
    // and the min/max stack; the duration well must still clear 48dp without
    // reintroducing overflow.
    testWidgets(
      'narrow range row (<220dp price area): duration well >= 48dp, no overflow',
      (tester) async {
        final row = _includedRow(tester, mode: ServicePriceType.range);
        await _pumpRow(tester, row: row, width: 300);

        final double duration = _durationWellHeight(tester);

        expect(
          duration,
          greaterThanOrEqualTo(_kMinTapTarget),
          reason:
              'duration well must clear the 48dp floor even in the range/'
              'min-max stacked branch',
        );

        // Both range wells render and clear the same floor.
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
          reason: 'no RenderFlex overflow in the narrow range/stacked branch',
        );
      },
    );
  });
}
