// Beautica OTP password-reset task (Phase B3) — generalized OTP verification
// screen serving BOTH the forgot-password flow (unauthenticated) and the
// settings change-password flow (authenticated).
//
// VISUAL TREATMENT: transcribed verbatim from `verification_screen.dart`'s
// existing VelvetTouch OTP entry (same layout, spacing, copy tone) via the
// shared `OtpCodeField` / `OtpResendRow` widgets extracted in Phase B1. This
// is a reuse, not a redesign — no new visual design was authored for this
// screen (frontend-design was intentionally NOT invoked for this task).
//
// The two entry points differ only in which repository calls back
// [onRequestOtp] / [onVerify] — see `app_router.dart`'s two route
// registrations: `RouteNames.resetOtpVerification` (forgot-password, extra =
// the submitted email) and `RouteNames.changePassword` (settings, no extra —
// the caller's identity comes from the authenticated session).
//
// Widget keys (ValueKey<String>):
//   'reset_otp_code_input' — hidden TextField (single entry for all 6 digits)
//   'reset_otp_submit'     — NeumorphicButton CTA
//   'reset_otp_resend'     — GestureDetector resend link
//   'auth_scaffold_back'   — top-left back button (AuthScaffold overlay)

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/util/mask_email.dart';
import '../domain/reset_password_args.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/otp_code_field.dart';
import 'widgets/otp_resend_row.dart';

const _kOtpLength = 6;

/// Generalized password-reset OTP screen — Beautica OTP task Phase B3.
///
/// Reused by two entry points via constructor closures:
///   - Forgot-password (unauthenticated): [onRequestOtp] calls
///     `AuthNotifier.requestPasswordReset(email)`; [onVerify] calls
///     `AuthNotifier.verifyPasswordResetOtp(email: email, code: code)`.
///   - Settings change-password (authenticated): [onRequestOtp] calls
///     `AuthNotifier.requestChangePasswordOtp()`; [onVerify] calls the same
///     `verifyPasswordResetOtp` with the caller's own email (display-only —
///     the backend resolves the authoritative identity from the JWT).
class ResetOtpVerificationScreen extends ConsumerStatefulWidget {
  const ResetOtpVerificationScreen({
    super.key,
    required this.onRequestOtp,
    required this.onVerify,
    required this.displayEmail,
    required this.fromChangePassword,
  });

  /// Requests (or re-sends) the OTP. Called on mount is NOT implied — the
  /// backend already sent the first code before this screen was reached
  /// (forgot-password's `POST /auth/forgot-password` / the settings row's
  /// `POST /users/me/change-password/request-otp`); this is invoked again
  /// only when the user taps "Надіслати знову".
  final Future<void> Function() onRequestOtp;

  /// Verifies [code] and resolves with the single-use reset ticket to carry
  /// forward to `ResetPasswordScreen`.
  final Future<String> Function(String code) onVerify;

  /// Email shown (masked) on screen. Display-only for the change-password
  /// entry point — the backend never reads it for that call.
  final String displayEmail;

  /// `true` when reached from the settings change-password row. Forwarded to
  /// [ResetPasswordArgs] so `ResetPasswordScreen` knows whether to run its
  /// normal success state or the forced-logout flow.
  final bool fromChangePassword;

  @override
  ConsumerState<ResetOtpVerificationScreen> createState() =>
      _ResetOtpVerificationScreenState();
}

