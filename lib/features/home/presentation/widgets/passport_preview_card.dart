// Phase 13.7 — "BEAUTY PASSPORT" preview card + "МІЙ РЕЙТИНГ" stat card.
//
// PassportPreviewCard shows a compact stat pill pointing to the passport page.
// The title "BEAUTY PASSPORT" is intentionally an untranslated English brand
// constant per the locked product decision.
//
// DELIBERATELY DATA-FREE: this tile is a pure navigation affordance (brand
// title + subtitle + glyph) and renders NO derived passport values, so it has
// nothing to disagree with the passport tab about. It is therefore NOT a
// Consumer — watching `passportProvider` here would fire
// GET /clients/me/passport on every Home hub build for data the tile does not
// display. The approved design (docs/signup-designs/) gives it no numeric slot;
// adding one is a design change, not a wire-up (see Phase 13.8 status note).
//
// MyRatingStatCard replaces the old ReviewsStatCard (Phase 13.7 revision):
// shows the client's aggregate two-sided rating (SVG star + n.n) or an em-dash
// when no rating yet. Client comments are never shown.
// TODO(backend): GET /clients/me/rating (two-sided client rating, excludes comments).

import 'package:flutter/material.dart';

import '../../../../core/icons/app_icon.dart';
import '../../../../core/icons/beautica_asset_icons.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/hub_widgets.dart';

/// Compact BEAUTY PASSPORT preview tile in the stat-pills row.
///
/// [onTap] navigates to `/passport` (Phase 13.8).
class PassportPreviewCard extends StatelessWidget {
  const PassportPreviewCard({super.key, required this.onTap});

  final VoidCallback onTap;

  // Pre-composed text styles.
  static final TextStyle _titleStyle = VelvetText.homePassportPreviewTitle;

  // fontSize 10 (down from 11) gives the long UA subtitle
  // "Твій б'юті-паспорт у Beautica" enough room to lay out in 2 lines at the
  // narrow half-width pill (~80–94dp text column at 320dp). The FittedBox below
  // is the safety net that absorbs any residual overflow (incl. text-scale 1.3)
  // so the string can never be ellipsis-cut.
  static final TextStyle _subtitleStyle =
      VelvetText.homePassportPreviewSubtitle;

  // Hoisted icon-circle decoration — withValues inside build() would allocate
  // a new Color on every rebuild; static final computes it once at class load.
  static final BoxDecoration _iconCircleDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    border: Border.all(color: BrandColors.faint.withValues(alpha: 0.4)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HubFlatCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm + 2,
        vertical: VelvetSpacing.md - 4,
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 32,
            width: 32,
            decoration: _iconCircleDecoration,
            child: const Center(
              child: AppIcon(
                BeauticaAssetIcons.passportFilled,
                size: 17,
                color: BrandColors.accentDeep,
              ),
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // "BEAUTY PASSPORT" — intentionally untranslated (brand constant).
                // Wrapped in the same FittedBox.scaleDown as the subtitle so the
                // brand title is never ellipsis-cut either at the narrow pill
                // width / text-scale 1.3 (e.g. "PASSPORT" no longer fits one line).
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    // ignore: avoid_hardcoded_strings — locked brand literal
                    'BEAUTY PASSPORT',
                    maxLines: 2,
                    softWrap: true,
                    style: _titleStyle,
                  ),
                ),
                const SizedBox(height: 2),
                // FittedBox.scaleDown shrinks the (already small) subtitle just
                // enough to keep the FULL UA string visible — no ellipsis — at
                // 320dp+ and across text scales up to the app's 1.3 clamp.
                // centerLeft keeps it left-aligned with the title above.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.homeHubPassportSubtitle,
                    maxLines: 2,
                    style: _subtitleStyle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stat tile that shows the client's aggregate two-sided rating
/// (SVG star icon + n.n) or an em-dash when no rating has been assigned yet.
///
/// [clientRating] is null when the backend rating endpoint hasn't yet returned
/// a value (backend GET /clients/me/rating, two-sided system — excludes comments).
/// [onTap] navigates to [RouteNames.myRating].
class MyRatingStatCard extends StatelessWidget {
  const MyRatingStatCard({
    super.key,
    required this.clientRating,
    required this.onTap,
  });

  final double? clientRating;
  final VoidCallback onTap;

  // Pre-composed text styles — no per-build allocation.
  // fontSize 10 (down from 11) mirrors the passport card's narrow-pill subtitle
  // treatment: the rating pill now takes the smaller 2-share of the 3:2 row, so
  // "Мій рейтинг" gets a tighter text column. The FittedBox.scaleDown wrappers
  // below are the safety net that absorb any residual overflow (incl. the long
  // UA label across two words at text-scale 1.3) so nothing is ever ellipsis-cut.
  static final TextStyle _labelStyle = VelvetText.homePassportStatLabel;
  static final TextStyle _valueRatedStyle =
      VelvetText.homePassportStatValueRated;
  static final TextStyle _valueEmptyStyle =
      VelvetText.homePassportStatValueEmpty;

  // Hoisted icon-circle decoration — withValues inside build() allocates a new
  // Color on every rebuild; static final computes it once at class load.
  static final BoxDecoration _iconCircleDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    border: Border.all(color: BrandColors.faint.withValues(alpha: 0.4)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The SVG star (BeauticaAssetIcons.star) in the icon circle is the rating's
    // star; the value text is just the number to avoid a duplicate glyph star.
    final String valueText = clientRating != null
        ? clientRating!.toStringAsFixed(1)
        : '—';
    final TextStyle valueStyle = clientRating != null
        ? _valueRatedStyle
        : _valueEmptyStyle;

    return HubFlatCard(
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm + 2,
        vertical: VelvetSpacing.md - 4,
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 32,
            width: 32,
            decoration: _iconCircleDecoration,
            child: const Center(
              child: AppIcon(
                BeauticaAssetIcons.star,
                size: 17,
                color: BrandColors.accentDeep,
              ),
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // FittedBox.scaleDown keeps the full "Мій рейтинг" label visible
                // (no ellipsis) at the narrower 2-share width and across text
                // scales up to the app's 1.3 clamp — matches the passport card.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.homeHubMyRating,
                    maxLines: 2,
                    softWrap: true,
                    style: _labelStyle,
                  ),
                ),
                const SizedBox(height: 2),
                // The value ("n.n" / "—") is short, but wrap it too so the
                // number is guaranteed to render fully at the narrow width.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(valueText, maxLines: 1, style: valueStyle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
