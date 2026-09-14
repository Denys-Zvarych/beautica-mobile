// The press / inert / loading machinery shared by every tappable neumorphic
// surface that is NOT a `NeumorphicButton` — currently `SettingsRow` (the
// horizontal settings row) and `ManagementActionCard` (the vertical action
// card pair on the salon-staff profile).
//
// WHY THIS FILE EXISTS
// --------------------
// 2026-09-14 audit (defect 6, REUSE-FIRST): `ManagementActionCard` had
// re-implemented `SettingsRow`'s ENTIRE interaction shell — the `_pressed`
// flag, `AnimatedScale` on press, `AnimatedOpacity` while inert,
// `boxShadow: _pressed ? null : ...` (the neumorphic "press flattens the
// extrusion" idiom), `AbsorbPointer` gating and the 16x16 trailing spinner —
// differing only in the numeric constants (scale, duration, opacity) and the
// box's own colour / radius / shadow / padding. Two copies of a press
// animation drift; this is the ONE copy.
//
// PROMOTION CONTRACT (additive only)
// ----------------------------------
// The parameter defaults below are `SettingsRow`'s pre-existing constants
// VERBATIM (scale 0.985 / 110 ms / opacity 0.6), so composing `SettingsRow`
// onto this widget is a pure refactor: same widget order, same durations,
// same curves, same decoration — pixel-identical, proven by
// `test/golden/settings_row_states_golden_test.dart` (four PNGs, NOT
// regenerated). `ManagementActionCard` passes its own three constants
// explicitly.
//
// The widget ORDER is load-bearing and mirrors both originals exactly:
//   Semantics > AbsorbPointer > GestureDetector > AnimatedScale >
//   AnimatedOpacity > AnimatedContainer(decoration + padding) > child
// Do not reorder — `AnimatedScale` above `AnimatedOpacity` keeps the press
// scale from compounding with the dim's own implicit animation, and
// `AbsorbPointer` above `GestureDetector` is what makes an inert surface
// swallow the tap before it can reach `onTap` (mutation-pinned in
// `test/features/master/presentation/widgets/management_action_card_test.dart`).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// A tappable raised neumorphic box that scales on press, flattens its
/// extrusion while held, dims while [inert], and absorbs taps while [inert].
///
/// Owns NO layout of its own beyond [padding] — callers supply whatever child
/// (a [Row], a [Column]) the surface carries.
class PressableSurface extends StatefulWidget {
  const PressableSurface({
    super.key,
    required this.onTap,
    required this.color,
    required this.borderRadius,
    required this.shadow,
    required this.padding,
    required this.child,
    this.semanticsLabel,
    this.inert = false,
    this.pressedScale = 0.985,
    this.pressDuration = const Duration(milliseconds: 110),
    this.inertOpacity = 0.6,
  });

  final VoidCallback onTap;

  /// The box fill at rest and while pressed (the press is expressed by the
  /// shadow dropping, never by a colour change).
  final Color color;
  final BorderRadius borderRadius;

  /// The extruded shadow pair at rest. Dropped to `null` while pressed —
  /// the surface reads as pushed INTO the ground.
  final List<BoxShadow> shadow;
  final EdgeInsets padding;

  /// Announced by a screen reader in place of the child's own text. `null`
  /// leaves the child's semantics untouched.
  final String? semanticsLabel;

  /// `true` while an action is in flight OR while the action this surface
  /// names does not exist yet. Dims the surface, absorbs taps, and reports
  /// `Semantics(enabled: false)`. Callers decide which of those two meanings
  /// applies and whether to swap their trailing affordance for an
  /// [ActionSpinner].
  final bool inert;

  final double pressedScale;
  final Duration pressDuration;
  final double inertOpacity;

  final Widget child;

  @override
  State<PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<PressableSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !widget.inert,
      label: widget.semanticsLabel,
      child: AbsorbPointer(
        // While inert, absorb taps so a second tap on a slow network is
        // VISIBLY ignored (the spinner keeps spinning) rather than silently
        // swallowed by a caller-side guard with zero on-screen feedback —
        // and so an action that does not exist yet is visibly unavailable,
        // never a tap that quietly does nothing.
        absorbing: widget.inert,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed ? widget.pressedScale : 1,
            duration: widget.pressDuration,
            child: AnimatedOpacity(
              opacity: widget.inert ? widget.inertOpacity : 1,
              duration: const Duration(milliseconds: 150),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: widget.borderRadius,
                  boxShadow: _pressed ? null : widget.shadow,
                ),
                padding: widget.padding,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 16x16 camel spinner that replaces a trailing chevron while a
/// [PressableSurface]'s action is in flight. Mirrors
/// `NeumorphicButton(loading: ...)`'s own idiom.
///
/// Callers pass the `key` their tests look the spinner up by — e.g.
/// `ValueKey<String>('settings_row_loading')`.
class ActionSpinner extends StatelessWidget {
  const ActionSpinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 16,
    width: 16,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: BrandColors.accentDeep,
    ),
  );
}

/// The square inset glyph well that opens every tappable neumorphic surface —
/// a [NeumorphicInset] at `VelvetRadii.field - 4` holding a centred 19 px
/// glyph. [size] is the only thing that varies between call sites
/// (`SettingsRow` 42, `ManagementActionCard` 40).
class NeumorphicGlyphWell extends StatelessWidget {
  const NeumorphicGlyphWell({
    super.key,
    required this.size,
    required this.child,
  });

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: size,
    width: size,
    child: NeumorphicInset(
      radius: VelvetRadii.field - 4,
      child: Center(child: child),
    ),
  );
}
