// Phase 2.13 — Forgot Password (request) screen — VelvetTouch redesign.
//
// SOURCE OF TRUTH:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/forgot_password_screen.dart
//
// VelvetTouch neumorphic light-mode replaces the retired glassmorphism layer.
// No BackdropFilter, no dart:ui, no AuthGradientBackground, no google_fonts
// inline, no AppSpacing, no shared/widgets/auth_scaffold.dart import —
// the VelvetTouch AuthScaffold lives in the features/auth/presentation/widgets/
// directory.
//
// Business logic preserved from the old implementation:
//   - ConsumerStatefulWidget + ConsumerState
//   - ScreenProtector lifecycle (has an email field)
//   - AuthNotifier.requestPasswordReset(email) call
//   - _linkSent toggle (form → confirmation on any successful non-throwing call)
//   - _inlineError for genuine transport / server errors
//   - _submit() + _backToLogin() navigation logic
//   - AppLocalizations for all user-visible strings
//   - RouteNames.login navigation via context.go()
//   - validateEmail() inline validation (no Form + GlobalKey)
//
// Anti-enumeration: confirmation copy is identical whether or not the account
// exists. The backend always returns a generic 200; the screen shows
// confirmation on ANY non-throwing call.
//
// Widget keys (ValueKey<String>):
//   'forgot_email'         — email NeumorphicTextField
//   'forgot_submit'        — send CTA (form state)
//   'forgot_preview_reset' — "У мене є посилання" CTA (sent state)
//   'auth_scaffold_back'   — top-left back button (AuthScaffold, all states)

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/email_validator.dart';
import 'auth_notifier.dart';
import 'widgets/auth_scaffold.dart';

/// Forgot-password request screen — Phase 2.13 VelvetTouch.
///
/// Two states on one screen:
///   A — email entry + "Надіслати посилання" CTA.
///   B — generic anti-enumeration confirmation (medallion, spam hint,
///       "У мене є посилання" preview CTA, back-to-login link).
class ForgotPasswordRequestScreen extends ConsumerStatefulWidget {
  const ForgotPasswordRequestScreen({super.key});

  @override
  ConsumerState<ForgotPasswordRequestScreen> createState() =>
      _ForgotPasswordRequestScreenState();
}

class _ForgotPasswordRequestScreenState
    extends ConsumerState<ForgotPasswordRequestScreen> {
  final TextEditingController _emailController = TextEditingController();

  /// True once a request has succeeded → swap to the confirmation state.
  bool _linkSent = false;

  /// True while a forgot-password request is in flight.
  bool _submitting = false;

  /// Inline error shown under the email field when a genuine transport / server
  /// error occurs (NOT shown for the generic anti-enumeration success).
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    _emailController.dispose();
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitting) return;

    final l10n = AppLocalizations.of(context);
    final emailError = validateEmail(_emailController.text.trim(), l10n);
    if (emailError != null) {
      setState(() => _inlineError = emailError);
      return;
    }

    final email = _emailController.text.trim();
    setState(() {
      _submitting = true;
      _inlineError = null;
    });

    try {
      await ref.read(authProvider.notifier).requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _linkSent = true;
      });
      if (kDebugMode) {
        log(
          'Forgot-password: showing generic confirmation',
          name: 'auth.reset',
          level: 800,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final l10n2 = AppLocalizations.of(context);
      final String message;
      if (e is ValidationFailure) {
        // Prefer the per-field email error, then the top-level server message,
        // over the generic errValidation copy (which userMessage returns).
        final emailErr = e.fieldErrors['email'];
        final serverMessage = e.serverMessage?.trim();
        if (emailErr != null && emailErr.isNotEmpty) {
          message = emailErr;
        } else if (serverMessage != null && serverMessage.isNotEmpty) {
          message = serverMessage;
        } else {
          message = l10n2.errValidation;
        }
      } else {
        message = e is Failure ? e.userMessage(context) : l10n2.errUnknown;
      }
      setState(() {
        _submitting = false;
        _inlineError = message;
      });
    }
  }

  void _backToLogin() => context.go(RouteNames.login);

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AuthScaffold(
      showBack: true,
      onBack: _backToLogin,
      bottomBar: _linkSent
          ? null
          : NeumorphicButton(
              key: const ValueKey<String>('forgot_submit'),
              label: l10n.forgotPasswordSubmit,
              loading: _submitting,
              onPressed: (_submitting || _emailController.text.trim().isEmpty)
                  ? null
                  : _submit,
            ),
      child: _linkSent ? _success(context, l10n) : _form(l10n),
    );
  }

  // ── States ──────────────────────────────────────────────────────────────

  Widget _form(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const VelvetHeader(),
        Text(l10n.forgotPasswordHeadline, style: VelvetText.heading()),
        const SizedBox(height: VelvetSpacing.sm),
        Text(l10n.forgotPasswordSubText, style: VelvetText.body()),
        const SizedBox(height: VelvetSpacing.xl),
        NeumorphicTextField(
          key: const ValueKey<String>('forgot_email'),
          label: l10n.forgotPasswordEmailLabel,
          controller: _emailController,
          hintText: l10n.forgotPasswordEmailPlaceholder,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          maxLength: 255,
          prefixIcon: const Icon(Icons.alternate_email_rounded),
          autofillHints: const <String>[AutofillHints.email],
          errorText: _inlineError,
          onChanged: (_) {
            // Single setState coalesces the error clear + CTA enabled-state
            // rebuild into one markNeedsBuild per keystroke.
            setState(() {
              if (_inlineError != null) _inlineError = null;
            });
          },
          onSubmitted: _submitting ? null : (_) => _submit(),
          enabled: !_submitting,
        ),
      ],
    );
  }

  Widget _success(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const VelvetHeader(),
        Center(
          child: Container(
            height: 72,
            width: 72,
            decoration: const BoxDecoration(
              color: BrandColors.base,
              shape: BoxShape.circle,
              boxShadow: VelvetShadows.extrudedSmall,
            ),
            child: const Icon(
              Icons.send_rounded,
              color: BrandColors.success,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.lg),
        Text(
          l10n.forgotPasswordConfirmTitle,
          style: VelvetText.heading(),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VelvetSpacing.sm),
        Text(
          l10n.forgotPasswordConfirmDesc,
          style: VelvetText.body(),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VelvetSpacing.xl),
        NeumorphicButton(
          key: const ValueKey<String>('forgot_preview_reset'),
          label: l10n.forgotPasswordResendLink,
          onPressed: () => context.go(RouteNames.resetPassword),
        ),
      ],
    );
  }
}