class _ResetOtpVerificationScreenState
    extends ConsumerState<ResetOtpVerificationScreen> {
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  final GlobalKey<OtpResendRowState> _resendRowKey =
      GlobalKey<OtpResendRowState>();

  bool _submitting = false;
  String? _inlineError;

  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws. Hold the keepAlive manager instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot guard (single app-wide owner;
    // the manager is internally !kDebugMode-guarded) — mirrors
    // VerificationScreen (this screen also collects an OTP + moves a reset
    // ticket, both PII-adjacent).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  bool get _isOtpComplete => _codeController.text.length == _kOtpLength;

  Future<void> _submit() async {
    if (!_isOtpComplete || _submitting) return;
    final l10n = AppLocalizations.of(context);

    setState(() {
      _submitting = true;
      _inlineError = null;
    });

    try {
      final ticket = await widget.onVerify(_codeController.text);
      if (!mounted) return;
      if (kDebugMode) {
        log(
          'ResetOtpVerificationScreen: verified, navigating to reset-password',
          name: 'auth.reset',
          level: 800,
        );
      }
      context.go(
        RouteNames.resetPassword,
        extra: ResetPasswordArgs(
          resetTicket: ticket,
          fromChangePassword: widget.fromChangePassword,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _inlineError = e is Failure ? e.userMessage(context) : l10n.errUnknown;
      });
    }
  }

  /// Callback passed to [OtpResendRow]. Returns the cooldown seconds the row
  /// should display, or null to leave the row's cooldown unchanged (generic
  /// error — allow immediate retry).
  Future<int?> _resend() async {
    final l10n = AppLocalizations.of(context);

    try {
      await widget.onRequestOtp();
      if (!mounted) return kDefaultOtpResendCooldownSeconds;

      _codeController.clear();
      setState(() => _inlineError = null);

      if (kDebugMode) {
        log(
          'ResetOtpVerificationScreen: resend dispatched',
          name: 'auth.reset',
          level: 800,
        );
      }
      return kDefaultOtpResendCooldownSeconds;
    } on ResendThrottledFailure catch (throttle) {
      if (!mounted) return throttle.retryAfterSeconds;
      setState(() => _inlineError = throttle.userMessage(context));
      return throttle.retryAfterSeconds;
    } catch (e) {
      if (!mounted) return null;
      setState(
        () => _inlineError = e is Failure
            ? e.userMessage(context)
            : l10n.errUnknown,
      );
      return null; // No cooldown on generic error — allow immediate retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maskedEmail = maskEmail(widget.displayEmail);

    return AuthScaffold(
      showBack: true,
      bottomBar: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _codeController,
        builder:
            (BuildContext context, TextEditingValue value, Widget? child) =>
                NeumorphicButton(
                  key: const ValueKey<String>('reset_otp_submit'),
                  label: l10n.resetOtpConfirmBtn,
                  loading: _submitting,
                  onPressed: (value.text.length == _kOtpLength && !_submitting)
                      ? _submit
                      : null,
                ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              height: 72,
              width: 72,
              decoration: const BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.all(
                  Radius.circular(VelvetRadii.logoTile),
                ),
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                color: BrandColors.accent,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          Text(
            l10n.resetOtpHeadline,
            style: VelvetText.heading(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Text.rich(
            TextSpan(
              style: VelvetText.body(),
              children: <InlineSpan>[
                TextSpan(text: '${l10n.resetOtpCardDesc}\n'),
                TextSpan(text: maskedEmail, style: VelvetText.bodyStrong()),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.xl),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _codeController,
            builder: (context, value, child) => OtpCodeField(
              controller: _codeController,
              focusNode: _codeFocus,
              length: _kOtpLength,
              fieldKey: const ValueKey<String>('reset_otp_code_input'),
              semanticsLabel: l10n.resetOtpSemantics,
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),
          OtpResendRow(
            key: _resendRowKey,
            onResend: _resend,
            // The OTP was already sent by the PREVIOUS screen's action
            // (forgot-password submit / settings row tap) before this screen
            // was reached — start the same cooldown window immediately so an
            // eager resend tap does not race the server's own cooldown.
            initialCooldown: kDefaultOtpResendCooldownSeconds,
            resendKey: const ValueKey<String>('reset_otp_resend'),
            promptText: l10n.resetOtpResendPrompt,
            resendLabel: l10n.resetOtpResendBtn,
            resendTimerLabel: (int seconds) =>
                l10n.resetOtpResendTimer('$seconds с'),
          ),
          if (_inlineError != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            AuthBanner(
              icon: Icons.error_outline_rounded,
              color: BrandColors.error,
              message: _inlineError!,
            ),
          ],
        ],
      ),
    );
  }
}
