// Phase 238 — the COMPACT wish-list card.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/widgets/passport_widgets.dart`
// (`WishlistCompactCard`). Preview tokens resolved to the shipped scale;
// Ukrainian strings routed through the ARB; `PriceTag` is the shared
// `core/widgets/price_tag.dart` rather than the preview's local copy.
//
// One of the two cards in the passport page's non-scrolling horizontal line.
//
//   ┌─────────────────────────────┐
//   │ (АМ)                    ♥   │  header — master mark + un-favourite
//   │ Ламінування та              │  TITLE       — svcCardName
//   │ фарбування брів             │
//   │ Анастасія Мельниченко       │  ATTRIBUTION — bookingCardSubtle
//   │ 60 хв  ( 800 ₴ )            │  figure
//   │ [      Записатись      ]    │  action
//   └─────────────────────────────┘
//
// ## TITLE OVER ATTRIBUTION — the hierarchy is in the TOKENS
//
// The service is the card's title and the master is its attribution, stacked
// directly under it. `svcCardName` (Comfortaa 12/700 — the system's "service
// name on a card") over `bookingCardSubtle` (Nunito 10/700, MUTED — the shipped
// slot for a line that sits under a name and qualifies it). The pair is welded
// by the scale's tightest gap (`AppSpacing.xxs`) and cut off from the figure
// below by its widest in-card one (`AppSpacing.sm`), so the two lines read as
// ONE unit rather than as two entries in a list.
//
// ## NO TRUNCATION — the whole reason this redesign exists
//
// The service name and the master name carry NO `maxLines` and NO
// `TextOverflow`. They wrap down the card. «Ламінування та фарбування брів»
// needs ~204 dp against 126 dp of text at 360 dp and 106 dp at 320 dp, so it
// takes two lines at both — and the longest unbreakable word in the fixtures,
// «Ламінування» (~79 dp), clears even the 320 dp case. A name that did NOT fit
// would wrap inside itself; neither path can ellipsise.
//
// Cards sit inside an `IntrinsicHeight` row (see `wishlist_section.dart`), so a
// name that takes an extra line grows BOTH cards and the two «Записатись»
// buttons stay on one baseline. That is what the [Spacer] below is for.
//
// ## Why the avatar and the heart share a header row
//
// Two rearrangements were measured and REJECTED, both because they steal width
// from a line that cannot afford it at 320 dp (text column = 106 dp):
//   * HEART INLINE WITH THE TITLE leaves the service name 70 dp — narrower than
//     its own longest unbreakable word (79 dp), so the word would overflow its
//     box with no ellipsis to hide it. That is the exact failure this design
//     exists to prevent.
//   * AVATAR INLINE WITH THE MASTER NAME is safe for text («Мельниченко» is
//     60 dp) but forces the heart onto a row of its own — +18 dp per card,
//     enough to push the «Записатись» CTAs below the fold.
//
// So both stay in the header row and BOTH text lines keep the card's full
// width. The one field this card cannot carry is the person glyph the
// full-width row uses for attribution: glyph + gap costs 18 dp, which would push
// the longest master name to two lines even at 360 dp.

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/price_tag.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../home/presentation/widgets/hub_widgets.dart';
import '../../domain/wishlist_service.dart';
import 'wishlist_entry_labels.dart';
import 'wishlist_heart_button.dart';

/// One saved (master, service) pair, in the passport page's compact density.
class WishlistCompactCard extends StatelessWidget {
  const WishlistCompactCard({
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

  /// The master mark on this density. Smaller than the full-width row's 38 dp
  /// because the card has 126 dp of text to protect, not 202.
  static const double _kAvatar = 32;

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
              HubAvatar(
                initials: item.avatarInitials(l10n),
                size: _kAvatar,
                imageUrl: item.avatarImageUrl,
                fallbackIcon: item.avatarFallbackIcon,
              ),
              const Spacer(),
              WishlistHeartButton(
                buttonKey: Key('wishlist_card_heart_${item.favoriteTargetId}'),
                onTap: onUnfavourite,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // ── Title + attribution ────────────────────────────────────────────
          // Both UNBOUNDED — no `maxLines`, no `TextOverflow`. See the header.
          Text(item.serviceName, style: VelvetText.svcCardName),
          const SizedBox(height: AppSpacing.xxs),
          // NO icon on this line — width is the binding constraint here (see
          // the file header), and the avatar already carries the salon
          // signal for a SALON row. [displayTitle] resolves to the master's
          // name or the salon's name; never [displayMasterName] directly,
          // which would assert on a SALON row.
          Text(item.displayTitle(l10n), style: VelvetText.bookingCardSubtle),
          const SizedBox(height: AppSpacing.sm),
          // ── Duration + price, in the master booking card's treatments ──────
          // A [Wrap], so the pill drops to a SECOND RUN rather than colliding
          // with a long duration («2 год 30 хв» + «1 200 ₴» needs ~112 dp
          // against the card's 106 at 320 dp). Nothing can truncate: both
          // children size to their own content and the pill scales its text
          // down before it clips.
          if (duration != null || item.showsPrice)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.xxs,
              runSpacing: VelvetSpacing.xs / 2,
              children: <Widget>[
                if (duration != null)
                  Text(duration, style: VelvetText.masterCardTime),
                if (item.showsPrice)
                  PriceTag(
                    price: item.priceLabel,
                    verticalPadding: PriceTag.compactVerticalPadding,
                  ),
              ],
            ),
          // Pins the two cards' buttons to one baseline however many lines the
          // names above took. Only meaningful under the section's
          // `IntrinsicHeight`; harmless anywhere else.
          const Spacer(),
          const SizedBox(height: AppSpacing.xs),
          HubFilledButton(
            key: Key('wishlist_card_book_${item.favoriteTargetId}'),
            label: item.bookCtaLabel(l10n),
            onTap: onBook,
          ),
        ],
      ),
    );
  }
}
