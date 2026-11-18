// PhoneFirstAuth (M515 item 4) — the ONE shared SMS-code step, promoted from
// the `reset_otp_verification_screen.dart` / `verification_screen.dart`
// layout (never a fork): AuthScaffold(bottomBar CTA) > icon tile > heading >
// description + bold target > OtpCodeField > OtpResendRow > inline AuthBanner.
//
// Design source: docs/signup-designs/PhoneFirstAuth/lib/widgets/
// phone_code_step.dart (approved 2026-11-18). Reused by M517 (phone add /
// change, notification email) and M521 (invite accept) with no fork.
//
// Slots (all optional; defaults = a plain code step):
//   [header]                 replaces icon tile + heading (wizard chrome).
//   [requireCurrentPassword] AUTH-D19: phone CHANGE / email add+change ask for
//                            the current password with the code (M517).
//   [passwordError]          «Невірний поточний пароль» under that field.
//   [locked]                 AUTH-D19 per-account lockout: banner + CTA off.

import 'package:flutter/material.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/velvet_geometry.dart';
import '../../../../core/theme/velvet_text.dart';
import '../../../../core/widgets/neumorphic.dart';
import '../../../../l10n/app_localizations.dart';
import 'auth_icon_tile.dart';
import 'auth_scaffold.dart';
import 'otp_code_field.dart';
import 'otp_resend_row.dart';

const int _kOtpLength = 6;

/// M515 item 4 — resend cooldown of the SMS code step (60 s).
const int kPhoneCodeResendCooldownSeconds = 60;

/// Shared SMS-code entry step (see the file header).
class PhoneCodeStep extends StatefulWidget {
  const PhoneCodeStep({
    super.key,
    required this.description,
    required this.onConfirm,
    required this.onResend,
    this.target,
    this.icon = Icons.sms_outlined,
    this.headline,
    this.header,
    this.ctaLabel,
    this.requireCurrentPassword = false,
    this.passwordError,
    this.codeError,
    this.locked = false,
    this.onBack,
    this.showBack = true,
    this.onCodeChanged,
  });

  /// Copy before the bold [target] («Ми надіслали 6-значний код у SMS на»).
  final String description;

  /// Masked / formatted phone or email shown bold on its own line; `null` =
  /// neutral copy (forgot-password never names the channel, AUTH-D18).
  final String? target;
  final IconData icon;

  /// Heading when no [header] is given; `null` = «Підтвердіть номер».
  final String? headline;
  final Widget? header;

  /// CTA label; `null` = «Підтвердити».
  final String? ctaLabel;
  final bool requireCurrentPassword;
  final String? passwordError;

  /// Inline error banner under the resend row (wrong / expired code, …).
  final String? codeError;
  final bool locked;
  final VoidCallback? onBack;
  final bool showBack;

  /// Called with the 6 digits (and the current password, `''` unless
  /// [requireCurrentPassword]) on «Підтвердити». The CTA shows its busy state
  /// until the future completes.
  final Future<void> Function(String code, String password) onConfirm;

  /// «Надіслати знову» — returns the cooldown seconds to show, or `null` to
  /// leave the row as is (see [OtpResendRow.onResend]).
  final Future<int?> Function() onResend;

  /// Every edit of the code (e.g. to clear a stale [codeError]).
  final ValueChanged<String>? onCodeChanged;

  @override
  State<PhoneCodeStep> createState() => _PhoneCodeStepState();
}

class _PhoneCodeStepState extends State<PhoneCodeStep> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  /// Drives ONLY the CTA: a password keystroke must not rebuild the code
  /// cells (no `setState` on the step).
  late final Listenable _ctaInputs = Listenable.merge(<Listenable>[
    _codeController,
    _passwordController,
  ]);
  String _lastCode = '';

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeEdited);
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeEdited);
    _codeController.dispose();
    _passwordController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _onCodeEdited() {
    final String code = _codeController.text;
    if (code == _lastCode) return;
    _lastCode = code;
    widget.onCodeChanged?.call(code);
  }

  bool _ready() =>
      !widget.locked &&
      _codeController.text.length == _kOtpLength &&
      (!widget.requireCurrentPassword || _passwordController.text.isNotEmpty);

  Future<void> _confirm() =>
      widget.onConfirm(_codeController.text, _passwordController.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? target = widget.target;
    final String? banner = widget.locked
        ? l10n.phoneCodeLocked
        : widget.codeError;
    final Widget? header = widget.header;

    return AuthScaffold(
      showBack: widget.showBack,
      onBack: widget.onBack,
      bottomBar: ListenableBuilder(
        listenable: _ctaInputs,
        builder: (BuildContext context, Widget? _) => NeumorphicButton(
          key: const ValueKey<String>('phone_code_submit'),
          label: widget.ctaLabel ?? l10n.resetOtpConfirmBtn,
          onPressed: null,
          onPressedAsync: _ready() ? _confirm : null,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (header != null)
            header
          else ...<Widget>[
            AuthIconTile(icon: widget.icon),
            const SizedBox(height: VelvetSpacing.lg),
            Text(
              widget.headline ?? l10n.phoneCodeHeadline,
              style: VelvetText.heading(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
          ],
          Text.rich(
            TextSpan(
              style: VelvetText.body(),
              children: <InlineSpan>[
                TextSpan(
                  text: target == null
                      ? widget.description
                      : '${widget.description}\n',
                ),
                if (target != null)
                  TextSpan(text: target, style: VelvetText.bodyStrong()),
              ],
            ),
            textAlign: header == null ? TextAlign.center : TextAlign.start,
          ),
          const SizedBox(height: VelvetSpacing.xl),
          OtpCodeField(
            controller: _codeController,
            focusNode: _codeFocus,
            length: _kOtpLength,
            fieldKey: const ValueKey<String>('phone_code_input'),
            semanticsLabel: l10n.resetOtpSemantics,
          ),
          if (widget.requireCurrentPassword) ...<Widget>[
            const SizedBox(height: VelvetSpacing.lg),
            NeumorphicTextField(
              key: const ValueKey<String>('phone_code_current_password'),
              label: l10n.phoneCodeCurrentPasswordLabel,
              controller: _passwordController,
              hintText: '••••••••',
              obscureToggle: true,
              maxLength: 128,
              enabled: !widget.locked,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              autofillHints: const <String>[AutofillHints.password],
              helperText: widget.passwordError == null
                  ? l10n.phoneCodeCurrentPasswordHelper
                  : null,
              errorText: widget.passwordError,
            ),
          ],
          const SizedBox(height: VelvetSpacing.xl),
          OtpResendRow(
            onResend: widget.onResend,
            // The code was sent by the PREVIOUS step's action — start the
            // cooldown at once so an eager tap does not race the server.
            initialCooldown: kPhoneCodeResendCooldownSeconds,
            assumedCooldownSeconds: kPhoneCodeResendCooldownSeconds,
            resendKey: const ValueKey<String>('phone_code_resend'),
            promptText: l10n.resetOtpResendPrompt,
            resendLabel: l10n.resetOtpResendBtn,
            resendTimerLabel: (int seconds) =>
                l10n.resetOtpResendTimer('$seconds с'),
            resendUnavailableLabel: l10n.resetOtpResendUnavailable,
          ),
          if (banner != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            AuthBanner(
              key: const ValueKey<String>('phone_code_error'),
              icon: widget.locked
                  ? Icons.lock_clock_outlined
                  : Icons.error_outline_rounded,
              color: BrandColors.error,
              message: banner,
            ),
          ],
        ],
      ),
    );
  }
}
