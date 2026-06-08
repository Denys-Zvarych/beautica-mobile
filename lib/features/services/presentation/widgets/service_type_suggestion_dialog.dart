// Service-type suggestion feature — "Suggest a service type" dialog.
//
// Lets a master propose a new platform service type from the service form's
// second-level service-type picker (Phase 16.4). A single input:
//   1. Name (Ukrainian, required) — the suggested service, e.g. "Ламінування вій".
//
// The owning category is NOT user-entered: the picker passes in the currently-
// selected category's System-B `categoryName` slug as read-only context, which
// the dialog forwards to the backend. The slug is never shown to or edited by
// the user.
//
// On submit the dialog calls [ServiceRepository.suggestServiceType]. On success
// it pops returning `true` so the caller can show the success SnackBar (the
// dialog itself does not own the ScaffoldMessenger). On 400 it maps
// [ValidationFailure.fieldErrors] to the inline name-field error; on 429/other
// failures it shows an inline SnackBar within the dialog's own messenger context
// and stays open so the user can correct or retry.
//
// Styling is 1:1 with category_request_dialog.dart (VelvetTouch neumorphic):
// NeumorphicCard surface, NeumorphicInset field wells, NeumorphicButton CTA, and
// the private [_DialogField] row. No glassmorphism.

import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/navigation/overlay_navigation.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Upper bound for the suggested service-type name (mirrors the backend
/// contract; the category dialog uses the same 100-char display-name cap).
const int kServiceTypeNameMaxLength = 100;

/// Opens the suggest-a-service-type dialog for the category identified by
/// [categoryName] (the System-B slug of the currently-selected category — a
/// read-only context value the picker supplies; the user never edits it).
///
/// Resolves to `true` when a suggestion was submitted successfully (the caller
/// should then show the success SnackBar), or `null`/`false` when the user
/// cancelled or dismissed.
Future<bool?> showServiceTypeSuggestionDialog(
  BuildContext context, {
  required String categoryName,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => ServiceTypeSuggestionDialog(categoryName: categoryName),
  );
}

/// The suggest-a-service-type modal dialog (VelvetTouch neumorphic).
class ServiceTypeSuggestionDialog extends ConsumerStatefulWidget {
  const ServiceTypeSuggestionDialog({required this.categoryName, super.key});

  /// The System-B slug of the owning category, forwarded to the backend as
  /// `categoryName`. Read-only context — never surfaced to the user.
  final String categoryName;

  @override
  ConsumerState<ServiceTypeSuggestionDialog> createState() =>
      _ServiceTypeSuggestionDialogState();
}

class _ServiceTypeSuggestionDialogState
    extends ConsumerState<ServiceTypeSuggestionDialog> {
  static const _tag = 'feature.services.service_type_suggestion_dialog';

  late final TextEditingController _nameCtrl;

  bool _submitted = false;
  bool _submitting = false;

  /// Server-side validation error for the name field, set when a
  /// [ValidationFailure] carries a `name` key. Takes precedence over the local
  /// rules and is cleared on the next edit.
  String? _serverNameError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (!mounted) return;
    // Clear a stale server error as soon as the user edits the field, and
    // rebuild so the live local-validation error tracks the new value.
    final hadServerError = _serverNameError != null;
    if (hadServerError) _serverNameError = null;
    if (_submitted || hadServerError) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // --- Validation -----------------------------------------------------------

  String? _nameError(AppLocalizations l10n) {
    // Server-side validation error takes precedence over the local rules.
    if (_serverNameError != null) return _serverNameError;
    if (!_submitted) return null;
    final trimmed = _nameCtrl.text.trim();
    if (trimmed.isEmpty) return l10n.serviceTypeSuggestNameError;
    return null;
  }

  bool _isValid(AppLocalizations l10n) => _nameError(l10n) == null;

  // --- Submit ---------------------------------------------------------------

  Future<void> _handleSubmit(AppLocalizations l10n) async {
    setState(() => _submitted = true);
    if (!_isValid(l10n)) {
      setState(() {});
      return;
    }
    setState(() => _submitting = true);
    try {
      final name = _nameCtrl.text.trim();
      await ref
          .read(serviceRepositoryProvider)
          .suggestServiceType(
            categoryName: widget.categoryName,
            name: name,
            // The description field was removed from this dialog; the repo keeps
            // its `String? description` param for API stability, so always pass
            // null (the generated model omits a null `description` key).
            description: null,
          );
      if (mounted) {
        // Return true so the caller surfaces the success SnackBar against the
        // parent screen's messenger (not the dialog's transient context).
        // dismissOverlay pops the dialog route and resolves the awaiting
        // showDialog<bool> future with `true`.
        dismissOverlay(context, true);
      }
    } catch (e) {
      if (kDebugMode) {
        log(
          'ServiceTypeSuggestionDialog.submit failed: $e',
          name: _tag,
          level: 900,
        );
      }
      if (mounted) {
        // A ValidationFailure carrying a `name` field error maps to the inline
        // name-field error instead of a transient snackbar, so the user sees
        // exactly which field the backend rejected.
        if (e is ValidationFailure) {
          final fieldMsg = e.fieldErrors['name'];
          if (fieldMsg != null) {
            setState(() {
              _submitting = false;
              _serverNameError = fieldMsg;
            });
            return;
          }
        }
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

    // The Dialog widget already accounts for the software keyboard by applying
    // MediaQuery.viewInsetsOf(context) internally to its effectivePadding.
    // Adding viewInsetsBottom manually to insetPadding.bottom and subtracting
    // it from maxHeight double-counts the keyboard height — causing the card to
    // shrink (button clipped) and re-centre upward (jump-to-top).  Both
    // problems are fixed by using static insetPadding and omitting the keyboard
    // term from the height constraint.  SingleChildScrollView already handles
    // any overflow so the submit button is always reachable.
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
                    l10n.serviceTypeSuggestTitle,
                    style: VelvetText.subheading(),
                  ),
                  const SizedBox(height: VelvetSpacing.sm),
                  // Quiet subline — sets the out-of-band approval expectation.
                  Text(
                    l10n.serviceTypeSuggestSubtitle,
                    style: VelvetText.body(),
                  ),
                  const SizedBox(height: VelvetSpacing.xl),

                  // Name (required).
                  _DialogField(
                    fieldKey: const Key('field-service-type-suggest-name'),
                    label: l10n.serviceTypeSuggestNameLabel,
                    controller: _nameCtrl,
                    hintText: l10n.serviceTypeSuggestNameHint,
                    errorText: _nameError(l10n),
                    enabled: !_submitting,
                    textCapitalization: TextCapitalization.sentences,
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(
                        kServiceTypeNameMaxLength,
                      ),
                    ],
                  ),
                  const SizedBox(height: VelvetSpacing.xl),

                  // Footer — cancel (text) + submit (gradient CTA).
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        key: const Key('btn-cancel-suggest-service-type'),
                        onPressed: _submitting
                            ? null
                            : () => dismissOverlay(context, false),
                        child: Text(
                          l10n.serviceTypeSuggestCancel,
                          style: VelvetText.body().copyWith(
                            color: const Color(0xFF9A8367), // BrandColors.muted
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.md),
                      Flexible(
                        child: NeumorphicButton(
                          key: const Key('btn-submit-suggest-service-type'),
                          label: l10n.serviceTypeSuggestSubmit,
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
// Private dialog field — mirrors _DialogField from category_request_dialog.dart.
//
// Label (uppercased Nunito) → NeumorphicInset well with focus ring → an inline
// error row (icon + error text) when [errorText] is set.
// ---------------------------------------------------------------------------

class _DialogField extends StatefulWidget {
  const _DialogField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.errorText,
    this.hintText,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? errorText;
  final String? hintText;
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
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
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
        // Inline error row (animated swap so the dialog doesn't jump).
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
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
