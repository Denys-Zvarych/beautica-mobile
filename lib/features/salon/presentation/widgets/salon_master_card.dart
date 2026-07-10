// Phase 13.6 — Salon master-rail card.
//
// Ported from the approved preview app at
// `docs/signup-designs/PublicSalonProfile/lib/widgets/salon_widgets.dart`
// (`SalonMasterCard`), wired to real [SalonMasterSummary] data instead of the
// preview's static mock rows.
//
// This card is the ONLY path from a salon into one of its masters (phase
// decision 7): tapping it pushes `/masters/:masterId` (the Public Master
// Profile, Phase 13.5).
//
// No master photo pipeline is wired yet anywhere in the app (the master's own
// public profile also renders gradient placeholders for its portfolio), so the
// avatar renders a deterministic camel/mocha gradient keyed on the rail
// position — never a fabricated photo.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Gradient fills cycled by rail position — the same family used by the
/// master profile's portfolio placeholder tiles.
const List<List<Color>> _kAvatarGradients = <List<Color>>[
  <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
  <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
  <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
  <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
  <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
  <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
];

/// Fixed card height (mobile-perf HIGH fix, Phase 13.6 audit): the rail used
/// to sit inside an `IntrinsicHeight`, which forced a second full layout pass
/// over every card just to stretch them all to the tallest sibling's natural
/// height. A single fixed height — generous enough for the worst case (a
/// 1-line name + a wrapped 2-line role + the rating row) — removes the need
/// for that second pass entirely while keeping the rail visually uniform.
///
/// Trimmed 214 -> 190 (~11%) alongside the card width/avatar shrink below —
/// re-verified against the same worst case (see the long-name/wrapped-role
/// stress case in `public_salon_profile_screen_test.dart`) so the smaller
/// card still doesn't reintroduce the overflow this constant exists to avoid.
///
/// The outer card box (this constant, plus the grid's `mainAxisExtent`) is
/// intentionally NOT reopened for the avatar-enlargement passes below — only
/// the avatar grows, spending headroom from the same worst-case content
/// budget this constant was tuned against (measured empirically, re-verified
/// on the second enlargement pass: the worst-case stress case still
/// overflows once the avatar grows past diameter 76 — 77 is the first
/// overflowing diameter, at 1.00px, scaling ~1:1 with diameter above that —
/// i.e. ~28px of slack above the original 56px avatar, of which 73px spends
/// 17px and leaves a 3px safety margin below the 76px max-safe diameter).
const double kSalonMasterCardHeight = 190;

/// One master in the salon's "Майстри салону" 2-column grid. A raised
/// neumorphic card: circular gradient avatar → master name → role sub-line →
/// camel ★ rating. Depresses on press for tactile feedback.
///
/// Width is intentionally NOT fixed here — the enclosing `GridView`'s tile
/// gives this card a tight width constraint per column (see
/// `_MastersTab` in `public_salon_profile_screen.dart`), so the card just
/// fills whatever column width the grid computes. Only [kSalonMasterCardHeight]
/// stays fixed (via the grid's `mainAxisExtent`), which is what the
/// long-name/wrapped-role overflow budget below is tuned against.
class SalonMasterCard extends StatefulWidget {
  const SalonMasterCard({
    super.key,
    required this.name,
    required this.role,
    required this.ratingLabel,
    required this.avatarIndex,
    required this.onTap,
    required this.onBook,
    required this.bookActionKey,
  });

  final String name;
  final String role;

  /// Pre-formatted rating string, e.g. "4.9", or "—" when no reviews yet.
  final String ratingLabel;

  /// Position in the rail — selects the avatar gradient deterministically.
  final int avatarIndex;

  /// Tapping the card body opens the master's public profile.
  final VoidCallback onTap;

  /// The corner book affordance — routes into the master-SCOPED booking flow
  /// (`RouteNames.bookingNew` with this master's id), so the client sees ONLY
  /// this master's services, not the whole salon catalogue. Distinct from the
  /// salon-wide "Записатись на послугу" CTA on the profile footer.
  final VoidCallback onBook;

  /// Unique key for the corner book button (keyed on the master id upstream)
  /// so widget tests can target one specific card's book action.
  final Key bookActionKey;

  @override
  State<SalonMasterCard> createState() => _SalonMasterCardState();
}

