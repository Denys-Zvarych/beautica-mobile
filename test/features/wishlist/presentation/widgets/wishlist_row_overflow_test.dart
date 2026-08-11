// TEXT-CLIPPING / LAYOUT-OVERFLOW guard for `WishlistRow`
// (`lib/features/wishlist/presentation/widgets/wishlist_row.dart`).
//
// WHY THIS FILE EXISTS
// ---------------------
// mobile-security finding (HIGH, in-diff on the CTA button change): the
// salon-arm CTA («Обрати майстра») used to be pinned to a FIXED width via
// `SizedBox`. That fixed width forced `HubFilledButton`'s own
// `FittedBox(fit: scaleDown)` to shrink the label to fit — which read as the
// label filling the button edge-to-edge with no breathing room (the
// originally reported bug). The fix replaced the `SizedBox` with a
// `ConstrainedBox(minWidth: _kActionWidth)` — a FLOOR, not a fixed width — so
// a label longer than «Записатись» is free to grow to its own natural size.
//
// That fix regressed in the other direction: the floor has NO ceiling, so at
// a large accessibility text scale the salon label's natural width grows
// without limit. Empirically reproduced at 320 dp width + 2.0x text scale:
// the button grows to 255.3×38 dp and the surrounding `Row`
// (`wishlist_row.dart:173`) overflows by 15 px — caught live by this suite's
// `overflow_guard.dart` (`RenderFlex overflowed by 15 pixels on the right`).
// The existing golden matrix (`passport_*` goldens) never exercised past
// 1.3x, so this never showed up there.
//
// THE FIX
// -------
// `_kActionWidthCeiling` (`_kActionWidth + VelvetSpacing.xxl` = 160 dp)
// restores a ceiling comfortably above «Обрати майстра»'s measured natural
// width at 1.0x (145.7 dp), applied via `ConstrainedBox(minWidth, maxWidth)`
// wrapped around an `IntrinsicWidth` (see that constant's doc comment for why
// the `IntrinsicWidth` indirection is load-bearing, not decorative — a bare
// `maxWidth` handed straight to `HubFilledButton` would inflate EVERY label,
// including ones already comfortably under the floor, to the ceiling, because
// `HubFilledButton`'s `Align`-based centring fills to any bounded max).
// Beyond the ceiling, `HubFilledButton`'s own `FittedBox` finally gets a
// bounded box to scale the label down into, so the safety valve the original
// `SizedBox` used to provide is restored — engaging ONLY when content
// genuinely exceeds the ceiling, not for every row.
//
// MUTATION PROOF (repo's own idiom — see `service_catalogue_accordion_
// overflow_test.dart`'s header): the first test below was run against
// `wishlist_row.dart` with `_kActionWidthCeiling` removed (reverting to the
// floor-only `BoxConstraints(minWidth: _kActionWidth)`) and FAILED there with
// exactly the reported symptom:
//
//   Layout overflow detected (Phase 17.2 guard): ══╡ EXCEPTION CAUGHT BY
//   RENDERING LIBRARY ╞═══...A RenderFlex overflowed by 15 pixels on the
//   right....The relevant error-causing widget was: Row
//   lib/features/wishlist/presentation/widgets/wishlist_row.dart:173:11
//
// (See the fix's own commit / review notes for the captured RED run.) Back on
// the fixed widget it passes. This is the direct, load-bearing proof that the
// test would have caught the regression, not merely described it.
//
// FOLLOW-UP — mobile-security finding (MEDIUM, capped scaling)
// --------------------------------------------------------------
// The ceiling above stopped the crash, but it introduced a SECOND, subtler
// defect: `HubFilledButton`'s `FittedBox(fit: scaleDown)` kept the button at
// exactly 160 dp from the moment content first reached the ceiling (measured
// at OS text scale ~1.14x for the salon label) all the way through 3.0x,
// shrinking the label back down to fit every time. The effective font size
// plateaued around ~12.5sp from 1.3x onward — the OS "larger text" setting
// stopped having any further effect past a fairly common preference, even
// though nothing clipped or overflowed.
//
// The fix: `wishlist_row.dart`'s `_naturalCtaWidth` now measures the
// button's true unclamped width at the ambient text scale, and `build`
// compares it against `_kActionWidthCeiling` to pick a LAYOUT rather than to
// clamp a WIDTH — below the ceiling, the untouched side-by-side `Row`; at or
// above it, the CTA reflows onto its own full-width line below the
// duration/price `Wrap`, where the full card width (~248 dp at 320 dp) gives
// the label far more room to render at its genuine scaled size before
// `FittedBox` ever has to act again.
//
// Two of the tests below (`the CTA reflows to a full-width line...` for both
// arms) were themselves updated by this follow-up: they used to assert the
// button was clamped to exactly the 160 dp ceiling at 2.0x, which was true
// under the old shrink-to-fit mechanism and is now WRONG under the new
// reflow mechanism — the button is no longer 160 dp at 2.0x, it is the full
// ~248 dp card content width. That is not a loosened regression guard, it is
// the fix's own intended behaviour change, and the new width is exactly as
// deterministic (a `SizedBox(width: double.infinity)` inside a fixed-width
// card, independent of font metrics) as the old one was.
//
// MUTATION PROOF for the two new scaling tests (same idiom as above): with
// the reflow removed (i.e. reverting to the ceiling-clamped `Row`-only
// layout — concretely, forcing `ctaReflows` to always evaluate `false` in
// `wishlist_row.dart`), THREE tests below FAIL:
//
//   "the CTA reflows to a full-width line..." (salon arm):
//     Expected: a numeric value within <0.5> of <248.0>
//     Actual: <160.0>
//
//   "a SALON row's CTA label renders at its genuinely scaled size at
//   2.0x, not plateaued...":
//     Expected: a value greater than <18.165044622161087>   (heightAt1_3x × 1.3)
//     Actual: <14.33199236065181>                           (heightAt2_0x)
//   — heightAt1_3x itself measured 13.97: 1.3x and 2.0x render at nearly
//   IDENTICAL heights (13.97 vs 14.33, a ~3% difference for a 54% scale
//   increase) — the exact plateau this test exists to catch.
//
//   "a SALON row's CTA label uses its full available on-screen width at
//   2.0x AND 3.0x...":
//     Expected: a value greater than <192.0>   (the old 128 dp cap × 1.5)
//     Actual: <128.0>
//   — at BOTH 2.0x and 3.0x the label's rendered width sits at EXACTLY the
//   old side-by-side cap (160 dp ceiling − 32 dp button padding = 128 dp),
//   confirming the pre-fix mechanism truly stops the label from ever using
//   more than that fixed 128 dp, regardless of how far the OS scale climbs.
//
// Restoring the reflow makes all three pass again — see the real,
// meaningfully-different measurements once the fix is back in place.
//
// Layer: Widget. No providers — [WishlistRow] is a `StatelessWidget`, so a
// `ProviderScope` override would be theatre (same rationale as
// `wishlist_row_test.dart`).

