// Phase 2.5 — Login screen (redesigned Modern Dark Cinema — Phase 3.x visual).
//
// ConsumerStatefulWidget: owns TextEditingControllers, FormKey, animation
// controller, and minor UI state (_obscurePassword, _buttonPressed).
// Network-side state lives in [authProvider].
//
// Layout: full-screen gradient (Midnight → deep navy), no AppBar, SafeArea
// wrapping a scrollable form centred in a max-width 400 column.
//
// Submit flow:
//   1. Validate form locally.
//   2. Call authProvider.notifier.login() — state transitions to AsyncLoading.
//   3. On AsyncData<Authenticated> → navigate to home.
//   4. On AsyncError → show floating SnackBar styled with BrandColors.cherry.
//
// Entrance animation: 5-item stagger (logo, title, email, password+forgot, CTA
// row) using FadeTransition + SlideTransition with Interval-based curves over
// 600 ms.
//
// All user-visible strings are fetched through AppLocalizations (UA primary).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/email_validator.dart';
import '../../../shared/validators/password_validator.dart';
import 'auth_gradient_background.dart';
import 'auth_notifier.dart';

/// Login screen for the Beautica app — Modern Dark Cinema design.
///
/// Presents email + password fields with a staggered entrance animation and
/// submits to [AuthNotifier.login]. Navigates to [RouteNames.home] on success;
/// surfaces [Failure.userMessage] in a floating [SnackBar] on error.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Form state
  // ---------------------------------------------------------------------------

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _buttonPressed = false;

  // ---------------------------------------------------------------------------
  // Entrance animation
  // ---------------------------------------------------------------------------

  late final AnimationController _entranceCtrl;

  // Cached per-item animations (4 staggered items: title, email,
  // password+forgot, CTA). Initialized in initState() after _entranceCtrl is
  // created so they are never recreated on build(). The logo (item 0 in the
  // Column) is unwrapped from stagger — Hero handles its own flight.
  late final List<Animation<double>> _opacities;
  late final List<Animation<Offset>> _slides;

  Widget _staggered(int index, Widget child) => FadeTransition(
    opacity: _opacities[index],
    child: SlideTransition(position: _slides[index], child: child),
  );

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Build cached animation objects once so build() never allocates new
    // Tween/CurvedAnimation instances. Indices 0..3 map to: title, email,
    // password+forgot, CTA row.
    _opacities = List.generate(
      4,
      (i) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceCtrl,
          curve: Interval(
            (i * 0.12).clamp(0.0, 1.0),
            (i * 0.12 + 0.5).clamp(0.0, 1.0),
            curve: Curves.easeOut,
          ),
        ),
      ),
    );
    _slides = List.generate(
      4,
      (i) =>
          Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
            CurvedAnimation(
              parent: _entranceCtrl,
              curve: Interval(
                (i * 0.12).clamp(0.0, 1.0),
                (i * 0.12 + 0.5).clamp(0.0, 1.0),
                curve: Curves.easeOut,
              ),
            ),
          ),
    );

    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOn();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _entranceCtrl.value = 1.0;
      } else {
        _entranceCtrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOff();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Submit logic
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

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
        context.go(RouteNames.home);
      },
      loading: () {
        // Still loading — guard only; shouldn't happen right after await.
      },
      error: (e, _) {
        final l10n = AppLocalizations.of(context);
        final message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
        _showErrorSnackBar(message);
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: BrandColors.cherry,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.sm),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Field decoration helper
  // ---------------------------------------------------------------------------

  InputDecoration _fieldDecor(
    String label, {
    String? errorText,
    Widget? suffixIcon,
  }) => InputDecoration(
    labelText: label,
    errorText: errorText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: BrandColors.darkSurface,
    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
    floatingLabelStyle: const TextStyle(color: BrandColors.bliss),
    errorStyle: const TextStyle(color: BrandColors.cherry),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.md),
      borderSide: BorderSide(
        color: Colors.white.withValues(alpha: 0.15),
        width: 1,
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.md),
      borderSide: BorderSide(
        color: Colors.white.withValues(alpha: 0.15),
        width: 1,
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.md),
      borderSide: const BorderSide(color: BrandColors.bliss, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.md),
      borderSide: const BorderSide(color: BrandColors.cherry),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.md),
      borderSide: const BorderSide(color: BrandColors.cherry, width: 1.5),
    ),
  );

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: BrandColors.midnight,
      body: Stack(
        children: [
          const AuthGradientBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xl,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Top spacer: pushes the logo upward relative to
                        // the form body so it appears higher on screen.
                        const SizedBox(height: AppSpacing.xl),

                        // ── Logo — no stagger wrapper; Hero handles its own
                        // flight transition. Wrapping with SlideTransition
                        // conflicts with the Hero overlay positioning.
                        Center(
                          child: Hero(
                            tag: 'beautica-logo',
                            child: SvgPicture.asset(
                              'assets/images/logo.svg',
                              width: 120,
                              semanticsLabel: 'Beautica',
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // ── Stagger 0: Screen title ───────────────────────
                        _staggered(
                          0,
                          Text(
                            l10n.loginTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── Stagger 1: Email field ────────────────────────
                        _staggered(
                          1,
                          TextFormField(
                            key: const Key('field-email'),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecor(l10n.loginEmailLabel),
                            validator: (v) => validateEmail(v, l10n),
                            enabled: !isLoading,
                            autocorrect: false,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // ── Stagger 2: Password field + forgot link ───────
                        _staggered(
                          2,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                key: const Key('field-password'),
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                enableSuggestions: false,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(color: Colors.white),
                                decoration: _fieldDecor(
                                  l10n.loginPasswordLabel,
                                  suffixIcon: IconButton(
                                    key: const Key('btn-toggle-password'),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.white,
                                      semanticLabel: _obscurePassword
                                          ? 'Показати пароль'
                                          : 'Приховати пароль',
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                validator: (v) => validatePassword(v, l10n),
                                enabled: !isLoading,
                                onFieldSubmitted: (_) =>
                                    isLoading ? null : _submit(),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  key: const Key('btn-forgot-password'),
                                  // TODO: Phase N — forgot password
                                  onPressed: null,
                                  style: TextButton.styleFrom(
                                    foregroundColor: BrandColors.sunshine,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.xxs,
                                    ),
                                  ),
                                  child: const Text('Забули пароль?'),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── Stagger 3: CTA + register link ───────────────
                        _staggered(
                          3,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GestureDetector(
                                onTapDown: (_) =>
                                    setState(() => _buttonPressed = true),
                                onTapUp: (_) =>
                                    setState(() => _buttonPressed = false),
                                onTapCancel: () =>
                                    setState(() => _buttonPressed = false),
                                child: AnimatedScale(
                                  scale: _buttonPressed ? 0.97 : 1.0,
                                  duration: const Duration(milliseconds: 100),
                                  child: ElevatedButton(
                                    key: const Key('btn-submit-login'),
                                    onPressed: isLoading ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: BrandColors.bliss,
                                      foregroundColor: BrandColors.midnight,
                                      disabledBackgroundColor: BrandColors.bliss
                                          .withValues(alpha: 0.5),
                                      minimumSize: const Size(
                                        double.infinity,
                                        56,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.md,
                                        ),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    child: isLoading
                                        ? const SizedBox(
                                            height: AppSpacing.md,
                                            width: AppSpacing.md,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: BrandColors.midnight,
                                            ),
                                          )
                                        : Text(l10n.loginSubmit),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    l10n.loginNoAccount,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    key: const Key('btn-go-to-register'),
                                    onPressed: isLoading
                                        ? null
                                        : () =>
                                              context.push(RouteNames.register),
                                    style: TextButton.styleFrom(
                                      foregroundColor: BrandColors.bliss,
                                    ),
                                    child: Text(l10n.loginCreateAccount),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
