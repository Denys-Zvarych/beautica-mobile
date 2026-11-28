// M552 — the «Клієнти» list body, PROMOTED (REUSE-FIRST) out of
// `clients_screen.dart`, where it lived inside `_ClientsScreenState`.
//
// Hosts:
//   • `ClientsScreen` (the tab) — under its `VelvetTopBar`, default params:
//     a row tap opens the client's card below [ClientListView.cardBase];
//   • the client-picker sheet (`client_picker_sheet.dart`) — [onRowTap] picks
//     the client instead, [searchHint] reads «Ім'я або телефон», [host] gives it
//     its own controller instance (empty search on every open; never the
//     tab's search).
// The bodies below are the ORIGINALS moved verbatim; the three params are
// additive and default to `null`, so the tab renders byte-identically
// (`test/golden/clients_screen_golden_test.dart`, seeded pre-promotion).
//
// Search → refresh → ListView ([kMyBookingsListPadding]). States (all four
// explicit): loading skeleton · error + retry · empty roster (the search is
// HIDDEN — nothing to find) · no match for a term · rows.
//
// Search: the field's 2-char floor and 50-char cap are the backend's `q`
// bounds; the controller debounces 300 ms and sends `q` only for a valid term.
//
// Rebuild scope: the view watches only the "empty roster" bool; the list body
// is its own [Consumer], so a load-more toggle rebuilds the list alone. A
// failed pull to refresh keeps the rows and shows an error snack. On app
// resume the rows re-read "now" (a passed «Наст.» drops off — no polling).
// The tab's controller is cached for 30 s, so a round-trip keeps pages and the
// applied search; the field is re-seeded with that search on mount. A search
// still inside its debounce when the view is disposed is cancelled — it never
// fetches for a closed host.
//
// REMOVE (M544, CLI-86) — tab host only: each row sits in an end-to-start
// `Dismissible` revealing the shared [SwipeActionBackground]; the swipe (or
// the row's screen-reader action) removes it optimistically through
// [ClientListController.remove], then the undo snack with its countdown
// offers «Повернути». A failed remove puts the row back + an error snack.
// [ClientListRow] itself is untouched; the picker host never swipes.
//
// PII: names render, never log; no phone anywhere (CLI-47).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_list_removal.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_route.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_row.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_removed_snack.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/list_card_skeleton.dart';
import 'package:beautica_mobile/shared/widgets/load_more_retry_footer.dart';
import 'package:beautica_mobile/shared/widgets/salon_notice_card.dart';
import 'package:beautica_mobile/shared/widgets/search_query_field.dart';
import 'package:beautica_mobile/shared/widgets/swipe_action_background.dart';

/// The searchable, paged client list for one [scope]. Fills its parent's
/// height (the list part is `Expanded`), so the host bounds it.
class ClientListView extends ConsumerStatefulWidget {
  const ClientListView({
    super.key,
    required this.scope,
    this.cardBase,
    this.onRowTap,
    this.searchHint,
    this.host = ClientListHost.tab,
  }) : assert(
         cardBase != null || onRowTap != null,
         'ClientListView: a row needs a card route or an onRowTap.',
       );

  /// Which clients to list.
  final ClientListScope scope;

  /// The list route the card routes hang under ([clientCardRoute]); used by
  /// the default row tap.
  final String? cardBase;

  /// ADDITIVE (M552): replaces the default row tap (open the card). `null` —
  /// the «Клієнти» tab — navigates to the card exactly as before.
  final void Function(ClientSummary summary)? onRowTap;

  /// ADDITIVE (M552): the search placeholder. `null` → «Пошук за імʼям».
  final String? searchHint;

  /// ADDITIVE (M552): which controller instance backs the list.
  /// [ClientListHost.tab] (the default) is the «Клієнти» tab's cached one.
  final ClientListHost host;

  static const Key searchKey = Key('clients-search-field');
  static const Key listKey = Key('clients-list');
  static const Key skeletonKey = Key('clients-skeleton');
  static const Key errorKey = Key('clients-error');
  static const Key emptyKey = Key('clients-empty');
  static const Key noMatchKey = Key('clients-no-match');
  static const Key loadMoreRetryKey = Key('clients-load-more-retry');

  /// M544 — the swipe-to-remove wrapper of the row for [summary].
  static Key dismissibleKey(ClientSummary summary) =>
      ValueKey<String>('client-dismiss-${summary.id}');

  @override
  ConsumerState<ClientListView> createState() => _ClientListViewState();
}

