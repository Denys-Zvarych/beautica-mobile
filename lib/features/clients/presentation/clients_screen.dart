// M509 — «Клієнти»: the provider's client list (B507), one screen for every
// provider role and both client kinds (CLI-46 / CLI-47).
//
// Ported literally from the approved preview
// `docs/signup-designs/ClientsTab/lib/screens/clients_screen.dart`, laid out
// like the master «Архів» / «Записи» tab lists: Scaffold(base) →
// SafeArea(bottom: false) → [VelvetTopBar] (no back — a tab root) → search →
// refresh → ListView ([kMyBookingsListPadding]), the bar in
// `Scaffold.bottomNavigationBar` (the `ProfileScaffold.bottomNavBar` rule: never
// nested in the body's SafeArea).
//
// Hosts — the screen is scope-agnostic; the host supplies the scope, the card
// base route and the bar:
//   salon shell (owner / admin)  scope salon(salonId)            bar: the shell's
//   owner master mode            scope salon(salonId, masterId)  bar: master bar
//   independent master           scope me                        bar: master bar
//   salon master                 scope me                        bar: master bar
//
// Blocks are shipped widgets: [ClientListRow] (the booking client strip),
// `ListCardSkeleton` (loading), `SalonNoticeCard` (empty / no match),
// `ErrorState` + retry, `MyBookingsLoadMoreSpinner` (paging footer, threshold
// 320 like «Мої записи») and `AppRefreshIndicator`.
//
// States (all four explicit): loading skeleton · error + retry · empty roster
// (the search is HIDDEN — nothing to find) · no match for a term · rows.
//
// Search: the field's 2-char floor and 50-char cap are the backend's `q`
// bounds; the controller debounces 300 ms and sends `q` only for a valid term.
// A row tap opens the client's card (M510) — a registered row at `user/:id`,
// a guest at `guest/:bookingId` below [cardBase].
//
// PII: names render, never log; no phone anywhere (CLI-47).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_route.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/list_card_skeleton.dart';
import 'package:beautica_mobile/shared/widgets/load_more_retry_footer.dart';
import 'package:beautica_mobile/shared/widgets/salon_notice_card.dart';
import 'package:beautica_mobile/shared/widgets/search_query_field.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';

/// The «Клієнти» tab body for one [scope].
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({
    super.key,
    required this.scope,
    required this.cardBase,
    this.bottomNavBar,
  });

  /// Which clients to list.
  final ClientListScope scope;

  /// The list route the card routes hang under ([clientCardRoute]).
  final String cardBase;

  /// The host's bottom bar, mounted in `Scaffold.bottomNavigationBar`. `null`
  /// when an enclosing shell already supplies it (the salon shell).
  final Widget? bottomNavBar;

  static const Key screenKey = Key('clients-screen');
  static const Key searchKey = Key('clients-search-field');
  static const Key listKey = Key('clients-list');
  static const Key skeletonKey = Key('clients-skeleton');
  static const Key errorKey = Key('clients-error');
  static const Key emptyKey = Key('clients-empty');
  static const Key noMatchKey = Key('clients-no-match');
  static const Key loadMoreRetryKey = Key('clients-load-more-retry');

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  /// `my_bookings_screen`'s load-more threshold.
  static const double _loadMoreThreshold = 320;

  final TextEditingController _search = TextEditingController();

  ClientListControllerProvider get _provider =>
      clientListControllerProvider(widget.scope);

  @override
  void dispose() {
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

  Future<void> _refresh() => ref.read(_provider.notifier).refresh();

  void _open(ClientSummary summary) {
    final String? masterId = switch (widget.scope) {
      SalonClientListScope(:final String? masterId) => masterId,
      MyClientListScope() => null,
    };
    // Drop the search field's focus before leaving: a keyboard dismissed with
    // back leaves the field focused, and the route would restore that focus
    // (reopening the keyboard) on return from the card.
    FocusManager.instance.primaryFocus?.unfocus();
    context.pushOnce<void>(
      clientCardRoute(widget.cardBase, summary.ref, masterId: masterId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ClientListState> async = ref.watch(_provider);
    final ClientListState? data = async.value;
    // An empty roster (no clients, no term applied) has nothing to search.
    final bool emptyRoster =
        !async.hasError &&
        data != null &&
        data.items.isEmpty &&
        data.query == null;

    return Scaffold(
      key: ClientsScreen.screenKey,
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            VelvetTopBar(title: l10n.clientsTitle),
            if (!emptyRoster)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.lg,
                  VelvetSpacing.xs,
                  VelvetSpacing.lg,
                  VelvetSpacing.md,
                ),
                child: SearchQueryField(
                  fieldKey: ClientsScreen.searchKey,
                  controller: _search,
                  hintText: l10n.clientsSearchHint,
                  minLengthError: l10n.clientsSearchMinLengthError,
                  minLength: kClientSearchMinLength,
                  maxLength: kClientSearchMaxLength,
                  onChanged: (String raw) =>
                      ref.read(_provider.notifier).setQuery(raw),
                ),
              ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: AppRefreshIndicator(
                  onRefresh: _refresh,
                  child: _body(async, data, l10n),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: widget.bottomNavBar,
    );
  }

  Widget _body(
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
        key: ClientsScreen.errorKey,
      );
    }
    if (data == null || data.isSearching) {
      return single(const ListCardSkeleton(), key: ClientsScreen.skeletonKey);
    }
    if (data.items.isEmpty) {
      return data.query == null
          ? single(
              SalonNoticeCard(
                key: ClientsScreen.emptyKey,
                icon: Icons.contacts_rounded,
                title: l10n.clientsEmptyTitle,
                body: l10n.clientsEmptyBody,
              ),
            )
          : single(
              SalonNoticeCard(
                key: ClientsScreen.noMatchKey,
                icon: Icons.search_off_rounded,
                title: l10n.clientsNoMatchTitle,
                body: l10n.clientsNoMatchBody,
              ),
            );
    }

    final DateTime now = ref.watch(clockProvider)();
    final List<ClientSummary> rows = data.items;
    return ListView.builder(
      key: ClientsScreen.listKey,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: kMyBookingsListPadding,
      itemCount:
          rows.length + (data.isLoadingMore || data.loadMoreFailed ? 1 : 0),
      itemBuilder: (BuildContext context, int i) {
        if (i >= rows.length) {
          if (data.loadMoreFailed) {
            return LoadMoreRetryFooter(
              message: l10n.clientsLoadMoreFailed,
              retryKey: ClientsScreen.loadMoreRetryKey,
              onRetry: () => ref.read(_provider.notifier).retryLoadMore(),
            );
          }
          return const MyBookingsLoadMoreSpinner();
        }
        final ClientSummary s = rows[i];
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : VelvetSpacing.md),
          child: RepaintBoundary(
            key: ValueKey<String>('client-${s.id}'),
            child: ClientListRow(summary: s, now: now, onTap: () => _open(s)),
          ),
        );
      },
    );
  }
}
