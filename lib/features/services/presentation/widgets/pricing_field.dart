// Phase 5.6 — PricingField widget: two-mode segmented pricing control.
//
// Ported verbatim from:
//   docs/signup-designs/ServiceCreateForm/lib/widgets/pricing_field.dart
//   docs/signup-designs/ServiceEditForm/lib/widgets/pricing_field.dart
// (both files are identical — approved design is the source of truth).
//
// VelvetTouch craft preserved:
//   - Two-segment recessed inset track (NeumorphicInset) with a sliding
//     camel-gradient "thumb" (AnimatedAlign + extrudedSmall shadows).
//   - Field area cross-fades + resizes (AnimatedSize + AnimatedSwitcher) when
//     the mode changes.
//   - FIXED → one "Сума" field with "грн" suffix.
//   - RANGE → side-by-side "Від" / "До" fields with an inline cross-field
//     "max > min" hint line (static + error variant).
//
// Internals deliberately avoid holding any business logic: all state lives in
// [_ServiceFormState]. This widget is purely presentational — it renders
// whatever [mode]/error values are passed in and fires [onModeChanged] when
// the user taps a segment.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

// Re-export the domain enum so callers only need to import this file.
export 'package:beautica_mobile/features/services/domain/master_service.dart'
    show ServicePriceType;

/// Two-option pricing mode toggle with conditional field area.
///
/// Parent is responsible for owning the [TextEditingController]s and the
/// current [mode] (which lives in [_ServiceFormState]). This widget is fully
/// stateless — it renders props and fires callbacks.
///
/// Keys exposed for widget tests:
///   - `Key('pricing-toggle-fixed')`  — fixed-mode segment
///   - `Key('pricing-toggle-range')`  — range-mode segment
///   - `Key('pricing-fixed-amount')`  — NeumorphicInset for the fixed field
///   - `Key('pricing-range-min')`     — NeumorphicInset for the min field
///   - `Key('pricing-range-max')`     — NeumorphicInset for the max field
class PricingField extends StatelessWidget {
  const PricingField({
    super.key,
    required this.mode,
    required this.onModeChanged,
    required this.fixedController,
    required this.minController,
    required this.maxController,
    this.enabled = true,
    this.fixedError,
    this.minError,
    this.rangeError,
  });

  /// Currently selected pricing mode.
  final ServicePriceType mode;

  /// Called when the user taps the other segment.
  final ValueChanged<ServicePriceType> onModeChanged;

  final TextEditingController fixedController;
  final TextEditingController minController;
  final TextEditingController maxController;

  /// When false the toggle and fields are dimmed and non-interactive
  /// (matches the form's [_submitting] lock state).
  final bool enabled;

  /// Inline error for the single fixed-amount field.
  final String? fixedError;

  /// Inline error for the "Від" (min) field in range mode.
  final String? minError;

  /// Cross-field range error (max must be > min), shown once beneath the pair.
  final String? rangeError;

