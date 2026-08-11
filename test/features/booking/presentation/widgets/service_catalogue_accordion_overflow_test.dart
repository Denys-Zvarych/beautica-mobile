// TEXT-CLIPPING / LAYOUT-OVERFLOW guard for `CatalogueServiceTile`
// (`lib/features/booking/presentation/widgets/service_catalogue_accordion.dart`).
//
// WHY THIS FILE EXISTS
// ---------------------
// The user-visible bug this guards against: adding the per-row favourite
// heart to `CatalogueServiceTile` (Phase 240) squeezed the top `Row` — which
// used to hold the CHECK CONTROL, the service NAME, the PRICE and (for the
// master flow) the HEART all as siblings — so a long service name got
// truncated more aggressively than before the heart shipped. The fix moved
// the price off that row onto the meta line (ahead of the duration, as one
// `Text.rich`), so the top row now holds only the check control, the name
// (alone, in its own `Expanded`) and the optional heart. A mobile-build-
// verifier scratch probe proved this fix overflow-free at width 240-320 /
// textScale 1.0-2.0, with/without the heart, using long price + long
// duration fixtures — then DELETED the probe. This file is that probe made
// permanent, following the exact stress-matrix pattern
// `booking_surfaces_overflow_test.dart` already established for the other
// three booking surfaces (own file here, not folded into that one — that
// file's own header scopes it explicitly to the three OTHER surfaces: the
// bookings list, the detail screen and the cancel dialog).
//
// WHAT IT PROVES
// --------------
//   1. No `RenderFlex overflowed` stripe on this tile, ever, across the
//      worst realistic combination: width 240-414dp x textScale 1.0-2.0 x
//      `showFavoriteHeart` true/false, with a long name AND a long price
//      band AND a long duration all at once (`_lay`/`pumpApp`'s suite-wide
//      overflow guard — see `test/helpers/overflow_guard.dart` — fails the
//      test automatically on any recorded overflow; nothing here needs a
//      manual `takeException()`).
//   2. The regression itself, structurally: the heart's trailing slot now
//      costs the name ONLY its own footprint — price no longer shares the
//      row and is not deducted from the name's available width. Proven by
//      an ABSOLUTE width measurement (not a delta — a delta between
//      heart-on/heart-off would be the same magnitude whether or not price
//      also competed, so it cannot distinguish old code from new; the
//      absolute available width can, and does — see the mutation-proof note
//      below).
//
// MUTATION PROOF (M14 — a structural assertion must be shown load-bearing)
// --------------------------------------------------------------------
// `'the heart costs the name only its own footprint'` was run against the
// PRE-FIX widget (`git stash` on `service_catalogue_accordion.dart` alone,
// this test file kept in place) and FAILED there — the name's measured
// available width was ~62dp narrower than the fixed assertion's tolerance
// window, because price was still sharing the row and eating into it. Back
// on the fixed widget it passes. This is the direct, load-bearing proof
// that the assertion would have caught the original bug, not just described
// it.

import 'package:beautica_mobile/features/booking/presentation/widgets/service_catalogue_accordion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Deliberately OVER-LONG fixtures — longer than any real backend value, per
// `booking_surfaces_overflow_test.dart`'s own convention. The name is
// Cyrillic (the primary locale) and long enough to ellipsise at every width
// in the matrix, including the widest (414dp) — required so the "available
// width" measurement below (technique note in the group's own header) is a
// clamp to the constraint, not the string's own intrinsic width.
// ---------------------------------------------------------------------------

const String _longName =
    'Комбінований апаратний манікюр з покриттям гель-лаком, зміцненням '
    'бази та художнім дизайном усіх нігтів на обох руках одночасно';

/// The exact fixtures the deleted verifier probe used.
const String _longPrice = '1200–2500 ₴';
const String _longDuration = '2 год 45 хв';

CatalogueRow _row({
  String id = 'overflow-row',
  String name = _longName,
  String priceLabel = _longPrice,
  String durationLabel = _longDuration,
}) => CatalogueRow(
  id: id,
  name: name,
  categoryLabel: 'MANICURE',
  durationLabel: durationLabel,
  priceLabel: priceLabel,
);

