// Phase 111 (mobile-qa) — widget tests for [FavoritesScreen].
//
// WHY THIS FILE EXISTS
// --------------------
// The port shipped with ZERO presentation coverage: no test touched
// `favorites_screen.dart`, `favorite_cards.dart`, `favorites_filter.dart` or
// `favorites_empty_state.dart`. All four AsyncValue states, the undo window
// (the screen's most intricate piece of state — three sets, two nested timers
// and the DELETE that must fire exactly once, at collapse), and the failed-
// unlike snackbar were unpinned.
//
// ── HOW THE SCREEN IS PUMPED ────────────────────────────────────────────────
//
// `_openProfile` calls `context.push(RouteNames.…)`, so the screen needs a
// router context — `pumpRoutedApp` with a two-route GoRouter, whose leaves are
// keyed probes. A plain `pumpApp` would throw the moment a card is tapped.
//
// `_openSearch` calls `StatefulNavigationShell.of(context)`, which exists only
// inside the real client shell. The empty state's CTA is therefore asserted
// PRESENT here and TAPPED in `integration_test/client_favorites_flow_test.dart`,
// where the shell is real. Tapping it in this tier would assert nothing except
// that the harness throws.
//
// ── FINDERS ─────────────────────────────────────────────────────────────────
//
// Keys first (M2). The only `find.text` calls are on WIRE fixture values —
// provider names and ratings — which are data, identical in every locale, and
// deliberately Latin so no `i18n-finder-ok` escape hatch is needed at all.
//
// ── THE HEART HAS NO KEY ────────────────────────────────────────────────────
//
// `UnlikeHeart` (`favorite_cards.dart:352`) exposes no `Key` — pre-existing,
// flagged by mobile-dev, and NOT worked around with `warnIfMissed: false`. It
// is reached by scoping `find.byType(UnlikeHeart)` to the row's own card key,
// which is precise (one heart per card) and survives the key being added later.
// Its `AnimatedScale` sits INSIDE the `GestureDetector`, not at the widget
// root, so the hit test reaches the handler — this is not the
// `RenderTransform`-swallows-the-tap trap.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/favorites/application/favorites_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:beautica_mobile/features/favorites/presentation/favorites_screen.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorite_cards.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorites_filter.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';
import 'favorites_test_fixtures.dart';

