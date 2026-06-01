// Service-category request feature — "Suggest a category" dialog.
//
// Lets a master / salon owner propose a new platform category from the service
// form's category picker. Two inputs:
//   1. Display name (Ukrainian) — what the user types, e.g. "Нарощування вій".
//   2. Code (slug) — auto-derived uppercase latin slug, editable, validated
//      against ^[A-Z][A-Z0-9_]*$.
//
// On submit the dialog calls [ServiceRepository.requestCategory]. On success it
// pops returning `true` so the caller can show the success SnackBar (the dialog
// itself does not own the ScaffoldMessenger). On 409/429/other failures it
// shows an inline SnackBar within the dialog's own Scaffold messenger context
// and stays open so the user can correct or retry.
//
// Styling is 1:1 with the VelvetTouch neumorphic system used by service_form.dart
// (NeumorphicCard surface, NeumorphicInset field wells, NeumorphicButton CTA).

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Opens the suggest-a-category dialog.
///
/// Resolves to `true` when a request was submitted successfully (the caller
/// should then show the success SnackBar), or `null`/`false` when the user
/// cancelled or dismissed.
Future<bool?> showCategoryRequestDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const CategoryRequestDialog(),
  );
}

/// The suggest-a-category modal dialog (VelvetTouch neumorphic).
class CategoryRequestDialog extends ConsumerStatefulWidget {
  const CategoryRequestDialog({super.key});

  @override
  ConsumerState<CategoryRequestDialog> createState() =>
      _CategoryRequestDialogState();
}

class _CategoryRequestDialogState extends ConsumerState<CategoryRequestDialog> {
  static const _tag = 'feature.services.category_request_dialog';

  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;

  /// True once the user manually edits the code field — after which the slug
  /// stops auto-syncing from the display name.
  bool _codeManuallyEdited = false;

