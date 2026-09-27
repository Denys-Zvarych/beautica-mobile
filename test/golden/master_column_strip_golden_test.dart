// Chrome golden — [MasterColumnStrip], the pinned roster strip above the
// salon «Записи» board
// (`lib/features/booking/presentation/widgets/master_column_strip.dart`).
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 336 gave the chip a THIRD state. `grep -rn MasterColumnStrip
// test/golden/` returned nothing before this file — the strip shipped with no
// pixel baseline at all, and the new state would have shipped with none
// either.
//
// Three cells, one per state, in one image each so the three can be diffed
// against each other by eye:
//
//  1. BOOKED — full-strength name, full-strength avatar.
//  2. FREE — the master IS working and has nothing booked: dimmed avatar,
//     muted name.
//  3. DAY OFF — the master is NOT working: the SAME de-emphasis as cell 2 (it
//     is deliberately one `quiet` flag, not two styles that could drift).
//
// THE POLICY CELLS 2 AND 3 ENCODE, MECHANICALLY
// ---------------------------------------------
// The chip no longer DRAWS a trailing load readout in any state — not the
// booking figure, not «вільно», not «Вихідний». Those three words were the
// only thing that ever separated cell 2 from cell 3, so the policy INVERTED:
// the two quiet baselines must now be byte-IDENTICAL, and the parity test at
// the bottom of this file is that statement's mechanical form. It is not a
// weakening — a chip that started styling `dayOff` differently from `free`,
// or that brought any readout back in one quiet state and not the other,
// fails there. Both must still differ from the BOOKED cell, which is what
// pins the `quiet` de-emphasis (dimmed avatar, muted name) that the readout
// removal deliberately KEPT.
//
// «Вихідний» itself did not disappear from the product: it moved to the
// grid's day-off column overlay (`bookings_timeline_grid.dart`) and to the
// chip's Semantics label, both covered structurally by the day-off column
// test named below.
//
// A NOTE ON WHAT THESE BASELINES ARE NOT
// --------------------------------------
// A golden regenerated from the code under test is self-referential. The
// CORRECTNESS of the day-off state — which string, derived from which
// predicate, over which column — is established structurally and
// independently in
// `test/features/booking/presentation/widgets/salon_bookings_day_off_column_test.dart`
// and `test/features/salon/presentation/salon_bookings_day_off_test.dart`.
// These PNGs' job from here is unintended pixel DRIFT, nothing more.
//
// Matrix kept tight (this is chrome, not a screen): {360} dp × {1.0} scale —
// the convention `client_top_bar_golden_test.dart` established for shared
// chrome. Suite config renders CI-mode goldens (`obscureText: true`,
// `renderShadows: false`), so text is coloured blocks and the chip's halo is
// suppressed; the chip's border and the avatar's dimming are neither, and
// render normally.
//
// CLOCK: the strip renders no date — no clock override needed.

import 'dart:io';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/golden_pump.dart';

const String _kBookedFile = 'master_column_strip_booked_360_1x';
const String _kFreeFile = 'master_column_strip_free_360_1x';
const String _kDayOffFile = 'master_column_strip_day_off_360_1x';

/// The rendered column width at the 360dp Android baseline — see
/// `TimelineDensity.columnWidth`'s arithmetic. Hard-coded rather than derived
/// so a density change shows up as a golden diff instead of silently
/// following.
const double _kColumnWidth = 148;

/// Hosts the chip on the brand base color at exactly one column's width, which
/// is what the board hands it.
Widget _host(Widget child) => ColoredBox(
  color: BrandColors.base,
  child: Padding(padding: const EdgeInsets.all(12), child: child),
);

/// The three cells share EVERY field but [bookingCount] and [dayOff]. That is
/// the point: any pixel difference beyond the trailing word is a style fork.
///
/// i18n-finder-ok / raw strings: golden fixture data feeding the strip's
/// opaque slots, not production UI copy governed by l10n.
MasterColumnStrip _strip({required int count, bool dayOff = false}) =>
    MasterColumnStrip(
      entries: <MasterColumnEntry>[
        MasterColumnEntry(
          masterId: 'm1',
          name: 'Софія Бондар',
          type: MasterType.salonMaster,
          bookingCount: count,
          professionalTitle: 'Стиліст',
          avgRating: 4.8,
          dayOff: dayOff,
        ),
      ],
      columnWidth: _kColumnWidth,
      gutter: 6,
    );

void main() {
  // Width is the column plus the host's 12dp padding on each side; height
  // clears `MasterColumnStrip.height` (64) plus that padding with slack.
  const Size cell = Size(_kColumnWidth + 24, 100);
  const double width = 360;

  // Cell 1 — BOOKED. Full-strength chip; the camel figure it once carried is
  // gone with the rest of the readout.
  goldenTest(
    'master_column_strip booked (full-strength chip, no readout)',
    fileName: _kBookedFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(_strip(count: 3)),
  );

  // Cell 2 — FREE. Working, nothing booked: quiet, and wordless.
  goldenTest(
    'master_column_strip free (working, nothing booked — quiet, no readout)',
    fileName: _kFreeFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(_strip(count: 0)),
  );

  // Cell 3 — DAY OFF. Phase 336's state, now visually equal to cell 2.
  goldenTest(
    'master_column_strip day off (not working at all — quiet, no readout)',
    fileName: _kDayOffFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(_strip(count: 0, dayOff: true)),
  );

  // ── The "one de-emphasis, no statement" policy, mechanically ────────────
  group('quiet-state parity', () {
    File goldenFile(String name) => File('test/golden/goldens/$name.png');

    List<int> bytes(String name) {
      final File f = goldenFile(name);
      expect(
        f.existsSync(),
        isTrue,
        reason:
            'baseline $name must be committed; run '
            '`flutter test test/golden/ --update-goldens` if this is a first '
            'generation.',
      );
      return f.readAsBytesSync();
    }

    test('the DAY-OFF baseline is byte-IDENTICAL to the FREE one — the words '
        'that separated them are no longer drawn', () {
      expect(
        bytes(_kDayOffFile),
        orderedEquals(bytes(_kFreeFile)),
        reason:
            'the chip draws no load readout in either quiet state, and the '
            'de-emphasis is ONE `quiet` flag rather than two styles. Any '
            'pixel between them means a readout came back in one state, or '
            '`dayOff` grew a style fork of its own.',
      );
    });

    test('both quiet baselines differ from the BOOKED one — the de-emphasis '
        'the readout removal deliberately KEPT', () {
      expect(bytes(_kFreeFile), isNot(orderedEquals(bytes(_kBookedFile))));
      expect(bytes(_kDayOffFile), isNot(orderedEquals(bytes(_kBookedFile))));
    });
  });
}
