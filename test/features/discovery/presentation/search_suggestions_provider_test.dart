// Phase 352 D2/D3/D9 — Unit tests for [SearchSuggestions] (the debounced,
// place-keyed, LRU-cached suggestion pipeline).
//
// Driven through a minimal widget harness — a bare `ProviderContainer` alone
// is not enough: `searchSuggestionsProvider` depends on
// `searchQueryDraftControllerProvider`/`searchFiltersControllerProvider` via
// `ref.watch`, and Riverpod 3 schedules that recompute through its own
// scheduler rather than running it synchronously inside `container.read`.
// A `Consumer` that itself `ref.watch`es the provider ties that recompute to
// the normal Flutter frame/rebuild cycle, which `tester.pump()` reliably
// drives — the same mechanism every screen-level test in this codebase
// already relies on for a debounced provider.
//
// `tester.pump(duration)` is what actually advances the `Timer` inside the
// notifier; `pumpAndSettle` fires no `Timer` of its own accord and would
// measure the PRE-debounce state — falsified once explicitly below.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/discovery/data/search_suggestion_repository.dart';
import 'package:beautica_mobile/features/discovery/domain/search_suggestion.dart';
import 'package:beautica_mobile/features/discovery/domain/search_suggestions.dart';
import 'package:beautica_mobile/features/discovery/presentation/search_suggestions_provider.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:dio/dio.dart'
    show CancelToken, DioException, DioExceptionType, RequestOptions;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

class _FixedAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async {
    state = _authenticated;
    return const AuthSession.authenticated(user: _testUser, accessToken: 'tok');
  }
}

/// Local categories available on-device — «Нарощення вій» word-starts on
/// «нар», matching the local instant layer (D2). NAILS is a fixture a test
/// can deliberately have the server OMIT, to prove availability filtering.
const _lashes = ServiceCategoryOption(
  name: 'EYELASH',
  displayName: 'Нарощення вій',
);
const _nails = ServiceCategoryOption(name: 'NAILS', displayName: 'Нігті');
const _categories = <ServiceCategoryOption>[_lashes, _nails];

const _lashSuggestion = SearchSuggestion(
  type: SearchSuggestionType.category,
  label: 'Нарощення вій',
  categoryKey: 'EYELASH',
);
const _nailServiceSuggestion = SearchSuggestion(
  type: SearchSuggestionType.service,
  label: 'Нарощення нігтів',
  categoryKey: 'NAILS',
  serviceTypeSlug: 'nail-extension',
);

typedef _Call = ({String term, String? cityId, String? districtId});

/// Records every `fetch` call and resolves via [resolve] — configurable per
/// test (including throwing, to exercise the error/429 fallback).
class _FakeSuggestionRepository implements SearchSuggestionRepository {
  _FakeSuggestionRepository({required this.resolve});

  final Future<List<SearchSuggestion>> Function(
    String term,
    String? cityId,
    String? districtId,
  )
  resolve;

  final List<_Call> calls = <_Call>[];

  /// The [CancelToken] passed to each [fetch] call, parallel to [calls]
  /// (mobile-perf LOW cycle-1 — supersede fix). Lets a test observe that
  /// `_scheduleFetch` cancelled the PREVIOUS call's token before issuing a
  /// new one.
  final List<CancelToken?> cancelTokens = <CancelToken?>[];

  @override
  Future<List<SearchSuggestion>> fetch({
    required String term,
    String? cityId,
    String? districtId,
    int limit = kSearchSuggestionMax,
    CancelToken? cancelToken,
  }) {
    calls.add((term: term, cityId: cityId, districtId: districtId));
    cancelTokens.add(cancelToken);
    return resolve(term, cityId, districtId);
  }
}

/// Server fixture: for `q` containing «нар», returns the NAIL service
/// (category NAILS) — a category the LOCAL matcher never returns (it only
/// ranks CATEGORY rows, never SERVICE) — proving the debounced response
/// APPENDS server rows rather than merely echoing the local ones. Any other
/// term resolves to an empty list.
Future<List<SearchSuggestion>> _serverRowsFor(
  String term,
  String? cityId,
  String? districtId,
) async {
  if (!term.toLowerCase().contains('нар')) return const <SearchSuggestion>[];
  // "Place chosen" fixture: only city-a offers the nail service; city-b does
  // not (proves availability filtering per place).
  if (districtId == null && cityId != null && cityId != 'city-a') {
    return const <SearchSuggestion>[];
  }
  return const <SearchSuggestion>[_nailServiceSuggestion];
}

