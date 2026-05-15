// Phase 2.6 — Register screen.
// Updated: logo size increased, salon multi-step flow, initial state bug fix,
//          real-time password strength indicator.
//
// ConsumerStatefulWidget: owns TextEditingControllers, FormKeys, intent state,
// selected role, animation controllers, _obscurePassword toggle, _buttonPressed
// press state, a map of server-side field errors, and (for salon owners) a
// salon registration step index.
//
// Layout: full-screen gradient (Midnight → deep navy), no AppBar, SafeArea
// wrapping a scrollable form centred in a max-width 400 column.
//
// Overall registration flow:
//   Step 0 — Intent picker:
//     Three large intent cards animate in via _intentCtrl (500 ms stagger).
//     No form fields are shown. _intentSelected == false.
//
//   Step 1 — Form (all non-salon roles) OR Salon step 1:
//     The selected card collapses to a small badge pill.
//     Form fields stagger in via _entranceCtrl (600 ms, 5 items).
//     Tapping the badge resets to Step 0.
//     For SALON_OWNER: shows email + password + business name.
//     For INDEPENDENT_MASTER / CLIENT: shows firstName, lastName, email, password.
//
//   Step 2 — Salon details (SALON_OWNER only):
//     Shown after the user taps "Next" on salon step 1 with valid fields.
//     Collects address + phone number. A two-segment progress bar is shown.
//     A "Back" button returns to Step 1 without losing step-1 data.
//
// Bug fix (change 3):
//   _intentSelected starts as false; the form fields are controlled by
//   _intentSelected, not by a separate "was tapped" flag. Previously the
//   intent card had role == independentMaster pre-highlighted but
//   _intentSelected was false — so tapping the already-highlighted card
//   set _intentSelected = true and revealed the fields. This was confusing.
//   Resolution: the intent picker now shows NO pre-selection highlight
//   (_selectedRole is nullable and starts null) so the initial highlighted
//   state is never mismatched with the form visibility state.
//
// Submit flow:
//   1. Validate form locally, including server-error injection.
//   2. Call authProvider.notifier.register() with the selected role.
//   3. On success → navigate to home.
//   4. On ValidationFailure → extract fieldErrors, set _serverErrors, re-validate.
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
import '../../../shared/widgets/password_strength_indicator.dart';
import '../domain/user_role.dart';
import 'auth_gradient_background.dart';
import 'auth_notifier.dart';

// ---------------------------------------------------------------------------
// Phone validation regex — module-level so it is compiled once.
// ---------------------------------------------------------------------------

