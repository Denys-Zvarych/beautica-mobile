// Phase 5.3 — Reusable service form widget.
//
// Stateless in terms of Riverpod — owns its own [TextEditingController]s and
// local [bool] flags through a thin [StatefulWidget]. The parent screen
// (ServiceCreateScreen, and later ServiceEditScreen in Phase 5.4) provides an
// [onSubmit] callback that receives the fully-validated [MasterServiceCreate]
// payload. The form is responsible only for:
//   - rendering three VelvetTouch fields (name, duration, price);
//   - running client-side validators on submit;
//   - toggling a loading state while [onSubmit] is in-flight.
//
// Description is intentionally absent from the UI (user decision: deferred).
// [MasterServiceCreate.description] is left null when the payload is built.

import 'dart:developer';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:flutter/foundation.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
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
/// [initialName], [initialDurationMinutes], and [initialPrice] seed the fields
/// for the edit use-case (Phase 5.4). They default to empty/zero, producing a
/// blank form for the create use-case.
///
/// [onSubmit] is awaited; the form disables the submit button and shows a
/// spinner while it is in-flight. Any exception thrown by [onSubmit] propagates
/// to the caller — the screen is responsible for error presentation.
class ServiceForm extends StatefulWidget {
  const ServiceForm({
    super.key,
    this.initialName = '',
    this.initialDurationMinutes,
    this.initialPrice,
    required this.onSubmit,
  });

  /// Pre-filled name (edit mode). Empty string = blank field (create mode).
  final String initialName;

  /// Pre-filled duration in minutes. Null = blank field.
  final int? initialDurationMinutes;

  /// Pre-filled price in UAH. Null = blank field.
  final double? initialPrice;

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

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _durationCtrl = TextEditingController(
      text: widget.initialDurationMinutes != null
          ? widget.initialDurationMinutes.toString()
          : '',
    );
    _priceCtrl = TextEditingController(
      text: widget.initialPrice != null
          ? widget.initialPrice!.toInt().toString()
          : '',
    );

    // After first submit, live-re-validate on every keystroke so errors clear
    // the instant the field becomes valid.
    for (final TextEditingController c in <TextEditingController>[
      _nameCtrl,
      _durationCtrl,
      _priceCtrl,
    ]) {
      c.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (_submitted && mounted) setState(() {});
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Intro sub-heading — mirrors the preview's quiet intent line.
        Padding(
          padding: const EdgeInsets.only(
            left: VelvetSpacing.xs,
            bottom: VelvetSpacing.lg,
          ),
          child: Text(l10n.serviceFormSubheading, style: _subheadingStyle),
        ),

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

        // CTA — Save button.
        NeumorphicButton(
          key: const Key('btn-submit-service'),
          label: l10n.masterSaveButton,
          icon: Icons.check_rounded,
          loading: _submitting,
          onPressed: _submitting ? null : () => _handleSubmit(l10n),
        ),
      ],
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
