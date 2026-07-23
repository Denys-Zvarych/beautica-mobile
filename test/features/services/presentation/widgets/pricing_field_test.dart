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
//   TAP-SUFFIX-FOCUSES Tap on the price field's currency-suffix text (l10n
//                      `pricingCurrencySuffix`, "₴") focuses the field
//                      (_PricingInputField now wraps the well in a
//                      GestureDetector(HitTestBehavior.opaque)).
//   TAP-HV-FOCUSES     Tap on "хв" suffix text in the duration well focuses the
//                      duration field.
//   TAP-PADDING-FOCUSES Tap on the interior padding of the well (not over the
//                       digit area or suffix) still focuses the field via the
//                       whole-well opaque tap target.
//   TAP-DISABLED-NOP   Tap on a disabled well does NOT grant focus (onTap:null).

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
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

/// Pump [PricingField] with a [durationController] so all well variants render.
///
/// Used by the centered-placeholder regression group to exercise both the
/// non-compact create/edit form layout and the compact service-setup row.
Future<void> _pumpWithDuration(
  WidgetTester tester, {
  ServicePriceType mode = ServicePriceType.fixed,
  bool compact = false,
  bool enabled = true,
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
              compact: compact,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Test group
// ---------------------------------------------------------------------------

void main() {
  // Resolve the price-field currency suffix from l10n rather than hardcoding
  // the literal — the TAP-SUFFIX/TAP-PADDING/TAP-DISABLED regression group
  // below asserts against this single source of truth so a future currency
  // change (l10n `pricingCurrencySuffix`) doesn't re-break this file.
  final String priceSuffix = lookupAppLocalizations(
    const Locale('uk'),
  ).pricingCurrencySuffix;

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

  // ── errorRing — ring WITHOUT a duplicate inline message (max well) ─────────
  //
  // Change under test (errorRing bool replacing the former empty-string ('')
  // errorText sentinel): in RANGE mode the cross-field "max > min" message is
  // rendered ONCE beneath the Від/До pair. The "max" well must show the recessed
  // error RING (NeumorphicInset.hasError == true) WITHOUT rendering its own
  // duplicate inline message row beneath it.
  //
  // The keyed widget for each well is the NeumorphicInset itself (it carries
  // widget.fieldKey), so we read NeumorphicInset.hasError directly — a structural
  // assertion that survives any restyle, unlike a golden.
  //
  // Three observable facts pin the branch:
  //   1. max well NeumorphicInset.hasError == true  → the error ring is on.
  //   2. min well NeumorphicInset.hasError == false → only the offending field
  //      rings (minError is null; rangeError must NOT bleed onto the min ring).
  //   3. the error message renders EXACTLY once (findsOneWidget) → the max well
  //      shows the ring only, with no duplicate message under it (the former ''
  //      sentinel would have rendered an empty inline row; the new bool must not).

  testWidgets(
    'B1-RANGE-ERROR-RING: range error rings the max well WITHOUT a duplicate '
    'inline message; the min well stays unringed and the message renders once',
    (tester) async {
      // The form passes l10n.errPriceMaxGtMin as the rangeError on bad input
      // (max < min); resolve it off-tree so the literal is never hardcoded.
      final AppLocalizations l10nUk = lookupAppLocalizations(
        const Locale('uk'),
      );

      await _pumpField(
        tester,
        mode: ServicePriceType.range,
        rangeError: l10nUk.errPriceMaxGtMin,
      );
      await tester.pumpAndSettle();

      // 1. The "max" well carries the error ring.
      final NeumorphicInset maxWell = tester.widget<NeumorphicInset>(
        find.byKey(const Key('pricing-range-max')),
      );
      expect(
        maxWell.hasError,
        isTrue,
        reason:
            'errorRing must drive NeumorphicInset.hasError on the max well so '
            'the offending field shows the recessed error ring',
      );

      // 2. The "min" well must NOT ring — minError is null and the cross-field
      //    rangeError only flags the max field.
      final NeumorphicInset minWell = tester.widget<NeumorphicInset>(
        find.byKey(const Key('pricing-range-min')),
      );
      expect(
        minWell.hasError,
        isFalse,
        reason:
            'the cross-field range error must ring only the max well, not the '
            'min well (minError is null)',
      );

      // 3. The cross-field message renders exactly once — the max well shows the
      //    ring only, with NO duplicate inline message row beneath it.
      expect(
        find.text(l10nUk.errPriceMaxGtMin),
        findsOneWidget,
        reason:
            'the "max > min" message must appear once (beneath the pair); the '
            'ringed max well must not render its own duplicate inline message',
      );
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
  // GestureDetector. A tap on the currency-suffix ("₴")/"хв" suffix Text or on
  // empty padding inside the NeumorphicInset box did nothing — the TextField's
  // own hit-test area did not extend over the suffix or surrounding
  // whitespace.  The fix wraps the entire well in
  // GestureDetector(behavior: HitTestBehavior.opaque,
  // onTap: () => _focus.requestFocus()) so that ANY tap inside the well bounds
  // focuses the underlying TextField.
  //
  // Observable proxy for focus:
  //   - Price field (currency suffix, hideSuffixWhenActive=true): focus causes
  //     _focused to become true → showSuffix becomes false → the suffix Text
  //     disappears.  The suffix disappearance is a deterministic,
  //     layout-visible proof that the FocusNode received requestFocus().
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

    // ── TAP-SUFFIX-FOCUSES ───────────────────────────────────────────────────
    //
    // Precondition: fixed-price well is empty and unfocused → the currency
    // suffix ("₴") is visible.  Tap it.  Post-condition: _focused=true on the
    // _PricingInputFieldState → showSuffix=false → the suffix disappears.
    // If the GestureDetector wrapper is absent (the old bug), the tap hits
    // the Text and falls through — the FocusNode never fires, _focused stays
    // false, and the assertion fails.

    testWidgets(
      'TAP-SUFFIX-FOCUSES: tap on the currency-suffix text focuses the '
      'fixed-price well (suffix disappears, proving requestFocus() was called)',
      (tester) async {
        await pumpWithDuration(tester);

        const Key priceKey = Key('pricing-fixed-amount');

        // Precondition: the suffix is visible (field is empty and unfocused).
        final suffixUnderPrice = find.descendant(
          of: find.byKey(priceKey),
          matching: find.text(priceSuffix),
        );
        expect(
          suffixUnderPrice,
          findsOneWidget,
          reason:
              'precondition: the currency suffix must be visible when the '
              'price well is empty and unfocused',
        );

        // Act: tap the currency-suffix Text.
        await tester.tap(suffixUnderPrice);
        await tester.pump();

        // Assert: the suffix is now ABSENT — the GestureDetector fired
        // _focus.requestFocus(), which set _focused=true, which hid the
        // suffix (hideSuffixWhenActive=true on the fixed-price field).
        expect(
          suffixUnderPrice,
          findsNothing,
          reason:
              'TAP-SUFFIX-FOCUSES: the currency suffix must disappear after '
              'tapping it — the whole-well GestureDetector must have called '
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

        // Precondition: the currency suffix is visible (field empty + unfocused).
        final suffixUnderPrice = find.descendant(
          of: find.byKey(priceKey),
          matching: find.text(priceSuffix),
        );
        expect(
          suffixUnderPrice,
          findsOneWidget,
          reason:
              'precondition: the currency suffix must be visible before the tap',
        );

        // Find the well bounding box and derive an interior padding point:
        // 4 dp inset from the right edge, centred vertically.  This point is
        // inside the NeumorphicInset but beyond the suffix Text and any digit
        // content (the field is empty).
        final Rect wellRect = tester.getRect(find.byKey(priceKey));
        final Offset paddingPoint = Offset(
          wellRect.right - 4.0, // 4dp inside the right edge
          wellRect.center.dy,
        );

        // Act: tap the padding pixel.
        await tester.tapAt(paddingPoint);
        await tester.pump();

        // Assert: focus was granted — the currency suffix disappeared.
        expect(
          suffixUnderPrice,
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
    // well must NOT grant focus.  The currency suffix must remain visible
    // (the field is empty + unfocused) and the platform text-input channel
    // must stay closed (no keyboard opened).

    testWidgets(
      'TAP-DISABLED-NOP: tap on a disabled well does NOT focus the field '
      '(onTap:null; currency suffix stays visible; no keyboard)',
      (tester) async {
        await pumpWithDuration(tester, enabled: false);

        const Key priceKey = Key('pricing-fixed-amount');

        // Precondition: the currency suffix is visible (field empty +
        // unfocused) and no text input is active.  (The price field's
        // GestureDetector has onTap:null because enabled=false.)
        final suffixUnderPrice = find.descendant(
          of: find.byKey(priceKey),
          matching: find.text(priceSuffix),
        );
        expect(
          suffixUnderPrice,
          findsOneWidget,
          reason:
              'precondition: the currency suffix must be visible on a '
              'disabled well',
        );
        expect(
          tester.testTextInput.isVisible,
          isFalse,
          reason: 'precondition: no text input active before the tap',
        );

        // Act: tap the disabled well.
        await tester.tap(find.byKey(priceKey));
        await tester.pump();

        // Assert: the currency suffix is still visible (focus was NOT granted).
        expect(
          suffixUnderPrice,
          findsOneWidget,
          reason:
              'TAP-DISABLED-NOP: the currency suffix must remain visible — a '
              'tap on a disabled well must NOT focus the field (onTap is '
              'null when enabled=false)',
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

  // ── Regression: centered-placeholder contract ──────────────────────────────
  //
  // Change under test (2026-06-13): [_PricingInputField] now passes
  // `textAlign: TextAlign.center` to its [TextField], so the hint/placeholder
  // and any typed value render horizontally centred inside the well.
  //
  // This group asserts that every well key exposed by [PricingField] contains a
  // [TextField] whose `textAlign` property equals [TextAlign.center]:
  //
  //   FIXED mode (durationController supplied, compact=false):
  //     Key('field-service-duration')  — duration "хв" well
  //     Key('pricing-fixed-amount')    — FIXED price (currency suffix) well
  //
  //   RANGE mode (durationController supplied, compact=false):
  //     Key('field-service-duration')  — duration "хв" well
  //     Key('pricing-range-min')       — RANGE min (currency suffix) well
  //     Key('pricing-range-max')       — RANGE max (currency suffix) well
  //
  //   Compact FIXED mode (compact=true):
  //     Key('service-setup-duration')  — duration well in the service-setup row
  //     Key('pricing-fixed-amount')    — FIXED price well (compact layout)
  //
  // Each assertion is a direct widget-property check — NOT a golden — so it
  // fails immediately if any future refactor drops `textAlign: TextAlign.center`
  // from [_PricingInputField], regardless of visual appearance.
  //
  // Pattern used throughout this group:
  //   find.descendant(of: find.byKey(wellKey), matching: find.byType(TextField))
  //   then tester.widget<TextField>(finder).textAlign == TextAlign.center

  group('Regression — centered-placeholder: TextField.textAlign == center', () {
    // Helper: locate the single TextField inside a keyed well and return it.
    // Named as a local function so it can be const-called without closure alloc.
    TextField textFieldInWell(WidgetTester tester, Key wellKey) {
      final finder = find.descendant(
        of: find.byKey(wellKey),
        matching: find.byType(TextField),
      );
      expect(
        finder,
        findsOneWidget,
        reason: 'expected exactly one TextField descendant of $wellKey',
      );
      return tester.widget<TextField>(finder);
    }

    // ── CENTER-DURATION-FIXED ─────────────────────────────────────────────────
    testWidgets(
      'CENTER-DURATION-FIXED: duration well TextField.textAlign is center '
      'in non-compact FIXED mode',
      (tester) async {
        await _pumpWithDuration(tester, mode: ServicePriceType.fixed);

        final tf = textFieldInWell(tester, const Key('field-service-duration'));

        expect(
          tf.textAlign,
          TextAlign.center,
          reason:
              'CENTER-DURATION-FIXED: _PricingInputField sets '
              'textAlign: TextAlign.center on its TextField; the duration well '
              'in FIXED mode must reflect this so the "60" placeholder and '
              'typed values render centred in the хв well',
        );
      },
    );

    // ── CENTER-PRICE-FIXED ────────────────────────────────────────────────────
    testWidgets(
      'CENTER-PRICE-FIXED: fixed-price well TextField.textAlign is center '
      'in non-compact FIXED mode',
      (tester) async {
        await _pumpWithDuration(tester, mode: ServicePriceType.fixed);

        final tf = textFieldInWell(tester, const Key('pricing-fixed-amount'));

        expect(
          tf.textAlign,
          TextAlign.center,
          reason:
              'CENTER-PRICE-FIXED: the fixed-price well must have '
              'textAlign: TextAlign.center so the "500" placeholder and typed '
              'amounts render centred inside the currency-suffix well',
        );
      },
    );

    // ── CENTER-DURATION-RANGE ─────────────────────────────────────────────────
    testWidgets(
      'CENTER-DURATION-RANGE: duration well TextField.textAlign is center '
      'in non-compact RANGE mode',
      (tester) async {
        await _pumpWithDuration(tester, mode: ServicePriceType.range);

        final tf = textFieldInWell(tester, const Key('field-service-duration'));

        expect(
          tf.textAlign,
          TextAlign.center,
          reason:
              'CENTER-DURATION-RANGE: the duration well\'s TextField must '
              'keep textAlign: TextAlign.center in RANGE mode — the same '
              '_PricingInputField instance is reused across FIXED/RANGE toggles',
        );
      },
    );

    // ── CENTER-RANGE-MIN ──────────────────────────────────────────────────────
    testWidgets(
      'CENTER-RANGE-MIN: range-min well TextField.textAlign is center '
      'in non-compact RANGE mode',
      (tester) async {
        await _pumpWithDuration(tester, mode: ServicePriceType.range);

        final tf = textFieldInWell(tester, const Key('pricing-range-min'));

        expect(
          tf.textAlign,
          TextAlign.center,
          reason:
              'CENTER-RANGE-MIN: the range-min price well must have '
              'textAlign: TextAlign.center so the "500" placeholder renders '
              'centred inside the narrow one-third-width well',
        );
      },
    );

    // ── CENTER-RANGE-MAX ──────────────────────────────────────────────────────
    testWidgets(
      'CENTER-RANGE-MAX: range-max well TextField.textAlign is center '
      'in non-compact RANGE mode',
      (tester) async {
        await _pumpWithDuration(tester, mode: ServicePriceType.range);

        final tf = textFieldInWell(tester, const Key('pricing-range-max'));

        expect(
          tf.textAlign,
          TextAlign.center,
          reason:
              'CENTER-RANGE-MAX: the range-max price well must have '
              'textAlign: TextAlign.center so the "800" placeholder renders '
              'centred inside the narrow one-third-width well',
        );
      },
    );

    // ── CENTER-COMPACT-DURATION ───────────────────────────────────────────────
    //
    // compact=true is used by the bulk service-setup row.  The duration well
    // switches to Key('service-setup-duration') but the same _PricingInputField
    // is rendered — it must also carry textAlign: TextAlign.center.

    testWidgets('CENTER-COMPACT-DURATION: compact service-setup-duration well '
        'TextField.textAlign is center', (tester) async {
      await _pumpWithDuration(
        tester,
        mode: ServicePriceType.fixed,
        compact: true,
      );

      final tf = textFieldInWell(tester, const Key('service-setup-duration'));

      expect(
        tf.textAlign,
        TextAlign.center,
        reason:
            'CENTER-COMPACT-DURATION: compact=true emits '
            'Key(\'service-setup-duration\'); the TextField inside must still '
            'have textAlign: TextAlign.center',
      );
    });
  });
}
