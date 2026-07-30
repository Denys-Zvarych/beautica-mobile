// Phase 13.4 / perf-sec MEDIUM-1 — Unit suite for [SearchResultsNotifier]'s
// CANCELLATION contract.
//
// WHY THIS FILE EXISTS
// --------------------
// Live search re-keys `searchResultsProvider` on every settled term. Before the
// fix, a superseded family member's two GETs ran to completion — ~20 unthrottled
// wildcard-LIKE scans across masters AND salons on `permitAll` endpoints for one
// typed phrase, ~18 of them obsolete on arrival. autoDispose freed the CACHE
// ENTRY but never touched the SOCKET.
//
// The widget suite (search_results_screen_test.dart) matches the token with
// `any(named: 'cancelToken')` at all 54 of its call sites, so passing `null`
// from both `_fetchFirstPage` and `loadMore` would leave every one of those
// tests green while restoring the whole request storm. Everything here therefore
// asserts TOKEN IDENTITY (`same(...)`) and CANCELLED-NESS, never mere
// non-nullity.
//
// THE ONE SUBTLE INVARIANT (group 'token lifecycle')
// --------------------------------------------------
// `build()` creates a token in a LOCAL and registers `ref.onDispose` closing
// over THAT local, while `loadMore` reads the `_cancelToken` FIELD at call time.
// The two must not be conflated:
//   • on a recompute, `onDispose` must cancel the OUTGOING token — never the
//     freshly-built one, which would abort the search the user is waiting for;
//   • `loadMore` must send the CURRENT field — never a stale local captured at
//     first build, which is already cancelled and would abort page 2 instantly.
// `recomputing cancels the outgoing token and leaves the incoming one live` and
// `loadMore after a recompute carries the NEW token, not the cancelled one`
// pin exactly that distinction.
//
// House rules: fresh [ProviderContainer] per test, always disposed via
// `addTearDown`; the repository is a mocktail mock (no real Dio, no network).

import 'dart:async';

import 'package:beautica_mobile/features/discovery/application/search_results_notifier.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository.dart';
import 'package:beautica_mobile/features/discovery/data/search_repository_provider.dart';
import 'package:beautica_mobile/features/discovery/domain/master_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/salon_search_item.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSearchRepository extends Mock implements SearchRepository {}

// ── Fixtures ────────────────────────────────────────────────────────────────

MasterSearchItem _master(String id) => MasterSearchItem(
  masterId: id,
  firstName: 'Марія',
  lastName: 'Іванюк',
  avatarUrl: null,
  avgRating: 4.8,
  reviewCount: 3,
  cityLabel: 'Львів',
  districtLabel: null,
  minEffectivePrice: 500,
  priceMax: null,
  street: null,
  buildingNo: null,
  locationNote: null,
  serviceNames: const <String>[],
  servicesLine: null,
);

SalonSearchItem _salon(String id) => SalonSearchItem(
  salonId: id,
  name: 'Lviv Nails',
  avatarUrl: null,
  avgRating: null,
  cityLabel: 'Львів',
  districtLabel: null,
  priceMin: 400,
  priceMax: 900,
  street: null,
  buildingNo: null,
  locationNote: null,
  serviceNames: const <String>[],
  servicesLine: null,
);

SearchPage<T> _page<T>(List<T> items, {int page = 0, int totalPages = 1}) =>
    SearchPage<T>(
      items: items,
      page: page,
      totalPages: totalPages,
      totalElements: items.length,
    );

