// Tap-target guard for `FavoriteHeartButton`
// (`lib/features/discovery/presentation/widgets/favorite_heart_button.dart`)
// as embedded in its `CatalogueServiceTile` caller
// (`lib/features/booking/presentation/widgets/service_catalogue_accordion.dart`).
//
// mobile-security finding (MEDIUM), FOLLOW-UP: the heart's hit area was its
// painted 24dp icon plus a left-only `VelvetSpacing.xs` `Padding` — 28×24dp,
// asymmetric and below the platform floor — because this button used to
// render INLINE as the last child of `CatalogueServiceTile`'s `Row`, whose
// `Expanded` name/meta column pays dp-for-dp for any width it grows into.
//
// An intermediate draft grew that inline pad to 32×36 and called it a
// "partial fix". It was not free: it took 4dp off the name column, and this
// file's own width pin was set FROM that tree, so the pin agreed with the
// regression instead of catching it. Reverted — see
// `favorite_heart_button.dart`'s file header.
//
// THIS FILE proves the GENUINE fix: the heart is no longer rendered inline
// at all. The `Row` keeps an inert placeholder sized to the heart's
// HISTORICAL committed 28dp footprint (so the `Expanded` column's width is
// byte-identical to the tree on `main`), and the real, tappable heart is
// rendered by a `Stack` overlay on top of the tile — a genuine 48×48 hit
// box, reaching the Android 48dp / iOS 44pt floor (WCAG 2.5.5 / Material /
// HIG) with NO cost to the name column at all.
//
// WHAT THIS FILE PROVES
// ----------------------
// Three groups:
//   1. `group('the heart's hit box is a genuine 48x48')` — the box measures
//      48×48 (not just "grew"), the painted icon did NOT change, and four
//      fresh probes (one per edge, 2dp inside the box, outside the painted
//      icon) fire the favourite toggle.
//   2. `group('the name column is unchanged')` — pins the name `Text`'s
//      measured (constraint-clamped) width at both `showFavoriteHeart: true`
//      and `false`, at the same tile width, to the values verified by
//      DIRECT MEASUREMENT against the COMMITTED pre-overlay tree (heart
//      inline at 28×24): 218.0dp / 250.0dp at a 320dp tile with a long name
//      (see below) — a future regression that re-grows the heart INLINE, or
//      that re-sizes the placeholder slot against anything but that 28dp
//      footprint, moves this number and fails here.
//   3. `group('the row still selects where users actually tap')` — the
//      row's own selection gesture still fires everywhere outside the
//      heart's 48×48 box (name, meta line, checkbox, AND a probe placed 2dp
//      outside the box's LEFT edge) and does NOT also fire the favourite
//      there; conversely a tap inside the box fires the favourite and never
//      the row. The RIGHT edge gets a geometric pin instead of a probe —
//      correcting the overlay's anchor to the icon's historical centre puts
//      the box flush against the tile's trailing edge, leaving no
//      "outside-but-still-on-the-tile" point on that side. Nothing is lost:
//      `Align(centerRight)` pins the right edge however wide the box grows,
//      so only the LEFT edge ever moves and only the left probe could ever
//      have caught an over-expansion.
//
// MUTATION PROOFS (run during this change, restored byte-for-byte after
// each, all green again)
// -----------------------------------------------------------------------
//   - Reverting the `Stack` overlay (rendering `FavoriteHeartButton`
//     directly as the `Row`'s last child again) turns the box back into a
//     Row-inline box whose right edge is pinned to the row's own bound —
//     measured 48×48 in THAT position, but the edge probes anchored on the
//     OVERLAY's expected geometry (offset from the tile's right edge via
//     `_kHeartOverlayRightInset`) land outside it, and the name-column width
//     test fails outright (the `Expanded` column shrinks by another 20dp on
//     top of the placeholder, since the inline box is now 48dp wide, not the
//     reserved 28dp) — RED.
//   - Over-expanding the overlay's box (bumping `_kHeartHitExtent` to a
//     larger value without changing the row-selection boundary probe, which
//     is anchored on the FIX's own 48dp spec, not the live box) made the
//     "2dp outside the box" LEFT probe land INSIDE the over-expanded box
//     instead, firing the favourite and failing the "row selection, not
//     favourite" assertion — RED.
//   - Anchoring the overlay on the placeholder SLOT's centre instead of the
//     icon's historical centre (the 2dp drift described above
//     `_kExpectedRightInset`) moved the box's right edge off its derived
//     position and failed the new right-edge pin — RED. The sibling result
//     cards catch the same mutation as an 88-pixel golden diff.
//   - Sizing the placeholder slot against the abandoned 32dp draft instead
//     of the committed 28dp footprint made the name-column width test fail
//     (218.0dp measures 214.0dp) — RED. This is the mutation the earlier
//     version of this file could NOT catch, because its pin had been taken
//     from that same draft.
//   Restoring the exact shipped overlay turned every assertion green again.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/service_catalogue_accordion.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/favorite_heart_button.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../../helpers/pump_app.dart';

