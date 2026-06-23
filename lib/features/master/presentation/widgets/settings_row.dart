// Building blocks for the settings hub menu and the account page.
//
// [SettingsRow]      — a tappable raised row: inset glyph well + label
//                      (+ optional trailing value) + chevron. The [destructive]
//                      variant (logout) drops the camel accent for the semantic
//                      error tone so it reads as a terminal action, set apart
//                      from the navigational rows — meaning carried by colour AND
//                      the distinct logout glyph, never hue alone.
// [SettingsToggleRow] — a row carrying an inline neumorphic switch instead of a
//                      chevron (e.g. notifications). Placeholder local state.
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/widgets/
// settings_widgets.dart` — ported 1:1, swapping VelvetColors → BrandColors and
// reusing the production [NeumorphicInset].

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';

/// A tappable raised settings row — the building block of the hub menu and the
/// account page.
class SettingsRow extends StatefulWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconWidget,
    this.value,
    this.showChevron = true,
    this.destructive = false,
  });

  final IconData icon;

  /// Optional pre-built glyph widget (e.g. an [AppIcon] SVG) rendered inside the
  /// inset well in place of the Material [Icon] built from [icon]. Callers must
  /// size it to 19 px and tint it to match the row state (non-destructive:
  /// [BrandColors.accentDeep]). The [destructive] recolour only applies to the
  /// Material fallback, so SVG glyphs should not be used on destructive rows.
  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;

  /// Optional right-aligned value (e.g. "Українська" on the language row).
  final String? value;

  /// Whether a navigational chevron sits at the far right.
  final bool showChevron;

  /// Renders the terminal/destructive treatment (logout).
  final bool destructive;

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _pressed = false;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );
  static const EdgeInsets _padding = EdgeInsets.all(VelvetSpacing.sm + 4);

  static final TextStyle _valueStyle = VelvetText.body().copyWith(fontSize: 14);

  @override
  Widget build(BuildContext context) {
    final Color glyph = widget.destructive
        ? BrandColors.error
        : BrandColors.accentDeep;
    final Color labelColor = widget.destructive
        ? BrandColors.error
        : BrandColors.text;
    final String? value = widget.value;

    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: _radius,
              boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
            ),
            padding: _padding,
            child: Row(
              children: <Widget>[
                SizedBox(
                  height: 42,
                  width: 42,
                  child: NeumorphicInset(
                    radius: VelvetRadii.field - 4,
                    child: Center(
                      child:
                          widget.iconWidget ??
                          Icon(widget.icon, size: 19, color: glyph),
                    ),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Text(
                    widget.label,
                    style: VelvetText.bodyStrong().copyWith(color: labelColor),
                  ),
                ),
                if (value != null) ...<Widget>[
                  Text(value, style: _valueStyle),
                  const SizedBox(width: VelvetSpacing.sm),
                ],
                if (widget.showChevron)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: BrandColors.faint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A settings row carrying an inline toggle on the right instead of a chevron —
/// e.g. push notifications. The toggle is a self-contained neumorphic pill: an
/// inset track with a raised camel/grey thumb that slides + recolours on tap.
/// Local state only (placeholder until notification preferences ship).
class SettingsToggleRow extends StatefulWidget {
  const SettingsToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.initialValue,
    this.subtitle,
    this.switchKey,
  });

  final IconData icon;
  final String label;
  final bool initialValue;
  final String? subtitle;

  /// Optional key for the switch (used by widget tests).
  final Key? switchKey;

  @override
  State<SettingsToggleRow> createState() => _SettingsToggleRowState();
}

class _SettingsToggleRowState extends State<SettingsToggleRow> {
  late bool _on = widget.initialValue;

  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );
  static const EdgeInsets _padding = EdgeInsets.all(VelvetSpacing.sm + 4);

  static final TextStyle _subtitleStyle = VelvetText.body().copyWith(
    fontSize: 12,
  );

  @override
  Widget build(BuildContext context) {
    final String? subtitle = widget.subtitle;
    return Semantics(
      toggled: _on,
      label: widget.label,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: BrandColors.base,
          borderRadius: _radius,
          boxShadow: VelvetShadows.extrudedSmall,
        ),
        child: Padding(
          padding: _padding,
          child: Row(
            children: <Widget>[
              SizedBox(
                height: 42,
                width: 42,
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
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(widget.label, style: VelvetText.bodyStrong()),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(subtitle, style: _subtitleStyle),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm),
              _NeumorphicSwitch(
                switchKey: widget.switchKey,
                value: _on,
                onChanged: (bool v) => setState(() => _on = v),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A soft-UI switch — an inset track with a raised thumb. On → camel thumb at
/// the right; off → muted thumb at the left. Animated slide + colour fade.
class _NeumorphicSwitch extends StatelessWidget {
  const _NeumorphicSwitch({
    required this.value,
    required this.onChanged,
    this.switchKey,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final Key? switchKey;

  static const double _w = 52;
  static const double _h = 30;
  static const double _thumb = 22;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        key: switchKey,
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: _h,
          width: _w,
          child: NeumorphicInset(
            radius: VelvetRadii.pill,
            child: Stack(
              children: <Widget>[
                AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(VelvetSpacing.xs),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: _thumb,
                      width: _thumb,
                      decoration: BoxDecoration(
                        color: value ? BrandColors.accent : BrandColors.faint,
                        shape: BoxShape.circle,
                        boxShadow: VelvetShadows.extrudedSmall,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