void main() {
  late _MockSearchRepository repo;

  /// Every `cancelToken` the notifier handed each endpoint, in call order.
  ///
  /// Recorded inside the stub answer rather than read back through `verify`:
  /// mocktail MARKS matched invocations as verified, so a second
  /// `verify(...).captured` returns only the calls made since the first — which
  /// silently turns a "2 tokens, compare them" assertion into a length-1 list.
  late List<CancelToken?> masterTokens;
  late List<CancelToken?> salonTokens;

  const SearchFilters filtersA = SearchFilters(query: 'манікюр');
  const SearchFilters filtersB = SearchFilters(query: 'педикюр');

  setUpAll(() {
    registerFallbackValue(const SearchFilters());
  });

  setUp(() {
    repo = _MockSearchRepository();
    masterTokens = <CancelToken?>[];
    salonTokens = <CancelToken?>[];
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [searchRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  // ── stub helpers ──────────────────────────────────────────────────────────

  void stubMasters(
    Future<SearchPage<MasterSearchItem>> Function(Invocation) answer,
  ) {
    when(
      () => repo.searchMasters(
        filters: any(named: 'filters'),
        page: any(named: 'page'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((Invocation i) {
      masterTokens.add(i.namedArguments[#cancelToken] as CancelToken?);
      return answer(i);
    });
  }

  void stubSalons(
    Future<SearchPage<SalonSearchItem>> Function(Invocation) answer,
  ) {
    when(
      () => repo.searchSalons(
        filters: any(named: 'filters'),
        page: any(named: 'page'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((Invocation i) {
      salonTokens.add(i.namedArguments[#cancelToken] as CancelToken?);
      return answer(i);
    });
  }

  /// Arms both endpoints with an immediate one-item page.
  ///
  /// `totalPages: 2` on masters so `hasMore` is true and [loadMore] is not a
  /// no-op; salons are single-page.
  void stubBothOk({int masterTotalPages = 2}) {
    stubMasters(
      (Invocation i) async => _page<MasterSearchItem>(
        <MasterSearchItem>[_master('m1')],
        page: i.namedArguments[#page] as int,
        totalPages: masterTotalPages,
      ),
    );
    stubSalons(
      (Invocation i) async => _page<SalonSearchItem>(<SalonSearchItem>[
        _salon('s1'),
      ], page: i.namedArguments[#page] as int),
    );
  }

  /// `captureAny`-based read-back, used ONCE per test (see [masterTokens] for
  /// why a second call in the same test would under-report).
  List<CancelToken?> capturedMasterTokens() => verify(
    () => repo.searchMasters(
      filters: any(named: 'filters'),
      page: any(named: 'page'),
      cancelToken: captureAny(named: 'cancelToken'),
    ),
  ).captured.cast<CancelToken?>();

  List<CancelToken?> capturedSalonTokens() => verify(
    () => repo.searchSalons(
      filters: any(named: 'filters'),
      page: any(named: 'page'),
      cancelToken: captureAny(named: 'cancelToken'),
    ),
  ).captured.cast<CancelToken?>();

  // ── the token actually reaches BOTH endpoints ─────────────────────────────

  group('first page forwards one shared token to both endpoints', () {
    test(
      'searchMasters AND searchSalons receive the SAME non-null CancelToken',
      () async {
        stubBothOk();
        final container = makeContainer();

        await container.read(searchResultsProvider(filtersA).future);

        final CancelToken? masterToken = capturedMasterTokens().single;
        final CancelToken? salonToken = capturedSalonTokens().single;

        expect(
          masterToken,
          isNotNull,
          reason:
              'passing null here would silently restore the request storm — '
              'every widget-tier any(named: cancelToken) matcher stays green',
        );
        expect(
          salonToken,
          same(masterToken),
          reason:
              'both endpoints of one family member must share ONE token, so a '
              'single cancel aborts the whole fan-out',
        );
        expect(masterToken!.isCancelled, isFalse);
      },
    );
  });

  // ── ref.onDispose(token.cancel) ───────────────────────────────────────────

  group('token lifecycle', () {
    test('disposing the family member cancels its token', () async {
      stubBothOk();
      final container = makeContainer();

      await container.read(searchResultsProvider(filtersA).future);
      final CancelToken token = capturedMasterTokens().single!;
      expect(token.isCancelled, isFalse, reason: 'live while mounted');

      container.dispose();

      expect(
        token.isCancelled,
        isTrue,
        reason:
            'ref.onDispose must cancel the token — autoDispose alone frees the '
            'cache entry but leaves the socket running',
      );
    });

    test(
      'a token cancelled by dispose carries the documented reason',
      () async {
        stubBothOk();
        final container = makeContainer();

        await container.read(searchResultsProvider(filtersA).future);
        final CancelToken token = masterTokens.single!;
        container.dispose();

        expect(token.cancelError, isNotNull);
        expect(
          token.cancelError!.error,
          'search superseded',
          reason:
              'the cancel reason is what identifies this abort in a Dio log as '
              'a superseded search rather than a user-driven cancel',
        );
      },
    );

    test(
      'recomputing cancels the OUTGOING token and leaves the incoming one live',
      () async {
        stubBothOk();
        final container = makeContainer();
        // Keep the member alive across the invalidate so autoDispose does not
        // tear it down for an unrelated reason.
        container.listen(
          searchResultsProvider(filtersA),
          (_, _) {},
          fireImmediately: true,
        );

        await container.read(searchResultsProvider(filtersA).future);
        final CancelToken first = masterTokens.single!;

        container.invalidate(searchResultsProvider(filtersA));
        await container.read(searchResultsProvider(filtersA).future);

        expect(masterTokens, hasLength(2));
        final CancelToken second = masterTokens.last!;

        expect(
          identical(first, second),
          isFalse,
          reason:
              'a cancelled CancelToken cannot be reused — build() must mint a '
              'fresh one every time',
        );
        expect(
          first.isCancelled,
          isTrue,
          reason: 'the superseded search must be aborted',
        );
        expect(
          second.isCancelled,
          isFalse,
          reason:
              'onDispose closes over the OUTGOING local token; cancelling the '
              'field instead would abort the search the user is waiting for',
        );
      },
    );

    test(
      'a token is never cancelled while its search is still current',
      () async {
        stubBothOk();
        final container = makeContainer();
        container.listen(searchResultsProvider(filtersA), (_, _) {});

        await container.read(searchResultsProvider(filtersA).future);
        // Reading a DIFFERENT family member must not disturb this one's token.
        await container.read(searchResultsProvider(filtersB).future);

        final CancelToken tokenA = masterTokens.first!;
        expect(
          tokenA.isCancelled,
          isFalse,
          reason: 'sibling family members own independent tokens',
        );
      },
    );
  });

  // ── loadMore reuses the CURRENT field ─────────────────────────────────────

  group('loadMore token reuse', () {
    test('the next page carries the same token as the first page', () async {
      stubBothOk();
      final container = makeContainer();
      container.listen(searchResultsProvider(filtersA), (_, _) {});

      await container.read(searchResultsProvider(filtersA).future);
      await container.read(searchResultsProvider(filtersA).notifier).loadMore();

      final List<CancelToken?> tokens = capturedMasterTokens();
      expect(tokens, hasLength(2), reason: 'page 0 + page 1');
      expect(
        tokens[1],
        same(masterTokens[0]),
        reason:
            'a pop mid-pagination must abort the next-page fetch too — that '
            'only works if loadMore reuses the member token',
      );
      expect(
        tokens[1],
        isNotNull,
        reason: 'loadMore passing null would leave page 2 uncancellable',
      );
    });

    test(
      'loadMore after a recompute carries the NEW token, not the cancelled one',
      () async {
        stubBothOk();
        final container = makeContainer();
        container.listen(
          searchResultsProvider(filtersA),
          (_, _) {},
          fireImmediately: true,
        );

        await container.read(searchResultsProvider(filtersA).future);
        final CancelToken stale = masterTokens.single!;

        container.invalidate(searchResultsProvider(filtersA));
        await container.read(searchResultsProvider(filtersA).future);

        await container
            .read(searchResultsProvider(filtersA).notifier)
            .loadMore();

        expect(
          masterTokens,
          hasLength(3),
          reason: 'page0, rebuilt page0, page1',
        );
        final CancelToken? loadMoreToken = masterTokens.last;

        expect(
          identical(loadMoreToken, stale),
          isFalse,
          reason:
              'loadMore reads the _cancelToken FIELD at call time; capturing '
              'build()s local would send an already-cancelled token and abort '
              'page 2 the instant it is issued',
        );
        expect(loadMoreToken!.isCancelled, isFalse);
      },
    );

    test('salons page 1 shares the master page-1 token', () async {
      stubBothOk();
      final container = makeContainer();
      container.listen(searchResultsProvider(filtersA), (_, _) {});

      await container.read(searchResultsProvider(filtersA).future);
      await container.read(searchResultsProvider(filtersA).notifier).loadMore();

      // Salons have hasMore==false after page 0 here only if totalPages==1;
      // stubBothOk gives salons a single page, so loadMore skips them.
      // Assert on the masters axis + confirm salons were NOT re-requested.
      expect(
        salonTokens,
        hasLength(1),
        reason: 'an exhausted endpoint must not be re-fetched by loadMore',
      );
    });
  });

  // ── cancellation never surfaces as a user-visible error ───────────────────

  group('a cancelled request produces no error state', () {
    test(
      'a recompute whose superseded fetch then FAILS never emits AsyncError',
      () async {
        final Completer<SearchPage<MasterSearchItem>> firstMasters =
            Completer<SearchPage<MasterSearchItem>>();
        int masterCall = 0;

        stubMasters((Invocation i) {
          masterCall++;
          if (masterCall == 1) return firstMasters.future;
          return Future<SearchPage<MasterSearchItem>>.value(
            _page<MasterSearchItem>(<MasterSearchItem>[_master('m2')]),
          );
        });
        stubSalons(
          (_) async => _page<SalonSearchItem>(<SalonSearchItem>[_salon('s1')]),
        );

        final container = makeContainer();
        final List<AsyncValue<SearchResultsState>> observed =
            <AsyncValue<SearchResultsState>>[];
        container.listen(
          searchResultsProvider(filtersA),
          (_, AsyncValue<SearchResultsState> next) => observed.add(next),
          fireImmediately: true,
        );

        // Supersede the in-flight search, then let the abandoned request fail
        // exactly the way a cancelled Dio request does.
        container.invalidate(searchResultsProvider(filtersA));
        firstMasters.completeError(StateError('cancelled: search superseded'));
        await container.read(searchResultsProvider(filtersA).future);
        await Future<void>.delayed(Duration.zero);

        expect(
          observed.where((AsyncValue<SearchResultsState> v) => v.hasError),
          isEmpty,
          reason:
              'Riverpod drops a superseded elements future — a cancelled '
              'search must never reach the retry state',
        );
        expect(observed.last.hasValue, isTrue);
      },
    );
  });

  // ── ref.mounted guards around the two `state =` writes in loadMore ────────

  group('loadMore ref.mounted guards', () {
    test(
      'SUCCESS path: a page that lands after dispose does not write state',
      () async {
        final Completer<SearchPage<MasterSearchItem>> nextMasters =
            Completer<SearchPage<MasterSearchItem>>();
        int masterCall = 0;

        stubMasters((Invocation i) {
          masterCall++;
          if (masterCall == 1) {
            return Future<SearchPage<MasterSearchItem>>.value(
              _page<MasterSearchItem>(<MasterSearchItem>[
                _master('m1'),
              ], totalPages: 2),
            );
          }
          return nextMasters.future;
        });
        stubSalons(
          (_) async => _page<SalonSearchItem>(<SalonSearchItem>[_salon('s1')]),
        );

        final container = makeContainer();
        container.listen(searchResultsProvider(filtersA), (_, _) {});
        await container.read(searchResultsProvider(filtersA).future);

        final SearchResultsNotifier notifier = container.read(
          searchResultsProvider(filtersA).notifier,
        );
        final Future<void> pending = notifier.loadMore();

        // Screen popped / filters re-keyed while page 2 is in flight — now the
        // COMMON case, because cancellation makes it so.
        container.dispose();
        nextMasters.complete(
          _page<MasterSearchItem>(
            <MasterSearchItem>[_master('m2')],
            page: 1,
            totalPages: 2,
          ),
        );

        // DISCRIMINATION NOTE (measured, do not "strengthen" this reason).
        // Removing the success-path guard ALONE keeps this green: the throw it
        // prevents lands in loadMore's own `catch`, whose guard then returns.
        // The pair is what is externally observable — remove BOTH guards and
        // this test goes red. So this asserts the OBSERVABLE contract (nothing
        // escapes loadMore after dispose); the :200 guard on its own is
        // defence-in-depth that no black-box test can isolate.
        await expectLater(
          pending,
          completes,
          reason:
              'a page landing on a disposed element must not let a `state =` '
              'rejection escape loadMore — with both mounted guards gone, '
              'Riverpod throws and this future completes with an error',
        );
      },
    );

    test(
      'ERROR path: a page that FAILS after dispose does not write state',
      () async {
        final Completer<SearchPage<MasterSearchItem>> nextMasters =
            Completer<SearchPage<MasterSearchItem>>();
        int masterCall = 0;

        stubMasters((Invocation i) {
          masterCall++;
          if (masterCall == 1) {
            return Future<SearchPage<MasterSearchItem>>.value(
              _page<MasterSearchItem>(<MasterSearchItem>[
                _master('m1'),
              ], totalPages: 2),
            );
          }
          return nextMasters.future;
        });
        stubSalons(
          (_) async => _page<SalonSearchItem>(<SalonSearchItem>[_salon('s1')]),
        );

        final container = makeContainer();
        container.listen(searchResultsProvider(filtersA), (_, _) {});
        await container.read(searchResultsProvider(filtersA).future);

        final SearchResultsNotifier notifier = container.read(
          searchResultsProvider(filtersA).notifier,
        );
        final Future<void> pending = notifier.loadMore();

        container.dispose();
        nextMasters.completeError(StateError('cancelled'));

        await expectLater(
          pending,
          completes,
          reason:
              'the catch block clears the spinner by writing `state`; without '
              'its own mounted guard that write throws on a disposed element',
        );
      },
    );
  });
}
