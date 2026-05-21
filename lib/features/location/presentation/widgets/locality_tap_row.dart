// Phase 2.18 — LocalityTapRow.
//
// The tap-row that replaces a native <select> in the locality cascade. Mirrors
// `.picker-row` from docs/signup-designs/sign-up-step-3-address.html across its
// three visual states:
//   - empty    : placeholder text (white 18%), camel chevron, grey pin.
//   - filled   : value text (cream 92%), camel border tint, camel pin.
//   - disabled : 45% opacity, no chevron, IgnorePointer + helper line below.
//
// Layout: a label sits ABOVE the row (matching the HTML `.picker-group label`),
// the row itself carries the leading pin, the stacked value, and the trailing
// chevron. All paddings come from [AppSpacing]; all repeated paint objects are
// hoisted to `static const` so `build()` allocates nothing.

import 'package:beautica_mobile/core/theme/app_spacing.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';

/// A single tap-to-open row in the locality cascade.
///
/// Renders a [label] above an interactive row that shows either [value]
/// (filled) or [placeholder] (empty). Tapping fires [onTap] unless [enabled]
/// is false. When [helper] is non-null it is rendered below the row (used for
/// the "city has no districts" disabled state).
class LocalityTapRow extends StatelessWidget {
  const LocalityTapRow({
    required this.label,
    required this.placeholder,
    required this.onTap,
    this.value,
    this.enabled = true,
    this.helper,
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

  /// Whether the row is interactive. When false the row is dimmed, wrapped in
  /// an [IgnorePointer], and the chevron is hidden.
  final bool enabled;

  /// Optional helper line rendered below the row (disabled-with-helper state).
  final String? helper;

  /// Optional inline widget rendered to the RIGHT of the [label] (same row as
  /// the label text). Used by Phase 2.19 to append the CLIENT "— необов'язково"
  /// optional tag and the "?" tip-icon to the Область label. Null on every
  /// other row / screen.
  final Widget? labelSuffix;

  // --- Hoisted paint objects (no per-build allocation) ----------------------

  static const _kRowHeight = 52.0;
  static const _kIconBoxWidth = 40.0;
  static const _kRowRadius = BorderRadius.all(Radius.circular(12));
  static const _kRowFill = Color(0x12FFFFFF); // white ~7%
  static const _kRowBorder = Color(0x1AFFFFFF); // white ~10%
  static const _kFilledFill = Color(0x0AB89A7A); // camel ~4%
  static const _kFilledBorder = Color(0x52B89A7A); // camel ~32%
  static const _kPlaceholderColor = Color(0x2EFFFFFF); // white ~18%
  static const _kValueColor = Color(0xEBF5EDE0); // cream ~92%
  static const _kIconEmptyColor = Color(0x40FFFFFF); // white ~25%
  static const _kChevronColor = Color(0x52B89A7A); // camel ~32%
  static const _kHelperColor = Color(0x52FFFFFF); // white ~32%

  static const _kLabelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: BrandColors.ash,
    letterSpacing: 0.2,
  );
  static const _kPlaceholderStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: _kPlaceholderColor,
  );
  static const _kValueStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: _kValueColor,
  );
  static const _kHelperStyle = TextStyle(
    fontSize: 11,
    height: 1.45,
    color: _kHelperColor,
  );

  // Hoisted row decorations — selected by [_isFilled] so `build()` allocates
  // neither the BoxDecoration nor the Border.all on every rebuild.
  static const _kFilledDecoration = BoxDecoration(
    color: _kFilledFill,
    borderRadius: _kRowRadius,
    border: Border.fromBorderSide(BorderSide(color: _kFilledBorder)),
  );
  static const _kEmptyDecoration = BoxDecoration(
    color: _kRowFill,
    borderRadius: _kRowRadius,
    border: Border.fromBorderSide(BorderSide(color: _kRowBorder)),
  );

  bool get _isFilled => value != null && value!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final row = Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Material(
          color: Colors.transparent,
          borderRadius: _kRowRadius,
          child: InkWell(
            key: const Key('locality_tap_row_ink'),
            onTap: enabled ? onTap : null,
            borderRadius: _kRowRadius,
            child: DecoratedBox(
              decoration: _isFilled ? _kFilledDecoration : _kEmptyDecoration,
              child: SizedBox(
                height: _kRowHeight,
                child: Row(
                  children: [
                    SizedBox(
                      width: _kIconBoxWidth,
                      child: Icon(
                        Icons.place_outlined,
                        size: 18,
                        color: _isFilled ? BrandColors.camel : _kIconEmptyColor,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _isFilled ? value! : placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _isFilled ? _kValueStyle : _kPlaceholderStyle,
                      ),
                    ),
                    if (enabled)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: _kChevronColor,
                        ),
                      )
                    else
                      const SizedBox(width: AppSpacing.sm),
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
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: labelSuffix == null
              ? Text(label, style: _kLabelStyle)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: _kLabelStyle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    labelSuffix!,
                  ],
                ),
        ),
        Semantics(
          button: enabled,
          enabled: enabled,
          label: label,
          value: _isFilled ? value : placeholder,
          child: row,
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xxs,
              left: AppSpacing.xxs,
            ),
            child: Text(helper!, style: _kHelperStyle),
          ),
      ],
    );
  }
}
