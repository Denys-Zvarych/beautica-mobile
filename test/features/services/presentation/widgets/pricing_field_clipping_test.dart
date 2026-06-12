// Regression guard — price-field clipping / "грн"-suffix occlusion (Step 2.7
// Rule 3).
//
// The bug: typed price digits read as hidden "under" the "грн" suffix. Two
// distinct defects in [_PricingInputField] (lib/.../widgets/pricing_field.dart):
//
//   1. VERTICAL CLIP — the input Row was wrapped in a HARD-height
//      `SizedBox(height: VelvetSizes.field - 2*(VelvetSpacing.sm+2))` (= 29dp)
//      with `isCollapsed: true` + zero contentPadding. A hard box clamps the
//      Row to exactly 29dp, so when the rendered single-line glyph height
//      exceeds 29dp (16sp Nunito + cursor, larger system text scale) the
//      EditableText is clipped top/bottom — digits look truncated/occluded.
//      Fix: `ConstrainedBox(minHeight: …)` so the box GROWS to the natural
//      line height instead of clamping.
//
//   2. HORIZONTAL CROWDING — the field→"грн" gap was `VelvetSpacing.sm` (8dp),
//      so long values crowded the right edge hard against the suffix and read
//      as overlapping. Fix: bumped the gap to `VelvetSpacing.md` (16dp).
//
// The "грн" suffix is a non-overlapping Row sibling: Expanded(TextField) + gap
// + Text("грн"). The same `_PricingInputField` backs FIXED, range-min and
// range-max, so guarding one mode per axis covers all three.
//
// Pre-fix (hard 29dp SizedBox + 8dp gap) these assertions FAIL:
//   • the gap assertion fails (8 < VelvetSpacing.md = 16);
//   • the vertical-growth assertion fails (hard box never grows past 29dp, so
//     the well stays clamped and the EditableText paint height is truncated
//     below the scaled font line height).
// Post-fix they PASS. Verified by reverting the ConstrainedBox+gap change.
//
// Deterministic: no backend, no Dio, fixed-width box, default test font, text
// asserted via the "грн" unit token (the literal under test) + stable keys.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Constants mirrored from the widget under test (kept in sync via tokens).
// ---------------------------------------------------------------------------

/// The bumped field→suffix gap. The fix raised this from `VelvetSpacing.sm`
/// (8) to `VelvetSpacing.md` (16); the guard asserts the larger value.
const double _kSuffixGap = VelvetSpacing.md;

/// The single-line input font size (`VelvetText.input()` is 16sp Nunito).
const double _kInputFontSize = 16.0;

/// Inner min-height the well's input Row is constrained to: the fixed control
/// height minus the symmetric vertical padding of the inner [Padding].
const double _kInnerMinHeight = VelvetSizes.field - 2 * (VelvetSpacing.sm + 2);

/// "грн" — the Ukrainian currency unit token rendered as the suffix. It is the
/// literal under test (the thing digits were reported to hide behind), so we
/// assert against it directly rather than via an l10n key.
const String _kSuffix = 'грн';

/// A value long enough to push the digits toward the suffix edge.
const String _kLongValue = '99999999.99';

