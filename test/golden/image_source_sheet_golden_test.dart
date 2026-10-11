// `ImageSourceSheet` golden — Phase 071. Default (2 rows) + canRemove (3 rows,
// destructive row in the error token).
//
// SEED / REFRESH: `flutter test --update-goldens
// test/golden/image_source_sheet_golden_test.dart`.

import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kSheetGoldenWidth = 360;

void main() {
  for (final ({String name, bool canRemove}) c
      in <({String name, bool canRemove})>[
        (name: 'image_source_sheet', canRemove: false),
        (name: 'image_source_sheet_can_remove', canRemove: true),
      ]) {
    goldenTest(
      'ImageSourceSheet ${c.name}',
      fileName: c.name,
      constraints: BoxConstraints.tight(
        const Size(_kSheetGoldenWidth, kGoldenHeight),
      ),
      textScaleFactor: 1.0,
      pumpWidget: goldenPumpWidget(width: _kSheetGoldenWidth),
      builder: () => Align(
        alignment: Alignment.topCenter,
        child: ImageSourceSheet(canRemove: c.canRemove),
      ),
    );
  }
}
