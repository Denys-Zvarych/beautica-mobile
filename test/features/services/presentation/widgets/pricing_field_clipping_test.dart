// Regression guard — price-field clipping / "грн"-suffix occlusion (Step 2.7
// Rule 3).
//
// Original bug (v1): typed price digits read as hidden "under" the "грн"
// suffix. Two distinct defects in [_PricingInputField]:
//
//   1. VERTICAL CLIP — the input Row was wrapped in a HARD-height SizedBox
//      (= 29dp) with `isCollapsed: true` + zero contentPadding. A hard box
//      clamps the Row to 29dp, so when the rendered single-line glyph height
//      exceeds 29dp (16sp Nunito + cursor, larger system text scale) the
//      EditableText is clipped top/bottom. Fix: ConstrainedBox(minHeight: …)
//      so the box GROWS to the natural line height.
//
//   2. HORIZONTAL CROWDING — the field→"грн" gap was VelvetSpacing.sm (8dp),
//      tightened to VelvetSpacing.xs (4dp) for the 3-column RANGE layout.
//
// The one-line layout change (Phase 5.6 / 2026-06-13) introduced a third
// behaviour that this file now guards:
//
//   3. HIDE-SUFFIX-WHEN-ACTIVE — price fields (FIXED, RANGE min/max) set
//      hideSuffixWhenActive=true so "грн" hides while the field is focused OR
//      has text, preventing digit/suffix overlap on narrow screens. The duration
//      well always keeps its "хв" suffix (hideSuffixWhenActive=false).
//
// Test plan (what this file asserts):
//   A. SUFFIX VISIBILITY CONTRACT
//      A1. Price field empty+unfocused → "грн" present (findsOneWidget).
//      A2. Price field empty+unfocused no-overlap: input does not overrun "грн".
//      A3. Price field with content → "грн" absent (findsNothing).
//      A4. Duration well with content → "хв" always present (findsOneWidget).
//   B. VERTICAL GROWTH (original bug guard, large text scale)
//      B1. Well grows past VelvetSizes.field under 2.5× text scale (no clip).
//      B2. EditableText paint height ≥ scaled line height (not truncated).
//   C. NARROW ONE-LINE LAYOUT
//      C1. Range min/max wells are on one line (equal tops) at 219dp.
//      C2. Min/max wells do not overlap each other horizontally.
//
// Deterministic: no backend, no Dio, fixed-width box, default test font.
// Currency tokens ("грн", "хв") are asserted directly — they ARE the contract.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Constants (mirrored from the widget under test via tokens).
// ---------------------------------------------------------------------------

/// The field→suffix gap after the RANGE-layout tightening.
/// The fix narrowed this from VelvetSpacing.sm (8) to VelvetSpacing.xs (4)
/// so the 3-column RANGE row leaves ~51 dp for digits at 360 dp.
/// The guard asserts the contract value only when the suffix is actually
/// visible (empty + unfocused field); any regression to a LARGER value would
/// still pass this floor, but D1 pins the exact token.
const double _kSuffixGap = VelvetSpacing.xs;

/// The single-line input font size (VelvetText.input() is 16sp Nunito).
const double _kInputFontSize = 16.0;

/// Inner min-height the well's input Row is constrained to.
const double _kInnerMinHeight = VelvetSizes.field - 2 * (VelvetSpacing.sm + 2);

/// "грн" — the price suffix token that hides when the field is active/non-empty.
const String _kPriceSuffix = 'грн';

/// "хв" — the duration suffix token that is ALWAYS visible.
const String _kDurationSuffix = 'хв';

/// Sub-pixel slack for edge/gap comparisons (font/layout rounding).
const double _kEps = 0.01;

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Controllers + teardown returned from the pump helpers.
class _PricingHandles {
  const _PricingHandles({
    required this.fixedCtrl,
    required this.minCtrl,
    required this.maxCtrl,
    this.durationCtrl,
  });

  final TextEditingController fixedCtrl;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;
  final TextEditingController? durationCtrl;
}

