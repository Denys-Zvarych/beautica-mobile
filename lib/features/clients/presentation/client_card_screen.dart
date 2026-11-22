// M510 — the provider's client card (CLI-48), ported from
// `docs/signup-designs/ClientCardVariants/lib/screens/client_card_screen.dart`.
//
// ONE layout for every provider role and both client kinds (CLI-D07): nothing
// here reads the client's kind. Only DATA differs — no photo → monogram, no
// `phone` → no phone chip, count 0 → «Ще немає оцінок» (not tappable).
//
//   avatar · name · «Заблоковано» · [phone chip] [rating chip]
//   [master chips] — SALON_OWNER / SALON_ADMIN only (CLI-73, CLI-D12)
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
// MASTER CHIPS (CLI-73 / CLI-74): «Усі майстри» + one chip per
// `servedByMasters` entry (salon-wide, server order). A chip re-keys ONLY the
// visits controller with that `masterId` (history + «Наступний візит»); the card
// itself is never refetched, so the chips stay put. Hidden with 0 masters, and
// when the route's `masterId` is not one of the chips (owner master mode: the
// view stays scoped to the owner's own master row). The selection lives in a
// [ValueNotifier] read only by the chip row and the timeline, so a chip tap
// never rebuilds the header. A non-UUID chip id is ignored (never queried).
//
// PII: name, photo and phone are rendered, never logged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/single_flight.dart';
import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_visits_controller.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_route.dart';
import 'package:beautica_mobile/features/clients/presentation/client_photo_report.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/blocked_tag.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/phone_link.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_readout.dart';
import 'package:beautica_mobile/features/favorites/presentation/widgets/favorites_filter.dart'
    show FavoriteCategoryChip;
import 'package:beautica_mobile/features/master/presentation/widgets/profile_scaffold.dart';
import 'package:beautica_mobile/features/moderation/application/my_reported_targets_notifier.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block_access.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/client_actions_flow.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:beautica_mobile/shared/validators/uuid_validator.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/load_more_retry_footer.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart'
    show PhotoViewerReport;
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

  /// The top bar's «⋯» — report / block / unblock (R3), the same flow as the
  /// provider «Деталі запису» client strip.
  static const Key moreKey = Key('client-card-more');
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

  /// CLI-73 — the master chip row and its chips.
  static const Key masterChipsKey = Key('client-master-chips');
  static const Key masterChipAllKey = Key('client-master-chip-all');
  static Key masterChipKey(String masterId) =>
      Key('client-master-chip-$masterId');

  @override
  ConsumerState<ClientCardScreen> createState() => _ClientCardScreenState();
}

class _ClientCardScreenState extends ConsumerState<ClientCardScreen> {
  /// `my_bookings_screen`'s load-more threshold.
  static const double _loadMoreThreshold = 320;

  ClientCardProvider get _cardProvider =>
      clientCardProvider(widget.scope, widget.client);

  /// CLI-74 — the master chip filter; starts at the route's `masterId`. Read
  /// only by the chip row and the timeline (not the header).
  late final ValueNotifier<String?> _filterMasterId = ValueNotifier<String?>(
    _masterId,
  );

  /// The visits read: the route scope with [masterId] (the chip filter).
  ClientListScope _visitsScopeFor(String? masterId) => switch (widget.scope) {
    final SalonClientListScope s => s.copyWith(masterId: masterId),
    final MyClientListScope s => s,
  };

  /// Every chip key this card has read visits under (the route's plus each
  /// chip tapped). Each is a separately cached (30 s) visits instance, so a
  /// refresh / retry / block must drop ALL of them, not only the current one.
  late final Set<String?> _visitedMasterIds = <String?>{_masterId};

  /// Invalidates the visits of every chip key read for this client.
  void _invalidateVisits() {
    for (final String? masterId in _visitedMasterIds) {
      ref.invalidate(
        clientVisitsControllerProvider(
          _visitsScopeFor(masterId),
          widget.client,
        ),
      );
    }
  }

