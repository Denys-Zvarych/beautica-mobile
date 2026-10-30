// Phase 426 D2 — one row of «Заблоковані клієнти».
//
// Ported from the approved preview
// `docs/signup-designs/UgcSafety/lib/widgets/moderation_widgets.dart`
// (`BlockedEntryCard`): the «Улюблені» card body — the SAME shell
// ([RaisedCardShell], promoted from favourites' `_FavoriteShell`) and the SAME
// identity disc ([MasterMark], moved to `shared/widgets/`) — with the trailing
// heart swapped for a «Розблокувати» link. Not tappable as a whole: the only
// action on a blocked entry is unblocking.
//
// Beyond the preview (brief, 2026-10-28): a registered client's avatar fills
// the disc when the API carries one, and a guest's masked phone
// («+380 •• ••• 12 34», already masked server-side) sits between the name and
// the «Заблоковано …» line in the same muted register. A registered client has
// no phone line.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/master_mark.dart';
import 'package:beautica_mobile/shared/widgets/raised_card_shell.dart';

/// «12 жовтня» — the Kyiv day [instant] falls on; the year is appended only
/// when it differs from [todayKyiv]'s («3 березня 2025»).
String formatBlockedOnDay(DateTime instant, DateTime todayKyiv) {
  final DateTime day = kyivDayOf(instant);
  final String base = '${day.day} ${monthGenitive(day.month)}';
  return day.year == todayKyiv.year ? base : '$base ${day.year}';
}

/// One blocked client: disc, name, masked phone (guests), blocked-on day,
/// trailing «Розблокувати».
class BlockedEntryCard extends StatelessWidget {
  const BlockedEntryCard({
    super.key,
    required this.block,
    required this.todayKyiv,
    required this.onUnblock,
  });

  final ClientBlock block;

  /// Kyiv date token for "today" — decides whether the year is shown.
  final DateTime todayKyiv;

  final VoidCallback onUnblock;

  /// Preview geometry: the disc at 48 (not the favourites' 56).
  static const double _markSize = 48;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? phone = block.maskedPhone;
    return RaisedCardShell(
      onTap: null,
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        VelvetSpacing.md,
        VelvetSpacing.xs,
        VelvetSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          MasterMark(
            initials: block.initials,
            size: _markSize,
            imageUrl: block.avatarUrl,
            imageKey: ValueKey<String>('blocked-avatar-${block.id}'),
          ),
          const SizedBox(width: VelvetSpacing.md - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  block.displayName,
                  style: VelvetText.subheading16,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (phone != null && phone.isNotEmpty) ...<Widget>[
                  const SizedBox(height: VelvetSpacing.xs),
                  Text(
                    // raw-ui-string-ok: server-masked phone — data, not copy.
                    phone,
                    key: ValueKey<String>('blocked-phone-${block.id}'),
                    style: VelvetText.feedbackMutedSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: VelvetSpacing.xs),
                Text(
                  l10n.blockedClientsBlockedOn(
                    formatBlockedOnDay(block.createdAt, todayKyiv),
                  ),
                  style: VelvetText.feedbackMutedSm,
                ),
              ],
            ),
          ),
          Semantics(
            // Its own node: the action must be announced as one button with
            // the client's name, not merged into the row's text.
            container: true,
            button: true,
            label: l10n.blockedClientsUnblockSemantics(block.displayName),
            excludeSemantics: true,
            child: TextButton(
              key: ValueKey<String>('blocked-unblock-${block.id}'),
              onPressed: onUnblock,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.sm + 4,
                ),
                foregroundColor: BrandColors.accentDeep,
                overlayColor: BrandColors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VelvetRadii.button),
                ),
              ),
              child: Text(
                l10n.blockedClientsUnblock,
                style: VelvetText.linkCompact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
