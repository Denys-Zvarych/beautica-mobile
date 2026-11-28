// M542 — CategoryIconGlyph remote branch golden (SVC-04 / SVC-58).
//
// Two glyphs side by side on the brand base, same size and tint: BROWS has no
// cached remote icon (bundled THIN asset), NAIL_SERVICE has the fixture SVG in
// the store (remote branch, `SvgPicture.memory` + the same srcIn tint). A
// regression that drops the tint on the remote branch (the fixture is drawn in
// `currentColor`, so it would paint black), changes its box, or stops reading
// the store moves this baseline. The existing category goldens (rail, setup,
// form, accordion, booking card, timeline) prove the bundled branch is
// unchanged — they render with an empty store.
//
// File name: category_icon_glyph_remote_360_1x.png

import 'dart:io';
import 'dart:typed_data';

import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/icons/category_icon_glyph.dart';
import 'package:beautica_mobile/core/icons/category_icon_store.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

final Uint8List _fixtureSvg = File(
  'test/core/icons/fixtures/remote_category_icon.svg',
).readAsBytesSync();

class _SeededStore extends CategoryIconStore {
  @override
  Map<String, CategoryIconBytes> build() => <String, CategoryIconBytes>{
    'NAIL_SERVICE': (
      url:
          'https://media.test/catalog/category-icons/NAIL_SERVICE/0123456789abcdef.svg',
      bytes: _fixtureSvg,
    ),
  };
}

Widget _scene() => const ColoredBox(
  color: BrandColors.base,
  child: Padding(
    padding: EdgeInsets.all(16),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CategoryIconGlyph(
          BeauticaAssetIcons.categoryBrows,
          key: Key('glyph_bundled'),
          categoryKey: 'BROWS',
          size: 36,
          color: BrandColors.accentDeep,
        ),
        SizedBox(width: 16),
        CategoryIconGlyph(
          BeauticaAssetIcons.categoryNailService,
          key: Key('glyph_remote'),
          categoryKey: 'NAIL_SERVICE',
          size: 36,
          color: BrandColors.accentDeep,
        ),
      ],
    ),
  ),
);

void main() {
  const double width = 360;
  goldenTest(
    'category icon glyph — bundled vs cached remote ${width.toInt()}dp',
    fileName: 'category_icon_glyph_remote_${widthScaleSuffix(width, 1.0)}',
    constraints: BoxConstraints.tight(const Size(width, 80)),
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: <Object>[
        categoryIconStoreProvider.overrideWith(_SeededStore.new),
      ],
    ),
    builder: _scene,
  );
}
