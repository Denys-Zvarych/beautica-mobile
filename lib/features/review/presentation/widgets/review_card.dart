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

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';

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
    this.onMore,
    this.showAvatar = true,
    this.dateLabel,
    this.dense = false,
    this.tagLabel,
    this.collapsedLines,
    this.expandLabel,
  });

  final ReviewCardData data;

  /// Widget-key namespace for this card (`salon-review` / `master-review`).
  final String keyPrefix;

  /// The booked service name (e.g. "Манікюр"), rendered as-is with no label,
  /// or null to hide the sub-line entirely.
  final String? serviceName;

  /// ADDITIVE (phase 424 D2): opens the report sheet. Hosts pass it only when
  /// the viewer is not the review's author. `null` (the default) renders no
  /// «⋮» and the header row is exactly as before.
  final VoidCallback? onMore;

  /// ADDITIVE (phase 545): `false` drops the avatar and its gap — the
  /// anonymous client comments on «Рейтинг клієнта» have no author (REV-D10).
  /// `true` (the default) renders the header exactly as before.
  final bool showAvatar;

  /// ADDITIVE (phase 545): a ready header date text (the comment's visit
  /// month) shown instead of the relative [ReviewCardData.createdAt] date.
  /// `null` (the default) keeps the relative date.
  final String? dateLabel;

  /// ADDITIVE (M572): the compact comment row — ONE meta line
  /// `[★ 12dp][date][tag?] … [⋮]`, then the text. No name or avatar slot.
  /// `false` (the default) renders the classic card exactly as before.
  final bool dense;

  /// ADDITIVE (M572): a small caption tag after the date in the dense meta
  /// line («Ваш коментар»). Dense only.
  final String? tagLabel;

  /// ADDITIVE (M572): clamp the dense text to this many lines; a
  /// [expandLabel] link expands it in place (one-way). `null` = unclamped.
  final int? collapsedLines;

  /// ADDITIVE (M572): the «Ще» link label. `null` disables clamping.
  final String? expandLabel;

  /// Widget key of the «⋮» slot for the card of review [id].
  static Key moreKey(String keyPrefix, String id) => Key('$keyPrefix-more-$id');

  /// Widget key of the dense text expand link for review [id].
  static Key expandKey(String keyPrefix, String id) =>
      Key('$keyPrefix-expand-$id');

  /// Widget key of the dense text for review [id].
  static Key textKey(String keyPrefix, String id) => Key('$keyPrefix-text-$id');

  /// The dense meta line is pinned to the «⋮» hit height so a row without
  /// «⋮» (already reported) is exactly as tall as one with it.
  static const double _denseMetaHeight = 40;

  @override
  Widget build(BuildContext context) =>
      dense ? _denseCard(context) : _classicCard(context);

  Widget _denseCard(BuildContext context) {
    final VoidCallback? more = onMore;
    final String? date = dateLabel;
    final String? tag = tagLabel;
    final String? comment = data.comment;
    return NeumorphicCard(
      key: Key('$keyPrefix-${data.id}'),
      // Right padding 4: the «⋮» hit box (44 wide, nudged 10 dp right) sits in
      // the corner; the text gets the missing 8 back (right edge = 12).
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.sm + 4,
        VelvetSpacing.xs,
        VelvetSpacing.xs,
        VelvetSpacing.sm + 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: _denseMetaHeight,
            child: Row(
              children: <Widget>[
                // Priority when space runs out: stars and date never shrink;
                // the tag ellipsizes.
                ReviewStarRow(rating: data.rating, size: 12, gap: 2),
                if (date != null) ...<Widget>[
                  const SizedBox(width: VelvetSpacing.sm - 2),
                  Text(date, style: VelvetText.feedbackMutedSm, maxLines: 1),
                ],
                if (tag != null) ...<Widget>[
                  const SizedBox(width: VelvetSpacing.sm - 2),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ReviewCaptionTag(label: tag),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (more != null)
                  ReviewMoreButton(
                    tapKey: ReviewCard.moreKey(keyPrefix, data.id),
                    onTap: more,
                  ),
              ],
            ),
          ),
          if (comment != null && comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: VelvetSpacing.sm),
              child: _ClampedText(
                key: ReviewCard.textKey(keyPrefix, data.id),
                text: comment,
                maxLines: collapsedLines,
                expandLabel: expandLabel,
                expandKey: ReviewCard.expandKey(keyPrefix, data.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _classicCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final VoidCallback? more = onMore;
    final DateTime? createdAt = data.createdAt;
    final String? relativeDate =
        dateLabel ??
        (createdAt == null ? null : formatRelativeDate(l10n, createdAt));
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
              if (showAvatar) ...<Widget>[
                ReviewAvatar(seed: data.id),
                const SizedBox(width: VelvetSpacing.sm + 2),
              ],
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
              if (more != null)
                ReviewMoreButton(
                  tapKey: ReviewCard.moreKey(keyPrefix, data.id),
                  onTap: more,
                ),
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

/// M572 — the dense text clamped to [maxLines] with a [expandLabel] link when
/// it overflows. Expanding is one-way (no «Згорнути»): the row grows in place.
/// The expanded flag is the ONLY local state a comment row carries. Without a
/// [maxLines] or an [expandLabel] the text renders unclamped.
class _ClampedText extends StatefulWidget {
  const _ClampedText({
    super.key,
    required this.text,
    required this.maxLines,
    required this.expandLabel,
    required this.expandKey,
  });

  final String text;
  final int? maxLines;
  final String? expandLabel;
  final Key expandKey;

  @override
  State<_ClampedText> createState() => _ClampedTextState();
}

class _ClampedTextState extends State<_ClampedText> {
  bool _expanded = false;

  static final TextStyle _style = VelvetText.bodyStrong();

  // The last overflow measurement and what it was measured for: layout passes
  // that change none of these (rebuilds, scrolling) reuse it.
  bool? _overflows;
  double? _measuredWidth;
  TextScaler? _measuredScaler;
  String? _measuredText;
  Locale? _measuredLocale;
  TextStyle? _measuredStyle;

  @override
  Widget build(BuildContext context) {
    final int? lines = widget.maxLines;
    final String? label = widget.expandLabel;
    if (lines == null || label == null || _expanded) {
      return Text(widget.text, style: _style);
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final bool clamp = _measureOverflow(context, c.maxWidth, lines);
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                widget.text,
                style: _style,
                maxLines: clamp ? lines : null,
                overflow: clamp ? TextOverflow.ellipsis : null,
              ),
              if (clamp)
                Semantics(
                  button: true,
                  label: label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: widget.expandKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _expanded = true),
                    // The label sits at the top of the hit strip, so the row
                    // only grows by the link's line.
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: 2,
                        bottom: 6,
                        right: VelvetSpacing.lg,
                      ),
                      child: Text(label, style: VelvetText.linkCompact),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Whether the text needs more than [lines] lines at [maxWidth], measured
  /// with exactly what the rendered [Text] resolves (ambient style, locale,
  /// text-height behaviour, scaler). Cached per (text, width, scaler, locale).
  bool _measureOverflow(BuildContext context, double maxWidth, int lines) {
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final Locale? locale = Localizations.maybeLocaleOf(context);
    final DefaultTextStyle ambient = DefaultTextStyle.of(context);
    final TextStyle resolved = ambient.style.merge(_style);
    final bool? cached = _overflows;
    if (cached != null &&
        _measuredStyle == resolved &&
        _measuredWidth == maxWidth &&
        _measuredScaler == scaler &&
        _measuredText == widget.text &&
        _measuredLocale == locale) {
      return cached;
    }
    final TextPainter tp = TextPainter(
      text: TextSpan(text: widget.text, style: resolved),
      maxLines: lines,
      textDirection: Directionality.of(context),
      textScaler: scaler,
      locale: locale,
      textWidthBasis: ambient.textWidthBasis,
      textHeightBehavior:
          ambient.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
    )..layout(maxWidth: maxWidth);
    final bool overflows = tp.didExceedMaxLines;
    tp.dispose();
    _overflows = overflows;
    _measuredWidth = maxWidth;
    _measuredScaler = scaler;
    _measuredText = widget.text;
    _measuredLocale = locale;
    _measuredStyle = resolved;
    return overflows;
  }
}

/// M572 — the small caption tag («Ваш коментар»). Same geometry as the
/// shipped `BlockedTag` (pill, 6/2 padding), camel tint instead of error, no
/// icon.
class ReviewCaptionTag extends StatelessWidget {
  const ReviewCaptionTag({super.key, required this.label});

  final String label;

  static final TextStyle _style = VelvetText.feedbackAccentTag;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BrandColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Text(
        label,
        style: _style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Phase 424 — the review card's «⋮» affordance. Quiet on purpose: a muted
/// glyph with no surface of its own, so a list of reviews does not read as a
/// list of buttons. 40 dp tall so the header row keeps the avatar's 40 dp
/// height (the card does not grow); 44 wide to stay comfortably tappable. It
/// pulls 10 dp into the card's right padding so the glyph's optical edge lines
/// up with the card content edge.
///
/// [tapKey] sits on the [GestureDetector] — the hit target — NOT on this
/// widget: the root is a `Transform` (optical nudge) and `RenderTransform.
/// hitTest` never adds itself to the hit path, so `tester.tap(find.byKey(…))`
/// on the root key would always be refused.
class ReviewMoreButton extends StatelessWidget {
  const ReviewMoreButton({
    super.key,
    this.tapKey,
    required this.onTap,
    this.icon = Icons.more_vert_rounded,
    this.semanticLabel,
  });

  /// Key of the tappable surface (see class doc).
  final Key? tapKey;
  final VoidCallback onTap;

  /// ADDITIVE (phase 425): the glyph. Defaults to the review card's «⋮»; the
  /// booking client strip passes `Icons.more_horiz_rounded` («⋯»).
  final IconData icon;

  /// ADDITIVE (phase 425): the spoken label. `null` keeps
  /// «Більше дій з відгуком».
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(10, 0),
      child: Semantics(
        button: true,
        label: semanticLabel ?? AppLocalizations.of(context).reviewMoreActions,
        excludeSemantics: true,
        child: GestureDetector(
          key: tapKey,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 40,
            width: 44,
            child: Icon(icon, size: 20, color: BrandColors.muted),
          ),
        ),
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

  static const int _count = 5;

  @override
  Widget build(BuildContext context) {
    // ONE tint pass for the whole row (mobile-perf, 2026-11-14) instead of a
    // `ColorFilter` — and so a `saveLayer` — per star: the five glyphs are
    // drawn untinted (`multicolor: true`, only their alpha matters) and a
    // single `ShaderMask(srcIn)` paints them with a hard-stop gradient —
    // [BrandColors.accentDeep] up to the middle of the gap after the last
    // filled star, [BrandColors.faint] after it. The split falls inside a
    // glyph-free gap, so every star is exactly one colour, as before.
    final int filled = rating.clamp(0, _count);
    final double width = _count * size + (_count - 1) * gap;
    final double split = filled == 0
        ? 0
        : filled == _count
        ? 1
        : (filled * (size + gap) - gap / 2) / width;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => LinearGradient(
        colors: const <Color>[
          BrandColors.accentDeep,
          BrandColors.accentDeep,
          BrandColors.faint,
          BrandColors.faint,
        ],
        stops: <double>[0, split, split, 1],
      ).createShader(bounds),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < _count; i++) ...<Widget>[
            AppIcon(BeauticaAssetIcons.star, size: size, multicolor: true),
            if (i < _count - 1) SizedBox(width: gap),
          ],
        ],
      ),
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
