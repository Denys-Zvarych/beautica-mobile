// Chrome golden — [VelvetTopBar] back affordance (Phase 24.1a).
//
// Pins the two back-button faces side by side in the real bar:
//   • icon-only (the pre-phase baseline every existing caller renders)
//   • labelled «‹ Салон» pill (owner master mode), with the longest
//     master-mode title and the owner bell + tune trailing pair
//
// Matrix kept tight (chrome, not a screen): {360} dp × {1.0} scale, on the
// brand base background.
//
// File names: velvet_top_bar_icon_only_360_1x.png
//             velvet_top_bar_labelled_360_1x.png

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

Widget _host(double width, Widget child) => ColoredBox(
  color: BrandColors.base,
  child: SizedBox(width: width, child: child),
);

Widget _trailingPair() => Row(
  mainAxisSize: MainAxisSize.min,
  children: <Widget>[
    NotificationBellButton(onTap: () {}, semanticLabel: 'Сповіщення'),
    const SizedBox(width: VelvetSpacing.sm + 4),
    NeumorphicIconButton(
      icon: Icons.tune_rounded,
      semanticLabel: 'Налаштування',
      onTap: () {},
    ),
  ],
);

void main() {
  const double width = 360;

  goldenTest(
    'velvet_top_bar icon-only back (baseline)',
    fileName: 'velvet_top_bar_icon_only_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 120)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () =>
        _host(width, VelvetTopBar(title: 'Мій профіль', onBack: () {})),
  );

  goldenTest(
    'velvet_top_bar labelled «Салон» back + bell/tune',
    fileName: 'velvet_top_bar_labelled_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 120)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(
      width,
      VelvetTopBar(
        title: 'Мій профіль',
        onBack: () {},
        backLabel: 'Салон',
        backSemanticLabel: 'Назад до салону',
        trailing: _trailingPair(),
      ),
    ),
  );
}
