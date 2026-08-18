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
// The rated state now renders the shared `RatingSummaryCard` (the same
// average + ★ row + count + per-star distribution table the master's «Мої
// відгуки» screen renders) instead of the old big-number + single RatingStar
// + explanation `_RatingDisplay`. `RatingSummaryCard` gets its own dedicated
// widget tests under `test/features/review/`; the tests below only pin how
// MyRatingScreen WIRES `ClientRating` into it (avgRating/reviewCount/
// distribution/countLabel), plus the locked product rule that no
// comment/`ReviewCard` list is ever rendered here.
//
// Tests cover:
//   1. Empty state renders (HubEmptyState with the AppIcon star SVG) when
//      avgRating is null.
//   2. VelvetTopBar back button has the correct key.
//   3. VelvetTopBar renders the "beautica" wordmark (a visual reuse of
//      ClientTopBar's wordmark only, NOT a visible "МІЙ РЕЙТИНГ" title, and no
//      AppBar); l10n.myRatingTitle is preserved as the bar's `title` (a11y
//      identity) and as a Semantics header label, not as a rendered string.
//   4. Back button triggers context.pop() — verified via router pop.
//   5. Rated state: RatingSummaryCard visible (Key my_rating_display).
//   6. Empty state: Key my_rating_empty_state is present when avgRating null.
//   7. Rated state passes the fetched distribution through to
//      RatingSummaryCard unchanged, and never renders a ReviewCard/comment
//      list.
//   8. Average value text: "4.7" rendered for avgRating 4.7.
//   9. Rated state renders the review-count line (l10n.myRatingReviewCount) via
//      RatingSummaryCard's countLabel.
//  10. Loading state renders a spinner.
//  11. Error state renders the failure message + a retry that re-invalidates
//      the provider.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/hub_widgets.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/features/rating/presentation/my_rating_screen.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/rating_summary_card.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MyRatingScreen)));

