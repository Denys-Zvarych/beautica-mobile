// M510 — the card's visit timeline: a paged AsyncNotifier family per
// (scope, client), page size 20, appended on scroll ([loadMore]).
//
// NEXT VISIT (D4): B508 pages NEWEST first, so the earliest upcoming visit sits
// at the END of the future block. The first load therefore keeps fetching pages
// (at most [kClientVisitLookaheadMaxPages]) while every loaded visit is still
// in the future and more pages exist; the head is then the true next visit.
// "Now" is the injected clock, read once per build and again by [refreshNow]
// (the card calls it on app resume, so a head whose start passed while the app
// was backgrounded moves into the history — no polling).
//
// A failed LOOKAHEAD page (1..max-1) never fails the timeline: the pages
// already loaded are kept, the lookahead stops, and the state carries
// [ClientVisitsState.loadMoreFailed] so the retry footer offers the next page
// (page 0 failing is still the timeline's error state).
//
// A failed append keeps the list and raises [ClientVisitsState.loadMoreFailed],
// which pauses auto-append until [retryLoadMore] (the scroll listener would
// otherwise re-fire the failing call every frame).
//
// STALE APPENDS: every build bumps [_generation]; an append that resolves after
// a refresh/rebuild drops its result (success OR failure) instead of
// overwriting the fresh state (the [ClientListController] pattern).
//
// ONE ROW PER BOOKING (BOOK-05): every page is flattened through
// [clientVisitsPerBooking] as it lands, so [ClientVisitsState.visits] holds one
// single-booking entry per booking (key = bookingId); paging still follows the
// server's page numbers.
//
// CACHE-FOR: once nothing listens (the card switched to another master chip),
// the instance stays cached for [kClientVisitsCacheFor] before it disposes, so
// a quick chip back-and-forth reuses the loaded pages instead of re-reading
// page 0 + the lookahead. A new listener inside the window cancels the timer.
// Every booking mutation (complete / decline / cancel / block / create) drops
// the WHOLE family through `booking_calendar_invalidation.dart`, so a card
// reopened inside the window after a mutation is always re-read.
//
// PII: nothing is logged.

import 'dart:async' show Timer;
import 'dart:developer';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';

part 'client_visits_controller.freezed.dart';
part 'client_visits_controller.g.dart';

@freezed
abstract class ClientVisitsState with _$ClientVisitsState {
  const factory ClientVisitsState({
    /// Every loaded booking (one single-item [ClientVisit] each), newest
    /// first.
    required List<ClientVisit> visits,

    /// The "now" the head was picked against.
    required DateTime asOf,
    required int page,
    required bool hasMore,
    @Default(false) bool isLoadingMore,
    @Default(false) bool loadMoreFailed,
  }) = _ClientVisitsState;

  const ClientVisitsState._();

  bool get canLoadMore => hasMore && !isLoadingMore && !loadMoreFailed;

  /// The head node: the visit with the earliest CONFIRMED item after [asOf].
  /// Computed once per state instance (memoised), not per read.
  ClientVisit? get nextVisit => _split.next;

  /// Everything except the head, newest first. Memoised like [nextVisit].
  List<ClientVisit> get history => _split.history;

  _VisitsSplit get _split =>
      _splitCache[this] ??= _VisitsSplit.of(visits, asOf);
}

/// Per-state memo of the head / history split. Keyed by the state INSTANCE,
/// so every state change (a new instance) computes it at most once.
final Expando<_VisitsSplit> _splitCache = Expando<_VisitsSplit>(
  'ClientVisitsState split',
);

/// The next-visit head and the rest of the timeline (newest first).
final class _VisitsSplit {
  const _VisitsSplit._(this.next, this.history);

  factory _VisitsSplit.of(List<ClientVisit> visits, DateTime asOf) {
    final ClientVisit? next = pickNextVisit(visits, asOf);
    if (next == null) return _VisitsSplit._(null, visits);
    return _VisitsSplit._(
      next,
      List<ClientVisit>.unmodifiable(
        visits.where((ClientVisit v) => v.visitKey != next.visitKey),
      ),
    );
  }

  final ClientVisit? next;
  final List<ClientVisit> history;
}

/// How long an unlistened [ClientVisitsController] instance stays cached.
const Duration kClientVisitsCacheFor = Duration(seconds: 30);

