// Phase 13.x / perf MEDIUM-1 — Debounce contract for the results screen's LIVE
// search field (`Key('results_query_field')`).
//
// WHY THIS FILE EXISTS
// --------------------
// `query` participates in [SearchFilters]'s `==`/`hashCode`, so every applied
// term re-keys the `searchResultsProvider` FAMILY and issues a fresh page-0
// fetch — on BOTH endpoints. Undebounced, typing «манікюр» would fire SEVEN
// two-endpoint fan-outs of wildcard-LIKE scans against `permitAll` endpoints.
//
// Before this file, `results_query_field` had ZERO test hits anywhere under
// test/features/discovery/ — deleting the `Timer` entirely, or shortening the
// window back to the 400 ms that fired mid-phrase, was invisible to the suite.
//
// THE PROBE
// ---------
// A hand-written counting [SearchRepository] rather than a mocktail mock: the
// assertions here are about HOW MANY times each endpoint was hit, and an exact
// count reads far better off a plain counter than off `verify(...).called(n)`.
// It is deliberately committed (mobile-perf used a throwaway version of it).
//
// TIME CONTROL
// ------------
// `tester.pump(Duration)` advances the test clock deterministically — it does
// NOT sleep. Using it to step across a debounce boundary is the correct tool and
// is not the `pump(Duration(seconds: 3))` anti-pattern, which is about waiting
// out real async work. Every step below is expressed relative to
// [_debounce] so shortening the production window breaks these tests loudly.

import 'package:beautica_mobile/features/discovery/data/search_repository.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository_provider.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_results_screen.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/overflow_guard.dart';

/// The production quiet window. Kept here as a named constant so the steps below
/// read as "just under" / "just over" the boundary rather than magic numbers.
const Duration _debounce = Duration(milliseconds: 500);

const Key _queryField = Key('results_query_field');

// ---------------------------------------------------------------------------
// Counting repository probe
// ---------------------------------------------------------------------------

class _CountingSearchRepository implements SearchRepository {
  int masterCalls = 0;
  int salonCalls = 0;

  /// The `query` carried by every masters request, in order.
  final List<String?> queries = <String?>[];

  void reset() {
    masterCalls = 0;
    salonCalls = 0;
    queries.clear();
  }

  /// Total two-endpoint fan-outs. A search costs ONE of these.
  int get fanOuts {
    expect(
      masterCalls,
      salonCalls,
      reason: 'the notifier always fans out to both endpoints in lockstep',
    );
    return masterCalls;
  }

  @override
  Future<SearchPage<MasterSearchItem>> searchMasters({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) async {
    masterCalls++;
    queries.add(filters.query);
    return const SearchPage<MasterSearchItem>(
      items: <MasterSearchItem>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    );
  }

  @override
  Future<SearchPage<SalonSearchItem>> searchSalons({
    required SearchFilters filters,
    required int page,
    int size = kSearchPageSize,
    CancelToken? cancelToken,
  }) async {
    salonCalls++;
    return const SearchPage<SalonSearchItem>(
      items: <SalonSearchItem>[],
      page: 0,
      totalPages: 1,
      totalElements: 0,
    );
  }
}

/// Real [SearchFiltersController] behaviour (so `setQuery`'s normalise → hold →
/// apply logic genuinely runs) with only `build()` seeded, skipping the
/// production auth-watch.
class _SeededFiltersController extends SearchFiltersController {
  _SeededFiltersController(this._seed);

  final SearchFilters _seed;

