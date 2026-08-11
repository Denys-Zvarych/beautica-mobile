// Tap-target guard for `FavoriteHeartButton`
// (`lib/features/discovery/presentation/widgets/favorite_heart_button.dart`)
// as embedded in its `SalonResultCard` caller
// (`lib/features/discovery/presentation/widgets/salon_result_card.dart`)
// through the shared `FavoriteHeartOverlay`
// (`lib/features/discovery/presentation/widgets/favorite_heart_overlay.dart`).
//
// Sibling of `master_result_card_favorite_heart_tap_target_test.dart` — see
// that file's header for the full defect history (28×24 sub-floor hit box,
// the abandoned 32×36 inline draft, the icon-centre vs slot-centre 2dp drift,
// and the `centerRight` draft that dropped the heart to mid-card height).
//
// This file is NOT redundant with the master's. The two cards share the
// overlay but NOT their content: the salon card omits the ★ rating row
// entirely (the salon DTO carries no rating), renders a different price
// branch, and keys its own body `GestureDetector` — so its card rect, its
// natural height and its `Expanded` column all differ. A regression that
// happened to leave the master card's arithmetic intact while breaking the
// salon's (a per-caller `containerPad`, a per-caller `Row` alignment) would
// pass over there and fail here. Both sites are shipped; both are pinned.
//
// WHAT THIS FILE PROVES — identical five groups, salon fixtures:
//   1. a genuine 48×48 box, unchanged 24dp painted icon, all four edges
//      firing EXACTLY ONE favourite repository call;
//   2. both derived insets (trailing + top) land at 4.0dp off the card's rect;
//   3. a probe 3dp outside the box's DERIVED leading boundary navigates to the
//      public salon profile and makes ZERO favourite calls;
//   4. the `Expanded` name column pays exactly `FavoriteHeartOverlay.
//      slotWidth` and no more;
//   5. RTL flips the box to the card's leading edge at the same inset.
//
// NOT DUPLICATED HERE: the semantics-node pin (`isSemantics(isButton: true,
// hasTapAction: true)` on the SAME node, name announced exactly once) already
// lives in `salon_result_card_test.dart`. Verified present and correct while
// writing this file.
//
// HARNESS NOTE — the repository override is load-bearing. `salon_result_card_
// test.dart` overrides only `favoriteToggleProvider`, so a toggle there is
// unobservable. Every test here also overrides `favoriteRepositoryProvider`,
// which is what makes "the heart fired" a countable fact. The card is pumped
// inside a `ListView` (the shape `search_results_screen.dart` renders it in)
// so the `NeumorphicCard` has its NATURAL height — under a bare
// `Scaffold(body: card)` it stretches to the full 2400dp stress viewport and
// the `box.top - card.top` pin would pass for the wrong reason.
//
// MUTATION PROOFS — every group below was shown to FAIL on a deliberately
// broken tree and pass again on the restored one, on BOTH cards
// simultaneously (production restored byte-for-byte after each; `diff -q`
// clean; 14/14 green). Measured values, salon side:
//
//   A. FULL REVERT to the committed pre-fix tree (heart INLINE with its
//      historical `EdgeInsets.only(left: xs)` pad, card returning `cardBody`
//      bare): group 1 RED (`Expected: 48.0 / Actual: <28.0>`), group 1 edge
//      probes RED (the icon-containment sanity gate fires,
//      `Expected: false / Actual: <true>`), group 2 RED (`4.0` vs `<16.0>`),
//      group 5 RED (`4.0` vs `<16.0>`). Group 4 stays GREEN under A and
//      SHOULD: the pre-fix inline heart occupied exactly the 28dp the
//      placeholder now reserves, which is the invariance the fix claims.
//
//   B. ANCHOR ON THE PLACEHOLDER SLOT'S CENTRE instead of the icon's
//      historical centre — the 2dp drift this change shipped once: groups 2
//      and 5 RED, `Expected: 4.0 (±0.5) / Actual: <6.0>`.
//
//   C. WIDEN the button's hit extent 48 → 64: group 3 RED — the DERIVED probe
//      `Offset(305.0, 36.0)` now lands inside the over-expanded box
//      `Rect.fromLTRB(292.0, 4.0, 356.0, 68.0)`, tripping the "must be
//      OUTSIDE" sanity gate. A probe built from the LIVE box could not have
//      caught this. Groups 1 and 5 RED too (`<64.0>`) — expected collateral.
//
//   D. SIZE THE PLACEHOLDER against the abandoned 32dp draft: group 4 RED —
//      slot-cost delta `Expected: 28.0 (±0.5) / Actual: <32.0>` plus the
//      `FavoriteHeartOverlay.slotWidth` cross-check. The delta assertion is
//      deliberately ordered BEFORE the absolute 172.0 pin, because the delta
//      is the load-bearing half: an absolute number alone can be re-baselined
//      onto a regression (exactly how the tile's earlier 214.0 pin agreed
//      with the bug instead of catching it).

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/favorite_heart_button.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/favorite_heart_overlay.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/salon_result_card.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository_provider.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/fakes/fake_favorite_repository.dart';
import '../../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Restated constants — deliberately NOT imported from the widgets under test.
// Importing the overlay's own `_hitExtent` (or the button's
// `_kFullMinTapExtent`) would make every assertion self-referential: a
// mutation shrinking box and constant together would still "pass". See the
// master sibling's header for the three self-referential tests this suite has
// already been bitten by.
// ---------------------------------------------------------------------------

