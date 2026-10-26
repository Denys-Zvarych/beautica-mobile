// Phase 422 D2 — padded-inset golden variants for the three floating
// bottom-nav pills under edge-to-edge (targetSdk 36).
//
// The zero-inset appearance of each bar is already pinned elsewhere
// (`salon_bottom_nav_golden_test.dart`, `client_bottom_nav_golden_test.dart`,
// and the owner-master-mode screen goldens for `VelvetBottomNavBar`) and must
// stay byte-identical. These cells add the NEW surface: a 48 dp bottom inset
// (3-button navigation), under which each pill must keep its own height and
// float `VelvetSpacing.md` above the inset strip instead of stretching into it.
// The geometry itself is asserted in
// `test/shared/widgets/bottom_nav_edge_to_edge_inset_test.dart`; these goldens
// pin the look.
//
// Matrix: {360, 414} dp x {1.0} scale (414 = the repo-wide second width).
//
// File names: <bar>_inset48_<width>_1x.png

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_bottom_nav.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const List<double> _widths = <double>[360, 414];
const double _inset = 48;

/// Bottom-aligns [bar] on the brand base with a [_inset] bottom system inset,
/// mirroring the `_host` of the zero-inset bar goldens.
Widget _host(double width, WidgetBuilder bar) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Builder(
      builder: (BuildContext context) {
        final MediaQueryData base = MediaQuery.of(context);
        return MediaQuery(
          data: base.copyWith(
            padding: const EdgeInsets.only(bottom: _inset),
            viewPadding: const EdgeInsets.only(bottom: _inset),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Builder(builder: bar),
          ),
        );
      },
    ),
  ),
);

void main() {
  final Map<String, WidgetBuilder> bars = <String, WidgetBuilder>{
    'velvet_bottom_nav_bar': (BuildContext _) =>
        const VelvetBottomNavBar(activeIndex: 0),
    'salon_bottom_nav': (BuildContext context) => SalonBottomNav(
      currentIndex: 0,
      onSelect: (_) {},
      items: SalonBottomNav.ownerAdminItems(AppLocalizations.of(context)),
    ),
    'client_bottom_nav': (BuildContext context) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return ClientBottomNav(
        activeIndex: 0,
        onTap: (_) {},
        homeLabel: l10n.clientNavHome,
        favoritesLabel: l10n.clientNavFavorites,
        searchLabel: l10n.clientNavSearch,
        bookingsLabel: l10n.clientNavBookings,
      );
    },
  };

  for (final double width in _widths) {
    final int w = width.toInt();
    for (final MapEntry<String, WidgetBuilder> bar in bars.entries) {
      goldenTest(
        '${bar.key} with a 48dp bottom inset at $w dp',
        fileName: '${bar.key}_inset48_${w}_1x',
        constraints: BoxConstraints.tight(Size(width, 140 + _inset)),
        textScaleFactor: 1.0,
        pumpWidget: goldenPumpWidget(width: width),
        builder: () => _host(width, bar.value),
      );
    }
  }
}
