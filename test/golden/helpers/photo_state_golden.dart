// Shared harness for the phase-072 photo-state goldens (avatar editor,
// ProfileAvatar, ServicePhotoSlot, PhotoThumbnail): one PNG per scenario, so a
// later scenario can never move an earlier baseline.

import 'package:alchemist/alchemist.dart' show PumpWidget;
import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_media_cache.dart';
import 'golden_pump.dart';
import 'solid_png.dart';

/// Allow-listed host used by the URL scenarios.
const String kGoldenMediaHost = 'media.test';

/// An allow-listed URL the fake cache serves as a solid teal image.
const String kGoldenAllowedUrl = 'https://$kGoldenMediaHost/p.png';

/// Non-allow-listed host: must render the fallback and fetch nothing.
const String kGoldenDisallowedUrl = 'https://evil.test/p.png';

const double kPhotoGoldenWidth = 360;

/// Registers set-up/tear-down that allow-lists [kGoldenMediaHost] and serves a
/// solid image for every allowed fetch. Call once at the top of `main()`.
void registerPhotoGoldenMedia() {
  setUp(() {
    MediaConfig.debugAllowedHosts = <String>{kGoldenMediaHost};
    debugMediaCacheManager = FakeMediaCacheManager(_solidTeal);
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
  });
}

Stream<FileResponse> _solidTeal(String url) =>
    mediaLoadedWith(url, solidPng(0x3E, 0x7C, 0x8C));

/// [goldenPumpWidget] plus a real-time wait so a fake-cache image finishes its
/// off-fake-clock decode (`pumpAndSettle` alone never awaits it, and the golden
/// would silently capture the not-yet-loaded state).
PumpWidget _pumpWithImages(bool settle) {
  final PumpWidget base = goldenPumpWidget(
    width: kPhotoGoldenWidth,
    settle: settle,
  );
  return (WidgetTester tester, Widget child) async {
    await base(tester, child);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
  };
}

/// Registers one golden at 360 dp / 1x or 1.3x text scale.
void photoGolden(
  String fileName,
  Widget Function() build, {
  Size size = const Size(360, 260),
  double textScale = 1.0,
  bool settle = true,
}) {
  goldenTest(
    fileName,
    fileName: fileName,
    constraints: BoxConstraints.tight(size),
    textScaleFactor: textScale,
    pumpBeforeTest: settle ? onlyPumpAndSettle : pumpOnce,
    pumpWidget: _pumpWithImages(settle),
    builder: () => ColoredBox(
      color: BrandColors.base,
      child: Center(child: build()),
    ),
  );
}