import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

/// The page's horizontal inset, both sides (`wishlist_screen.dart`'s
/// `ListView`) — mirrors `wishlist_row_test.dart`'s own `_kPageInset` so this
/// file reproduces the REAL layout the row gets in production, not a bare
/// pump with 40 dp of room the row never has.
const double _kPageInset = 24;

/// A SALON-sourced entry — the arm whose CTA («Обрати майстра») is longer
/// than «Записатись» and therefore the one that can actually reach the
/// ceiling.
WishlistService _salonEntry() => const WishlistService(
  sourceType: WishlistSourceType.salon,
  salonId: 'salon-1',
  salonName: 'Салон краси «Оксамит»',
  serviceDefId: 'def-1',
  serviceName: 'Ламінування вій',
  durationMinutes: 60,
  priceDisplay: '600 ₴',
);

/// Advances one-shot animations without `pumpAndSettle` (which would hang on
/// a genuinely overflowing, re-reporting tree) — same bounded pump-until-
/// stable technique `service_catalogue_accordion_overflow_test.dart` uses.
Future<void> _lay(WidgetTester tester) async {
  await tester.pump();
  const Duration step = Duration(milliseconds: 16);
  for (int i = 0; i < 60 && tester.binding.hasScheduledFrame; i++) {
    await tester.pump(step);
  }
}