Future<void> _pump(
  WidgetTester tester, {
  required Future<ClientRating> Function() rating,
  double? width,
  double? textScaleFactor,
}) async {
  await tester.pumpApp(
    const MyRatingScreen(),
    overrides: <Object>[myRatingProvider.overrideWith((ref) => rating())],
    width: width,
    textScaleFactor: textScaleFactor,
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
    // Sums to reviewCount (12) so the distribution reads naturally, though
    // RatingSummaryCard itself does not require that invariant.
    const List<int> distribution = <int>[7, 3, 1, 1, 0];

    Future<ClientRating> rated() async => const ClientRating(
      avgRating: 4.7,
      reviewCount: 12,
      distribution: distribution,
    );

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
        reason: 'RatingSummaryCard must render "4.7" for avgRating = 4.7',
      );
    });

    testWidgets('renders exactly one RatingSummaryCard, wired with the fetched '
        'avgRating/reviewCount/distribution/countLabel', (tester) async {
      await _pump(tester, rating: rated);
      await tester.pumpAndSettle();

      final Finder cardFinder = find.byType(RatingSummaryCard);
      expect(
        cardFinder,
        findsOneWidget,
        reason:
            'the rated state must render exactly one RatingSummaryCard — '
            'the same average + ★ row + count + distribution table the '
            "master's «Мої відгуки» screen renders",
      );

      final RatingSummaryCard card = tester.widget<RatingSummaryCard>(
        cardFinder,
      );
      final AppLocalizations l10n = _l10n(tester);
      expect(card.avgRating, equals(4.7));
      expect(card.reviewCount, equals(12));
      expect(
        card.distribution,
        equals(distribution),
        reason:
            'the distribution fetched via ClientRating must reach '
            'RatingSummaryCard unchanged (highest-first, index 0 = 5★)',
      );
      expect(card.countLabel, equals(l10n.myRatingReviewCount(12)));
    });

    testWidgets('renders the review-count line via RatingSummaryCard', (
      tester,
    ) async {
      await _pump(tester, rating: rated);
      await tester.pumpAndSettle();

      final AppLocalizations l10n = _l10n(tester);
      expect(find.text(l10n.myRatingReviewCount(12)), findsOneWidget);
    });

    testWidgets(
      'never renders a ReviewCard or any comment — the client sees only the '
      'aggregate table',
      (tester) async {
        // Locked product rule: the client NEVER sees individual comments from
        // masters/salons about them — GET /users/me/rating returns none, and
        // this screen must not render ReviewCard even if one were ever passed
        // in by mistake.
        await _pump(tester, rating: rated);
        await tester.pumpAndSettle();

        expect(
          find.byType(ReviewCard),
          findsNothing,
          reason:
              'MyRatingScreen must never render ReviewCard/comment content — '
              'only the aggregate RatingSummaryCard table',
        );
      },
    );
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

  // ── Top-bar tests ────────────────────────────────────────────────────────

  group('MyRatingScreen — VelvetTopBar', () {
    testWidgets('back button has correct key', (tester) async {
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pump();

      expect(
        find.byKey(const Key('my_rating_back_button')),
        findsOneWidget,
        reason: 'back button must be discoverable by key for nav assertions',
      );
    });

    testWidgets('renders the shared VelvetTopBar, not a Material AppBar', (
      tester,
    ) async {
      // House header convergence: the page chrome lives in the shared 48 dp
      // VelvetTopBar (centred wordmark, NeumorphicIconButton back arrow) —
      // NOT a Material AppBar with a left-aligned title.
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pump();

      expect(find.byType(VelvetTopBar), findsOneWidget);
      expect(
        find.byType(AppBar),
        findsNothing,
        reason: 'MyRatingScreen must not fall back to a Material AppBar',
      );

      final VelvetTopBar bar = tester.widget<VelvetTopBar>(
        find.byType(VelvetTopBar),
      );
      // `title` no longer renders visually (titleWidget overrides it with the
      // wordmark) but is still required and still carries the screen's a11y
      // identity — see the wordmark/semantics group below.
      expect(bar.title, equals(_l10n(tester).myRatingTitle));
      expect(
        bar.titleWidget,
        isNotNull,
        reason:
            'MyRatingScreen must supply titleWidget (the wordmark) rather '
            'than relying on the default Text(title) rendering',
      );
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

  // ── QA: house-header regression contract ─────────────────────────────────
  //
  // The dev's test above asserts a VelvetTopBar EXISTS and an AppBar does not.
  // That guard would still pass if the wordmark regressed to left-aligned, or
  // to the wrong style, or if the back affordance stayed a Material
  // IconButton — i.e. it does not pin the thing that was actually broken.
  //
  // Before (Phase 13.7): `AppBar(title: Text(l10n.myRatingTitle,
  //          style: heading18), centerTitle: false, leading: IconButton(...))`
  // After (Phase 13.7 revision): the shared 48 dp VelvetTopBar — CENTRED
  //          title at `VelvetText.subheading()`, NeumorphicIconButton back
  //          arrow.
  // Current (this change): the centred slot is the lowercase "beautica"
  //          wordmark at `VelvetText.wordmark()` (via `titleWidget`, reusing
  //          `ClientTopBar`'s wordmark VISUAL only — MyRatingScreen is a
  //          pushed top-level GoRoute with a back arrow, not a shell branch
  //          root), NOT a visible "МІЙ РЕЙТИНГ" string. The screen's a11y
  //          identity is preserved via
  //          a `Semantics(header: true, label: l10n.myRatingTitle)` wrapping
  //          the wordmark — see the group below.
  //
  // The centring assertion is geometric because a property assertion on
  // `textAlign` cannot distinguish "centred in the strip" from "centred inside
  // a Row cell that sits to the right of the arrow" — the latter is exactly
  // what the old AppBar rendered.

  group('MyRatingScreen — house header (centred beautica wordmark)', () {
    Finder titleFinder() => find.descendant(
      of: find.byType(VelvetTopBar),
      matching: find.byType(Text),
    );

    testWidgets('the wordmark is CENTRED on screen, not left-aligned', (
      tester,
    ) async {
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      final double screenCentre =
          tester.getSize(find.byType(Scaffold)).width / 2;

      expect(
        tester.getCenter(titleFinder()).dx,
        closeTo(screenCentre, 0.5),
        reason:
            'the page wordmark must be horizontally centred like every other '
            'ProfileScaffold / SectionScaffold screen and every screen '
            'reusing the wordmark visual (e.g. ClientTopBar\'s branch-root '
            'screens). The old AppBar(centerTitle: false) rendered it '
            'hard-left beside the back arrow — that is the regression this '
            'assertion exists to catch',
      );
    });

    testWidgets('renders the lowercase "beautica" wordmark, not the l10n '
        'title string', (tester) async {
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(VelvetTopBar),
          matching: find.text('beautica'),
        ),
        findsOneWidget,
        reason:
            'the top bar must render the brand wordmark literal, reusing '
            'ClientTopBar\'s wordmark visual (not its branch-root routing)',
      );
      expect(
        find.descendant(
          of: find.byType(VelvetTopBar),
          matching: find.text(_l10n(tester).myRatingTitle),
        ),
        findsNothing,
        reason:
            'the localised "МІЙ РЕЙТИНГ" title must no longer render '
            'visually — it survives only as the bar\'s a11y identity',
      );
    });

    testWidgets('the wordmark renders at VelvetText.wordmark(), not '
        'subheading or heading18', (tester) async {
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      final TextStyle? style = tester.widget<Text>(titleFinder()).style;

      expect(
        style,
        equals(VelvetText.wordmark()),
        reason:
            'the wordmark must use the SAME style as every screen reusing '
            'the wordmark visual (ClientTopBar\'s branch-root screens), so '
            'the two constructs cannot drift',
      );
      expect(
        style,
        isNot(equals(VelvetText.subheading())),
        reason:
            'VelvetText.subheading() was the pre-wordmark house-header title '
            'style; regressing to it would silently restore the old '
            'centred-title look under a wordmark-shaped test',
      );
      expect(
        style,
        isNot(equals(VelvetText.heading18)),
        reason:
            'VelvetText.heading18 was the deleted AppBar-era _titleStyle; '
            'regressing to it reintroduces the mismatched title',
      );
    });

    testWidgets(
      'the l10n title survives as a Semantics(header: true) label, not '
      'orphaned by the wordmark swap',
      (tester) async {
        // ARB-key regression guard (backlog row 55 pattern): `myRatingTitle`
        // must keep a LIVE code reference even though no visible Text uses it
        // anymore — a screen reader must still announce the screen's real
        // identity, not the brand wordmark, when focus lands on the header.
        final SemanticsHandle handle = tester.ensureSemantics();

        await _pump(tester, rating: () async => const ClientRating());
        await tester.pumpAndSettle();

        final AppLocalizations l10n = _l10n(tester);
        expect(
          find.bySemanticsLabel(l10n.myRatingTitle),
          findsOneWidget,
          reason:
              'the header region must announce l10n.myRatingTitle to a '
              'screen reader even though the visible glyph is "beautica"',
        );

        // `find.ancestor` walks the WHOLE ancestor chain (MaterialApp/Scaffold
        // insert their own Semantics widgets too), so narrow to the ancestor
        // whose OWN `properties.header` is true — that is unambiguously ours.
        final Semantics wrapper = tester.widget<Semantics>(
          find.ancestor(
            of: find.descendant(
              of: find.byType(VelvetTopBar),
              matching: find.text('beautica'),
            ),
            matching: find.byWidgetPredicate(
              (Widget w) => w is Semantics && w.properties.header == true,
            ),
          ),
        );
        expect(
          wrapper.properties.label,
          equals(l10n.myRatingTitle),
          reason:
              'the header-flagged Semantics wrapper must carry '
              'l10n.myRatingTitle as its label',
        );
        expect(
          wrapper.excludeSemantics,
          isTrue,
          reason:
              'without excludeSemantics the child Text\'s own auto-label '
              '("beautica") merges into this node, turning the clean '
              '"Мій рейтинг" announcement into "Мій рейтинг\\nbeautica"',
        );

        handle.dispose();
      },
    );

    // QA (Rule 3b follow-up) — the wordmark carries `maxLines: 1` +
    // `overflow: TextOverflow.ellipsis` as a defensive guard (mirroring
    // `ClientTopBar`'s identical construct — see
    // `client_top_bar_test.dart`'s "wordmark layout survives elevated text
    // scale" regression test). Until now NOTHING pumped this screen at a
    // narrow width or an elevated text scale, so the guard was pure dead
    // code as far as the suite could tell. `tester.pumpApp`'s `width`/
    // `textScaleFactor` knobs install the shared overflow guard (see
    // `pump_app.dart`), so a real `RenderFlex`/text overflow at the stress
    // size fails this test automatically — no golden needed (backlog row
    // 313 is a DIFFERENT, unrelated gap: the rated-state star-row, not this
    // top-bar wordmark).
    testWidgets('the wordmark survives 320dp width + 1.3x text scale without '
        'overflow, and the a11y header label is unaffected', (tester) async {
      // NOTE: dispose() must be called INSIDE the test body — flutter_test's
      // `_verifySemanticsHandlesWereDisposed` runs before addTearDown
      // callbacks, so `addTearDown(handle.dispose)` fails the test it is
      // meant to clean up (same pattern as the Semantics test above).
      final SemanticsHandle handle = tester.ensureSemantics();

      await _pump(
        tester,
        rating: () async => const ClientRating(),
        width: 320,
        textScaleFactor: 1.3,
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'no RenderFlex/text overflow may escape at the narrowest '
            'Android width (320dp) combined with an elevated text scale',
      );

      // The bar must still render SOMETHING in the title slot — either the
      // full wordmark or its ellipsized form — never an empty gap.
      expect(
        find.descendant(
          of: find.byType(VelvetTopBar),
          matching: find.byType(Text),
        ),
        findsOneWidget,
        reason:
            'the title slot must still render a Text node at the stress '
            'size, whether or not the ellipsis guard engaged',
      );

      // The a11y identity survives the stress pump too — the Semantics
      // wrapper is structural (not text-measurement-dependent), so it must
      // never be knocked out by the same layout pressure that could
      // ellipsize the visible glyph.
      expect(
        find.bySemanticsLabel(_l10n(tester).myRatingTitle),
        findsOneWidget,
        reason:
            'the header a11y label must survive the same stress pump that '
            'exercises the visible wordmark\'s ellipsis guard',
      );

      handle.dispose();
    });

    testWidgets('the back affordance is a NeumorphicIconButton, not IconButton', (
      tester,
    ) async {
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      expect(
        find.byType(NeumorphicIconButton),
        findsOneWidget,
        reason: 'the house back arrow is a NeumorphicIconButton',
      );
      expect(
        find.descendant(
          of: find.byType(MyRatingScreen),
          matching: find.byType(IconButton),
        ),
        findsNothing,
        reason:
            'the Material IconButton path (the old AppBar leading) is gone and '
            'must not creep back',
      );
      expect(
        tester.widget(find.byKey(const Key('my_rating_back_button'))),
        isA<NeumorphicIconButton>(),
        reason:
            'my_rating_back_button must name the NeumorphicIconButton itself, '
            'so every tap-by-key nav assertion actually hits the new button',
      );
    });

    // The header used to be a Scaffold `appBar:` — structurally OUTSIDE the
    // body, so no async branch could ever swallow it. It is now a Column
    // sibling of the `async.when(...)` body, so "the header survives every
    // state" became a real (previously unpinned) invariant. One test per state:
    // re-pumping several ProviderScopes inside a single body reuses the same
    // container, so a per-pump `retry` knob would not take effect.

    testWidgets('the header renders in the LOADING state', (tester) async {
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
      expect(
        find.byType(VelvetTopBar),
        findsOneWidget,
        reason: 'the header must sit outside async.when(), not inside loading',
      );
    });

    testWidgets('the header renders in the ERROR state', (tester) async {
      await tester.pumpApp(
        const MyRatingScreen(),
        overrides: <Object>[
          myRatingProvider.overrideWith((ref) async {
            throw const NetworkFailure();
          }),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_rating_error_state')), findsOneWidget);
      expect(
        find.byType(VelvetTopBar),
        findsOneWidget,
        reason:
            'a failed fetch must never strand the user without a back arrow',
      );
      expect(
        find.byKey(const Key('my_rating_back_button')),
        findsOneWidget,
        reason: 'the error state must remain escapable via the back arrow',
      );
    });

    testWidgets('the header renders in the DATA state', (tester) async {
      await _pump(
        tester,
        rating: () async => const ClientRating(avgRating: 4.7, reviewCount: 12),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('my_rating_display')), findsOneWidget);
      expect(find.byType(VelvetTopBar), findsOneWidget);
    });

    testWidgets('the body starts VelvetSpacing.md below the top bar', (
      tester,
    ) async {
      // Body top padding moved lg → md so this screen matches ProfileScaffold /
      // SectionScaffold, whose bodies sit directly beneath the same bar (the
      // bar already contributes its own xs bottom padding). Measured
      // geometrically rather than by reading the EdgeInsets, so the assertion
      // describes what the user sees.
      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      final double gap =
          tester.getRect(find.byType(HubFlatCard)).top -
          tester.getRect(find.byType(VelvetTopBar)).bottom;

      expect(
        gap,
        closeTo(VelvetSpacing.md, 0.5),
        reason:
            'ProfileScaffold / SectionScaffold parity: md (16) between the bar '
            'and the body card, not the pre-migration lg (24)',
      );
    });
  });

  group('MyRatingScreen — back affordance behaviour', () {
    testWidgets('the back button carries the LOCALISED semantic label', (
      tester,
    ) async {
      // dispose() INSIDE the body: flutter_test verifies semantics handles
      // before addTearDown callbacks run.
      final SemanticsHandle handle = tester.ensureSemantics();

      await _pump(tester, rating: () async => const ClientRating());
      await tester.pumpAndSettle();

      final AppLocalizations l10n = _l10n(tester);
      expect(
        find.bySemanticsLabel(l10n.registerBackStep),
        findsOneWidget,
        reason:
            'a11y: the NeumorphicIconButton back arrow is an unlabelled glyph '
            'to a screen reader unless backSemanticLabel reaches the semantics '
            'tree — and the label must come from l10n, never a raw literal '
            '(the bar\'s own fallback is the hardcoded «Назад»)',
      );
      expect(
        tester
            .widget<NeumorphicIconButton>(find.byType(NeumorphicIconButton))
            .semanticLabel,
        equals(l10n.registerBackStep),
        reason:
            'the screen must pass its localised label, not rely on the '
            'VelvetTopBar default',
      );

      handle.dispose();
    });

    testWidgets('popping works when the arrow is found BY TYPE, not by key', (
      tester,
    ) async {
      // Deliberately does NOT use my_rating_back_button: this proves the pop
      // wiring lives on the NeumorphicIconButton itself, so moving `onBack` to
      // some other node while leaving the key behind still fails.
      final GoRouter router = GoRouter(
        initialLocation: '/base',
        routes: <RouteBase>[
          GoRoute(
            path: '/base',
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
      router.push('/base/rating');
      await tester.pumpAndSettle();
      expect(find.byType(MyRatingScreen), findsOneWidget);

      await tester.tap(find.byType(NeumorphicIconButton));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('base_page')), findsOneWidget);
      expect(
        find.byType(MyRatingScreen),
        findsNothing,
        reason:
            'context.pop() from the NeumorphicIconButton must unmount the '
            'rating screen',
      );
    });
  });
}
