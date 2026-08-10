// Phase 13.4 — Favorite heart toggle (shared by master + salon result cards).
//
// Watches the [favoriteToggleProvider] slice for ONE target and renders
// a filled/outlined heart that scales on toggle (ported from the approved
// preview's `_HeartButton`). Tapping flips the flag optimistically via the
// notifier; on error the notifier reverts the flag and this widget calls
// [onError] so the host screen can show a snackbar.
//
// It primes the notifier with [initialIsFavorite] on first build (the search
// payload carries no favorited flag yet, so cards seed `false`) — a later seed
// never stomps a user toggle (see [FavoriteToggleNotifier.primeIfAbsent]).
//
// ## Known tap-target gap — INTENTIONALLY left unfixed here
//
// This heart's hit area is its painted 24dp icon plus a `VelvetSpacing.xs`
// (4dp) LEFT-only pad — effectively ~28×24dp, below the Android 48dp / iOS
// 44pt floor (WCAG 2.5.5 / Material / HIG), the same defect
// `wishlist_heart_button.dart`'s `WishlistHeartButton` had until it was
// fixed by growing its own invisible margin to 48×48 via `Padding`.
//
// That fix is NOT mirrored here. This button's only shipped caller today is
// `service_catalogue_accordion.dart`'s service tile, and that tile's ENTIRE
// row is itself the tap target (`onTapUp` on the outer `GestureDetector`
// toggles selection) — a dense row of checkbox + name + meta line + this
// heart, at booking-flow widths as narrow as 320dp. Both `GestureDetector`s
// share every pixel of the heart's box, so expanding it does not add a new
// tappable region: it enlarges the pixel band that the ROW'S OWN selection
// gesture loses to the heart. Growing a ~28×24dp box to 48×48 would roughly
// triple that stolen band right where a thumb is already most likely to
// land near the trailing edge, trading a real but low-severity a11y gap for
// a real mis-tap risk on a booking-selection control. See
// `service_catalogue_accordion_overflow_test.dart`'s 30-test harness for how
// tight this tile's width budget already is before adding any more pressure
// to it.
//
// Left as a documented, deliberate gap rather than silently accepted —
// revisit if this widget ever gets a caller whose row is NOT itself
// tappable (at which point it should take the identical `Padding` fix
// `WishlistHeartButton` uses, not a new variant).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';

import '../../../favorites/application/favorite_toggle_notifier.dart';
import '../../../favorites/domain/favorite_target.dart';

/// A tappable favourite heart bound to [target] via the toggle notifier.
class FavoriteHeartButton extends ConsumerStatefulWidget {
  const FavoriteHeartButton({
    super.key,
    required this.target,
    required this.semanticAddLabel,
    required this.semanticRemoveLabel,
    this.initialIsFavorite = false,
    this.onError,
  });

  /// The master/salon this heart toggles.
  final FavoriteTarget target;

  /// Accessibility label when the heart is currently NOT favorited (tapping
  /// adds it).
  final String semanticAddLabel;

  /// Accessibility label when the heart IS favorited (tapping removes it).
  final String semanticRemoveLabel;

  /// Seed flag used the first time this target is seen by the notifier.
  final bool initialIsFavorite;

  /// Invoked with the localized error message when a toggle fails (and the
  /// notifier has already reverted the optimistic flag).
  final void Function(Failure failure)? onError;

  @override
  ConsumerState<FavoriteHeartButton> createState() =>
      _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends ConsumerState<FavoriteHeartButton> {
  @override
  void initState() {
    super.initState();
    // Seed the flag after the first frame so we don't mutate a provider during
    // build. primeIfAbsent never overwrites an existing (possibly toggled) flag.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(favoriteToggleProvider.notifier)
          .primeIfAbsent(widget.target, isFavorite: widget.initialIsFavorite);
    });
  }

  Future<void> _onTap() async {
    final Failure? failure = await ref
        .read(favoriteToggleProvider.notifier)
        .toggle(widget.target);
    if (failure != null) widget.onError?.call(failure);
  }

  @override
  Widget build(BuildContext context) {
    // Watch only this target's entry — so an unrelated card's toggle never
    // rebuilds this heart. An absent target reads hard `false`: the notifier
    // prunes settled `false` entries (and skips priming them), so absence
    // unambiguously means "not favorited". The non-false seed is still stored by
    // primeIfAbsent, so a `true` initial flag is honoured until the user toggles.
    final bool isFavorite = ref.watch(
      favoriteToggleProvider.select(
        (Map<FavoriteTarget, FavoriteEntry> m) =>
            m[widget.target]?.isFavorite ?? false,
      ),
    );

    return Semantics(
      button: true,
      label: isFavorite ? widget.semanticRemoveLabel : widget.semanticAddLabel,
      child: GestureDetector(
        onTap: _onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(left: VelvetSpacing.xs),
          child: AnimatedScale(
            scale: isFavorite ? 1.0 : 0.92,
            duration: const Duration(milliseconds: 150),
            child: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: isFavorite ? BrandColors.error : BrandColors.faint,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
