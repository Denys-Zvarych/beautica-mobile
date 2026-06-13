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
//
// Regression — tap-target fix (2026-06-13):
//   TAP-GRN-FOCUSES    Tap on "грн" suffix text in the fixed-price well focuses
//                      the field (_PricingInputField now wraps the well in a
//                      GestureDetector(HitTestBehavior.opaque)).
//   TAP-HV-FOCUSES     Tap on "хв" suffix text in the duration well focuses the
//                      duration field.
//   TAP-PADDING-FOCUSES Tap on the interior padding of the well (not over the
//                       digit area or suffix) still focuses the field via the
//                       whole-well opaque tap target.
//   TAP-DISABLED-NOP   Tap on a disabled well does NOT grant focus (onTap:null).

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

  // ── Regression: tap-target fix — GestureDetector(HitTestBehavior.opaque) ──
  //
  // Before the fix, the _PricingInputField well was NOT wrapped in a
  // GestureDetector. A tap on the "грн"/"хв" suffix Text or on empty padding
  // inside the NeumorphicInset box did nothing — the TextField's own hit-test
  // area did not extend over the suffix or surrounding whitespace.  The fix
  // wraps the entire well in GestureDetector(behavior: HitTestBehavior.opaque,
  // onTap: () => _focus.requestFocus()) so that ANY tap inside the well bounds
  // focuses the underlying TextField.
  //
  // Observable proxy for focus:
  //   - Price field ("грн", hideSuffixWhenActive=true): focus causes _focused to
  //     become true → showSuffix becomes false → "грн" Text disappears.  The
  //     suffix disappearance is a deterministic, layout-visible proof that the
  //     FocusNode received requestFocus().
  //   - Duration field ("хв", hideSuffixWhenActive=false): suffix stays visible
  //     regardless of focus, so we assert via
  //     WidgetsBinding.instance.focusManager.primaryFocus != null and
  //     tester.testTextInput.isVisible (true only when a text field is active).

  group('Regression — GestureDetector(HitTestBehavior.opaque) tap-target fix', () {
    // Shared helpers: pump with both a durationController and fixed
    // controllers so all well variants are exercised.
    Future<
      ({
        TextEditingController fixedCtrl,
        TextEditingController minCtrl,
        TextEditingController maxCtrl,
        TextEditingController durationCtrl,
      })
    >
    pumpWithDuration(
      WidgetTester tester, {
      bool enabled = true,
      ServicePriceType mode = ServicePriceType.fixed,
    }) async {
      final fixedCtrl = TextEditingController();
      final minCtrl = TextEditingController();
      final maxCtrl = TextEditingController();
      final durationCtrl = TextEditingController();
      addTearDown(fixedCtrl.dispose);
      addTearDown(minCtrl.dispose);
      addTearDown(maxCtrl.dispose);
      addTearDown(durationCtrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: PricingField(
                  mode: mode,
                  onModeChanged: (_) {},
                  fixedController: fixedCtrl,
                  minController: minCtrl,
                  maxController: maxCtrl,
                  durationController: durationCtrl,
                  enabled: enabled,
                  compact: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (
        fixedCtrl: fixedCtrl,
        minCtrl: minCtrl,
        maxCtrl: maxCtrl,
        durationCtrl: durationCtrl,
      );
    }

    // ── TAP-GRN-FOCUSES ─────────────────────────────────────────────────────
    //
    // Precondition: fixed-price well is empty and unfocused → "грн" is
    // visible.  Tap the "грн" Text.  Post-condition: _focused=true on the
    // _PricingInputFieldState → showSuffix=false → "грн" disappears.
    // If the GestureDetector wrapper is absent (the old bug), the tap hits
    // the Text and falls through — the FocusNode never fires, _focused stays
    // false, and the assertion fails.

    testWidgets(
      'TAP-GRN-FOCUSES: tap on the "грн" suffix text focuses the fixed-price '
      'well (suffix disappears, proving requestFocus() was called)',
      (tester) async {
        await pumpWithDuration(tester);

        const Key priceKey = Key('pricing-fixed-amount');

        // Precondition: "грн" is visible (field is empty and unfocused).
        final grnUnderPrice = find.descendant(
          of: find.byKey(priceKey),
          matching: find.text('грн'),
        );
        expect(
          grnUnderPrice,
          findsOneWidget,
          reason:
              'precondition: "грн" must be visible when the price well is '
              'empty and unfocused',
        );

        // Act: tap the "грн" suffix Text.
        await tester.tap(grnUnderPrice);
        await tester.pump();

        // Assert: "грн" is now ABSENT — the GestureDetector fired
        // _focus.requestFocus(), which set _focused=true, which hid the
        // suffix (hideSuffixWhenActive=true on the fixed-price field).
        expect(
          grnUnderPrice,
          findsNothing,
          reason:
              'TAP-GRN-FOCUSES: "грн" must disappear after tapping it — '
              'the whole-well GestureDetector must have called '
              '_focus.requestFocus(), making showSuffix false',
        );
      },
    );

    // ── TAP-HV-FOCUSES ──────────────────────────────────────────────────────
    //
    // The duration well uses hideSuffixWhenActive=false so "хв" stays visible
    // even after the field gains focus.  Instead we assert focus via the
    // platform text-input channel: tester.testTextInput.isVisible is true
    // only when Flutter has opened a software keyboard connection for an
    // active TextField, which happens exactly when requestFocus() succeeds on
    // a text field.

    testWidgets(
      'TAP-HV-FOCUSES: tap on the "хв" suffix text focuses the duration well '
      '(platform text input becomes visible, proving requestFocus() was called)',
      (tester) async {
        await pumpWithDuration(tester);

        const Key durationKey = Key('field-service-duration');

        // Precondition: "хв" is visible (always) and no text input is active.
        expect(
          find.descendant(
            of: find.byKey(durationKey),
            matching: find.text('хв'),
          ),
          findsOneWidget,
          reason: 'precondition: "хв" must be visible in the duration well',
        );
        expect(
          tester.testTextInput.isVisible,
          isFalse,
          reason: 'precondition: no text input must be active before the tap',
        );

        // Act: tap the "хв" suffix Text inside the duration well.
        await tester.tap(
          find.descendant(
            of: find.byKey(durationKey),
            matching: find.text('хв'),
          ),
        );
        await tester.pump();

        // Assert: the platform text-input channel is now open, confirming
        // that the GestureDetector's onTap called _focus.requestFocus() and
        // the TextField opened the keyboard connection.
        expect(
          tester.testTextInput.isVisible,
          isTrue,
          reason:
              'TAP-HV-FOCUSES: tapping "хв" must open the platform text '
              'input (keyboard), proving the duration well\'s FocusNode '
              'received requestFocus() from the GestureDetector',
        );
      },
    );

    // ── TAP-PADDING-FOCUSES ─────────────────────────────────────────────────
    //
    // HitTestBehavior.opaque ensures the GestureDetector claims the entire
    // well rectangle, including empty padding pixels to the right of any digit
    // content.  We tap inside the NeumorphicInset box at a point that is
    // interior but offset toward the right edge — beyond any rendered text.
    // We use the fixed-price well so the focus-causes-suffix-disappears proxy
    // applies cleanly.

    testWidgets(
      'TAP-PADDING-FOCUSES: tap on well interior padding (not on the digits or '
      'suffix) focuses the fixed-price well via HitTestBehavior.opaque',
      (tester) async {
        await pumpWithDuration(tester);

        const Key priceKey = Key('pricing-fixed-amount');

        // Precondition: "грн" is visible (field empty + unfocused).
        final grnUnderPrice = find.descendant(
          of: find.byKey(priceKey),
          matching: find.text('грн'),
        );
        expect(
          grnUnderPrice,
          findsOneWidget,
          reason: 'precondition: "грн" must be visible before the tap',
        );

        // Find the well bounding box and derive an interior padding point:
        // 4 dp inset from the right edge, centred vertically.  This point is
        // inside the NeumorphicInset but beyond the "грн" Text and any digit
        // content (the field is empty).
        final Rect wellRect = tester.getRect(find.byKey(priceKey));
        final Offset paddingPoint = Offset(
          wellRect.right - 4.0, // 4dp inside the right edge
          wellRect.center.dy,
        );

        // Act: tap the padding pixel.
        await tester.tapAt(paddingPoint);
        await tester.pump();

        // Assert: focus was granted — "грн" disappeared.
        expect(
          grnUnderPrice,
          findsNothing,
          reason:
              'TAP-PADDING-FOCUSES: tapping the right-interior padding of '
              'the well must focus the field — HitTestBehavior.opaque makes '
              'the entire GestureDetector rect hittable, not just the '
              'TextField or suffix text widget',
        );
      },
    );

    // ── TAP-DISABLED-NOP ────────────────────────────────────────────────────
    //
    // When enabled=false the GestureDetector's onTap is null.  Tapping the
    // well must NOT grant focus.  The "грн" suffix must remain visible (the
    // field is empty + unfocused) and the platform text-input channel must
    // stay closed (no keyboard opened).

    testWidgets(
      'TAP-DISABLED-NOP: tap on a disabled well does NOT focus the field '
      '(onTap:null; "грн" stays visible; no keyboard)',
      (tester) async {
        await pumpWithDuration(tester, enabled: false);

        const Key priceKey = Key('pricing-fixed-amount');

        // Precondition: "грн" is visible (field empty + unfocused) and no
        // text input is active.  (The price field's GestureDetector has
        // onTap:null because enabled=false.)
        final grnUnderPrice = find.descendant(
          of: find.byKey(priceKey),
          matching: find.text('грн'),
        );
        expect(
          grnUnderPrice,
          findsOneWidget,
          reason: 'precondition: "грн" must be visible on a disabled well',
        );
        expect(
          tester.testTextInput.isVisible,
          isFalse,
          reason: 'precondition: no text input active before the tap',
        );

        // Act: tap the disabled well.
        await tester.tap(find.byKey(priceKey));
        await tester.pump();

        // Assert: "грн" still visible (focus was NOT granted).
        expect(
          grnUnderPrice,
          findsOneWidget,
          reason:
              'TAP-DISABLED-NOP: "грн" must remain visible — a tap on a '
              'disabled well must NOT focus the field (onTap is null when '
              'enabled=false)',
        );
        // Assert: no keyboard opened.
        expect(
          tester.testTextInput.isVisible,
          isFalse,
          reason:
              'TAP-DISABLED-NOP: the platform text input must remain closed '
              'after tapping a disabled well',
        );
      },
    );
  });
}