class _ClientListViewState extends ConsumerState<ClientListView> {
  /// `my_bookings_screen`'s load-more threshold.
  static const double _loadMoreThreshold = 320;

  /// Seeded with the cached list's applied search (see the file header).
  late final TextEditingController _search;

  /// Ticks on resume so ONLY the list body rebuilds and re-reads its "now"
  /// (the search field stays put).
  final ValueNotifier<int> _resumeTick = ValueNotifier<int>(0);

  late final AppLifecycleListener _lifecycle;

  /// The controller that owns the last [ClientListController.setQuery]
  /// debounce — cancelled on dispose (no `ref` use there).
  ClientListController? _searchOwner;

  ClientListControllerProvider get _provider =>
      clientListControllerProvider(widget.scope, host: widget.host);

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(_provider).value?.query ?? '',
    );
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (mounted) _resumeTick.value++;
      },
    );
  }

  @override
  void dispose() {
    _searchOwner?.cancelPendingSearch();
    _lifecycle.dispose();
    _resumeTick.dispose();
    _search.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.extentAfter <= _loadMoreThreshold) {
      // The controller guards double-fetch, the last page and a failed append.
      ref.read(_provider.notifier).loadMore();
    }
    return false;
  }

  /// Pull to refresh: a failure over loaded rows keeps them + an error snack.
  Future<void> _refresh() async {
    final Object? error = await ref.read(_provider.notifier).refresh();
    if (error == null || !mounted) return;
    showErrorSnack(
      context,
      (error is Failure ? error : UnknownFailure(cause: error)).userMessage(
        context,
      ),
    );
  }

  void _tap(ClientSummary summary) {
    final void Function(ClientSummary)? onRowTap = widget.onRowTap;
    if (onRowTap != null) {
      onRowTap(summary);
      return;
    }
    final String? cardBase = widget.cardBase;
    if (cardBase == null) return;
    final String? masterId = switch (widget.scope) {
      SalonClientListScope(:final String? masterId) => masterId,
      MyClientListScope() => null,
    };
    // Drop the search field's focus before leaving: a keyboard dismissed with
    // back leaves the field focused, and the route would restore that focus
    // (reopening the keyboard) on return from the card.
    FocusManager.instance.primaryFocus?.unfocus();
    context.pushOnce<void>(
      clientCardRoute(cardBase, summary.ref, masterId: masterId),
    );
  }

  /// Failed removes per row id: part of THAT row's swipe subtree key, so only
  /// the failed row remounts.
  final Map<String, int> _removeFailures = <String, int>{};

  /// M544 — the swipe / screen-reader removal of [summary]'s row. The undo
  /// snack shows only once the write landed; a failure re-shows the row
  /// (the controller) and says so.
  Future<void> _remove(ClientSummary summary) async {
    final ProviderContainer container = ProviderScope.containerOf(
      context,
      listen: false,
    );
    final ClientRemoval? removal = await ref
        .read(_provider.notifier)
        .remove(summary);
    if (removal == null || !mounted) return;
    if (removal.error != null) {
      // The row is back (the controller); its Dismissible element may still
      // be the DISMISSED one when the failure lands before the next frame —
      // re-key so it remounts at rest instead of collapsed.
      setState(
        () => _removeFailures.update(
          summary.id,
          (int n) => n + 1,
          ifAbsent: () => 1,
        ),
      );
      showErrorSnack(context, AppLocalizations.of(context).clientsRemoveFailed);
      return;
    }
    showClientRemovedSnack(
      context,
      onUndo: () => _undo(container, summary, removal.index),
    );
  }

  /// «Повернути»: back at [index] through the controller while this view is
  /// mounted; after it left (tab switched inside the 5 s) the write still
  /// runs through the root [container] and the next mount refetches.
  Future<void> _undo(
    ProviderContainer container,
    ClientSummary summary,
    int index,
  ) async {
    final Object? error = mounted
        ? await ref.read(_provider.notifier).restore(summary, index)
        : await restoreClientToList(
            container.read(clientRepositoryProvider),
            container.invalidate,
            widget.scope,
            summary.ref,
          );
    if (error == null || !mounted) return;
    showErrorSnack(
      context,
      (error is Failure ? error : UnknownFailure(cause: error)).userMessage(
        context,
      ),
    );
  }

  /// The row, wrapped for swipe-to-remove on the tab host (see the header).
  Widget _removable(ClientSummary s, Widget row, AppLocalizations l10n) {
    if (widget.host != ClientListHost.tab) return row;
    return Semantics(
      customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
        CustomSemanticsAction(label: l10n.clientsRemoveAction): () =>
            _remove(s),
      },
      child: KeyedSubtree(
        key: ValueKey<int>(_removeFailures[s.id] ?? 0),
        child: Dismissible(
          key: ClientListView.dismissibleKey(s),
          direction: DismissDirection.endToStart,
          background: SwipeActionBackground(
            icon: Icons.person_remove_outlined,
            label: l10n.clientsRemoveSwipe,
          ),
          onDismissed: (DismissDirection _) => _remove(s),
          child: row,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // An empty roster (no clients, no term applied) has nothing to search.
    // Only this bool is watched here: the list body is its own Consumer.
    final bool emptyRoster = ref.watch(
      _provider.select((AsyncValue<ClientListState> async) {
        final ClientListState? data = async.value;
        return !async.hasError &&
            data != null &&
            data.items.isEmpty &&
            data.query == null;
      }),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!emptyRoster)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.xs,
              VelvetSpacing.lg,
              VelvetSpacing.md,
            ),
            child: SearchQueryField(
              fieldKey: ClientListView.searchKey,
              controller: _search,
              hintText: widget.searchHint ?? l10n.clientsSearchHint,
              minLengthError: l10n.clientsSearchMinLengthError,
              minLength: kClientSearchMinLength,
              maxLength: kClientSearchMaxLength,
              onChanged: (String raw) {
                final ClientListController owner = ref.read(_provider.notifier);
                _searchOwner = owner;
                owner.setQuery(raw);
              },
            ),
          ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: AppRefreshIndicator(
              onRefresh: _refresh,
              child: ValueListenableBuilder<int>(
                valueListenable: _resumeTick,
                builder: (BuildContext context, int _, Widget? _) => Consumer(
                  builder: (BuildContext context, WidgetRef ref, Widget? _) {
                    final AsyncValue<ClientListState> async = ref.watch(
                      _provider,
                    );
                    return _body(ref, async, async.value, l10n);
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(
    WidgetRef ref,
    AsyncValue<ClientListState> async,
    ClientListState? data,
    AppLocalizations l10n,
  ) {
    ListView single(Widget child, {Key? key}) => ListView(
      key: key,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: kMyBookingsListPadding,
      children: <Widget>[child],
    );

    if (async.hasError && !async.isLoading) {
      final Object error = async.error ?? const UnknownFailure();
      return single(
        ErrorState(
          failure: error is Failure ? error : UnknownFailure(cause: error),
          onRetry: () => ref.read(_provider.notifier).refresh(),
        ),
        key: ClientListView.errorKey,
      );
    }
    if (data == null || data.isSearching) {
      return single(const ListCardSkeleton(), key: ClientListView.skeletonKey);
    }
    if (data.items.isEmpty) {
      return data.query == null
          ? single(
              SalonNoticeCard(
                key: ClientListView.emptyKey,
                icon: Icons.contacts_rounded,
                title: l10n.clientsEmptyTitle,
                body: l10n.clientsEmptyBody,
              ),
            )
          : single(
              SalonNoticeCard(
                key: ClientListView.noMatchKey,
                icon: Icons.search_off_rounded,
                title: l10n.clientsNoMatchTitle,
                body: l10n.clientsNoMatchBody,
              ),
            );
    }

    final DateTime now = ref.watch(clockProvider)();
    final List<ClientSummary> rows = data.items;
    return ListView.builder(
      key: ClientListView.listKey,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: kMyBookingsListPadding,
      itemCount:
          rows.length + (data.isLoadingMore || data.loadMoreFailed ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (i >= rows.length) {
          if (data.loadMoreFailed) {
            return LoadMoreRetryFooter(
              message: l10n.clientsLoadMoreFailed,
              retryKey: ClientListView.loadMoreRetryKey,
              onRetry: () => ref.read(_provider.notifier).retryLoadMore(),
            );
          }
          return const MyBookingsLoadMoreSpinner();
        }
        final ClientSummary s = rows[i];
        return Padding(
          key: ValueKey<String>('client-${s.id}'),
          padding: EdgeInsets.only(top: i == 0 ? 0 : VelvetSpacing.md),
          child: _removable(
            s,
            RepaintBoundary(
              child: ClientListRow(summary: s, now: now, onTap: () => _tap(s)),
            ),
            l10n,
          ),
        );
      },
    );
  }
}
