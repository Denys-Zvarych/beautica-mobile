// Tap-target guard for `FavoriteHeartButton`
// (`lib/features/discovery/presentation/widgets/favorite_heart_button.dart`)
// as embedded in its `MasterResultCard` caller
// (`lib/features/discovery/presentation/widgets/master_result_card.dart`)
// through the shared `FavoriteHeartOverlay`
// (`lib/features/discovery/presentation/widgets/favorite_heart_overlay.dart`).
//
// mobile-security finding (MEDIUM), FOLLOW-UP: the heart's hit area was its
// painted 24dp icon plus a left-only `VelvetSpacing.xs` `Padding` — 28×24dp,
// asymmetric and below the Android 48dp / iOS 44pt floor (WCAG 2.5.5 /
// Material / HIG). All THREE call sites were fixed by the same overlay
// technique, but only `CatalogueServiceTile` was pinned by a regression test
// (`test/features/booking/presentation/widgets/
// catalogue_service_tile_favorite_heart_tap_target_test.dart`). This file and
// its `salon_result_card_favorite_heart_tap_target_test.dart` sibling close
// the two unpinned sites.
//
// WHY THE RESULT CARDS NEED THEIR OWN FILE (not "same as the tile")
// -----------------------------------------------------------------
// The tile's `Row` has no explicit `crossAxisAlignment` (defaults to `center`)
// and the tile's own padding is `VelvetSpacing.sm + 4`; both result cards use
// `CrossAxisAlignment.start` inside a `NeumorphicCard(padding:
// EdgeInsets.all(VelvetSpacing.md))`. So the overlay anchors `topEnd` here,
// not `centerEnd`, and BOTH axes carry a derived inset — the vertical one is
// load-bearing on these cards and simply absent on the tile. An early draft of
// `FavoriteHeartOverlay` copied the tile's `centerRight` verbatim and dropped
// the heart to mid-card height; nothing in the tile's own test could have
// caught that, and no widget test caught it either (only the golden suite
// did). Group 2 below is the widget-tier pin that now would.
//
// WHAT THIS FILE PROVES
// ----------------------
//   1. `group('the heart's hit box is a genuine 48x48')` — the box measures
//      48×48 (not merely "grew"), the painted icon is UNCHANGED at 24dp, and
//      four fresh probes (one per edge, 2dp inside the box, outside the
//      painted icon) each fire EXACTLY ONE favourite repository call.
//   2. `group('the box lands exactly where the geometry derives')` — both
//      insets from the card's own rect (`card.right - box.right` and
//      `box.top - card.top`) equal the INDEPENDENTLY RESTATED derivation
//      `containerPad + iconSize / 2 - hitExtent / 2` = 4.0dp. This is the pin
//      that catches the 2dp slot-centre-vs-icon-centre drift that already bit
//      this change once (see `favorite_heart_overlay.dart`'s `build()`), and
//      the vertical half catches the `centerRight` draft described above.
//   3. `group('the card still navigates where users actually tap')` — a probe
//      3dp OUTSIDE the box's DERIVED left boundary (derived from the restated
//      constants, NOT from the measured box — see [_kExpectedInset]'s doc)
//      pushes the master profile and makes ZERO favourite repository calls.
//   4. `group('the name column is unchanged')` — the `Expanded` name column
//      loses EXACTLY `FavoriteHeartOverlay.slotWidth` to the reserved
//      placeholder and not one dp more.
//   5. `group('the overlay is direction-aware (RTL)')` — under
//      `TextDirection.rtl` the box flips to the card's LEADING (visually
//      left) edge at the same 4.0dp inset and the same 48×48, proving the
//      `AlignmentDirectional`/`EdgeInsetsDirectional` pair actually does
//      something. Previously unpinned by any test.
//
// NOT DUPLICATED HERE: the semantics-node pin (`isSemantics(isButton: true,
// hasTapAction: true)` on the SAME node as the merged label, name announced
// exactly once) already lives in `master_result_card_test.dart`'s
// `'MasterResultCard navigation (Phase 13.5)'` group. Verified present and
// correct while writing this file; re-asserting it here would be redundant.
//
// HARNESS NOTE — the repository override is load-bearing.
// ------------------------------------------------------
// `master_result_card_test.dart` overrides only `favoriteToggleProvider`, so
// a favourite toggle in that file mutates notifier state and is otherwise
// UNOBSERVABLE. Every test here also overrides `favoriteRepositoryProvider`
// with `FakeFavoriteRepository`, which is what turns "did the heart fire?"
// into a countable fact.
//
// The card is pumped inside a `ListView` — the shape `search_results_screen.
// dart` actually renders it in — so the `NeumorphicCard` has its NATURAL
// height. Under a bare `Scaffold(body: card)` the card stretches to the full
// 2400dp stress viewport, which would make `box.top - card.top` accidentally
// correct for the wrong reason (any top-anchored box passes when the card's
// top is the viewport's top).
//
// MUTATION PROOFS — every group below was shown to FAIL on a deliberately
// broken tree and pass again on the restored one (production restored
// byte-for-byte after each; `diff -q` clean; 14/14 green). Measured values:
//
//   A. FULL REVERT to the committed pre-fix tree — the heart back INLINE as
//      the `Row`'s last child with its historical `EdgeInsets.only(left: xs)`
//      pad, and the cards returning `cardBody` bare instead of wrapping it in
//      `FavoriteHeartOverlay`:
//        · group 1 RED — box width `Expected: 48.0 (±0.5) / Actual: <28.0>`;
//        · group 1 edge probes RED — the top probe now lands ON the painted
//          icon, so the `icon.contains(probe)` sanity gate fires
//          (`Expected: false / Actual: <true>`);
//        · group 2 RED — trailing inset `Expected: 4.0 / Actual: <16.0>`;
//        · group 5 (RTL) RED — leading inset `Expected: 4.0 / Actual: <16.0>`.
//      Group 4 stays GREEN under A, CORRECTLY: the pre-fix inline heart
//      occupied exactly the 28dp the placeholder now reserves, so the name
//      column is byte-identical in both trees. That invariance IS the fix's
//      claim; group 4 has its own mutation below.
//
//   B. ANCHOR ON THE PLACEHOLDER SLOT'S CENTRE instead of the icon's
//      historical centre (`containerPad + slotWidth / 2 - hitExtent / 2`) —
//      the exact 2dp drift this change shipped once:
//        · group 2 RED, both axes — `Expected: 4.0 (±0.5) / Actual: <6.0>`;
//        · group 5 (RTL) RED — same 6.0.
//
//   C. WIDEN the button's hit extent 48 → 64:
//        · group 3 RED — the derived probe `Offset(305.0, 36.0)` now falls
//          INSIDE the over-expanded box `Rect.fromLTRB(292.0, 4.0, 356.0,
//          68.0)`, so the "must be OUTSIDE" sanity gate fires
//          (`Expected: false / Actual: <true>`). A probe built from the LIVE
//          box instead of the restated constants could not have caught this.
//        · groups 1 and 5 RED too (`Actual: <64.0>`) — expected collateral.
//
//   D. SIZE THE PLACEHOLDER against the abandoned 32dp draft
//      (`slotWidth = iconSize + VelvetSpacing.sm`):
//        · group 4 RED — the slot-cost delta `Expected: 28.0 (±0.5) / Actual:
//          <32.0>`, and the `FavoriteHeartOverlay.slotWidth` cross-check RED.
//          (The delta assertion is deliberately ordered BEFORE the absolute
//          172.0 pin so this is the failure that surfaces: the delta is the
//          load-bearing half — the absolute number alone could be re-baselined
//          onto a regression, which is exactly how the tile's earlier 214.0
//          pin agreed with the bug instead of catching it.)

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/favorite_heart_button.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/favorite_heart_overlay.dart';
import 'package:beautica_mobile/features/discovery/presentation/widgets/master_result_card.dart';
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
//
// Importing `FavoriteHeartOverlay._hitExtent` (or `FavoriteHeartButton`'s
// `_kFullMinTapExtent`) would make every assertion below self-referential: a
// mutation that shrinks the box AND the constant together would still "pass",
// which is precisely the failure mode this suite has been bitten by three
// times this session (a contrast test mirroring its own constant, a width
// probe measuring the test surface, and a `button` flag that stayed `true`
// through a real regression).
//
// The ONE exception is [FavoriteHeartOverlay.slotWidth] in group 4, which is
// asserted AGAINST an independently restated [_kSlotWidth] rather than used as
// the source of truth — see that group.
// ---------------------------------------------------------------------------

