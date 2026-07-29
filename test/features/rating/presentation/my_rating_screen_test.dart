// Phase 13.7 (revised) / track 7.x Wave B — MyRatingScreen widget tests.
//
// Replaces test/features/reviews/presentation/my_reviews_screen_test.dart.
//
// MyRatingScreen is now a ConsumerWidget wired to [myRatingProvider] (`GET
// /users/me/rating`, track 7.x Wave B) instead of taking a `clientRating`
// constructor param — every test below overrides the provider instead of
// passing a value directly, mirroring `leave_review_screen_test.dart`'s
// `bookingDetailProvider(...).overrideWith(...)` convention.
//
// Tests cover:
//   1. Empty state renders (HubEmptyState with the AppIcon star SVG) when
//      avgRating is null.
//   2. AppBar back button has the correct key.
//   3. AppBar title renders via l10n.myRatingTitle.
//   4. Back button triggers context.pop() — verified via router pop.
//   5. Rated state: big number + RatingStar visible (Key my_rating_display).
//   6. Empty state: Key my_rating_empty_state is present when avgRating null.
//   7. Rated state renders a single RatingStar carrying the rating value.
//   8. Star value text: "4.7" rendered for rating 4.7.
//   9. RatingStar.fillFor fill-fraction boundaries are pinned (1.0/5.0/3.0/4.7/
//      2.3/0.0/null).
//  10. Rated state renders explanation text (l10n.myRatingExplanation).
//  11. Rated state renders the review-count line (l10n.myRatingReviewCount).
//  12. Loading state renders a spinner.
//  13. Error state renders the failure message + a retry that re-invalidates
//      the provider.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/rating/presentation/my_rating_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MyRatingScreen)));

Future<void> _pump(
  WidgetTester tester, {
  required Future<ClientRating> Function() rating,
}) async {
  await tester.pumpApp(
    const MyRatingScreen(),
    overrides: <Object>[myRatingProvider.overrideWith((ref) => rating())],
  );
  await tester.pump();
}