  @override
  SearchFilters build() => _seed;
}

const List<LocalizationsDelegate<Object>> _delegates =
    <LocalizationsDelegate<Object>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

void main() {
  setUp(installOverflowGuard);

  Future<_CountingSearchRepository> pumpScreen(
    WidgetTester tester, {
    SearchFilters seed = const SearchFilters(),
  }) async {
    final _CountingSearchRepository repo = _CountingSearchRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Object>[
          searchRepositoryProvider.overrideWithValue(repo),
          searchFiltersControllerProvider.overrideWith(
            () => _SeededFiltersController(seed),
          ),
          favoriteToggleProvider.overrideWith(_NoopFavoriteToggle.new),
        ].cast(),
        child: MaterialApp(
          localizationsDelegates: _delegates,
          supportedLocales: const <Locale>[Locale('uk'), Locale('en')],
          locale: const Locale('uk'),
          home: SearchResultsScreen(initialFilters: seed),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The mount itself legitimately costs one fan-out; measure from zero.
    repo.reset();
    return repo;
  }

  /// Types [text] then lets the debounce elapse and the refetch settle.
  Future<void> typeAndSettle(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(_queryField), text);
    await tester.pump(_debounce + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  // ── the core promise: keystrokes collapse into one search ────────────────

  group('debounce collapses keystrokes', () {
    testWidgets('seven rapid keystrokes produce exactly ONE fan-out', (
      tester,
    ) async {
      final repo = await pumpScreen(tester);

      // Type «манікюр» one character at a time, each well inside the window.
      for (final String prefix in <String>[
        'м',
        'ма',
        'ман',
        'мані',
        'манік',
        'манікю',
        'манікюр',
      ]) {
        await tester.enterText(find.byKey(_queryField), prefix);
        // fixed-wait-ok: must land INSIDE the 500 ms window so it restarts.
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(_debounce + const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(
        repo.fanOuts,
        1,
        reason:
            'undebounced this is SEVEN two-endpoint fan-outs of wildcard-LIKE '
            'scans for a single typed word',
      );
      expect(
        repo.queries.single,
        'манікюр',
        reason: 'the ONE search that runs must be the FINAL settled term',
      );
    });

    testWidgets('nothing is fetched before the window elapses', (tester) async {
      final repo = await pumpScreen(tester);

      await tester.enterText(find.byKey(_queryField), 'манікюр');
      await tester.pump(_debounce - const Duration(milliseconds: 50));

      expect(
        repo.fanOuts,
        0,
        reason:
            'the apply must happen strictly AFTER the quiet window — firing '
            'early is what the 400 ms setting did mid-phrase',
      );

      // Let it land so the test ends with no pending timer.
      // fixed-wait-ok: elapses the last 50 ms just proven NOT yet elapsed.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(repo.fanOuts, 1);
    });

    testWidgets('each keystroke RESTARTS the window (it is not a throttle)', (
      tester,
    ) async {
      final repo = await pumpScreen(tester);

      // Two keystrokes 400 ms apart: total elapsed 800 ms > one window, yet the
      // window never completes because the second keystroke restarts it. A
      // throttle (leading-edge) implementation would have fired by now.
      await tester.enterText(find.byKey(_queryField), 'манік');
      // fixed-wait-ok: 400 ms is just UNDER the window, so the next key restarts it.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byKey(_queryField), 'манікюр');
      // fixed-wait-ok: 2nd sub-window step; 800 ms total must still fetch zero.
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        repo.fanOuts,
        0,
        reason:
            'a restarted window means 800 ms of typing still costs zero '
            'requests — this is what `_queryDebounceTimer?.cancel()` buys',
      );

      // fixed-wait-ok: completes the restarted window so one search fires.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(repo.fanOuts, 1);
      expect(repo.queries.single, 'манікюр');
    });
  });

  // ── the below-minimum rule costs nothing on the wire ─────────────────────

  group('below-minimum terms never reach the wire', () {
    testWidgets('a 1-character term issues ZERO requests', (tester) async {
      final repo = await pumpScreen(tester);

      await typeAndSettle(tester, 'м');

      expect(
        repo.fanOuts,
        0,
        reason:
            'the backend answers a below-minimum q with an empty page plus a '
            '"type at least 3 characters" message — a guaranteed-useless round '
            'trip that would also blank the results already on screen',
      );
    });

    testWidgets('a 2-character term issues ZERO requests', (tester) async {
      final repo = await pumpScreen(tester);

      await typeAndSettle(tester, 'ма');

      expect(repo.fanOuts, 0);
    });

    testWidgets('the 3rd character is what finally issues the request', (
      tester,
    ) async {
      final repo = await pumpScreen(tester);

      await typeAndSettle(tester, 'ма');
      expect(repo.fanOuts, 0, reason: 'still held');

      await typeAndSettle(tester, 'ман');

      expect(repo.fanOuts, 1, reason: 'the minimum is inclusive');
      expect(repo.queries.single, 'ман');
    });
  });

  // ── an unchanged applied query must not re-key ───────────────────────────
  //
  // DISCRIMINATION NOTE (measured — do not overstate what these prove).
  // Deleting BOTH early-return guards (`_applyQuery`'s
  // `if (applied == _filters.query) return;` AND `_applyFilters`'s
  // `if (next == _filters) return;`) leaves these tests GREEN. That is not a
  // gap in the tests — it is the real mechanism: [SearchFilters] is a freezed
  // value type, so re-keying with an EQUAL filter set resolves to the very same
  // `searchResultsProvider` family member, which is already cached. The two
  // guards are a rebuild optimisation layered on top of that, not the guarantee.
  //
  // What these tests DO discriminate is the NORMALISATION delegation: replacing
  // `_applyQuery`'s setQuery round-trip with a raw `copyWith(query: raw)` makes
  // four of them fail, because '  манікюр  ' then differs from 'манікюр' and
  // re-keys the family for nothing. That — plus a hypothetical loss of
  // SearchFilters' value equality — is the regression surface here.
  group('idempotence', () {
    testWidgets('re-typing the SAME applied term does not refetch', (
      tester,
    ) async {
      final repo = await pumpScreen(
        tester,
        seed: const SearchFilters(query: 'манікюр'),
      );

      await typeAndSettle(tester, 'манікюр');

      expect(
        repo.fanOuts,
        0,
        reason:
            '_applyQuery reads the settled query back and compares it — an '
            'unconditional _applyFilters would re-key the family and refetch '
            'identical results',
      );
    });

    testWidgets('trailing whitespace does not count as a change', (
      tester,
    ) async {
      final repo = await pumpScreen(
        tester,
        seed: const SearchFilters(query: 'манікюр'),
      );

      await typeAndSettle(tester, '  манікюр  ');

      expect(
        repo.fanOuts,
        0,
        reason:
            'normalisation happens BEFORE the comparison, so padding is not a '
            'new search',
      );
    });

    testWidgets('a genuinely different term DOES refetch (control)', (
      tester,
    ) async {
      final repo = await pumpScreen(
        tester,
        seed: const SearchFilters(query: 'манікюр'),
      );

      await typeAndSettle(tester, 'педикюр');

      expect(
        repo.fanOuts,
        1,
        reason:
            'isolation control — the idempotence tests above must not be '
            'passing simply because nothing ever refetches',
      );
      expect(repo.queries.single, 'педикюр');
    });
  });

  // ── teardown ─────────────────────────────────────────────────────────────

  group('dispose', () {
    testWidgets('the pending debounce TIMER is cancelled when the screen is '
        'popped', (tester) async {
      // DISCRIMINATION NOTE. The clock is deliberately NOT advanced past the
      // window after unmounting. That is the whole point: `_applyQuery` already
      // opens with `if (!mounted) return;`, so letting an UNCANCELLED timer fire
      // is silently harmless and no request-count assertion can see it (measured
      // — that version of this test stayed green with `dispose`'s cancel
      // removed). What DOES see it is flutter_test's own end-of-test check,
      // which fails with "A Timer is still pending even after the widget tree
      // was disposed" — but only if the timer is still armed when the test ends.
      await pumpScreen(tester);

      await tester.enterText(find.byKey(_queryField), 'манікюр');
      // fixed-wait-ok: stops the clock mid-window, leaving the Timer ARMED.
      await tester.pump(const Duration(milliseconds: 100));

      // Pop the screen mid-window and stop the clock there.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a debounce that fires after the pop issues no request', (
      tester,
    ) async {
      // The complementary half: even if a timer somehow survives, `_applyQuery`
      // must not act on it. Here the clock IS advanced past the window.
      final repo = await pumpScreen(tester);

      await tester.enterText(find.byKey(_queryField), 'манікюр');
      // fixed-wait-ok: arms the Timer mid-window, before the pop below.
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(_debounce * 2);
      await tester.pumpAndSettle();

      expect(
        repo.fanOuts,
        0,
        reason:
            'a search for a screen the user already left must never be issued',
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Inert favourite toggle — the heart is irrelevant here and the production
/// notifier watches the auth stack.
class _NoopFavoriteToggle extends FavoriteToggleNotifier {
  @override
  Map<FavoriteTarget, FavoriteEntry> build() =>
      const <FavoriteTarget, FavoriteEntry>{};
}