  /// The visits of the CURRENT chip selection (actions read it on demand).
  ClientVisitsControllerProvider get _visitsProvider =>
      clientVisitsControllerProvider(
        _visitsScopeFor(_filterMasterId.value),
        widget.client,
      );

  /// MOD-39 / CLI-70 — the avatar viewer report, built once per
  /// (role, client, name) instead of on every build.
  ({UserRole? role, ClientRef client, String name})? _avatarReportKey;
  PhotoViewerReport? _avatarReport;

  PhotoViewerReport? _avatarReportFor(UserRole? role, String name) {
    final ({UserRole? role, ClientRef client, String name}) key = (
      role: role,
      client: widget.client,
      name: name,
    );
    if (key != _avatarReportKey) {
      _avatarReportKey = key;
      _avatarReport = clientPhotoReport(role, widget.client, name: name);
    }
    return _avatarReport;
  }

  String? get _masterId => switch (widget.scope) {
    SalonClientListScope(:final String? masterId) => masterId,
    MyClientListScope() => null,
  };

  @override
  void didUpdateWidget(ClientCardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope || oldWidget.client != widget.client) {
      _visitedMasterIds
        ..clear()
        ..add(_masterId);
      _filterMasterId.value = _masterId;
    }
  }

  @override
  void dispose() {
    _filterMasterId.dispose();
    super.dispose();
  }

  /// A chip tap: `null` = «Усі майстри»; a non-UUID id is ignored.
  void _selectMaster(String? masterId) {
    if (masterId != null && !isUuid(masterId)) return;
    _visitedMasterIds.add(masterId);
    _filterMasterId.value = masterId;
  }

  /// CLI-73 — chips only on a salon card for owner / admin with ≥1 master,
  /// and only when the route's `masterId` (if any) is one of the chips.
  bool _showMasterChips(UserRole? role, ClientCard card) {
    if (widget.scope is! SalonClientListScope) return false;
    if (role != UserRole.salonOwner && role != UserRole.salonAdmin) {
      return false;
    }
    if (card.servedByMasters.isEmpty) return false;
    final String? routeMasterId = _masterId;
    return routeMasterId == null ||
        card.servedByMasters.any(
          (ClientServedMaster m) => m.masterId == routeMasterId,
        );
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.extentAfter <= _loadMoreThreshold) {
      // The controller guards double-fetch, the last page and a failed append.
      ref.read(_visitsProvider.notifier).loadMore();
    }
    return false;
  }

  Future<void> _refresh() async {
    ref.invalidate(_cardProvider);
    _invalidateVisits();
    try {
      await ref.read(_cardProvider.future);
    } catch (_) {
      // The error state renders it; the indicator just stops.
    }
  }

  /// Single-flight for the «⋯»: the anchor booking read + sheet.
  bool _moreInFlight = false;

  /// The booking the «⋯» acts through (`POST /blocks { bookingId }`, the
  /// detail's `clientBlockId` / `clientBlockable`): a guest card's own anchor
  /// booking; for a registered client, the newest loaded visit's booking.
  String? _anchorBookingId() => switch (widget.client) {
    GuestClientRef(:final String bookingId) => bookingId,
    RegisteredClientRef() => switch (ref.read(_visitsProvider).value?.visits) {
      final List<ClientVisit> v when v.isNotEmpty => v.first.firstBookingId,
      _ => null,
    },
  };

  /// Whether the «⋯» has anything to offer [role] before the anchor read:
  /// report a registered client not yet reported, or a role that may block.
  /// The exact gate (server `clientBlockable` / `clientBlocked`) is
  /// [clientActionsGateFor] on tap. Called from build.
  bool _showMore(UserRole? role) {
    if (role == null || role == UserRole.client) return false;
    final bool canReport = switch (widget.client) {
      RegisteredClientRef(:final String userId) => !watchIsReported(
        ref,
        ReportTargetType.clientProfile,
        userId,
      ),
      GuestClientRef() => false,
    };
    return canReport || clientBlocksAllowedFor(role);
  }

  Future<void> _onMore(UserRole? role) async {
    if (_moreInFlight) return;
    final String? anchor = _anchorBookingId();
    if (anchor == null) return;
    _moreInFlight = true;
    try {
      final Booking booking;
      // The detail provider is autoDispose: hold it across the await.
      final ProviderSubscription<AsyncValue<Booking>> hold = ref.listenManual(
        bookingDetailProvider(anchor),
        (_, _) {},
      );
      try {
        booking = await ref.read(bookingDetailProvider(anchor).future);
      } on Failure catch (f) {
        if (mounted) showErrorSnack(context, f.userMessage(context));
        return;
      } finally {
        hold.close();
      }
      if (!mounted) return;
      final String? clientId = booking.clientId;
      // A registered card acts through its newest visit; if that booking no
      // longer belongs to the route's client, act on nothing (no snack).
      if (widget.client case RegisteredClientRef(
        :final String userId,
      ) when clientId != userId) {
        return;
      }
      final ClientActionsGate? gate = clientActionsGateFor(
        booking,
        role,
        reported:
            clientId != null &&
            ref.read(myReportedTargetsProvider).value?.contains((
                  type: ReportTargetType.clientProfile,
                  id: clientId,
                )) ==
                true,
      );
      if (gate == null) return;
      await runClientActions(
        context,
        ref,
        booking: booking,
        gate: gate,
        salonId: switch (widget.scope) {
          SalonClientListScope(:final String salonId) => salonId,
          MyClientListScope() => null,
        },
        // The «Заблоковано» tag (and any visit the block cancelled).
        onChanged: () {
          ref.invalidate(_cardProvider);
          _invalidateVisits();
        },
      );
    } finally {
      _moreInFlight = false;
    }
  }

  void _openRating() => context.pushOnce<void>(
    clientRatingRoute(widget.cardBase, widget.client, masterId: _masterId),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ClientCard> card = ref.watch(_cardProvider);
    // Both reads start together (the route scope's visits), but only the
    // timeline sliver WATCHES the visits: a listen keeps the fetch alive
    // without rebuilding the header and chips on every loading-more toggle.
    ref.listen<AsyncValue<ClientVisitsState>>(
      clientVisitsControllerProvider(_visitsScopeFor(_masterId), widget.client),
      (_, _) {},
    );
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
            onRetry: () {
              ref.invalidate(_cardProvider);
              _invalidateVisits();
            },
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
          avatarReport: _avatarReportFor(
            role,
            c.displayName ?? l10n.bookingDetailGuestClient,
          ),
        ),
        <Widget>[
          if (_showMasterChips(role, c))
            SliverToBoxAdapter(
              child: ValueListenableBuilder<String?>(
                valueListenable: _filterMasterId,
                builder: (BuildContext context, String? selected, Widget? _) =>
                    _MasterChips(
                      masters: c.servedByMasters,
                      selectedId: selected,
                      onSelect: _selectMaster,
                    ),
              ),
            ),
          ValueListenableBuilder<String?>(
            valueListenable: _filterMasterId,
            builder: (BuildContext context, String? masterId, Widget? _) =>
                _VisitsTimeline(
                  scope: _visitsScopeFor(masterId),
                  client: widget.client,
                  onOpenBooking: (String bookingId) =>
                      context.pushOnce<void>(widget.bookingRoute(bookingId)),
                ),
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
        trailing: card.hasValue && _showMore(role)
            ? NeumorphicIconButton(
                key: ClientCardScreen.moreKey,
                icon: Icons.more_horiz_rounded,
                semanticLabel: l10n.clientMoreActions,
                onTap: () => _onMore(role),
              )
            : null,
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
    this.avatarReport,
  });

  final ClientCard card;
  final ClipboardService clipboard;
  final bool showPhone;
  final VoidCallback onOpenRating;

  /// MOD-39 / CLI-70 — the avatar viewer's «Поскаржитися»; `null` → none.
  final PhotoViewerReport? avatarReport;

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
            previewOnTap: true,
            previewReport: avatarReport,
          ),
        ),
        SizedBox(height: hasPhoto ? 12 : 10),
        Text(
          card.displayName ?? l10n.bookingDetailGuestClient,
          key: ClientCardScreen.nameKey,
          textAlign: TextAlign.center,
          style: VelvetText.displayName(),
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

/// CLI-73 — «Усі майстри» + one chip per served master, one horizontal row.
/// Reuses the app's filter chip ([FavoriteCategoryChip]: raised at rest,
/// pressed in when selected).
class _MasterChips extends StatelessWidget {
  const _MasterChips({
    required this.masters,
    required this.selectedId,
    required this.onSelect,
  });

  final List<ClientServedMaster> masters;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
      child: SingleChildScrollView(
        key: ClientCardScreen.masterChipsKey,
        scrollDirection: Axis.horizontal,
        // The raised chips' shadows must not be cut at the row's edges.
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xs),
        child: Row(
          children: <Widget>[
            FavoriteCategoryChip(
              key: ClientCardScreen.masterChipAllKey,
              label: l10n.clientMastersFilterAll,
              selected: selectedId == null,
              onTap: () => onSelect(null),
            ),
            for (final ClientServedMaster m in masters) ...<Widget>[
              const SizedBox(width: VelvetSpacing.sm),
              FavoriteCategoryChip(
                key: ClientCardScreen.masterChipKey(m.masterId),
                label: m.name,
                selected: selectedId == m.masterId,
                onTap: () => onSelect(m.masterId),
              ),
            ],
          ],
        ),
      ),
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
        // Section title = the profile section label; month = the accent
        // caption.
        style: strong ? VelvetText.sectionLabel() : VelvetText.feedbackAccentSm,
      ),
    );
  }
}

