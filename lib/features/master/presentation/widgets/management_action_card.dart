// Phase 325 — the management-action card pair (schedule + services) on the
// salon-staff profile screen.
//
// Design source: `docs/signup-designs/SalonServicesEntryPath/lib/widgets/
// entry_widgets.dart:12-130` (`ManagementActionCard`, variant **B · пара
// дій** — the ONLY approved variant of that preview). Transcribed literally,
// swapping the preview's own `VelvetColors`/`VelvetText` tokens for this
// app's [BrandColors]/[VelvetText] — see that file's own header for why
// `Theme.of(context).colorScheme` is never used here (`ColorScheme.fromSeed`
// derives a MOCHA-tonal `primary`, not the camel accent this card needs).
//
// A vertical raised card — distinct from the horizontal [SettingsRow] it
// replaces on this screen: a 40x40 inset glyph well + chevron on the top
// row, then the label, then the (promoted-to-readable) value. Exactly one
// card in a pair may carry [emphasis] — the camel wash — per the design's
// own "spend the boldness in one place" rule.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// A tappable raised card: inset glyph well + chevron on top, label + value
/// below. The vertical sibling of `SettingsRow` used where a pair of
/// management actions sits side by side (e.g. «Графік роботи» / «Послуги» on
/// `SalonStaffProfileScreen`).
class ManagementActionCard extends StatefulWidget {
  const ManagementActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.enabled = true,
    this.emphasis = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// Present-but-not-yet-available, same contract as `SettingsRow.enabled` —
  /// dims the card and absorbs taps rather than omitting it.
  final bool enabled;

  /// The camel-washed treatment. Exactly one card in a pair may carry it —
  /// spend the boldness in one place (design source's own rule).
  final bool emphasis;

  /// Additive, defaults `false` — NOT part of the approved static preview
  /// (a demo app has no live async fetch to be "loading"). Mirrors
  /// `SettingsRow.loading`'s exact idiom (swap the trailing chevron for a
  /// small spinner, absorb taps) so the schedule card can keep the
  /// pre-existing mutation-critical AsyncLoading contract
  /// (`salon_staff_profile_screen_test.dart`'s `'AsyncLoading (unresolved,
  /// no value yet) → loading spinner...'` case) without a new visual
  /// treatment — every caller that omits it renders exactly per the
  /// approved design.
  final bool loading;

  // Camel wash — the same `#EDE4D5` "hero" surface tint inlined as a private
  // per-file constant across the app (`my_salons_screen.dart`,
  // `master_strip_shell.dart`, this screen's own loading skeleton, etc.) —
  // never centralised in [BrandColors], by established convention.
  static const Color _emphasisWash = Color(0xFFEDE4D5);

  @override
  State<ManagementActionCard> createState() => _ManagementActionCardState();
}

class _ManagementActionCardState extends State<ManagementActionCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool inert = widget.loading || !widget.enabled;
    return Semantics(
      button: true,
      enabled: !inert,
      label: '${widget.label}: ${widget.value}',
      child: AbsorbPointer(
        absorbing: inert,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed ? 0.975 : 1,
            duration: const Duration(milliseconds: 120),
            child: AnimatedOpacity(
              opacity: inert ? 0.55 : 1,
              duration: const Duration(milliseconds: 150),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: widget.emphasis
                      ? ManagementActionCard._emphasisWash
                      : BrandColors.base,
                  borderRadius: BorderRadius.circular(VelvetRadii.card),
                  boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
                ),
                padding: const EdgeInsets.all(VelvetSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        SizedBox(
                          height: 40,
                          width: 40,
                          child: NeumorphicInset(
                            radius: VelvetRadii.field - 4,
                            child: Center(
                              child: Icon(
                                widget.icon,
                                size: 19,
                                color: BrandColors.accentDeep,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (widget.loading)
                          const SizedBox(
                            key: ValueKey<String>(
                              'management_action_card_loading',
                            ),
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BrandColors.accentDeep,
                            ),
                          )
                        else
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: BrandColors.faint,
                          ),
                      ],
                    ),
                    const SizedBox(height: VelvetSpacing.sm + 2),
                    Text(
                      widget.label,
                      style: VelvetText.managementCardLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.value,
                      style: VelvetText.managementCardValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
