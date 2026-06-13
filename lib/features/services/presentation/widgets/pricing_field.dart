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
//   - FIXED: one "Сума" field with "грн" suffix.
//   - RANGE (with durationController): flat Row — duration / min / '–' / max —
//     all three wells are equal Expanded(flex:1) siblings so they are rendered
//     at EXACTLY the same width. The '–' dash is a real in-flow element with
//     its own horizontal extent (never overlaps the well borders).
//     AnimatedSwitcher is replaced by an instant swap; AnimatedSize is retained
//     on the rangeError row so error appearance is still animated.
//   - Cross-field "max > min" validation line below the range pair.
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
    this.durationLabel,
    this.showSectionLabel = true,
    this.compact = false,
  });

  /// Optional controller for the DURATION (minutes) field.
  ///
  /// When supplied, [PricingField] renders the duration well to the LEFT of
  /// the price field(s) so duration + price always share a single horizontal
  /// line — at every phone width down to ~320 dp, in both fixed and range
  /// modes. In the compact service-setup row the well is label-less; in the
  /// create/edit form ([showSectionLabel] == true) the well carries
  /// [durationLabel] as its visible label.
  ///
  /// When null the price field(s) take the full width and carry their own
  /// labels (legacy layout, not used after Phase 5.x).
  final TextEditingController? durationController;

  /// Inline error for the duration well (only consulted when
  /// [durationController] is supplied).
  final String? durationError;

  /// Label shown above the duration well in non-compact (create/edit) mode.
  /// Ignored when [durationController] is null or in compact mode.
  final String? durationLabel;

  /// Whether to render the "ЦІНА" section label above the mode toggle. The
  /// create/edit form shows it; the compact service-setup row hides it (the
  /// surrounding card already frames the pricing block).
  final bool showSectionLabel;

  /// When true the wells are rendered without visible labels (a11y preserved
  /// via Semantics) and with tighter horizontal padding + gap, so the
  /// duration+price row fits a single line at ~320 dp. Used by the bulk
  /// service-setup row. The create/edit form uses false (default).
  final bool compact;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool hasDuration = durationController != null;

    // ---------------------------------------------------------------------------
    // Flat RANGE row — all three input wells are equal-flex siblings.
    //
    // Previous layout nested min+max inside Expanded(flex:2) which made them
    // ~8 dp narrower than duration (dash subtracted only from the price area).
    // New flat layout puts duration / min / max all as Expanded(flex:1) in the
    // SAME Row so Flutter distributes remaining width equally among all three.
    //
    //   FIXED (hasDuration):
    //     Row[Expanded(flex:1, duration) | SizedBox(gap) | Expanded(flex:1, price)]
    //
    //   RANGE (hasDuration):
    //     Row[
    //       Expanded(flex:1, duration),
    //       SizedBox(gap),
    //       Expanded(flex:1, min),
    //       Padding(horizontal xs, Text('--')),   <- fixed width, in-flow
    //       Expanded(flex:1, max),
    //     ]
    //
    // Width at 360 dp (32 dp screen padding => 328 dp row):
    //   FIXED  : gap=8 dp; each = (328-8)/2 = 160 dp
    //   RANGE  : gap=8, dash=8; each = (328-16)/3 = 104 dp  (duration == min == max)
    //   320 dp : each = (288-16)/3 ~ 90.7 dp  -- overflow-proof (Expanded)
    //
    // Duration State identity: _buildDurationWell always emits the same
    // _PricingInputField (locked key) as children[0]. Flutter keeps its
    // _PricingInputFieldState + FocusNode alive across fixed<->range toggles.
    //
    // Transition: AnimatedSwitcher could no longer wrap a single price-area
    // child after flattening, so it is replaced by an instant swap (the row
    // children change in place). AnimatedSize is retained on the rangeError
    // row so error appearance/disappearance stays smooth. Per spec,
    // correctness takes priority over the cross-fade.
    //
    // Legacy path (hasDuration == false): price area fills the full width,
    // delegated to _buildFixed / _buildRange as before.
    // ---------------------------------------------------------------------------

    final Widget pricingBody;
    if (!hasDuration) {
      pricingBody = mode == ServicePriceType.fixed
          ? _buildFixed(l10n, compact: compact)
          : _buildRange(l10n, compact: compact);
    } else if (mode == ServicePriceType.fixed) {
      pricingBody = Row(
        crossAxisAlignment: compact
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: _buildDurationWell(l10n, compact: compact)),
          SizedBox(width: compact ? VelvetSpacing.xs : VelvetSpacing.sm),
          Expanded(child: _buildFixed(l10n, compact: compact)),
        ],
      );
    } else {
      final bool hasRangeError = rangeError != null;
      pricingBody = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _buildDurationWell(l10n, compact: compact)),
              SizedBox(width: compact ? VelvetSpacing.xs : VelvetSpacing.sm),
              Expanded(
                child: _PricingInputField(
                  fieldKey: const Key('pricing-range-min'),
                  label: l10n.pricingFromLabel,
                  compact: compact,
                  controller: minController,
                  enabled: enabled,
                  hint: '500',
                  suffixText: 'грн',
                  formatters: _priceFormatters,
                  errorText: minError,
                  hideSuffixWhenActive: true,
                ),
              ),
              _buildDash(compact: compact),
              Expanded(
                child: _PricingInputField(
                  fieldKey: const Key('pricing-range-max'),
                  label: l10n.pricingToLabel,
                  compact: compact,
                  controller: maxController,
                  enabled: enabled,
                  hint: '800',
                  suffixText: 'грн',
                  formatters: _priceFormatters,
                  // Pass empty string to flag the error ring without a
                  // duplicate message below (mirrors the approved preview).
                  errorText: hasRangeError ? '' : null,
                  hideSuffixWhenActive: true,
                ),
              ),
            ],
          ),
          // Range validation line: AnimatedSize handles the height transition
          // when the error appears / disappears (no layout jump).
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: hasRangeError
                ? Padding(
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
                          Expanded(
                            child: Text(rangeError!, style: _rangeErrorStyle),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    }

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

        // Flat pricing body: see comment block above for full geometry rationale.
        // FIXED (hasDuration): Row[duration | gap | price]
        // RANGE (hasDuration): Row[duration | gap | min | dash | max] + rangeError
        // Legacy (no duration): delegated to _buildFixed / _buildRange.
        pricingBody,
      ],
    );
  }

  /// The duration well shown to the left of the price field(s).
  ///
  /// In compact mode (service-setup row) the label is suppressed (a11y via
  /// Semantics). In non-compact mode (create/edit form) [durationLabel] is
  /// shown above the well. The "хв" affix always stays visible — it is never
  /// hidden on focus/typing (only the "грн" affix on price fields hides).
  Widget _buildDurationWell(AppLocalizations l10n, {required bool compact}) {
    return _PricingInputField(
      fieldKey: compact
          ? const Key('service-setup-duration')
          : const Key('field-service-duration'),
      label: durationLabel ?? l10n.serviceSetupDurationLabel,
      compact: compact,
      controller: durationController!,
      enabled: enabled,
      hint: '60',
      suffixText: l10n.serviceSetupDurationSuffix,
      formatters: _durationFormatters,
      errorText: durationError,
      hideSuffixWhenActive: false,
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
      // Hide "грн" while the price field is active/non-empty to prevent the
      // suffix from overlapping digits on narrow screens. "хв" on the duration
      // well always stays visible (hideSuffixWhenActive defaults to false).
      hideSuffixWhenActive: true,
    );
    // _buildFixed returns only the price field. When hasDuration is true the
    // duration well is rendered as a sibling Expanded in build(), not here.
    return KeyedSubtree(
      key: const ValueKey<String>('pricing-fixed'),
      child: priceField,
    );
  }

  // Hoisted text style for the en-dash separator between min and max.
  static final TextStyle _separatorStyle = VelvetText.input().copyWith(
    color: BrandColors.muted,
    fontWeight: FontWeight.w700,
  );

  /// Builds the in-flow en-dash separator between min and max wells.
  ///
  /// In compact mode (no labels) a plain Center suffices. In non-compact mode
  /// a SizedBox offset of [VelvetSpacing.lg] pushes the dash down to align
  /// visually with the well body rather than floating near the label row.
  ///
  /// The dash is a REAL layout element with its own horizontal extent
  /// (2 x [VelvetSpacing.xs] padding) — it never overlaps either well.
  Widget _buildDash({required bool compact}) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.xs),
        child: Center(child: Text('–', style: _separatorStyle)),
      );
    }
    // Non-compact: label row above each well is ~VelvetSpacing.lg dp tall
    // (label text line-height + bottom gap). A matching SizedBox offset keeps
    // the dash vertically centred on the well body, not on label + well.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: VelvetSpacing.lg),
          Text('–', style: _separatorStyle),
        ],
      ),
    );
  }

  /// Legacy RANGE layout used only when [durationController] is null (i.e.
  /// the create/edit form without an inline duration well). When a
  /// [durationController] is supplied the flat-row RANGE is built directly
  /// inside [build] so all three fields are equal-flex siblings.
  Widget _buildRange(AppLocalizations l10n, {required bool compact}) {
    final bool hasRangeError = rangeError != null;

    return KeyedSubtree(
      key: const ValueKey<String>('pricing-range'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _PricingInputField(
                  fieldKey: const Key('pricing-range-min'),
                  label: l10n.pricingFromLabel,
                  compact: compact,
                  controller: minController,
                  enabled: enabled,
                  hint: '500',
                  suffixText: 'грн',
                  formatters: _priceFormatters,
                  errorText: minError,
                  hideSuffixWhenActive: true,
                ),
              ),
              _buildDash(compact: compact),
              Expanded(
                child: _PricingInputField(
                  fieldKey: const Key('pricing-range-max'),
                  label: l10n.pricingToLabel,
                  compact: compact,
                  controller: maxController,
                  enabled: enabled,
                  hint: '800',
                  suffixText: 'грн',
                  formatters: _priceFormatters,
                  // The cross-field error surfaces once below the pair.
                  // Empty string flags the field ring without a duplicate msg.
                  errorText: hasRangeError ? '' : null,
                  hideSuffixWhenActive: true,
                ),
              ),
            ],
          ),
          // Inline range validation line rendered only when there is an error.
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
    this.hideSuffixWhenActive = false,
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

  /// When true the suffix is hidden while the field is focused OR has
  /// non-empty text, preventing digits from overlapping the affix on narrow
  /// screens. Should be true for price fields ("грн") and false for the
  /// duration well ("хв" must stay visible at all times).
  final bool hideSuffixWhenActive;

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
  bool _hasText = false;

  void _onFocusChanged() {
    if (_focus.hasFocus != _focused && mounted) {
      setState(() => _focused = _focus.hasFocus);
    }
  }

  void _onTextChanged() {
    final bool nowHasText = widget.controller.text.isNotEmpty;
    if (nowHasText != _hasText && mounted) {
      setState(() => _hasText = nowHasText);
    }
  }

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    _focus = FocusNode()..addListener(_onFocusChanged);
    // Controller listener for hide-suffix-when-active: only attached when the
    // feature is enabled to avoid an unnecessary listener on the duration well.
    if (widget.hideSuffixWhenActive) {
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    if (widget.hideSuffixWhenActive) {
      widget.controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError =
        widget.errorText != null && widget.errorText!.isNotEmpty;

    // Suffix visibility: for price fields hide the "грн" affix whenever the
    // field is focused OR has non-empty text, so digits never overlap the
    // suffix on narrow screens. The "хв" suffix on the duration well is always
    // visible (hideSuffixWhenActive == false).
    final bool showSuffix =
        !widget.hideSuffixWhenActive || (!_focused && !_hasText);

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
              if (showSuffix) ...<Widget>[
                SizedBox(width: affixGap),
                Text(widget.suffixText, style: _suffixStyle),
              ],
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