class _SalonMasterCardState extends State<SalonMasterCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<Color> gradient =
        _kAvatarGradients[widget.avatarIndex % _kAvatarGradients.length];
    return Semantics(
      button: true,
      label: l10n.salonMasterCardSemanticLabel(
        widget.name,
        widget.role,
        widget.ratingLabel,
      ),
      // The book affordance is a Stack sibling of the card body (not a child
      // of its content Column), so it does NOT consume the fixed
      // [kSalonMasterCardHeight] overflow budget the card is tuned against.
      // Placing it above the body in paint order also means its taps never
      // reach the body's gesture detector — tapping the corner books; tapping
      // anywhere else still opens the master profile.
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // Opaque + full-tile so a tap anywhere on the card body (incl. its
          // center and padding) always resolves onto THIS detector and fires
          // `onTap`. Without `opaque` + `width: double.infinity` below, the
          // Stack loosens this non-positioned child's constraints, the body
          // shrinks to its content width and pins top-left, and the tile's
          // center falls through to the enclosing scroll viewport (the
          // whole-card-tap regression this class doc contract guards against).
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) {
              setState(() => _pressed = false);
              widget.onTap();
            },
            child: AnimatedScale(
              scale: _pressed ? 0.97 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                // Fill the full tile in BOTH axes. The grid tile constrains
                // this tightly per column, but the enclosing Stack loosens that
                // constraint for its non-positioned body child, so `width:
                // double.infinity` (clamped to the tile's maxWidth) is required
                // to keep the card spanning the whole column — without it the
                // body shrinks to content width and the tile's center tap
                // misses the card body (whole-card-tap regression). Height is
                // exactly the tile's `mainAxisExtent`, so this adds no overflow.
                width: double.infinity,
                height: kSalonMasterCardHeight,
                decoration: BoxDecoration(
                  color: BrandColors.base,
                  borderRadius: BorderRadius.circular(VelvetRadii.card),
                  boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: VelvetSpacing.md - 2,
                  vertical: VelvetSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // Enlarged 56 -> 68 -> 73 (second pass, +5) so the avatar
                    // reads more prominently in the grid card. Re-verified
                    // empirically against the long-name/wrapped-role stress case
                    // (see `public_salon_profile_screen_test.dart`) starting from
                    // the 68px baseline: diameter 76 still passes (0px
                    // overflow), 77 is the first diameter that overflows (1.00px,
                    // then scaling ~1:1 with diameter — 78 -> 2px, 80 -> 4px, 84
                    // -> 8px), so max-safe is 76 and 73 leaves a 3px safety
                    // margin below that breakeven for font-rendering variance
                    // across platforms. The card's OUTER box
                    // ([kSalonMasterCardHeight], the grid's `mainAxisExtent`)
                    // stays untouched — only this circle grows.
                    Container(
                      height: 73,
                      width: 73,
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
                          size: 34,
                        ),
                      ),
                    ),
                    const SizedBox(height: VelvetSpacing.sm),
                    Text(
                      widget.name,
                      style: VelvetText.subheading().copyWith(fontSize: 14),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.role,
                      style: VelvetText.feedback(
                        BrandColors.muted,
                      ).copyWith(fontSize: 11),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: VelvetSpacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.star_rounded,
                          size: 13,
                          color: BrandColors.accentDeep,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          widget.ratingLabel,
                          style: VelvetText.bodyStrong().copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: VelvetSpacing.sm,
            right: VelvetSpacing.sm,
            child: _SalonMasterBookButton(
              key: widget.bookActionKey,
              semanticLabel: l10n.salonMasterCardBookSemanticLabel(widget.name),
              onPressed: widget.onBook,
            ),
          ),
        ],
      ),
    );
  }
}

/// The camel-accent corner "book" affordance overlaid on a [SalonMasterCard].
///
/// Icon-only by design — the card is a compact 2-column grid tile with no room
/// for a labelled button — so its meaning is carried entirely by the
/// [semanticLabel] ("Записатись до майстра …"). Reuses the card's neumorphic
/// language: a raised camel circle ([VelvetShadows.extrudedSmall]) matching the
/// avatar's gradient family, so it reads as native to the card rather than a
/// new visual element. It owns its own tap so pressing it books the master
/// (master-scoped flow) without also opening the profile behind it.
class _SalonMasterBookButton extends StatelessWidget {
  const _SalonMasterBookButton({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
  });

  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 34,
          width: 34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFFC8A878), Color(0xFF8A6840)],
            ),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: const Center(
            child: Icon(
              Icons.event_available_rounded,
              size: 18,
              color: BrandColors.white,
            ),
          ),
        ),
      ),
    );
  }
}