/// Android's 48dp / iOS's 44pt tap-target floor (WCAG 2.5.5, Material, HIG)
/// — restated from the public spec, not imported from the widget's own
/// constant, same rationale `wishlist_heart_button_tap_target_test.dart`
/// gives: the assertion below is that this box DOES reach the floor, and
/// that must not be derived from the same constant the widget uses to
/// build it (a mutation that shrinks both together would still "pass").
const double _kPlatformMinTapExtent = 48;

/// The heart's documented painted icon size — restated, not imported, same
/// rationale as [_kPlatformMinTapExtent]: this is the "did NOT change"
/// assertion, so it must not come from the same source the widget draws it
/// from.
const double _kPaintedIcon = 24;

/// A name deliberately longer than any realistic backend value so its
/// rendered `Text` width CLAMPS to the `Expanded` column's available
/// constraint (ellipsis engages) rather than reporting its own intrinsic
/// width — the same technique
/// `service_catalogue_accordion_overflow_test.dart` uses, required here
/// because the name-column-width group below needs to observe the
/// CONSTRAINT, not the string's natural size. Reused verbatim from that
/// file's own `_longName` fixture (kept as a local copy, per this test
/// suite's existing per-file-fixture convention — see this file's sibling
/// `_row` helper below, mirroring the older version of this same file).
const String _longName =
    'Комбінований апаратний манікюр з покриттям гель-лаком, зміцненням '
    'бази та художнім дизайном усіх нігтів на обох руках одночасно';

/// The tile width the name-column-width group pins its numbers against.
const double _kProbeTileWidth = 320;

/// The name `Text`'s measured width at [_kProbeTileWidth] with the heart
/// SHOWN — verified by direct measurement against the COMMITTED pre-overlay
/// tree (heart inline at its historical 28×24 footprint), where it is
/// IDENTICAL. See the file header's mutation proof: a regression that
/// re-grows the heart inline, or that re-sizes the placeholder slot against
/// anything other than that 28dp footprint, moves this number.
///
/// It was briefly pinned at 214.0 — 4dp narrower — while the slot was sized
/// against the abandoned 32dp "partial inline fix" draft. That pin encoded
/// the regression instead of catching it: the column really had lost 4dp,
/// and this test happily agreed. 218.0 is the width the committed tree
/// actually renders.
const double _kNameWidthWithHeart = 218.0;

/// The same measurement with the heart HIDDEN (no placeholder, no gap) —
/// unaffected by this change at all, kept here so both configurations are
/// pinned side by side.
const double _kNameWidthWithoutHeart = 250.0;

/// Restated (NOT imported — these mirror private constants in
/// `service_catalogue_accordion.dart`/`favorite_heart_button.dart`)
/// derivation of the overlay box's expected RIGHT inset from the tile's own
/// right edge, and its expected extent. Anchoring the boundary probes below
/// on this INDEPENDENTLY-COMPUTED geometry — not the live box's own
/// `GestureDetector` rect — is what makes the boundary probe able to catch
/// an accidental over-expansion of the button's own tap-target constants
/// (`_kFullMinTapExtent`/`_kFullTapPad` in `favorite_heart_button.dart`): a
/// self-referential probe (built FROM the live, possibly-mutated rect)
/// would silently keep "passing" no matter how big that box grew — see the
/// file header's mutation proof and the sibling `_kExpectedBoxWidth` this
/// same idea used in the previous (32×36 inline) version of this file.
///
/// The overlay's `Align(alignment: Alignment.centerRight)` means the box's
/// RIGHT edge is pinned to `tileRight - _kExpectedRightInset` regardless of
/// how wide the box itself grows (only its LEFT edge moves) — so the RIGHT
/// edge is the stable anchor to build the boundary checks from.
///
/// The inset derives from the ICON's historical centre, not the centre of
/// the [_kHeartSlotWidth] placeholder: the heart's committed `Padding` was
/// LEFT-ONLY, so the icon painted flush-right inside its 28dp footprint and
/// those two centres are 2dp apart. See `service_catalogue_accordion.dart`'s
/// `_kHeartOverlayRightInset` doc for the full derivation and for what a
/// slot-centred anchor silently costs.
const double _kTileHorizontalPad = VelvetSpacing.sm + 4;
const double _kHeartSlotWidth = FavoriteHeartButton.iconSize + VelvetSpacing.xs;
const double _kExpectedRightInset =
    _kTileHorizontalPad + _kPaintedIcon / 2 - _kPlatformMinTapExtent / 2;

