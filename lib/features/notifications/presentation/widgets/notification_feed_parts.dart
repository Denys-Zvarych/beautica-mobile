// Phase 363 — the small pieces around the feed's rows: the mark-all strip, the
// day header, the loading-row silhouette and the list footer.
//
// Reuse map (none of these re-implement an existing widget):
//   day header     → `SectionHeader` (shared/widgets/section_header.dart)
//   loading row    → `BookingsSkeletonWell` wells inside `BookingsSkeleton`'s
//                    additive `rowBuilder` (booking/…/my_bookings_states.dart)
//   spinner        → `MyBookingsLoadMoreSpinner`
//   429 footer     → `MyBookingsRetryCooldown` (promoted out of the archive)

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/my_bookings_states.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/section_header.dart';

import '../../domain/notifications_feed_state.dart';

/// The strip above the list: the unread count on the left, «Позначити всі як
/// прочитані» on the right. HIDDEN (collapses to zero height) when [unread] is
/// 0 — a greyed control on an all-read list reads as broken.
class NotificationsMarkAllBar extends StatelessWidget {
  const NotificationsMarkAllBar({
    super.key,
    required this.unread,
    required this.onMarkAll,
  });

  static const Key actionKey = Key('notifications-mark-all-read');

  /// Backend's cap: a count at this value means "this many or more".
  static const int unreadCap = 99;

  final int unread;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: unread <= 0
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.xs,
                VelvetSpacing.md,
                0,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      unread >= unreadCap
                          ? l10n.notificationsUnreadCountCapped
                          : l10n.notificationsUnreadCount(unread),
                      style: VelvetText.label().copyWith(
                        color: BrandColors.textSecondary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    child: InkWell(
                      key: actionKey,
                      onTap: onMarkAll,
                      borderRadius: BorderRadius.circular(VelvetRadii.field),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: NeumorphicIconButton.extent,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: VelvetSpacing.sm,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.done_all_rounded,
                                size: 16,
                                color: BrandColors.accentDeep,
                              ),
                              const SizedBox(width: VelvetSpacing.xs + 2),
                              Text(
                                l10n.notificationsMarkAllRead,
                                style: VelvetText.link(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// «Сьогодні» / «Вчора» / «Пн, 28 вересня» — built from [SectionHeader] so the
/// day boundaries read as the list's structure.
class NotificationsDayHeader extends StatelessWidget {
  const NotificationsDayHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: VelvetSpacing.xs,
        top: VelvetSpacing.md,
        bottom: VelvetSpacing.sm,
      ),
      child: Semantics(
        header: true,
        child: SectionHeader(
          title: label,
          titleStyle: VelvetText.subheading().copyWith(
            color: BrandColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// One loading row in the compact row's silhouette: recessed wells on the bare
/// base (nothing has risen yet). Handed to `BookingsSkeleton.rowBuilder`.
class NotificationsSkeletonRow extends StatelessWidget {
  const NotificationsSkeletonRow({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    // Ragged, text-like line lengths that vary per row.
    final double titleWidth = width * (0.30 + (index % 3) * 0.06);
    final double bodyWidth = width * (0.46 + (index % 2) * 0.08);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        border: Border.all(color: BrandColors.faint.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.sm + VelvetSpacing.xs),
        child: Row(
          children: <Widget>[
            const BookingsSkeletonWell(
              width: 36,
              height: 36,
              radius: VelvetRadii.field - 4,
            ),
            const SizedBox(width: VelvetSpacing.sm + VelvetSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BookingsSkeletonWell(width: titleWidth, height: 11),
                  const SizedBox(height: VelvetSpacing.sm),
                  BookingsSkeletonWell(width: bodyWidth, height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list tail.
///
/// * a 429 with a usable `Retry-After` → the shared cooldown footer; when the
///   window closes it retries the page itself;
/// * any other failure → a notice and an explicit retry button (nothing
///   re-fires by itself);
/// * otherwise a spinner, and — once, when it is first built, i.e. when the
///   lazy list has scrolled near the end — a request for the next page.
///
/// The "near the end" signal is the footer being BUILT by the lazy sliver, not
/// a scroll listener, so there is no listener to refire and a list too short to
/// scroll still loads its next page.
class NotificationsLoadMoreFooter extends StatelessWidget {
  const NotificationsLoadMoreFooter({
    super.key,
    required this.feed,
    required this.now,
    required this.onLoadMore,
    required this.onRetry,
  });

  static const Key retryKey = Key('notifications-load-more-retry');
  static const Key cooldownKey = Key('notifications-load-more-cooldown');

  final NotificationsFeedState feed;

  /// The injected clock's current instant (never a raw `DateTime.now`).
  final DateTime now;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Failure? failure = feed.loadMoreFailure;
    final DateTime? notBefore = feed.loadMoreRetryNotBefore;
    if (failure is NotificationsRateLimitedFailure && notBefore != null) {
      // The window is an ABSOLUTE instant, so a footer that scrolled away and
      // was rebuilt keeps counting from where it was. `ceil`: «0 с» is never
      // shown while time remains.
      final int remaining = (notBefore.difference(now).inMilliseconds / 1000)
          .ceil();
      if (remaining <= 0) {
        // Window already closed while the footer was off-screen.
        return _LoadMoreTrigger(requestNow: true, onLoadMore: onRetry);
      }
      return MyBookingsRetryCooldown(
        key: ValueKey<DateTime>(notBefore),
        textKey: cooldownKey,
        seconds: remaining,
        onElapsed: onRetry,
      );
    }
    if (failure != null) {
      final AppLocalizations l10n = AppLocalizations.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.sm),
        child: Column(
          children: <Widget>[
            Text(
              l10n.notificationsLoadMoreFailed,
              textAlign: TextAlign.center,
              style: VelvetText.body(),
            ),
            InkWell(
              key: retryKey,
              onTap: onRetry,
              borderRadius: BorderRadius.circular(VelvetRadii.field),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: NeumorphicIconButton.extent,
                  minWidth: NeumorphicIconButton.extent,
                ),
                child: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: VelvetSpacing.md,
                    ),
                    child: Text(l10n.retryLabel, style: VelvetText.link()),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return _LoadMoreTrigger(
      requestNow: !feed.loadingMore,
      onLoadMore: onLoadMore,
    );
  }
}

/// The spinner that asks for the next page exactly once when it is mounted.
class _LoadMoreTrigger extends StatefulWidget {
  const _LoadMoreTrigger({required this.requestNow, required this.onLoadMore});

  final bool requestNow;
  final VoidCallback onLoadMore;

  @override
  State<_LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<_LoadMoreTrigger> {
  @override
  void initState() {
    super.initState();
    if (widget.requestNow) {
      // Deferred: a provider must not mutate itself during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoadMore();
      });
    }
  }

  @override
  Widget build(BuildContext context) => const MyBookingsLoadMoreSpinner();
}
