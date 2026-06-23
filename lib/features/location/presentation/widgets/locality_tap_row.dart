// Phase 2.18 — LocalityTapRow (VelvetTouch redesign).
//
// The tap-row that replaces a native <select> in the locality cascade.
// Transcribed from the `_PickerRow` class in:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/address_screen.dart
//
// Visual states:
//   - empty    : placeholder text (BrandColors.placeholder), muted pin.
//   - filled   : value text (VelvetText.input()), accent pin.
//   - disabled : 45% opacity via Opacity; IgnorePointer blocks touches; no chevron.
//
// Layout: a label (with optional right-aligned suffix) sits ABOVE the row,
// the row itself is a NeumorphicInset containing a leading icon, the stacked
// value/placeholder, and a trailing chevron (when enabled). All repeated paint
// objects are hoisted to module-level `final` so `build()` allocates nothing.

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:flutter/material.dart';

// --- Module-level hoisted text styles (zero per-build allocation) -----------

final _hintStyle = VelvetText.input().copyWith(color: BrandColors.placeholder);
final TextStyle _tapRowErrorStyle = VelvetText.feedback(BrandColors.error);
final TextStyle _tapRowMutedStyle = VelvetText.feedback(BrandColors.muted);

/// A single tap-to-open row in the locality cascade.
///
/// Renders a [label] above an interactive [NeumorphicInset] well that shows
/// either [value] (filled) or [placeholder] (empty). Tapping fires [onTap]
/// unless [enabled] is false. When [helper] is non-null it is rendered below
/// the row (used for the "city has no districts" disabled state).
class LocalityTapRow extends StatelessWidget {
  const LocalityTapRow({
    required this.label,
    required this.placeholder,
    required this.onTap,
    this.value,
    this.enabled = true,
    this.helper,
    this.errorText,
    this.labelSuffix,
    super.key,
  });

  /// Label rendered above the row (e.g. "Область").
  final String label;

  /// Placeholder shown inside the row when [value] is null (e.g. "Оберіть місто").
  final String placeholder;

  /// The selected display value, or null when nothing is chosen yet.
  final String? value;

  /// Invoked when the row is tapped. Ignored entirely when [enabled] is false.
  final VoidCallback onTap;

  /// Whether the row is interactive. When false the row is dimmed (45% opacity),
  /// wrapped in an [IgnorePointer], and the chevron is hidden.
  final bool enabled;

  /// Optional helper line rendered below the row (disabled-with-helper state).
  final String? helper;

  /// Optional inline error rendered below the row in the error colour.
  /// Takes precedence over [helper].
  final String? errorText;

  /// Optional inline widget rendered to the RIGHT of the [label] (same row as
  /// the label text). Used by Phase 2.19 to append the CLIENT "— необов'язково"
  /// tag and the "?" tip-icon to the Область label. Null on every other row.
  final Widget? labelSuffix;

  bool get _isFilled => value != null && value!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final bool isEmpty = !_isFilled;
    final String display = isEmpty ? placeholder : value!;

    final row = IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Semantics(
          button: enabled,
          enabled: enabled,
          label: label,
          value: display,
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: NeumorphicInset(
              child: SizedBox(
                height: VelvetSizes.field,
                child: Row(
                  children: [
                    const SizedBox(width: VelvetSpacing.md),
                    AppIcon(
                      BeauticaAssetIcons.locationMarker,
                      size: 20,
                      color: isEmpty ? BrandColors.muted : BrandColors.accent,
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    Expanded(
                      child: Text(
                        display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isEmpty ? _hintStyle : VelvetText.input(),
                      ),
                    ),
                    if (enabled)
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: BrandColors.muted,
                        size: 20,
                      ),
                    const SizedBox(width: VelvetSpacing.sm),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: VelvetSpacing.xs),
          child: labelSuffix == null
              ? Text(label, style: VelvetText.label())
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: VelvetText.label(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    labelSuffix!,
                  ],
                ),
        ),
        row,
        // Error takes precedence over the helper line.
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs, left: 6),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorText!,
                key: const ValueKey<String>('locality_tap_row_error'),
                style: _tapRowErrorStyle,
              ),
            ),
          )
        else if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs, left: 6),
            child: Text(helper!, style: _tapRowMutedStyle),
          ),
      ],
    );
  }
}