Future<void> _pumpRow(
  WidgetTester tester,
  WishlistService item, {
  required double width,
  required double textScaleFactor,
}) async {
  await tester.pumpApp(
    Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPageInset),
        child: WishlistRow(item: item, onBook: () {}, onUnfavourite: () {}),
      ),
    ),
    width: width,
    textScaleFactor: textScaleFactor,
  );
  await _lay(tester);
}

/// Pumps a fresh salon row at 320 dp / [textScaleFactor] and returns the
/// visually rendered bounding box of its CTA label («Обрати майстра»).
///
/// `getRect` (not `getSize`) is deliberate: `getSize` reports the `Text`'s
/// LOCAL, pre-transform layout size, but `HubFilledButton` wraps its label in
/// a `FittedBox`, which scales visually via a paint-time transform that
/// `getSize` cannot see. `getRect`/`getTopLeft`/`getBottomRight` walk
/// `RenderBox.localToGlobal`, which DOES apply that transform
/// (`RenderFittedBox.applyPaintTransform`), so the rect measured here is the
/// label's true ON-SCREEN size — the only thing an OS text-scale setting is
/// actually supposed to change.
Future<Rect> _measureSalonCtaLabelRect(
  WidgetTester tester, {
  required double textScaleFactor,
}) async {
  await _pumpRow(
    tester,
    _salonEntry(),
    width: 320,
    textScaleFactor: textScaleFactor,
  );
  final Finder label = find.descendant(
    of: find.byType(HubFilledButton),
    // The scaling test cares about the RENDERED SIZE of whichever label
    // `bookCtaLabel` resolves to for this fixed salon fixture, not about
    // asserting locale-specific copy.
    // i18n-finder-ok: locating the CTA's own label glyphs by rendered size
    matching: find.text('Обрати майстра'),
  );
  expect(label, findsOneWidget);
  return tester.getRect(label);
}

