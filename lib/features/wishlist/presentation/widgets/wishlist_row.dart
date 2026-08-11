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
//   * its name column is 186 dp at 360 dp and 146 dp at 320 dp — wide enough
//     that «Анастасія Мельниченко» (~120 dp) renders on ONE line at both, so
//     removing the avatar would buy nothing. (Was 202/162 before
//     `WishlistHeartButton`'s tap-target fix widened its invisible hit box
//     from 32dp to 48dp — see that file's doc comment.)
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

import 'dart:developer' as developer;

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

  /// The CTA column's FLOOR — a `minWidth`, not a fixed width, so «Записатись»
  /// is still the same size on every MASTER row however long the duration
  /// beside it is (a button that changed width down a list would read as a
  /// different control), while a longer label (a SALON row's «Обрати
  /// майстра») is free to grow past the floor to its own natural size instead
  /// of being squeezed into it.
  ///
  /// Before Phase G's salon arm, this was the button's exact width via a
  /// `SizedBox`. «Обрати майстра» (natural ~114 dp, `HubFilledButton`'s own
  /// `VelvetSpacing.md` padding included) is wider than this floor (112 dp,
  /// sized for «Записатись», natural ~78 dp) — pinning it to exactly 112 dp
  /// forced `HubFilledButton`'s `FittedBox` to shrink the label by a hair to
  /// fit, which read as the label filling the button edge-to-edge with no
  /// breathing room (the reported "text getting whole button length" bug).
  /// A floor instead of a fixed width lets `HubFilledButton`'s own padding
  /// give the label real margin on BOTH arms, and adapts automatically to
  /// each label's own length — including the EN translations, which are
  /// already live today (`app_en.arb:3239,3243` — "Book" / "Choose a
  /// master"), not a hypothetical future one — no re-measured magic number
  /// to keep in sync.
  static const double _kActionWidth = 112;

  /// The CTA column's CEILING when it sits BESIDE the duration/price [Wrap]
  /// — restores the safety valve the floor-only `minWidth` removed.
  ///
  /// `_kActionWidth` above has no upper bound, so at a large accessibility
  /// text scale the salon arm's «Обрати майстра» grows the button without
  /// limit (natural width scales with the font) and pushes the side-by-side
  /// `Row` past its available width — reproduced empirically at 320 dp +
  /// 2.0x text scale: a 255.3 dp button on a 320 dp phone overflows the row
  /// by 15 px.
  ///
  /// Set to `_kActionWidth + VelvetSpacing.xxl` (160 dp) — comfortably above
  /// «Обрати майстра»'s measured natural width at 1.0x (145.7 dp: 113.7 dp
  /// label + `HubFilledButton`'s own 2 × `VelvetSpacing.md` padding), so the
  /// normal case never brushes the ceiling at 1.0x. Reusing an existing
  /// spacing token rather than a fresh magic number, per the file-wide
  /// no-magic-numbers rule.
  ///
  /// mobile-security (MEDIUM, capped scaling): the first fix clamped the
  /// side-by-side layout at this ceiling and let `HubFilledButton`'s own
  /// `FittedBox(fit: scaleDown)` shrink the label back down whenever content
  /// exceeded it. That stopped the crash/overflow, but it also capped the
  /// label's EFFECTIVE font size — measured salon-label sizes plateaued
  /// around ~12.5sp from OS text scale 1.3x through 3.0x, so the
  /// accessibility setting stopped having any further effect past a fairly
  /// common "larger text" preference. `FittedBox` shrinking a label back to
  /// near-1.0x size is exactly the failure mode this constant now exists to
  /// AVOID rather than to lean on.
  ///
  /// The fix: [_naturalCtaWidth] measures the button's true, unclamped width
  /// at the ambient text scale ([build]'s `textScaler`), and [build] compares
  /// it against this ceiling to choose the layout, NOT to clamp the button
  /// inside it —
  ///   * below the ceiling: the side-by-side `Row` below, CTA still wrapped
  ///     in the `ConstrainedBox(minWidth: _kActionWidth, maxWidth:
  ///     _kActionWidthCeiling)` + `IntrinsicWidth` pair (unchanged from the
  ///     original fix — this path is what keeps the 1.0x and sub-ceiling
  ///     cases pixel-identical to before);
  ///   * at/above the ceiling: the CTA drops to its OWN full-width line below
  ///     the duration/price `Wrap` instead of beside it (see [build]). A
  ///     full card-width line is far wider than this 160 dp ceiling — at
  ///     320 dp it is ~248 dp even after page + card padding — so the label
  ///     renders at (or very close to) its genuine scaled size, and
  ///     `FittedBox` only has to act as the last-resort guard its own doc
  ///     comment describes, for a scale extreme enough to still outgrow a
  ///     full card width.
  ///
  /// Rejected alternatives (see the mobile-security finding this fixes for
  /// the full brief):
  ///   * raising this constant to a bigger fixed value — reintroduces the
  ///     exact same plateau at some larger scale, and this `Row` has a
  ///     second element (the duration/price `Wrap`) that grows with the SAME
  ///     text scale, so any fixed ceiling big enough to satisfy an extreme
  ///     scale would starve or overflow the `Wrap` at that same scale
  ///     instead. Reflowing to a `Column` sidesteps having to solve for two
  ///     growing siblings sharing one `Row` at all;
  ///   * a ceiling that is itself a function of text scale — same problem
  ///     one step removed: it would still need to model how much room the
  ///     `Wrap` needs at that scale to stay correct, is exactly the "bigger
  ///     magic number" this doc comment's sibling constant already forbids,
  ///     and buys nothing the reflow does not already give for free;
  ///   * wrapping the label to two lines instead of reflowing the whole
  ///     button — keeps the compact-pill CTA a single control at every
  ///     scale (a two-line pill reads as broken chrome, not an accessibility
  ///     accommodation) and needs no new wrap-detection logic beyond the
  ///     measurement already required to pick a layout at all.
  static const double _kActionWidthCeiling = _kActionWidth + VelvetSpacing.xxl;

  /// Measures the CTA button's natural, UNCLAMPED width — [label] rendered
  /// in [VelvetText.cta135] at the ambient [textScaler], plus
  /// `HubFilledButton`'s own `2 × VelvetSpacing.md` horizontal padding — so
  /// [build] can decide whether the side-by-side layout still fits it or the
  /// row must reflow (see [_kActionWidthCeiling]'s doc comment). Both the
  /// style and the padding are the SAME public constants `HubFilledButton`
  /// itself renders with (`hub_widgets.dart`), re-derived here rather than
  /// duplicated as a private literal so a future change to either one moves
  /// this measurement automatically.
  ///
  /// Not memoised, and that is already optimal: [build] only re-runs when
  /// [label] or the ambient text scale actually changes — that IS the memo,
  /// the same reasoning `master_address_block.dart`'s own fit-measuring
  /// helper documents for the identical shape of check.
  ///
  /// Defended the same way that helper is against `TextPainter.layout`
  /// throwing on a malformed UTF-16 [label] — Postgres/ARB sources make this
  /// unreachable in practice, but a throw here would fail during LAYOUT
  /// rather than paint, which degrades far harder. Falls back to `0`, which
  /// always compares BELOW the ceiling — i.e. the pre-fix, ceiling-clamped
  /// side-by-side layout — so a measurement failure never over-promises a
  /// full-width reflow it could not actually verify fits.
  static double _naturalCtaWidth(
    BuildContext context,
    String label,
    TextScaler textScaler,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: label, style: VelvetText.cta135),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
      maxLines: 1,
    );
    try {
      painter.layout();
      return painter.width + 2 * VelvetSpacing.md;
    } catch (error, stackTrace) {
      developer.log(
        'wishlist row CTA width measurement failed; falling back to the '
        'ceiling-clamped side-by-side layout',
        name: 'feature.wishlist',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return 0;
    } finally {
      // In `finally` so a throw cannot leak the native paragraph handle.
      painter.dispose();
    }
  }

  static final Color _hairlineColor = BrandColors.faint.withValues(
    alpha: _kHairlineAlpha,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? duration = item.durationLabel();
    final String ctaLabel = item.bookCtaLabel(l10n);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    // See `_kActionWidthCeiling`'s doc comment: this is the ONLY thing that
    // decides which of the two layouts below renders. Below the ceiling,
    // nothing changes from before this fix; at/above it, the CTA reflows to
    // its own full-width line instead of being squeezed by
    // `HubFilledButton`'s `FittedBox`.
    final bool ctaReflows =
        _naturalCtaWidth(context, ctaLabel, textScaler) > _kActionWidthCeiling;
    final Widget metaWrap = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: VelvetSpacing.xs,
      runSpacing: VelvetSpacing.xs / 2,
      children: <Widget>[
        // Time + price wear the master booking card's own treatments: a
        // muted caption, then the figure in a pill.
        if (duration != null) Text(duration, style: VelvetText.masterCardTime),
        if (item.showsPrice) PriceTag(price: item.priceLabel),
      ],
    );
    final Widget ctaButton = HubFilledButton(
      key: Key('wishlist_row_book_${item.favoriteTargetId}'),
      label: ctaLabel,
      onTap: onBook,
    );
    return HubFlatCard(
      radius: VelvetRadii.field,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              HubAvatar(
                initials: item.avatarInitials(l10n),
                size: _kAvatar,
                imageUrl: item.avatarImageUrl,
                fallbackIcon: item.avatarFallbackIcon,
              ),
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
                        item.sourceType == WishlistSourceType.salon
                            ? const Icon(
                                Icons.storefront_rounded,
                                size: _kMetaGlyph,
                                color: BrandColors.accent,
                              )
                            : const Icon(
                                Icons.person_outline_rounded,
                                size: _kMetaGlyph,
                                color: BrandColors.accent,
                              ),
                        const SizedBox(width: AppSpacing.xxs),
                        // Also unbounded — «Анастасія Мельниченко» renders whole.
                        Expanded(
                          child: Text(
                            item.displayTitle(l10n),
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
                buttonKey: Key('wishlist_row_heart_${item.favoriteTargetId}'),
                onTap: onUnfavourite,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(height: _kHairline, color: _hairlineColor),
          const SizedBox(height: AppSpacing.xs),
          if (ctaReflows)
            // At/above the ceiling (see `_kActionWidthCeiling`'s doc
            // comment): the CTA can no longer sit beside the duration/price
            // `Wrap` without either overflowing the row or being squeezed
            // back down by `HubFilledButton`'s `FittedBox` — so it drops to
            // its own full-width line below the meta content instead, where
            // it renders at (or very close to) its genuine scaled size.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                metaWrap,
                const SizedBox(height: AppSpacing.xs),
                SizedBox(width: double.infinity, child: ctaButton),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: metaWrap),
                const SizedBox(width: AppSpacing.xs),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: _kActionWidth,
                    maxWidth: _kActionWidthCeiling,
                  ),
                  // See `_kActionWidthCeiling`'s doc comment: `IntrinsicWidth`
                  // is load-bearing here, not decorative — it is what keeps a
                  // short label (e.g. «Записатись», already at its floor) from
                  // being inflated to the ceiling by `HubFilledButton`'s own
                  // `Align`-based centring.
                  child: IntrinsicWidth(child: ctaButton),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
