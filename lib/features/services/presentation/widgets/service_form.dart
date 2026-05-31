// Phase 5.3 — Reusable service form widget.
// Phase 5.4 — Extended with [initial] MasterService support for the edit flow:
//   - Pre-populates fields from the loaded service.
//   - Dirty-state tracking: compares current field values vs the loaded baseline.
//   - Exposes a "Незбережені зміни" badge via [_DirtyMarker] (fades in whenever
//     any field diverges from the loaded values).
//   - [ServiceEditScreen] passes [initial] and a [MasterServiceUpdate]-producing
//     [onSubmit] callback; [ServiceCreateScreen] passes nothing (blank form).
//
// The parent screen (ServiceCreateScreen / ServiceEditScreen) provides an
// [onSubmit] callback that receives the fully-validated [MasterServiceCreate]
// payload. The form is responsible only for:
//   - rendering three VelvetTouch fields (name, duration, price);
//   - running client-side validators on submit;
//   - toggling a loading state while [onSubmit] is in-flight;
//   - showing the dirty-state marker when [initial] is set.
//
// Description is intentionally absent from the UI (user decision: deferred).
// [MasterServiceCreate.description] is left null when the payload is built.

import 'dart:developer';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:flutter/foundation.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/name_validator.dart';
import 'package:beautica_mobile/shared/validators/numeric_validators.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A form for creating or editing a service.
///
/// Renders three [NeumorphicTextField]-equivalent fields (using the project's
/// existing [NeumorphicInset] + [TextField] composition identical to the
/// approved preview app) and a [NeumorphicButton] CTA. Validation is
/// submit-triggered: errors surface after the first submit attempt, then clear
/// live as the user corrects each field.
///
/// [initial] seeds all fields for the edit use-case (Phase 5.4). When null,
/// the form starts blank (create use-case). When set, a dirty-state marker
/// ("Незбережені зміни") fades in beneath the sub-heading the moment any
/// field diverges from the loaded values, giving the master a quiet signal.
///
/// [submitLabel] overrides the CTA label. Defaults to [l10n.masterSaveButton]
/// when null, so the create screen gets "Зберегти" and the edit screen gets
/// "Зберегти зміни" by passing the appropriate l10n key.
///
/// [onSubmit] is awaited; the form disables the submit button and shows a
/// spinner while it is in-flight. Any exception thrown by [onSubmit] propagates
/// to the caller — the screen is responsible for error presentation.
class ServiceForm extends StatefulWidget {
  const ServiceForm({
    super.key,
    this.initial,
    this.submitLabel,
    required this.onSubmit,
  });

  /// Pre-filled service values (edit mode). Null = blank form (create mode).
  ///
  /// When set, the dirty-state marker is shown whenever any field value
  /// diverges from the baseline established by this object.
  final MasterService? initial;

  /// Override for the CTA button label. When null, uses [l10n.masterSaveButton].
  final String? submitLabel;

  /// Called with the validated payload when the user taps Save.
  ///
  /// Must return a [Future] so the form can show a loading spinner. Throw a
  /// [Failure] or any exception to surface an error at the screen level.
  final Future<void> Function(MasterServiceCreate input) onSubmit;