void main() {
  group('finding 1 (HIGH, mobile-security) — the salon CTA no longer grows '
      'without limit at accessibility text scale', () {
    testWidgets('a SALON row does not overflow at 320 dp x 2.0x text scale', (
      tester,
    ) async {
      // The exact empirical repro from the audit: 320 dp width (the
      // narrowest supported phone) + 2.0x text scale (a real Android
      // "larger text" accessibility setting, not an exotic edge case).
      // The overflow guard installed by `pumpApp` fails this test
      // automatically on any recorded `RenderFlex overflowed` — nothing
      // here needs a manual `takeException()`.
      await _pumpRow(tester, _salonEntry(), width: 320, textScaleFactor: 2.0);

      // Sanity: the row actually composed (the guard's tearDown is what
      // fails on overflow — this just proves we pumped the real tree).
      expect(find.byType(HubFilledButton), findsOneWidget);
      // i18n-finder-ok: fixture salon service name — test-authored data.
      expect(find.text('Ламінування вій'), findsOneWidget);
    });

    testWidgets(
      'the reflowed CTA is still a live tap target, not just correctly '
      'sized — tapping it fires onBook at 320 dp x 2.0x',
      (tester) async {
        // Every test above proves the reflowed button is positioned and
        // sized correctly. None of them proves it is still HITTABLE there —
        // the M14/M15 class of bug this repo has hit before, where a widget
        // renders in the right place but a sibling or an intrinsic-sizing
        // quirk leaves the real tap landing elsewhere. `WishlistRow` builds
        // `ctaButton` exactly ONCE (`wishlist_row.dart`'s `build`) and only
        // changes which parent (`Row` vs `Column`) it sits in, so this also
        // confirms the reflow path did not drop the `onTap` wiring on the
        // way.
        bool booked = false;
        await tester.pumpApp(
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _kPageInset),
              child: WishlistRow(
                item: _salonEntry(),
                onBook: () => booked = true,
                onUnfavourite: () {},
              ),
            ),
          ),
          width: 320,
          textScaleFactor: 2.0,
        );
        await _lay(tester);

        await tester.tap(find.byType(HubFilledButton));
        await tester.pump();

        expect(
          booked,
          isTrue,
          reason:
              'the reflowed CTA rendered but tapping it never reached '
              'onBook — a hit-testing dead zone, not a layout bug',
        );
      },
    );

    testWidgets('the CTA reflows to a full-width line, not clamped to the old '
        '160 dp ceiling, at 320 dp x 2.0x', (tester) async {
      // The structural half of the proof: not just "no crash", but that
      // the REFLOW is the mechanism doing the work (mobile-security
      // MEDIUM follow-up — see this file's header). Under the ORIGINAL
      // (HIGH) fix the button clamped to exactly the 160 dp ceiling here
      // and `FittedBox` shrank the label to fit inside it — that shrink
      // is exactly the "capped scaling" defect the follow-up removes, so
      // the button must NOT sit at 160 dp any more. Instead it reflows
      // onto its own line at the full card content width: 320 dp page
      // width − 2×24 dp page inset (`_kPageInset`) − 2×12 dp card padding
      // (`HubFlatCard`'s `AppSpacing.sm`) = 248 dp, forced by the
      // `SizedBox(width: double.infinity)` `wishlist_row.dart` wraps the
      // reflowed button in — a value independent of the label's own font
      // metrics, so it stays exact regardless of future copy changes.
      await _pumpRow(tester, _salonEntry(), width: 320, textScaleFactor: 2.0);

      const double kOldCeiling = 160;
      const double kReflowedCardContentWidth = 320 - 2 * 24 - 2 * 12;
      final double buttonWidth = tester
          .getSize(find.byType(HubFilledButton))
          .width;
      expect(
        buttonWidth,
        closeTo(kReflowedCardContentWidth, 0.5),
        reason:
            'the reflowed CTA should fill the card\'s full content '
            'width, not the old fixed ceiling — a value close to 160 '
            'here means the reflow stopped engaging and the label is '
            'back to being squeezed by FittedBox',
      );
      expect(
        buttonWidth,
        greaterThan(kOldCeiling),
        reason:
            'the whole point of the follow-up is that the button no '
            'longer tops out at the old 160 dp ceiling at this scale',
      );
    });

    testWidgets(
      'a MASTER row does not overflow at 320 dp x 2.0x either, and its '
      'CTA reflows the same way the salon arm\'s does',
      (tester) async {
        // At 2.0x «Записатись» itself grows past the 112 dp floor AND past
        // the 160 dp ceiling (the font scales, not just the salon label),
        // so it reflows exactly like the salon arm and lands at the same
        // full card-content width — see the salon test above for the 248 dp
        // derivation. That is expected and correct at this extreme, NOT a
        // regression: the 1.0x contract («Записатись» == exactly 112 dp) is
        // asserted separately below, scoped to 1.0x where the side-by-side
        // layout actually applies.
        const WishlistService masterEntry = WishlistService(
          masterServiceId: 'ms-1',
          masterId: 'm-1',
          serviceName: 'Нарощування вій',
          masterName: 'Олена',
          durationMinutes: 60,
          priceDisplay: '800 ₴',
        );
        await _pumpRow(tester, masterEntry, width: 320, textScaleFactor: 2.0);

        const double kReflowedCardContentWidth = 320 - 2 * 24 - 2 * 12;
        final double buttonWidth = tester
            .getSize(find.byType(HubFilledButton))
            .width;
        expect(buttonWidth, closeTo(kReflowedCardContentWidth, 0.5));
      },
    );
  });

  group(
    'finding 1 (MEDIUM, mobile-security) — the CTA tracks the OS text-scale '
    'setting instead of plateauing past ~1.3x',
    () {
      testWidgets(
        "a SALON row's CTA label renders at its genuinely scaled size at "
        '2.0x, not plateaued the way it did before the reflow fix',
        (tester) async {
          // Measure the SAME label's actual rendered height at two
          // different OS text scales, both in the 320 dp worst case the
          // audit used.
          //
          // Before the reflow fix, `FittedBox` clamped the button (and
          // therefore the label) at the 160 dp ceiling from ~1.14x text
          // scale onward, so this pair of heights would come back nearly
          // IDENTICAL — a plateau, not a scale. After the fix the CTA
          // reflows to its own full-width line before the ceiling is
          // reached, so the label keeps growing with the OS setting
          // instead. See this file's header for the captured RED run with
          // the reflow reverted.
          final double heightAt1_3x = (await _measureSalonCtaLabelRect(
            tester,
            textScaleFactor: 1.3,
          )).height;
          final double heightAt2_0x = (await _measureSalonCtaLabelRect(
            tester,
            textScaleFactor: 2.0,
          )).height;

          expect(
            heightAt2_0x,
            greaterThan(heightAt1_3x * 1.3),
            reason:
                'the 2.0x label should render meaningfully TALLER than '
                'the 1.3x label — a result close to (or below) '
                'heightAt1_3x is the exact "capped scaling" plateau this '
                'fix removes',
          );
        },
      );

      testWidgets(
        "a SALON row's CTA label uses its full available on-screen width at "
        '2.0x AND 3.0x — bounded by the CARD, not by an arbitrary small '
        'ceiling',
        (tester) async {
          // Past ~2.0x the label's rendered WIDTH itself saturates at the
          // available space inside the reflowed, full-width button (216 dp:
          // the 248 dp reflowed button minus HubFilledButton's own
          // `2 × VelvetSpacing.md` horizontal padding) — `FittedBox` is
          // width-bound there, so pushing the OS scale further genuinely
          // cannot make the label wider without either overflowing the card
          // or shrinking below full width, and further height growth from
          // 2.0x to 3.0x flattens out too (both already render close to the
          // available 38 dp button height's own proportional limit). That
          // is NOT the reported "capped scaling" defect returning — it is a
          // real, physical limit reached only after the label is already
          // filling the full card-width real estate, a limit no on-screen
          // control can be exempt from. The defect this test guards against
          // is the OLD, much smaller and much-too-early ceiling: before the
          // fix the label's available width topped out at 160 − 32 = 128 dp
          // (the side-by-side ceiling minus the button's own padding) and
          // that cap engaged already at ~1.14x. This asserts the label now
          // reaches a width CLEARLY beyond that old 128 dp cap, at both
          // scales — proof the fix is genuinely using card-width real
          // estate, not just a differently-sized version of the same small
          // clamp.
          const double kOldLabelWidthCap = 128;
          final double widthAt2_0x = (await _measureSalonCtaLabelRect(
            tester,
            textScaleFactor: 2.0,
          )).width;
          final double widthAt3_0x = (await _measureSalonCtaLabelRect(
            tester,
            textScaleFactor: 3.0,
          )).width;

          expect(widthAt2_0x, greaterThan(kOldLabelWidthCap * 1.5));
          expect(widthAt3_0x, greaterThan(kOldLabelWidthCap * 1.5));
        },
      );
    },
  );

  group('the normal case (1.0x) is unregressed by the ceiling', () {
    testWidgets(
      'a SALON row\'s CTA still renders at its own natural width at 1.0x, '
      'not stretched to the ceiling',
      (tester) async {
        await _pumpRow(tester, _salonEntry(), width: 360, textScaleFactor: 1);

        // «Обрати майстра»'s measured natural full-button width — label
        // (113.7 dp) + `HubFilledButton`'s own 2 × `VelvetSpacing.md` (16 dp)
        // padding. Comfortably under the 160 dp ceiling, so `IntrinsicWidth`
        // must report the NATURAL value here, not the ceiling — this is the
        // exact case a bare `maxWidth` (without `IntrinsicWidth`) would have
        // broken.
        const double kNaturalSalonWidth = 145.7;
        final double buttonWidth = tester
            .getSize(find.byType(HubFilledButton))
            .width;
        expect(
          buttonWidth,
          closeTo(kNaturalSalonWidth, 1),
          reason:
              'the button should size to its OWN content, not fill to the '
              '160 dp ceiling, when content comfortably fits under it',
        );
      },
    );

    testWidgets(
      'a MASTER row\'s CTA still renders at exactly the 112 dp floor at '
      '1.0x',
      (tester) async {
        const WishlistService masterEntry = WishlistService(
          masterServiceId: 'ms-1',
          masterId: 'm-1',
          serviceName: 'Нарощування вій',
          masterName: 'Олена',
          durationMinutes: 60,
          priceDisplay: '800 ₴',
        );
        await _pumpRow(tester, masterEntry, width: 360, textScaleFactor: 1);

        const double kActionWidth = 112;
        final double buttonWidth = tester
            .getSize(find.byType(HubFilledButton))
            .width;
        expect(buttonWidth, closeTo(kActionWidth, 0.5));
      },
    );
  });
}
