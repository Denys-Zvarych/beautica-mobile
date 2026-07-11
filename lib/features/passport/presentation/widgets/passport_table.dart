// Phase 13.8 — BEAUTY PASSPORT "document" card (the page hero).
//
// Ported 1:1 from the approved preview app
// `docs/signup-designs/BeautyPassport/lib/widgets/passport_widgets.dart`.
// Token swap: `VelvetColors.*` → `BrandColors.*`; `VelvetSpacing`/`VelvetRadii`/
// `VelvetShadows` resolve to the project tokens. Ukrainian column labels and the
// footer/budget strings come from l10n; the brand title "BEAUTY PASSPORT" and
// the subtitle «Твій б'юті-паспорт у Beautica» stay untranslated brand
// literals per the locked product decision.
//
// Read-only by design: every value is auto-derived, there is NO add/edit
// affordance anywhere (no «+ Додати ще»).
//
// Perf: per-build TextStyle / withValues colours are hoisted to static final,
// and static decorations are const where the API allows.

import 'package:flutter/material.dart';

import '../../../../core/icons/app_icon.dart';
import '../../../../core/icons/beautica_asset_icons.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';

/// The locked, untranslated product title.
// ignore: constant_identifier_names — brand literal, kept verbatim.
const String kBeautyPassportTitle = 'BEAUTY PASSPORT';

/// The locked, untranslated product subtitle.
const String kBeautyPassportSubtitle = 'Твій б’юті-паспорт у Beautica';

/// The whole passport rendered as ONE neumorphic card. The card clips its own
/// rounded corners so the oversized «B» watermark in the top-right is trimmed
/// cleanly by the card edge. Read-only by design — every value is auto-derived.
class PassportCard extends StatelessWidget {
  const PassportCard({
    super.key,
    required this.procedures,
    required this.districts,
    required this.budgetValue,
    required this.reviewsLeft,
    required this.memberSince,
  });

  /// Top-3 favourite procedure labels (rank-ordered, most-frequent first).
  final List<String> procedures;

  /// Top-3 favourite district labels (rank-ordered, most-frequent first).
  final List<String> districts;

  /// The single budget value chip, e.g. «до 800 грн».
  final String budgetValue;

  final int reviewsLeft;

  /// Member-since label for the footer "issued" line, e.g. «2024».
  final String memberSince;

