// Phase 4.3 — VelvetField labelled form field widget.
//
// Ported verbatim from
// `docs/signup-designs/MasterEditScreen/lib/widgets/velvet_field.dart`.
// Color references changed from `VelvetColors.*` to `BrandColors.*`; all
// VelvetSpacing/VelvetRadii/VelvetText constants are identical in production.
//
// Differences from [NeumorphicTextField]:
//   • Supports [maxLines] > 1 (bio textarea).
//   • Renders a live `n / max` character counter when [showCounter] is true.
//   • Shows an informational helper line (lock icon + caption) below the well
//     for privacy notes (phone field).
//   • Optional [prefixText] (e.g. `@` for Instagram).
//   • Labels are uppercased; a "необов'язково" tag appends when [optional].
//   • The [fieldKey] is forwarded to the inner [TextField] so widget tests can
//     find it via `find.byKey(Key('field-firstName'))`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

import 'neumorphic.dart';

/// A labelled neumorphic form field in the VelvetTouch language.
///
/// The input sits in a recessed (inset) well — the soft-UI equivalent of a
/// "pressed-in" text box. On focus the rim picks up an animated camel ring +
/// soft glow; on validation error the rim and helper line turn to the semantic
/// error tone (always paired with icon + text, never colour alone). Optional
/// [prefixText] (e.g. `@` for Instagram), [maxLines] / [maxLength] for the
/// bio textarea, and a live `n / max` counter when [showCounter] is set.
class VelvetField extends StatefulWidget {
  const VelvetField({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.hint,
    this.prefixText,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.optional = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;

  /// Stable key forwarded to the inner [TextField]. Used by widget tests to
  /// locate the field by key (e.g. `Key('field-firstName')`).
  final Key? fieldKey;

  final String? hint;
  final String? prefixText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final int? maxLength;
  final bool showCounter;

  /// When non-null the field renders its error state (rim colour + helper line).
  /// Driven externally by the parent [Form] validator result.
  final String? errorText;

  /// Informative, reassuring note rendered below the well (lock icon + text).
  /// Hidden while [errorText] is showing so the two helper lines never stack.
  final String? helperText;

  final bool enabled;

  /// Appends a muted "необов'язково" tag to the label when true.
  final bool optional;

  /// Optional change callback forwarded to the inner [TextField].
  final ValueChanged<String>? onChanged;

  @override
  State<VelvetField> createState() => _VelvetFieldState();
}

class _VelvetFieldState extends State<VelvetField> {
  late final FocusNode _focus;
  bool _focused = false;

  // All styles are static so they are built once at class-load time.
  // None of these are const (GoogleFonts calls are runtime), but they are
  // allocated only once across the entire app lifetime — zero per-frame cost.
  static final TextStyle _labelStyle = VelvetText.label();
  static final TextStyle _optionalTagStyle = VelvetText.label().copyWith(
    color: BrandColors.faint,
    letterSpacing: 0.3,
  );
  static final TextStyle _fieldInputStyle = VelvetText.input();
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
    fontWeight: FontWeight.w600,
  );
  static final TextStyle _prefixStyle = VelvetText.input().copyWith(
    color: BrandColors.accentDeep,
    fontWeight: FontWeight.w800,
  );
  static final TextStyle _errorStyle = VelvetText.feedback(BrandColors.error);
  static final TextStyle _counterStyle = VelvetText.statCaption().copyWith(
    color: BrandColors.muted,
  );
  // Caption (helper note) — Nunito 12/w600, textSecondary, height 1.4.
  static final TextStyle _captionStyle = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.4,
    letterSpacing: 0.1,
    color: BrandColors.textSecondary,
  );

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()
      ..addListener(() {
        if (_focus.hasFocus != _focused && mounted) {
          setState(() => _focused = _focus.hasFocus);
        }
      });
    if (widget.showCounter) {
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (widget.showCounter) {
      widget.controller.removeListener(_onChanged);
    }
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasError = widget.errorText != null;
    final bool multiline = widget.maxLines > 1;

    // Ring colour: error wins → focus camel → transparent (resting/disabled).
    final Color ringColor = hasError
        ? BrandColors.error
        : _focused
        ? BrandColors.accent
        : Colors.transparent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Label row (uppercased label + optional "необов'язково" tag).
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.sm),
          child: Row(
            children: <Widget>[
              Text(widget.label.toUpperCase(), style: _labelStyle),
              if (widget.optional) ...<Widget>[
                const SizedBox(width: VelvetSpacing.sm),
                // Ukrainian "необов'язково" — contains a Unicode apostrophe;
                // the l10n system is not used here because this tag is a
                // permanent design token of the VelvetField component itself,
                // not a user-facing translatable string in the usual sense.
                // The ARB approach would require a key per field which is
                // excessive for a UI-component-level token.
                Text('необов’язково', style: _optionalTagStyle),
              ],
            ],
          ),
        ),

        // The inset well + animated focus/error ring.
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            border: Border.all(
              color: ringColor,
              width: ringColor == Colors.transparent ? 0 : 1.6,
            ),
            boxShadow: _focused && !hasError
                ? <BoxShadow>[
                    BoxShadow(
                      color: BrandColors.accent.withValues(alpha: 0.28),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: NeumorphicInset(
            radius: VelvetRadii.field,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: multiline ? VelvetSpacing.md : VelvetSpacing.sm + 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (widget.prefixText != null)
                    Padding(
                      padding: EdgeInsets.only(
                        top: multiline ? 0 : 2,
                        right: 2,
                      ),
                      child: Text(widget.prefixText!, style: _prefixStyle),
                    ),
                  Expanded(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: multiline ? 0 : VelvetSizes.field - 24,
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: TextField(
                          key: widget.fieldKey,
                          controller: widget.controller,
                          focusNode: _focus,
                          enabled: widget.enabled,
                          maxLines: widget.maxLines,
                          minLines: widget.maxLines,
                          maxLength: widget.maxLength,
                          // Counter rendered manually below — suppress built-in.
                          buildCounter: _noCounter,
                          inputFormatters:
                              widget.inputFormatters ??
                              (widget.maxLength != null
                                  ? <TextInputFormatter>[
                                      LengthLimitingTextInputFormatter(
                                        widget.maxLength,
                                      ),
                                    ]
                                  : null),
                          keyboardType:
                              widget.keyboardType ??
                              (multiline
                                  ? TextInputType.multiline
                                  : TextInputType.text),
                          style: _fieldInputStyle,
                          cursorColor: BrandColors.accentDeep,
                          onChanged: widget.onChanged,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText: widget.hint,
                            hintStyle: _hintStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Helper line — error (icon + text) OR live char counter (or both if
        // counter is requested alongside a non-error state).
        if (hasError || widget.showCounter)
          Padding(
            padding: const EdgeInsets.only(
              left: 4,
              right: 4,
              top: VelvetSpacing.sm - 2,
            ),
            child: Row(
              children: <Widget>[
                if (hasError) ...<Widget>[
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: BrandColors.error,
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(child: Text(widget.errorText!, style: _errorStyle)),
                ] else
                  const Spacer(),
                if (widget.showCounter && widget.maxLength != null)
                  Text(
                    '${widget.controller.text.characters.length} / ${widget.maxLength}',
                    style: _counterStyle,
                  ),
              ],
            ),
          ),

        // Privacy / informational helper — lock icon + muted caption.
        // Suppressed while [errorText] is showing so the two never stack on
        // the same field.
        if (widget.helperText != null && !hasError)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: BrandColors.accent.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.xs + 2),
                Expanded(
                  child: Text(
                    widget.helperText!,
                    style: _captionStyle,
                    softWrap: true,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Suppresses [TextField]'s built-in counter — we render our own.
  Widget? _noCounter(
    BuildContext context, {
    required int currentLength,
    required int? maxLength,
    required bool isFocused,
  }) => null;
}
