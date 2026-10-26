// Phase 422 D2 — edge-to-edge insets for the three floating bottom-nav pills
// (`VelvetBottomNavBar`, `SalonBottomNav`, `ClientBottomNav`).
//
// targetSdk 36 makes edge-to-edge mandatory, so the system navigation bar's
// height arrives as a bottom `MediaQuery.padding`. Before 422 each pill fed
// that inset to an INTERNAL `SafeArea`, so the pill stretched down under the
// system bar (and `ClientBottomNav`, whose stack has a fixed height, squeezed
// its tiles once the inset passed half the centre disc). Now the outer margin
// grows by the inset and the pill keeps its own height, floating above the
// system bar.
//
// Pinned per bar, per inset (0 = API <= 34 / every golden, 24 = gesture nav,
// 48 = 3-button nav):
//   * no layout exception;
//   * the pill's bottom edge sits exactly `VelvetSpacing.md + inset` above the
//     screen bottom;
//   * the pill's height equals its zero-inset height (it does not stretch).
// The zero-inset row is the pre-422 geometry, so it also guards "API <= 34
// renders identically".

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Size _surface = Size(390, 844);
const List<double> _insets = <double>[0, 24, 48];

typedef _BarBuilder = Widget Function(BuildContext context);

final Map<String, (Type, _BarBuilder)> _bars = <String, (Type, _BarBuilder)>{
  'VelvetBottomNavBar': (
    VelvetBottomNavBar,
    (BuildContext _) => const VelvetBottomNavBar(activeIndex: 0),
  ),
  'SalonBottomNav': (
    SalonBottomNav,
    (BuildContext context) => SalonBottomNav(
      currentIndex: 0,
      onSelect: (_) {},
      items: SalonBottomNav.ownerAdminItems(AppLocalizations.of(context)),
    ),
  ),
  'ClientBottomNav': (
    ClientBottomNav,
    (BuildContext _) => ClientBottomNav(
      activeIndex: 0,
      onTap: (_) {},
      homeLabel: 'home',
      favoritesLabel: 'favorites',
      searchLabel: 'search',
      bookingsLabel: 'bookings',
    ),
  ),
};

Future<Rect> _pumpAndMeasurePill(
  WidgetTester tester, {
  required Type barType,
  required _BarBuilder build,
  required double inset,
}) async {
  tester.view.physicalSize = _surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
              padding: EdgeInsets.only(bottom: inset),
              viewPadding: EdgeInsets.only(bottom: inset),
            ),
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: Builder(builder: build),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
  // The pill is the bar's first ClipRRect (the client bar's centre disc comes
  // later in tree order).
  return tester.getRect(
    find
        .descendant(of: find.byType(barType), matching: find.byType(ClipRRect))
        .first,
  );
}

void main() {
  for (final MapEntry<String, (Type, _BarBuilder)> bar in _bars.entries) {
    final (Type type, _BarBuilder build) = bar.value;
    group('${bar.key} — edge-to-edge bottom inset (phase 422)', () {
      for (final double inset in _insets) {
        testWidgets(
          'inset $inset: pill floats md + inset above the bottom, same height',
          (WidgetTester tester) async {
            final Rect zero = await _pumpAndMeasurePill(
              tester,
              barType: type,
              build: build,
              inset: 0,
            );
            final Rect pill = await _pumpAndMeasurePill(
              tester,
              barType: type,
              build: build,
              inset: inset,
            );
            expect(pill.bottom, _surface.height - VelvetSpacing.md - inset);
            expect(pill.height, zero.height);
            expect(pill.left, zero.left);
            expect(pill.width, zero.width);
          },
        );
      }
    });
  }
}