  static final List<TextInputFormatter> _priceFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(7),
  ];

  // Hoisted so _buildRange() allocates nothing on keystroke rebuilds.
  static final TextStyle _rangeErrorStyle = VelvetText.feedback(
    BrandColors.error,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Section label.
        Padding(
          padding: const EdgeInsets.only(
            left: VelvetSpacing.xs,
            bottom: VelvetSpacing.sm,
          ),
          child: Text(l10n.pricingSectionLabel, style: VelvetText.label()),
        ),

        // Mode toggle — recessed track + sliding camel thumb.
        _PricingModeToggle(
          mode: mode,
          enabled: enabled,
          onChanged: onModeChanged,
          l10n: l10n,
        ),
        const SizedBox(height: VelvetSpacing.md),

        // Conditional field area — cross-fades + resizes between modes.
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (Widget child, Animation<double> anim) =>
                FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    axisAlignment: -1,
                    child: child,
                  ),
                ),
            child: mode == ServicePriceType.fixed
                ? _buildFixed(l10n)
                : _buildRange(l10n),
          ),
        ),
      ],
    );
  }

  Widget _buildFixed(AppLocalizations l10n) {
    return KeyedSubtree(
      key: const ValueKey<String>('pricing-fixed'),
      child: _PricingInputField(
        fieldKey: const Key('pricing-fixed-amount'),
        label: l10n.pricingAmountLabel,
        controller: fixedController,
        enabled: enabled,
        hint: '500',
        suffixText: 'грн',
        formatters: _priceFormatters,
        errorText: fixedError,
      ),
    );
  }

  Widget _buildRange(AppLocalizations l10n) {
    final bool hasRangeError = rangeError != null;
    return KeyedSubtree(
      key: const ValueKey<String>('pricing-range'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _PricingInputField(
                  fieldKey: const Key('pricing-range-min'),
                  label: l10n.pricingFromLabel,
                  controller: minController,
                  enabled: enabled,
                  hint: '500',
                  suffixText: 'грн',
                  formatters: _priceFormatters,
                  errorText: minError,
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: _PricingInputField(
                  fieldKey: const Key('pricing-range-max'),
                  label: l10n.pricingToLabel,
                  controller: maxController,
                  enabled: enabled,
                  hint: '800',
                  suffixText: 'грн',
                  formatters: _priceFormatters,
                  // The cross-field error is surfaced once below the pair.
                  // Pass an empty string to flag the field ring without
                  // a duplicate message (mirrors the approved preview).
                  errorText: hasRangeError ? '' : null,
                ),
              ),
            ],
          ),
          // Inline range VALIDATION line beneath the pair — rendered only
          // when there is a range error. The always-on static hint was removed
          // per design; the cross-field error message still surfaces here.
          if (hasRangeError)
            Padding(
              padding: const EdgeInsets.only(
                left: VelvetSpacing.xs,
                right: VelvetSpacing.xs,
                top: VelvetSpacing.sm - 2,
              ),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 1.5),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 15,
                        color: BrandColors.error,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.xs + 2),
                    Expanded(child: Text(rangeError!, style: _rangeErrorStyle)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle widget
// ---------------------------------------------------------------------------

/// The two-segment soft-UI toggle. A single recessed inset track holds both
/// labels; the active half is a raised camel-gradient pillow that slides between
/// the two positions on selection.
///
/// Ported verbatim from the approved preview app's [_PricingModeToggle].
class _PricingModeToggle extends StatelessWidget {
  const _PricingModeToggle({
    required this.mode,
    required this.enabled,
    required this.onChanged,
    required this.l10n,
  });

  final ServicePriceType mode;
  final bool enabled;
  final ValueChanged<ServicePriceType> onChanged;
  final AppLocalizations l10n;

  static const double _height = 50;

  /// Inset between the recessed track and the sliding thumb. The thumb height
  /// is [_height] minus twice this pad, so referencing the same token keeps the
  /// two from drifting.
  static const double _pad = VelvetSpacing.xs;

  // Hoisted: VelvetRadii.button (16) - 4 = 12. Avoids per-LayoutBuilder alloc.
  static const BorderRadius _thumbRadius = BorderRadius.all(
    Radius.circular(12),
  );

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: NeumorphicInset(
        radius: VelvetRadii.button,
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: SizedBox(
            height: _height - (_pad * 2),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double half = constraints.maxWidth / 2;
                return Stack(
                  children: <Widget>[
                    // Sliding camel thumb.
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      alignment: mode == ServicePriceType.fixed
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        width: half,
                        height: _height - (_pad * 2),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: <Color>[
                              BrandColors.accentLatte,
                              BrandColors.accentDeep,
                            ],
                          ),
                          borderRadius: _thumbRadius,
                          boxShadow: VelvetShadows.extrudedSmall,
                        ),
                      ),
                    ),
                    // The two tappable labels over the thumb.
                    Row(
                      children: <Widget>[
                        _Segment(
                          segmentKey: const Key('pricing-toggle-fixed'),
                          label: l10n.pricingModeFixed,
                          icon: Icons.attach_money_rounded,
                          selected: mode == ServicePriceType.fixed,
                          onTap: enabled
                              ? () => onChanged(ServicePriceType.fixed)
                              : null,
                        ),
                        _Segment(
                          segmentKey: const Key('pricing-toggle-range'),
                          label: l10n.pricingModeRange,
                          icon: Icons.linear_scale_rounded,
                          selected: mode == ServicePriceType.range,
                          onTap: enabled
                              ? () => onChanged(ServicePriceType.range)
                              : null,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// One segment of the toggle. Extracted so it can be const-constructed.
class _Segment extends StatelessWidget {
  const _Segment({
    required this.segmentKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final Key segmentKey;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  // Hoisted to avoid per-build allocations for the common cases.
  static final TextStyle _selectedLabel = VelvetText.cta().copyWith(
    fontSize: 14,
    color: BrandColors.white,
    fontWeight: FontWeight.w700,
  );
  static final TextStyle _unselectedLabel = VelvetText.cta().copyWith(
    fontSize: 14,
    color: BrandColors.textSecondary,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? BrandColors.white : BrandColors.textSecondary;
    return Expanded(
      child: Semantics(
        key: segmentKey,
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: VelvetSpacing.xs + 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: selected ? _selectedLabel : _unselectedLabel,
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual pricing input field
//
// Extracted from [_VelvetFieldRow] in service_form.dart to avoid duplicating
// the same NeumorphicInset + TextField composition. Uses the same tokens
// (VelvetSpacing, VelvetSizes, BrandColors) and mirrors the approved preview's
// VelvetField exactly.
// ---------------------------------------------------------------------------

class _PricingInputField extends StatefulWidget {
  const _PricingInputField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.hint,
    required this.suffixText,
    required this.formatters,
    this.enabled = true,
    this.errorText,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String hint;
  final String suffixText;
  final List<TextInputFormatter> formatters;
  final bool enabled;
  final String? errorText;

  @override
  State<_PricingInputField> createState() => _PricingInputFieldState();
}

class _PricingInputFieldState extends State<_PricingInputField> {
  // Hoisted to avoid per-build allocations.
  static final TextStyle _inputStyle = VelvetText.input();
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
  );
  static final TextStyle _suffixStyle = VelvetText.input().copyWith(
    color: BrandColors.muted,
    fontWeight: FontWeight.w700,
  );
  static final TextStyle _labelStyle = VelvetText.label();
  static final TextStyle _errorStyle = VelvetText.feedback(BrandColors.error);

  late final FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()
      ..addListener(() {
        if (_focus.hasFocus != _focused && mounted) {
          setState(() => _focused = _focus.hasFocus);
        }
      });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError =
        widget.errorText != null && widget.errorText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Label row.
        Padding(
          padding: const EdgeInsets.only(
            left: VelvetSpacing.xs,
            bottom: VelvetSpacing.sm,
          ),
          child: Text(widget.label.toUpperCase(), style: _labelStyle),
        ),

        // Inset well with focus ring.
        NeumorphicInset(
          key: widget.fieldKey,
          focused: _focused,
          hasError: hasError || widget.errorText == '',
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm + 2,
            ),
            child: SizedBox(
              height: VelvetSizes.field - 2 * (VelvetSpacing.sm + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: widget.formatters,
                      style: _inputStyle,
                      cursorColor: BrandColors.accent,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: widget.hint,
                        hintStyle: _hintStyle,
                      ),
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  Text(widget.suffixText, style: _suffixStyle),
                ],
              ),
            ),
          ),
        ),

        // Inline error row (only when there's a non-empty error message).
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(
              left: VelvetSpacing.xs,
              right: VelvetSpacing.xs,
              top: VelvetSpacing.sm - 2,
            ),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: BrandColors.error,
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(child: Text(widget.errorText!, style: _errorStyle)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
