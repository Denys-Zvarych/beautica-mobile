// M510 — «★ 4,9 · 12 оцінок» / «Ще немає оцінок» (ClientCardVariants
// `RatingReadout`). Shown for EVERY client: count 0 (every guest, an unrated
// registered client) reads «Ще немає оцінок». The ★ is the shipped
// [RatingStar].

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';

class RatingReadout extends StatelessWidget {
  const RatingReadout({
    super.key,
    required this.average,
    required this.count,
    this.size = 14,
  });

  /// `null` when nobody rated the client.
  final double? average;
  final int count;
  final double size;

  /// Whether there is a rating to show (the chip is tappable only then).
  bool get rated => average != null && count > 0;

  static const Key emptyKey = Key('client-rating-empty');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double? avg = average;
    if (avg == null || count <= 0) {
      return Text(
        l10n.clientRatingEmpty,
        key: emptyKey,
        style: clientBody(size, color: BrandColors.muted),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RatingStar(rating: avg, size: size + 4, showLabel: false),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '${formatClientRatingAvg(avg)} · ${l10n.clientRatingCount(count)}',
            style: clientBody(size, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
