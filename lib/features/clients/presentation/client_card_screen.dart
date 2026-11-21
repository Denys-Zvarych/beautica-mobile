// M510 — the provider's client card (CLI-48), ported from
// `docs/signup-designs/ClientCardVariants/lib/screens/client_card_screen.dart`.
//
// ONE layout for every provider role and both client kinds (CLI-D07): nothing
// here reads the client's kind. Only DATA differs — no photo → monogram, no
// `phone` → no phone chip, count 0 → «Ще немає оцінок» (not tappable).
//
//   avatar · name · «Заблоковано» · [phone chip] [rating chip]
//   «Наступний візит» head node (D4)
//   «Історія візитів» — month-grouped, newest first, paged
//
// PHONE, fail closed (D5): the chip needs the server's `phone` AND
// `canSeeClientPhone(role)`, so a SALON_MASTER never sees one even if a buggy
// server sends it.
//
// No master name, counters, kind label or «З нами з» (D2/D3). A visit card opens
// booking detail of its first item. 404 → «Клієнта не знайдено» (uniform, also
// a guest attached to an account since the list loaded, B527).
//
// PII: name, photo and phone are rendered, never logged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_visits_controller.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_route.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/blocked_tag.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/phone_link.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_readout.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_scaffold.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/load_more_retry_footer.dart';
import 'package:beautica_mobile/shared/widgets/public_profile_skeleton.dart';
import 'package:beautica_mobile/shared/widgets/salon_notice_card.dart';

/// The client card. See the file header.
class ClientCardScreen extends ConsumerStatefulWidget {
  const ClientCardScreen({
    super.key,
    required this.scope,
    required this.client,
    required this.cardBase,
    required this.bookingRoute,
  });

  /// Which clients the card is read from (salon / salon + masterId / me).
  final ClientListScope scope;
  final ClientRef client;

  /// The list route the card hangs under ([clientRatingRoute] base).
  final String cardBase;

  /// The booking-detail route of the host shell for a visit's first booking.
  final String Function(String bookingId) bookingRoute;

  static const Key screenKey = Key('client-card-screen');
  static const Key backKey = Key('btn-back-client-card');
  static const Key nameKey = Key('client-card-name');
  static const Key phoneChipKey = Key('phone-link');
  static const Key ratingChipKey = Key('rating-link');
  static const Key nextVisitKey = Key('client-next-visit');
  static const Key historyEmptyKey = Key('client-history-empty');
  static const Key notFoundKey = Key('client-card-not-found');
  static const Key errorKey = Key('client-card-error');
  static const Key skeletonKey = Key('client-card-skeleton');
  static const Key visitsErrorKey = Key('client-visits-error');
  static const Key visitsRetryMoreKey = Key('client-visits-retry-more');

  static Key visitKey(String visitKey) => Key('client-visit-$visitKey');

  @override
  ConsumerState<ClientCardScreen> createState() => _ClientCardScreenState();
}

class _ClientCardScreenState extends ConsumerState<ClientCardScreen> {
  /// `my_bookings_screen`'s load-more threshold.
  static const double _loadMoreThreshold = 320;

  ClientCardProvider get _cardProvider =>
      clientCardProvider(widget.scope, widget.client);

  ClientVisitsControllerProvider get _visitsProvider =>
      clientVisitsControllerProvider(widget.scope, widget.client);

