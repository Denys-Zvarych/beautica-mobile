// Phase 2.16 — Registration wizard Step 1 (Account / credentials).
// VelvetTouch redesign.
//
// This screen owns the credential form only — email + password + confirm-
// password. The shared chrome (brand header, role chip, headline, two-dot
// progress) is drawn by [RegisterFlowShell].
//
// Lifecycle:
//   1. User picks a role on the role-selection screen → registerDraftProvider
//      is initialised with that role.
//   2. /register loads RegisterStep1Screen inside RegisterFlowShell.
//   3. User fills the three fields and taps "Продовжити".
//   4. On valid submit the values are merged into the draft and the wizard
//      navigates to /register/step-2 (Phase 2.17). Step 1 does NOT call the
//      real `AuthNotifier.register` — the registration POST happens at the
//      end of Step 3 (Phase 2.19) once the full draft is assembled.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/email_validator.dart';
import '../../../shared/validators/password_validator.dart';
import '../state/register_draft_notifier.dart';
import 'register_flow_shell.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/password_checklist.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Step 1 of the multi-step registration wizard — credentials.
class RegisterStep1Screen extends ConsumerStatefulWidget {
  const RegisterStep1Screen({super.key});

  @override
  ConsumerState<RegisterStep1Screen> createState() =>
      _RegisterStep1ScreenState();
}

class _RegisterStep1ScreenState extends ConsumerState<RegisterStep1Screen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _passwordValue = '';
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  late final List<PasswordRule> _rules = passwordRules();

  @override
  void initState() {
    super.initState();
    // Pre-fill from the draft (e.g. when the user returns to Step 1 via the
    // back link from Step 2).
    final draft = ref.read(registerDraftProvider);
    if (draft != null) {
      _emailController.text = draft.email;
      _passwordController.text = draft.password;
      _confirmPasswordController.text = draft.confirmPassword;
      _passwordValue = draft.password;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  void _submit() {
    final l10n = AppLocalizations.of(context);

    final emailErr = validateEmail(_emailController.text.trim(), l10n);

    // Validate password via the shared strict validator (validateNewPassword)
    // so the submit gate is always the same function as the backend-aligned
    // policy — min 8, max 128, ≥1 digit, ≥1 uppercase. The live checklist rows
    // still use _rules for real-time UX feedback; this call is the hard gate.
    final pwErr = validateNewPassword(_passwordController.text, l10n);

    final confirmErr =
        _confirmPasswordController.text != _passwordController.text
        ? l10n.errPasswordsMismatch
        : (_confirmPasswordController.text.isEmpty
              ? l10n.errPasswordRequired
              : null);

    if (emailErr != null || pwErr != null || confirmErr != null) {
      setState(() {
        _emailError = emailErr;
        _passwordError = pwErr;
        _confirmError = confirmErr;
      });
      return;
    }

    ref
        .read(registerDraftProvider.notifier)
        .updateStep1(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          confirmPassword: _confirmPasswordController.text,
        );

    if (kDebugMode) {
      log(
        'Step 1 submitted — advancing to /register/step-2',
        name: 'auth.register.step1',
        level: 800,
      );
    }

    context.go(RouteNames.registerStep2);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AuthScaffold(
      showBack: true,
      onBack: () => context.go(RouteNames.registerRole),
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('step1_submit'),
        label: l10n.registerContinue,
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Brand header + wizard chrome ───────────────────────────────
          const VelvetHeader(),
          WizardStepChrome(step: 1, headline: l10n.registerHeadline),

          // ── Email ──────────────────────────────────────────────────────
          NeumorphicTextField(
            key: const ValueKey<String>('step1_email'),
            label: l10n.loginEmailLabel,
            controller: _emailController,
            hintText: 'ви@beautica.ua',
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            maxLength: 255,
            prefixIcon: const Icon(Icons.alternate_email_rounded),
            autofillHints: const <String>[AutofillHints.email],
            errorText: _emailError,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
          ),
          const SizedBox(height: VelvetSpacing.sm),

          // ── Password ───────────────────────────────────────────────────
          NeumorphicTextField(
            key: const ValueKey<String>('step1_password'),
            label: l10n.loginPasswordLabel,
            controller: _passwordController,
            hintText: '••••••••',
            obscureToggle: true,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            maxLength: 128,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            autofillHints: const <String>[AutofillHints.newPassword],
            errorText: _passwordError,
            onChanged: (v) => setState(() {
              _passwordValue = v;
              if (_passwordError != null) _passwordError = null;
            }),
          ),
          const SizedBox(height: VelvetSpacing.xs),

          // ── Password checklist ─────────────────────────────────────────
          PasswordChecklist(value: _passwordValue, rules: _rules),
          const SizedBox(height: VelvetSpacing.sm),

          // ── Confirm password ───────────────────────────────────────────
          NeumorphicTextField(
            key: const ValueKey<String>('step1_confirm'),
            label: l10n.registerConfirmPasswordLabel,
            controller: _confirmPasswordController,
            hintText: '••••••••',
            obscureToggle: true,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            maxLength: 128,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            autofillHints: const <String>[AutofillHints.newPassword],
            errorText: _confirmError,
            onChanged: (_) {
              if (_confirmError != null) setState(() => _confirmError = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: VelvetSpacing.md),

          // ── Terms line (full rich text) ────────────────────────────────
          Text.rich(
            TextSpan(
              style: VelvetText.feedback(BrandColors.muted),
              children: <InlineSpan>[
                TextSpan(text: l10n.registerTermsPrefix),
                const TextSpan(text: ' '),
                TextSpan(
                  text: l10n.registerTermsTerms,
                  style: VelvetText.link().copyWith(fontSize: 13),
                ),
                TextSpan(text: l10n.registerTermsConjunction),
                TextSpan(
                  text: l10n.registerTermsPrivacy,
                  style: VelvetText.link().copyWith(fontSize: 13),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.sm),

          // ── ← Back to role select ──────────────────────────────────────
          Center(
            child: GestureDetector(
              key: const ValueKey<String>('step1_back'),
              onTap: () {
                // Going back preserves the draft (incl. role) so role-selection
                // screen re-highlights the chosen role. Do NOT reset() here.
                context.go(RouteNames.registerRole);
              },
              child: Padding(
                padding: const EdgeInsets.all(VelvetSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 14,
                      color: BrandColors.accentDeep,
                    ),
                    const SizedBox(width: 4),
                    Text(l10n.registerBackToRole, style: VelvetText.link()),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.xs),

          // ── "Вже є акаунт? Увійти" ─────────────────────────────────────
          Center(
            child: GestureDetector(
              key: const ValueKey<String>('step1_login_link'),
              onTap: () {
                // Navigate to /login BEFORE nulling the draft. If reset() ran
                // first, the still-mounted RegisterFlowShell's null-role guard
                // would read role == null in didChangeDependencies, schedule a
                // context.go('/register/role') post-frame callback, and that
                // callback would win the race against this go() call —
                // landing the user on role-selection instead of login.
                context.go(RouteNames.login);
                // Security (Phase 2.16 HIGH-1) — wipe the in-progress draft
                // (incl. the plaintext password) when abandoning the wizard.
                ref.read(registerDraftProvider.notifier).reset();
              },
              child: Padding(
                padding: const EdgeInsets.all(VelvetSpacing.xs),
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: l10n.registerHaveAccount,
                        style: VelvetText.body(),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: l10n.registerSignIn,
                        style: VelvetText.link(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.sm),
        ],
      ),
    );
  }
}
