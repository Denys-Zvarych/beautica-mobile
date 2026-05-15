// Phase 2.6 — Register screen (two-step intent picker — Phase 3.x visual).
//
// ConsumerStatefulWidget: owns TextEditingControllers, FormKey, intent state,
// selected role, animation controllers, _obscurePassword toggle, _buttonPressed
// press state, and a map of server-side field errors for inline display.
//
// Layout: full-screen gradient (Midnight → deep navy), no AppBar, SafeArea
// wrapping a scrollable form centred in a max-width 400 column.
//
// Two-step flow:
//   Step 1 (_intentSelected == false):
//     Three large intent cards animate in via _intentCtrl (500 ms stagger).
//     No form fields are shown.
//   Step 2 (_intentSelected == true):
//     The selected card collapses to a small badge pill.
//     Form fields stagger in via _entranceCtrl (600 ms, 5 items).
//     Tapping the badge resets to Step 1.
//
// Submit flow:
//   1. Validate form locally, including server-error injection.
//   2. Call authProvider.notifier.register() with the selected role.
//   3. On success → navigate to home.
//   4. On ValidationFailure → extract fieldErrors, set _serverErrors, re-validate
//      so each field shows its inline error.
//   5. On other Failure → floating SnackBar styled with BrandColors.cherry.
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

// ---------------------------------------------------------------------------
// Intent option data class
// ---------------------------------------------------------------------------

/// Pure data descriptor for a registration intent card.
///
/// No Flutter imports — intentionally a plain Dart class so it stays in the
/// presentation layer without dragging Widget dependencies into the data model.
class _IntentOption {
  const _IntentOption({required this.icon, required this.role});

  /// Decorative emoji string displayed as a visual anchor alongside text.
  /// Not used as a semantic icon — the card's text labels carry accessibility.
  final String icon;

  final UserRole role;
}

/// The three self-registration intent options.
///
/// [UserRole.salonAdmin] and [UserRole.salonMaster] are omitted — they are
/// invite-only and cannot self-register.
const List<_IntentOption> _kIntentOptions = [
  _IntentOption(icon: '✂️', role: UserRole.independentMaster),
  _IntentOption(icon: '🏠', role: UserRole.salonOwner),
  _IntentOption(icon: '💅', role: UserRole.client),
];

// ---------------------------------------------------------------------------
// L10n helper functions
// ---------------------------------------------------------------------------

String _intentTitle(_IntentOption option, AppLocalizations l10n) =>
    switch (option.role) {
      UserRole.independentMaster => l10n.intentIndependentTitle,
      UserRole.salonOwner => l10n.intentSalonTitle,
      UserRole.client => l10n.intentClientTitle,
      _ => '',
    };

String _intentSubtitle(_IntentOption option, AppLocalizations l10n) =>
    switch (option.role) {
      UserRole.independentMaster => l10n.intentIndependentSubtitle,
      UserRole.salonOwner => l10n.intentSalonSubtitle,
      UserRole.client => l10n.intentClientSubtitle,
      _ => '',
    };

// ---------------------------------------------------------------------------
// RegisterScreen
// ---------------------------------------------------------------------------

