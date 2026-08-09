// Phase 2.13 — Forgot Password (request) screen — VelvetTouch redesign.
// Beautica OTP task (Phase B3) — replaces the old email-link confirmation
// state with navigation to the OTP verification screen.
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
//   - _inlineError for genuine transport / server errors
//   - _submit() + _backToLogin() navigation logic
//   - AppLocalizations for all user-visible strings
//   - RouteNames.login navigation via context.go()
//   - validateEmail() inline validation (no Form + GlobalKey)
//
// Beautica OTP task change: this screen is now SINGLE-STATE (form only). A
// successful `POST /auth/forgot-password` no longer flips to an in-screen
// "check your email for a link" confirmation — it navigates straight to
// `ResetOtpVerificationScreen` (the same generic anti-enumeration guarantee
// still holds: the backend always returns a generic 200 regardless of
// whether the account exists, so navigation itself reveals nothing).
//
// Widget keys (ValueKey<String>):
//   'forgot_email'         — email NeumorphicTextField
//   'forgot_submit'        — send CTA
//   'auth_scaffold_back'   — top-left back button (AuthScaffold)

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/formatters/server_field_message.dart';
import '../../../shared/validators/email_validator.dart';
import 'auth_notifier.dart';
import 'widgets/auth_scaffold.dart';

/// Forgot-password request screen — Phase 2.13 VelvetTouch; Beautica OTP task
/// Phase B3.
///
/// Single state: email entry + "Надіслати код" CTA. On success, navigates to
/// [RouteNames.resetOtpVerification] carrying the submitted email (a bare
/// `String`) in `extra` — the anti-enumeration guarantee is preserved because
/// the backend's `POST /auth/forgot-password` always returns a generic 200
/// regardless of whether the account exists, so the navigation itself never
/// discloses anything.
class ForgotPasswordRequestScreen extends ConsumerStatefulWidget {
  const ForgotPasswordRequestScreen({super.key});

  @override
  ConsumerState<ForgotPasswordRequestScreen> createState() =>
      _ForgotPasswordRequestScreenState();
}

class _ForgotPasswordRequestScreenState
    extends ConsumerState<ForgotPasswordRequestScreen> {
  final TextEditingController _emailController = TextEditingController();

  /// True while a forgot-password request is in flight.
  bool _submitting = false;

  /// Inline error shown under the email field when a genuine transport / server
  /// error occurs (NOT shown for the generic anti-enumeration success).
  String? _inlineError;

  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws. Hold the keepAlive manager instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot guard (single app-wide owner;
    // the manager is internally !kDebugMode-guarded).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _emailController.dispose();
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
      if (kDebugMode) {
        log(
          'Forgot-password: OTP dispatched, navigating to verification',
          name: 'auth.reset',
          level: 800,
        );
      }
      await context.push(RouteNames.resetOtpVerification, extra: email);
      // Reset the in-flight flag on return (e.g. the user swipes back to
      // this screen) so a second submit is not silently disabled.
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      final l10n2 = AppLocalizations.of(context);
      final String message;
      if (e is ValidationFailure) {
        // Prefer the per-field email error — it renders directly on the
        // email input's own errorText below, so it is the one server string
        // this screen is allowed to show verbatim (single-field form, the
        // offending field IS the one on screen), GUARDED through
        // `serverFieldMessageOr` like every other per-field surface in the
        // codebase (service_form.dart, the suggestion dialogs) — an
        // oversized or control/bidi-laden backend value falls back instead
        // of rendering raw (mobile-security, 2026-08). When the backend
        // attributes nothing to `email` specifically (or the value fails the
        // guard), fall back to the localized errValidation copy — NOT the
        // top-level serverMessage, which can be untranslated/technical and
        // was previously shown raw here.
        message = serverFieldMessageOr(
          e.fieldErrors['email'],
          e.userMessage(context),
        );
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
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('forgot_submit'),
        label: l10n.forgotPasswordSubmit,
        loading: _submitting,
        onPressed: (_submitting || _emailController.text.trim().isEmpty)
            ? null
            : _submit,
      ),
      child: Column(
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
      ),
    );
  }
}
