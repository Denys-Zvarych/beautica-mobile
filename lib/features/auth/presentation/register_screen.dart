// Phase 2.6 — Register screen (redesigned Modern Dark Cinema — Phase 3.x visual).
//
// ConsumerStatefulWidget: owns TextEditingControllers, FormKey, selected role,
// animation controller, _obscurePassword toggle, _buttonPressed press state,
// and a map of server-side field errors for inline display.
//
// Layout: full-screen gradient (Midnight → deep navy), no AppBar, SafeArea
// wrapping a scrollable form centred in a max-width 400 column.
//
// Submit flow:
//   1. Validate form locally, including server-error injection.
//   2. Call authProvider.notifier.register().
//   3. On success → navigate to home.
//   4. On ValidationFailure → extract fieldErrors, set _serverErrors, re-validate
//      so each field shows its inline error.
//   5. On other Failure → floating SnackBar styled with BrandColors.cherry.
//
// Entrance animation: 7-item stagger (logo, title, role selector, name row,
// email, password, CTA row) using FadeTransition + SlideTransition with
// Interval-based curves over 700 ms.
//
// All user-visible strings go through AppLocalizations (UA primary).

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
import '../../../shared/validators/name_validator.dart';
import '../../../shared/validators/password_validator.dart';
import '../domain/user_role.dart';
import 'auth_gradient_background.dart';
import 'auth_notifier.dart';
import 'user_role_l10n.dart';