/// Pumps a [PricingField] inside a fixed-[width] box with UK l10n.
///
/// [mode] selects FIXED vs RANGE.
/// [textScale] inflates the system text scaler to expose hard-SizedBox vertical
/// clip (a ConstrainedBox grows; a SizedBox does not).
/// [primeValuePrice] — when non-null — loads text into the price controllers so
/// the hideSuffixWhenActive contract is exercised (suffix must be ABSENT).
/// [withDuration] — when true — also passes a durationController so the
/// duration well is rendered (needed to test the "хв" suffix).
Future<_PricingHandles> _pump(
  WidgetTester tester, {
  required ServicePriceType mode,
  double width = 360,
  double textScale = 1.0,
  String? primeValuePrice,
  bool withDuration = false,
}) async {
  final fixedCtrl = TextEditingController(text: primeValuePrice ?? '');
  final minCtrl = TextEditingController(text: primeValuePrice ?? '');
  final maxCtrl = TextEditingController(text: primeValuePrice ?? '');
  final durationCtrl = withDuration ? TextEditingController() : null;
  addTearDown(fixedCtrl.dispose);
  addTearDown(minCtrl.dispose);
  addTearDown(maxCtrl.dispose);
  if (durationCtrl != null) addTearDown(durationCtrl.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: PricingField(
                  mode: mode,
                  onModeChanged: (_) {},
                  fixedController: fixedCtrl,
                  minController: minCtrl,
                  maxController: maxCtrl,
                  durationController: durationCtrl,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _PricingHandles(
    fixedCtrl: fixedCtrl,
    minCtrl: minCtrl,
    maxCtrl: maxCtrl,
    durationCtrl: durationCtrl,
  );
}

/// The [EditableText] nested inside the well keyed [wellKey].
Finder _editableUnder(Key wellKey) => find.descendant(
  of: find.byKey(wellKey),
  matching: find.byType(EditableText),
);

/// A [Text] widget with [text] nested inside the well keyed [wellKey].
Finder _textUnder(Key wellKey, String text) =>
    find.descendant(of: find.byKey(wellKey), matching: find.text(text));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ==========================================================================
  // A. SUFFIX VISIBILITY CONTRACT
  //    hideSuffixWhenActive=true (price fields): "грн" hides with content.
  //    hideSuffixWhenActive=false (duration well): "хв" is always visible.
  // ==========================================================================
  group('PricingField — suffix visibility contract (hideSuffixWhenActive)', () {
    // Map of well labels → (mode, wellKey) for the three price wells.
    const Map<String, ({ServicePriceType mode, Key well})> priceWells = {
      'FIXED amount': (
        mode: ServicePriceType.fixed,
        well: Key('pricing-fixed-amount'),
      ),
      'RANGE min': (
        mode: ServicePriceType.range,
        well: Key('pricing-range-min'),
      ),
      'RANGE max': (
        mode: ServicePriceType.range,
        well: Key('pricing-range-max'),
      ),
    };

    for (final entry in priceWells.entries) {
      final String label = entry.key;
      final ServicePriceType mode = entry.value.mode;
      final Key well = entry.value.well;

      // A1: empty + unfocused → "грн" present.
      testWidgets('A1 $label: empty+unfocused field — "грн" is PRESENT', (
        tester,
      ) async {
        // No primeValue → controllers start empty → suffix is visible.
        await _pump(tester, mode: mode, width: 360);

        expect(
          find.text(_kPriceSuffix),
          findsWidgets,
          reason:
              '$label: "грн" must be visible when the price field is '
              'empty and unfocused',
        );
        expect(tester.takeException(), isNull);
      });

      // A2: empty + unfocused → "грн" not overlapping the input.
      testWidgets(
        'A2 $label: empty+unfocused field — "грн" does not overlap input',
        (tester) async {
          await _pump(tester, mode: mode, width: 360);

          expect(_editableUnder(well), findsOneWidget);
          expect(_textUnder(well, _kPriceSuffix), findsOneWidget);

          final Rect input = tester.getRect(_editableUnder(well));
          final Rect suffix = tester.getRect(_textUnder(well, _kPriceSuffix));

          // No horizontal overlap: input's right edge ≤ suffix's left edge.
          expect(
            input.right,
            lessThanOrEqualTo(suffix.left + _kEps),
            reason:
                '$label: the EditableText must not overrun the "грн" suffix '
                'when the field is empty and unfocused',
          );

          // The tightened gap (VelvetSpacing.xs, 4 dp) must be present.
          expect(
            suffix.left - input.right,
            greaterThanOrEqualTo(_kSuffixGap - _kEps),
            reason:
                '$label: field→suffix gap must be at least VelvetSpacing.xs '
                '($_kSuffixGap dp) for the 3-column RANGE layout',
          );

          expect(tester.takeException(), isNull);
        },
      );

      // A3: field with content → "грн" is ABSENT (hideSuffixWhenActive=true).
      testWidgets('A3 $label: field with content — "грн" is ABSENT', (
        tester,
      ) async {
        // primeValuePrice → controllers start non-empty → suffix hides.
        await _pump(tester, mode: mode, width: 360, primeValuePrice: '500');

        expect(
          _textUnder(well, _kPriceSuffix),
          findsNothing,
          reason:
              '$label: "грн" must be HIDDEN when the price field has content '
              '(hideSuffixWhenActive=true)',
        );
        expect(tester.takeException(), isNull);
      });
    }

    // A4: duration well "хв" — always visible regardless of content.
    testWidgets(
      'A4 duration well: "хв" is ALWAYS present regardless of content',
      (tester) async {
        // Pump with a non-empty duration value; "хв" must stay visible.
        final handles = await _pump(
          tester,
          mode: ServicePriceType.fixed,
          width: 360,
          withDuration: true,
        );

        // Seed the duration controller with a value to simulate non-empty state.
        handles.durationCtrl!.text = '60';
        await tester.pump();

        expect(
          find.text(_kDurationSuffix),
          findsOneWidget,
          reason:
              'duration "хв" must be visible even when the field has content '
              '(hideSuffixWhenActive=false on the duration well)',
        );
        expect(tester.takeException(), isNull);
      },
    );

    // A4b: duration well with empty field also shows "хв".
    testWidgets(
      'A4b duration well: "хв" is ALWAYS present when field is empty',
      (tester) async {
        await _pump(
          tester,
          mode: ServicePriceType.fixed,
          width: 360,
          withDuration: true,
        );

        expect(
          find.text(_kDurationSuffix),
          findsOneWidget,
          reason: 'duration "хв" must be visible when the field is empty',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ==========================================================================
  // B. VERTICAL GROWTH (original clipping bug guard — large text scale).
  //    A ConstrainedBox(minHeight) grows; a hard SizedBox(height) clamps.
  //    Exercised only on the FIXED well (which is identical to range wells
  //    at the _PricingInputField level); the test still passes with content
  //    absent — vertical growth is independent of suffix visibility.
  // ==========================================================================
  group(
    'PricingField — well grows under large text scale (no vertical clip)',
    () {
      const Map<String, ({ServicePriceType mode, Key well})> targets = {
        'FIXED amount': (
          mode: ServicePriceType.fixed,
          well: Key('pricing-fixed-amount'),
        ),
        'RANGE min': (
          mode: ServicePriceType.range,
          well: Key('pricing-range-min'),
        ),
        'RANGE max': (
          mode: ServicePriceType.range,
          well: Key('pricing-range-max'),
        ),
      };

      for (final entry in targets.entries) {
        final String label = entry.key;
        final ServicePriceType mode = entry.value.mode;
        final Key well = entry.value.well;

        testWidgets(
          '$label: well grows beyond VelvetSizes.field at 2.5× text scale',
          (tester) async {
            const double scale = 2.5; // 16sp → 40sp, well above 29dp inner min.
            // Use a wide box so the scaled toggle labels don't overflow.
            await _pump(
              tester,
              mode: mode,
              width: 700,
              textScale: scale,
              // No primeValuePrice: the vertical growth test does not need the
              // suffix to be present or absent — it only checks the well height.
            );

            const double scaledLine = _kInputFontSize * scale;
            expect(
              scaledLine,
              greaterThan(_kInnerMinHeight),
              reason:
                  'precondition: scaled line ($scaledLine) must exceed '
                  'inner min-height ($_kInnerMinHeight)',
            );

            final double wellHeight = tester.getSize(find.byKey(well)).height;
            expect(
              wellHeight,
              greaterThan(VelvetSizes.field),
              reason:
                  '$label: well must grow above VelvetSizes.field '
                  '(${VelvetSizes.field}) under 2.5× scale — a hard SizedBox '
                  'would clamp it',
            );

            final RenderBox editableBox = tester.renderObject<RenderBox>(
              _editableUnder(well),
            );
            final double paint = editableBox.size.height;
            expect(
              paint,
              greaterThanOrEqualTo(scaledLine - 2.0),
              reason:
                  '$label: EditableText paint height ($paint) must not be '
                  'truncated below the scaled line height ($scaledLine)',
            );

            expect(tester.takeException(), isNull);
          },
        );
      }
    },
  );

  // ==========================================================================
  // C. NARROW ONE-LINE LAYOUT
  //    Min/max wells are always side-by-side (no stacking breakpoint).
  // ==========================================================================
  group('PricingField — narrow RANGE layout: min/max on one line', () {
    testWidgets(
      'C1–C2: at 219dp min/max are side-by-side and non-overlapping',
      (tester) async {
        await _pump(
          tester,
          mode: ServicePriceType.range,
          width: 219, // narrow phone
          // No primeValuePrice: the layout test doesn't need suffix hiding.
        );

        const Key minKey = Key('pricing-range-min');
        const Key maxKey = Key('pricing-range-max');

        final Rect minWell = tester.getRect(find.byKey(minKey));
        final Rect maxWell = tester.getRect(find.byKey(maxKey));

        // C1: equal tops → one line (no stacking).
        expect(
          minWell.top,
          closeTo(maxWell.top, _kEps),
          reason: 'min/max must be on one line (equal tops) at 219dp',
        );

        // C2: non-overlapping horizontally.
        expect(
          minWell.right,
          lessThanOrEqualTo(maxWell.left + _kEps),
          reason: 'min/max wells must not overlap horizontally at 219dp',
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'no RenderFlex overflow in the narrow one-line range row',
        );
      },
    );
  });

  // ==========================================================================
  // D. RANGE TRUNCATION + DASH ALIGNMENT (regression guards for user-reported
  //    bugs in the non-compact 3-column RANGE layout at realistic phone width).
  //
  //   D1. No-truncation guard: each RANGE well must be wide enough to display
  //       a typical price value ("8000") without clipping digits. The fix
  //       tightened affixGap to VelvetSpacing.xs (4 dp); reverting to md (16)
  //       would reduce digit area below the safe threshold and fail this test.
  //
  //   D2. Dash vertical-center guard: the '–' separator must sit on the well's
  //       input line (vertical center ≈ the min-well's center), NOT near the
  //       top of the row (the pre-fix "shifted to top" regression).
  // ==========================================================================
  group('PricingField — non-compact RANGE at 360dp: truncation + dash alignment', () {
    // Minimum digit-area width that "8000" (~36 dp at 16sp Nunito) requires
    // with a small safety margin. Any regression that reduces digit space
    // below this value (e.g. reverting affixGap to md=16) will fail D1.
    //
    // Geometry at 360 dp with 32 dp of Scaffold body padding:
    //   row width ≈ 328 dp; dash column ≈ 2×xs + text ≈ 16 dp.
    //   3 equal Expanded wells → each ≈ (328 − 8 gap − 16 dash) / 3 ≈ 101 dp.
    //   digit area = wellWidth − 2×wellHPad(sm=8) − affixGap(xs=4) − suffix.
    //   "грн" suffix width ≈ 28 dp → digit area ≈ 101 − 16 − 4 − 28 ≈ 53 dp.
    //   The guard uses 40 dp as a conservative floor (well above "8000" ~36 dp).
    const double kMinDigitArea = 40.0;

    // Tolerance for the vertical-alignment guard (font rounding, 1 dp slack).
    const double kAlignTol = 2.0;

    // Minimum sane well width at 360 dp. Guard ensures affixGap didn't balloon.
    const double kMinWellWidth = 88.0;

    // D1 — digit area wide enough for "8000" in non-compact RANGE at 360 dp.
    testWidgets(
      'D1: non-compact RANGE at 360dp — "8000" min/max field is not truncated',
      (tester) async {
        // Prime the min/max controllers with a typical value so the suffix
        // hides (hideSuffixWhenActive=true) and only the digit area is active.
        // This is the exact scenario the user reported as "5... грн".
        await _pump(
          tester,
          mode: ServicePriceType.range,
          width: 360,
          primeValuePrice: '8000',
        );

        const Key minKey = Key('pricing-range-min');
        const Key maxKey = Key('pricing-range-max');

        // Suffix is hidden (primeValuePrice set), so we measure the well box.
        final double minWellWidth = tester.getSize(find.byKey(minKey)).width;
        final double maxWellWidth = tester.getSize(find.byKey(maxKey)).width;

        // Each well must be at least kMinWellWidth dp — narrower means the
        // affixGap or horizontal padding ballooned back to md=16.
        expect(
          minWellWidth,
          greaterThanOrEqualTo(kMinWellWidth),
          reason:
              'RANGE min well must be at least ${kMinWellWidth}dp wide at '
              '360dp — narrower means affixGap or wellHPad reverted to '
              'VelvetSpacing.md (the truncation cause)',
        );
        expect(
          maxWellWidth,
          greaterThanOrEqualTo(kMinWellWidth),
          reason:
              'RANGE max well must be at least ${kMinWellWidth}dp wide at '
              '360dp — narrower means affixGap or wellHPad reverted to '
              'VelvetSpacing.md (the truncation cause)',
        );

        // Digit area check: well − 2×wellHPad(sm=8) − affixGap(xs=4) ≥ 40 dp.
        // Suffix is hidden so the full EditableText width IS the digit area.
        final double editableWidth = tester
            .getSize(_editableUnder(minKey))
            .width;
        expect(
          editableWidth,
          greaterThanOrEqualTo(kMinDigitArea),
          reason:
              'The EditableText width inside the RANGE min well must be at '
              'least ${kMinDigitArea}dp so "8000" is not clipped. '
              'Current width: ${editableWidth}dp. '
              'Regression indicator: affixGap reverted from xs(4) to md(16).',
        );

        expect(tester.takeException(), isNull);
      },
    );

    // D1b — pin the exact affixGap token: VelvetSpacing.xs (4 dp).
    // If a future edit widens it back to sm(8) or md(16) the suffix would
    // crowd digits. This test asserts the gap via the rendered geometry: when
    // the suffix IS visible (empty, unfocused) the gap = suffix.left − input.right.
    testWidgets(
      'D1b: non-compact RANGE at 360dp empty field — affixGap == VelvetSpacing.xs (4dp)',
      (tester) async {
        await _pump(
          tester,
          mode: ServicePriceType.range,
          width: 360,
          // No primeValuePrice: suffix must be visible to measure the gap.
        );

        const Key minKey = Key('pricing-range-min');

        final Rect editableRect = tester.getRect(_editableUnder(minKey));
        final Rect suffixRect = tester.getRect(
          _textUnder(minKey, _kPriceSuffix),
        );

        final double measuredGap = suffixRect.left - editableRect.right;

        // The gap must equal VelvetSpacing.xs (4 dp), ±ε.
        // A regression to sm(8) or md(16) would widen the gap beyond the
        // upper bound and indicate the affix is consuming digit space again.
        expect(
          measuredGap,
          inInclusiveRange(
            VelvetSpacing.xs - _kEps,
            VelvetSpacing.sm - _kEps, // anything < sm(8) is acceptable
          ),
          reason:
              'non-compact RANGE affixGap must be VelvetSpacing.xs (4 dp). '
              'Measured gap: ${measuredGap}dp. '
              'Regression: if gap >= sm(8) the affix crowded the digit area '
              'and caused the "5... грн" truncation.',
        );

        expect(tester.takeException(), isNull);
      },
    );

    // D2 — the '–' separator vertical center must align with the wells.
    //
    // Before the fix _buildDash(compact:false) had no label-height offset,
    // so the Center was computed over the full Column height (label + well),
    // placing the dash near the top of the row. The fix mirrors the sibling
    // label-row height via an Opacity(0) placeholder, then Centers the dash
    // inside a SizedBox(VelvetSizes.field) — putting it exactly at the well's
    // midpoint. This test catches a revert of that fix.
    testWidgets(
      'D2: non-compact RANGE at 360dp — "–" dash is vertically centered on the well',
      (tester) async {
        await _pump(tester, mode: ServicePriceType.range, width: 360);

        const Key minKey = Key('pricing-range-min');

        // Locate the dash Text widget.
        final Finder dashFinder = find.text('–');
        expect(
          dashFinder,
          findsOneWidget,
          reason: 'the "–" separator must be present in non-compact RANGE',
        );

        final Rect dashRect = tester.getRect(dashFinder);
        final Rect minWellRect = tester.getRect(find.byKey(minKey));

        final double dashCenterY = dashRect.center.dy;
        final double wellCenterY = minWellRect.center.dy;

        // The dash center must be within kAlignTol of the well's center.
        // A regression to the old layout would shift the dash ≈ half the
        // label-row height (~10–14 dp) upward, exceeding this tolerance.
        expect(
          dashCenterY,
          closeTo(wellCenterY, kAlignTol),
          reason:
              '"–" vertical center (${dashCenterY}dp) must be within '
              '${kAlignTol}dp of the min well center (${wellCenterY}dp). '
              'A larger offset indicates _buildDash() reverted to the '
              '"shifted to top" layout (missing label-height placeholder).',
        );

        expect(tester.takeException(), isNull);
      },
    );
  });
}