/// Android's 48dp / iOS's 44pt tap-target floor (WCAG 2.5.5, Material, HIG).
const double _kPlatformMinTapExtent = 48;

/// The heart's documented painted icon size — the "did NOT change" assertion.
const double _kPaintedIcon = 24;

/// The card's own `NeumorphicCard(padding: EdgeInsets.all(...))`.
const double _kContainerPad = VelvetSpacing.md;

/// Where the overlay's 48×48 box must sit on BOTH axes, measured in from the
/// card's top/trailing edge:
///
///   inset = containerPad + iconSize / 2 - hitExtent / 2 = 16 + 12 - 24 = 4.0
///
/// [FavoriteHeartOverlay.slotWidth] is deliberately absent — the box centres
/// on where the ICON historically painted, not on the 28dp placeholder that
/// replaced it. Those two points are 2dp apart (the committed `Padding` was
/// LEFT-only, so the icon painted flush-trailing inside its footprint).
const double _kExpectedInset =
    _kContainerPad + _kPaintedIcon / 2 - _kPlatformMinTapExtent / 2;

/// The inline placeholder width the card's `Row` reserves — the heart's
/// HISTORICAL inline footprint (24dp icon + LEFT-only 4dp pad).
const double _kSlotWidth = _kPaintedIcon + VelvetSpacing.xs;

/// The width every geometric pin is taken at.
const double _kProbeWidth = 360;

/// The narrower width the name-column pin is taken at.
const double _kNameProbeWidth = 320;

/// A salon name long enough that its `Text` CLAMPS to the `Expanded` column's
/// constraint (ellipsis engages) rather than reporting its intrinsic width —
/// group 4 must observe the CONSTRAINT, not the string.
const String _kLongName =
    'Студія Краси «Камелія» на Печерську — манікюр, педикюр та догляд';

/// The name `Text`'s measured width at [_kNameProbeWidth] with the overlay's
/// placeholder slot reserved.
///
/// Identical to the committed pre-overlay tree by construction: the content
/// box is `320 - 2*16 = 288`, less the 72dp thumbnail and its 16dp gap = 200,
/// less the reserved slot. The committed tree spent exactly the same 28dp on
/// the INLINE heart, so both trees leave the column 172dp. Group 4 also
/// asserts the delta from the slot-free 200dp, so a slot re-sized against the
/// abandoned 32dp draft moves this number AND breaks the delta.
const double _kNameWidthWithSlot = 172.0;

/// Auth-free favourite toggle — skips the production `build()`'s
/// `ref.watch(authProvider)` so the heart renders with no auth graph.
class _AuthFreeFavoriteToggleNotifier extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}

