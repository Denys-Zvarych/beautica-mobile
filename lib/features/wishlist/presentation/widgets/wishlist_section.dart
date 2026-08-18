// Phase 238 — the BEAUTY WISH LIST section on the passport page.
//
// Transcribed from the approved preview
// `docs/signup-designs/BeautyPassport/lib/screens/passport_screen.dart`
// (`_WishlistSection`). Preview tokens resolved to the shipped scale;
// Ukrainian strings routed through the ARB; the preview's local mutable list
// replaced by `wishlistProvider`.
//
// ## A LINE, NOT A RAIL
//
// The cards sit in a PLAIN [Row] showing exactly [_kPreviewCount] of them —
// two. There is no `ListView.horizontal`, no `SingleChildScrollView`, no
// carousel and no half-card peeking at the edge: nothing here suggests a
// horizontal gesture, because there isn't one.
//
// Two is a MEASURED number, not a round one. At 360 dp two cards are 150 dp
// wide (126 dp of text) and at 320 dp 130 dp (106 dp of text) — enough for the
// longest unbreakable word in the fixtures («Ламінування», ~79 dp). THREE cards
// would be 97 dp wide, i.e. 73 dp of text at 360 dp and 60 dp at 320 dp:
// narrower than a single word of the content they carry. Three was rejected
// outright.
//
// Everything that did not fit lives behind «Показати всі (N)». It is an OUTLINE
// button on purpose — it must read as this section's overflow control and not
// compete with the two camel-filled «Записатись» CTAs inside the cards, which
// are the section's real actions. It sits UNDER the row rather than as a
// trailing "+N" tile because a tile would consume one of only two card slots,
// half the visible content, just to say "there is more".
//
// ## The header is a brand literal
//
// «Beauty wish list» is an untranslated English product name sitting in
// Ukrainian copy, exactly like `BEAUTY PASSPORT` on the identity strip above
// it. It is passed to [HubSectionTitle] with `literal: true` — the flag the
// shipped app added for precisely this class of string — which renders it
// uppercase in Comfortaa 11 at `letterSpacing: 1.6`. Uppercase, not title case:
// [HubSectionTitle] uppercases every section header anyway, so title case would
// be the one odd header on the page, and uppercase makes the name read as a
// sibling of the strip's `BEAUTY PASSPORT` rather than as a caption.
//
// ## This section's states are INDEPENDENT of the derived block's
//
// A client with no booking history can still have favourites, and vice versa.
// The two never gate each other.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../home/presentation/widgets/hub_widgets.dart';
import '../../application/wishlist_notifier.dart';
import '../../domain/wishlist_service.dart';
import 'wishlist_compact_card.dart';
import 'wishlist_count_pill.dart';
import 'wishlist_removable.dart';
import 'wishlist_removal.dart';
import 'wishlist_states.dart';

/// The locked, untranslated product name of the wish-list section.
///
/// A named constant rather than an inline literal: `no_raw_ui_strings` is an
/// ERROR-severity gate in CI, and this is genuinely NOT a translatable string —
/// it is a product name, in the same class as `BEAUTY PASSPORT`.
// ignore: constant_identifier_names — brand literal, kept verbatim.
const String kBeautyWishListTitle = 'Beauty wish list';

/// The BEAUTY WISH LIST block on the passport page.
class WishlistSection extends ConsumerStatefulWidget {
  const WishlistSection({
    super.key,
    required this.onBook,
    required this.onFindMaster,
    required this.onShowAll,
  });

  /// Starts a booking for one saved (master, service) pair.
  final void Function(WishlistService item) onBook;

  /// Sends the client to discovery from the empty state.
  final VoidCallback onFindMaster;

  /// Opens the full «Усі збережені» page.
  final VoidCallback onShowAll;

  /// How many cards the non-scrolling line shows. See the file header for the
  /// measurement that fixes it at two.
  static const int previewCount = 2;

  @override
  ConsumerState<WishlistSection> createState() => _WishlistSectionState();
}

