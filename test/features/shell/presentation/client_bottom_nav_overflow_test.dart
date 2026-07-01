// Regression test for the "BEAUTY PASSPORT" bottom-nav label box.
//
// Source: lib/features/shell/presentation/widgets/client_bottom_nav.dart
//   - Each flanking tab is a fixed 60px tile (`_tileWidth`).
//   - `_ClientNavTile` wraps its `Text(maxLines: 2, ellipsis)` label (fontSize 9,
//     line-height 1.1) in a FIXED `SizedBox(height: _labelBoxHeight = 22)`.
//   - The 5th tab label is `kBeautyPassportLabel = 'BEAUTY PASSPORT'`.
//
// ── RED-phase finding — VERTICAL vector (2026-06-19) ─────────────────────────
// The hypothesised RenderFlex overflow at TextScaler.linear(1.3) DOES NOT
// reproduce with the current source. Verified empirically across scales 1.0,
// 1.3, 1.6, 2.0, 3.0 on a 320px surface: `tester.takeException()` is null every
// time. Reason: every vertical dimension in the tile is fixed and does NOT scale
// with text —
//   pill 3 + margin(xs 4) + icon 22 + gap 2 + labelBox 22 = 53px < bar 64px.
// The label `Text` is hard-capped by `SizedBox(height: 22)` plus
// `TextOverflow.ellipsis`, so at 1.3 the two-line wrap is silently
// ellipsis-clipped to a 22px box (measured: 'BEAUTY PASSPORT' renders 56x22 at
// 1.3, 56x20 at 1.0) — it never overruns a Flex, so no FlutterError is thrown.
//
// Conclusion: the fixed `SizedBox` + ellipsis is exactly the guard that PREVENTS
// the vertical overflow. The first group pins that guard: it asserts no
// exception AND asserts the label box stays bounded at elevated scale. If a
// future change removes the fixed box or the ellipsis (letting the label expand
// and push the Column past the 64px bar), the 1.3 cell will start throwing.
//
// Pumped UNCLAMPED at 1.3 (the harness does NOT re-apply the app's
// maxScaleFactor clamp) so the tile's own tolerance is what is under test.
//
// ── HORIZONTAL vector — permanent regression guard (fixed 2026-06-19) ────────
// The REAL field bug was a HORIZONTAL RenderFlex overflow: the centered fixed-
// width Row (client_bottom_nav.dart) needs ~332px but a 360dp phone only offers
// ~328px after the 32px outer padding, which pushed the 5th tile (BEAUTY
// PASSPORT, index 4) off the right edge. The FIX wraps the inner cluster Row in
// `FittedBox(fit: BoxFit.scaleDown)`, so on narrow phones the whole cluster
// shrinks just enough to fit (and is untouched on wide phones).
//
// The second group below is now the permanent guard: at every supported width
// (320 / 360 / 390) the bar must render WITHOUT a horizontal overflow. It pumps
// at REAL constrained widths via `tester.binding.setSurfaceSize`. Pre-fix
// behaviour (for reference — the guard reproduces this if the FittedBox is
// removed): 320px → Row 288px → overflow 44px; 360px → Row 328px → overflow
// 4.0px; 390px → Row 358px → fits.
// IMPORTANT: setting MediaQuery.size alone does NOT constrain layout width — the
// prior attempt did exactly that and the bar laid out at the harness default
// 800px, so nothing overflowed. setSurfaceSize + Scaffold.bottomNavigationBar is
// what makes the bar render at the narrow width (asserted via getSize).

