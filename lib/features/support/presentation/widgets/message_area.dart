// A tall multiline message well built on the inset neumorphic treatment, with a
// live character counter tucked into its bottom-right corner. The counter flips
// to the error tone while the message is below the minimum so the affordance
// reads without a separate banner.
//
// Used for the required support message (10..5000 chars). The label sits above
// the well; an inline helper / error row renders below it.
//
// Design source: `docs/signup-designs/ContactSupport/lib/widgets/
// message_area.dart` — ported 1:1, swapping VelvetColors → BrandColors.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:flutter/material.dart';

/// A tall multiline message field with a live `n/max` counter.
class MessageArea extends StatefulWidget {
  const MessageArea({
    super.key,
    required this.label,
    required this.controller,
    required this.minLength,
    required this.maxLength,
    this.fieldKey,
    this.hintText,
    this.errorText,
    this.helperText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final int minLength;
  final int maxLength;
  final Key? fieldKey;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  @override
  State<MessageArea> createState() => _MessageAreaState();
}

class _MessageAreaState extends State<MessageArea> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  static final TextStyle _labelStyle = VelvetText.label();
  static final TextStyle _inputStyle = VelvetText.input().copyWith(
    height: 1.45,
  );
  static final TextStyle _hintStyle = VelvetText.input().copyWith(
    color: BrandColors.placeholder,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );
  static final TextStyle _errorStyle = VelvetText.feedback(BrandColors.error);
  static final TextStyle _helperStyle = VelvetText.feedback(BrandColors.muted);

  // Live-counter styles — hoisted so the per-keystroke counter rebuild never
  // re-allocates the TextStyle. They differ only by color; pick by validity.
  static final TextStyle _counterMuted = VelvetText.feedback(BrandColors.muted)
      .copyWith(
        fontSize: 12,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
  static final TextStyle _counterError = VelvetText.feedback(BrandColors.error)
      .copyWith(
        fontSize: 12,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int len = widget.controller.text.characters.length;
    final bool hasError = widget.errorText != null;
    final bool belowMin = len > 0 && len < widget.minLength;
    final TextStyle counterStyle = (hasError || belowMin)
        ? _counterError
        : _counterMuted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: VelvetSpacing.sm),
          child: Text(widget.label, style: _labelStyle),
        ),
        NeumorphicInset(
          focused: _focused,
          hasError: hasError,
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  VelvetSpacing.md,
                  VelvetSpacing.md,
                  VelvetSpacing.md,
                  VelvetSpacing.lg + VelvetSpacing.xs,
                ),
                child: TextField(
                  key: widget.fieldKey,
                  controller: widget.controller,
                  focusNode: _focusNode,
                  maxLength: widget.maxLength,
                  maxLines: 6,
                  minLines: 6,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onChanged: widget.onChanged,
                  style: _inputStyle,
                  cursorColor: BrandColors.accent,
                  decoration: InputDecoration(
                    counterText: '',
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.hintText,
                    hintStyle: _hintStyle,
                  ),
                ),
              ),
              // Live counter, tucked into the well's bottom-right corner.
              Positioned(
                right: VelvetSpacing.md,
                bottom: VelvetSpacing.sm + 2,
                child: Text('$len/${widget.maxLength}', style: counterStyle),
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: VelvetSpacing.sm),
            child: Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    size: 15,
                    color: BrandColors.error,
                  ),
                  const SizedBox(width: VelvetSpacing.xs + 2),
                  Expanded(child: Text(widget.errorText!, style: _errorStyle)),
                ],
              ),
            ),
          )
        else if (widget.helperText != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, top: VelvetSpacing.sm),
            child: Text(widget.helperText!, style: _helperStyle),
          ),
      ],
    );
  }
}