  @override
  State<ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<ServiceForm> {
  static const _tag = 'feature.services.form';

  // Label styles — cached to avoid per-frame TextStyle allocations.
  static final TextStyle _labelStyle = VelvetText.label();
  static final TextStyle _feedbackError = VelvetText.feedback(
    const Color(0xFFB0452F), // BrandColors.error
  );
  static final TextStyle _subheadingStyle = VelvetText.body();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _priceCtrl;

  bool _submitted = false;
  bool _submitting = false;
  bool _wasDirty = false;

  // Dirty-state baseline values (edit mode only). These are the string
  // representations of widget.initial fields — compared character-by-character
  // against the current field texts to determine if the form is dirty.
  late final String _baselineName;
  late final String _baselineDuration;
  late final String _baselinePrice;

  /// True when the form is in edit mode ([widget.initial] is set) and at
  /// least one field differs from the loaded service values.
  bool get _isDirty {
    if (widget.initial == null) return false;
    return _nameCtrl.text != _baselineName ||
        _durationCtrl.text != _baselineDuration ||
        _priceCtrl.text != _baselinePrice;
  }

  @override
  void initState() {
    super.initState();

    final MasterService? initial = widget.initial;

    // Price display: always integer — never "750.0" (backlog price-precision rule).
    _baselineName = initial?.name ?? '';
    _baselineDuration = initial != null
        ? initial.durationMinutes.toString()
        : '';
    _baselinePrice = initial != null ? initial.price.toInt().toString() : '';

    _nameCtrl = TextEditingController(text: _baselineName);
    _durationCtrl = TextEditingController(text: _baselineDuration);
    _priceCtrl = TextEditingController(text: _baselinePrice);

    // After first submit, live-re-validate on every keystroke so errors clear
    // the instant the field becomes valid. In edit mode, also repaint the dirty
    // badge on each keystroke.
    for (final TextEditingController c in <TextEditingController>[
      _nameCtrl,
      _durationCtrl,
      _priceCtrl,
    ]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!mounted) return;
    final dirty = _isDirty;
    if (_submitted || dirty != _wasDirty) {
      _wasDirty = dirty;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _durationCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  // --- Validators -----------------------------------------------------------

  String? _nameError(AppLocalizations l10n) {
    if (!_submitted) return null;
    return validateName(_nameCtrl.text, l10n);
  }

  String? _durationError(AppLocalizations l10n) {
    if (!_submitted) return null;
    return validateDurationMinutes(_durationCtrl.text, l10n);
  }

  String? _priceError(AppLocalizations l10n) {
    if (!_submitted) return null;
    return validatePriceUah(_priceCtrl.text, l10n);
  }

  bool _isValid(AppLocalizations l10n) =>
      _nameError(l10n) == null &&
      _durationError(l10n) == null &&
      _priceError(l10n) == null;

  // --- Submit ---------------------------------------------------------------

  Future<void> _handleSubmit(AppLocalizations l10n) async {
    setState(() => _submitted = true);
    if (!_isValid(l10n)) {
      // Surface the freshly-computed errors.
      setState(() {});
      return;
    }
    setState(() => _submitting = true);
    try {
      final input = MasterServiceCreate(
        name: _nameCtrl.text.trim(),
        durationMinutes: int.parse(_durationCtrl.text.trim()),
        price: double.parse(_priceCtrl.text.trim()),
        // Description is intentionally omitted from the form (user decision,
        // Phase 5.3). The domain model accepts null.
      );
      await widget.onSubmit(input);
    } catch (e, st) {
      if (kDebugMode) {
        log(
          'ServiceForm.onSubmit threw: $e',
          name: _tag,
          level: 900,
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  // --- Field builder --------------------------------------------------------

  /// Builds a labelled neumorphic inset field with optional suffix text and
  /// inline error rendering. Mirrors the [VelvetField] pattern from the
  /// approved preview app but uses the project's existing [NeumorphicInset]
  /// and [NeumorphicTextField] primitives.
  Widget _buildField({
    required Key fieldKey,
    required String label,
    required TextEditingController controller,
    required String? errorText,
    String? hintText,
    String? suffixText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool enabled = true,
  }) {
    return _VelvetFieldRow(
      fieldKey: fieldKey,
      label: label,
      controller: controller,
      errorText: errorText,
      hintText: hintText,
      suffixText: suffixText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      enabled: enabled,
      labelStyle: _labelStyle,
      feedbackErrorStyle: _feedbackError,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isEditMode = widget.initial != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Intro sub-heading — mirrors the preview's quiet intent line.
        Padding(
          padding: const EdgeInsets.only(left: VelvetSpacing.xs),
          child: Text(
            isEditMode
                ? l10n.serviceEditSubheading
                : l10n.serviceFormSubheading,
            style: _subheadingStyle,
          ),
        ),

        // Dirty-state marker (edit mode only) — fades in beneath the intro
        // line when any field diverges from the loaded service values.
        if (isEditMode) _DirtyMarker(visible: _isDirty, l10n: l10n),

        const SizedBox(height: VelvetSpacing.lg),

        // 1 — Service name (required, 1–255 chars).
        _buildField(
          fieldKey: const Key('field-service-name'),
          label: l10n.serviceNameLabel,
          controller: _nameCtrl,
          errorText: _nameError(l10n),
          hintText: l10n.serviceNameHint,
          enabled: !_submitting,
        ),
        const SizedBox(height: VelvetSpacing.lg),

        // 2 — Duration + Price side-by-side (master thinks of them together).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _buildField(
                fieldKey: const Key('field-service-duration'),
                label: l10n.serviceDurationLabel,
                controller: _durationCtrl,
                errorText: _durationError(l10n),
                hintText: '60',
                suffixText: 'хв',
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                enabled: !_submitting,
              ),
            ),
            const SizedBox(width: VelvetSpacing.md),
            Expanded(
              child: _buildField(
                fieldKey: const Key('field-service-price'),
                label: l10n.servicePriceLabel,
                controller: _priceCtrl,
                errorText: _priceError(l10n),
                hintText: '500',
                suffixText: '₴',
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(7),
                ],
                enabled: !_submitting,
              ),
            ),
          ],
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // CTA — Save / Save changes button.
        NeumorphicButton(
          key: const Key('btn-submit-service'),
          label: widget.submitLabel ?? l10n.masterSaveButton,
          icon: Icons.check_rounded,
          loading: _submitting,
          onPressed: _submitting ? null : () => _handleSubmit(l10n),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dirty-state marker
//
// A small camel inset pill that fades + slides in when the form diverges from
// its loaded values, and fades out when the user reverts every field. Mirrors
// the `_DirtyMarker` in the approved ServiceEditForm preview app exactly.
// ---------------------------------------------------------------------------

// Label styles extracted to `static final` to avoid per-frame allocations.
class _DirtyMarker extends StatelessWidget {
  const _DirtyMarker({required this.visible, required this.l10n});

  final bool visible;
  final AppLocalizations l10n;

  // Hoisted: never construct inside build().
  // feedbackAccentSm = Nunito 13/700, accentDeep, 12 sp — the closest
  // pre-cached variant to the approved preview's "caption accentDeep w800".
  // One cheap copyWith for the weight and tracking delta — far cheaper than
  // a full GoogleFonts.nunito() call on every frame.
  static final TextStyle _captionStyle = VelvetText.feedbackAccentSm.copyWith(
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topLeft,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: visible ? 1.0 : 0.0,
        child: visible
            ? Padding(
                padding: const EdgeInsets.only(
                  left: VelvetSpacing.xs,
                  top: VelvetSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      height: 7,
                      width: 7,
                      decoration: const BoxDecoration(
                        color: BrandColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    Text(l10n.serviceUnsavedChanges, style: _captionStyle),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private field widget
//
// Extracted to avoid nesting a StatefulWidget (FocusNode listener) directly
// inside the _ServiceFormState build method, which would create a new instance
// on every build. By lifting it to a named private class, the element tree is
// stable and Flutter correctly reconciles focus state.
// ---------------------------------------------------------------------------

class _VelvetFieldRow extends StatefulWidget {
  const _VelvetFieldRow({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.errorText,
    required this.labelStyle,
    required this.feedbackErrorStyle,
    this.hintText,
    this.suffixText,
    this.keyboardType,
    this.inputFormatters,
    this.enabled = true,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? hintText;
  final String? suffixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;

  // Passed from parent to reuse the single cached static instances.
  final TextStyle labelStyle;
  final TextStyle feedbackErrorStyle;

  @override
  State<_VelvetFieldRow> createState() => _VelvetFieldRowState();
}

class _VelvetFieldRowState extends State<_VelvetFieldRow> {
  // Hoisted to avoid per-build TextStyle allocations.
  static final TextStyle _inputStyle = VelvetText.input();
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: const Color(0xFFAD9A82), // BrandColors.placeholder
  );
  static final TextStyle _suffixStyle = VelvetText.input().copyWith(
    color: const Color(0xFF9A8367), // BrandColors.muted
    fontWeight: FontWeight.w700,
  );

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
    final bool hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Label row.
        Padding(
          padding: const EdgeInsets.only(
            left: VelvetSpacing.xs,
            bottom: VelvetSpacing.sm,
          ),
          child: Text(widget.label.toUpperCase(), style: widget.labelStyle),
        ),

        // Inset well with focus ring.
        NeumorphicInset(
          key: widget.fieldKey,
          focused: _focused,
          hasError: hasError,
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
                      keyboardType: widget.keyboardType ?? TextInputType.text,
                      inputFormatters: widget.inputFormatters,
                      style: _inputStyle,
                      cursorColor: const Color(
                        0xFFB89A7A,
                      ), // BrandColors.accent
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: widget.hintText,
                        hintStyle: _hintStyle,
                      ),
                    ),
                  ),
                  if (widget.suffixText != null) ...<Widget>[
                    const SizedBox(width: VelvetSpacing.sm),
                    Text(widget.suffixText!, style: _suffixStyle),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Inline error row.
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
                    color: Color(0xFFB0452F), // BrandColors.error
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      widget.errorText!,
                      style: widget.feedbackErrorStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
