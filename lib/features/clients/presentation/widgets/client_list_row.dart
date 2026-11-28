// M509 — one row of the «Клієнти» list.
//
// NOTHING NEW VISUALLY (ClientsTab README, D6): the row is the booking-detail
// client strip ([BookingClientStrip] → `MasterStripShell`, `MasterAvatarBadge`,
// `MasterRatingReadout`) driven through its three additive params — `details`,
// `onTap`, `semanticsLabel`:
//
//   avatar (photo, else monogram) · name or «Гість» · ★ readout («—» when
//   unrated) · «Ост.: 7 лис» · «Наст.: пт, 20 лис, 14:00» · «Заблоковано» chip
//
// User decisions 2026-11-20 (CLI-47 / CLI-D10), all enforced HERE:
//   • one layout for every provider role and both client kinds — a GUEST row
//     is a registered row without a photo: no client-kind label (CLI-100),
//     the SAME ★ readout (the server's values; a guest is rated by phone, REV-D04);
//   • NO completed-visits count and NO phone (the API sends none);
//   • short dates, one per line, wrapping instead of ellipsizing;
//   • the screen-reader label keeps the long «Останній візит … / Наступний …».
//
// The strip's own `isGuest` stays `false` on purpose — that flag hides the
// ★ readout, which this list keeps.
//
// PII: name only; never logged.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/relative_date.dart';

/// A client row. [now] feeds the screen-reader «останній візит» wording, the
/// year rule of the short dates (a date outside the current Kyiv year shows its
/// year) and drops a «Наст.» whose start has already passed (the server value
/// is from the last fetch; the screen re-reads [now] on app resume).
class ClientListRow extends StatelessWidget {
  const ClientListRow({
    super.key,
    required this.summary,
    required this.now,
    this.onTap,
  });

  final ClientSummary summary;
  final DateTime now;

  /// Opens the client's card. `null` renders an inert strip.
  final VoidCallback? onTap;

  static const Key lastKey = Key('client-row-last');
  static const Key nextKey = Key('client-row-next');
  static const Key blockedKey = Key('client-row-blocked');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ClientSummary s = summary;
    final DateTime? lastAt = s.lastVisitAt;
    // A next visit whose start instant is not after [now] is no longer
    // "next" — an absolute-instant comparison, not a calendar day.
    final DateTime? nextAt = switch (s.nextVisitAt) {
      final DateTime at when at.isAfter(now) => at,
      _ => null,
    };

    // Short meta — Kyiv wall-clock, the shipped formatters.
    final String? lastLine = lastAt == null
        ? null
        : '${l10n.clientsRowLastVisitShort}: '
              '${formatShortDay(lastAt, now: now)}';
    final String? nextLine = nextAt == null
        ? null
        : '${l10n.clientsRowNextVisitShort}: ${_nextWhen(nextAt, now)}';

    final String name = s.displayName ?? l10n.bookingDetailGuestClient;
    final String? lastRelative = lastAt == null
        ? null
        : formatRelativeDate(l10n, lastAt, now: now);
    final String semantics = <String>[
      lastRelative == null
          ? l10n.clientsRowSemanticsNoVisit(name)
          : l10n.clientsRowSemantics(name, lastRelative),
      if (nextAt != null)
        '${l10n.clientsRowNextVisit}: ${_nextWhen(nextAt, now)}',
      if (s.blocked) l10n.clientBlockedBadge,
    ].join(', ');

    final Widget? details = (lastLine == null && nextLine == null && !s.blocked)
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (lastLine != null) _metaLine(lastLine, lastKey),
              if (nextLine != null) _metaLine(nextLine, nextKey),
              if (s.blocked) ...<Widget>[
                const SizedBox(height: VelvetSpacing.xs),
                RoleChip(
                  key: blockedKey,
                  label: l10n.clientBlockedBadge,
                  icon: Icons.block_rounded,
                  tint: BrandColors.error,
                ),
              ],
            ],
          );

    return BookingClientStrip(
      shellKey: Key('client-row-${s.id}'),
      avatarImageKey: Key('client-row-avatar-${s.id}'),
      name: s.displayName,
      avatarUrl: s.avatarUrl,
      initials: s.initials,
      rating: s.displayRating,
      reviewCount: s.ratingCount,
      details: details,
      onTap: onTap,
      semanticsLabel: semantics,
    );
  }

  /// «пт, 20 лис, 14:00» («пт, 8 січ 2027, 14:00» outside the Kyiv year).
  static String _nextWhen(DateTime instant, DateTime now) =>
      '${formatBookingDayHeader(instant, now: now)}, ${formatSlotTime(instant)}';
}

/// `feedbackMutedSm` (11 sp, the app's secondary-meta size). Never
/// ellipsized: a line that does not fit wraps instead.
Widget _metaLine(String text, Key key) =>
    Text(text, key: key, style: VelvetText.feedbackMutedSm, softWrap: true);