/// Register screen for new INDEPENDENT_MASTER accounts.
///
/// All roles except [UserRole.independentMaster] are rendered as disabled
/// segments with a tooltip indicating they are coming soon.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Form state
  // ---------------------------------------------------------------------------

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  UserRole _selectedRole = UserRole.independentMaster;
  bool _obscurePassword = true;
  bool _buttonPressed = false;

  /// Server-side field errors injected after a [ValidationFailure].
  /// The matching TextFormField validators return these messages on the next
  /// [_formKey.currentState!.validate()] call.
  Map<String, String> _serverErrors = const {};

  // ---------------------------------------------------------------------------
  // Entrance animation (6 staggered items, 700 ms total)
  // ---------------------------------------------------------------------------

  late final AnimationController _entranceCtrl;

  // Cached per-item animations (6 staggered items: title, role selector,
  // name row, email, password, CTA). Initialized in initState() after
  // _entranceCtrl is created so they are never recreated on build(). The logo
  // (first child in the Column) is unwrapped from stagger — Hero handles its
  // own flight transition.
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
      duration: const Duration(milliseconds: 700),
    );

    // Build cached animation objects once so build() never allocates new
    // Tween/CurvedAnimation instances. Indices 0..5 map to: title, role
    // selector, name row, email, password, CTA row.
    _opacities = List.generate(
      6,
      (i) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceCtrl,
          curve: Interval(
            (i * 0.10).clamp(0.0, 1.0),
            (i * 0.10 + 0.45).clamp(0.0, 1.0),
            curve: Curves.easeOut,
          ),
        ),
      ),
    );
    _slides = List.generate(
      6,
      (i) =>
          Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
            CurvedAnimation(
              parent: _entranceCtrl,
              curve: Interval(
                (i * 0.10).clamp(0.0, 1.0),
                (i * 0.10 + 0.45).clamp(0.0, 1.0),
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
    _firstNameController.dispose();
    _lastNameController.dispose();
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
    // Clear any previous server errors before revalidating.
    setState(() => _serverErrors = const {});

    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(authProvider.notifier)
        .register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
        );

    if (!mounted) return;

    final authState = ref.read(authProvider);
    authState.when(
      data: (_) {
        if (kDebugMode) {
          log(
            'Register screen: navigating to home',
            name: 'auth.register',
            level: 800,
          );
        }
        context.go(RouteNames.home);
      },
      loading: () {
        // Guard only — should not happen right after await.
      },
      error: (e, _) {
        if (e is ValidationFailure && e.fieldErrors.isNotEmpty) {
          // Surface field-level errors inline via errorText on each field.
          setState(() => _serverErrors = e.fieldErrors);
        } else {
          final l10n = AppLocalizations.of(context);
          final message = e is Failure
              ? e.userMessage(context)
              : l10n.errUnknown;
          _showErrorSnackBar(message);
        }
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
                        // ── Logo — no stagger wrapper; Hero handles its own
                        // flight transition. Wrapping with SlideTransition
                        // conflicts with the Hero overlay positioning.
                        Center(
                          child: Hero(
                            tag: 'beautica-logo',
                            child: SvgPicture.asset(
                              'assets/images/logo.svg',
                              width: 100,
                              semanticsLabel: 'Beautica',
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // ── Stagger 0: Screen title ───────────────────────
                        _staggered(
                          0,
                          Text(
                            l10n.registerTitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── Stagger 1: Role selector ──────────────────────
                        _staggered(
                          1,
                          _RoleSelector(
                            selectedRole: _selectedRole,
                            isLoading: isLoading,
                            onChanged: (role) =>
                                setState(() => _selectedRole = role),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // ── Stagger 2: First name + Last name row ─────────
                        _staggered(
                          2,
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  key: const Key('field-firstName'),
                                  controller: _firstNameController,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _fieldDecor(
                                    l10n.firstNameLabel,
                                    errorText: _serverErrors['firstName'],
                                  ),
                                  validator: (v) => validateName(v, l10n),
                                  enabled: !isLoading,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: TextFormField(
                                  key: const Key('field-lastName'),
                                  controller: _lastNameController,
                                  textInputAction: TextInputAction.next,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: _fieldDecor(
                                    l10n.lastNameLabel,
                                    errorText: _serverErrors['lastName'],
                                  ),
                                  validator: (v) => validateName(v, l10n),
                                  enabled: !isLoading,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // ── Stagger 3: Email field ────────────────────────
                        _staggered(
                          3,
                          TextFormField(
                            key: const Key('field-email'),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.white),
                            decoration: _fieldDecor(
                              l10n.loginEmailLabel,
                              errorText: _serverErrors['email'],
                            ),
                            validator: (v) => validateEmail(v, l10n),
                            enabled: !isLoading,
                            autocorrect: false,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // ── Stagger 4: Password field ─────────────────────
                        _staggered(
                          4,
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
                              errorText: _serverErrors['password'],
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
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            validator: (v) => validatePassword(v, l10n),
                            enabled: !isLoading,
                            onFieldSubmitted: (_) =>
                                isLoading ? null : _submit(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // ── Stagger 5: CTA + login link ───────────────────
                        _staggered(
                          5,
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
                                    key: const Key('btn-submit-register'),
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
                                        : Text(l10n.registerSubmit),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    l10n.registerHaveAccount,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    key: const Key('btn-go-to-login'),
                                    onPressed: isLoading
                                        ? null
                                        : () => context.canPop()
                                              ? context.pop()
                                              : context.go(RouteNames.login),
                                    style: TextButton.styleFrom(
                                      foregroundColor: BrandColors.bliss,
                                    ),
                                    child: Text(l10n.registerSignIn),
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

/// Role segment picker — dark-surface themed.
///
/// Only [UserRole.independentMaster] is enabled for the MVP; all other roles
/// display a tooltip indicating they are coming soon. Extracted to keep
/// [_RegisterScreenState.build] readable.
class _RoleSelector extends StatelessWidget {
  const _RoleSelector({
    required this.selectedRole,
    required this.isLoading,
    required this.onChanged,
  });

  final UserRole selectedRole;
  final bool isLoading;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget segmentLabel(UserRole role) {
      final text = Text(role.label(l10n));
      if (role == UserRole.independentMaster) return text;
      return Tooltip(message: l10n.roleComingSoon, child: text);
    }

    return Theme(
      data: Theme.of(context).copyWith(
        // Dark-surface style: override the SegmentedButton color scheme so
        // the unselected segments read on the dark gradient background.
        colorScheme: Theme.of(context).colorScheme.copyWith(
          secondaryContainer: BrandColors.bliss,
          onSecondaryContainer: BrandColors.midnight,
          outline: Colors.white.withValues(alpha: 0.2),
          surface: BrandColors.darkSurface,
          onSurface: Colors.white,
        ),
      ),
      child: SegmentedButton<UserRole>(
        key: const Key('field-role'),
        segments: UserRole.values
            .map(
              (r) => ButtonSegment<UserRole>(
                value: r,
                label: segmentLabel(r),
                enabled: r == UserRole.independentMaster,
              ),
            )
            .toList(),
        selected: {selectedRole},
        onSelectionChanged: isLoading
            ? null
            : (selected) => onChanged(selected.first),
        multiSelectionEnabled: false,
      ),
    );
  }
}