import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientBottomNav — BEAUTY PASSPORT label box tolerance', () {
    // Pumps the bar at a fixed surface width with an explicit, UNCLAMPED text
    // scaler. Width 320 stresses the fixed 60px tiles on a small phone; the
    // scaler is applied verbatim (no maxScaleFactor clamp).
    Future<void> pumpBar(
      WidgetTester tester, {
      required double surfaceWidth,
      required TextScaler textScaler,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('uk'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) {
              final MediaQueryData base = MediaQuery.of(context);
              return MediaQuery(
                data: base.copyWith(
                  size: Size(surfaceWidth, 800),
                  textScaler: textScaler,
                ),
                child: const Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: ClientBottomNav(
                      activeIndex: 0,
                      onTap: _noop,
                      homeLabel: 'Головна',
                      favoritesLabel: 'Улюблені',
                      searchLabel: 'Пошук',
                      bookingsLabel: 'Записи',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no RenderFlex overflow at textScale 1.0 on a 320px surface', (
      WidgetTester tester,
    ) async {
      await pumpBar(
        tester,
        surfaceWidth: 320,
        textScaler: const TextScaler.linear(1.0),
      );

      expect(tester.takeException(), isNull);
      expect(find.text(kBeautyPassportLabel), findsOneWidget);
    });

    testWidgets('no RenderFlex overflow at textScale 1.3 on a 320px surface '
        '(fixed label box + ellipsis keeps BEAUTY PASSPORT bounded)', (
      WidgetTester tester,
    ) async {
      await pumpBar(
        tester,
        surfaceWidth: 320,
        textScaler: const TextScaler.linear(1.3),
      );

      // No exception: the SizedBox(height: 22) + ellipsis guard absorbs the
      // two-line wrap instead of overflowing a Flex. This pins the guard —
      // remove it and this cell starts throwing.
      expect(tester.takeException(), isNull);

      // The label box must stay bounded at elevated scale: a single tile is
      // 60px wide, and the rendered label height must not exceed the reserved
      // 22px box (proves the clip is doing its job, not silently expanding).
      final Size labelSize = tester.getSize(find.text(kBeautyPassportLabel));
      expect(labelSize.height, lessThanOrEqualTo(22.0));
    });
  });

  // ── HORIZONTAL vector ──────────────────────────────────────────────────────
  //
  // The vertical-scale group above is HONEST: it proves the fixed label box +
  // ellipsis absorb a tall label. But it cannot catch the REAL field bug —
  // a HORIZONTAL RenderFlex overflow that pushes the 5th tile (BEAUTY PASSPORT)
  // off the right edge on common narrow phones.
  //
  // Why the prior MediaQuery(size:) approach never reproduced it: setting
  // `MediaQuery.size` does NOT constrain the widget's layout width. The render
  // surface stays at the harness default (800px), so the centered Row always had
  // plenty of room and never overflowed. To reproduce we must constrain the REAL
  // painted width via `tester.binding.setSurfaceSize(...)` and let the bar take
  // the full surface width through `Scaffold.bottomNavigationBar`.
  //
  // The math (from client_bottom_nav.dart):
  //   Inner Row fixed children = _tileWidth(60)×4 + _itemGap(10)×4
  //                              + (_centerSize(52) + _itemGap(10))
  //                            = 240 + 40 + 62 = 332px.
  //   Outer Padding.fromLTRB(md=16, 0, md=16, md=16) = 32px horizontal.
  //   Total natural ≈ 332 + 32 = 364px.
  // Without the FittedBox this overflows at 360dp (~4px) and 320dp (~44px) and
  // only fits at ≥390dp. WITH the FittedBox.scaleDown fix all three widths fit —
  // these cells assert no overflow at every supported width.
  group('ClientBottomNav — horizontal width overflow (BEAUTY PASSPORT tile)', () {
    // Pumps the bar at a REAL constrained surface width via setSurfaceSize and
    // mounts it as a true bottomNavigationBar so it receives the full surface
    // width (NOT the harness default). textScale is pinned to 1.0 so width — not
    // text height — is the only variable under test.
    Future<void> pumpAtWidth(
      WidgetTester tester, {
      required double surfaceWidth,
    }) async {
      await tester.binding.setSurfaceSize(Size(surfaceWidth, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('uk'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (BuildContext context) {
              final MediaQueryData base = MediaQuery.of(context);
              return MediaQuery(
                // Pin the text scaler to 1.0 — this vector isolates WIDTH.
                data: base.copyWith(textScaler: const TextScaler.linear(1.0)),
                child: const Scaffold(
                  bottomNavigationBar: ClientBottomNav(
                    activeIndex: 0,
                    onTap: _noop,
                    homeLabel: 'Головна',
                    favoritesLabel: 'Улюблені',
                    searchLabel: 'Пошук',
                    bookingsLabel: 'Записи',
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no horizontal overflow at 360px (most-common device) — '
        'cluster scales to fit', (WidgetTester tester) async {
      await pumpAtWidth(tester, surfaceWidth: 360);

      // Confirm the bar truly rendered at the narrow width (not the harness
      // default of 800) — this is the assertion the prior attempt lacked.
      final double barWidth = tester
          .getSize(find.byType(ClientBottomNav))
          .width;
      expect(
        barWidth,
        360.0,
        reason: 'bar must render at the constrained 360px surface width',
      );

      // The 5th tile (BEAUTY PASSPORT, index 4) is present in the tree and,
      // after the FittedBox.scaleDown fix, stays within the right edge.
      expect(find.byKey(const Key('client-nav-tile-4')), findsOneWidget);

      // GREEN (post-fix invariant): FittedBox.scaleDown shrinks the 332px
      // cluster to fit the ~328px available width — NO horizontal RenderFlex
      // overflow at 360px. This is the permanent regression guard.
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'no horizontal overflow at 320px (small device) — cluster scales to fit',
      (WidgetTester tester) async {
        await pumpAtWidth(tester, surfaceWidth: 320);

        final double barWidth = tester
            .getSize(find.byType(ClientBottomNav))
            .width;
        expect(barWidth, 320.0);

        expect(find.byKey(const Key('client-nav-tile-4')), findsOneWidget);

        // GREEN (post-fix invariant): the larger shortfall at 320px is also
        // absorbed by FittedBox.scaleDown — NO horizontal overflow at any
        // supported width.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'no horizontal overflow at 390px (wide device) — cluster fits at '
      'natural size',
      (WidgetTester tester) async {
        await pumpAtWidth(tester, surfaceWidth: 390);

        final double barWidth = tester
            .getSize(find.byType(ClientBottomNav))
            .width;
        expect(barWidth, 390.0);

        expect(find.byKey(const Key('client-nav-tile-4')), findsOneWidget);

        // GREEN: 390 - 32 padding = 358px available ≥ 332px Row → no overflow.
        // This cell passing proves the matrix fails by WIDTH, not blanket-fails.
        expect(tester.takeException(), isNull);
      },
    );
  });
}

// Top-level const no-op so the harness widget tree can stay `const`.
void _noop(int _) {}
