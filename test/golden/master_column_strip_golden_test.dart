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
//  1. BOOKED — camel figure, full-strength name, full-strength avatar.
//  2. FREE — the master IS working and has nothing booked: dimmed avatar,
//     muted name, «вільно».
//  3. DAY OFF — the master is NOT working: the SAME de-emphasis as cell 2 (it
//     is deliberately one `quiet` flag, not two styles that could drift) with
//     «Вихідний» in place of «вільно».
//
// THE POLICY CELLS 2 AND 3 ENCODE, MECHANICALLY
// ---------------------------------------------
// Cells 2 and 3 differ ONLY in the trailing word. That is the design decision
// — one de-emphasis, two statements — and the parity test at the bottom of
// this file is its mechanical form: it asserts the free and day-off baselines
// are NOT byte-identical (the word must actually change, or the fix is
// invisible) while both differ from the booked one. Without that pair, a
// regenerated cell 3 would happily bake in "identical to cell 2" and the whole
// point of the phase would sail through green.
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

  // Cell 1 — BOOKED. The unchanged, pre-phase-336 loaded state.
  goldenTest(
    'master_column_strip booked (camel figure, full-strength chip)',
    fileName: _kBookedFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(_strip(count: 3)),
  );

  // Cell 2 — FREE. Working, nothing booked. Unchanged by phase 336.
  goldenTest(
    'master_column_strip free (working, nothing booked — «вільно»)',
    fileName: _kFreeFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(_strip(count: 0)),
  );

  // Cell 3 — DAY OFF. Phase 336's new state.
  goldenTest(
    'master_column_strip day off (not working at all — «Вихідний»)',
    fileName: _kDayOffFile,
    constraints: BoxConstraints.tight(cell),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => _host(_strip(count: 0, dayOff: true)),
  );

  // ── The "one de-emphasis, two statements" policy, mechanically ───────────
  group('quiet-state parity (phase 336)', () {
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

    test('the DAY-OFF baseline differs from the FREE one — otherwise the state '
        'the whole phase adds is invisible', () {
      expect(
        bytes(_kDayOffFile),
        isNot(orderedEquals(bytes(_kFreeFile))),
        reason:
            'an off master and a free master must not look the same: that '
            'IS the bug this phase fixes. A chip that stopped picking up '
            '`dayOff` shows up here even after a regeneration.',
      );
    });

    test('both quiet baselines differ from the BOOKED one', () {
      expect(bytes(_kFreeFile), isNot(orderedEquals(bytes(_kBookedFile))));
      expect(bytes(_kDayOffFile), isNot(orderedEquals(bytes(_kBookedFile))));
    });
  });
}
