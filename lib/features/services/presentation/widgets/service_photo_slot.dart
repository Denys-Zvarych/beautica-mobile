// Phase 5.4 — Service cover-photo affordance.
//
// A reusable neumorphic inset 4:3 tile at the top of the service edit form.
// Transcribed 1:1 from the approved preview app at
// `docs/signup-designs/ServiceEditForm/lib/widgets/service_photo_slot.dart`.
//
// Two states:
//   - empty  → camera icon + "Додати фото" label + subtitle
//   - filled → warm camel gradient stand-in + "Змінити фото" overlay chip
//
// Tapping the slot is a placeholder for the real photo picker (Phase 9.x).
// The widget does not trigger any repository call; it simply calls [onTap].
//
// Accessibility: the Semantics wrapper announces the current state and marks
// the widget as a button so screen readers surface the tap affordance.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// The service cover-photo affordance used in [ServiceEditScreen].
///
/// [imageUrl] is reserved for Phase 9.x — when null the empty state is shown.
/// [onTap] is called when the slot is tapped; pass null to disable interaction.
class ServicePhotoSlot extends StatefulWidget {
  const ServicePhotoSlot({super.key, this.imageUrl, this.onTap});

  /// When non-null the filled state is rendered (warm gradient stand-in until
  /// Phase 9.x wires up a real [Image.network]).
  final String? imageUrl;

  /// Called when the user taps the slot. Pass null to disable interaction
  /// (e.g. while the form is submitting).
  final VoidCallback? onTap;

  /// A gentle 4:3 cover ratio reads as a listing thumbnail without dominating
  /// the form above the name field.
  static const double _aspect = 4 / 3;

  @override
  State<ServicePhotoSlot> createState() => _ServicePhotoSlotState();
}

class _ServicePhotoSlotState extends State<ServicePhotoSlot> {
  // Hoisted statics — avoids allocating new objects on every build().
  static final TextStyle _changePhotoLabelStyle = VelvetText.cta().copyWith(
    fontSize: 14,
  );
  static final BoxDecoration _iconPillNormal = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.field),
    boxShadow: VelvetShadows.extrudedSmall,
  );
  static final BoxDecoration _iconPillPressed = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.field),
  );

  bool _pressed = false;

  bool get _interactive => widget.onTap != null;
  bool get _filled => widget.imageUrl != null;

  Widget _buildEmpty(AppLocalizations l10n) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // Small extruded camel pillow cradling the camera glyph.
        Container(
          height: 56,
          width: 56,
          decoration: _pressed ? _iconPillPressed : _iconPillNormal,
          child: const Icon(
            Icons.add_a_photo_rounded,
            color: BrandColors.accent,
            size: 26,
          ),
        ),
        const SizedBox(height: VelvetSpacing.sm + 2),
        Text(l10n.servicePhotoAdd, style: VelvetText.subheading()),
      ],
    );
  }

  Widget _buildFilled(AppLocalizations l10n) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Warm camel gradient stands in for a real network image (Phase 9.x).
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                BrandColors.accentLogo,
                BrandColors.accent,
                BrandColors.accentLatte,
              ],
              stops: <double>[0.0, 0.55, 1.0],
            ),
          ),
        ),
        // Bottom-anchored dark veil so the "Змінити фото" chip stays legible.
        const Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: 0.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0x59000000)],
                ),
              ),
            ),
          ),
        ),
        // "Змінити фото" chip, bottom-left.
        Positioned(
          left: VelvetSpacing.md,
          bottom: VelvetSpacing.md,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.photo_camera_rounded,
                color: BrandColors.white,
                size: 18,
              ),
              const SizedBox(width: VelvetSpacing.sm),
              Text(l10n.servicePhotoChange, style: _changePhotoLabelStyle),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final Widget well = AspectRatio(
      aspectRatio: ServicePhotoSlot._aspect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VelvetRadii.card),
          // Camel ring frames the filled state so the image edge reads.
          border: Border.all(
            color: _filled
                ? BrandColors.accent.withValues(alpha: 0.35)
                : Colors.transparent,
            width: _filled ? 1.4 : 0,
          ),
        ),
        child: NeumorphicInset(
          radius: VelvetRadii.card,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VelvetRadii.card),
            child: Padding(
              padding: EdgeInsets.all(_filled ? 0 : VelvetSpacing.sm),
              child: _filled ? _buildFilled(l10n) : _buildEmpty(l10n),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _interactive,
      label: _filled
          ? l10n.servicePhotoChangeSemantics
          : l10n.servicePhotoAddSemantics,
      child: GestureDetector(
        onTapDown: _interactive ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _interactive
            ? () => setState(() => _pressed = false)
            : null,
        onTapUp: _interactive
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: well,
        ),
      ),
    );
  }
}