SalonSearchItem _salon({String name = 'Студія «Камелія»'}) => SalonSearchItem(
  salonId: 'salon-1',
  name: name,
  avatarUrl: null,
  avgRating: null,
  cityLabel: 'Київ',
  districtLabel: 'Печерський',
  priceMin: 300,
  priceMax: 1200,
  street: null,
  buildingNo: null,
  locationNote: null,
  serviceNames: const <String>[],
);

void main() {
  List<Object> overrides(FakeFavoriteRepository repo) => <Object>[
    favoriteToggleProvider.overrideWith(_AuthFreeFavoriteToggleNotifier.new),
    // LOAD-BEARING: without this the toggle's repository call is unobservable
    // and every "the heart fired" assertion below would be vacuous.
    favoriteRepositoryProvider.overrideWithValue(repo),
  ];

  Future<void> pumpCard(
    WidgetTester tester, {
    required FakeFavoriteRepository repo,
    double width = _kProbeWidth,
    TextDirection textDirection = TextDirection.ltr,
    SalonSearchItem? salon,
  }) async {
    await tester.pumpApp(
      Scaffold(
        body: Directionality(
          textDirection: textDirection,
          child: ListView(
            children: <Widget>[SalonResultCard(salon: salon ?? _salon())],
          ),
        ),
      ),
      overrides: overrides(repo),
      width: width,
    );
    await tester.pumpAndSettle();
  }

  ({Rect card, Rect box, Rect icon}) rects(WidgetTester tester) => (
    card: tester.getRect(find.byType(NeumorphicCard)),
    box: tester.getRect(
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

  // =========================================================================
  // 1. A genuine 48×48 box, unchanged 24dp icon, hittable on all four edges.
  // =========================================================================
  group("the heart's hit box is a genuine 48x48", () {
    testWidgets(
      'measures exactly 48x48 (up from 28x24) on BOTH axes, and the painted '
      'icon size is unchanged at 24dp',
      (tester) async {
        final repo = FakeFavoriteRepository();
        await pumpCard(tester, repo: repo);

        final Rect box = rects(tester).box;

        expect(
          box.width,
          moreOrLessEquals(_kPlatformMinTapExtent, epsilon: 0.5),
          reason: 'expected the full 48dp box width, got ${box.width}',
        );
        expect(
          box.height,
          moreOrLessEquals(_kPlatformMinTapExtent, epsilon: 0.5),
          reason: 'expected the full 48dp box height, got ${box.height}',
        );

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

    testWidgets(
      'all FOUR edges of the box fire the favourite — 2dp inside each edge, '
      'outside the painted icon',
      (tester) async {
        final repo = FakeFavoriteRepository();
        await pumpCard(tester, repo: repo);

        // Four probes in ONE test, cleared between, so the ALTERNATING toggle
        // is genuinely exercised: probe 1 adds, probe 2 removes, probe 3 adds,
        // probe 4 removes. Asserting `addCalls` alone would pass for the wrong
        // reason on the even probes.
        for (final (String edge, Offset Function(Rect, Rect) at)
            in <(String, Offset Function(Rect, Rect))>[
              ('top', (Rect b, Rect _) => Offset(b.center.dx, b.top + 2)),
              ('bottom', (Rect b, Rect _) => Offset(b.center.dx, b.bottom - 2)),
              ('left', (Rect b, Rect _) => Offset(b.left + 2, b.center.dy)),
              ('right', (Rect b, Rect _) => Offset(b.right - 2, b.center.dy)),
            ]) {
          // Re-measured per probe: the heart's `AnimatedScale` runs 0.92 ↔ 1.0
          // across a toggle, so the ICON's rect really does change between
          // probes even though the box does not.
          final (card: Rect _, box: Rect box, icon: Rect icon) = rects(tester);
          final Offset probe = at(box, icon);

          // Sanity gate — without these two the probe proves nothing: outside
          // the box it would be testing the card, and on the painted icon it
          // would pass on the PRE-FIX 28×24 tree.
          expect(
            box.contains(probe),
            isTrue,
            reason: '$edge probe $probe must be inside the box $box',
          );
          expect(
            icon.contains(probe),
            isFalse,
            reason: '$edge probe $probe must be outside the painted icon $icon',
          );

          repo.addCalls.clear();
          repo.removeCalls.clear();

          await tester.tapAt(probe);
          await tester.pumpAndSettle();

          expect(
            repo.addCalls.length + repo.removeCalls.length,
            1,
            reason:
                'a tap $edge of the painted icon but inside the 48x48 box '
                'must reach the favourite repository exactly once (add '
                '${repo.addCalls.length} + remove ${repo.removeCalls.length})',
          );
        }
      },
    );
  });

  // =========================================================================
  // 2. The box lands exactly where the derivation says — on BOTH axes.
  // =========================================================================
  group('the box lands exactly where the geometry derives', () {
    testWidgets('the trailing inset AND the top inset each equal the restated '
        'containerPad + iconSize/2 - hitExtent/2', (tester) async {
      final repo = FakeFavoriteRepository();
      await pumpCard(tester, repo: repo);

      final (card: Rect card, box: Rect box, icon: Rect _) = rects(tester);

      expect(
        card.right - box.right,
        moreOrLessEquals(_kExpectedInset, epsilon: 0.5),
        reason:
            'the box must sit $_kExpectedInset dp in from the card\'s '
            'trailing edge (derived from the ICON\'s historical centre, not '
            'the placeholder slot\'s) — got ${card.right - box.right}',
      );
      expect(
        box.top - card.top,
        moreOrLessEquals(_kExpectedInset, epsilon: 0.5),
        reason:
            'this card\'s Row is CrossAxisAlignment.start, so the heart was '
            'TOP-aligned, not centred — the overlay must anchor topEnd with '
            'the same derived inset; got ${box.top - card.top}',
      );
    });
  });

  // =========================================================================
  // 3. No tap hijacking — the card still navigates outside the box.
  // =========================================================================
  group('the card still navigates where users actually tap', () {
    testWidgets(
      'a probe 3dp OUTSIDE the box\'s DERIVED leading boundary pushes the '
      'salon profile and makes ZERO favourite calls',
      (tester) async {
        final repo = FakeFavoriteRepository();

        tester.view.physicalSize = const Size(_kProbeWidth, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // The pushed URI is captured in the destination's own builder rather
        // than read off `router.routerDelegate.currentConfiguration`: an
        // IMPERATIVE `context.push` leaves that reporting the PARENT location
        // (measured: '/' while the stub screen is genuinely on screen) — the
        // known go_router imperative-match quirk. `state.uri` in the builder
        // is the location that actually matched.
        String? pushedLocation;
        final GoRouter router = GoRouter(
          initialLocation: '/',
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext context, GoRouterState state) => Scaffold(
                body: ListView(
                  children: <Widget>[SalonResultCard(salon: _salon())],
                ),
              ),
            ),
            GoRoute(
              path: '/salons/:id',
              builder: (BuildContext context, GoRouterState state) {
                pushedLocation = state.uri.toString();
                return const Scaffold(
                  body: SizedBox.shrink(key: Key('stub_salon_profile')),
                );
              },
            ),
          ],
        );

        await tester.pumpRoutedApp(router, overrides: overrides(repo));
        await tester.pumpAndSettle();

        final (card: Rect card, box: Rect box, icon: Rect _) = rects(tester);

        // DERIVED, NOT MEASURED. `AlignmentDirectional.topEnd` pins the box's
        // TRAILING edge however wide the box grows, so only its LEADING edge
        // moves — a probe computed from the LIVE box's left edge would move
        // with it and never catch an over-expansion. Anchoring on the card's
        // rect plus the restated constants is what makes the "hit extent
        // widened to 64" mutation go red.
        final double expectedLeft =
            card.right - _kExpectedInset - _kPlatformMinTapExtent;
        final Offset probe = Offset(expectedLeft - 3, box.center.dy);

        expect(
          box.contains(probe),
          isFalse,
          reason:
              'sanity: the probe $probe must be OUTSIDE the measured box $box '
              '— if the shipped box already swallows it, this test proves '
              'nothing',
        );

        await tester.tapAt(probe);
        await tester.pumpAndSettle();

        expect(
          repo.addCalls.length + repo.removeCalls.length,
          0,
          reason:
              'a tap outside the heart\'s box must not reach the favourite '
              'repository — the overlay must not hijack the card body',
        );
        expect(
          find.byKey(const Key('stub_salon_profile')),
          findsOneWidget,
          reason: 'the same tap must have opened the public salon profile',
        );
        expect(
          pushedLocation,
          RouteNames.salonPublicProfile('salon-1'),
          reason: 'the pushed location must be the salon profile route',
        );
      },
    );
  });

  // =========================================================================
  // 4. The `Expanded` name column pays EXACTLY the reserved slot, no more.
  // =========================================================================
  group('the name column is unchanged', () {
    testWidgets('the name Text is constrained to the same width the committed '
        'pre-overlay (28x24 inline) tree gave it', (tester) async {
      final repo = FakeFavoriteRepository();
      await pumpCard(
        tester,
        repo: repo,
        width: _kNameProbeWidth,
        salon: _salon(name: _kLongName),
      );

      final Rect card = tester.getRect(find.byType(NeumorphicCard));
      final Rect name = tester.getRect(
        find.byKey(const Key('salon_card_name')),
      );

      // The genuine "with heart vs without heart" DELTA. The card exposes no
      // heart-less mode, so the slot-free width is reconstructed from the
      // live tree's OTHER geometry — the card's trailing edge, its restated
      // padding, and the name column's LEFT edge (set by the thumbnail +
      // gap, entirely independent of the heart). The difference is, by
      // definition, whatever the trailing placeholder cost.
      final double widthWithoutSlot = card.right - _kContainerPad - name.left;
      expect(
        widthWithoutSlot - name.width,
        moreOrLessEquals(_kSlotWidth, epsilon: 0.5),
        reason:
            'the name column may lose the reserved slot and nothing more — '
            'a slot sized against the abandoned 32dp draft costs it 4dp '
            'extra; got ${widthWithoutSlot - name.width}',
      );

      expect(
        name.width,
        moreOrLessEquals(_kNameWidthWithSlot, epsilon: 0.5),
        reason:
            'the Expanded name column must reserve the EXACT width it did '
            'before the heart moved into a Stack overlay — got ${name.width}',
      );
    });

    test('the shared overlay still reserves the historical 28dp footprint', () {
      // The one place `FavoriteHeartOverlay.slotWidth` is touched — as the
      // SUBJECT of an assertion against the restated [_kSlotWidth], never as
      // the source the pins above are built from.
      expect(
        FavoriteHeartOverlay.slotWidth,
        moreOrLessEquals(_kSlotWidth, epsilon: 0.01),
        reason:
            'the placeholder must stay sized to the heart\'s COMMITTED inline '
            'footprint (24dp icon + 4dp left-only pad), not the abandoned '
            '32dp "partial inline fix" draft',
      );
    });
  });

  // =========================================================================
  // 5. RTL — the overlay is direction-aware. Previously unpinned.
  // =========================================================================
  group('the overlay is direction-aware (RTL)', () {
    testWidgets(
      'under TextDirection.rtl the box flips to the card\'s LEADING (visually '
      'left) edge at the same derived inset, still 48x48',
      (tester) async {
        final repo = FakeFavoriteRepository();
        await pumpCard(tester, repo: repo, textDirection: TextDirection.rtl);

        final (card: Rect card, box: Rect box, icon: Rect _) = rects(tester);

        expect(
          box.left - card.left,
          moreOrLessEquals(_kExpectedInset, epsilon: 0.5),
          reason:
              'a Row reverses its children under RTL, so the placeholder slot '
              'moves to the visual LEFT. A hard-coded Alignment.topRight '
              'would leave the box pinned to the visual right — overlay and '
              'slot on opposite sides of the card. Got ${box.left - card.left}',
        );
        expect(
          box.top - card.top,
          moreOrLessEquals(_kExpectedInset, epsilon: 0.5),
          reason: 'the vertical anchor is direction-independent',
        );
        expect(
          box.width,
          moreOrLessEquals(_kPlatformMinTapExtent, epsilon: 0.5),
        );
        expect(
          box.height,
          moreOrLessEquals(_kPlatformMinTapExtent, epsilon: 0.5),
        );
      },
    );
  });
}
