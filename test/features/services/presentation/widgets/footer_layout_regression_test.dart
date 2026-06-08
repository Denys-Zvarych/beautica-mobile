// Regression tests for the CTA-label truncation bug (footer layout fix).
//
// Bug: the submit CTA ("Надіслати" + send icon) was wrapped in Flexible inside
// a side-by-side Row[Cancel, Flexible(Submit)].  On a ~360 dp phone the Cancel
// button consumed ~100 dp of natural width, leaving the Flexible CTA with only
// ~116 dp inside a double-padded card (redundant inner Padding eating 24 dp/side
// on top of NeumorphicCard's own 24 dp/side padding).  NeumorphicButton renders
// Row(mainAxisSize:min)[Icon(20)+SizedBox(8)+Flexible(Text(overflow:ellipsis))];
// with only ~116 dp the icon+gap alone consumed 28 dp, leaving ~88 dp for the
// Flexible Text — far less than the ~106 dp needed for "Надіслати" in Comfortaa
// 16 px/700 — so the label ellipsized to "Надісл…".
//
// Fix: the footer is now a stacked Column (full-width NeumorphicButton above a
// centred Cancel TextButton).  crossAxisAlignment.stretch on the parent Column
// stretches the NeumorphicButton to the full card content width.  The redundant
// inner Padding was also removed.
//
// ─────────────────────────────────────────────────────────────────────────────
// HONEST STATEMENT about flutter_test and ellipsis detection
// ─────────────────────────────────────────────────────────────────────────────
// flutter_test runs on the host without a real GPU / text shaper.  Comfortaa is
// a web font served via google_fonts; in the test environment google_fonts falls
// back to the system default font (Roboto / FallbackFont), so TextPainter
// measurements differ from the on-device values.
//
// Consequence: directly asserting `RenderParagraph.didExceedMaxLines == false`
// or comparing painted-text-width to an unconstrained TextPainter layout is
// UNRELIABLE — the measurement would be for the fallback font, not Comfortaa,
// and would produce a false-passing test against the bug (the fallback font may
// be narrower and fit even in the squeezed Flexible).
//
// What IS deterministically verifiable in flutter_test and DOES distinguish
// old from new:
//   1. Footer structure: NeumorphicButton is a direct Column child at index 6
//      (crossAxisAlignment.stretch), NOT inside a Row together with Cancel.
//   2. Render width: the NeumorphicButton's rendered width equals the full
//      card content width (≈ 264 dp on 360 dp).  Under the old layout the
//      button was squeezed to ~130 dp by its Row sibling.
//   3. No Row ancestor contains BOTH the submit and cancel buttons.
//
// These three assertions WOULD HAVE FAILED against the old layout at 360 dp
// because:
//   (1) old: NeumorphicButton was a child of Flexible which was a child of Row;
//       it was NOT a direct Column child.
//   (2) old: button render width ≈ 130 dp, not ≈ 264 dp.
//   (3) old: a Row existed whose descendant subtree contained both buttons.
//
// ─────────────────────────────────────────────────────────────────────────────
// Layout math (for reference)
// ─────────────────────────────────────────────────────────────────────────────
// Screen width           = 360 dp  (logical, dpr=1)
// Dialog insetPadding.h  = VelvetSpacing.lg × 2 = 48 dp  → dialog  = 312 dp
// NeumorphicCard pad.h   = VelvetSpacing.lg × 2 = 48 dp  → content = 264 dp
// Fixed layout: CTA width = 264 dp (full content width, stretched by Column).
// Old layout:   CTA width ≈ 264 − 48 (redundant Padding) − ~80 (Cancel) ≈ 136 dp
//               → Comfortaa 16px "Надіслати" + 20px icon requires > 136 dp → ellipsis.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_type_suggestion_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ─────────────────────────────────────────────────────────────────────────────
// Shared constants
// ─────────────────────────────────────────────────────────────────────────────

// Narrow phone viewport — the width at which the old layout truncated the label.
// 360 logical pixels × dpr 1.0 so logical px == physical px in the test.
const _kNarrowWidth = 360.0;
const _kNarrowHeight = 800.0;
const _kNarrowDpr = 1.0;

// Dialog geometry (mirrors production constants):
//   insetPadding.horizontal = VelvetSpacing.lg × 2 = 48 dp
//   NeumorphicCard padding   = VelvetSpacing.lg × 2 = 48 dp (each side)
// → card content width on a 360 dp screen = 360 - 48 = 312 dp for the dialog,
//   312 - 48 = 264 dp for card content.
const double _kExpectedCtaWidth = _kNarrowWidth - 48.0 - 48.0; // 264 dp