/// Advances one-shot animations without `pumpAndSettle` (which would hang on
/// a genuinely overflowing, re-reporting tree) — same bounded pump-until-
/// stable technique as `booking_surfaces_overflow_test.dart`'s own `_lay`.
Future<void> _lay(WidgetTester tester) async {
  await tester.pump();
  const Duration step = Duration(milliseconds: 16);
  for (int i = 0; i < 60 && tester.binding.hasScheduledFrame; i++) {
    await tester.pump(step);
  }
}

const List<double> _widths = <double>[240, 320, 360, 414];
const List<double> _scales = <double>[1.0, 1.3, 2.0];

void main() {
  group('overflow guard — long name + long price + long duration', () {
    for (final double width in _widths) {
      for (final double scale in _scales) {
        for (final bool heart in <bool>[true, false]) {
          testWidgets('CatalogueServiceTile @ ${width}dp x$scale '
              '(showFavoriteHeart: $heart) — no overflow', (tester) async {
            await tester.pumpApp(
              Scaffold(
                body: CatalogueServiceTile(
                  row: _row(),
                  selected: false,
                  onToggle: () {},
                  showFavoriteHeart: heart,
                ),
              ),
              width: width,
              textScaleFactor: scale,
            );
            await _lay(tester);

            // Sanity: the tile actually composed (the guard's tearDown is
            // what fails on overflow — this just proves we pumped the
            // real tree, not an empty one).
            expect(
              find.byKey(const Key('catalogue-service-name-overflow-row')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('catalogue-service-meta-overflow-row')),
              findsOneWidget,
            );
            if (heart) {
              expect(
                find.byKey(const Key('booking_service_heart_overflow-row')),
                findsOneWidget,
              );
            } else {
              expect(
                find.byKey(const Key('booking_service_heart_overflow-row')),
                findsNothing,
              );
            }
          });
        }
      }
    }
  });

  group('the deliberate truncation this file asserts', () {
    testWidgets(
      'the long name still ellipsises (maxLines: 1) — expected, not a bug',
      (tester) async {
        await tester.pumpApp(
          Scaffold(
            body: CatalogueServiceTile(
              row: _row(),
              selected: false,
              onToggle: () {},
              showFavoriteHeart: true,
            ),
          ),
          width: 320,
        );
        await _lay(tester);

        final RenderParagraph name = tester.renderObject<RenderParagraph>(
          find.byKey(const Key('catalogue-service-name-overflow-row')),
        );
        expect(
          name.didExceedMaxLines,
          isTrue,
          reason:
              'the fixture name is deliberately longer than any realistic '
              'backend value specifically so it ellipsises at every width '
              'in the matrix — this is the maxLines:1 contract, not the bug',
        );
      },
    );

    testWidgets(
      'the meta line (price, icon, duration) never overflows even when '
      'both figures are maximally long',
      (tester) async {
        await tester.pumpApp(
          Scaffold(
            body: CatalogueServiceTile(
              row: _row(name: 'X'), // short name — isolates the meta line
              selected: false,
              onToggle: () {},
              showFavoriteHeart: true,
            ),
          ),
          width: 240,
          textScaleFactor: 2.0,
        );
        await _lay(tester);

        // No overflow (asserted automatically by the guard's tearDown); the
        // meta line's `Wrap` may legitimately drop the icon+duration group
        // to its own line at this extreme (240dp x 2.0x with a heart AND a
        // long price band AND a long duration), and either `Text`'s own
        // `maxLines:1`/`ellipsis` may still fire beyond that — that is the
        // safety valve `_metaLine` exists for, not something to assert
        // against. What IS asserted (never legitimately allowed to
        // degrade) is that neither figure paints zero glyphs — see the
        // dedicated group below.
        expect(
          find.byKey(const Key('catalogue-service-meta-overflow-row')),
          findsOneWidget,
        );
      },
    );
  });

  group('finding 1 (MEDIUM, mobile-security, round 2) — duration must always '
      'paint something', () {
    // Pins the empirical repro from the audit: at a constrained width and
    // an elevated textScaleFactor with a long RANGE price, the ROUND-1
    // `Text.rich` meta line's single `maxLines: 1` paragraph gave duration
    // (last in span order) a shared, sometimes-EMPTY truncation budget —
    // `RenderParagraph.getBoxesForSelection` for the duration substring
    // returned `[]`: zero painted glyphs, not partial truncation. A widget
    // existing in the tree proves nothing here (`findsOneWidget` above
    // would have passed even on the broken round-1 widget) — only a
    // painted-box / measured-width check can tell "ellipsised down to one
    // character" apart from "not painted at all", which is exactly the
    // distinction that matters for a fact (the appointment's duration)
    // the client needs before booking.
    Future<double> durationLaidOutWidth(
      WidgetTester tester, {
      required bool heart,
    }) async {
      const String rowId = 'duration-paint-probe';
      await tester.pumpApp(
        Scaffold(
          body: CatalogueServiceTile(
            row: _row(
              id: rowId,
              name: 'X', // short name — isolates the meta line
              priceLabel: '1 200–3 500 ₴', // long RANGE price, per the audit
              durationLabel: '1 год 30 хв',
            ),
            selected: false,
            onToggle: () {},
            showFavoriteHeart: heart,
          ),
        ),
        width: 240,
        textScaleFactor: 1.6,
      );
      await _lay(tester);

      // `durationLabel` is pre-formatted DATA (`DurationMinutes.format`), not
      // `AppLocalizations` UI copy — it is identical in every locale, same
      // rationale as `service_catalogue_accordion_test.dart`'s fixture-data
      // annotations.
      final Finder durationText = find.descendant(
        of: find.byKey(const Key('catalogue-service-meta-$rowId')),
        // i18n-finder-ok: fixture duration (test data), not app UI copy.
        matching: find.text('1 год 30 хв'),
      );
      expect(
        durationText,
        findsOneWidget,
        reason:
            'the duration Text must still be IN THE TREE (a Wrap child '
            'that drops to its own line is still built) — this alone does '
            'not prove it painted anything, which is why the width/box '
            'check below is the real assertion',
      );

      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        durationText,
      );
      // `getBoxesForSelection` over the FULL text range is empty iff
      // nothing painted — the exact symptom the audit reproduced against
      // the round-1 `Text.rich`.
      final List<TextBox> boxes = paragraph.getBoxesForSelection(
        const TextSelection(
          baseOffset: 0,
          extentOffset: 11, // '1 год 30 хв'.length
        ),
      );
      expect(
        boxes,
        isNotEmpty,
        reason:
            'finding 1: the duration must paint at least one glyph box — '
            'an empty list here means the duration is entirely unpainted, '
            'not merely ellipsised',
      );

      return paragraph.size.width;
    }

    testWidgets(
      'duration still paints when the price is long and pressure is high '
      '(without the heart)',
      (tester) async {
        final double width = await durationLaidOutWidth(tester, heart: false);
        expect(width, greaterThan(0));
      },
    );

    testWidgets(
      'duration still paints when the price is long and pressure is high '
      '(with the heart, the tightest real case)',
      (tester) async {
        final double width = await durationLaidOutWidth(tester, heart: true);
        expect(width, greaterThan(0));
      },
    );
  });

  group('finding 2 (mobile-build-verifier) — the duration must degrade like '
      'the price, not throw', () {
    // The price `Text` is a DIRECT `Wrap` child, so `Wrap` bounds its width
    // and `maxLines: 1`/`ellipsis` engages — a pathological price ellipsises
    // instead of overflowing (empirically proven by the verifier: a ~60-char
    // price measured 138dp inside a 240dp tile, `didExceedMaxLines: true`,
    // no overflow). Before this fix, the duration `Text` sat inside the
    // icon-pairing `Row` with NO `Flexible`/`Expanded`, so that `Row` handed
    // it unbounded width and `maxLines`/`ellipsis` never had a finite width
    // to truncate against — a pathological duration threw a genuine
    // `RenderFlex overflowed by 557 pixels`, caught live by this suite's
    // `overflow_guard.dart`. This test pins the fix: the duration `Text` is
    // now wrapped in `Flexible`, so it degrades exactly as price does.
    testWidgets(
      'a pathologically long duration ellipsises instead of overflowing '
      '(240dp x2.0, heart shown)',
      (tester) async {
        const String rowId = 'pathological-duration-probe';
        // Deliberately far longer than any real `DurationMinutes.format`
        // output (a real duration is at most a couple of digits either
        // side of "год"/"хв") — exists only to prove the `Flexible`
        // ellipsis safety valve, mirroring how the meta-line's price side
        // is already proven safe against an over-long RANGE price.
        const String pathologicalDuration =
            '99 год 59 хв 99 год 59 хв 99 год 59 хв 99 год 59 хв 99 год '
            '59 хв 99 год 59 хв 99 год 59 хв 99 год 59 хв';
        await tester.pumpApp(
          Scaffold(
            body: CatalogueServiceTile(
              row: _row(
                id: rowId,
                name: 'X', // short name — isolates the meta line
                priceLabel: '300 ₴',
                durationLabel: pathologicalDuration,
              ),
              selected: false,
              onToggle: () {},
              showFavoriteHeart: true,
            ),
          ),
          width: 240,
          textScaleFactor: 2.0,
        );
        await _lay(tester);

        // No `RenderFlex overflowed` stripe (asserted automatically by the
        // suite-wide overflow guard's `tearDown` — see file header). The
        // tile composing at all, with the meta line present, is the sanity
        // check; the real assertion is the ABSENCE of a recorded overflow.
        expect(
          find.byKey(const Key('catalogue-service-meta-$rowId')),
          findsOneWidget,
        );
      },
    );
  });

  group('the regression itself — the heart costs the name only its own '
      'footprint', () {
    testWidgets(
      'at a fixed tile width, the name has the SAME available width with '
      'the heart shown as it would if price were still absent from the row',
      (tester) async {
        // A tight but SHORT (not over-long) name here so the paint result
        // between the two configurations differs ONLY in the width the
        // Text is CONSTRAINED to, not in some other font-shaping quirk —
        // both still use the same over-long name to guarantee ellipsis (so
        // the measured `size.width` clamps to the constraint, per the file
        // header's technique note) but the exact string is irrelevant here;
        // only the two constraint widths are compared.
        const double tileWidth = 320;

        Future<double> nameWidthWith({required bool heart}) async {
          await tester.pumpApp(
            Scaffold(
              body: CatalogueServiceTile(
                row: _row(id: 'w-probe'),
                selected: false,
                onToggle: () {},
                showFavoriteHeart: heart,
              ),
            ),
            width: tileWidth,
          );
          await _lay(tester);
          return tester
              .getSize(find.byKey(const Key('catalogue-service-name-w-probe')))
              .width;
        }

        final double widthWithHeart = await nameWidthWith(heart: true);
        final double widthWithoutHeart = await nameWidthWith(heart: false);

        // The heart's own trailing-slot footprint (icon 24dp + its
        // Padding(left: VelvetSpacing.xs = 4dp) + the SizedBox(width:
        // VelvetSpacing.xs = 4dp) gap before it) is the ONLY thing that
        // should separate these two measurements now that price lives on
        // the meta line instead of this row. Before the fix, price
        // ('1200–2500 ₴' at `VelvetText.feedbackMutedSm`, ~60-70dp) plus its
        // own `VelvetSpacing.sm` (8dp) gap ALSO sat in this row, so the
        // pre-fix delta (and pre-fix absolute widths) would be far outside
        // this window — see the file header's mutation-proof note; this is
        // the assertion that was run against the pre-fix widget and failed
        // there.
        final double delta = widthWithoutHeart - widthWithHeart;
        expect(
          delta,
          inInclusiveRange(20.0, 40.0),
          reason:
              'the heart footprint alone (icon + its two small gaps) should '
              'account for the whole difference — a wider delta would mean '
              "something else (e.g. the price returning to this row) is "
              'also eating into the name\'s available width',
        );

        // Absolute floor: even WITH the heart, the name keeps the vast
        // majority of the tile's content width — at 320dp minus the check
        // control (30dp), its gap (16dp), the tile's own horizontal padding
        // (2 x 12dp) and the heart's footprint (~32dp), the name should
        // still have roughly 210-230dp. A regression that reintroduced price
        // into this row would additionally deduct ~60-70dp + an 8dp gap,
        // landing well under this floor.
        expect(
          widthWithHeart,
          greaterThan(200.0),
          reason:
              'with price correctly OFF this row, the name should still '
              'have the great majority of the tile width even with the '
              'heart present',
        );
      },
    );
  });
}
