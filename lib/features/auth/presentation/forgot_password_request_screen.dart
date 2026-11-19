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
// M517 (AUTH-D18) — ONE «Телефон або email» identifier field, like login
// (preview docs/signup-designs/PhoneFirstAuth/lib/screens/
// forgot_password_screen.dart): «@» = email rules, anything else = the
// Ukrainian-mobile rule; the normalised identifier goes to
// `POST /auth/forgot-password` as `identifier`. The next screen never names
// the channel. No email hint (removed at design review 2026-11-18).
//
// Widget keys (ValueKey<String>):
//   'forgot_identifier'    — phone-or-email NeumorphicTextField
//   'forgot_submit'        — send CTA
//   'auth_scaffold_back'   — top-left back button (AuthScaffold)

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/network/app_check_prefetch.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/identifier_classifier.dart';
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
  final TextEditingController _identifierController = TextEditingController();

  /// True while a forgot-password request is in flight.
  bool _submitting = false;

  /// Inline error shown under the email field when a genuine transport / server
  /// error occurs (NOT shown for the generic anti-enumeration success).
  String? _inlineError;

  /// Phone-first hardening P2 — an App Check token is prefetched at most once
  /// per screen, and only once the input is a Ukrainian mobile number (an
  /// email sends no SMS and needs none).
  bool _prefetched = false;

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
    _identifierController.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitting) return;

    final l10n = AppLocalizations.of(context);
    final identifierError = validateIdentifier(
      _identifierController.text,
      l10n,
    );
    if (identifierError != null) {
      setState(() => _inlineError = identifierError);
      return;
    }

    final identifier = normalizeIdentifier(_identifierController.text);
    setState(() {
      _submitting = true;
      _inlineError = null;
    });

    try {
      await ref.read(authProvider.notifier).requestPasswordReset(identifier);
      if (!mounted) return;
      if (kDebugMode) {
        log(
          'Forgot-password: OTP dispatched, navigating to verification',
          name: 'auth.reset',
          level: 800,
        );
      }
      await context.push(RouteNames.resetOtpVerification, extra: identifier);
      // Reset the in-flight flag on return (e.g. the user swipes back to
      // this screen) so a second submit is not silently disabled.
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      if (!mounted) return;
      final l10n2 = AppLocalizations.of(context);
      // Every failure renders LOCALIZED copy — including ValidationFailure.
      //
      // This screen used to prefer the backend's per-field `errors.email`
      // string, on the reasoning that a single-field form may echo the
      // offending field verbatim. In practice that string is Spring's own
      // English ("Email must be a valid address") and it reached Ukrainian
      // users untranslated. Nor is it reachable in any useful case:
      // `validateEmail` (`shared/validators/email_validator.dart`) is
      // strictly tighter than Spring's `@Email`, so anything the backend
      // would reject was already rejected inline above and never posted.
      // `ValidationFailure.userMessage` gives the localized errValidation
      // copy, which is what the remaining (contract-drift) case deserves.
      final String message = e is Failure
          ? e.userMessage(context)
          : l10n2.errUnknown;
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
        label: l10n.registerSendCode,
        loading: _submitting,
        onPressed: (_submitting || _identifierController.text.trim().isEmpty)
            ? null
            : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const VelvetHeader(),
          Text(l10n.forgotPasswordHeadline, style: VelvetText.heading()),
          const SizedBox(height: VelvetSpacing.sm),
          Text(l10n.forgotPasswordIdentifierSubText, style: VelvetText.body()),
          const SizedBox(height: VelvetSpacing.xl),
          NeumorphicTextField(
            key: const ValueKey<String>('forgot_identifier'),
            label: l10n.loginIdentifierLabel,
            controller: _identifierController,
            hintText: l10n.loginIdentifierHint,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            maxLength: 255,
            prefixIcon: const Icon(Icons.person_outline_rounded),
            autofillHints: const <String>[
              AutofillHints.username,
              AutofillHints.email,
            ],
            errorText: _inlineError,
            onChanged: (String value) {
              if (!_prefetched &&
                  !isEmailIdentifier(value) &&
                  normalizeUaMobile(value) != null) {
                _prefetched = true;
                ref.read(appCheckTokenPrefetcherProvider).prefetch();
              }
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
