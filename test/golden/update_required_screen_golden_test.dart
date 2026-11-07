// Phase 438 — «Оновіть додаток» goldens: the approved preview
// (docs/signup-designs/UpdateRequired/) at every golden width × text scale,
// plus the «Google Play не відкрився» state.

import 'package:beautica_mobile/core/app_version/update_required_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'helpers/golden_pump.dart';

UpdateRequiredScreen _screen({bool playFails = false}) => UpdateRequiredScreen(
  packageName: 'com.beautica.app',
  installedVersion: '1.5.0',
  storeUrl: 'https://play.google.com/store/apps/details?id=com.beautica.app',
  launcher: (Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async =>
      !playFails,
);

void main() {
  for (final double width in kGoldenWidths) {
    for (final double scale in kGoldenTextScales) {
      final String suffix = widthScaleSuffix(width, scale);
      goldenTest(
        'update required ${width.toInt()}dp text-${scale}x',
        fileName: 'update_required_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(width: width),
        builder: _screen,
      );
    }
  }

  goldenTest(
    'update required — Play could not be opened 360dp',
    fileName: 'update_required_play_error_360',
    constraints: BoxConstraints.tight(const Size(360, kGoldenHeight)),
    textScaleFactor: 1.0,
    whilePerforming: (WidgetTester tester) async {
      await tester.tap(find.byKey(UpdateRequiredScreen.buttonKey));
      await tester.pumpAndSettle();
      return null;
    },
    pumpWidget: goldenPumpWidget(width: 360),
    builder: () => _screen(playFails: true),
  );
}