/// One timeline row = ONE booking (BOOK-05: 1 booking = 1 service; the
/// appointment grouping never surfaces). The controller flattens the API's
/// groups via `clientVisitsPerBooking`, so [visit] always holds one item.
class _Node extends StatelessWidget {
  const _Node({
    super.key,
    required this.visit,
    required this.onOpen,
    this.upcoming = false,
  });

  /// [VelvetText.masterCardDateFull] in the upcoming visit's accent.
  static final TextStyle _upcomingWhenStyle = VelvetText.masterCardDateFull
      .copyWith(color: BrandColors.accentDeep);

  final ClientVisit visit;
  final bool upcoming;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ClientVisitItem booking = visit.items.first;
    final String when =
        '${upcoming ? formatFullDate(booking.startsAt) : formatBookingDayHeader(booking.startsAt)}, '
        '${formatSlotTime(booking.startsAt)}';
    final String price = switch (booking.price) {
      final double p? => formatBookingPrice(
        price: p,
        priceMax: booking.priceMax,
      ),
      null => priceUnavailableLabel,
    };
    final String status = l10n.bookingStatusSemantics(
      BookingStatusVisual.forStatus(
        booking.status,
        atSalon: false,
        l10n: l10n,
      ).label,
    );
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
          // One explicit label matching the row: when, THIS booking's status,
          // service, price. Child semantics are excluded so the pill and texts
          // are not announced a second time.
          child: Semantics(
            button: true,
            excludeSemantics: true,
            label: <String>[
              l10n.clientVisitSemantics(when),
              status,
              booking.serviceName,
              price,
            ].join(', '),
            child: GestureDetector(
              key: upcoming
                  ? ClientCardScreen.nextVisitKey
                  : ClientCardScreen.visitKey(visit.visitKey),
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(booking.bookingId),
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
                            // The booking card's date caption; the upcoming
                            // visit keeps its accent.
                            style: upcoming
                                ? _upcomingWhenStyle
                                : VelvetText.masterCardDateFull,
                          ),
                        ),
                        const SizedBox(width: 6),
                        BookingStatusBadge.forStatus(status: booking.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        // The name takes the row's free width and wraps by
                        // word (max 3 lines, then ellipsis); the price stays
                        // intrinsic on the right.
                        Expanded(
                          child: Text(
                            booking.serviceName,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: VelvetText.masterCardServiceFull,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(price, style: VelvetText.masterCardPricePill),
                      ],
                    ),
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
