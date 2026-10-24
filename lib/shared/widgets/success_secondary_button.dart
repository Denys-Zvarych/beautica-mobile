// SuccessSecondaryButton — the raised base-tone sibling of NeumorphicButton.
//
// PROMOTED (phase 414, REUSE-FIRST) from
// `lib/features/booking/presentation/widgets/booking_success_scaffold.dart`,
// where it was the onward action of both booking-success screens and the
// salon walk-in «done» state. The booking-links card («Копіювати») is its
// second feature consumer, so it moved here instead of being copied.
//
// Same 49 dp height and button radius as NeumorphicButton, `extrudedButton`
// shadow dropped on press, mocha glyph + Comfortaa CTA label, no gradient.
// The only change from the original is ADDITIVE and render-identical whenever
// the label fits (it always does on the booking-success screens — pinned by
// `test/golden/booking_slot_flow_golden_test.dart`): the label sits in a
// `Flexible` with ellipsis inside a symmetric `VelvetSpacing.sm` inset, the
// same overflow guard NeumorphicButton already carries, so a half-width
// button never overflows at a large text scale.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// One secondary action — a raised base-tone neumorphic pill with a mocha
/// glyph and label. [buttonKey] lands on the tappable [GestureDetector].
class SuccessSecondaryButton extends StatefulWidget {
  const SuccessSecondaryButton({
    super.key,
    required this.buttonKey,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<SuccessSecondaryButton> createState() => _SuccessSecondaryButtonState();
}

class _SuccessSecondaryButtonState extends State<SuccessSecondaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        key: widget.buttonKey,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: VelvetSizes.cta,
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.button),
            boxShadow: _pressed ? null : VelvetShadows.extrudedButton,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(widget.icon, size: 20, color: BrandColors.accentDeep),
              const SizedBox(width: VelvetSpacing.sm),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VelvetText.cta().copyWith(
                    color: BrandColors.accentDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