/// Android's 48dp / iOS's 44pt tap-target floor (WCAG 2.5.5, Material, HIG).
const double _kPlatformMinTapExtent = 48;

/// The heart's documented painted icon size — the "did NOT change" assertion.
const double _kPaintedIcon = 24;

/// The card's own `NeumorphicCard(padding: EdgeInsets.all(...))`, equal on all
/// four sides — the shape `FavoriteHeartOverlay` requires of its callers.
const double _kContainerPad = VelvetSpacing.md;

/// Where the overlay's 48×48 box must sit, on BOTH axes, measured in from the
/// card's own top/trailing edge.
///
/// The icon HISTORICALLY painted flush to the content box's top-trailing
/// corner (its committed `Padding` was `EdgeInsets.only(left: xs)` — no top
/// pad at all, and the `Row` pinned its trailing edge), so its centre sat
/// `containerPad + iconSize / 2` in from that corner on each axis. The box is
/// [_kPlatformMinTapExtent] on each axis, so its own edge sits half an extent
/// closer to the corner than its centre:
///
///   inset = containerPad + iconSize / 2 - hitExtent / 2 = 16 + 12 - 24 = 4.0
///
/// [FavoriteHeartOverlay.slotWidth] is deliberately ABSENT from this formula.
/// Centring on the 28dp placeholder slot instead of the 24dp icon drags the
/// painted heart 2dp off where it shipped — a drift invisible to any
/// assertion built from the live box, and one this change already shipped
/// once (caught only as an 88-pixel golden diff).
const double _kExpectedInset =
    _kContainerPad + _kPaintedIcon / 2 - _kPlatformMinTapExtent / 2;

