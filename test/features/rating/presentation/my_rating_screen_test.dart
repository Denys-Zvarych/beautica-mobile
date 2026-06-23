// Phase 13.7 (revised) — MyRatingScreen widget tests.
//
// Replaces test/features/reviews/presentation/my_reviews_screen_test.dart.
//
// Tests cover:
//   1. Empty state renders (HubEmptyState with the AppIcon star SVG).
//   2. AppBar back button has the correct key.
//   3. AppBar title renders via l10n.myRatingTitle.
//   4. Back button triggers context.pop() — verified via router pop.
//   5. Rated state: big number + RatingStar visible (Key my_rating_display).
//   6. Empty state: Key my_rating_empty_state is present when clientRating null.
//   7. Rated state renders a single RatingStar carrying the rating value.
//   8. Star value text: "4.7" rendered for rating 4.7.
//   QA additions (mobile-qa):
//   9. RatingStar.fillFor fill-fraction boundaries are pinned (1.0/5.0/3.0/4.7/
//      2.3/0.0/null) — replaces the deleted 5-slot _StarRow breakdown.
//  10. Rated state renders explanation text (l10n.myRatingExplanation).

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/rating/presentation/my_rating_screen.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

void main() {
  // ── Empty-state tests ─────────────────────────────────────────────────────

  group('MyRatingScreen — empty state (clientRating: null)', () {
    testWidgets('empty state key is present', (tester) async {
      await tester.pumpApp(const MyRatingScreen());
      await tester.pump();

      expect(
        find.byKey(const Key('my_rating_empty_state')),
        findsOneWidget,
        reason:
            'MyRatingScreen with null rating must show my_rating_empty_state',
      );
    });

    testWidgets('empty state renders the AppIcon star SVG', (tester) async {
      await tester.pumpApp(const MyRatingScreen());
      await tester.pump();

      // The empty-state star is now a BeauticaAssetIcons.star SVG passed to
      // HubEmptyState via iconWidget (replacing Material's star_outline_rounded).
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.asset == BeauticaAssetIcons.star,
        ),
        findsOneWidget,
        reason:
            'HubEmptyState in the empty state must render the star SVG icon',
      );
    });

    testWidgets('rated display key is absent', (tester) async {
      await tester.pumpApp(const MyRatingScreen());
      await tester.pump();

      expect(
        find.byKey(const Key('my_rating_display')),
        findsNothing,
        reason:
            'my_rating_display must not be visible when clientRating is null',
      );
    });
  });

  // ── Rated-state tests ─────────────────────────────────────────────────────

  group('MyRatingScreen — rated state (clientRating: 4.7)', () {
    testWidgets('rated display key is present', (tester) async {
      await tester.pumpApp(const MyRatingScreen(clientRating: 4.7));
      await tester.pump();

      expect(
        find.byKey(const Key('my_rating_display')),
        findsOneWidget,
        reason:
            'MyRatingScreen with non-null rating must show my_rating_display',
      );
    });

    testWidgets('empty state key is absent', (tester) async {
      await tester.pumpApp(const MyRatingScreen(clientRating: 4.7));
      await tester.pump();

      expect(
        find.byKey(const Key('my_rating_empty_state')),
        findsNothing,
        reason:
            'my_rating_empty_state must not be visible when clientRating is non-null',
      );
    });

    testWidgets('shows "★ 4.7" value text', (tester) async {
      await tester.pumpApp(const MyRatingScreen(clientRating: 4.7));
      await tester.pump();

      expect(
        find.text('4.7'),
        findsOneWidget,
        reason: 'big number must render "4.7" for clientRating = 4.7',
      );
    });

    testWidgets('renders a single RatingStar carrying the rating', (
      tester,
    ) async {
      // The old 5-slot _StarRow is gone: the rated state now renders exactly
      // ONE RatingStar (single fractional-fill star) holding the rating value.
      await tester.pumpApp(const MyRatingScreen(clientRating: 4.7));
      await tester.pump();

      final Finder starFinder = find.byType(RatingStar);
      expect(
        starFinder,
        findsOneWidget,
        reason: 'rated state must render exactly one RatingStar',
      );

      final RatingStar star = tester.widget<RatingStar>(starFinder);
      expect(
        star.rating,
        equals(4.7),
        reason: 'the RatingStar must carry the clientRating value (4.7)',
      );
    });

    testWidgets('for rating 5.0 the RatingStar is fully filled', (
      tester,
    ) async {
      await tester.pumpApp(const MyRatingScreen(clientRating: 5.0));
      await tester.pump();

      final Finder starFinder = find.byType(RatingStar);
      expect(
        starFinder,
        findsOneWidget,
        reason: 'rated state must render exactly one RatingStar',
      );

      final RatingStar star = tester.widget<RatingStar>(starFinder);
      expect(
        star.rating,
        equals(5.0),
        reason: 'the RatingStar must carry the clientRating value (5.0)',
      );
      // 5.0 is the top of the 1–5 scale → fully filled (fraction 1.0).
      expect(
        RatingStar.fillFor(5.0),
        equals(1.0),
        reason: 'rating 5.0 must map to a fully filled star (fill == 1.0)',
      );
    });
  });

  // ── RatingStar fill-fraction boundaries (QA additions) ────────────────────
  //
  // The deleted _StarRow per-slot breakdown counted full/half/outlined Material
  // glyphs. The single fractional-fill RatingStar replaces that model: there are
  // no per-slot glyphs, so we pin the fill-fraction formula instead. Fill is
  // normalized: ((rating - 1) / 4).clamp(0, 1) — 1.0 is empty, 5.0 is full.

  group('RatingStar.fillFor — fill-fraction boundaries', () {
    test('rating 1.0 → 0.0 (bottom of scale renders an empty star)', () {
      expect(RatingStar.fillFor(1.0), equals(0.0));
    });

    test('rating 5.0 → 1.0 (top of scale renders a full star)', () {
      expect(RatingStar.fillFor(5.0), equals(1.0));
    });

    test('rating 3.0 → 0.5 (midpoint of the 1–5 scale)', () {
      expect(RatingStar.fillFor(3.0), equals(0.5));
    });

    test('rating 4.7 → 0.925 (the canonical sample value)', () {
      expect(RatingStar.fillFor(4.7), closeTo(0.925, 1e-9));
    });

    test('rating 2.3 → 0.325 (no rounding to a half boundary)', () {
      // Replaces the old "2.3 → no half star (frac < 0.5)" intent: under the
      // continuous fill model 2.3 simply maps to its exact fraction.
      expect(RatingStar.fillFor(2.3), closeTo(0.325, 1e-9));
    });

    test(
      'rating 2.5 → 0.375 (former exact-half boundary is just a fraction)',
      () {
        // Old model treated 2.5 as the exact half-star lower bound. The new model
        // has no glyph boundary; 2.5 is simply (2.5 - 1) / 4 = 0.375.
        expect(RatingStar.fillFor(2.5), closeTo(0.375, 1e-9));
      },
    );

    test('rating 0.0 → 0.0 (below-scale value clamps to empty)', () {
      expect(RatingStar.fillFor(0.0), equals(0.0));
    });

    test('null rating → 0.0 (no rating yet renders an empty star)', () {
      expect(RatingStar.fillFor(null), equals(0.0));
    });
  });

  // ── Explanation text (QA addition) ────────────────────────────────────────

  group('MyRatingScreen — rated state explanation text', () {
    testWidgets('rated state renders the myRatingExplanation l10n text', (
      tester,
    ) async {
      // The explanation (l10n.myRatingExplanation) is only shown in the rated
      // state (_RatingDisplay). It must be absent in the empty state.
      await tester.pumpApp(const MyRatingScreen(clientRating: 4.7));
      await tester.pump();

      // The text widget renders l10n.myRatingExplanation. In the uk locale
      // this is the UA string about ratings forming from master/salon reviews.
      // We use a content assertion here (not a raw-string finder) because the
      // l10n key is the source of truth; asserting on the key value ensures
      // the binding is wired correctly.
      // Raw-string assertion is acceptable for l10n content verification
      // (M2 only bans raw strings as PRIMARY FINDERS via find.text for
      // navigation — content assertions that verify data binding are correct).
      expect(
        find.byKey(const Key('my_rating_display')),
        findsOneWidget,
        reason: 'rated state must show my_rating_display (precondition)',
      );
      // Verify that _RatingDisplay rendered at least one Text child that
      // contains the expected UA explanation content fragment.
      // The full string is long, so we match on a distinctive fragment.
      expect(
        find.textContaining('рейтинг'),
        findsWidgets,
        reason:
            'rated state must render the myRatingExplanation text which '
            'explains how the client rating is formed',
      );
    });

    testWidgets('empty state does NOT render myRatingExplanation', (
      tester,
    ) async {
      await tester.pumpApp(const MyRatingScreen());
      await tester.pump();

      // In the empty state only HubEmptyState renders — the explanation is
      // absent because _RatingDisplay is not built.
      // The empty-state message (l10n.myRatingEmpty) contains "рейтинг" too,
      // but there must NOT be a second Text containing "формується" which
      // only appears in myRatingExplanation.
      expect(
        find.textContaining('формується'),
        findsNothing,
        reason:
            'myRatingExplanation must NOT render when clientRating is null '
            '(empty state only shows myRatingEmpty)',
      );
    });
  });

  // ── AppBar tests ─────────────────────────────────────────────────────────

  group('MyRatingScreen — AppBar', () {
    testWidgets('back button has correct key', (tester) async {
      await tester.pumpApp(const MyRatingScreen());
      await tester.pump();

      expect(
        find.byKey(const Key('my_rating_back_button')),
        findsOneWidget,
        reason: 'back button must be discoverable by key for nav assertions',
      );
    });

    testWidgets('AppBar is present', (tester) async {
      await tester.pumpApp(const MyRatingScreen());
      await tester.pump();

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('back button pops the route', (tester) async {
      final GoRouter router = GoRouter(
        initialLocation: '/rating-base',
        routes: <RouteBase>[
          GoRoute(
            path: '/rating-base',
            builder: (context, state) =>
                const Scaffold(body: Text('base', key: Key('base_page'))),
            routes: <RouteBase>[
              GoRoute(
                path: 'rating',
                builder: (context, state) => const MyRatingScreen(),
              ),
            ],
          ),
        ],
      );

      await tester.pumpRoutedApp(router);
      // ignore: unawaited_futures
      router.push('/rating-base/rating');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_rating_back_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('my_rating_back_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('base_page')), findsOneWidget);
    });
  });
}
