// «Навчання» (NAVCHANNIA) category icon — render proof.
//
// `category_icon_asset_contract_test.dart` checks the SVG as TEXT (viewBox,
// no hard-coded fills). This file proves the bundled asset actually PARSES
// and renders through the app's own icon path: `categoryIconFor` → `AppIcon`
// → `SvgPicture`. A malformed path / unsupported element would pass the text
// contract and still throw (or draw nothing) on-device.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/icons/category_icons.dart';

const Key _iconKey = Key('navchannia_category_icon');

void main() {
  testWidgets('NAVCHANNIA resolves through AppIcon to the bundled SVG, which '
      'decodes to a 24x24 picture and renders without error', (
    WidgetTester tester,
  ) async {
    final String asset = categoryIconFor(categoryKey: 'NAVCHANNIA');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppIcon(asset, key: _iconKey, size: 32, color: Colors.brown),
          ),
        ),
      ),
    );

    final SvgPicture svg = tester.widget<SvgPicture>(
      find.descendant(
        of: find.byKey(_iconKey),
        matching: find.byType(SvgPicture),
      ),
    );
    final SvgAssetLoader loader = svg.bytesLoader as SvgAssetLoader;
    expect(loader.assetName, BeauticaAssetIcons.categoryNavchannia);

    // Real decode of the bundled bytes (parser + vector_graphics compiler).
    final PictureInfo? info = await tester.runAsync(
      () => vg.loadPicture(loader, null),
    );
    expect(info, isNotNull);
    expect(info!.size, const Size(24, 24));
    info.picture.dispose();

    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_iconKey)), const Size(32, 32));
  });
}