/// The inline placeholder width the card's `Row` reserves — the heart's
/// HISTORICAL inline footprint (24dp icon + a LEFT-only 4dp pad). Restated so
/// group 4 can assert `FavoriteHeartOverlay.slotWidth` still equals it.
const double _kSlotWidth = _kPaintedIcon + VelvetSpacing.xs;

/// The width every geometric pin is taken at.
const double _kProbeWidth = 360;

/// The narrower width the name-column pin is taken at (the tightest phone the
/// discovery goldens capture).
const double _kNameProbeWidth = 320;

/// A name long enough that its `Text` CLAMPS to the `Expanded` column's
/// available constraint (ellipsis engages) rather than reporting its own
/// intrinsic width — group 4 needs to observe the CONSTRAINT, not the string.
const String _kLongFirstName = 'Олександра-Мирослава';
const String _kLongLastName = 'Зварич-Пономаренко-Вишневецька Костянтинівна';

/// The name `Text`'s measured width at [_kNameProbeWidth] with the overlay's
/// placeholder slot reserved.
///
/// Verified to be IDENTICAL to the committed pre-overlay tree by construction,
/// not by assertion alone: the content box is `320 - 2*16 = 288`, less the
/// 72dp thumbnail and its 16dp gap = 200, less the reserved slot. The
/// committed tree spent exactly the same 28dp on the INLINE heart (24dp icon +
/// 4dp left pad), so both trees leave the column 172dp. Group 4 asserts the
/// delta from the slot-free 200dp as well, so a slot re-sized against the
/// abandoned 32dp draft moves this number AND breaks the delta.
const double _kNameWidthWithSlot = 172.0;

/// Auth-free favourite toggle — skips the production `build()`'s
/// `ref.watch(authProvider)` so the heart renders with no auth graph. Mirrors
/// the private copy in `master_result_card_test.dart` (per-file convention).
class _AuthFreeFavoriteToggleNotifier extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}

