// Phase 2.13 — Reset Password (set new password) screen — VelvetTouch redesign.
//
// SOURCE OF TRUTH:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/reset_password_screen.dart
//
// VelvetTouch neumorphic light-mode replaces the retired glassmorphism layer.
// No BackdropFilter, no dart:ui, no AuthGradientBackground, no google_fonts
// inline, no AppSpacing, no PasswordCriteriaRow (retired glassmorphism widget).
//
// Business logic preserved from the old implementation:
//   - ConsumerStatefulWidget + ConsumerState
//   - final String token constructor param
//   - _ResetState enum (form, success, invalid)
//   - ScreenProtector lifecycle (has password fields)
//   - AuthNotifier.confirmPasswordReset(token, newPassword) call
//   - on ResetTokenInvalidFailure catch → _state = _ResetState.invalid
//   - Generic error catch → _inlineError (stays on form for retry)
//   - _passwordController.clear(); _confirmController.clear() on success
//   - _goToLogin() via context.go(RouteNames.login)
//   - _requestNewLink() via context.go(RouteNames.forgotPassword)
//   - validateNewPassword(v, l10n) on the password field
//   - Confirm-field mismatch guard
//
// Widget keys (ValueKey<String>):
//   'reset_password'    — new password NeumorphicTextField
//   'reset_confirm'     — confirm password NeumorphicTextField
//   'reset_submit'      — submit CTA (form state)
//   'reset_back_login'  — "Увійти" CTA (success state)
//   'reset_invalid_cta' — "Запросити нове посилання" CTA (invalid state)

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
import '../../../shared/validators/password_validator.dart';
import 'auth_notifier.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/password_checklist.dart';

// ---------------------------------------------------------------------------
// Local state machine for the screen.
// ---------------------------------------------------------------------------

