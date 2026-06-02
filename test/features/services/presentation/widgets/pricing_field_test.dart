// Phase 5.6 — Widget tests for [PricingField].
//
// Verifies:
//   B1-FIXED-VISIBLE   FIXED mode shows pricing-fixed-amount, hides range keys.
//   B1-RANGE-VISIBLE   RANGE mode shows pricing-range-min + pricing-range-max,
//                      hides pricing-fixed-amount.
//   B1-TAP-RANGE       Tapping pricing-toggle-range fires onModeChanged(range).
//   B1-TAP-FIXED       Tapping pricing-toggle-fixed fires onModeChanged(fixed).
//   B1-RANGE-ERROR     rangeError non-null → error Text + Icons.error_outline_rounded.
//   B1-RANGE-ERROR-NIL rangeError null → Icons.error_outline_rounded absent.
//   B1-DISABLED        enabled:false → Opacity(0.55) wraps the toggle.

import 'package:beautica_mobile/features/services/presentation/widgets/pricing_field.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Pump [PricingField] inside a minimal MaterialApp with UK l10n.
///
/// [mode] controls which segment is active.
/// [onModeChanged] records the value fired by the toggle.
/// [rangeError] / [enabled] are forwarded directly.
Future<void> _pumpField(
  WidgetTester tester, {
  ServicePriceType mode = ServicePriceType.fixed,
  ValueChanged<ServicePriceType>? onModeChanged,
  String? rangeError,
  bool enabled = true,
}) async {
  final fixedCtrl = TextEditingController();
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  addTearDown(fixedCtrl.dispose);
  addTearDown(minCtrl.dispose);
  addTearDown(maxCtrl.dispose);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return PricingField(
              mode: mode,
              onModeChanged: onModeChanged ?? (_) {},
              fixedController: fixedCtrl,
              minController: minCtrl,
              maxController: maxCtrl,
              enabled: enabled,
              rangeError: rangeError,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump(); // settle AnimatedSwitcher
}

// ---------------------------------------------------------------------------
// Test group
// ---------------------------------------------------------------------------

void main() {
  // ── B1-FIXED-VISIBLE ──────────────────────────────────────────────────────

  testWidgets(
    'B1-FIXED-VISIBLE: FIXED mode shows pricing-fixed-amount, hides range keys',
    (tester) async {
      await _pumpField(tester, mode: ServicePriceType.fixed);

      // Fixed field must be present.
      expect(find.byKey(const Key('pricing-fixed-amount')), findsOneWidget);

      // Range fields must be absent (AnimatedSwitcher removes the old child).
      expect(find.byKey(const Key('pricing-range-min')), findsNothing);
      expect(find.byKey(const Key('pricing-range-max')), findsNothing);
    },
  );

  // ── B1-RANGE-VISIBLE ─────────────────────────────────────────────────────

  testWidgets(
    'B1-RANGE-VISIBLE: RANGE mode shows both range keys, hides fixed key',
    (tester) async {
      await _pumpField(tester, mode: ServicePriceType.range);
      // AnimatedSwitcher takes one more frame to finish the cross-fade.
      await tester.pumpAndSettle();

      // Range fields must be present.
      expect(find.byKey(const Key('pricing-range-min')), findsOneWidget);
      expect(find.byKey(const Key('pricing-range-max')), findsOneWidget);

      // Fixed field must be absent.
      expect(find.byKey(const Key('pricing-fixed-amount')), findsNothing);
    },
  );

  // ── B1-TAP-RANGE ─────────────────────────────────────────────────────────

  testWidgets(
    'B1-TAP-RANGE: tapping pricing-toggle-range fires onModeChanged(range)',
    (tester) async {
      ServicePriceType? captured;

      await _pumpField(
        tester,
        mode: ServicePriceType.fixed,
        onModeChanged: (v) => captured = v,
      );

      // The Semantics widget carrying the key is the tappable region.
      await tester.tap(find.byKey(const Key('pricing-toggle-range')));
      await tester.pump();

      expect(captured, ServicePriceType.range);
    },
  );

  // ── B1-TAP-FIXED ─────────────────────────────────────────────────────────

  testWidgets(
    'B1-TAP-FIXED: tapping pricing-toggle-fixed fires onModeChanged(fixed)',
    (tester) async {
      ServicePriceType? captured;

      // Start in RANGE mode so tapping FIXED actually triggers the callback.
      await _pumpField(
        tester,
        mode: ServicePriceType.range,
        onModeChanged: (v) => captured = v,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pricing-toggle-fixed')));
      await tester.pump();

      expect(captured, ServicePriceType.fixed);
    },
  );

  // ── B1-RANGE-ERROR ────────────────────────────────────────────────────────

  testWidgets(
    'B1-RANGE-ERROR: non-null rangeError shows the message Text and error icon',
    (tester) async {
      const errorMsg = 'Максимум має бути більшим за мінімум';
      await _pumpField(
        tester,
        mode: ServicePriceType.range,
        rangeError: errorMsg,
      );
      await tester.pumpAndSettle();

      // The error text must appear somewhere in the widget tree.
      expect(find.text(errorMsg), findsOneWidget);

      // The error icon (error_outline_rounded) must be present.
      expect(find.byIcon(Icons.error_outline_rounded), findsWidgets);
    },
  );

  // ── B1-RANGE-ERROR-NIL ────────────────────────────────────────────────────

  testWidgets(
    'B1-RANGE-ERROR-NIL: null rangeError → Icons.error_outline_rounded absent',
    (tester) async {
      await _pumpField(
        tester,
        mode: ServicePriceType.range,
        rangeError:
            null, // explicit null — hint line shows swap icon, not error
      );
      await tester.pumpAndSettle();

      // No error icon should appear in the range hint row.
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    },
  );

  // ── Bugfix 2 — the always-on RANGE static hint is gone ─────────────────────
  //
  // Regression: RANGE mode used to render a permanent static hint line
  // (l10n.pricingRangeHint, "Максимум має бути більшим за мінімум") beneath the
  // Від/До pair, even with valid input. The fix removed that always-on hint;
  // only the cross-field VALIDATION error (l10n.errPriceMaxGtMin) surfaces, and
  // only when there is an actual range error. Because pricingRangeHint and
  // errPriceMaxGtMin happen to share the same Ukrainian wording, the difference
  // is structural: with NO error, neither the hint text NOR the error icon may
  // appear; with an error, both reappear (covered by B1-RANGE-ERROR above).

  testWidgets(
    'Bugfix 2: RANGE mode with no error shows neither the static hint text '
    'nor the error icon',
    (tester) async {
      await _pumpField(tester, mode: ServicePriceType.range, rangeError: null);
      await tester.pumpAndSettle();

      // Resolve the (now-removed) static hint string from l10n so we never
      // hardcode the Ukrainian literal.
      final BuildContext ctx = tester.element(find.byType(PricingField));
      final AppLocalizations l10n = AppLocalizations.of(ctx);

      // The always-on static hint text must NOT be rendered (it was removed).
      expect(
        find.text(l10n.pricingRangeHint),
        findsNothing,
        reason:
            'Bugfix 2: the always-on RANGE static hint must not render when '
            'there is no range error',
      );
      // …and there must be no error decoration either, since there is no error.
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    },
  );

  // ── Bugfix 2 — the max≤min VALIDATION error STILL renders on bad input ──────
  //
  // The complementary guard: removing the static hint must NOT remove the
  // cross-field error. When a non-null rangeError is passed (max ≤ min), the
  // error message AND the error icon must both surface beneath the pair.

  testWidgets(
    'Bugfix 2: RANGE mode still renders the errPriceMaxGtMin error + icon when '
    'a range error is present',
    (tester) async {
      // The form passes l10n.errPriceMaxGtMin as the rangeError on bad input;
      // resolve it off-tree so the literal is never hardcoded.
      final AppLocalizations l10nUk = lookupAppLocalizations(
        const Locale('uk'),
      );

      await _pumpField(
        tester,
        mode: ServicePriceType.range,
        rangeError: l10nUk.errPriceMaxGtMin,
      );
      await tester.pumpAndSettle();

      // The validation error message must be visible.
      expect(
        find.text(l10nUk.errPriceMaxGtMin),
        findsOneWidget,
        reason:
            'Bugfix 2: the max≤min validation error must still surface after '
            'the static hint removal',
      );
      // The error icon must accompany it.
      expect(find.byIcon(Icons.error_outline_rounded), findsWidgets);
    },
  );

  // ── B1-DISABLED ───────────────────────────────────────────────────────────

  testWidgets(
    'B1-DISABLED: enabled:false wraps the toggle in Opacity(opacity: 0.55)',
    (tester) async {
      await _pumpField(tester, enabled: false);

      // Find an Opacity widget with opacity == 0.55 in the toggle subtree.
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(
        opacityWidgets.any((o) => o.opacity == 0.55),
        isTrue,
        reason:
            'PricingModeToggle must render Opacity(0.55) when enabled is false',
      );
    },
  );
}