MasterSearchItem _master({
  String firstName = 'Олена',
  String lastName = 'Коваль',
}) => MasterSearchItem(
  masterId: 'master-1',
  firstName: firstName,
  lastName: lastName,
  avatarUrl: null,
  avgRating: 4.8,
  reviewCount: 12,
  cityLabel: 'Київ',
  districtLabel: 'Печерський',
  minEffectivePrice: 500,
  priceMax: null,
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

  /// Pumps the card in the `ListView` shape `search_results_screen.dart` uses,
  /// so the `NeumorphicCard` gets its NATURAL height (see the file header).
  Future<void> pumpCard(
    WidgetTester tester, {
    required FakeFavoriteRepository repo,
    double width = _kProbeWidth,
    TextDirection textDirection = TextDirection.ltr,
    MasterSearchItem? master,
  }) async {
    await tester.pumpApp(
      Scaffold(
        body: Directionality(
          textDirection: textDirection,
          child: ListView(
            children: <Widget>[MasterResultCard(master: master ?? _master())],
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
  // 1. A genuine 48×48 box, with an unchanged 24dp painted icon, hittable on
  //    all four edges.
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

        // The painted icon must be UNCHANGED — this fix grows the invisible
        // margin only, never the glyph.
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

        // One test, four probes, cleared between — so the ALTERNATING toggle
        // is genuinely exercised. Probe 1 adds, probe 2 removes, probe 3 adds,
        // probe 4 removes: asserting `addCalls` alone would pass for the wrong
        // reason on the even probes (a length of 0 is not "no call", it is
        // "the OTHER call"). Count both lists.
        for (final (String edge, Offset Function(Rect, Rect) at)
            in <(String, Offset Function(Rect, Rect))>[
              ('top', (Rect b, Rect _) => Offset(b.center.dx, b.top + 2)),
              ('bottom', (Rect b, Rect _) => Offset(b.center.dx, b.bottom - 2)),
              ('left', (Rect b, Rect _) => Offset(b.left + 2, b.center.dy)),
              ('right', (Rect b, Rect _) => Offset(b.right - 2, b.center.dy)),
            ]) {
          // Re-measured per probe: the heart's `AnimatedScale` runs 0.92 ↔ 1.0
          // across a toggle, so the ICON's rect genuinely changes between
          // probes even though the box does not.
          final (card: Rect _, box: Rect box, icon: Rect icon) = rects(tester);
          final Offset probe = at(box, icon);

          // Sanity gate — without these two the probe proves nothing: a probe
          // that fell outside the box would be testing the card, and one that
          // landed on the painted icon would pass on the PRE-FIX 28×24 tree.
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
            'the same derived inset. An early draft copied the tile\'s '
            'centreRight and silently dropped the heart to mid-card height; '
            'got ${box.top - card.top}',
      );
    });
  });

  // =========================================================================
  // 3. No tap hijacking — the card still navigates outside the box.
  // =========================================================================
  group('the card still navigates where users actually tap', () {
    testWidgets(
      'a probe 3dp OUTSIDE the box\'s DERIVED leading boundary pushes the '
      'master profile and makes ZERO favourite calls',
      (tester) async {
        final repo = FakeFavoriteRepository();

        tester.view.physicalSize = const Size(_kProbeWidth, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // The pushed URI is captured in the destination's own builder rather
        // than read back off `router.routerDelegate.currentConfiguration`:
        // an IMPERATIVE `context.push` leaves that reporting the PARENT
        // location (measured: '/' here, while the stub screen is genuinely on
        // screen) — the known go_router imperative-match quirk. The builder's
        // `state.uri` is the location that actually matched.
        String? pushedLocation;
        final GoRouter router = GoRouter(
          initialLocation: '/',
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext context, GoRouterState state) => Scaffold(
                body: ListView(
                  children: <Widget>[MasterResultCard(master: _master())],
                ),
              ),
            ),
            GoRoute(
              path: '/masters/:id',
              builder: (BuildContext context, GoRouterState state) {
                pushedLocation = state.uri.toString();
                return const Scaffold(
                  body: SizedBox.shrink(key: Key('stub_master_profile')),
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
        // ever moves — and a probe computed from the LIVE box's own left edge
        // would move with it, never catching an over-expansion. Anchoring on
        // the card's rect plus the restated constants is what makes the
        // "hit extent widened to 64" mutation go red.
        final double expectedLeft =
            card.right - _kExpectedInset - _kPlatformMinTapExtent;
        final Offset probe = Offset(expectedLeft - 3, box.center.dy);

        expect(
          box.contains(probe),
          isFalse,
          reason:
              'sanity: the probe $probe must be OUTSIDE the measured box $box '
              '— if the shipped box already swallows it, this test is proving '
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
          find.byKey(const Key('stub_master_profile')),
          findsOneWidget,
          reason: 'the same tap must have opened the public master profile',
        );
        expect(
          pushedLocation,
          RouteNames.masterPublicProfile('master-1'),
          reason: 'the pushed location must be the master profile route',
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
        master: _master(firstName: _kLongFirstName, lastName: _kLongLastName),
      );

      final Rect card = tester.getRect(find.byType(NeumorphicCard));
      final Rect name = tester.getRect(
        find.byKey(const Key('master_card_name')),
      );

      // The genuine "with heart vs without heart" DELTA. The card exposes no
      // heart-less mode, so the slot-free width is reconstructed from the
      // live tree's OTHER geometry — the card's own trailing edge, its
      // restated padding, and the name column's LEFT edge (set by the
      // thumbnail + gap, entirely independent of the heart). The difference
      // between that and the measured width is, by definition, whatever the
      // trailing placeholder cost.
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
            'footprint (24dp icon + 4dp left-only pad), not to the abandoned '
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