enum _ResetState { form, success, invalid }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Reset-password screen — Phase 2.13 VelvetTouch.
///
/// [token] is the single-use reset token from the emailed deep link, parsed
/// from the `?token=` query parameter by the router. It is never displayed or
/// editable. A missing/empty token still renders the form; the first submit
/// then surfaces the backend's generic 400 as the invalid-link state.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  /// Single-use reset token from the emailed deep link.
  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  _ResetState _state = _ResetState.form;
  bool _submitting = false;
  String? _inlineError;

  /// Drives the live PasswordChecklist. Updated via onChanged so the checklist
  /// rebuilds per keystroke without rebuilding the full screen tree.
  String _passwordValue = '';

  /// Drives the confirm-field mismatch error. Updated via onChanged.
  String _confirmValue = '';

  /// Per-field inline error for the password field (validator result on submit).
  String? _passwordError;

  /// Password policy rules — initialised once in [didChangeDependencies] to
  /// allow l10n key lookup (AppLocalizations requires a BuildContext, which is
  /// unavailable at field-initialisation time).
  List<PasswordRule>? _rules;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rules ??= passwordRules(AppLocalizations.of(context));
  }

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
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ── Derived state ──────────────────────────────────────────────────────

  /// Returns a mismatch error string only once both fields have content AND
  /// they differ. Returns null when the confirm field is empty (do not nag
  /// before the user has typed anything in it) or when the passwords match.
  String? _getConfirmError(AppLocalizations l10n) {
    if (_confirmValue.isEmpty) return null;
    return _confirmValue == _passwordValue ? null : l10n.errPasswordsMismatch;
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitting) return;

    final l10n = AppLocalizations.of(context);

    // Validate the new password field first.
    final pwdErr = validateNewPassword(_passwordController.text, l10n);
    if (pwdErr != null) {
      setState(() => _passwordError = pwdErr);
      return;
    }

    // Client-side mismatch guard — backend only takes a single password field.
    if (_confirmValue != _passwordValue) return;

    setState(() {
      _submitting = true;
      _inlineError = null;
    });

    try {
      await ref
          .read(authProvider.notifier)
          .confirmPasswordReset(
            token: widget.token,
            newPassword: _passwordController.text,
          );
      if (!mounted) return;
      // No auto-login — show the success state; user taps "Увійти" to /login.
      // Clear password fields from memory now that they are no longer needed.
      _passwordController.clear();
      _confirmController.clear();
      setState(() {
        _submitting = false;
        _state = _ResetState.success;
      });
      if (kDebugMode) {
        log('Reset-password: success state', name: 'auth.reset', level: 800);
      }
    } on ResetTokenInvalidFailure {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _state = _ResetState.invalid;
      });
      if (kDebugMode) {
        log(
          'Reset-password: invalid-token state',
          name: 'auth.reset',
          level: 800,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final l10n2 = AppLocalizations.of(context);
      final message = e is Failure ? e.userMessage(context) : l10n2.errUnknown;
      setState(() {
        _submitting = false;
        _inlineError = message;
      });
    }
  }

  void _goToLogin() => context.go(RouteNames.login);

  void _requestNewLink() => context.go(RouteNames.forgotPassword);

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    switch (_state) {
      case _ResetState.form:
        return _buildForm(l10n);
      case _ResetState.success:
        return _buildSuccess(l10n);
      case _ResetState.invalid:
        return _buildInvalid(l10n);
    }
  }

  // ── Form state ──────────────────────────────────────────────────────────

  Widget _buildForm(AppLocalizations l10n) {
    return AuthScaffold(
      showBack: true,
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('reset_submit'),
        label: l10n.resetPasswordSubmit,
        loading: _submitting,
        onPressed: _submitting ? null : _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const VelvetHeader(),
          Text(l10n.resetPasswordHeadline, style: VelvetText.heading()),
          const SizedBox(height: VelvetSpacing.sm),
          Text(l10n.resetPasswordSubText, style: VelvetText.body()),
          const SizedBox(height: VelvetSpacing.xl),
          NeumorphicTextField(
            key: const ValueKey<String>('reset_password'),
            label: l10n.resetPasswordNewLabel,
            controller: _passwordController,
            obscureToggle: true,
            toggleKey: const Key('reset_password_toggle'),
            maxLength: 128,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            autofillHints: const <String>[AutofillHints.newPassword],
            errorText: _passwordError,
            enabled: !_submitting,
            onChanged: (String v) {
              setState(() {
                _passwordValue = v;
                if (_passwordError != null) _passwordError = null;
              });
            },
          ),
          const SizedBox(height: VelvetSpacing.sm),
          // _rules is guaranteed non-null after didChangeDependencies runs.
          PasswordChecklist(value: _passwordValue, rules: _rules!),
          const SizedBox(height: VelvetSpacing.lg),
          NeumorphicTextField(
            key: const ValueKey<String>('reset_confirm'),
            label: l10n.resetPasswordConfirmLabel,
            controller: _confirmController,
            obscureToggle: true,
            toggleKey: const Key('reset_confirm_toggle'),
            maxLength: 128,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(Icons.lock_reset_rounded),
            errorText: _getConfirmError(l10n),
            enabled: !_submitting,
            onChanged: (String v) => setState(() => _confirmValue = v),
            onSubmitted: _submitting ? null : (_) => _submit(),
          ),
          if (_inlineError != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _inlineError!,
                style: VelvetText.feedback(BrandColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Success state ────────────────────────────────────────────────────────

  Widget _buildSuccess(AppLocalizations l10n) {
    return AuthScaffold(
      showBack: false,
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('reset_back_login'),
        label: l10n.resetPasswordSuccessCta,
        onPressed: _goToLogin,
      ),
      child: Column(
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
                Icons.verified_rounded,
                color: BrandColors.success,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          Text(
            l10n.resetPasswordSuccessTitle,
            style: VelvetText.heading(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Text(
            l10n.resetPasswordSuccessDesc,
            style: VelvetText.body(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Invalid state ────────────────────────────────────────────────────────

  Widget _buildInvalid(AppLocalizations l10n) {
    return AuthScaffold(
      showBack: true,
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('reset_invalid_cta'),
        label: l10n.resetPasswordInvalidCta,
        onPressed: _requestNewLink,
      ),
      child: Column(
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
                Icons.error_outline,
                color: BrandColors.error,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          Text(
            l10n.resetPasswordInvalidTitle,
            style: VelvetText.heading(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Text(
            l10n.resetPasswordInvalidDesc,
            style: VelvetText.body(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
