// Unit tests for [TimelineDensity] — the single token every timeline
// constant is derived from (`timeline_density.dart`, phase 21.12).
//
// WHY THIS FILE EXISTS
// --------------------
// `timeline_density.dart` (199 lines, new on this branch) shipped with NO
// test of its own. It is exercised only transitively, by six widget/golden
// files that render through it. That is the wrong tier for what it actually
// is: a pure arithmetic derivation whose every output is a documented
// literal, where a one-character edit re-tiers the entire board and the
// rendered result still looks plausible.
//
// TWO CLAIMS IN ITS DOC ARE LOAD-BEARING AND WERE UNTESTED:
//
//   1. «[TimelineDensity.master] reproduces the shipped timeline
//      pixel-for-pixel: every getter below returns exactly the literal the
//      corresponding retired constant held.» The file's whole justification
//      for deleting `BookingsTimelineGrid._kHourH` /
//      `TimelineHourRuler._kHourH` is that the master scope is unchanged. It
//      says so «BY CONSTRUCTION, not by a test» ([columnWidth]'s doc) — which
//      is honest about the formula's shape, but says nothing about the
//      LITERALS, which a later density pass can and historically did move
//      (`72` → `112` → `168` → `120`).
//
//   2. The MASTER scope's 60-minute band must clear
//      [MasterBookingCard.fullLayoutMinHeight], or every one-hour master
//      booking silently drops from the FULL body to the COMPACT one. The
//      grid's ADDENDUM 8 calls this the reason `120` «may not go lower», and
//      `timeline_hour_ruler.dart:69-80` states the clearance explicitly — but
//      as PROSE in three files, with nothing that fails when it stops being
//      true. Note that prose is already stale: it cites `118dp` and «2dp of
//      clearance» while the constant it names is now `115`. That drift is
//      exactly what an untested invariant does.
//
// WIDGET-FIELD VACUITY DOES NOT APPLY HERE. Reading a field off a rendered
// widget and calling it layout is vacuous. This is the opposite case: the
// subject under test IS the arithmetic, it has no render path of its own,
// and the six render-tier tests that consume it cannot discriminate «120»
// from «118» in a PNG. Cross-constant RELATIONSHIPS — not restatements of a
// single literal — are what carry the weight below.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_density.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/timeline_hour_ruler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimelineDensity.master reproduces the retired constants', () {
    test('scale is the identity, and the scope is single-column', () {
      expect(TimelineDensity.master.scale, 1);
      expect(
        TimelineDensity.master.columnsPerViewport,
        1,
        reason:
            'at 1 the gutter term vanishes and columnWidth reduces to the '
            'shipped min(ceiling, maxWidth) — the premise the whole '
            '"master scope unchanged" argument rests on',
      );
    });

    test('every vertical literal is the one the retired constants held', () {
      expect(
        TimelineDensity.master.hourHeight,
        120,
        reason:
            'the retired `BookingsTimelineGrid._kHourH` / '
            '`TimelineHourRuler._kHourH`. History 72 -> 112 -> 168 -> 120: '
            'this number has moved three times, so "unchanged by '
            'construction" covers the FORMULA, never the literal.',
      );
      expect(
        TimelineDensity.master.slotHeight,
        TimelineDensity.master.hourHeight / 2,
        reason: 'a slot is a half-hour, in both scopes, by definition',
      );
    });

    test('rulerWidth still equals the mirror TimelineHourRuler kept', () {
      // THE DRIFT THE TOKEN WAS CREATED TO KILL, asserted across the two
      // files rather than restated inside one. `kMasterRulerWidth` survives
      // in `timeline_hour_ruler.dart` as a documented mirror; nothing
      // currently fails if the token moves and the mirror does not, which is
      // the same two-numbers-one-comment coupling `_kHourH` had.
      expect(
        TimelineDensity.master.rulerWidth,
        TimelineHourRuler.kMasterRulerWidth,
      );
      expect(TimelineDensity.master.rulerWidth, 42);
    });

    test('horizontal literals match the shipped grid', () {
      expect(TimelineDensity.master.columnWidthCeiling, 272);
      expect(
        TimelineDensity.master.columnGutter,
        VelvetSpacing.sm,
        reason:
            'at master the column gutter IS the lane gutter the shipped grid '
            'has always used — asserted against the token, not against 8, so '
            'a VelvetSpacing change surfaces here rather than silently '
            'redefining the grid',
      );
    });

    test(
      'columnWidth is the shipped min(ceiling, maxWidth), term for term',
      () {
        // Three viewports: below the ceiling, exactly at it, above it. The
        // middle one is the only value at which both arms agree, so a
        // formula that returned the WRONG arm would still pass if it were
        // the only case tested.
        expect(TimelineDensity.master.columnWidth(200), 200);
        expect(TimelineDensity.master.columnWidth(272), 272);
        expect(TimelineDensity.master.columnWidth(400), 272);
      },
    );
  });

  group('TimelineDensity.salon — 70% bands at the 360dp baseline', () {
    test('scale and column count', () {
      expect(TimelineDensity.salon.scale, TimelineDensity.salonScale);
      expect(TimelineDensity.salonScale, 0.7);
      expect(TimelineDensity.salon.columnsPerViewport, 2);
    });

    test('vertical bands are exactly 70% of master', () {
      expect(
        TimelineDensity.salon.hourHeight,
        TimelineDensity.master.hourHeight * TimelineDensity.salonScale,
      );
      expect(TimelineDensity.salon.hourHeight, closeTo(84, 0.0001));
      expect(
        TimelineDensity.salon.slotHeight,
        TimelineDensity.salon.hourHeight / 2,
      );
    });

    test('rulerWidth hits its 30dp FLOOR rather than the scaled value', () {
      // 42 * 0.7 = 29.4, which rounds to 29 — BELOW the floor. So the floor
      // is genuinely load-bearing at the shipped salon scale, not a
      // defensive no-op, and a change to either the floor or `salonScale`
      // moves the rendered ruler. Both arms are asserted so the test says
      // WHICH one won.
      expect((42 * TimelineDensity.salonScale).roundToDouble(), 29);
      expect(TimelineDensity.salon.rulerWidth, 30);
    });

    test('columnGutter scales but stays above its 4dp floor', () {
      expect(
        (VelvetSpacing.sm * TimelineDensity.salonScale).roundToDouble(),
        6,
      );
      expect(TimelineDensity.salon.columnGutter, 6);
    });

    test('two masters fit at the 360dp Android baseline', () {
      // The worked example in [TimelineDensity.columnWidth]'s own doc:
      //   lane viewport = 360 - 12 - 12 - 30 (rulerWidth) - 4 (gap) = 302
      //   column        = min(190, (302 - 6) / 2) = 148
      const double laneViewport = 360 - 12 - 12 - 30 - 4;
      expect(laneViewport, 302);

      expect(TimelineDensity.salon.columnWidthCeiling, 190);
      expect(TimelineDensity.salon.columnWidth(laneViewport), 148);

      // The CONTRACT the number serves, stated independently of it: two
      // columns plus their gutter must fit inside the viewport. This is what
      // still fails if someone "fixes" 148 to something else.
      expect(
        TimelineDensity.salon.columnWidth(laneViewport) * 2 +
            TimelineDensity.salon.columnGutter,
        lessThanOrEqualTo(laneViewport),
        reason: 'the salon board must always show two masters at 360dp',
      );
    });

    test('a wide viewport grows columns TOWARD the ceiling, never past', () {
      expect(
        TimelineDensity.salon.columnWidth(1000),
        TimelineDensity.salon.columnWidthCeiling,
      );
    });
  });

  group('the band-vs-card-layout invariant (grid ADDENDUM 8)', () {
    test(
      'a MASTER 60-minute band clears MasterBookingCard.fullLayoutMinHeight',
      () {
        // If this ever goes false, every one-hour booking on the master
        // timeline silently renders the COMPACT body instead of the FULL
        // one. Nothing else in the suite fails: the card still lays out, the
        // goldens get regenerated, and the regression ships.
        expect(
          TimelineDensity.master.hourHeight,
          greaterThanOrEqualTo(MasterBookingCard.fullLayoutMinHeight),
          reason:
              'ADDENDUM 8: 120 is the smallest scale at which a 60-minute '
              'band still clears the full layout. Lowering hourHeight, or '
              'raising the card\'s natural height, breaks the master board.',
        );
        // The margin, pinned so a change that eats it is VISIBLE in the diff
        // rather than merely still-passing. (The prose in
        // `timeline_hour_ruler.dart` says "2dp"; it is stale — the constant
        // it cites moved from 118 to 115.)
        expect(
          TimelineDensity.master.hourHeight -
              MasterBookingCard.fullLayoutMinHeight,
          5,
          reason: 'clearance is 5dp — update this AND the prose together',
        );
      },
    );

    test('the SALON band deliberately does NOT clear it — bands shrink, type '
        'does not', () {
      // The documented design decision, asserted so it reads as INTENDED
      // rather than as an accident someone later "fixes" by scaling the
      // card thresholds too (which would shrink the very text a salon
      // owner is scanning — see `timeline_density.dart`'s header).
      expect(
        TimelineDensity.salon.hourHeight,
        lessThan(MasterBookingCard.fullLayoutMinHeight),
        reason:
            'salon cards re-tier to compact/micro BY DESIGN. If this flips, '
            'someone scaled the card\'s height thresholds by `scale` — the '
            'one thing the density token forbids.',
      );
    });
  });
}