/// Auth-free favourite toggle — skips the production `build()`'s
/// `ref.watch(authProvider)` so the heart renders with no auth graph.
/// Mirrors `service_selector_sheet_test.dart`'s own private copy (per-file
/// convention: each test file that pumps a favourite heart defines its own).
class _AuthFreeFavoriteToggleNotifier extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}

CatalogueRow _row({
  String id = 'tap-target-row',
  String name = 'Стрижка жіноча',
}) => CatalogueRow(
  id: id,
  name: name,
  categoryLabel: 'HAIR',
  durationLabel: '1 год 30 хв',
  priceLabel: '850 ₴',
);

void main() {
  List<Object> overrides(FakeFavoriteRepository repo) => <Object>[
    favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
    favoriteRepositoryProvider.overrideWithValue(repo),
  ];

  Future<void> pumpTile(
    WidgetTester tester, {
    required FakeFavoriteRepository repo,
    required VoidCallback onToggle,
    double width = _kProbeTileWidth,
    bool showFavoriteHeart = true,
    bool selected = false,
    String name = 'Стрижка жіноча',
  }) async {
    await tester.pumpApp(
      Scaffold(
        body: CatalogueServiceTile(
          row: _row(name: name),
          selected: selected,
          onToggle: onToggle,
          showFavoriteHeart: showFavoriteHeart,
        ),
      ),
      overrides: overrides(repo),
      width: width,
    );
    await tester.pumpAndSettle();
  }

  ({Rect outer, Rect icon}) heartRects(WidgetTester tester) => (
    outer: tester.getRect(
      find.descendant(
        of: find.byType(FavoriteHeartButton),
        matching: find.byType(GestureDetector),
      ),
    ),
    icon: tester.getRect(
      find.descendant(
        of: find.byType(FavoriteHeartButton),
        matching: find.byType(Icon),
      ),
    ),
  );

  group("the heart's hit box is a genuine 48x48", () {
    testWidgets(
      'measures exactly 48x48 (up from 28x24), reaching the platform floor '
      'on both axes, and the painted icon size is unchanged',
      (tester) async {
        final repo = FakeFavoriteRepository();
        await pumpTile(tester, repo: repo, onToggle: () {});

        final (outer: Rect outer, icon: Rect _) = heartRects(tester);

        expect(
          outer.width,
          moreOrLessEquals(_kPlatformMinTapExtent, epsilon: 0.5),
          reason: 'expected the full 48dp box width, got ${outer.width}',
        );
        expect(
          outer.height,
          moreOrLessEquals(_kPlatformMinTapExtent, epsilon: 0.5),
          reason: 'expected the full 48dp box height, got ${outer.height}',
        );

        // The painted icon must be UNCHANGED — this fix grows the invisible
        // margin only, never the icon itself.
        final Icon icon = tester.widget<Icon>(
          find.descendant(
            of: find.byType(FavoriteHeartButton),
            matching: find.byType(Icon),
          ),
        );
        expect(
          icon.size,
          _kPaintedIcon,
          reason: 'the painted icon size must not move',
        );
      },
    );

    Future<void> expectEdgeProbeFiresFavorite(
      WidgetTester tester,
      Offset Function(Rect outer, Rect icon) probeAt,
      String edge,
    ) async {
      final repo = FakeFavoriteRepository();
      await pumpTile(tester, repo: repo, onToggle: () {});

      final (outer: Rect outer, icon: Rect icon) = heartRects(tester);
      final Offset probe = probeAt(outer, icon);

      // Sanity: the probe really is inside the 48x48 box and outside the
      // painted icon, or this proves nothing.
      expect(
        outer.contains(probe),
        isTrue,
        reason: '$edge probe $probe must be inside the box $outer',
      );
      expect(
        icon.contains(probe),
        isFalse,
        reason: '$edge probe $probe must be outside the painted icon $icon',
      );

      await tester.tapAt(probe);
      await tester.pumpAndSettle();

      expect(
        repo.addCalls,
        hasLength(1),
        reason:
            'a tap $edge of the painted icon, inside the 48x48 box, must '
            'still fire the favourite toggle',
      );
    }

    testWidgets('2dp inside the top margin', (tester) async {
      await expectEdgeProbeFiresFavorite(
        tester,
        (outer, icon) => Offset(icon.center.dx, outer.top + 2),
        'above',
      );
    });

    testWidgets('2dp inside the bottom margin', (tester) async {
      await expectEdgeProbeFiresFavorite(
        tester,
        (outer, icon) => Offset(icon.center.dx, outer.bottom - 2),
        'below',
      );
    });

    testWidgets('2dp inside the left margin', (tester) async {
      await expectEdgeProbeFiresFavorite(
        tester,
        (outer, icon) => Offset(outer.left + 2, icon.center.dy),
        'left',
      );
    });

    testWidgets('2dp inside the right margin', (tester) async {
      await expectEdgeProbeFiresFavorite(
        tester,
        (outer, icon) => Offset(outer.right - 2, icon.center.dy),
        'right',
      );
    });
  });

  group('the name column is unchanged', () {
    testWidgets(
      'the name text is constrained to the SAME width as the committed '
      'pre-overlay (28x24 inline) tree, with the heart shown',
      (tester) async {
        final repo = FakeFavoriteRepository();
        await pumpTile(tester, repo: repo, onToggle: () {}, name: _longName);

        final double width = tester
            .getSize(
              find.byKey(const Key('catalogue-service-name-tap-target-row')),
            )
            .width;

        expect(
          width,
          moreOrLessEquals(_kNameWidthWithHeart, epsilon: 0.5),
          reason:
              'the Expanded name/meta column must reserve the EXACT same '
              'width it did before the heart moved into a Stack overlay — '
              'a regression that re-grows the heart INLINE moves this '
              'number (verified by direct measurement against the '
              'pre-overlay tree, see the file header)',
        );
      },
    );

    test('the two pins differ by EXACTLY the reserved slot — the placeholder '
        'plus its leading gap, and nothing more', () {
      // Ties the two measured pins to the layout that produces them, so a
      // future edit cannot quietly move both together and stay green. The
      // heart costs the name column its leading `SizedBox(width: xs)` gap
      // plus the placeholder itself — 4 + 28 = 32dp — and nothing else.
      expect(
        _kNameWidthWithoutHeart - _kNameWidthWithHeart,
        moreOrLessEquals(VelvetSpacing.xs + _kHeartSlotWidth, epsilon: 0.5),
        reason:
            'the name column may lose the reserved slot and its gap, but '
            'not one dp more — if this fails, the placeholder is no longer '
            "sized to the heart's historical 28dp inline footprint",
      );
    });

    testWidgets('unaffected baseline: the name text without the heart at all', (
      tester,
    ) async {
      final repo = FakeFavoriteRepository();
      await pumpTile(
        tester,
        repo: repo,
        onToggle: () {},
        name: _longName,
        showFavoriteHeart: false,
      );

      final double width = tester
          .getSize(
            find.byKey(const Key('catalogue-service-name-tap-target-row')),
          )
          .width;

      expect(
        width,
        moreOrLessEquals(_kNameWidthWithoutHeart, epsilon: 0.5),
        reason:
            'sanity baseline — this configuration never had a heart '
            'to grow, so this number should never move',
      );
    });
  });

  group('the row still selects where users actually tap', () {
    testWidgets('tapping the name, the meta line, and the checkbox all toggle '
        'SERVICE SELECTION, never the favourite', (tester) async {
      final repo = FakeFavoriteRepository();
      var toggleCount = 0;
      await pumpTile(tester, repo: repo, onToggle: () => toggleCount++);

      await tester.tap(
        find.byKey(const Key('catalogue-service-name-tap-target-row')),
      );
      await tester.pumpAndSettle();
      expect(toggleCount, 1, reason: 'tapping the name must select');

      await tester.tap(
        find.byKey(const Key('catalogue-service-meta-tap-target-row')),
      );
      await tester.pumpAndSettle();
      expect(toggleCount, 2, reason: 'tapping the meta line must select');

      await tester.tap(find.byType(CatalogueCheckControl));
      await tester.pumpAndSettle();
      expect(toggleCount, 3, reason: 'tapping the checkbox must select');

      expect(
        repo.addCalls,
        isEmpty,
        reason:
            'none of these taps must have reached the favourite '
            'repository',
      );
    });

    testWidgets(
      "a probe 2dp OUTSIDE the heart's 48x48 box (its LEFT boundary — the "
      'only side with room) still selects the row, not the favourite, and '
      "the box's pinned RIGHT edge lands exactly where derived",
      (tester) async {
        final repo = FakeFavoriteRepository();
        var toggleCount = 0;
        await pumpTile(tester, repo: repo, onToggle: () => toggleCount++);

        // Anchored on the tile's own rect PLUS the independently-restated
        // `_kExpectedRightInset`/`_kPlatformMinTapExtent` — NOT the live
        // heart's own `GestureDetector` rect — see those constants' doc
        // comment for why: a probe built from the live rect is
        // self-referential and would never catch an accidental
        // over-expansion of the button's own tap-target size.
        final Rect tileRect = tester.getRect(find.byType(CatalogueServiceTile));
        final double expectedRight = tileRect.right - _kExpectedRightInset;
        final double expectedLeft = expectedRight - _kPlatformMinTapExtent;
        final double centerY = tileRect.center.dy;

        // The RIGHT side gets a geometric pin rather than a hit probe, and
        // that is not a weakening: correcting the overlay's anchor to the
        // icon's historical centre puts `_kExpectedRightInset` at 0, i.e.
        // the box is FLUSH with the tile's trailing edge — there is no
        // "2dp outside, still on the tile" point left to tap on that side.
        // The pin proves the same thing the probe did (the boundary lands
        // exactly where derived); over-expansion is still caught on the
        // left, which is the only edge that moves — `Align(centerRight)`
        // pins the right edge no matter how wide the box grows, so a
        // right-side hit probe never could have caught it.
        final (outer: Rect outer, icon: Rect _) = heartRects(tester);
        expect(
          outer.right,
          moreOrLessEquals(expectedRight, epsilon: 0.5),
          reason:
              "the box's right edge must sit exactly "
              '$_kExpectedRightInset dp in from the tile’s right edge '
              '(derived from the icon’s historical centre), got '
              '${outer.right} against an expected $expectedRight',
        );

        final Offset justLeft = Offset(expectedLeft - 2, centerY);

        await tester.tapAt(justLeft);
        await tester.pumpAndSettle();
        expect(
          toggleCount,
          1,
          reason: "a probe 2dp left of the heart's box must select the row",
        );

        expect(
          repo.addCalls,
          isEmpty,
          reason:
              'the boundary probe must not have reached the favourite '
              'repository — proves the boundary lands where intended',
        );
      },
    );

    testWidgets(
      'conversely, a tap INSIDE the heart\'s box fires the favourite and '
      'does NOT select the row',
      (tester) async {
        final repo = FakeFavoriteRepository();
        var toggleCount = 0;
        await pumpTile(tester, repo: repo, onToggle: () => toggleCount++);

        await tester.tap(find.byType(FavoriteHeartButton));
        await tester.pumpAndSettle();

        expect(
          repo.addCalls,
          hasLength(1),
          reason: 'tapping the heart must reach the favourite repository',
        );
        expect(
          toggleCount,
          0,
          reason: 'tapping the heart must never also select the row',
        );
      },
    );
  });

  // ---------------------------------------------------------------------
  // The tile is announced ONCE, not twice.
  //
  // mobile-security N1 (LOW): the tile's `Semantics` used to set an explicit
  // `label: bookingServiceTileSemantics(name, duration, price)` AND merge its
  // descendants, so a screen reader heard every field twice — «Стрижка
  // жіноча, 1 год 30 хв, 850 ₴ / Стрижка жіноча / 850 ₴ / 1 год 30 хв»
  // (verified by semantics dump). PRE-EXISTING, and byte-identical with
  // `showFavoriteHeart: false` — the same defect class the two result cards
  // fixed, left standing on the third site. The annotation now carries
  // `button` + `checked` only and lets the merged content speak.
  //
  // Announcement ORDER is now source order (name → price → duration) rather
  // than the dropped label's name → duration → price. Deliberate — see the
  // tile's own comment: restoring the old sequence would mean moving the
  // price BEHIND the duration visually, against the locked design decision.
  //
  // MUTATION PROOF (run during this change, restored after): re-adding
  // `label: l10n.bookingServiceTileSemantics(...)` to the tile's `Semantics`
  // takes every count below from 1 to 2 — all three assertions RED. Removing
  // it again returns them to 1 — GREEN.
  // ---------------------------------------------------------------------
  group('the tile announces each field exactly once', () {
    testWidgets(
      'the tile is ONE node carrying tap + button + checked, and its merged '
      'label states the name, price and duration once each',
      (tester) async {
        final repo = FakeFavoriteRepository();
        await pumpTile(tester, repo: repo, onToggle: () {}, selected: true);

        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pump();

        // Anchored on a node INSIDE the annotated body (the name `Text`), so
        // `getSemantics` resolves to the tile's own merged node rather than
        // walking past it to the route scope — the tile's outermost render
        // object (`AnimatedScale`) carries no semantics of its own.
        final SemanticsNode node = tester.getSemantics(
          find.byKey(const Key('catalogue-service-name-tap-target-row')),
        );

        expect(
          node,
          isSemantics(
            isButton: true,
            hasTapAction: true,
            hasCheckedState: true,
            isChecked: true,
          ),
          reason:
              'dropping the explicit label must not disturb the role or the '
              'selection state — the SAME node must still carry the tap '
              'action, the button role and the checked state',
        );

        final String label = node.getSemanticsData().label;

        // A plain `contains` passes against the stuttered label and catches
        // nothing, which is exactly what shipped. Count, do not contain.
        for (final (String field, String what) in const <(String, String)>[
          ('Стрижка жіноча', 'name'),
          ('850 ₴', 'price'),
          ('1 год 30 хв', 'duration'),
        ]) {
          expect(
            field.allMatches(label).length,
            1,
            reason:
                'the $what must be announced once, not stuttered — got '
                '${field.allMatches(label).length} occurrences of "$field" '
                'in "$label"',
          );
        }

        handle.dispose();
      },
    );

    testWidgets(
      'the same holds with the heart hidden — this was never a heart-induced '
      'defect',
      (tester) async {
        final repo = FakeFavoriteRepository();
        await pumpTile(
          tester,
          repo: repo,
          onToggle: () {},
          showFavoriteHeart: false,
        );

        final SemanticsHandle handle = tester.ensureSemantics();
        await tester.pump();

        final String label = tester
            .getSemantics(
              find.byKey(const Key('catalogue-service-name-tap-target-row')),
            )
            .getSemanticsData()
            .label;

        const String name = 'Стрижка жіноча';
        expect(
          name.allMatches(label).length,
          1,
          reason:
              'the stutter was byte-identical with and without the heart, so '
              'the fix must be too — got '
              '${name.allMatches(label).length} occurrences in "$label"',
        );

        handle.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------
  // THE TILE IS TAPPABLE BY ITS OWN KEY.
  //
  // THE BUG (introduced by `21c4e5c4`, the heart-48dp tap-target change, and
  // merged to `dev` via PR #47): hoisting `AnimatedScale` out of the tile's
  // `GestureDetector` up to the widget's ROOT made the tile's own render
  // object a `RenderTransform`. `RenderTransform.hitTest` deliberately returns
  // `hitTestChildren(...)` WITHOUT adding a `BoxHitTestEntry` for ITSELF, and
  // `WidgetController._getElementPoint` requires exactly that entry in
  // `HitTestResult.path` before it will tap. So
  // `tester.tap(find.byKey(tileKeyForId(row.id)))` — the finder BOTH booking
  // screens' tests use — could not hit the tile at all. Fixed by wrapping the
  // return in a bare `SizedBox` (a `RenderConstrainedBox`, which inherits the
  // default `RenderBox.hitTest` and self-registers once a child is hit); see
  // that widget's "The `SizedBox` is LOAD-BEARING" comment.
  //
  // WHY THIS PIN MUST ARM THE FLAG ITSELF — the detection asymmetry IS the
  // problem. `WidgetController.hitTestWarningShouldBeFatal` defaults to FALSE.
  // The E2E tier arms it (`integration_test/support/e2e_boot_policy.dart:125`)
  // and went hard-red immediately. The widget tier does NOT, so ~30 taps
  // across `service_selector_sheet_test.dart` (`:355`, `:614`, `:736`) and
  // `salon_service_selection_screen_test.dart` merely PRINTED a warning and
  // kept passing — 48 warning lines, zero failures, for the entire time this
  // was broken. A pin written without the flag would reproduce that exact
  // false-pass and prove nothing.
  //
  // The flag is ALSO armed suite-wide now, in `test/flutter_test_config.dart`
  // step (5b) — measured first: the whole `test/` suite is 6209/0 with it on
  // and needs no allow-list. This group keeps its OWN `setUp` anyway, and that
  // is not redundant: this file is the pin for THIS defect and must bite on its
  // own terms, not on a distant config file staying armed. If step (5b) is ever
  // relaxed or narrowed, every other tap in the tier quietly degrades back to a
  // warning — and this group does not.
  //
  // BOTH KEY PREFIXES are pinned even though they resolve to the SAME widget:
  // `salon_service_selection_screen.dart:576` and
  // `service_selector_sheet.dart:577` hand different `tileKeyForId` builders to
  // the shared `CatalogueCategorySection`/`CatalogueServiceTile`. That shared-
  // widget fact is exactly what a future refactor could break on one side only,
  // and the prefixes are restated here as literals (not imported — both
  // builders are private to their screens) on this file's existing
  // "restate the spec, don't import the implementation" convention.
  //
  // BOTH `showFavoriteHeart` VALUES are pinned because they build DIFFERENT
  // subtrees under the same root — `true` inserts a `Stack`, `false` returns
  // `tileBody` directly — and only the shared root was at fault. The salon flow
  // ships `false` today; the master flow ships `true`.
  //
  // MUTATION PROOF (run during this change, reverted byte-for-byte after):
  // deleting the `SizedBox` wrapper from
  // `service_catalogue_accordion.dart`'s `build` (returning the `AnimatedScale`
  // directly, i.e. the shipped-broken tree) turns all four cases RED with
  //   "Finder specifies a widget that would not receive pointer events ...
  //    A different widget CatalogueServiceTile-[<'booking_service_tile_tap-
  //    target-row'>] would receive the pointer events"
  // Restoring the wrapper returns all four to GREEN. The flag is what makes
  // that a failure rather than a console line.
  // ---------------------------------------------------------------------
  group('the tile is tappable by its own key', () {
    late bool previousFatalFlag;

    setUp(() {
      previousFatalFlag = WidgetController.hitTestWarningShouldBeFatal;
      // Restores, for THIS group only, the guard the widget tier never had.
      // Without it `tester.tap` below prints a warning and silently taps
      // nothing — the tap "succeeds", `onToggle` never fires, and the
      // assertion fails with a confusing count instead of naming the cause.
      // With it, an unhittable root fails AT THE TAP, quoting the render
      // object that would have received the pointer instead.
      WidgetController.hitTestWarningShouldBeFatal = true;
    });

    // Restored rather than left armed: the flag is process-global static
    // state, and leaking it into whatever file `flutter test` schedules next
    // under randomized ordering would make an unrelated suite's failure
    // depend on this file having run first.
    tearDown(() {
      WidgetController.hitTestWarningShouldBeFatal = previousFatalFlag;
    });

    /// Pumps ONE row through the real `CatalogueCategorySection`, which is
    /// what actually applies `tileKeyForId` to the tile — pumping
    /// `CatalogueServiceTile` directly and passing a `key:` by hand would
    /// skip the production wiring these two prefixes come from.
    Future<void> pumpSection(
      WidgetTester tester, {
      required FakeFavoriteRepository repo,
      required Key Function(String id) tileKeyForId,
      required VoidCallback onToggle,
      required bool showFavoriteHeart,
    }) async {
      await tester.pumpApp(
        Scaffold(
          body: CatalogueCategorySection(
            category: CatalogueCategoryGroup(
              key: 'cat',
              label: 'HAIR',
              rows: <CatalogueRow>[_row()],
            ),
            expanded: true,
            selectedIdsListenable: ValueNotifier<Set<String>>(<String>{}),
            onToggleExpand: () {},
            onToggleService: (_) => onToggle(),
            headerSemanticsLabel:
                ({
                  required String label,
                  required int count,
                  required int selectedCount,
                  required bool expanded,
                }) => label,
            tileKeyForId: tileKeyForId,
            headerVerticalPadding: 12,
            showFavoriteHeart: showFavoriteHeart,
          ),
        ),
        overrides: overrides(repo),
        width: _kProbeTileWidth,
      );
      await tester.pumpAndSettle();
    }

    // ('<literal prefix>', 'which screen supplies it')
    const List<(String, String)> keyPrefixes = <(String, String)>[
      ('booking_service_tile_', 'service_selector_sheet.dart:577'),
      (
        'salon_booking_service_tile_',
        'salon_service_selection_screen.dart:576',
      ),
    ];

    for (final (String prefix, String origin) in keyPrefixes) {
      for (final bool withHeart in const <bool>[true, false]) {
        testWidgets('a plain tester.tap on Key("$prefix<id>") selects the row '
            '(showFavoriteHeart: $withHeart) — $origin', (tester) async {
          final repo = FakeFavoriteRepository();
          var toggleCount = 0;
          await pumpSection(
            tester,
            repo: repo,
            tileKeyForId: (String id) => Key('$prefix$id'),
            onToggle: () => toggleCount++,
            showFavoriteHeart: withHeart,
          );

          // `_row()`'s default id — the same value the section maps
          // through `tileKeyForId` above.
          final Finder tile = find.byKey(Key('${prefix}tap-target-row'));

          // Sanity: the key really resolves, so a failure below is about
          // HITTABILITY and not a typo'd finder.
          expect(
            tile,
            findsOneWidget,
            reason: 'the section must key its tile with the $origin prefix',
          );

          // No `warnIfMissed: false` and no `tapAt` fallback — a plain
          // `tester.tap` by key is precisely what was impossible, and with
          // the fatal flag armed it now throws rather than warns.
          await tester.tap(tile);
          await tester.pumpAndSettle();

          expect(
            toggleCount,
            1,
            reason:
                'tapping the tile by its own key must reach the row '
                "selection gesture — with `AnimatedScale` at the widget's "
                'root the tile never appeared in the hit-test path at all',
          );
          expect(
            repo.addCalls,
            isEmpty,
            reason:
                "the tile's centre is nowhere near the heart's 48x48 box at "
                'the trailing edge — this tap must not have favourited',
          );
        });
      }
    }

    // Guards the guard: if a future edit drops the `setUp` above (or Flutter
    // changes the flag's default), every case in this group silently degrades
    // back into a warning-only smoke test. This states the precondition as an
    // assertion so that regression is loud.
    testWidgets('the fatal-hit-test flag really is armed for this group', (
      tester,
    ) async {
      expect(
        WidgetController.hitTestWarningShouldBeFatal,
        isTrue,
        reason:
            'without this flag a tap on an unhittable widget prints a console '
            'warning and taps NOTHING — the exact false-pass mode that let '
            'this bug through ~30 widget-tier taps',
      );
    });
  });

  group('onError is still forwarded through the (now full 48x48) hit box', () {
    testWidgets('a failing toggle surfaces the Failure via onError', (
      tester,
    ) async {
      final repo = FakeFavoriteRepository()..addResult = const NetworkFailure();
      Failure? captured;

      await tester.pumpApp(
        Scaffold(
          body: CatalogueCategorySection(
            category: CatalogueCategoryGroup(
              key: 'cat',
              label: 'HAIR',
              rows: <CatalogueRow>[_row()],
            ),
            expanded: true,
            selectedIdsListenable: ValueNotifier<Set<String>>(<String>{}),
            onToggleExpand: () {},
            onToggleService: (_) {},
            headerSemanticsLabel:
                ({
                  required String label,
                  required int count,
                  required int selectedCount,
                  required bool expanded,
                }) => label,
            tileKeyForId: (String id) => Key('tile-$id'),
            headerVerticalPadding: 12,
            showFavoriteHeart: true,
            onFavoriteError: (Failure f) => captured = f,
          ),
        ),
        overrides: overrides(repo),
        width: _kProbeTileWidth,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FavoriteHeartButton));
      await tester.pumpAndSettle();

      expect(
        captured,
        isA<NetworkFailure>(),
        reason: 'the full 48x48 hit box must still forward toggle failures',
      );
    });
  });
}
