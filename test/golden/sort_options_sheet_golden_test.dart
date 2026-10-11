// `SortOptionsSheet` golden guard — Phase 071 (promotion proof).
//
// Phase 071 promotes the sheet chrome + option row out of
// `sort_options_sheet.dart` into `lib/shared/widgets/velvet_sheet.dart` so the
// image-source sheet reuses them. No golden existed for the sort sheet, so this
// one was SEEDED BEFORE the promotion; the post-promotion run must match it
// byte-for-byte (`feedback_golden_not_acceptance`: the proof is that the master
// did not change, not that a master exists).
//
// SEED / REFRESH: `flutter test --update-goldens
// test/golden/sort_options_sheet_golden_test.dart`.

import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/sort_options_sheet.dart';
import 'package:flutter/material.dart';

import 'helpers/golden_pump.dart';

const double _kSheetGoldenWidth = 360;

void main() {
  goldenTest(
    'SortOptionsSheet rating selected',
    fileName: 'sort_options_sheet',
    constraints: BoxConstraints.tight(
      const Size(_kSheetGoldenWidth, kGoldenHeight),
    ),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: _kSheetGoldenWidth),
    builder: () => const Align(
      alignment: Alignment.topCenter,
      child: SortOptionsSheet(active: SearchSort.ratingDesc),
    ),
  );
}
