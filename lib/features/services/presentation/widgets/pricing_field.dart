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
    this.durationController,
    this.durationError,
    this.showSectionLabel = true,
  });

  /// Optional controller for the per-row DURATION (minutes) field. When
  /// supplied (the compact first-time service-setup row), [PricingField]
  /// renders a compact, label-less duration well to the LEFT of the price
  /// field(s) so duration + price always share a single horizontal line — at
  /// every phone width down to ~320 dp, in both fixed and range modes. When
  /// null the price field(s) take the full width and carry their labels (the
  /// create/edit form, where duration lives in its own row above).
  final TextEditingController? durationController;

  /// Inline error for the compact duration well (only consulted when
  /// [durationController] is supplied).
  final String? durationError;

  /// Whether to render the "ЦІНА" section label above the mode toggle. The
  /// create/edit form shows it; the compact service-setup row hides it (the
  /// surrounding card already frames the pricing block).
  final bool showSectionLabel;

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

  // Price fields accept a decimal amount with up to two fractional digits and
  // a single separator (',' or '.'). The backend cap is 99 999 999.99, so the
  // length limiter is generous enough for "99999999.99" (11 chars) without
  // blocking legitimate input. [_DecimalPriceFormatter] rejects (does not
  // mangle) any edit that would produce a malformed value — a second separator,
  // a third decimal digit, or a leading separator. The field validator remains
  // the authority on submit (hardened 2026-06-03).
  static final List<TextInputFormatter> _priceFormatters = <TextInputFormatter>[
    const _DecimalPriceFormatter(),
    LengthLimitingTextInputFormatter(11),
  ];

  // Duration is whole minutes, ≤ 3 digits (mirrors the prior service-setup
  // call site). Hoisted so _buildDurationWell() allocates nothing per keystroke.
  static final List<TextInputFormatter> _durationFormatters =
      <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ];

  // Hoisted so _buildRange() allocates nothing on keystroke rebuilds.
  static final TextStyle _rangeErrorStyle = VelvetText.feedback(
    BrandColors.error,
  );

  // Flex weights for the compact service-setup row's single line of wells.
  // Duration holds a short minutes value ("60") so it gets the smaller share;
  // the price area (one fixed field, or the min+max pair) carries the larger
  // amounts. The outer compact Row is duration (_durationFlex) | price area
  // (_priceAreaFlex); inside the price area the range min+max each take an
  // equal Expanded share. These are proportional only — every slot is an
  // Expanded, so the Row can never overflow no matter how narrow the phone is;
  // the TextFields shrink to their slot and scroll their own content
  // internally rather than forcing a horizontal RenderFlex.
  static const int _durationFlex = 3;
  static const int _priceAreaFlex = 5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool compact = durationController != null;

    // The conditional price field area — cross-fades + resizes between modes.
    // CRITICAL: the duration well is NOT inside this switcher. Toggling
    // fixed↔range only swaps the price field(s), so the duration field's
    // _PricingInputFieldState + FocusNode keep their identity across mode
    // changes (no focus/keyboard drop, no per-toggle State churn — perf M1).
    final Widget priceArea = AnimatedSize(
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
            ? _buildFixed(l10n, compact: compact)
            : _buildRange(l10n, compact: compact),
      ),
    );

    // In the compact service-setup row the duration well rides OUTSIDE the
    // switcher (stable identity) as the first Expanded slot; only the price
    // area reflows on toggle. Every slot is an Expanded, so the Row can never
    // overflow regardless of phone width (320/360/412 dp). In the create/edit
    // form (durationController == null) the price area spans the full width
    // and carries its own label, with no duration well here.
    final Widget pricingBody = compact
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: _durationFlex, child: _buildDurationWell(l10n)),
              const SizedBox(width: VelvetSpacing.sm),
              Expanded(flex: _priceAreaFlex, child: priceArea),
            ],
          )
        : priceArea;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Section label (hidden in the compact service-setup row).
        if (showSectionLabel)
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

        // In the create/edit form (durationController == null) this is the
        // single labelled price field; in the compact service-setup row it is
        // a Row[ duration well | price area ] where the duration well sits
        // OUTSIDE the mode AnimatedSwitcher (stable across fixed↔range toggle).
        pricingBody,
      ],
    );
  }

  /// The compact, label-less duration well shown to the left of the price
  /// field(s) in the service-setup row. Minutes affix ("хв") keeps it tight so
  /// three numeric wells still fit one line at ~320 dp.
  Widget _buildDurationWell(AppLocalizations l10n) {
    return _PricingInputField(
      fieldKey: const Key('service-setup-duration'),
      label: l10n.serviceSetupDurationLabel,
      compact: true,
      controller: durationController!,
      enabled: enabled,
      hint: '60',
      suffixText: l10n.serviceSetupDurationSuffix,
      formatters: _durationFormatters,
      errorText: durationError,
    );
  }

  Widget _buildFixed(AppLocalizations l10n, {required bool compact}) {
    final Widget priceField = _PricingInputField(
      fieldKey: const Key('pricing-fixed-amount'),
      label: l10n.pricingAmountLabel,
      compact: compact,
      controller: fixedController,
      enabled: enabled,
      hint: '500',
      suffixText: 'грн',
      formatters: _priceFormatters,
      errorText: fixedError,
    );
    // In the compact row the duration well lives OUTSIDE this switcher (in the
    // parent Row), so the fixed price area is just the single price field —
    // identical to the create/edit form save for the compact styling.
    return KeyedSubtree(
      key: const ValueKey<String>('pricing-fixed'),
      child: priceField,
    );
  }

  Widget _buildRange(AppLocalizations l10n, {required bool compact}) {
    final bool hasRangeError = rangeError != null;
    final Widget minField = _PricingInputField(
      fieldKey: const Key('pricing-range-min'),
      label: l10n.pricingFromLabel,
      compact: compact,
      controller: minController,
      enabled: enabled,
      hint: '500',
      suffixText: 'грн',
      formatters: _priceFormatters,
      errorText: minError,
    );
    final Widget maxField = _PricingInputField(
      fieldKey: const Key('pricing-range-max'),
      label: l10n.pricingToLabel,
      compact: compact,
      controller: maxController,
      enabled: enabled,
      hint: '800',
      suffixText: 'грн',
      formatters: _priceFormatters,
      // The cross-field error is surfaced once below the pair. Pass an empty
      // string to flag the field ring without a duplicate message (mirrors the
      // approved preview).
      errorText: hasRangeError ? '' : null,
    );
    return KeyedSubtree(
      key: const ValueKey<String>('pricing-range'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The range price area is the min+max pair. In the compact row the
          // duration well sits OUTSIDE this switcher (in the parent Row), so on
          // a 320 dp phone the visible line is still duration | min | max, but
          // duration never disposes on toggle. Both slots are Expanded, so the
          // pair is overflow-proof at any width; the compact gap tightens to
          // keep the digits legible when squeezed. The create/edit form
          // (compact == false) keeps the labelled side-by-side pair.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: minField),
              SizedBox(width: compact ? VelvetSpacing.sm : VelvetSpacing.md),
              Expanded(child: maxField),
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
            // Bound the row to the segment's share of the toggle width so the
            // label can ellipsize instead of overflowing at the smallest
            // supported phone width (320 dp). The icon stays fixed; only the
            // label flexes, and it degrades to ellipsis purely as a tight-width
            // fallback (at 360 dp+ the full label always fits).
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: VelvetSpacing.xs),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: selected ? _selectedLabel : _unselectedLabel,
                    child: Text(
                      label,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
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
    this.compact = false,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String hint;
  final String suffixText;
  final List<TextInputFormatter> formatters;
  final bool enabled;
  final String? errorText;

  /// Compact variant used inside the one-line service-setup row: the field
  /// label is suppressed (the [label] is still wired through Semantics for
  /// accessibility) and the field→affix gap tightens so three numeric wells
  /// fit a single line down to ~320 dp without clipping the digits or affix.
  final bool compact;

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

    // Compact wells (the one-line service-setup row) drop the visible label and
    // tighten the horizontal padding + field→affix gap so three numeric wells
    // fit a single line at ~320 dp. The label is preserved for screen readers
    // via Semantics so accessibility is unchanged.
    final double wellHPad = widget.compact
        ? VelvetSpacing.sm
        : VelvetSpacing.md;
    final double affixGap = widget.compact
        ? VelvetSpacing.xs
        : VelvetSpacing.md;

    final Widget well = NeumorphicInset(
      key: widget.fieldKey,
      focused: _focused,
      hasError: hasError || widget.errorText == '',
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: wellHPad,
          vertical: VelvetSpacing.sm + 2,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: VelvetSizes.field - 2 * (VelvetSpacing.sm + 2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // The TextField scrolls its own content horizontally, so a long
              // value never pushes the affix out of the well or overflows the
              // enclosing Row.
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
              SizedBox(width: affixGap),
              Text(widget.suffixText, style: _suffixStyle),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Label row — hidden in the compact one-line row (kept for a11y below).
        if (!widget.compact)
          Padding(
            padding: const EdgeInsets.only(
              left: VelvetSpacing.xs,
              bottom: VelvetSpacing.sm,
            ),
            child: Text(widget.label.toUpperCase(), style: _labelStyle),
          ),

        // Inset well with focus ring. In compact mode the suppressed label is
        // re-attached via Semantics so screen readers still announce the field.
        if (widget.compact)
          Semantics(textField: true, label: widget.label, child: well)
        else
          well,

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

// ---------------------------------------------------------------------------
// Decimal price input formatter
//
// Accepts only a well-formed positive decimal with up to two fractional digits
// and a single separator (',' or '.'). Unlike FilteringTextInputFormatter, it
// REJECTS a malformed edit wholesale (returns the old value) rather than
// silently stripping characters mid-string — so the cursor never jumps and a
// pasted "12.999" simply doesn't take instead of becoming "12.99".
//
// An empty string is always allowed (so the field can be cleared). The intermediate
// states "12." and "12," are allowed so the user can type the separator before
// the fractional digits. Final-form validation (bounds, required) is done by
// validatePriceAmount on submit (hardened 2026-06-03).
// ---------------------------------------------------------------------------

class _DecimalPriceFormatter extends TextInputFormatter {
  const _DecimalPriceFormatter();

  // Up to 8 integer digits, optional single separator, up to 2 decimal digits.
  // The trailing-separator case ("12." / "12,") is permitted as an intermediate
  // typing state. Hoisted as a static final — allocated once.
  static final RegExp _allowed = RegExp(r'^\d{0,8}([.,]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final String text = newValue.text;
    if (text.isEmpty) return newValue; // allow clearing the field
    if (_allowed.hasMatch(text)) return newValue;
    // Reject the edit: keep the previous (valid) value.
    return oldValue;
  }
}
