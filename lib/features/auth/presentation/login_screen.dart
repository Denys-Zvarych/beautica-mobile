// Phase 2.5 — Login screen — VelvetTouch neumorphic redesign.
//
// Replaces the old glassmorphism design (dark espresso bg, BackdropFilter glass
// cards, gradient CTA) with the VelvetTouch light-mode neumorphic system:
//   - AuthScaffold from presentation/widgets/ (base #E6DDD0, no blur).
//   - VelvetHeader (logo pillow + wordmark).
//   - NeumorphicTextField for email and password.
//   - NeumorphicButton for the primary CTA.
//   - AuthBanner for inline EMAIL_NOT_VERIFIED feedback.
//   - No Form wrapper — validation is inline via errorText params.
//   - No BackdropFilter, no glassmorphism, no AuthGradientBackground.
//
// Business logic and navigation are unchanged:
//   1. Validate fields locally; show errorText on each NeumorphicTextField.
//   2. Call authProvider.notifier.login(email, password).
//   3. On success → context.go(RouteNames.home).
//   4. On EMAIL_NOT_VERIFIED → show inline AuthBanner; banner action navigates
//      to /verification.
//   5. On any other error → VelvetSnack (error variant) with localised message.
//
// ScreenProtector is kept for security (mobile-security MS-1).
// All user-facing strings go through AppLocalizations.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/role_home.dart';
import '../../../routing/route_names.dart';
import '../../../shared/feedback/show_velvet_snack.dart';
import '../../../shared/validators/email_validator.dart';
import '../../../shared/validators/password_validator.dart';
import 'auth_notifier.dart';
import 'auth_selectors.dart';
import 'widgets/auth_scaffold.dart';

// ---------------------------------------------------------------------------
// LoginScreen
// ---------------------------------------------------------------------------