/// Sub-pixel slack for edge/gap comparisons (font/layout rounding).
const double _kEps = 0.01;

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Pumps a [PricingField] inside a fixed-[width] box with UK l10n. [mode]
/// selects FIXED vs RANGE. [textScale] inflates the system text scaler so the
/// rendered line height exceeds the inner min-height — this is what exposes the
/// hard-`SizedBox` vertical clip (a `ConstrainedBox` grows; a `SizedBox` does
/// not). [primeValue], when non-null, is loaded into all three controllers so a
/// long value is on screen.
Future<_PricingHandles> _pump(
  WidgetTester tester, {
  required ServicePriceType mode,
  double width = 360,
  double textScale = 1.0,
  String? primeValue,
}) async {
  final fixedCtrl = TextEditingController(text: primeValue ?? '');
  final minCtrl = TextEditingController(text: primeValue ?? '');
  final maxCtrl = TextEditingController(text: primeValue ?? '');
  addTearDown(fixedCtrl.dispose);
  addTearDown(minCtrl.dispose);
  addTearDown(maxCtrl.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            // Inherit the test window's media query but override the scaler so
            // the input line height is forced taller than the inner min-height.
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
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return const _PricingHandles();
}

/// Marker type so the harness reads as intentional; no payload needed.
class _PricingHandles {
  const _PricingHandles();
}

/// The [EditableText] nested under the well keyed [wellKey].
Finder _editableUnder(Key wellKey) => find.descendant(
  of: find.byKey(wellKey),
  matching: find.byType(EditableText),
);

/// The "грн" suffix [Text] nested under the well keyed [wellKey].
Finder _suffixUnder(Key wellKey) =>
    find.descendant(of: find.byKey(wellKey), matching: find.text(_kSuffix));

/// Painted height of the [EditableText]'s render object (its laid-out box, not
/// just the constraint). A clipped hard-box truncates this below the font line
/// height; a grown ConstrainedBox does not.
double _editablePaintHeight(WidgetTester tester, Key wellKey) {
  final RenderBox box = tester.renderObject<RenderBox>(_editableUnder(wellKey));
  return box.size.height;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PricingField — digits never occluded by the "грн" suffix', () {
    // The fixed-mode well plus both range wells share one [_PricingInputField],
    // so the horizontal-gap guard is exercised against every key.
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

      // ── HORIZONTAL — input never overlaps the suffix; bumped gap present ──
      testWidgets(
        '$label: long value does not overlap "грн" and keeps the bumped gap',
        (tester) async {
          await _pump(tester, mode: mode, width: 360, primeValue: _kLongValue);

          expect(_editableUnder(well), findsOneWidget);
          expect(_suffixUnder(well), findsOneWidget);

          final Rect input = tester.getRect(_editableUnder(well));
          final Rect suffix = tester.getRect(_suffixUnder(well));

          // No horizontal overlap: the input's right edge sits at or before
          // the suffix's left edge.
          expect(
            input.right,
            lessThanOrEqualTo(suffix.left + _kEps),
            reason:
                '$label: the EditableText must not overrun the "грн" suffix '
                '(digits read as hidden under the suffix when it does)',
          );

          // The bumped field→suffix gap (VelvetSpacing.md) must be present —
          // the pre-fix VelvetSpacing.sm (8) gap fails this.
          expect(
            suffix.left - input.right,
            greaterThanOrEqualTo(_kSuffixGap - _kEps),
            reason:
                '$label: gap between the input and "грн" must be at least '
                'VelvetSpacing.md ($_kSuffixGap); pre-fix it was '
                'VelvetSpacing.sm (8)',
          );

          expect(tester.takeException(), isNull);
        },
      );

      // ── VERTICAL — the box grows; the input line is not clipped ───────────
      // Force a line height taller than the inner min-height via a large text
      // scaler. A hard `SizedBox(height: 29)` clamps the Row to 29dp and clips
      // the EditableText; the `ConstrainedBox(minHeight: 29)` fix lets the well
      // grow to the natural (scaled) line height so nothing is truncated.
      testWidgets(
        '$label: well grows beyond min-height under large text scale (no clip)',
        (tester) async {
          const double scale = 2.5; // 16sp → 40sp line, well above 29dp.
          // Use a wide box: a large text scaler also inflates the mode-toggle
          // labels, which would horizontally overflow the toggle Row at a
          // phone width. The toggle layout is not the subject here — the field
          // well's VERTICAL growth is — so give the row width to render the
          // scaled toggle cleanly and isolate the vertical assertion.
          await _pump(
            tester,
            mode: mode,
            width: 700,
            textScale: scale,
            primeValue: _kLongValue,
          );

          // Scaled single-line glyph height — comfortably above _kInnerMinHeight
          // (29). The default test font lays a line out at ~fontSize tall, so
          // the scaled line is ~40dp.
          const double scaledLine = _kInputFontSize * scale;
          expect(
            scaledLine,
            greaterThan(_kInnerMinHeight),
            reason:
                'precondition: the scaled line ($scaledLine) must exceed the '
                'inner min-height ($_kInnerMinHeight) so a hard box would clip',
          );

          // The well (keyed NeumorphicInset) must have grown past the clamped
          // single-control height; a hard SizedBox would have pinned it.
          final double wellHeight = tester.getSize(find.byKey(well)).height;
          expect(
            wellHeight,
            greaterThan(VelvetSizes.field),
            reason:
                '$label: the well must grow above VelvetSizes.field '
                '(${VelvetSizes.field}) when the line height exceeds the inner '
                'min-height — a hard SizedBox would clamp it instead',
          );

          // The EditableText must be laid out at (at least) the scaled line
          // height — i.e. it was NOT truncated below the font line by a hard
          // box. Allow a small tolerance for font ascent/descent rounding.
          final double paint = _editablePaintHeight(tester, well);
          expect(
            paint,
            greaterThanOrEqualTo(scaledLine - 2.0),
            reason:
                '$label: the EditableText paint height ($paint) must not be '
                'truncated below the scaled line height ($scaledLine); the '
                'pre-fix hard SizedBox clipped it',
          );

          // Even with a tall line, the input still must not overrun "грн".
          final Rect input = tester.getRect(_editableUnder(well));
          final Rect suffix = tester.getRect(_suffixUnder(well));
          expect(
            input.right,
            lessThanOrEqualTo(suffix.left + _kEps),
            reason: '$label: no horizontal overlap even under large text scale',
          );

          expect(tester.takeException(), isNull);
        },
      );
    }

    // ── No overflow at a narrow width — range min/max stay ONE LINE ─────────
    // The width-conditional stacking (_rangeStackBreakpoint = 220dp) was
    // DELETED in the one-line refactor: range min/max are now always side-by-
    // side Expanded slots, so they never overflow no matter how narrow the
    // phone is. At a narrow width with a primed value the inputs must still not
    // overlap each other or their "грн" suffix, and there must be no overflow.
    testWidgets(
      'narrow RANGE (219dp): one-line min/max do not overflow or occlude "грн"',
      (tester) async {
        await _pump(
          tester,
          mode: ServicePriceType.range,
          width: 219, // narrow phone; min/max stay side-by-side (all-Expanded)
          primeValue: '5000', // a realistic value that fits the narrow well
        );

        const Key minKey = Key('pricing-range-min');
        const Key maxKey = Key('pricing-range-max');

        final Rect minWell = tester.getRect(find.byKey(minKey));
        final Rect maxWell = tester.getRect(find.byKey(maxKey));

        // One line: the min/max wells share the same vertical band (no
        // stacking — the 220dp breakpoint is gone).
        expect(
          minWell.top,
          closeTo(maxWell.top, _kEps),
          reason: 'min/max must be on one line (equal tops) at 219dp',
        );

        // Side-by-side, not overlapping: min's right edge is at or before
        // max's left edge.
        expect(
          minWell.right,
          lessThanOrEqualTo(maxWell.left + _kEps),
          reason: 'min/max wells must not overlap horizontally at 219dp',
        );

        for (final Key well in const <Key>[minKey, maxKey]) {
          expect(_editableUnder(well), findsOneWidget);
          final Rect input = tester.getRect(_editableUnder(well));
          final Rect suffix = tester.getRect(_suffixUnder(well));
          expect(
            input.right,
            lessThanOrEqualTo(suffix.left + _kEps),
            reason: 'one-line $well: input must not overrun "грн" at 219dp',
          );
          expect(
            suffix.left - input.right,
            greaterThanOrEqualTo(_kSuffixGap - _kEps),
            reason: 'one-line $well: bumped gap preserved at 219dp',
          );
        }

        expect(
          tester.takeException(),
          isNull,
          reason: 'no RenderFlex overflow in the narrow one-line range row',
        );
      },
    );
  });
}
