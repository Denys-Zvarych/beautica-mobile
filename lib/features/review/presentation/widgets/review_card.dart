// Phase 4.5 — Shared, model-agnostic review leaf widgets.
//
// Extracted verbatim from the salon "Відгуки" tab
// (`features/salon/presentation/widgets/salon_reviews_section.dart`, Phase 13.6)
// so the salon public profile AND the independent-master received-reviews
// screen (Phase 4.6) render each review card from ONE code path. This is a pure
// move — the VelvetTouch styling (NeumorphicCard, camel ★ row, gradient avatar,
// `Icons.spa_outlined` service line) is unchanged; only the widgets are now
// public and parameterised by primitives / a small view-model instead of a
// feature-specific domain type.
//
// Feature-neutral by construction: this file imports NO feature domain and only
// the SHARED relative-date keys via [AppLocalizations]. The (optional) service
// sub-line renders the raw service name ([ReviewCard.serviceName]) with no
// prefix label — the widget never references a feature-specific l10n key.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/relative_date.dart';

/// The primitives a [ReviewCard] renders, decoupled from any feature domain
/// model. Salon maps `SalonReviewItem` → [ReviewCardData] (with [serviceName]);
/// master maps `MasterReviewItem` → [ReviewCardData] (also with [serviceName],
/// backend `92280c3` — `null` only when the backend couldn't resolve a
/// service, in which case the service-name sub-line doesn't render).
///
/// Phase 334 adds a THIRD consumer: «Деталі запису»'s provider branch maps
/// [Booking.reviewByClient] here to show the provider the review their client
/// left about them. That payload (`ClientAuthoredReviewResponse`) is
/// `{rating, comment}` and nothing more — no review id, no author name, no
/// timestamp — so [id] is seeded from the BOOKING id, [clientDisplayName]
/// from the booking's own client name, and [createdAt]/[comment] are both
/// passed `null` where the wire has nothing. Those two fields were widened to
/// nullable for it; see each one's doc for why no existing caller moved.
@immutable
final class ReviewCardData {
  const ReviewCardData({
    required this.id,
    required this.clientDisplayName,
    required this.rating,
    this.comment,
    this.createdAt,
    this.serviceName,
  });

  /// Stable review id — seeds the deterministic avatar gradient and the card's
  /// widget key.
  final String id;

  /// Already masked by the backend (e.g. "Олена К.") — render as-is.
  final String clientDisplayName;

  /// This review's 1–5 star score.
  final int rating;

  /// The review body, or `null` when the payload carries no comment at all —
  /// the booking-detail «Відгук клієнта» block (phase 334) reads
  /// `ClientAuthoredReviewResponse.comment`, which is null when the client
  /// rated without writing anything. The body line is then omitted entirely;
  /// the ★ row IS the review.
  ///
  /// ADDITIVE WIDENING, not a new param: `null` is the only value that
  /// suppresses the line. An EMPTY string still renders the same empty [Text]
  /// (and its leading gap) it always has, so the salon and master reviews
  /// tabs — which pass a non-nullable `String` straight off their domain
  /// items — are byte-for-byte unaffected.
  final String? comment;

  /// When the review was authored — rendered as a relative date in the header
  /// row. `null` when the payload carries no timestamp: the booking-detail
  /// block (phase 334) reads `ClientAuthoredReviewResponse`, which is
  /// `{rating, comment}` and nothing else. The relative-date [Text] is then
  /// omitted and the name takes the full header width.
  ///
  /// ADDITIVE WIDENING — the salon and master reviews tabs both pass a
  /// non-null `createdAt` off their domain items, so their header rows are
  /// unchanged.
  final DateTime? createdAt;

  /// Optional booked-service name (salon and master reviews). `null` when the
  /// backend couldn't resolve one for this review.
  final String? serviceName;
}

/// A single review: a raised card with an avatar + name + relative-date header,
/// this review's ★ row, the comment body and an optional muted service-name
/// sub-line.
///
/// The card's widget key is `Key('$keyPrefix-${data.id}')` (salon uses
/// `salon-review`, master uses `master-review`) so widget tests can target an
/// individual card. When [serviceName] is null/empty the service sub-line is
/// omitted entirely.
class ReviewCard extends StatelessWidget {
  const ReviewCard({
    super.key,
    required this.data,
    required this.keyPrefix,
    this.serviceName,
  });

  final ReviewCardData data;

  /// Widget-key namespace for this card (`salon-review` / `master-review`).
  final String keyPrefix;

  /// The booked service name (e.g. "Манікюр"), rendered as-is with no label,
  /// or null to hide the sub-line entirely.
  final String? serviceName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final DateTime? createdAt = data.createdAt;
    final String? relativeDate = createdAt == null
        ? null
        : formatRelativeDate(l10n, createdAt);
    final String? comment = data.comment;
    final String? service = serviceName;
    return NeumorphicCard(
      key: Key('$keyPrefix-${data.id}'),
      padding: const EdgeInsets.all(VelvetSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ReviewAvatar(seed: data.id),
              const SizedBox(width: VelvetSpacing.sm + 2),
              Expanded(
                child: Text(
                  data.clientDisplayName,
                  style: VelvetText.subheading15,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (relativeDate != null) ...<Widget>[
                const SizedBox(width: VelvetSpacing.sm),
                Text(relativeDate, style: VelvetText.feedbackMutedSm),
              ],
            ],
          ),
          const SizedBox(height: VelvetSpacing.sm + 2),
          ReviewStarRow(rating: data.rating, size: 16, gap: 2),
          // `null` (no comment on the payload at all) drops the body line and
          // its leading gap; an EMPTY string keeps both, exactly as before the
          // nullable widening — see [ReviewCardData.comment].
          if (comment != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.sm + 2),
            Text(comment, style: VelvetText.bodyStrong()),
          ],
          if (service != null && service.isNotEmpty) ...<Widget>[
            const SizedBox(height: VelvetSpacing.sm + 2),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.spa_outlined,
                  size: 13,
                  color: BrandColors.muted,
                ),
                const SizedBox(width: VelvetSpacing.xs + 1),
                Flexible(
                  child: Text(
                    service,
                    style: VelvetText.feedbackMuted12w600,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A camel ★ row for a 1–5 [rating]. Filled stars use [BrandColors.accentDeep];
/// the remaining stars are muted to [BrandColors.faint].
class ReviewStarRow extends StatelessWidget {
  const ReviewStarRow({
    super.key,
    required this.rating,
    this.size = 16,
    this.gap = 2,
  });

  final int rating;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < 5; i++) ...<Widget>[
          Icon(
            Icons.star_rounded,
            size: size,
            color: i < rating ? BrandColors.accentDeep : BrandColors.faint,
          ),
          if (i < 4) SizedBox(width: gap),
        ],
      ],
    );
  }
}

/// A small circular gradient avatar with an embossed person glyph — the same
/// camel→mocha treatment as the salon master card avatar, sized for a review
/// row. [seed] deterministically picks the gradient (never a fabricated photo).
class ReviewAvatar extends StatelessWidget {
  const ReviewAvatar({super.key, required this.seed});

  final String seed;

  static const List<List<Color>> _gradients = <List<Color>>[
    <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
    <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
    <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
    <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
    <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
    <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
  ];

  @override
  Widget build(BuildContext context) {
    final List<Color> gradient =
        _gradients[seed.hashCode.abs() % _gradients.length];
    return Container(
      height: 40,
      width: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: BrandColors.white.withValues(alpha: 0.82),
          size: 20,
        ),
      ),
    );
  }
}