  String? get _masterId => switch (widget.scope) {
    SalonClientListScope(:final String? masterId) => masterId,
    MyClientListScope() => null,
  };

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.extentAfter <= _loadMoreThreshold) {
      // The controller guards double-fetch, the last page and a failed append.
      ref.read(_visitsProvider.notifier).loadMore();
    }
    return false;
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(_cardProvider)
      ..invalidate(_visitsProvider);
    try {
      await ref.read(_cardProvider.future);
    } catch (_) {
      // The error state renders it; the indicator just stops.
    }
  }

  void _openRating() => context.pushOnce<void>(
    clientRatingRoute(widget.cardBase, widget.client, masterId: _masterId),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ClientCard> card = ref.watch(_cardProvider);
    // Both reads start together, but only the timeline sliver WATCHES the
    // visits: a listen keeps the fetch alive without rebuilding the header and
    // chips on every loading-more toggle.
    ref.listen<AsyncValue<ClientVisitsState>>(_visitsProvider, (_, _) {});
    final UserRole? role = ref.watch(authProvider.select(authUserRoleOrNull));

    final (Widget body, List<Widget> slivers) = card.when(
      loading: () => (const _CardSkeleton(), const <Widget>[]),
      error: (Object e, StackTrace _) {
        final Failure failure = e is Failure ? e : UnknownFailure(cause: e);
        if (failure is NotFoundFailure) {
          return (
            ErrorState(
              key: ClientCardScreen.notFoundKey,
              failure: failure,
              message: l10n.clientNotFound,
            ),
            const <Widget>[],
          );
        }
        return (
          ErrorState(
            key: ClientCardScreen.errorKey,
            failure: failure,
            onRetry: () => ref
              ..invalidate(_cardProvider)
              ..invalidate(_visitsProvider),
          ),
          const <Widget>[],
        );
      },
      data: (ClientCard c) => (
        _CardHeader(
          card: c,
          // D5 — fail closed on the role; no `kind` check.
          showPhone: canSeeClientPhone(role),
          onOpenRating: _openRating,
          clipboard: ref.read(clipboardServiceProvider),
        ),
        <Widget>[
          _VisitsTimeline(
            scope: widget.scope,
            client: widget.client,
            onOpenBooking: (String bookingId) =>
                context.pushOnce<void>(widget.bookingRoute(bookingId)),
          ),
        ],
      ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ProfileScaffold(
        key: ClientCardScreen.screenKey,
        title: l10n.clientCardTitle,
        backKey: ClientCardScreen.backKey,
        backSemanticLabel: l10n.registerBackStep,
        onRefresh: _refresh,
        slivers: slivers,
        child: body,
      ),
    );
  }
}

/// Loading: the shared public-profile skeleton (no tabs) + the bookings one.
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: ClientCardScreen.skeletonKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PublicProfileSkeleton(showTabs: false),
        SizedBox(height: VelvetSpacing.lg),
        BookingsSkeleton(count: 2),
      ],
    );
  }
}