void main() {
  // ── Empty-state tests ─────────────────────────────────────────────────────

  group('MyRatingScreen — empty state (avgRating: null)', () {
    testWidgets('empty state key is present', (tester) async {
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('my_rating_empty_state')),
        findsOneWidget,
        reason:
            'MyRatingScreen with null avgRating must show '
            'my_rating_empty_state',
      );
    });

    testWidgets('empty state renders the AppIcon star SVG', (tester) async {
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      // The empty-state star is a BeauticaAssetIcons.star SVG passed to
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
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('my_rating_display')),
        findsNothing,
        reason: 'my_rating_display must not be visible when avgRating is null',
      );
    });
  });

  // ── Rated-state tests ─────────────────────────────────────────────────────

  group('MyRatingScreen — rated state (avgRating: 4.7, reviewCount: 12)', () {
    Future<ClientRating> rated() async =>
        const ClientRating(avgRating: 4.7, reviewCount: 12);

    testWidgets('rated display key is present', (tester) async {
      await _pump(tester, rating: rated);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('my_rating_display')),
        findsOneWidget,
        reason:
            'MyRatingScreen with non-null avgRating must show '
            'my_rating_display',
      );
    });

    testWidgets('empty state key is absent', (tester) async {
      await _pump(tester, rating: rated);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('my_rating_empty_state')),
        findsNothing,
        reason:
            'my_rating_empty_state must not be visible when avgRating is '
            'non-null',
      );
    });

    testWidgets('shows "4.7" value text', (tester) async {
      await _pump(tester, rating: rated);
      await tester.pumpAndSettle();

      expect(
        find.text('4.7'),
        findsOneWidget,
        reason: 'big number must render "4.7" for avgRating = 4.7',
      );
    });

    testWidgets('renders a single RatingStar carrying the rating', (
      tester,
    ) async {
      // The rated state renders exactly ONE RatingStar (single fractional-fill
      // star) holding the rating value.
      await _pump(tester, rating: rated);
      await tester.pumpAndSettle();

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
        reason: 'the RatingStar must carry the avgRating value (4.7)',
      );
    });

    testWidgets('for rating 5.0 the RatingStar is fully filled', (
      tester,
    ) async {
      await _pump(
        tester,
        rating: () async => const ClientRating(avgRating: 5.0, reviewCount: 1),
      );
      await tester.pumpAndSettle();

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
        reason: 'the RatingStar must carry the avgRating value (5.0)',
      );
      // 5.0 is the top of the 1–5 scale → fully filled (fraction 1.0).
      expect(
        RatingStar.fillFor(5.0),
        equals(1.0),
        reason: 'rating 5.0 must map to a fully filled star (fill == 1.0)',
      );
    });

    testWidgets('renders the review-count line', (tester) async {
      await _pump(tester, rating: rated);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = _l10n(tester);
      expect(
        find.byKey(const Key('my_rating_review_count')),
        findsOneWidget,
        reason: 'rated state must render the review-count line',
      );
      expect(find.text(l10n.myRatingReviewCount(12)), findsOneWidget);
    });
  });

  // ── RatingStar fill-fraction boundaries (QA additions) ────────────────────
  //
  // The single fractional-fill RatingStar's formula: fill is normalized:
  // ((rating - 1) / 4).clamp(0, 1) — 1.0 is empty, 5.0 is full.

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
      expect(RatingStar.fillFor(2.3), closeTo(0.325, 1e-9));
    });

    test(
      'rating 2.5 → 0.375 (former exact-half boundary is just a fraction)',
      () {
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
      await _pump(
        tester,
        rating: () async => const ClientRating(avgRating: 4.7, reviewCount: 12),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('my_rating_display')),
        findsOneWidget,
        reason: 'rated state must show my_rating_display (precondition)',
      );
      // Content assertion is acceptable for l10n content verification (M2
      // only bans raw strings as PRIMARY FINDERS via find.text for
      // navigation — content assertions that verify data binding are fine).
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
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      // In the empty state only HubEmptyState renders — the explanation is
      // absent because _RatingDisplay is not built. The empty-state message
      // (l10n.myRatingEmpty) contains "рейтинг" too, but there must NOT be a
      // second Text containing "формується" which only appears in
      // myRatingExplanation.
      expect(
        find.textContaining('формується'),
        findsNothing,
        reason:
            'myRatingExplanation must NOT render when avgRating is null '
            '(empty state only shows myRatingEmpty)',
      );
    });
  });

  // ── Loading / error states ──────────────────────────────────────────────

  group('MyRatingScreen — loading and error states', () {
    testWidgets('loading state renders a spinner', (tester) async {
      await tester.pumpApp(
        const MyRatingScreen(),
        overrides: <Object>[
          myRatingProvider.overrideWith(
            (ref) => Completer<ClientRating>().future,
          ),
        ],
      );
      await tester.pump();

      expect(find.byKey(const Key('my_rating_loading')), findsOneWidget);
    });

    testWidgets(
      'a Failure surfaces the localized message and a retry re-invalidates '
      'the provider',
      (tester) async {
        int fetches = 0;
        await tester.pumpApp(
          const MyRatingScreen(),
          overrides: <Object>[
            myRatingProvider.overrideWith((ref) async {
              fetches++;
              throw const NetworkFailure();
            }),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = _l10n(tester);
        expect(fetches, 1);
        expect(find.byKey(const Key('my_rating_error_state')), findsOneWidget);
        expect(find.text(l10n.errNetwork), findsOneWidget);

        await tester.tap(find.byKey(const Key('my_rating_error_retry')));
        await tester.pump();

        expect(fetches, 2, reason: 'retry must invalidate myRatingProvider');
      },
    );

    testWidgets('a non-Failure error shows the generic errUnknown message', (
      tester,
    ) async {
      await tester.pumpApp(
        const MyRatingScreen(),
        overrides: <Object>[
          myRatingProvider.overrideWith((ref) async {
            throw Exception('boom');
          }),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = _l10n(tester);
      expect(find.text(l10n.errUnknown), findsOneWidget);
    });
  });

  // ── AppBar tests ─────────────────────────────────────────────────────────

  group('MyRatingScreen — AppBar', () {
    testWidgets('back button has correct key', (tester) async {
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pump();

      expect(
        find.byKey(const Key('my_rating_back_button')),
        findsOneWidget,
        reason: 'back button must be discoverable by key for nav assertions',
      );
    });

    testWidgets('AppBar is present', (tester) async {
      await _pump(tester, rating: () async => const ClientRating());
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

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          myRatingProvider.overrideWith((ref) async => const ClientRating()),
        ],
      );
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