  bool _submitted = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _codeCtrl = TextEditingController();
    _nameCtrl.addListener(_onNameChanged);
    _codeCtrl.addListener(_onCodeChanged);
  }

  void _onNameChanged() {
    if (!mounted) return;
    // Auto-derive the slug until the user takes manual control of the code.
    if (!_codeManuallyEdited) {
      final derived = deriveCategorySlug(_nameCtrl.text);
      if (derived != _codeCtrl.text) {
        // Temporarily detach the code listener so this programmatic write is
        // not mistaken for a manual edit.
        _codeCtrl.removeListener(_onCodeChanged);
        _codeCtrl.value = TextEditingValue(
          text: derived,
          selection: TextSelection.collapsed(offset: derived.length),
        );
        _codeCtrl.addListener(_onCodeChanged);
      }
    }
    if (_submitted) setState(() {});
  }

  void _onCodeChanged() {
    if (!mounted) return;
    _codeManuallyEdited = true;
    if (_submitted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  // --- Validation -----------------------------------------------------------

  String? _nameError(AppLocalizations l10n) {
    if (!_submitted) return null;
    final trimmed = _nameCtrl.text.trim();
    if (trimmed.isEmpty) return l10n.categoryRequestNameError;
    if (trimmed.length > kCategoryDisplayNameMaxLength) {
      return l10n.categoryRequestNameTooLong;
    }
    return null;
  }

  String? _codeError(AppLocalizations l10n) {
    if (!_submitted) return null;
    return isValidCategorySlug(_codeCtrl.text.trim())
        ? null
        : l10n.categoryRequestCodeError;
  }

  bool _isValid(AppLocalizations l10n) =>
      _nameError(l10n) == null && _codeError(l10n) == null;

  // --- Submit ---------------------------------------------------------------

  Future<void> _handleSubmit(AppLocalizations l10n) async {
    setState(() => _submitted = true);
    if (!_isValid(l10n)) {
      setState(() {});
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(serviceRepositoryProvider)
          .requestCategory(
            name: _codeCtrl.text.trim(),
            displayName: _nameCtrl.text.trim(),
          );
      if (mounted) {
        // Return true so the caller surfaces the success SnackBar against the
        // parent screen's messenger (not the dialog's transient context).
        // context.pop pops the dialog route and resolves the awaiting
        // showDialog<bool> future in _openSuggestDialog with `true`.
        context.pop(true);
      }
    } catch (e) {
      if (kDebugMode) {
        log('CategoryRequestDialog.submit failed: $e', name: _tag, level: 900);
      }
      if (mounted) {
        setState(() => _submitting = false);
        final message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: NeumorphicCard(
          child: Padding(
            padding: const EdgeInsets.all(VelvetSpacing.lg),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Title.
                  Text(
                    l10n.categoryRequestTitle,
                    style: VelvetText.subheading(),
                  ),
                  const SizedBox(height: VelvetSpacing.sm),
                  // Quiet subline — sets the out-of-band approval expectation.
                  Text(l10n.categoryRequestSubtitle, style: VelvetText.body()),
                  const SizedBox(height: VelvetSpacing.xl),

                  // Field 1 — display name.
                  _DialogField(
                    fieldKey: const Key('field-category-request-name'),
                    label: l10n.categoryRequestNameLabel,
                    controller: _nameCtrl,
                    hintText: l10n.categoryRequestNameHint,
                    errorText: _nameError(l10n),
                    enabled: !_submitting,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(
                        kCategoryDisplayNameMaxLength,
                      ),
                    ],
                  ),
                  const SizedBox(height: VelvetSpacing.lg),

                  // Field 2 — code slug (auto-derived, editable).
                  _DialogField(
                    fieldKey: const Key('field-category-request-code'),
                    label: l10n.categoryRequestCodeLabel,
                    controller: _codeCtrl,
                    errorText: _codeError(l10n),
                    helperText: l10n.categoryRequestCodeHelper,
                    enabled: !_submitting,
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(kCategorySlugMaxLength),
                      // Upper-case as the user types so the field always mirrors
                      // the wire shape.
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) => newValue.copyWith(
                          text: newValue.text.toUpperCase(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: VelvetSpacing.xl),

                  // Footer — cancel (text) + submit (gradient CTA).
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        key: const Key('btn-cancel-suggest-category'),
                        onPressed: _submitting
                            ? null
                            : () => context.pop(false),
                        child: Text(
                          l10n.categoryRequestCancel,
                          style: VelvetText.body().copyWith(
                            color: const Color(0xFF9A8367), // BrandColors.muted
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.md),
                      Flexible(
                        child: NeumorphicButton(
                          key: const Key('btn-submit-suggest-category'),
                          label: l10n.categoryRequestSubmit,
                          icon: Icons.send_rounded,
                          loading: _submitting,
                          onPressed: _submitting
                              ? null
                              : () => _handleSubmit(l10n),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private dialog field — mirrors _VelvetFieldRow from service_form.dart.
//
// Label (uppercased Nunito) → NeumorphicInset well with focus ring → either an
// inline error row (icon + error text) when [errorText] is set, or a quiet
// helper caption when [helperText] is set and there is no error.
// ---------------------------------------------------------------------------

class _DialogField extends StatefulWidget {
  const _DialogField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.errorText,
    this.hintText,
    this.helperText,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? hintText;
  final String? helperText;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final bool enabled;

  @override
  State<_DialogField> createState() => _DialogFieldState();
}

class _DialogFieldState extends State<_DialogField> {
  // Hoisted styles — no per-build TextStyle allocations.
  static final TextStyle _labelStyle = VelvetText.label();
  static final TextStyle _inputStyle = VelvetText.input();
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: const Color(0xFFAD9A82), // BrandColors.placeholder
  );
  static final TextStyle _helperStyle = VelvetText.feedback(
    const Color(0xFF9A8367), // BrandColors.muted
  );
  static final TextStyle _errorStyle = VelvetText.feedback(
    const Color(0xFFB0452F), // BrandColors.error
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
    final bool showHelper = !hasError && widget.helperText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: VelvetSpacing.xs,
            bottom: VelvetSpacing.sm,
          ),
          child: Text(widget.label.toUpperCase(), style: _labelStyle),
        ),
        NeumorphicInset(
          key: widget.fieldKey,
          focused: _focused,
          hasError: hasError,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm + 2,
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              textCapitalization: widget.textCapitalization,
              inputFormatters: widget.inputFormatters,
              style: _inputStyle,
              cursorColor: const Color(0xFFB89A7A), // BrandColors.accent
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
        ),
        // Error row OR helper caption (animated swap so the dialog doesn't jump).
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: hasError
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
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 15,
                          color: Color(0xFFB0452F), // BrandColors.error
                        ),
                        const SizedBox(width: VelvetSpacing.xs + 2),
                        Expanded(
                          child: Text(widget.errorText!, style: _errorStyle),
                        ),
                      ],
                    ),
                  ),
                )
              : showHelper
              ? Padding(
                  padding: const EdgeInsets.only(
                    left: VelvetSpacing.xs,
                    right: VelvetSpacing.xs,
                    top: VelvetSpacing.sm - 2,
                  ),
                  child: Text(widget.helperText!, style: _helperStyle),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