/// Avatar · name · tag · chips. Never watches the visits.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.card,
    required this.showPhone,
    required this.onOpenRating,
    required this.clipboard,
  });

  final ClientCard card;
  final ClipboardService clipboard;
  final bool showPhone;
  final VoidCallback onOpenRating;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool hasPhoto = card.avatarUrl != null;
    final String? phone = showPhone ? card.phone : null;
    final bool rated = card.displayRating != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // A monogram does not need the hero size of a photo: it would read as
        // an empty slot, so it shrinks and the header tightens.
        Center(
          child: ClientAvatar(
            size: hasPhoto ? 96 : 68,
            imageUrl: card.avatarUrl,
            initials: card.initials,
          ),
        ),
        SizedBox(height: hasPhoto ? 12 : 10),
        Text(
          card.displayName ?? l10n.bookingDetailGuestClient,
          key: ClientCardScreen.nameKey,
          textAlign: TextAlign.center,
          style: clientHeading(22),
        ),
        if (card.blocked) ...<Widget>[
          const SizedBox(height: 6),
          const Center(child: BlockedTag()),
        ],
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            if (phone != null)
              _Chip(
                key: ClientCardScreen.phoneChipKey,
                semanticsLabel: l10n.clientPhoneSemantics(phone),
                onTap: () =>
                    showPhoneSheet(context, phone, clipboard: clipboard),
                child: PhoneLink(phone: phone),
              ),
            _Chip(
              key: ClientCardScreen.ratingChipKey,
              semanticsLabel: rated ? l10n.clientRatingOpenHint : null,
              onTap: rated ? onOpenRating : null,
              child: RatingReadout(
                average: card.displayRating,
                count: card.ratingCount,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// The visits sliver — the ONLY widget that watches the visits controller, so
/// paging / loading toggles rebuild just the timeline.
class _VisitsTimeline extends ConsumerWidget {
  const _VisitsTimeline({
    required this.scope,
    required this.client,
    required this.onOpenBooking,
  });

  final ClientListScope scope;
  final ClientRef client;
  final ValueChanged<String> onOpenBooking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ClientVisitsControllerProvider provider =
        clientVisitsControllerProvider(scope, client);
    return ref
        .watch(provider)
        .when(
          loading: () =>
              const SliverToBoxAdapter(child: BookingsSkeleton(count: 2)),
          error: (Object e, StackTrace _) => SliverToBoxAdapter(
            child: ErrorState(
              key: ClientCardScreen.visitsErrorKey,
              failure: e is Failure ? e : UnknownFailure(cause: e),
              onRetry: () => ref.invalidate(provider),
            ),
          ),
          data: (ClientVisitsState v) => _Timeline(
            state: v,
            onRetryMore: () => ref.read(provider.notifier).retryLoadMore(),
            onOpenBooking: onOpenBooking,
          ),
        );
  }
}

/// A raised action pill (preview `_Chip`).
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticsLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      container: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.pill),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(child: child),
              if (onTap != null) ...<Widget>[
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: BrandColors.muted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One flat row of the timeline sliver.
sealed class _Row {
  const _Row();
}

final class _NextTitleRow extends _Row {
  const _NextTitleRow();
}

final class _HistoryTitleRow extends _Row {
  const _HistoryTitleRow();
}

final class _MonthRow extends _Row {
  const _MonthRow(this.monthKey, this.instant);

  final int monthKey;
  final DateTime instant;
}

final class _VisitRow extends _Row {
  const _VisitRow(this.visit, {this.upcoming = false});

  final ClientVisit visit;
  final bool upcoming;
}

final class _EmptyRow extends _Row {
  const _EmptyRow();
}

final class _RetryMoreRow extends _Row {
  const _RetryMoreRow();
}

final class _SpinnerRow extends _Row {
  const _SpinnerRow();
}

/// Rows memoised per [ClientVisitsState] instance: a rebuild that is not a
/// state change reuses them.
final Expando<List<_Row>> _rowsCache = Expando<List<_Row>>('timeline rows');

/// Kyiv `year * 12 + month` — the month group key.
int _monthKey(DateTime instant) {
  final DateTime local = toBeauticaTime(instant);
  return local.year * 12 + local.month;
}

List<_Row> _rowsOf(ClientVisitsState state) {
  final ClientVisit? next = state.nextVisit;
  final List<ClientVisit> history = state.history;
  final List<_Row> rows = <_Row>[];
  if (next != null) {
    rows
      ..add(const _NextTitleRow())
      ..add(_VisitRow(next, upcoming: true));
  }
  if (history.isNotEmpty) {
    rows.add(const _HistoryTitleRow());
    int? month;
    for (final ClientVisit v in history) {
      final int key = _monthKey(v.startsAt);
      if (key != month) {
        month = key;
        rows.add(_MonthRow(key, v.startsAt));
      }
      rows.add(_VisitRow(v));
    }
  }
  if (next == null && history.isEmpty) rows.add(const _EmptyRow());
  if (state.loadMoreFailed) {
    rows.add(const _RetryMoreRow());
  } else if (state.isLoadingMore) {
    rows.add(const _SpinnerRow());
  }
  return List<_Row>.unmodifiable(rows);
}

/// Next-visit head node, then the history grouped by Kyiv month (D4), as a
/// lazy [SliverList] — only visible rows are built.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.state,
    required this.onRetryMore,
    required this.onOpenBooking,
  });

  final ClientVisitsState state;
  final VoidCallback onRetryMore;
  final ValueChanged<String> onOpenBooking;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<_Row> rows = _rowsCache[state] ??= _rowsOf(state);
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int index) => switch (rows[index]) {
        _NextTitleRow() => _Label(
          l10n.clientNextVisitTitle,
          key: const ValueKey<String>('timeline-next-title'),
          strong: true,
        ),
        _HistoryTitleRow() => _Label(
          l10n.clientHistoryTitle,
          key: const ValueKey<String>('timeline-history-title'),
          strong: true,
        ),
        _MonthRow(:final int monthKey, :final DateTime instant) => _Label(
          formatMonthYearHeader(instant),
          key: ValueKey<String>('timeline-month-$monthKey'),
        ),
        _VisitRow(:final ClientVisit visit, :final bool upcoming) => _Node(
          key: ValueKey<String>(visit.visitKey),
          visit: visit,
          upcoming: upcoming,
          onOpen: onOpenBooking,
        ),
        _EmptyRow() => SalonNoticeCard(
          key: ClientCardScreen.historyEmptyKey,
          icon: Icons.event_note_rounded,
          title: l10n.clientHistoryEmptyTitle,
          body: l10n.clientHistoryEmptyBody,
        ),
        _RetryMoreRow() => LoadMoreRetryFooter(
          message: l10n.clientsLoadMoreFailed,
          onRetry: onRetryMore,
          retryKey: ClientCardScreen.visitsRetryMoreKey,
        ),
        _SpinnerRow() => const MyBookingsLoadMoreSpinner(),
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {super.key, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(strong ? 0 : 26, strong ? 10 : 6, 0, 6),
      child: Text(
        text,
        style: strong
            ? clientHeading(16)
            : clientBody(
                13,
                weight: FontWeight.w800,
                color: BrandColors.accent,
              ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({
    super.key,
    required this.visit,
    required this.onOpen,
    this.upcoming = false,
  });

  final ClientVisit visit;
  final bool upcoming;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final BookingStatusBadge? sharedBadge = switch (visit.sharedStatus) {
      final status? => BookingStatusBadge.forStatus(status: status),
      null => null,
    };
    final String when =
        '${upcoming ? formatFullDate(visit.startsAt) : formatBookingDayHeader(visit.startsAt)}, '
        '${formatSlotTime(visit.startsAt)}';
    // No intrinsic/fixed height: the card sizes the node, and the rail and dot
    // are positioned against it, so a 2–3-line service name grows the card.
    return Stack(
      children: <Widget>[
        Positioned(
          left: 12,
          top: 0,
          bottom: 0,
          width: 2,
          child: ColoredBox(color: BrandColors.faint.withValues(alpha: 0.55)),
        ),
        Positioned(
          left: 7,
          top: 16,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: upcoming ? VelvetGradients.accentDiscFace : null,
              color: upcoming ? null : BrandColors.base,
              border: upcoming
                  ? null
                  : Border.all(color: BrandColors.accent, width: 2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 26, bottom: 10),
          child: Semantics(
            button: true,
            label: l10n.clientVisitSemantics(when),
            child: GestureDetector(
              key: upcoming
                  ? ClientCardScreen.nextVisitKey
                  : ClientCardScreen.visitKey(visit.visitKey),
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(visit.firstBookingId),
              child: NeumorphicCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                radius: VelvetRadii.field,
                shadows: VelvetShadows.extrudedSmall,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            when,
                            style: clientBody(
                              13,
                              weight: FontWeight.w700,
                              color: upcoming
                                  ? BrandColors.accentDeep
                                  : BrandColors.muted,
                            ),
                          ),
                        ),
                        if (sharedBadge != null) ...<Widget>[
                          const SizedBox(width: 6),
                          sharedBadge,
                        ],
                      ],
                    ),
                    for (final ClientVisitItem item in visit.items) ...<Widget>[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              item.serviceName,
                              style: clientBody(15, weight: FontWeight.w700),
                            ),
                          ),
                          if (sharedBadge == null) ...<Widget>[
                            const SizedBox(width: 6),
                            BookingStatusBadge.forStatus(status: item.status),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            item.price == null
                                ? priceUnavailableLabel
                                : formatBookingPrice(
                                    price: item.price!,
                                    priceMax: item.priceMax,
                                  ),
                            style: clientBody(15, weight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
