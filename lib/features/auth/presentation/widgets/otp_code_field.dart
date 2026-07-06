// Shared 6-digit OTP entry field — extracted from `verification_screen.dart`
// (Phase 2.11 VelvetTouch redesign) so the password-reset OTP flow can reuse
// the exact same visual treatment (Beautica OTP task, "Phase B1").
//
// Six neumorphic cells driven by a single hidden numeric input. The active
// cell renders with a camel border ring (focused); inactive filled cells are
// extruded-small; empty cells are extruded-small with no digit.
//
// Zero behavioural change from the original `_OtpField`/`_OtpCell` private
// widgets: [fieldKey] and [semanticsLabel] are now constructor parameters so
// [VerificationScreen] can pass its original literal values unchanged, while
// new callers (the password-reset OTP screen) supply their own key + l10n
// string instead of inheriting email-verification-specific copy.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// A row of [length] neumorphic OTP cells backed by a single hidden
/// [TextField] that owns the real text input + system keyboard.
class OtpCodeField extends StatelessWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.fieldKey,
    required this.semanticsLabel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;

  /// Key applied to the hidden [TextField] — widget tests drive OTP entry via
  /// `tester.enterText(find.byKey(fieldKey), ...)`.
  final Key fieldKey;

  /// Accessibility label announced for the OTP entry as a whole.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      textField: true,
      child: GestureDetector(
        onTap: focusNode.requestFocus,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Hidden input that owns the actual text + system keyboard.
            // The Opacity(opacity: 0) wrapper is intentional — it keeps the
            // TextField in the widget tree (keyboard accessibility / focus
            // management / autofill) while rendering it invisible. Do not
            // replace with Offstage, which removes the widget from layout.
            Opacity(
              opacity: 0,
              child: SizedBox(
                height: 1,
                width: 1,
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: length,
                  showCursor: false,
                  // Prevent IME from training on OTP digits (MASVS-PLATFORM).
                  enableSuggestions: false,
                  autocorrect: false,
                  enableIMEPersonalizedLearning: false,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(length),
                  ],
                  decoration: const InputDecoration(counterText: ''),
                ),
              ),
            ),
            // Visible cells — driven by the hidden controller's text.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < length; i++) ...<Widget>[
                  Flexible(
                    child: _OtpCell(
                      digit: i < controller.text.length
                          ? controller.text[i]
                          : '',
                      active: i == controller.text.length && focusNode.hasFocus,
                    ),
                  ),
                  if (i != length - 1)
                    const SizedBox(width: VelvetSpacing.sm + 2),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single OTP cell — neumorphic extruded tile that shows one digit.
// Active (cursor position): camel border, no shadow.
// Filled: extruded-small shadow, accent-colored digit.
// Empty: extruded-small shadow, no digit.
// ---------------------------------------------------------------------------

class _OtpCell extends StatelessWidget {
  const _OtpCell({required this.digit, required this.active});

  final String digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 50,
      constraints: const BoxConstraints(maxWidth: 41),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        boxShadow: active ? const <BoxShadow>[] : VelvetShadows.extrudedSmall,
        border: active ? Border.all(color: BrandColors.accent, width: 2) : null,
      ),
      child: Text(digit, style: VelvetText.otpDigit),
    );
  }
}