/// Login screen — VelvetTouch neumorphic design.
///
/// Submits to [AuthNotifier.login]. On [AuthSession.authenticated] navigates
/// to [RouteNames.home]. On EMAIL_NOT_VERIFIED shows an inline [AuthBanner]
/// instead of a snack. On all other errors surfaces [Failure.userMessage]
/// via [showErrorSnack].
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ---------------------------------------------------------------------------
  // Controllers & field-level error state
  // ---------------------------------------------------------------------------

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _emailError;
  String? _passwordError;

  bool _showUnverified = false;
  String? _unverifiedEmail;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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
    _passwordController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Submit logic
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);

    // Inline validation — sets errorText on each NeumorphicTextField.
    final emailErr = validateEmail(_emailController.text, l10n);
    final passwordErr = validatePassword(_passwordController.text, l10n);
    if (emailErr != null || passwordErr != null) {
      setState(() {
        _emailError = emailErr;
        _passwordError = passwordErr;
      });
      return;
    }

    // Clear previous errors and unverified banner before a new attempt.
    setState(() {
      _emailError = null;
      _passwordError = null;
      if (_showUnverified) _showUnverified = false;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    await ref.read(authProvider.notifier).login(email, password);

    if (!mounted) return;

    final authState = ref.read(authProvider);
    authState.when(
      data: (_) {
        if (kDebugMode) {
          log(
            'Login screen: navigating to home',
            name: 'auth.login',
            level: 800,
          );
        }
        // Signal the OS password manager to save the credential.
        TextInput.finishAutofillContext();
        final role = ref.read(currentUserProvider)?.role;
        // Phase 13.1 — resolve the landing path through the shared
        // [roleHomePath] helper, the single source of truth shared with the
        // authenticated-on-auth-route gate in auth_redirect.dart. CLIENT lands
        // on the 5-tab client shell at /home. A null role (no current user)
        // falls back to the home shell.
        final destination = role == null ? RouteNames.home : roleHomePath(role);
        context.go(destination);
      },
      loading: () {
        // Still loading — shouldn't happen right after await; guard only.
      },
      error: (e, _) {
        // EMAIL_NOT_VERIFIED: show inline banner instead of SnackBar.
        // MEDIUM-2 (mobile-security 2026-05-24): use the typed `emailNotVerified`
        // field set by ErrorMapperInterceptor — never probe `cause.toString()` for
        // the sub-code because that couples UI to the internal DioException shape.
        if (e is UnauthorizedFailure && e.emailNotVerified) {
          setState(() {
            _showUnverified = true;
            _unverifiedEmail = email;
          });
          return;
        }
        final message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
        showErrorSnack(context, message);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return AuthScaffold(
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Logo pillow + wordmark — vertically aligned with wizard icon tiles.
          // No top offset (VelvetHeader.topSpacing removed); SizedBox.lg matches
          // the gap used by role_selection, step_1, step_2, step_3, verification.
          const Center(child: VelvetLogo(compact: true)),
          const SizedBox(height: VelvetSpacing.lg),

          // ── Heading
          Text(
            l10n.loginHeadline,
            style: VelvetText.heading(),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: VelvetSpacing.sm),

          // ── Sub-text
          Text(
            l10n.loginSubText,
            style: VelvetText.feedback(BrandColors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: VelvetSpacing.xl),

          // ── EMAIL_NOT_VERIFIED inline banner
          if (_showUnverified) ...<Widget>[
            AuthBanner(
              icon: Icons.mark_email_unread_outlined,
              color: BrandColors.accent,
              message: l10n.loginUnverifiedMessage,
              actionLabel: l10n.loginUnverifiedAction,
              onAction: () => context.push(
                RouteNames.verification,
                extra: _unverifiedEmail ?? _emailController.text.trim(),
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
          ],

          // ── Credential fields — wrapped in AutofillGroup so the OS password
          //    manager can correctly associate email + password as a pair and
          //    offer to save/fill the credential on submit (MASVS-PLATFORM).
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ── Email field
                NeumorphicTextField(
                  key: const ValueKey<String>('login_email'),
                  label: l10n.loginEmailLabel,
                  controller: _emailController,
                  hintText: l10n.loginEmailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  autofillHints: const <String>[
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  errorText: _emailError,
                  enabled: !isLoading,
                  onChanged: (_) {
                    if (_emailError != null) setState(() => _emailError = null);
                  },
                ),

                const SizedBox(height: VelvetSpacing.md),

                // ── Password field
                NeumorphicTextField(
                  key: const ValueKey<String>('login_password'),
                  label: l10n.loginPasswordLabel,
                  controller: _passwordController,
                  hintText: '••••••••',
                  obscureToggle: true,
                  maxLength: 128,
                  textInputAction: TextInputAction.done,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  autofillHints: const <String>[AutofillHints.password],
                  errorText: _passwordError,
                  enabled: !isLoading,
                  onChanged: (_) {
                    if (_passwordError != null) {
                      setState(() => _passwordError = null);
                    }
                  },
                  onSubmitted: isLoading ? null : (_) => _submit(),
                ),
              ],
            ),
          ),

          const SizedBox(height: VelvetSpacing.sm),

          // ── Forgot password — right-aligned link
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              key: const ValueKey<String>('login_forgot'),
              onTap: isLoading
                  ? null
                  : () => context.push(RouteNames.forgotPassword),
              child: Padding(
                padding: const EdgeInsets.all(VelvetSpacing.xs),
                child: Text(l10n.loginForgotPassword, style: VelvetText.link()),
              ),
            ),
          ),

          const SizedBox(height: VelvetSpacing.lg),

          // ── Primary CTA
          NeumorphicButton(
            key: const ValueKey<String>('login_submit'),
            label: l10n.loginSubmit,
            loading: isLoading,
            onPressed: isLoading ? null : _submit,
          ),

          const SizedBox(height: VelvetSpacing.lg),

          // ── Sign-up link row
          // Wrapped in Wrap so the two text spans reflow onto a second line at
          // narrow viewports (320 dp) with large text scale (1.3×) instead of
          // overflowing the Row. At normal sizes (360 dp / 1.0×) they always
          // fit on one line and Wrap renders identically to a Row.
          Wrap(
            alignment: WrapAlignment.center,
            children: <Widget>[
              Text(l10n.loginNoAccount, style: VelvetText.body()),
              GestureDetector(
                key: const ValueKey<String>('login_signup'),
                onTap: isLoading
                    ? null
                    : () => context.push(RouteNames.registerRole),
                child: Padding(
                  padding: const EdgeInsets.only(left: VelvetSpacing.xs),
                  child: Text(
                    l10n.loginCreateAccount,
                    style: VelvetText.link(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