/// Matches valid phone characters: digits, +, spaces, hyphens, parentheses.
final RegExp _rePhone = RegExp(r'^[+\d\s\-()]+$');

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
/// Step 0 presents three intent cards so the user can identify their role
/// before seeing any form fields (progressive disclosure). Step 1 collapses
/// the selected card to a badge pill and reveals the registration form.
/// For SALON_OWNER there is an additional Step 2 for salon-specific details
/// (address, phone), guided by a two-segment progress indicator.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Intent state — BUG FIX (change 3):
  //   _selectedRole starts as null so no card is highlighted before the user
  //   taps. This removes the mismatch between the visual pre-selection and the
  //   hidden form fields that caused the "tap twice" bug.
  // ---------------------------------------------------------------------------

  bool _intentSelected = false;

  /// Nullable — null means the user has not yet chosen a role (Step 0).
  UserRole? _selectedRole;

  _IntentOption get _selectedOption => _kIntentOptions.firstWhere(
    (o) => o.role == _selectedRole,
    orElse: () => _kIntentOptions.first,
  );

  // ---------------------------------------------------------------------------
  // Salon multi-step state (change 2)
  // ---------------------------------------------------------------------------

  /// 0 = salon step 1 (email + password + business name)
  /// 1 = salon step 2 (address + phone)
  int _salonStep = 0;

  // Separate form keys per salon step so validation is scoped correctly.
  final _formKey = GlobalKey<FormState>();
  final _salonStep2FormKey = GlobalKey<FormState>();

  // ---------------------------------------------------------------------------
  // Form controllers
  // ---------------------------------------------------------------------------

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _buttonPressed = false;

  /// Server-side field errors injected after a [ValidationFailure].
  Map<String, String> _serverErrors = const {};

  // ---------------------------------------------------------------------------
  // Entrance animation — Step 1 form stagger (5 items, 600 ms)
  // ---------------------------------------------------------------------------

  late final AnimationController _entranceCtrl;

  // Cached per-item animations (5 staggered items: title=0, name/business=1,
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
  // Intent animation — Step 0 card stagger (3 items, 500 ms)
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

    // Step 1 controller — NOT started here; started only when the user taps an
    // intent card.
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

    // Step 0 controller — started after first frame (reduced-motion check).
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
    _businessNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
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
      _salonStep = 0;
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
    setState(() {
      _intentSelected = false;
      _salonStep = 0;
    });
    _entranceCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _intentCtrl.value = 1.0;
    } else {
      _intentCtrl.forward();
    }
  }

  // ---------------------------------------------------------------------------
  // Salon multi-step navigation (change 2)
  // ---------------------------------------------------------------------------

  void _advanceSalonStep() {
    // Validate only the current salon step form before advancing.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _salonStep = 1);
    // Re-run the entrance animation so salon step 2 fields animate in.
    _entranceCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _entranceCtrl.value = 1.0;
    } else {
      _entranceCtrl.forward();
    }
  }

  void _retreatSalonStep() {
    setState(() => _salonStep = 0);
    _entranceCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _entranceCtrl.value = 1.0;
    } else {
      _entranceCtrl.forward();
    }
  }

  // ---------------------------------------------------------------------------
  // Submit logic
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    // Clear any previous server errors before revalidating.
    setState(() => _serverErrors = const {});

    final role = _selectedRole;
    if (role == null) return;

    // For salon owner on step 2, validate the step-2 form key.
    final formValid = role == UserRole.salonOwner && _salonStep == 1
        ? (_salonStep2FormKey.currentState?.validate() ?? false)
        : (_formKey.currentState?.validate() ?? false);

    if (!formValid) return;

    await ref
        .read(authProvider.notifier)
        .register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          // For salon owners firstName/lastName are not collected — send empty
          // strings so the backend field constraints are satisfied.
          firstName: role == UserRole.salonOwner
              ? ''
              : _firstNameController.text.trim(),
          lastName: role == UserRole.salonOwner
              ? ''
              : _lastNameController.text.trim(),
          role: role,
          businessName: role == UserRole.salonOwner
              ? _businessNameController.text.trim()
              : null,
          address: role == UserRole.salonOwner
              ? _addressController.text.trim()
              : null,
          phone: role == UserRole.salonOwner
              ? _phoneController.text.trim()
              : null,
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
  // Field decoration helper — static borders allocated once at class load time
  // ---------------------------------------------------------------------------

  // The five OutlineInputBorder objects are promoted to static final so they
  // are allocated exactly once per class, not on every build() call (which
  // fires for every form field on every rebuild). The dynamic parts (errorText,
  // suffixIcon, fillColor, labelStyle) stay as runtime values in _fieldDecor.

  static final _kFieldRadius = BorderRadius.circular(AppSpacing.md);

  static final _kBorderDefault = OutlineInputBorder(
    borderRadius: _kFieldRadius,
    borderSide: const BorderSide(
      color: Color(0x26FFFFFF),
      width: 1,
    ), // white 15%
  );

  static final _kBorderFocused = OutlineInputBorder(
    borderRadius: _kFieldRadius,
    borderSide: const BorderSide(color: BrandColors.bliss, width: 1.5),
  );

  static final _kBorderError = OutlineInputBorder(
    borderRadius: _kFieldRadius,
    borderSide: const BorderSide(color: BrandColors.cherry),
  );

  static final _kBorderFocusedError = OutlineInputBorder(
    borderRadius: _kFieldRadius,
    borderSide: const BorderSide(color: BrandColors.cherry, width: 1.5),
  );

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
    border: _kBorderDefault,
    enabledBorder: _kBorderDefault,
    focusedBorder: _kBorderFocused,
    errorBorder: _kBorderError,
    focusedErrorBorder: _kBorderFocusedError,
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
  // Static animation helpers — allocated once, never recreated on rebuild
  // ---------------------------------------------------------------------------

  /// Offset tween for the salon step AnimatedSwitcher slide transition.
  /// Promoted to static final so it is not re-allocated on every animation tick.
  static final _kSalonSlide = Tween<Offset>(
    begin: const Offset(0.08, 0),
    end: Offset.zero,
  );

  /// Transition builder for the salon step AnimatedSwitcher.
  /// Extracted to a static method so the closure is not recreated each frame.
  static Widget _salonStepTransition(
    Widget child,
    Animation<double> animation,
  ) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: _kSalonSlide.animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: child,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 0 — Intent picker view
  // ---------------------------------------------------------------------------

  Widget _buildIntentPickerView(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Top spacer — mirrors the login screen breathing room.
        const SizedBox(height: AppSpacing.xl),

        // ── Logo — Hero tag shared with login for flight continuity.
        // Change 1: logo width increased from 120 → 160 for visual prominence.
        Center(
          child: Hero(
            tag: 'beautica-logo',
            child: SvgPicture.asset(
              'assets/images/logo.svg',
              width: 160,
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
        // Bug fix (change 3): isSelected is now _selectedRole == role.
        // _selectedRole starts null so no card is pre-highlighted, eliminating
        // the mismatch between visual state and form visibility.
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
  // Step 1+ — Form view (delegates to salon or standard path)
  // ---------------------------------------------------------------------------

  Widget _buildFormView(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    final role = _selectedRole;
    if (role == null) return const SizedBox.shrink();

    return role == UserRole.salonOwner
        ? _buildSalonFormView(context, l10n, isLoading)
        : _buildStandardFormView(context, l10n, isLoading, role);
  }

  // ---------------------------------------------------------------------------
  // Standard single-step form (INDEPENDENT_MASTER, CLIENT)
  // ---------------------------------------------------------------------------

  Widget _buildStandardFormView(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
    UserRole role,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),

          // ── Logo — Change 1: increased from 120 → 160.
          Center(
            child: Hero(
              tag: 'beautica-logo',
              child: SvgPicture.asset(
                'assets/images/logo.svg',
                width: 160,
                semanticsLabel: 'Beautica',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Selected intent badge — tapping resets to Step 0.
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
          // Kept for INDEPENDENT_MASTER and CLIENT per spec.
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
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
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
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
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

          // ── Stagger 3: Password field + strength indicator ─────────────
          _staggered(3, _buildPasswordField(l10n, isLoading)),
          const SizedBox(height: AppSpacing.lg),

          // ── Stagger 4: CTA + login link ────────────────────────────────
          _staggered(4, _buildCta(l10n, isLoading)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Salon multi-step form (SALON_OWNER) — Change 2
  // ---------------------------------------------------------------------------

  Widget _buildSalonFormView(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),

        // ── Logo — Change 1: increased from 120 → 160.
        Center(
          child: Hero(
            tag: 'beautica-logo',
            child: SvgPicture.asset(
              'assets/images/logo.svg',
              width: 160,
              semanticsLabel: 'Beautica',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Selected intent badge — tapping resets to Step 0.
        Center(
          child: _SelectedBadge(
            option: _selectedOption,
            l10n: l10n,
            onTap: _salonStep == 0 ? _resetToIntentPicker : null,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Two-segment step progress bar ──────────────────────────────────
        _SalonStepIndicator(currentStep: _salonStep),
        const SizedBox(height: AppSpacing.md),

        // ── Step-specific form content ─────────────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: _salonStepTransition,
          child: _salonStep == 0
              ? _buildSalonStep1(context, l10n, isLoading)
              : _buildSalonStep2(context, l10n, isLoading),
        ),
      ],
    );
  }

  /// Salon registration — Step 1: email + password + business name.
  Widget _buildSalonStep1(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('salon-step-1'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step title
          _staggered(
            0,
            Text(
              l10n.registerSalonStep1Title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Business name
          _staggered(
            1,
            TextFormField(
              key: const Key('field-businessName'),
              controller: _businessNameController,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecor(
                l10n.registerBusinessNameLabel,
                errorText: _serverErrors['businessName'],
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return l10n.errNameRequired;
                }
                return null;
              },
              enabled: !isLoading,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Email
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

          // Password + strength indicator
          _staggered(3, _buildPasswordField(l10n, isLoading)),
          const SizedBox(height: AppSpacing.lg),

          // Next button
          _staggered(
            4,
            ElevatedButton(
              key: const Key('btn-salon-next'),
              onPressed: isLoading ? null : _advanceSalonStep,
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
              child: Text(l10n.registerNextStep),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildLoginLink(l10n, isLoading),
        ],
      ),
    );
  }

  /// Salon registration — Step 2: address + phone.
  Widget _buildSalonStep2(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    return Form(
      key: _salonStep2FormKey,
      child: Column(
        key: const ValueKey('salon-step-2'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step title
          _staggered(
            0,
            Text(
              l10n.registerSalonStep2Title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Address
          _staggered(
            1,
            TextFormField(
              key: const Key('field-address'),
              controller: _addressController,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecor(
                l10n.registerAddressLabel,
                errorText: _serverErrors['address'],
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return l10n.errAddressRequired;
                }
                if (v.length > 255) return l10n.errAddressTooLong;
                return null;
              },
              enabled: !isLoading,
              autocorrect: false,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Phone (optional)
          _staggered(
            2,
            TextFormField(
              key: const Key('field-phone'),
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecor(
                l10n.registerPhoneLabel,
                errorText: _serverErrors['phoneNumber'],
              ),
              // Phone is optional but validated for format/length when present.
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                if (v.length > 20) return l10n.errPhoneTooLong;
                if (!_rePhone.hasMatch(v)) return l10n.errPhoneInvalidFormat;
                return null;
              },
              enabled: !isLoading,
              autocorrect: false,
              onFieldSubmitted: (_) => isLoading ? null : _submit(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Submit + Back buttons
          _staggered(4, _buildSalonStep2Buttons(l10n, isLoading)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared sub-builders
  // ---------------------------------------------------------------------------

  /// Password field with the strength indicator below it (change 4).
  ///
  /// Delegates to [_PasswordFieldWithStrength], which owns its own
  /// [TextEditingController] listener and [setState] calls so that password
  /// keystrokes never rebuild the parent [_RegisterScreenState] widget tree.
  /// The parent retains [_passwordController] for form submission access.
  Widget _buildPasswordField(AppLocalizations l10n, bool isLoading) {
    return _PasswordFieldWithStrength(
      controller: _passwordController,
      serverError: _serverErrors['password'],
      isLoading: isLoading,
      fieldDecor: _fieldDecor,
      onSubmit: isLoading ? null : _submit,
      l10n: l10n,
    );
  }

  /// Primary CTA button + sign-in link for single-step forms.
  Widget _buildCta(AppLocalizations l10n, bool isLoading) {
    return Column(
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
        _buildLoginLink(l10n, isLoading),
      ],
    );
  }

  /// Back + Submit row for salon step 2.
  Widget _buildSalonStep2Buttons(AppLocalizations l10n, bool isLoading) {
    return Column(
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
              key: const Key('btn-salon-submit-register'),
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
        TextButton(
          key: const Key('btn-salon-back'),
          onPressed: isLoading ? null : _retreatSalonStep,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: 0.7),
          ),
          child: Text(l10n.registerBackStep),
        ),
      ],
    );
  }

  /// "Already have an account? Sign in" row.
  Widget _buildLoginLink(AppLocalizations l10n, bool isLoading) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.registerHaveAccount,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
        TextButton(
          key: const Key('btn-go-to-login'),
          onPressed: isLoading
              ? null
              : () => context.canPop()
                    ? context.pop()
                    : context.go(RouteNames.login),
          style: TextButton.styleFrom(foregroundColor: BrandColors.bliss),
          child: Text(l10n.registerSignIn),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _SalonStepIndicator — two-segment progress bar (change 2)
// ---------------------------------------------------------------------------

/// Two-segment progress bar for the salon owner multi-step registration.
///
/// Segment 0 = Step 1 (basic info), segment 1 = Step 2 (salon details).
/// Both segments get the bliss colour once reached.
class _SalonStepIndicator extends StatelessWidget {
  const _SalonStepIndicator({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: List.generate(2, (i) {
            final isActive = i <= currentStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : AppSpacing.xs),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  height: 3,
                  decoration: BoxDecoration(
                    color: isActive
                        ? BrandColors.bliss
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${currentStep + 1} / 2',
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      ],
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

/// Compact pill showing the selected intent — tapping returns to Step 0.
///
/// Displayed at the top of the form view so the user always knows which role
/// they are registering for, and can change it without losing the form screen.
/// [onTap] is nullable — passing null disables the tap (used on salon step 2
/// to prevent accidentally resetting all entered data).
class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({
    required this.option,
    required this.l10n,
    required this.onTap,
  });

  final _IntentOption option;
  final AppLocalizations l10n;
  final VoidCallback? onTap;

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
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.edit_outlined,
              color: BrandColors.bliss.withValues(alpha: 0.7),
              size: 14,
            ),
          ],
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// _PasswordFieldWithStrength
// ---------------------------------------------------------------------------

/// Password [TextFormField] paired with a [PasswordStrengthIndicator].
///
/// Owns its own [State] so that keystrokes on the password field call
/// `setState` only on this small subtree — never on the root
/// [_RegisterScreenState] (which contains the entire 1400-line register form).
///
/// The parent continues to own the [TextEditingController] so it can read the
/// password value at form submission time. This widget subscribes to the
/// controller via [addListener] and keeps a local copy of the text for the
/// strength indicator.
class _PasswordFieldWithStrength extends StatefulWidget {
  const _PasswordFieldWithStrength({
    required this.controller,
    required this.serverError,
    required this.isLoading,
    required this.fieldDecor,
    required this.onSubmit,
    required this.l10n,
  });

  final TextEditingController controller;
  final String? serverError;
  final bool isLoading;

  /// Callback to the parent's `_fieldDecor` helper so the border styles remain
  /// consistent with the rest of the form without duplicating the definitions.
  final InputDecoration Function(
    String label, {
    String? errorText,
    Widget? suffixIcon,
  })
  fieldDecor;

  /// Called when the user submits the password field (keyboard action or
  /// `onFieldSubmitted`). Null when the form is loading (disables submission).
  final VoidCallback? onSubmit;

  final AppLocalizations l10n;

  @override
  State<_PasswordFieldWithStrength> createState() =>
      _PasswordFieldWithStrengthState();
}

class _PasswordFieldWithStrengthState
    extends State<_PasswordFieldWithStrength> {
  /// Local copy of the password text — drives [PasswordStrengthIndicator].
  /// Updated via a [TextEditingController] listener; setState only rebuilds
  /// this small widget, never the parent screen.
  String _currentPassword = '';

  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPasswordChanged);
    _currentPassword = widget.controller.text;
  }

  void _onPasswordChanged() {
    final text = widget.controller.text;
    if (text != _currentPassword) {
      setState(() => _currentPassword = text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPasswordChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('field-password'),
          controller: widget.controller,
          obscureText: _obscurePassword,
          enableSuggestions: false,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          style: const TextStyle(color: Colors.white),
          decoration: widget.fieldDecor(
            l10n.loginPasswordLabel,
            errorText: widget.serverError,
            suffixIcon: IconButton(
              key: const Key('btn-toggle-password'),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.white,
                semanticLabel: _obscurePassword
                    ? l10n.showPasswordSemanticLabel
                    : l10n.hidePasswordSemanticLabel,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (v) => validatePassword(v, l10n),
          enabled: !widget.isLoading,
          onFieldSubmitted: (_) => widget.onSubmit?.call(),
        ),
        PasswordStrengthIndicator(
          key: const Key('password-strength-indicator'),
          password: _currentPassword,
        ),
      ],
    );
  }
}