void main() {
  group('FavoritesScreen — the four AsyncValue states', () {
    testWidgets('LOADING: the skeleton is shown while both fetches are in '
        'flight', (WidgetTester tester) async {
      final FavoritesHarness h = FavoritesHarness()..blockMasters();
      await h.pump(tester);
      await tester.pump();

      expect(find.byKey(const Key('favorites-loading')), findsOneWidget);
      expect(find.byType(FavoriteMasterCard), findsNothing);
      expect(find.byKey(const Key('favorites-error')), findsNothing);

      h.releaseMasters();
      await tester.pumpAndSettle();
    });

    testWidgets('LOADED: one card per row, with the provider\'s own data '
        'rendered', (WidgetTester tester) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          favMaster('m1', name: 'Marta Honchar', rating: 4.7),
        ]
        ..repo.salons = <FavoriteItem>[
          favSalon('s1', name: 'Crystal Room', rating: 5),
        ];
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
      expect(find.byKey(const Key('favorites-salon-s1')), findsOneWidget);
      // NOT a smoke assertion: the specific bound values. A card that rendered
      // but bound nothing would pass a bare `findsOneWidget` on the key alone.
      expect(find.text('Marta Honchar'), findsOneWidget);
      expect(find.text('Crystal Room'), findsOneWidget);
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('5.0'), findsOneWidget);
    });

    testWidgets('EMPTY: the nothing-saved state and its search CTA', (
      WidgetTester tester,
    ) async {
      final FavoritesHarness h = FavoritesHarness();
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-empty-state')), findsOneWidget);
      expect(
        find.byKey(const Key('favorites-find-master-button')),
        findsOneWidget,
      );
      // The FILTER-empty variant must NOT be what an unfiltered empty list
      // renders — it would send the client to "clear the filter" with no
      // filter set.
      expect(
        find.byKey(const Key('favorites-category-empty-state')),
        findsNothing,
      );
    });

    testWidgets('ERROR: the error state renders and its retry REFETCHES', (
      WidgetTester tester,
    ) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.mastersResult = const NotFoundFailure();
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-error')), findsOneWidget);
      final int callsBefore = h.repo.mastersCalls;

      h.repo.mastersResult = null;
      h.repo.masters = <FavoriteItem>[favMaster('m1', name: 'Marta Honchar')];
      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      // The tap is not decoration — it re-issued the fetch AND the list
      // replaced the error surface.
      expect(h.repo.mastersCalls, greaterThan(callsBefore));
      expect(find.byKey(const Key('favorites-error')), findsNothing);
      expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
    });

    testWidgets('a RETRY IN FLIGHT renders LOADING, never the error surface', (
      WidgetTester tester,
    ) async {
      // M12 / trap 3 in `favorites_notifier.dart`'s header. `AsyncLoading(error:
      // …, retrying: true)` satisfies `hasError` and carries the real error, so
      // a screen that branched on `hasError` would show a permanent error
      // surface while Riverpod is still transparently retrying underneath it.
      //
      // RED WHEN the `switch (favorites)` in `favorites_screen.dart:207` is
      // replaced by a `favorites.hasError ? _ErrorBody : …` branch.
      //
      // NetworkFailure is TRANSIENT per `failure_retry_policy.dart`, so the
      // production predicate this harness installs genuinely retries it — the
      // mid-retry shape is reachable here and nowhere else in this suite.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[favMaster('m1', name: 'Marta Honchar')]
        ..repo.mastersResult = const NetworkFailure();
      await h.pump(tester);
      // Drain the first attempt only — do NOT settle, which would burn the
      // whole ~38 s backoff curve and land on the terminal error.
      await tester.pump();
      await tester.pump();

      final AsyncValue<List<FavoriteItem>> state = h
          .container(tester)
          .read(favoritesProvider);
      expect(
        state.hasError,
        isTrue,
        reason: 'the fixture must have failed at least once by now',
      );
      expect(
        state,
        isA<AsyncLoading<List<FavoriteItem>>>(),
        reason:
            'the provider must still be mid-retry for this test to mean '
            'anything — if it is already AsyncError the assertion below is '
            'vacuous',
      );

      expect(find.byKey(const Key('favorites-loading')), findsOneWidget);
      expect(find.byKey(const Key('favorites-error')), findsNothing);

      // Let the retry land so no backoff timer outlives the test. The first
      // retry is scheduled 200 ms out and the fixture now succeeds, so this
      // resolves in a few pumps — pump-until, never a guessed duration.
      h.repo.mastersResult = null;
      await tester.pumpUntilFound(find.byKey(const Key('favorites-master-m1')));
      await tester.pumpAndSettle();
    });
  });

  group('FavoritesScreen — the category filter', () {
    testWidgets('renders NOTHING when no favourite carries a category', (
      WidgetTester tester,
    ) async {
      // The degenerate case: a favourite whose DTO carried an empty
      // `categories` list (or elements each missing one half of their pair —
      // see `FavoriteMapper._categoriesFromDto`). A pill that can only ever
      // say «Всі» is furniture costing permanent vertical space on a scroll.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[favMaster('m1')];
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-filter-pill')), findsNothing);
      expect(find.byType(FavoriteCategoryChip), findsNothing);
    });

    testWidgets('appears, opens, and FILTERS the list once categories exist', (
      WidgetTester tester,
    ) async {
      // The normal case now that both favourites DTOs carry a category.
      // Exercises `FavoriteChoice.from`, the `visible` derivation, and the
      // chip wiring end to end.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          favMaster(
            'm1',
            name: 'Marta Honchar',
            categoryId: 'c1',
            categoryLabel: 'Nails',
          ),
          favMaster(
            'm2',
            name: 'Olena Kravets',
            categoryId: 'c2',
            categoryLabel: 'Brows',
          ),
        ];
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-filter-pill')), findsOneWidget);

      await tester.tap(find.byKey(const Key('favorites-filter-pill')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favorites-chip-cat-c1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
      expect(find.byKey(const Key('favorites-master-m2')), findsNothing);

      // «Скинути» is reachable from the COLLAPSED pill — the client never has
      // to reopen the panel to get back to everything.
      await tester.tap(find.byKey(const Key('favorites-filter-reset')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favorites-master-m2')), findsOneWidget);
    });

    testWidgets('an empty CATEGORY shows the clear-filter state, not the '
        'search CTA', (WidgetTester tester) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          favMaster('m1', categoryId: 'c1', categoryLabel: 'Nails'),
        ];
      await h.pump(tester, selectedCategory: 'c2');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('favorites-category-empty-state')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('favorites-empty-state')), findsNothing);
      expect(
        find.byKey(const Key('favorites-show-all-button')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a provider offering SEVERAL categories appears under EACH chip',
      (WidgetTester tester) async {
        // Backend `b0c924f`: a favourite now carries every distinct category
        // the provider offers, not the client's most-recently-booked one. m1
        // offers both Nails and Brows — selecting either chip must surface
        // it, and it must keep showing up on «Всі».
        final FavoritesHarness h = FavoritesHarness()
          ..repo.masters = <FavoriteItem>[
            favMaster(
              'm1',
              name: 'Marta Honchar',
              categories: const <FavoriteCategory>[
                FavoriteCategory(id: 'c1', label: 'Nails'),
                FavoriteCategory(id: 'c2', label: 'Brows'),
              ],
            ),
            favMaster(
              'm2',
              name: 'Olena Kravets',
              categoryId: 'c2',
              categoryLabel: 'Brows',
            ),
          ];
        await h.pump(tester);
        await tester.pumpAndSettle();

        // «Всі» — both rows visible.
        expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
        expect(find.byKey(const Key('favorites-master-m2')), findsOneWidget);

        await tester.tap(find.byKey(const Key('favorites-filter-pill')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('favorites-chip-cat-c1')));
        await tester.pumpAndSettle();

        // c1 (Nails) — only m1 offers it.
        expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
        expect(find.byKey(const Key('favorites-master-m2')), findsNothing);

        await tester.tap(find.byKey(const Key('favorites-filter-pill')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('favorites-chip-cat-c2')));
        await tester.pumpAndSettle();

        // c2 (Brows) — BOTH m1 and m2 offer it; m1 is not exclusive to c1.
        expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
        expect(find.byKey(const Key('favorites-master-m2')), findsOneWidget);
      },
    );
  });

  group('FavoritesScreen — retained selection — mobile-security re-audit '
      'finding 2 (LOW)', () {
    // Both routes reduce to the same shape: the client is FILTERED to a
    // category id that then drops out of `FavoriteChoice.from(items)` — one
    // because the category's last favourite is gone, the other because a
    // reorder pushed it past `FavoriteChoice._kMaxChoices` — while `visible`
    // (item-filtered, not choice-derived) stays correctly filtered the whole
    // time. Without `_FavoritesScreenState._withRetainedSelection`, the pill
    // silently falls back to «Всі» and «Скинути» disappears while the data
    // is still filtered — the control lies about a filter the list still
    // enforces.

    testWidgets(
      'ROUTE 1 (pre-existing, no cap involved): unliking the SELECTED '
      "category's LAST favourite keeps the pill naming it and «Скинути» "
      'reachable',
      (WidgetTester tester) async {
        final FavoritesHarness h = FavoritesHarness()
          ..repo.masters = <FavoriteItem>[
            favMaster(
              'm1',
              name: 'Marta Honchar',
              categoryId: 'c1',
              categoryLabel: 'Nails',
            ),
            // A second, DIFFERENT category so the raw union is non-empty
            // after m1 goes — this is the "category disappears from a
            // non-empty choices list" case, distinct from the filter's own
            // "zero categories at all" degradation (see the widget's own
            // "renders NOTHING" test above).
            favMaster(
              'm2',
              name: 'Olena Kravets',
              categoryId: 'c2',
              categoryLabel: 'Brows',
            ),
          ];
        await h.pump(tester, selectedCategory: 'c1');
        await tester.pumpAndSettle();
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(FavoritesScreen)),
        );

        expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
        expect(find.byKey(const Key('favorites-master-m2')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text('Nails'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('favorites-filter-reset')), findsOneWidget);

        await h.tapHeart(tester, 'favorites-master-m1');
        await h.settleUndoWindow(tester);

        // c1 now has zero favourites — `FavoriteChoice.from` no longer
        // returns it — but `favoritesCategoryFilterProvider` still holds
        // 'c1'.
        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text('Nails'),
          ),
          findsOneWidget,
          reason:
              'the pill must keep naming the emptied category, not fall '
              'back to «Всі» while a filter is still applied',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text(l10n.favoritesFilterAll),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const Key('favorites-filter-reset')),
          findsOneWidget,
          reason:
              '«Скинути» must stay reachable so the client can get back to '
              '«Всі» in one tap without having to reopen the panel',
        );

        // mobile-security re-audit INFO: retention was traced but UNASSERTED
        // for its second consumer. `_emptyState`'s own `categoryLabel` lookup
        // (`favorites_screen.dart:556-562`) reads the SAME `choices` list the
        // pill reads above — `visible` is empty here (c1's only favourite is
        // gone), so the category empty state is what actually renders, and
        // without retention its lookup misses too, falling back to `''` and
        // rendering the title with a BLANK category name instead of «Nails».
        expect(
          find.byKey(const Key('favorites-category-empty-state')),
          findsOneWidget,
          reason:
              'visible is empty for c1, so the category empty state — '
              'not the loaded list — is what is on screen here',
        );
        expect(
          find.text(l10n.favoritesCategoryEmptyTitle('Nails')),
          findsOneWidget,
          reason:
              'the empty-state title must carry the REAL retained category '
              'name, not fall back to the blank string `choices.firstOrNull '
              '?? \'\'` produces once c1 drops out of the raw union',
        );

        // Discard-on-clear: tapping «Скинути» must actually clear it, not
        // leave the retained memory stuck forever.
        await tester.tap(find.byKey(const Key('favorites-filter-reset')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text(l10n.favoritesFilterAll),
          ),
          findsOneWidget,
          reason:
              'clearing the filter must show «Всі» — the retained memory '
              'must not outlive the selection that owned it',
        );
      },
    );

    testWidgets(
      'ROUTE 2 (the cap): a reorder that pushes the SELECTED category past '
      'the 50-chip cap does not un-apply the filter either',
      (WidgetTester tester) async {
        final FavoritesHarness h = FavoritesHarness()
          ..repo.masters = <FavoriteItem>[
            favMaster('m_c0', categoryId: 'c0', categoryLabel: 'Nails'),
          ];
        await h.pump(tester, selectedCategory: 'c0');
        await tester.pumpAndSettle();
        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(FavoritesScreen)),
        );

        expect(find.byKey(const Key('favorites-filter-reset')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text('Nails'),
          ),
          findsOneWidget,
        );

        // A reorder that surfaces 50 OTHER distinct categories ahead of c0 in
        // traversal order pushes c0 past `FavoriteChoice._kMaxChoices` — m_c0
        // is still favourited and still carries category c0; it is simply no
        // longer among the first 50 DISTINCT codes `FavoriteChoice.from`
        // walks before it gives up.
        h.repo.masters = <FavoriteItem>[
          for (int i = 0; i < 50; i++)
            favMaster('m_d$i', categoryId: 'd$i', categoryLabel: 'Category $i'),
          favMaster('m_c0', categoryId: 'c0', categoryLabel: 'Nails'),
        ];
        await h.container(tester).read(favoritesProvider.notifier).refresh();
        await tester.pumpAndSettle();

        // The item itself is still correctly filtered — this route is about
        // the CONTROL lying, not the data.
        expect(find.byKey(const Key('favorites-master-m_c0')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text('Nails'),
          ),
          findsOneWidget,
          reason:
              'the pill must keep naming the SELECTED category even after a '
              'reorder truncates it out of the raw union',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text(l10n.favoritesFilterAll),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const Key('favorites-filter-reset')),
          findsOneWidget,
          reason:
              '«Скинути» must stay reachable — the filter is still '
              'applied',
        );
      },
    );

    testWidgets('discard-on-clear: clearing the filter does not leave a stale '
        'retained chip behind in the OPEN PANEL', (WidgetTester tester) async {
      // The pill itself cannot distinguish this defect (its lookup is
      // `selectedId == null ? null : ...`, so it always falls back to
      // «Всі» once cleared regardless of what the retained memory still
      // holds) — the only place a memory that outlived its selection is
      // observable is the chip `Wrap` inside the open panel.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          favMaster('m1', categoryId: 'c1', categoryLabel: 'Nails'),
          favMaster('m2', categoryId: 'c2', categoryLabel: 'Brows'),
        ];
      await h.pump(tester, selectedCategory: 'c1');
      await tester.pumpAndSettle();

      // Empty out c1 so `_retainedChoice` holds Nails/c1 — same setup as
      // ROUTE 1 above.
      await h.tapHeart(tester, 'favorites-master-m1');
      await h.settleUndoWindow(tester);

      await tester.tap(find.byKey(const Key('favorites-filter-reset')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('favorites-filter-pill')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('favorites-chip-cat-c1')),
        findsNothing,
        reason:
            'c1 has zero favourites AND the filter is cleared — the '
            'retained memory must not outlive the selection that owned '
            'it, or a chip leading nowhere renders in the open panel',
      );
      expect(
        find.byKey(const Key('favorites-chip-cat-c2')),
        findsOneWidget,
        reason: 'c2 is genuinely live (m2) — must still render',
      );
    });

    testWidgets('discard-on-mismatch: a selection that never saw the retained '
        'category live does not inherit its stale chip', (
      WidgetTester tester,
    ) async {
      // Not reachable through a real chip tap (a tap only ever selects an
      // id present in the panel at tap time — see the method's own doc) —
      // reached here the way it would in production: an external write to
      // `favoritesCategoryFilterProvider` (e.g. a stale deep-link param)
      // landing on an id this screen never saw live at all.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          favMaster('m1', categoryId: 'c1', categoryLabel: 'Nails'),
          favMaster('m2', categoryId: 'c2', categoryLabel: 'Brows'),
        ];
      await h.pump(tester, selectedCategory: 'c1');
      await tester.pumpAndSettle();

      // Empty out c1 so `_retainedChoice` holds Nails/c1.
      await h.tapHeart(tester, 'favorites-master-m1');
      await h.settleUndoWindow(tester);

      h
          .container(tester)
          .read(favoritesCategoryFilterProvider.notifier)
          .select('zzz-unknown');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('favorites-filter-pill')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('favorites-chip-cat-c1')),
        findsNothing,
        reason:
            'the retained Nails/c1 memory belongs to a DIFFERENT id than '
            'the one now selected — it must be discarded, not spliced in '
            'under the wrong id',
      );
      expect(
        find.byKey(const Key('favorites-chip-cat-c2')),
        findsOneWidget,
        reason: 'c2 is genuinely live (m2) — must still render',
      );
    });

    testWidgets(
      'adopt-from-live: a genuine category RENAME while still selected and '
      'live is reflected immediately, and the RENAMED label — not the '
      "tap-time one — is what survives once the category later goes "
      'non-live',
      (WidgetTester tester) async {
        final FavoritesHarness h = FavoritesHarness()
          ..repo.masters = <FavoriteItem>[
            favMaster('m1', categoryId: 'c1', categoryLabel: 'Nails'),
          ];
        await h.pump(tester, selectedCategory: 'c1');
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text('Nails'),
          ),
          findsOneWidget,
        );

        // The admin renames the category. c1 is still LIVE (m1 still
        // carries it) — the pill must pick up the fresh label immediately.
        h.repo.masters = <FavoriteItem>[
          favMaster('m1', categoryId: 'c1', categoryLabel: 'Manicure'),
        ];
        await h.container(tester).read(favoritesProvider.notifier).refresh();
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text('Manicure'),
          ),
          findsOneWidget,
        );

        // Now c1 goes non-live — retention kicks in. The memory it falls
        // back to must be the RENAMED label, not the one frozen at the
        // very first tap.
        await h.tapHeart(tester, 'favorites-master-m1');
        await h.settleUndoWindow(tester);

        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text('Manicure'),
          ),
          findsOneWidget,
          reason:
              '`_retainedChoice` must track the live label on every build '
              'while still live, not freeze at the tap-time label',
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('favorites-filter-pill')),
            matching: find.text('Nails'),
          ),
          findsNothing,
        );
      },
    );
  });

  group('FavoritesScreen — the undo window', () {
    testWidgets('unlike replaces the card with a dent IN ITS OWN SLOT and '
        'sends nothing yet', (WidgetTester tester) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          favMaster('m1', name: 'Marta Honchar'),
          favMaster('m2', name: 'Olena Kravets'),
        ];
      await h.pump(tester);
      await tester.pumpAndSettle();
      final double listHeightBefore = tester
          .getSize(find.byType(CustomScrollView))
          .height;

      await h.tapHeart(tester, 'favorites-master-m1');
      await tester.pump();

      expect(find.byKey(const Key('favorites-dent-m1')), findsOneWidget);
      expect(find.byKey(const Key('favorites-master-m1')), findsNothing);
      // The row BELOW is untouched — the slot is held, so the list does not
      // jump at the moment of the tap.
      expect(find.byKey(const Key('favorites-master-m2')), findsOneWidget);
      expect(
        tester.getSize(find.byType(CustomScrollView)).height,
        listHeightBefore,
      );
      // NOTHING has been sent. The DELETE fires at collapse, not at tap.
      expect(h.repo.removeCalls, isEmpty);
      expect(h.container(tester).read(favoritesProvider).value, hasLength(2));

      await h.settleUndoWindow(tester);
    });

    testWidgets('«Повернути» restores the card and never touches the server', (
      WidgetTester tester,
    ) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[favMaster('m1', name: 'Marta Honchar')];
      await h.pump(tester);
      await tester.pumpAndSettle();

      await h.tapHeart(tester, 'favorites-master-m1');
      await tester.pump();
      await tester.tap(find.byKey(const Key('favorites-undo-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
      expect(find.byKey(const Key('favorites-dent-m1')), findsNothing);
      expect(h.repo.removeCalls, isEmpty);

      // And the cancelled timer must not fire later. Pump well past the
      // window: a leaked timer would remove the row here.
      await h.settleUndoWindow(tester);
      expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
      expect(h.repo.removeCalls, isEmpty);
    });

    testWidgets('the window expiring commits EXACTLY ONE DELETE', (
      WidgetTester tester,
    ) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          favMaster('m1', name: 'Marta Honchar'),
          favMaster('m2', name: 'Olena Kravets'),
        ];
      await h.pump(tester);
      await tester.pumpAndSettle();

      await h.tapHeart(tester, 'favorites-master-m1');
      await h.settleUndoWindow(tester);

      expect(h.repo.removeCalls, hasLength(1));
      expect(h.repo.removeCalls.single.id, 'm1');
      expect(h.repo.removeCalls.single.type.name, 'master');
      // And it went out as a REMOVE, never an ADD — the prime-to-true contract
      // in `favorites_notifier.unfavorite`, observed end to end.
      expect(h.repo.addCalls, isEmpty);
      expect(find.byKey(const Key('favorites-master-m1')), findsNothing);
      expect(find.byKey(const Key('favorites-master-m2')), findsOneWidget);
    });

    testWidgets('a FAILED commit restores the row and surfaces a snackbar', (
      WidgetTester tester,
    ) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[
          favMaster('m1', name: 'Marta Honchar'),
          favMaster('m2', name: 'Olena Kravets'),
        ]
        ..repo.removeResult = const ServerFailure();
      await h.pump(tester);
      await tester.pumpAndSettle();

      await h.tapHeart(tester, 'favorites-master-m1');
      await h.settleUndoWindow(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      // Restored AT ITS ORIGINAL INDEX — the list reads exactly as the client
      // last saw it, not with the row appended to the bottom.
      final List<FavoriteItem> items = h
          .container(tester)
          .read(favoritesProvider)
          .value!;
      expect(items.map((FavoriteItem i) => i.id).toList(), <String>[
        'm1',
        'm2',
      ]);
      expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);
    });

    testWidgets('a pull-to-refresh CANCELS an open undo window', (
      WidgetTester tester,
    ) async {
      // RED WHEN the timer sweep at `favorites_screen.dart:164-171` is deleted.
      // A refresh replaces the list wholesale, so a timer still holding an id
      // from the OLD list fires a DELETE for a row the client can no longer
      // see — and `unfavorite` finds no matching id and silently no-ops, which
      // looks exactly like the unlike was lost.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[favMaster('m1', name: 'Marta Honchar')];
      await h.pump(tester);
      await tester.pumpAndSettle();

      await h.tapHeart(tester, 'favorites-master-m1');
      await tester.pump();
      expect(find.byKey(const Key('favorites-dent-m1')), findsOneWidget);

      await h.container(tester).read(favoritesProvider.notifier).refresh();
      // The screen's own handler is what clears the timers; drive it, not the
      // notifier alone.
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        touchSlopY: 0,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorites-dent-m1')), findsNothing);
      expect(find.byKey(const Key('favorites-master-m1')), findsOneWidget);

      await h.settleUndoWindow(tester);
      expect(
        h.repo.removeCalls,
        isEmpty,
        reason: 'the cancelled window must not fire a DELETE after a refresh',
      );
    });
  });

  group('FavoritesScreen — navigation', () {
    testWidgets('tapping a MASTER card pushes the public master profile', (
      WidgetTester tester,
    ) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[favMaster('m1', name: 'Marta Honchar')];
      await h.pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('favorites-master-m1')));
      await tester.pumpAndSettle();

      // Pin the resolved PAGE, not just the path: a literal route declared
      // before a dynamic sibling can absorb the path and leave a location
      // assertion green while the wrong page mounted.
      expect(find.byKey(const Key('probe-master-profile')), findsOneWidget);
      expect(h.router.state.pathParameters['masterId'], 'm1');
    });

    testWidgets('tapping a SALON card pushes the public salon profile', (
      WidgetTester tester,
    ) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.salons = <FavoriteItem>[favSalon('s1', name: 'Crystal Room')];
      await h.pump(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('favorites-salon-s1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('probe-salon-profile')), findsOneWidget);
      expect(h.router.state.pathParameters['salonId'], 's1');
    });

    testWidgets('a card tap does NOT fire the unlike, and vice versa', (
      WidgetTester tester,
    ) async {
      // The heart sits INSIDE the card shell's GestureDetector. Without
      // `HitTestBehavior.opaque` on the heart the tap would fall through to the
      // shell and open the profile instead of removing the favourite.
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[favMaster('m1', name: 'Marta Honchar')];
      await h.pump(tester);
      await tester.pumpAndSettle();

      await h.tapHeart(tester, 'favorites-master-m1');
      await tester.pump();

      expect(find.byKey(const Key('probe-master-profile')), findsNothing);
      expect(find.byKey(const Key('favorites-dent-m1')), findsOneWidget);

      await h.settleUndoWindow(tester);
    });
  });

  group('FavoritesScreen — shell contract', () {
    testWidgets('carries the client-branch-favorites Key the placeholder '
        'exposed', (WidgetTester tester) async {
      // `scripts/forbid_missing_client_branch_key.sh` enforces this statically;
      // this asserts the Key actually reaches the RENDERED tree, which the
      // script cannot see.
      final FavoritesHarness h = FavoritesHarness();
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('client-branch-favorites')), findsOneWidget);
    });

    testWidgets('grows NO AppBar of its own — the shell owns the top bar', (
      WidgetTester tester,
    ) async {
      final FavoritesHarness h = FavoritesHarness()
        ..repo.masters = <FavoriteItem>[favMaster('m1')];
      await h.pump(tester);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(FavoritesScreen),
          matching: find.byType(AppBar),
        ),
        findsNothing,
      );
    });
  });

  group('FavoriteCategoryChip label — mobile-security finding 2 (unbounded '
      'text)', () {
    testWidgets(
      'caps its label to ONE line with ellipsis, matching the address '
      "block's note convention",
      (WidgetTester tester) async {
        // `sanitizeDisplayText` strips the bidi/zero-width class but NOT
        // `\n`/U+2028/U+2029 (a separate, recorded backlog gap — not touched
        // here), so a label containing a real newline is the exact input a
        // hostile/buggy category label could carry. Without `maxLines` +
        // `overflow` this Text grows past one line inside the AnimatedSize
        // panel; asserting the Text's own properties (rather than pixel
        // height) pins the fix directly and deterministically.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FavoriteCategoryChip(
                label: 'Line one\nLine two\nLine three',
                selected: false,
                onTap: _noop,
              ),
            ),
          ),
        );

        final Text textWidget = tester.widget<Text>(
          find.text('Line one\nLine two\nLine three'),
        );

        expect(
          textWidget.maxLines,
          1,
          reason: 'the chip label must be capped to one line',
        );
        expect(
          textWidget.overflow,
          TextOverflow.ellipsis,
          reason:
              'an uncapped label with embedded line separators would '
              'otherwise stretch the chip inside the AnimatedSize panel',
        );
      },
    );
  });

  group('_StatePill label (via FavoritesInlineFilter) — mobile-security '
      're-audit finding 1 (unbounded text, MEDIUM)', () {
    testWidgets(
      'caps its label to ONE line with ellipsis — the same defect just '
      'fixed on the chip, but on furniture that is ALWAYS visible',
      (WidgetTester tester) async {
        // `_StatePill` renders `selected?.label` — the SAME untrusted
        // `FavoriteChoice.label` the chip caps, from the same source
        // (`FavoriteChoice.from`). Unlike the chip, which only renders while
        // the panel is open, the pill is the filter's only PERMANENT
        // furniture — this is the strictly worse exposure the re-audit
        // flagged. `_StatePill` is private, so it is exercised through the
        // public `FavoritesInlineFilter` with the panel CLOSED (default),
        // which guarantees the only `Text` carrying this label anywhere in
        // the tree is the pill's — the chip is not even built.
        const String label = 'Line one\nLine two\nLine three';
        await tester.pumpApp(
          const FavoritesInlineFilter(
            choices: <FavoriteChoice>[FavoriteChoice(id: 'c1', label: label)],
            selectedId: 'c1',
            onSelect: _noopSelect,
          ),
        );

        final Text textWidget = tester.widget<Text>(find.text(label));

        expect(
          textWidget.maxLines,
          1,
          reason:
              'the pill label must be capped to one line, matching the '
              'fix already applied to FavoriteCategoryChip',
        );
        expect(
          textWidget.overflow,
          TextOverflow.ellipsis,
          reason:
              'an uncapped label with embedded line separators would '
              'otherwise stretch the pill — permanent furniture, unlike the '
              'chip which only renders while the panel is open',
        );
      },
    );
  });
}

void _noop() {}

void _noopSelect(String? _) {}