@riverpod
class ClientVisitsController extends _$ClientVisitsController {
  static const String _tag = 'feature.clients';

  CancelToken? _token;

  /// Bumped on every build; a load-more that resolves under an older value is
  /// stale and dropped.
  int _generation = 0;

  @override
  Future<ClientVisitsState> build(
    ClientListScope scope,
    ClientRef client,
  ) async {
    final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
    _generation++;
    final CancelToken token = _token = CancelToken();
    ref.onDispose(token.cancel);
    _cacheFor();
    final DateTime now = ref.read(clockProvider)();
    if (userId == null) {
      return ClientVisitsState(
        visits: const <ClientVisit>[],
        asOf: now,
        page: 0,
        hasMore: false,
      );
    }
    final ClientRepository repo = ref.read(clientRepositoryProvider);
    PageResponse<ClientVisit> page = await repo.getVisits(
      scope,
      client,
      page: 0,
      cancelToken: token,
    );
    final List<ClientVisit> visits = clientVisitsPerBooking(page.items);
    int pages = 1;
    bool lookaheadFailed = false;
    while (page.hasMore &&
        pages < kClientVisitLookaheadMaxPages &&
        nextVisitLookaheadPending(visits, now)) {
      try {
        page = await repo.getVisits(
          scope,
          client,
          page: page.page + 1,
          cancelToken: token,
        );
      } catch (_) {
        // Disposed / superseded: the result is never read anyway.
        if (token.isCancelled) rethrow;
        log('visits lookahead failed', name: _tag, level: 900);
        lookaheadFailed = true;
        break;
      }
      visits.addAll(clientVisitsPerBooking(page.items));
      pages++;
    }
    return ClientVisitsState(
      visits: List<ClientVisit>.unmodifiable(visits),
      asOf: now,
      page: page.page,
      hasMore: page.hasMore,
      loadMoreFailed: lookaheadFailed,
    );
  }

  /// Re-reads "now" (the injected clock) so the head / history split is
  /// recomputed against it — the card calls this on app resume. No request.
  void refreshNow() {
    final ClientVisitsState? current = state.value;
    if (state.isLoading || current == null) return;
    final DateTime now = ref.read(clockProvider)();
    if (now == current.asOf) return;
    state = AsyncData<ClientVisitsState>(current.copyWith(asOf: now));
  }

  /// The standard cache-for pattern: keep alive while unlistened for
  /// [kClientVisitsCacheFor], then release.
  void _cacheFor() {
    // The link type is not exported by riverpod 3's public API.
    final link = ref.keepAlive();
    Timer? timer;
    ref
      ..onCancel(() {
        timer?.cancel();
        timer = Timer(kClientVisitsCacheFor, link.close);
      })
      ..onResume(() => timer?.cancel())
      ..onDispose(() => timer?.cancel());
  }

  /// Appends the next page. No-op while loading or reloading (pull-to-refresh),
  /// exhausted or after a failed append.
  Future<void> loadMore() async {
    final ClientVisitsState? current = state.value;
    if (state.isLoading || current == null || !current.canLoadMore) return;
    final int generation = _generation;
    state = AsyncData<ClientVisitsState>(current.copyWith(isLoadingMore: true));
    try {
      final PageResponse<ClientVisit> page = await ref
          .read(clientRepositoryProvider)
          .getVisits(
            scope,
            client,
            page: current.page + 1,
            cancelToken: _token,
          );
      if (!ref.mounted || generation != _generation) return;
      state = AsyncData<ClientVisitsState>(
        current.copyWith(
          visits: List<ClientVisit>.unmodifiable(<ClientVisit>[
            ...current.visits,
            ...clientVisitsPerBooking(page.items),
          ]),
          page: page.page,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      log('visits loadMore failed', name: _tag, level: 900);
      state = AsyncData<ClientVisitsState>(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }

  /// Retries a failed append (clears the pause, re-issues the same page).
  Future<void> retryLoadMore() async {
    final ClientVisitsState? current = state.value;
    if (current == null || !current.loadMoreFailed) return;
    state = AsyncData<ClientVisitsState>(
      current.copyWith(loadMoreFailed: false),
    );
    await loadMore();
  }
}
