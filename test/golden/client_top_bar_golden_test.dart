// Chrome golden — [ClientTopBar] (the shared CLIENT wordmark · bell · burger).
//
// Pins the two bell states that are otherwise invisible to a structural test:
//   • idle   (hasUnread: false) → dotless notification bell SVG
//   • unread (hasUnread: true)  → bell SVG with the baked-in red dot
// A regression that swaps the asset, drops the dot, or shifts the wordmark
// baseline reads as a pixel diff here. The wordmark-jump *position* invariant is
// covered structurally by client_branch_chrome_test.dart; this golden is the
// pixel-truth companion for the bar's appearance.
//
// Matrix kept tight (this is chrome, not a screen): {360} dp × {1.0} scale. The
// bar sits on the brand base color (the CLIENT shells' background) so the
// neumorphic burger + bell render against their real backdrop.
//
// File names: client_top_bar_idle_360_1x.png
//             client_top_bar_unread_360_1x.png

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

/// Hosts [child] on the brand base background with the production branch-root
/// horizontal page padding (16 dp), so the bar lays out as it does on screen.
Widget _host(double width, Widget child) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: child,
    ),
  ),
);

ClientTopBar _bar({required bool hasUnread}) => ClientTopBar(
  onBell: () {},
  onBurger: () {},
  bellSemanticLabel: 'Сповіщення',
  burgerSemanticLabel: 'Меню',
  bellKey: const Key('golden_bell'),
  burgerKey: const Key('golden_burger'),
  hasUnread: hasUnread,
);

void main() {
  const double width = 360;

  goldenTest(
    'client_top_bar idle (dotless bell)',
    fileName: 'client_top_bar_idle_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 120)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(width, _bar(hasUnread: false)),
  );

  goldenTest(
    'client_top_bar unread (dotted bell)',
    fileName: 'client_top_bar_unread_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 120)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(width, _bar(hasUnread: true)),
  );
}