class _WishlistSectionState extends ConsumerState<WishlistSection>
    with WishlistRemovalHost {
  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<WishlistService>> async = ref.watch(wishlistProvider);

    // EXPLICIT BRANCH ORDER — deliberately NOT `.when()`.
    //
    // `AsyncLoading(retrying: true)` still reports `hasError`, so a
    // `hasError`-first order (or `.when()`) would paint the failure card
    // straight back under the client's finger the instant they tap «Спробувати
    // знову». Matching `isLoading` FIRST is what prevents that.
    //
    // `ref.invalidate` RETAINS the previous `.value`, so a reload keeps a good
    // list on screen and only a genuine FIRST load shows the skeleton. Nothing
    // here gates on `value == null` as a "was reloaded" signal — it would never
    // fire.
    final Widget body;
    if (async.isLoading) {
      final List<WishlistService>? retained = async.value;
      body = retained == null
          ? const WishlistLoadingState()
          : _buildList(l10n, retained);
    } else if (async.hasError) {
      // The retry listener is on-screen and visible here, so the offstage-pause
      // caveat (an invalidate whose only listeners are paused defers its
      // refetch to resume) cannot bite.
      body = WishlistErrorState(
        onRetry: () => ref.invalidate(wishlistProvider),
      );
    } else {
      final List<WishlistService>? items = async.value;
      body = items == null
          ? const WishlistLoadingState()
          : _buildList(l10n, items);
    }

    // The counter is suppressed whenever the section has no list to count —
    // a failure, or a first load that has not landed yet. Both would otherwise
    // render «0» beside a card that is explicitly NOT claiming the wish list is
    // empty, which is the same "failure looks like emptiness" collapse the
    // branch order above exists to prevent, just in the header.
    //
    // A RELOAD (loading WITH a retained value) does keep its counter: the
    // number on screen is still true, and blanking it would make a background
    // refresh look like data loss.
    final List<WishlistService>? counted = async.value;
    final int? count = counted == null ? null : visibleCount(counted.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        HubSectionTitle(
          title: kBeautyWishListTitle,
          literal: true,
          trailing: count == null ? null : WishlistCountPill(count: count),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(l10n.wishlistSectionLede, style: VelvetText.body()),
        const SizedBox(height: VelvetSpacing.md),
        body,
      ],
    );
  }

  Widget _buildList(AppLocalizations l10n, List<WishlistService> items) {
    final int visible = visibleCount(items.length);
    // Gated on the PROVIDER's list, NOT on `visible`. Keying the empty state on
    // the visible count made the LAST removal skip its exit animation: the
    // count hit zero the instant the final card entered `removingIds`, so the
    // card was unmounted in the same frame as the heart pop instead of fading
    // over `WishlistRemovable.duration` — and the empty card appeared before
    // the wire call had even been made, so a failure flipped it back.
    //
    // The COUNT PILL and «Показати всі (N)» still read `visible`: the number
    // should tick down with the animation, which is a different question from
    // whether the section has anything left to show.
    if (items.isEmpty) {
      return WishlistEmptyState(onFindMaster: widget.onFindMaster);
    }
    final List<WishlistService> shown = items
        .take(WishlistSection.previewCount)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // IntrinsicHeight so both cards match the taller one and their buttons
        // share a baseline however many lines the names took.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < shown.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  // A FADE, not the full-width rows' height-collapse: these
                  // cards get a TIGHT height from the IntrinsicHeight row, so
                  // there is no height for an AnimatedSize to animate. The card
                  // fades, then the line re-flows and the next favourite
                  // promotes into the freed slot.
                  child: AnimatedOpacity(
                    // `favoriteTargetId`, not `masterServiceId` — the latter
                    // is null on a SALON row, which would collide every
                    // salon entry onto the same `ValueKey<String>('null')`.
                    key: ValueKey<String>(shown[i].favoriteTargetId),
                    opacity: removingIds.contains(shown[i].favoriteTargetId)
                        ? 0
                        : 1,
                    duration: WishlistRemovable.duration,
                    curve: Curves.easeOut,
                    child: WishlistCompactCard(
                      item: shown[i],
                      onBook: () => widget.onBook(shown[i]),
                      onUnfavourite: () =>
                          requestRemoval(shown[i].favoriteTargetId),
                    ),
                  ),
                ),
              ],
              // Keeps a lone card at HALF width rather than letting it stretch
              // across the row when only one favourite is left. A card that
              // doubled in width on the removal of its neighbour would read as
              // a layout bug, not as a list shrinking.
              if (shown.length == 1) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                const Expanded(child: SizedBox.shrink()),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        HubOutlineButton(
          key: const Key('wishlist_show_all_button'),
          label: l10n.wishlistShowAll(visible),
          onTap: widget.onShowAll,
        ),
      ],
    );
  }
}
