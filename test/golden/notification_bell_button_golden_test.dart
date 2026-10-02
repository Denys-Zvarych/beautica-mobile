// Phase 361 — pixel lock for the shared [NotificationBellButton] in both
// states. Plain = dotless bell (flattened to textSecondary); unread = the
// two-tone asset with the baked-in dot. File names:
//   notification_bell_button_plain_1x.png
//   notification_bell_button_unread_1x.png

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

Widget _host({required bool hasUnread}) => ColoredBox(
  color: BrandColors.base,
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: NotificationBellButton(
      onTap: () {},
      semanticLabel: 'Сповіщення',
      hasUnread: hasUnread,
    ),
  ),
);

void main() {
  const double width = 120;

  goldenTest(
    'notification bell plain',
    fileName: 'notification_bell_button_plain_1x',
    constraints: BoxConstraints.tight(const Size(width, 80)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(hasUnread: false),
  );

  goldenTest(
    'notification bell unread',
    fileName: 'notification_bell_button_unread_1x',
    constraints: BoxConstraints.tight(const Size(width, 80)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(hasUnread: true),
  );
}
