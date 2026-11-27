// M510 — the card's visit timeline: a paged AsyncNotifier family per
// (scope, client), page size 20, appended on scroll ([loadMore]).
//
// NEXT VISIT (D4, CLI-89): the head comes from the card's `nextVisit` (B530 —
// the visit holding the earliest CONFIRMED booking after now in the read's
// scope), so the first load fetches the card + ONE visits page, never a
// lookahead. The card read and page 0 start together (neither waits for the
// other). [build] LISTENS to [clientCardProvider] for the same (scope, client)
// instead of watching it: a card-only refresh (a retry elsewhere) swaps
// [ClientVisitsState.pinnedNext] in place and keeps every loaded page; a
// pull-to-refresh invalidates both, so it is still one card + one page-0 read.
// A card that lands while the timeline is in error re-runs [build]. The head is picked
// from the card's visit with the same per-booking pick as the history
// ([pickNextVisit] over [clientVisitsPerBooking]); the loaded row of that
// booking, whenever its page lands, is filtered out of the history, and its
// appointment siblings stay in the history (CLI-78).
// "Now" is the injected clock, read once per build and again by [refreshNow]
// (the card calls it on app resume, so a head whose start passed while the app
// was backgrounded drops off — no polling).
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
// page 0. A new listener inside the window cancels the timer.
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
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
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

    /// The card's next visit (B530 `ClientCard.nextVisit`), the head's source.
    ClientVisit? pinnedNext,
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
      _splitCache[this] ??= _VisitsSplit.of(visits, pinnedNext, asOf);
}

/// Per-state memo of the head / history split. Keyed by the state INSTANCE,
/// so every state change (a new instance) computes it at most once.
final Expando<_VisitsSplit> _splitCache = Expando<_VisitsSplit>(
  'ClientVisitsState split',
);

/// The next-visit head and the rest of the timeline (newest first).
final class _VisitsSplit {
  const _VisitsSplit._(this.next, this.history);

  factory _VisitsSplit.of(
    List<ClientVisit> visits,
    ClientVisit? pinnedNext,
    DateTime asOf,
  ) {
    final ClientVisit? next = pinnedNext == null
        ? null
        : pickNextVisit(
            clientVisitsPerBooking(<ClientVisit>[pinnedNext]),
            asOf,
          );
    if (next == null) return _VisitsSplit._(null, visits);
    final String nextBookingId = next.firstBookingId;
    return _VisitsSplit._(
      next,
      List<ClientVisit>.unmodifiable(
        visits.where((ClientVisit v) => v.firstBookingId != nextBookingId),
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
    final ClientCardProvider cardProvider = clientCardProvider(scope, client);
    ref.listen<AsyncValue<ClientCard>>(cardProvider, _onCard);
    // Both requests start now; the page future is marked handled so a card
    // failure (awaited first) never leaves its error unhandled.
    final Future<ClientCard> cardFuture = ref.read(cardProvider.future);
    final Future<PageResponse<ClientVisit>> pageFuture =
        ref
            .read(clientRepositoryProvider)
            .getVisits(scope, client, page: 0, cancelToken: token)
          ..ignore();
    final ClientCard card = await cardFuture;
    final PageResponse<ClientVisit> page = await pageFuture;
    return ClientVisitsState(
      visits: EqualUnmodifiableListView<ClientVisit>(
        clientVisitsPerBooking(page.items),
      ),
      asOf: now,
      pinnedNext: card.nextVisit,
      page: page.page,
      hasMore: page.hasMore,
    );
  }

  /// A card change outside [build] (card-only refresh): swap the head source
  /// in place, keeping the loaded pages. While [build] runs it reads the card
  /// itself; a timeline in error is rebuilt instead — including a refresh
  /// error, which in Riverpod 3 keeps the previous pages as its value (an
  /// in-place swap would turn those stale pages back into AsyncData). A card
  /// error leaves the timeline as is (the card renders its own error).
  void _onCard(AsyncValue<ClientCard>? previous, AsyncValue<ClientCard> next) {
    if (next.isLoading || state.isLoading) return;
    final ClientCard? card = next.value;
    if (next.hasError || card == null) return;
    final ClientVisitsState? current = state.value;
    if (state.hasError || current == null) {
      ref.invalidateSelf();
      return;
    }
    if (current.pinnedNext == card.nextVisit) return;
    state = AsyncData<ClientVisitsState>(
      current.copyWith(pinnedNext: card.nextVisit),
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
      // The latest state, not [current]: the head may have been swapped by
      // [_onCard] while the page was in flight.
      final ClientVisitsState latest = state.value ?? current;
      state = AsyncData<ClientVisitsState>(
        latest.copyWith(
          visits: EqualUnmodifiableListView<ClientVisit>(<ClientVisit>[
            ...latest.visits,
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
        (state.value ?? current).copyWith(
          isLoadingMore: false,
          loadMoreFailed: true,
        ),
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
