// M510 — «★ 4,9 · 12 оцінок» / «Ще немає оцінок» (ClientCardVariants
// `RatingReadout`). Shown for EVERY client: count 0 (an unrated guest or
// registered client) reads «Ще немає оцінок». A guest shows the server's own
// values (rated by phone, REV-D04); nothing here special-cases guests. The ★ is the shipped
// [RatingStar].

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';

class RatingReadout extends StatelessWidget {
  const RatingReadout({super.key, required this.average, required this.count});

  /// `null` when nobody rated the client.
  final double? average;
  final int count;

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
        style: VelvetText.feedbackMutedSm,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The booking client strip's ★ readout scale (`MasterRatingReadout`).
        RatingStar(rating: avg, size: 16, showLabel: false),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            '${formatClientRatingAvg(avg)} · ${l10n.clientRatingCount(count)}',
            style: VelvetText.bodyStrong14,
          ),
        ),
      ],
    );
  }
}
