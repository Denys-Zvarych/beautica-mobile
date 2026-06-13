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
//      so long values crowded the suffix. Fix: bumped to VelvetSpacing.md (16dp).
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

/// The bumped field→suffix gap. The fix raised this from VelvetSpacing.sm (8)
/// to VelvetSpacing.md (16); the guard asserts the larger value only when the
/// suffix is actually visible (empty + unfocused field).
const double _kSuffixGap = VelvetSpacing.md;

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

          // The bumped gap (VelvetSpacing.md) must be present.
          expect(
            suffix.left - input.right,
            greaterThanOrEqualTo(_kSuffixGap - _kEps),
            reason:
                '$label: field→suffix gap must be at least VelvetSpacing.md '
                '($_kSuffixGap dp) when "грн" is visible',
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
}