/// Pumps a minimal widget tree — a `Consumer` that `ref.watch`es
/// [searchSuggestionsProvider] so its recompute rides the normal Flutter
/// rebuild cycle — with the auth graph stubbed authenticated and the
/// categories + suggestion repository overridden. Returns the root
/// [ProviderContainer] so a test can drive/read the notifiers directly.
///
/// Not disposed via `addTearDown` — `flutter_test`'s per-test tree teardown
/// disposes the pumped widget tree, and with it the `ProviderScope`'s
/// container.
Future<({ProviderContainer container, _FakeSuggestionRepository repo})> _boot(
  WidgetTester tester, {
  List<ServiceCategoryOption> categories = _categories,
  Future<List<SearchSuggestion>> Function(String, String?, String?)? resolve,
}) async {
  final repo = _FakeSuggestionRepository(resolve: resolve ?? _serverRowsFor);
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        authProvider.overrideWith(_FixedAuthNotifier.new),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        approvedCategoriesProvider.overrideWith((ref) async => categories),
        searchSuggestionRepositoryProvider.overrideWithValue(repo),
      ].cast(),
      child: Consumer(
        builder: (BuildContext context, WidgetRef ref, _) {
          container = ProviderScope.containerOf(context);
          ref.watch(searchSuggestionsProvider);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  // Let the (async) categories provider settle to DATA, and the resulting
  // rebuild land, before the test starts driving the notifier.
  await tester.pumpAndSettle();
  return (container: container, repo: repo);
}

/// Sets the draft (what the user typed) — the same funnel
/// `SearchFiltersController.setQuery` uses.
void _type(ProviderContainer c, String term) =>
    c.read(searchFiltersControllerProvider.notifier).setQuery(term);

void main() {
  group('national (no place)', () {
    testWidgets(
      'local CATEGORY rows are available INSTANTLY with 0 calls before the '
      'debounce; after it, the server rows are appended',
      (tester) async {
        final boot = await _boot(tester);
        final c = boot.container;
        final repo = boot.repo;

        _type(c, 'нар');
        await tester.pump(); // synchronous local computation lands
        expect(
          c.read(searchSuggestionsProvider).map((s) => s.categoryKey),
          contains('EYELASH'),
        );
        expect(
          repo.calls,
          isEmpty,
          reason: 'the local row must not have cost a request',
        );

        await tester.pump(kSearchSuggestionDebounce);
        await tester.pump(); // let the fetch Future resolve

        expect(repo.calls, hasLength(1));
        expect(repo.calls.single.cityId, isNull);
        expect(
          c.read(searchSuggestionsProvider).map((s) => s.serviceTypeSlug),
          contains('nail-extension'),
          reason: 'the server SERVICE row must have been appended',
        );
      },
    );

    testWidgets('FALSIFIES the debounce: without letting fake time elapse, the '
        'service row assertion above would be vacuous', (tester) async {
      final boot = await _boot(tester);
      final c = boot.container;

      _type(c, 'нар');
      // A bare flush — NO duration elapses, so the 200 ms debounce cannot
      // have fired.
      await tester.pump();

      expect(
        c.read(searchSuggestionsProvider).map((s) => s.serviceTypeSlug),
        isNot(contains('nail-extension')),
        reason:
            'no time has elapsed — the server row must NOT be present yet, '
            'proving the pump(kSearchSuggestionDebounce) step above is '
            'load-bearing',
      );
    });
  });

  group('place chosen', () {
    testWidgets(
      'NO local rows before the debounce; after it, exactly the server rows '
      '— a local category the server omits is ABSENT',
      (tester) async {
        final boot = await _boot(tester);
        final c = boot.container;
        final repo = boot.repo;
        c
            .read(searchFiltersControllerProvider.notifier)
            .selectSettlement(cityId: 'city-a');

        _type(c, 'нар');
        await tester.pump();
        expect(
          c.read(searchSuggestionsProvider),
          isEmpty,
          reason: 'a place is chosen — the device cannot verify local rows',
        );
        expect(repo.calls, isEmpty);

        await tester.pump(kSearchSuggestionDebounce);
        await tester.pump();

        expect(repo.calls, hasLength(1));
        expect(repo.calls.single.cityId, 'city-a');
        final List<SearchSuggestion> rows = c.read(searchSuggestionsProvider);
        expect(rows.map((s) => s.serviceTypeSlug), contains('nail-extension'));
        expect(
          rows.map((s) => s.categoryKey),
          isNot(contains('EYELASH')),
          reason:
              'EYELASH is a category the LOCAL matcher would show but the '
              'fixture server never returns for this place — proving the '
              'server list, not a merge with the local one, is authoritative',
        );
      },
    );
  });

  group('debounce coalescing + LRU', () {
    testWidgets(
      'typing «н», «на», «нар» quickly issues exactly ONE call (for «нар»)',
      (tester) async {
        final boot = await _boot(tester);
        final c = boot.container;
        final repo = boot.repo;

        _type(c, 'н');
        // fixed-wait-ok: simulates a real keystroke gap strictly UNDER the
        // 200 ms debounce — the point is that each partial term's timer gets
        // cancelled by the next keystroke, not that any particular gap
        // elapses; there is no state to pump-until here.
        await tester.pump(const Duration(milliseconds: 50));
        _type(c, 'на');
        // fixed-wait-ok: see the note above — under the 200 ms debounce.
        await tester.pump(const Duration(milliseconds: 50));
        _type(c, 'нар');
        await tester.pump(kSearchSuggestionDebounce);
        await tester.pump();

        expect(repo.calls, hasLength(1));
        expect(repo.calls.single.term, 'нар');
      },
    );

    testWidgets('a repeated (term, place) is an LRU hit — 0 new calls', (
      tester,
    ) async {
      final boot = await _boot(tester);
      final c = boot.container;
      final repo = boot.repo;

      _type(c, 'нар');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();
      expect(repo.calls, hasLength(1));

      // Clear then retype the SAME term (a genuinely new build() run, not a
      // no-op draft write).
      _type(c, '');
      await tester.pump();
      _type(c, 'нар');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();

      expect(
        repo.calls,
        hasLength(1),
        reason: 'the second «нар» must be served from the LRU, not refetched',
      );
      expect(
        c.read(searchSuggestionsProvider).map((s) => s.serviceTypeSlug),
        contains('nail-extension'),
        reason: 'the cached rows are still served correctly on a hit',
      );
    });

    testWidgets('the SAME term in a DIFFERENT place issues a NEW call (the key '
        'includes place)', (tester) async {
      final boot = await _boot(tester);
      final c = boot.container;
      final repo = boot.repo;
      final notifier = c.read(searchFiltersControllerProvider.notifier);

      notifier.selectSettlement(cityId: 'city-a');
      _type(c, 'нар');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();
      expect(repo.calls, hasLength(1));

      notifier.selectSettlement(cityId: 'city-b');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();

      expect(
        repo.calls,
        hasLength(2),
        reason: 'a different place must never reuse the first place’s hit',
      );
      expect(repo.calls.last.cityId, 'city-b');
    });

    testWidgets(
      'place change with the list open: OLD rows clear at once, then a NEW '
      'request renders its rows; switching back is an LRU hit',
      (tester) async {
        final boot = await _boot(tester);
        final c = boot.container;
        final repo = boot.repo;
        final notifier = c.read(searchFiltersControllerProvider.notifier);

        notifier.selectSettlement(cityId: 'city-a');
        _type(c, 'нар');
        await tester.pump(kSearchSuggestionDebounce);
        await tester.pump();
        expect(
          c.read(searchSuggestionsProvider).map((s) => s.serviceTypeSlug),
          contains('nail-extension'),
        );

        // Switch to city-b, which the fixture server excludes.
        notifier.selectSettlement(cityId: 'city-b');
        await tester.pump();
        expect(
          c.read(searchSuggestionsProvider),
          isEmpty,
          reason:
              'the old rows must clear AT ONCE — a place is chosen, so '
              'no local rows can stand in either',
        );

        await tester.pump(kSearchSuggestionDebounce);
        await tester.pump();
        expect(
          c.read(searchSuggestionsProvider),
          isEmpty,
          reason: 'city-b is excluded by the fixture server',
        );
        expect(repo.calls, hasLength(2));

        // Switch BACK to city-a — an LRU hit, 0 new calls.
        notifier.selectSettlement(cityId: 'city-a');
        await tester.pump();
        expect(
          c.read(searchSuggestionsProvider).map((s) => s.serviceTypeSlug),
          contains('nail-extension'),
          reason: 'served instantly from the LRU',
        );
        expect(repo.calls, hasLength(2), reason: 'no new request was issued');
      },
    );

    testWidgets('a price/rating change issues 0 calls (select-scoped watch)', (
      tester,
    ) async {
      final boot = await _boot(tester);
      final c = boot.container;
      final repo = boot.repo;
      final notifier = c.read(searchFiltersControllerProvider.notifier);

      _type(c, 'нар');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();
      final int callsAfterFirst = repo.calls.length;
      expect(callsAfterFirst, 1);

      notifier.setMaxPrice(900);
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();

      expect(
        repo.calls.length,
        callsAfterFirst,
        reason:
            'the provider watches only cityId/districtId via select — a '
            'price edit must not re-key or refetch',
      );
    });
  });

  group('stale guard', () {
    testWidgets('a slow response for an OLD term is discarded', (tester) async {
      final Map<String, Completer<List<SearchSuggestion>>> pending =
          <String, Completer<List<SearchSuggestion>>>{};
      final boot = await _boot(
        tester,
        resolve: (String term, String? cityId, String? districtId) {
          final completer = Completer<List<SearchSuggestion>>();
          pending[term] = completer;
          return completer.future;
        },
      );
      final c = boot.container;

      _type(c, 'нар');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump(); // the 'нар' request is now in flight

      // The user keeps typing past it before it resolves.
      _type(c, 'нарощ');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump(); // the 'нарощ' request is now ALSO in flight

      // The stale 'нар' answer lands late.
      pending['нар']!.complete(const <SearchSuggestion>[
        _nailServiceSuggestion,
      ]);
      await tester.pump();

      expect(
        c.read(searchSuggestionsProvider),
        isNot(contains(_nailServiceSuggestion)),
        reason: 'a response for an old term must never overwrite a newer key',
      );

      // The current term's own answer still applies normally.
      pending['нарощ']!.complete(const <SearchSuggestion>[_lashSuggestion]);
      await tester.pump();
      expect(c.read(searchSuggestionsProvider), contains(_lashSuggestion));
    });

    testWidgets('a slow response for an OLD place is discarded', (
      tester,
    ) async {
      final Map<String?, Completer<List<SearchSuggestion>>> pending =
          <String?, Completer<List<SearchSuggestion>>>{};
      final boot = await _boot(
        tester,
        resolve: (String term, String? cityId, String? districtId) {
          final completer = Completer<List<SearchSuggestion>>();
          pending[cityId] = completer;
          return completer.future;
        },
      );
      final c = boot.container;
      final notifier = c.read(searchFiltersControllerProvider.notifier);

      notifier.selectSettlement(cityId: 'city-a');
      _type(c, 'нар');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();

      notifier.selectSettlement(cityId: 'city-b');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();

      // The stale city-a answer lands late.
      pending['city-a']!.complete(const <SearchSuggestion>[
        _nailServiceSuggestion,
      ]);
      await tester.pump();

      expect(
        c.read(searchSuggestionsProvider),
        isEmpty,
        reason: 'a response for an old PLACE must never overwrite the new one',
      );

      pending['city-b']!.complete(const <SearchSuggestion>[]);
      await tester.pump();
      expect(c.read(searchSuggestionsProvider), isEmpty);
    });
  });

  group('CancelToken supersede (mobile-perf LOW cycle-1 fix)', () {
    testWidgets(
      'a superseding keystroke cancels the PREVIOUS request’s CancelToken — '
      'a late cancellation error never surfaces as an error/empty state, and '
      'the current (second) request’s own answer still renders',
      (tester) async {
        final Map<String, Completer<List<SearchSuggestion>>> pending =
            <String, Completer<List<SearchSuggestion>>>{};
        final boot = await _boot(
          tester,
          resolve: (String term, String? cityId, String? districtId) {
            final completer = Completer<List<SearchSuggestion>>();
            pending[term] = completer;
            return completer.future;
          },
        );
        final c = boot.container;
        final repo = boot.repo;

        _type(c, 'нар');
        await tester.pump(kSearchSuggestionDebounce);
        await tester.pump(); // the 'нар' request is now in flight
        expect(repo.cancelTokens, hasLength(1));
        final CancelToken? token1 = repo.cancelTokens[0];
        expect(token1, isNotNull);
        expect(
          token1!.isCancelled,
          isFalse,
          reason: 'not superseded yet — must not be cancelled prematurely',
        );

        // The superseding keystroke — `_scheduleFetch` must cancel `token1`
        // AT ONCE, before its own 200 ms debounce even elapses.
        _type(c, 'нарощ');
        await tester.pump();
        expect(
          token1.isCancelled,
          isTrue,
          reason:
              'a newer fetch must cancel the previous one’s CancelToken '
              'immediately on supersede, not merely on eventual disposal',
        );

        await tester.pump(kSearchSuggestionDebounce);
        await tester.pump(); // the 'нарощ' request is now in flight
        expect(repo.cancelTokens, hasLength(2));
        expect(
          repo.cancelTokens[1],
          isNot(same(token1)),
          reason: 'the current request must get its OWN, fresh token',
        );

        // The superseded 'нар' request's future rejects the way a REAL
        // cancelled Dio request would — a DioException of type cancel —
        // landing late. It must be dropped silently.
        pending['нар']!.completeError(
          DioException(
            requestOptions: RequestOptions(path: '/api/v1/search/suggestions'),
            type: DioExceptionType.cancel,
          ),
        );
        await tester.pump();
        expect(
          c.read(searchSuggestionsProvider).map((s) => s.categoryKey),
          contains('EYELASH'),
          reason:
              'a cancellation must never clear/replace the current rows — '
              'the local instant row for "нарощ" must still be showing',
        );

        // The current (second) request's own answer still applies normally.
        pending['нарощ']!.complete(const <SearchSuggestion>[
          _nailServiceSuggestion,
        ]);
        await tester.pump();
        expect(
          c.read(searchSuggestionsProvider).map((s) => s.serviceTypeSlug),
          contains('nail-extension'),
        );
      },
    );

    testWidgets(
      'disposing the provider cancels its pending request’s CancelToken',
      (tester) async {
        final Map<String, Completer<List<SearchSuggestion>>> pending =
            <String, Completer<List<SearchSuggestion>>>{};
        final boot = await _boot(
          tester,
          resolve: (String term, String? cityId, String? districtId) {
            final completer = Completer<List<SearchSuggestion>>();
            pending[term] = completer;
            return completer.future;
          },
        );
        final c = boot.container;
        final repo = boot.repo;

        _type(c, 'нар');
        await tester.pump(kSearchSuggestionDebounce);
        await tester.pump(); // the 'нар' request is now in flight
        final CancelToken? token = repo.cancelTokens.single;
        expect(token, isNotNull);
        expect(token!.isCancelled, isFalse);

        c.dispose();

        expect(
          token.isCancelled,
          isTrue,
          reason:
              'ref.onDispose must cancel any still-pending fetch, not just '
              'the debounce Timer',
        );
      },
    );
  });

  group('error / 429 fallback', () {
    testWidgets('national: an error leaves the local rows in place', (
      tester,
    ) async {
      final boot = await _boot(
        tester,
        resolve: (String term, String? cityId, String? districtId) =>
            Future<List<SearchSuggestion>>.error(Exception('boom')),
      );
      final c = boot.container;

      _type(c, 'нар');
      await tester.pump();
      expect(
        c.read(searchSuggestionsProvider).map((s) => s.categoryKey),
        contains('EYELASH'),
      );

      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();

      expect(
        c.read(searchSuggestionsProvider).map((s) => s.categoryKey),
        contains('EYELASH'),
        reason: 'a national error must silently keep the local rows',
      );
    });

    testWidgets('place chosen: an error clears the list — no throw', (
      tester,
    ) async {
      final boot = await _boot(
        tester,
        resolve: (String term, String? cityId, String? districtId) =>
            Future<List<SearchSuggestion>>.error(Exception('boom')),
      );
      final c = boot.container;
      c
          .read(searchFiltersControllerProvider.notifier)
          .selectSettlement(cityId: 'city-a');

      _type(c, 'нар');
      await tester.pump(kSearchSuggestionDebounce);
      await tester.pump();

      expect(c.read(searchSuggestionsProvider), isEmpty);
    });
  });
}