// ─────────────────────────────────────────────────────────────────────────────
// Pump helpers — pump the dialog widget directly (not via route push) at the
// narrow viewport.  No GoRouter needed: the regression tests exercise layout
// geometry, not navigation.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _pumpServiceTypeSuggestionDialog(
  WidgetTester tester,
  _MockServiceRepository repo,
) async {
  tester.view.physicalSize = const Size(_kNarrowWidth, _kNarrowHeight);
  tester.view.devicePixelRatio = _kNarrowDpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: Scaffold(
          body: Center(
            child: ServiceTypeSuggestionDialog(categoryName: 'EYELASH'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpCategoryRequestDialog(
  WidgetTester tester,
  _MockServiceRepository repo,
) async {
  tester.view.physicalSize = const Size(_kNarrowWidth, _kNarrowHeight);
  tester.view.devicePixelRatio = _kNarrowDpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('uk'),
        home: Scaffold(body: Center(child: CategoryRequestDialog())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Returns true when the widget identified by [key] is a DIRECT child of at
/// least one Column widget in the tree (i.e. it appears in Column.children,
/// not just as a deeper descendant).
///
/// Used to assert that NeumorphicButton is a direct Column child in the fixed
/// layout.  In the old layout it was Flexible → NeumorphicButton, where
/// Flexible was a child of a Row which was a child of the Column — so the
/// NeumorphicButton widget appeared in NO Column's direct children list.
bool _isDirectColumnChild(WidgetTester tester, Key key) {
  for (final col in tester.widgetList<Column>(find.byType(Column))) {
    for (final child in col.children) {
      if (child.key == key) return true;
    }
  }
  return false;
}

/// Returns true when ANY Row widget's descendant subtree contains BOTH
/// [submitFinder] and [cancelFinder].
///
/// In the old layout: Row[TextButton(cancel), Flexible(NeumorphicButton(submit))]
/// — both buttons were descendants of the same Row → returns true.
///
/// In the fixed layout: the footer Row only exists inside NeumorphicButton
/// itself (the Icon+Label row) and inside the cancel Center — no Row contains
/// BOTH buttons → returns false.
bool _anyRowContainsBothButtons(
  WidgetTester tester,
  Finder submitFinder,
  Finder cancelFinder,
) {
  for (final rowElement in tester.elementList(find.byType(Row))) {
    // Collect all elements in this Row's subtree.
    bool hasSubmit = false;
    bool hasCancel = false;

    rowElement.visitChildren((child) {
      // Check transitively.
      child.visitChildren((_) => true); // force tree walk via visitor
    });

    // Simpler approach: check if both finders match within this Row's subtree.
    final rowFinder = find.byElementPredicate((e) => e == rowElement);
    hasSubmit = find
        .descendant(of: rowFinder, matching: submitFinder)
        .evaluate()
        .isNotEmpty;
    hasCancel = find
        .descendant(of: rowFinder, matching: cancelFinder)
        .evaluate()
        .isNotEmpty;

    if (hasSubmit && hasCancel) return true;
  }
  return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  late _MockServiceRepository repo;

  setUp(() => repo = _MockServiceRepository());

  // ===========================================================================
  // ServiceTypeSuggestionDialog
  // ===========================================================================

  group('ServiceTypeSuggestionDialog — footer layout regression', () {
    // -------------------------------------------------------------------------
    // Test A: structural — NeumorphicButton is a DIRECT Column child.
    //
    // WHY this catches the bug:
    //   Old layout: the NeumorphicButton appeared as
    //     Card-Column → Row → Flexible → NeumorphicButton
    //   It was NOT in any Column's direct children list.
    //   → _isDirectColumnChild returns false (old).
    //   → _isDirectColumnChild returns true  (new — Column[…, NeumorphicButton, …]).
    //
    // This is a widget-tree assertion (Column.children list), independent of
    // font metrics, so it is deterministic in the headless test environment.
    // -------------------------------------------------------------------------
    testWidgets('A. submit NeumorphicButton is a DIRECT Column child at 360 dp '
        '(not nested inside a Row)', (tester) async {
      await _pumpServiceTypeSuggestionDialog(tester, repo);

      const submitKey = Key('btn-submit-suggest-service-type');
      const cancelKey = Key('btn-cancel-suggest-service-type');

      expect(find.byKey(submitKey), findsOneWidget);
      expect(find.byKey(cancelKey), findsOneWidget);

      // Fixed layout: NeumorphicButton is a direct Column child.
      expect(
        _isDirectColumnChild(tester, submitKey),
        isTrue,
        reason:
            'NeumorphicButton(btn-submit-suggest-service-type) must be a '
            'direct child of a Column widget. In the old buggy layout it was '
            'Column → Row → Flexible → NeumorphicButton and therefore NOT a '
            'direct Column child — this assertion would fail against the bug.',
      );

      // Fixed layout: no Row should contain BOTH the submit and cancel buttons.
      expect(
        _anyRowContainsBothButtons(
          tester,
          find.byKey(submitKey),
          find.byKey(cancelKey),
        ),
        isFalse,
        reason:
            'No Row widget must contain both the submit CTA and the cancel '
            'TextButton as descendants. The old Row[Cancel, Flexible(Submit)] '
            'layout placed them side-by-side, squeezing the CTA width on '
            '360 dp screens and causing label ellipsis.',
      );
    });

    // -------------------------------------------------------------------------
    // Test B: render width — the NeumorphicButton must span the full card
    // content width at 360 dp.
    //
    // Layout math (fixed layout, 360 dp logical, dpr=1):
    //   dialog width  = screen(360) - insetPadding.h(48)         = 312 dp
    //   card content  = dialog(312) - cardPadding.h(48)          = 264 dp
    //   → NeumorphicButton width must be ≈ 264 dp.
    //
    // Old layout (Row + redundant Padding):
    //   available for Row = 264 - extraPadding.h(48) = 216 dp
    //   Flexible CTA width = 216 - naturalWidthOfCancel (≈ 80–110 dp) ≈ 106–136 dp
    //   → button width ≈ 106–136 dp, NOT 264 dp.
    //
    // WHY this catches the bug: in the old layout the button's render width was
    // ~130 dp, well below 264 dp.  This assertion fails against the old code
    // and passes against the new code.
    //
    // NOTE: This is a render-phase measurement (tester.getSize) that does NOT
    // depend on font metrics — it reflects the layout engine's constraint
    // propagation, which is fully deterministic in flutter_test.
    // -------------------------------------------------------------------------
    testWidgets(
      'B. NeumorphicButton rendered width equals full card-content width '
      '(not squeezed by a sibling Cancel button) at 360 dp',
      (tester) async {
        await _pumpServiceTypeSuggestionDialog(tester, repo);

        final ctaSize = tester.getSize(
          find.byKey(const Key('btn-submit-suggest-service-type')),
        );

        // Use a 4 dp tolerance for sub-pixel rounding on the dialog inset math.
        expect(
          ctaSize.width,
          greaterThanOrEqualTo(_kExpectedCtaWidth - 4),
          reason:
              'NeumorphicButton must span the full card-content width '
              '(≥ ${_kExpectedCtaWidth - 4} dp on a 360 dp screen). '
              'Under the old Row[Cancel, Flexible(Submit)] layout with redundant '
              'inner Padding the button was constrained to ~130 dp and its '
              '"Надіслати" label ellipsized to "Надісл…".',
        );
      },
    );

    // -------------------------------------------------------------------------
    // Test C: no redundant Padding wraps the submit CTA in the card Column.
    //
    // The old layout had Padding(all: VelvetSpacing.lg = 24 dp) as an intermediate
    // Column child wrapping the footer Row.  The fix removed it, making
    // NeumorphicButton a direct Column child (verified by Test A).  Test C is an
    // independent confirmation: we assert that the Column whose child IS the
    // NeumorphicButton uses crossAxisAlignment.stretch — meaning the Column
    // itself provides the stretch without a Padding narrowing the space first.
    //
    // WHY this catches the bug: the old Column had crossAxisAlignment.stretch
    // too, but the Padding(all:24) inside it created a narrower child space
    // before the Row even ran.  In the new layout the Column child directly
    // IS the NeumorphicButton, so the stretch is direct.
    // -------------------------------------------------------------------------
    testWidgets(
      'C. the Column containing the submit CTA uses stretch alignment '
      '(CTA is not padded-then-stretched)',
      (tester) async {
        await _pumpServiceTypeSuggestionDialog(tester, repo);

        const submitKey = Key('btn-submit-suggest-service-type');

        // Find the Column that directly contains the submit button and confirm
        // it uses crossAxisAlignment.stretch so the CTA expands to full width.
        Column? parentColumn;
        for (final col in tester.widgetList<Column>(find.byType(Column))) {
          for (final child in col.children) {
            if (child.key == submitKey) {
              parentColumn = col;
              break;
            }
          }
          if (parentColumn != null) break;
        }

        expect(
          parentColumn,
          isNotNull,
          reason: 'A Column directly containing the submit button must exist.',
        );
        expect(
          parentColumn!.crossAxisAlignment,
          CrossAxisAlignment.stretch,
          reason:
              'The Column that directly parents the NeumorphicButton must use '
              'CrossAxisAlignment.stretch so the CTA expands to the full card '
              'content width without a narrowing Padding wrapper.',
        );
      },
    );
  });

  // ===========================================================================
  // CategoryRequestDialog — same three structural / width / stretch assertions.
  // ===========================================================================

  group('CategoryRequestDialog — footer layout regression', () {
    testWidgets('A. submit NeumorphicButton is a DIRECT Column child at 360 dp '
        '(not nested inside a Row)', (tester) async {
      await _pumpCategoryRequestDialog(tester, repo);

      const submitKey = Key('btn-submit-suggest-category');
      const cancelKey = Key('btn-cancel-suggest-category');

      expect(find.byKey(submitKey), findsOneWidget);
      expect(find.byKey(cancelKey), findsOneWidget);

      expect(
        _isDirectColumnChild(tester, submitKey),
        isTrue,
        reason:
            'NeumorphicButton(btn-submit-suggest-category) must be a direct '
            'child of a Column. In the old buggy layout it was inside '
            'Column → Row → Flexible → NeumorphicButton — not a direct child.',
      );

      expect(
        _anyRowContainsBothButtons(
          tester,
          find.byKey(submitKey),
          find.byKey(cancelKey),
        ),
        isFalse,
        reason:
            'No Row widget must contain both the submit CTA and the cancel '
            'TextButton. The old Row[Cancel, Flexible(Submit)] layout caused '
            'label ellipsis on 360 dp screens.',
      );
    });

    testWidgets(
      'B. NeumorphicButton rendered width equals full card-content width '
      '(not squeezed by a sibling Cancel button) at 360 dp',
      (tester) async {
        await _pumpCategoryRequestDialog(tester, repo);

        final ctaSize = tester.getSize(
          find.byKey(const Key('btn-submit-suggest-category')),
        );

        expect(
          ctaSize.width,
          greaterThanOrEqualTo(_kExpectedCtaWidth - 4),
          reason:
              'NeumorphicButton must span the full card-content width '
              '(≥ ${_kExpectedCtaWidth - 4} dp on a 360 dp screen). '
              'Under the old Row + redundant Padding layout the button was '
              'constrained to ~130 dp and the label ellipsized.',
        );
      },
    );

    testWidgets('C. the Column containing the submit CTA uses stretch alignment '
        '(CTA is not padded-then-stretched)', (tester) async {
      await _pumpCategoryRequestDialog(tester, repo);

      const submitKey = Key('btn-submit-suggest-category');

      Column? parentColumn;
      for (final col in tester.widgetList<Column>(find.byType(Column))) {
        for (final child in col.children) {
          if (child.key == submitKey) {
            parentColumn = col;
            break;
          }
        }
        if (parentColumn != null) break;
      }

      expect(
        parentColumn,
        isNotNull,
        reason: 'A Column directly containing the submit button must exist.',
      );
      expect(
        parentColumn!.crossAxisAlignment,
        CrossAxisAlignment.stretch,
        reason:
            'The Column that directly parents the NeumorphicButton must use '
            'CrossAxisAlignment.stretch so the CTA expands to full card width.',
      );
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// MANUAL VISUAL CHECKLIST
// Items that cannot be deterministically asserted in flutter_test due to
// font-fallback differences in the headless test environment.
// ─────────────────────────────────────────────────────────────────────────────
//
// 1. Run on a real 360 dp phone (or emulator — Pixel 4a has 360 dp logical width):
//    flutter run -d emulator-5554
//    Navigate: service-type picker → tap "Запропонувати тип послуги".
//    VERIFY: the CTA pill shows the FULL "Надіслати" label with the send icon.
//    No ellipsis ("Надісл…").
//
// 2. Same check for the category-request dialog:
//    Navigate: service picker → tap "Запропонувати нову категорію".
//    VERIFY: the CTA pill label "Надіслати" is fully visible.
//
// 3. Rotate to landscape on a narrow device (Pixel 4a landscape = 720 dp wide).
//    The Column footer should still look correct: CTA full-width, Cancel centred.
//
// 4. The updated golden snapshots (900 × 1400 logical, dpr=1) in this commit
//    provide a pixel-level baseline.  Confirm the PNGs show:
//    - CTA button spanning edge-to-edge inside the card (no narrow squeeze).
//    - Cancel text centred on its own row below the CTA.
//    - No "…" glyph in the CTA label glyph block area.