/// Register screen for new Beautica accounts.
///
/// Step 1 presents three intent cards so the user can identify their role
/// before seeing any form fields (progressive disclosure). Step 2 collapses
/// the selected card to a badge pill and reveals the registration form with a
/// staggered entrance animation.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Intent state
  // ---------------------------------------------------------------------------

  bool _intentSelected = false;
  UserRole _selectedRole = UserRole.independentMaster;

  _IntentOption get _selectedOption =>
      _kIntentOptions.firstWhere((o) => o.role == _selectedRole);

  // ---------------------------------------------------------------------------
  // Form state
  // ---------------------------------------------------------------------------

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _buttonPressed = false;

  /// Server-side field errors injected after a [ValidationFailure].
  Map<String, String> _serverErrors = const {};

  // ---------------------------------------------------------------------------
  // Entrance animation — Step 2 form stagger (5 items, 600 ms)
  // ---------------------------------------------------------------------------

  late final AnimationController _entranceCtrl;

  // Cached per-item animations (5 staggered items: title=0, name row=1,
  // email=2, password=3, CTA=4). Initialized in initState() after
  // _entranceCtrl is created so they are never recreated on build(). The logo
  // is outside the stagger — Hero handles its own flight transition.
  late final List<Animation<double>> _opacities;
  late final List<Animation<Offset>> _slides;

  Widget _staggered(int index, Widget child) => FadeTransition(
    opacity: _opacities[index],
    child: SlideTransition(position: _slides[index], child: child),
  );

  // ---------------------------------------------------------------------------
  // Intent animation — Step 1 card stagger (3 items, 500 ms)
  // ---------------------------------------------------------------------------

  late final AnimationController _intentCtrl;

  // Cached per-card animations (3 cards). Each uses a 0.5-width window spaced
  // 0.15 apart so card 0 leads and card 2 trails by 300 ms.
  late final List<Animation<double>> _intentOpacities;
  late final List<Animation<Offset>> _intentSlides;

  Widget _intentStaggered(int index, Widget child) => FadeTransition(
    opacity: _intentOpacities[index],
    child: SlideTransition(position: _intentSlides[index], child: child),
  );

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Step 2 controller — NOT started in initState; started only when the
    // user taps an intent card.
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Build cached form animation objects once (indices 0..4).
    // offset: 0.12, window: 0.5 → items stagger 72 ms apart over 600 ms.
    _opacities = List.generate(
      5,
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
      5,
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

    // Step 1 controller — started in initState (after reduced-motion guard).
    _intentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Build cached intent card animation objects (indices 0..2).
    // offset: 0.15, window: 0.5 → cards stagger 75 ms apart over 500 ms.
    _intentOpacities = List.generate(
      3,
      (i) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _intentCtrl,
          curve: Interval(
            (i * 0.15).clamp(0.0, 1.0),
            (i * 0.15 + 0.5).clamp(0.0, 1.0),
            curve: Curves.easeOut,
          ),
        ),
      ),
    );
    _intentSlides = List.generate(
      3,
      (i) =>
          Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
            CurvedAnimation(
              parent: _intentCtrl,
              curve: Interval(
                (i * 0.15).clamp(0.0, 1.0),
                (i * 0.15 + 0.5).clamp(0.0, 1.0),
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
        // Skip intent card animation — show them immediately.
        _intentCtrl.value = 1.0;
        // Do NOT pre-complete _entranceCtrl — it starts on user tap only.
      } else {
        _intentCtrl.forward();
      }
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _intentCtrl.dispose();
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
  // Intent selection
  // ---------------------------------------------------------------------------

  void _selectIntent(_IntentOption option) {
    setState(() {
      _selectedRole = option.role;
      _intentSelected = true;
    });
    if (MediaQuery.of(context).disableAnimations) {
      _entranceCtrl.value = 1.0;
    } else {
      _entranceCtrl.forward();
    }
    if (kDebugMode) {
      log(
        'Intent selected: ${option.role.toWire}',
        name: 'auth.register',
        level: 800,
      );
    }
  }

  void _resetToIntentPicker() {
    setState(() => _intentSelected = false);
    _entranceCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _intentCtrl.value = 1.0;
    } else {
      _intentCtrl.forward();
    }
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
          role: _selectedRole,
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
                  child: _intentSelected
                      ? _buildFormView(context, l10n, isLoading)
                      : _buildIntentPickerView(context, l10n),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Intent picker view
  // ---------------------------------------------------------------------------

  Widget _buildIntentPickerView(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Top spacer — mirrors the login screen breathing room.
        const SizedBox(height: AppSpacing.xl),

        // ── Logo — Hero tag shared with login for flight continuity.
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
        const SizedBox(height: AppSpacing.xl),

        // ── Intent picker title ────────────────────────────────────────────
        _intentStaggered(
          0,
          Text(
            l10n.intentPickerTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── Intent cards (3 items, staggered) ─────────────────────────────
        _intentStaggered(
          0,
          _IntentCard(
            option: _kIntentOptions[0],
            isSelected: _selectedRole == _kIntentOptions[0].role,
            onTap: () => _selectIntent(_kIntentOptions[0]),
            l10n: l10n,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _intentStaggered(
          1,
          _IntentCard(
            option: _kIntentOptions[1],
            isSelected: _selectedRole == _kIntentOptions[1].role,
            onTap: () => _selectIntent(_kIntentOptions[1]),
            l10n: l10n,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _intentStaggered(
          2,
          _IntentCard(
            option: _kIntentOptions[2],
            isSelected: _selectedRole == _kIntentOptions[2].role,
            onTap: () => _selectIntent(_kIntentOptions[2]),
            l10n: l10n,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // ── Already have account row ───────────────────────────────────────
        _intentStaggered(
          2,
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.registerHaveAccount,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              ),
              TextButton(
                key: const Key('btn-go-to-login-from-intent'),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go(RouteNames.login),
                style: TextButton.styleFrom(foregroundColor: BrandColors.bliss),
                child: Text(l10n.registerSignIn),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Form view
  // ---------------------------------------------------------------------------

  Widget _buildFormView(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Top spacer.
          const SizedBox(height: AppSpacing.xl),

          // ── Logo — Hero tag shared with login for flight continuity.
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

          // ── Selected intent badge — shown immediately, no stagger.
          // Tapping resets to Step 1.
          Center(
            child: _SelectedBadge(
              option: _selectedOption,
              l10n: l10n,
              onTap: _resetToIntentPicker,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Stagger 0: Screen title ────────────────────────────────────
          _staggered(
            0,
            Text(
              l10n.registerTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Stagger 1: First name + Last name row ──────────────────────
          _staggered(
            1,
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

          // ── Stagger 2: Email field ─────────────────────────────────────
          _staggered(
            2,
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

          // ── Stagger 3: Password field ──────────────────────────────────
          _staggered(
            3,
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
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => validatePassword(v, l10n),
              enabled: !isLoading,
              onFieldSubmitted: (_) => isLoading ? null : _submit(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Stagger 4: CTA + login link ────────────────────────────────
          _staggered(
            4,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTapDown: (_) => setState(() => _buttonPressed = true),
                  onTapUp: (_) => setState(() => _buttonPressed = false),
                  onTapCancel: () => setState(() => _buttonPressed = false),
                  child: AnimatedScale(
                    scale: _buttonPressed ? 0.97 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: ElevatedButton(
                      key: const Key('btn-submit-register'),
                      onPressed: isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BrandColors.bliss,
                        foregroundColor: BrandColors.midnight,
                        disabledBackgroundColor: BrandColors.bliss.withValues(
                          alpha: 0.5,
                        ),
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.md),
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
                        color: Colors.white.withValues(alpha: 0.7),
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
    );
  }
}

// ---------------------------------------------------------------------------
// _IntentCard
// ---------------------------------------------------------------------------

/// Tappable dark-surface card displaying an intent option with emoji, title,
/// and subtitle. Highlighted in bliss gold when [isSelected] is true.
class _IntentCard extends StatelessWidget {
  const _IntentCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
    required this.l10n,
  });

  final _IntentOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? BrandColors.bliss.withValues(alpha: 0.12)
              : BrandColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? BrandColors.bliss
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Decorative emoji — visual anchor only; not used as a semantic
            // navigation icon. Accessibility is carried by the text labels.
            Text(option.icon, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _intentTitle(option, l10n),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: isSelected ? BrandColors.bliss : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _intentSubtitle(option, l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: BrandColors.bliss,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SelectedBadge
// ---------------------------------------------------------------------------

/// Compact pill showing the selected intent — tapping returns to Step 1.
///
/// Displayed at the top of the form view (Step 2) so the user always knows
/// which role they are registering for, and can change it without losing the
/// form screen.
class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({
    required this.option,
    required this.l10n,
    required this.onTap,
  });

  final _IntentOption option;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: BrandColors.bliss.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: BrandColors.bliss.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(option.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _intentTitle(option, l10n),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: BrandColors.bliss,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.edit_outlined,
            color: BrandColors.bliss.withValues(alpha: 0.7),
            size: 14,
          ),
        ],
      ),
    ),
  );
}
