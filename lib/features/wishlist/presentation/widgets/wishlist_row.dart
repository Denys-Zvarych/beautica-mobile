// Phase 239 — the FULL-WIDTH wish-list row.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/widgets/passport_widgets.dart`
// (`WishlistRow`). Preview tokens resolved to the shipped scale; Ukrainian
// strings routed through the ARB; `PriceTag` is the shared
// `core/widgets/price_tag.dart`.
//
// Used by exactly ONE surface — the «Усі збережені» full-list page. The
// passport page's `WishlistCompactCard` is a separate, deliberately different
// widget.
//
//   ╭──╮  Нарощування вій —                    ♥
//   │ОК│  класика 2D
//   ╰──╯  👤 Олена Ковальчук
//   ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈
//   60 хв  ( 800 ₴ )               [ Записатись ]
//
// ## Why this was NOT flattened to match the compact card
//
// It keeps its leading avatar AND its person glyph, and that is coherent
// scaling rather than drift:
//   * its name column is 202 dp at 360 dp and 162 dp at 320 dp — wide enough
//     that «Анастасія Мельниченко» (~120 dp) renders on ONE line at both, so
//     removing the avatar would buy nothing;
//   * the person glyph does the attribution job EXPLICITLY. The compact card
//     cannot afford it — glyph + gap costs 18 dp against a 126 dp text column;
//   * the two surfaces are deliberately different densities and their tokens
//     scale in step: title `cardTitle()` (Comfortaa 14) → `svcCardName` (12);
//     attribution `body14Text` (Nunito 11) → `bookingCardSubtle` (10).
//
// ## NO TRUNCATION
//
// The service name is an [Expanded] [Text] with no `maxLines` and no
// `TextOverflow`, so it wraps inside its own row; the master name is likewise
// unbounded; the duration/price pair sits in a [Wrap], so a wide band drops to
// a second run rather than clipping.

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/price_tag.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../home/presentation/widgets/hub_widgets.dart';
import '../../domain/wishlist_service.dart';
import 'wishlist_entry_labels.dart';
import 'wishlist_heart_button.dart';

/// One saved (master, service) pair at full width, with room for the duration
/// and the person glyph the compact card has to drop.
class WishlistRow extends StatelessWidget {
  const WishlistRow({
    super.key,
    required this.item,
    required this.onBook,
    required this.onUnfavourite,
  });

  final WishlistService item;

  /// Starts a booking for this exact master + service.
  final VoidCallback onBook;

  /// Un-favourites the entry (the filled heart, tapped off).
  final VoidCallback onUnfavourite;

  /// The master mark at this density.
  static const double _kAvatar = 38;

  /// The inline attribution glyph, and the eyebrow-scale glyph size shared with
  /// the passport's derived block.
  static const double _kMetaGlyph = 14;

  /// Hairline rule thickness.
  static const double _kHairline = 1;

  /// Alpha of the in-card hairline. Soft on purpose: it separates two halves of
  /// ONE card, not two cards.
  static const double _kHairlineAlpha = 0.35;

  /// The CTA column. A fixed width rather than a `Flexible`, so «Записатись»
  /// is the same size on every row however long the duration beside it is —
  /// a button that changed width down a list would read as a different control.
  static const double _kActionWidth = 112;

  static final Color _hairlineColor = BrandColors.faint.withValues(
    alpha: _kHairlineAlpha,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? duration = item.durationLabel();
    return HubFlatCard(
      radius: VelvetRadii.field,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              HubAvatar(initials: item.masterInitials(l10n), size: _kAvatar),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Deliberately unbounded: wraps, never ellipsises. The row
                    // anchor — the system's "service name on a card".
                    Text(item.serviceName, style: VelvetText.cardTitle()),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.person_outline_rounded,
                          size: _kMetaGlyph,
                          color: BrandColors.accent,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        // Also unbounded — «Анастасія Мельниченко» renders whole.
                        Expanded(
                          child: Text(
                            item.displayMasterName(l10n),
                            style: VelvetText.body14Text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: VelvetSpacing.xs),
              WishlistHeartButton(
                buttonKey: Key('wishlist_row_heart_${item.masterServiceId}'),
                onTap: onUnfavourite,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(height: _kHairline, color: _hairlineColor),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: VelvetSpacing.xs,
                  runSpacing: VelvetSpacing.xs / 2,
                  children: <Widget>[
                    // Time + price wear the master booking card's own
                    // treatments: a muted caption, then the figure in a pill.
                    if (duration != null)
                      Text(duration, style: VelvetText.masterCardTime),
                    if (item.showsPrice) PriceTag(price: item.priceLabel),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                width: _kActionWidth,
                child: HubFilledButton(
                  key: Key('wishlist_row_book_${item.masterServiceId}'),
                  label: l10n.wishlistBookCta,
                  onTap: onBook,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