  // A soft warm blush fill: a subtle vertical gradient from a lighter, creamier
  // top to a slightly warmer bottom — derived from the existing warm tokens so
  // it stays inside the Warm Mocha family. Hoisted so it is computed once.
  static final BoxDecoration _cardDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color.lerp(BrandColors.base, BrandColors.shadowLightStrong, 0.45)!,
        Color.lerp(BrandColors.base, BrandColors.accent, 0.10)!,
      ],
    ),
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    boxShadow: VelvetShadows.extrudedCard,
  );

  static final BorderRadius _clipRadius = BorderRadius.circular(
    VelvetRadii.card,
  );

  // The embossed «B» watermark style — hoisted (copyWith + withValues allocate).
  static final TextStyle _watermarkStyle = VelvetText.passportWatermark
      .copyWith(color: BrandColors.accentDeep.withValues(alpha: 0.09));

  static final Color _hairlineColor = BrandColors.faint.withValues(alpha: 0.35);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // L4 (perf): the card's dual-blur `extrudedCard` shadow + gradient +
    // ClipRRect is the most expensive paint on the page. Isolating it behind a
    // [RepaintBoundary] lets its layer cache independently, so a top-bar /
    // profile repaint never re-rasterises the blur.
    return RepaintBoundary(
      child: Container(
        decoration: _cardDecoration,
        child: ClipRRect(
          borderRadius: _clipRadius,
          child: Stack(
            children: <Widget>[
              // The embossed «B» monogram, low-opacity, bled off the top-right
              // corner so the card edge trims it like a printed document seal.
              Positioned(
                top: -34,
                right: -14,
                child: Text(
                  // ignore: avoid_hardcoded_strings — decorative brand monogram.
                  'B',
                  style: _watermarkStyle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(VelvetSpacing.md + 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const _PassportHeader(),
                    const SizedBox(height: VelvetSpacing.md + 2),
                    // The three derived columns, separated by ruled hairlines.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: _PassportColumn(
                              icon: Icons.workspace_premium_rounded,
                              label: l10n.passportColumnProcedures,
                              items: procedures,
                            ),
                          ),
                          const _ColumnRule(),
                          Expanded(
                            child: _PassportColumn(
                              icon: Icons.location_on_rounded,
                              iconWidget: const AppIcon(
                                BeauticaAssetIcons.locationMarker,
                                size: 14,
                                color: BrandColors.accentDeep,
                              ),
                              label: l10n.passportColumnDistricts,
                              items: districts,
                            ),
                          ),
                          const _ColumnRule(),
                          Expanded(
                            child: _PassportColumn(
                              icon: Icons.account_balance_wallet_rounded,
                              label: l10n.passportColumnBudget,
                              items: <String>[budgetValue],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: VelvetSpacing.md + 2),
                    Container(height: 1, color: _hairlineColor),
                    const SizedBox(height: VelvetSpacing.sm + 4),
                    _PassportFooter(
                      reviewsLeft: reviewsLeft,
                      memberSince: memberSince,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card header: a recessed crown well + the locked English product title
/// «BEAUTY PASSPORT» and its Ukrainian subtitle. The title is never translated.
class _PassportHeader extends StatelessWidget {
  const _PassportHeader();

  static const BoxDecoration _crownWellDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.all(Radius.circular(12)),
    boxShadow: VelvetShadows.extrudedSmall,
  );

  static final TextStyle _titleStyle = VelvetText.passportSectionTitle;

  static final TextStyle _subtitleStyle = VelvetText.body125;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          height: 38,
          width: 38,
          alignment: Alignment.center,
          decoration: _crownWellDecoration,
          child: const Icon(
            Icons.workspace_premium_rounded,
            size: 20,
            color: BrandColors.accentDeep,
          ),
        ),
        const SizedBox(width: VelvetSpacing.sm + 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(kBeautyPassportTitle, style: _titleStyle),
              const SizedBox(height: 2),
              Text(kBeautyPassportSubtitle, style: _subtitleStyle),
            ],
          ),
        ),
      ],
    );
  }
}

/// A single passport column: an icon + eyebrow label, then a vertical stack of
/// chips (rank-ordered, most-frequent first). Read-only — auto-derived values
/// with no add affordance.
class _PassportColumn extends StatelessWidget {
  const _PassportColumn({
    required this.icon,
    required this.label,
    required this.items,
    this.iconWidget,
  });

  final IconData icon;

  /// Optional pre-built icon widget (e.g. an [AppIcon] SVG). When non-null it
  /// replaces the Material [Icon] built from [icon]; callers must size/tint it
  /// to match (14 px, [BrandColors.accentDeep]).
  final Widget? iconWidget;
  final String label;
  final List<String> items;

  static final TextStyle _labelStyle = VelvetText.passportTableLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: VelvetSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              iconWidget ?? Icon(icon, size: 14, color: BrandColors.accentDeep),
              const SizedBox(width: 5),
              Expanded(child: Text(label.toUpperCase(), style: _labelStyle)),
            ],
          ),
          const SizedBox(height: VelvetSpacing.sm + 2),
          for (int i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 6),
            _PassportTag(label: items[i]),
          ],
        ],
      ),
    );
  }
}

/// A read-only derived chip: a soft cream pill carrying one preference. No
/// close/edit affordance — these are auto-derived, not user-managed tags.
class _PassportTag extends StatelessWidget {
  const _PassportTag({required this.label});

  final String label;

  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.shadowLightStrong.withValues(alpha: 0.85),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: BrandColors.accent.withValues(alpha: 0.22)),
  );

  static final TextStyle _textStyle = VelvetText.passportTableText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: _decoration,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _textStyle,
      ),
    );
  }
}

/// A thin vertical hairline separating the passport columns.
class _ColumnRule extends StatelessWidget {
  const _ColumnRule();

  static final Color _color = BrandColors.faint.withValues(alpha: 0.40);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.only(right: VelvetSpacing.sm + 2, top: 2),
      color: _color,
    );
  }
}

/// The footer line: the client's reviews-left standing, rendered in the EXACT
/// language of the Головна (Home Hub) stat card (`passport_preview_card.dart`):
/// a 32×32 circular icon well + a w800 title over a lighter subtitle.
class _PassportFooter extends StatelessWidget {
  const _PassportFooter({required this.reviewsLeft, required this.memberSince});

  final int reviewsLeft;
  final String memberSince;

  static final TextStyle _titleStyle = VelvetText.passportFooterTitle;
  static final TextStyle _subtitleStyle = VelvetText.passportFooterSubtitle;

  static final BoxDecoration _iconCircleDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    border: Border.all(color: BrandColors.faint.withValues(alpha: 0.4)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
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
              Text(
                l10n.passportReviewsLeft(reviewsLeft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _titleStyle,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.passportMemberSince(memberSince),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _subtitleStyle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
