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
const double kSalonMasterCardHeight = 190;

/// One master in the salon's "Майстри салону" horizontal rail. A raised
/// neumorphic card: circular gradient avatar → master name → role sub-line →
/// camel ★ rating. Depresses on press for tactile feedback.
class SalonMasterCard extends StatefulWidget {
  const SalonMasterCard({
    super.key,
    required this.name,
    required this.role,
    required this.ratingLabel,
    required this.avatarIndex,
    required this.onTap,
  });

  final String name;
  final String role;

  /// Pre-formatted rating string, e.g. "4.9", or "—" when no reviews yet.
  final String ratingLabel;

  /// Position in the rail — selects the avatar gradient deterministically.
  final int avatarIndex;
  final VoidCallback onTap;

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
      child: GestureDetector(
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
            width: 132,
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
                Container(
                  height: 56,
                  width: 56,
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
                      size: 26,
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
    );
  }
}
