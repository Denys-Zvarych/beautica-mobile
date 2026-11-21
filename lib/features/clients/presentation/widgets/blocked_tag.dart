// M510 — the «Заблоковано» tag under the card name (ClientCardVariants
// `BlockedTag`).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

class BlockedTag extends StatelessWidget {
  const BlockedTag({super.key});

  static const Key tagKey = Key('client-card-blocked');

  @override
  Widget build(BuildContext context) {
    return Container(
      key: tagKey,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: BrandColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.block_rounded, size: 13, color: BrandColors.error),
          const SizedBox(width: 4),
          Text(
            AppLocalizations.of(context).clientBlockedBadge,
            style: clientBody(
              12,
              weight: FontWeight.w700,
              color: BrandColors.error,
            ),
          ),
        ],
      ),
    );
  }
}
