// Phase 2.6 — Register screen — Warm Mocha visual redesign (Phase 2.x).
// Updated: universal 2-step flow for all roles, Ukrainian phone mask,
//          email autovalidation, phone required for all roles,
//          businessName moved to step 2 for salon owners.
//
// VISUAL REDESIGN ONLY — all business logic, form validation, Riverpod state,
// Keys, routing, and animation controllers are unchanged from the previous
// "Modern Dark Cinema" version. Changed only:
//   - Background: AuthGradientBackground (espresso + mocha blobs).
//   - Brand row: monogram B + BEAUTICA (shared _BrandRow-equivalent widget).
//   - Role picker cards: glassmorphism with camel selected state, checkmark
//     circle, Material icons matching the HTML role-selection-page.html.
//   - Step indicator: 3-step progress row matching sign-up-page.html / done-page.html.
//   - Form fields: warm-mocha InputDecoration (camel focus ring, 12 px radius).
//   - CTA buttons: mocha gradient (same _MochaCtaButton from login_screen.dart).
//   - Scaffold background: BrandColors.espresso.
//
// ConsumerStatefulWidget: owns TextEditingControllers, FormKeys, intent state,
// selected role, animation controllers, _obscurePassword toggle, _buttonPressed
// press state, a map of server-side field errors, and a universal registration
// step index (_registrationStep) shared across all roles.
//
// Overall registration flow (UNCHANGED):
//   Step 0 — Intent picker: three glassmorphism role cards.
//   Step 1 (all roles) — Credentials: email + password.
//   Step 2 (all roles) — Details: name/phone or businessName/address/phone.
//
// All user-visible strings go through AppLocalizations (UA primary).

import 'dart:developer';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/email_validator.dart';
import '../../../shared/validators/name_validator.dart';
import '../../../shared/validators/password_validator.dart';
import '../../../shared/widgets/auth_field_label.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import '../../../shared/widgets/password_strength_indicator.dart';
import '../domain/user_role.dart';
import 'auth_notifier.dart';

// ---------------------------------------------------------------------------
// Phone validation regex — module-level so it is compiled once.
// ---------------------------------------------------------------------------

/// Matches a fully-formatted Ukrainian phone number:
///   +380 XX XXX XX XX  (digits only after the fixed +380 prefix).
///
/// The raw value stored in the controller will always start with '+380 '
/// because [_UkrainianPhoneFormatter] prefixes it automatically.
final RegExp _reUkrainianPhone = RegExp(r'^\+380\s\d{2}\s\d{3}\s\d{2}\s\d{2}$');

// ---------------------------------------------------------------------------
// Static style constants — allocated once, never inside build()
// ---------------------------------------------------------------------------

/// Role card border radius (18 px matching HTML role cards).
const _kRoleCardRadius = BorderRadius.all(Radius.circular(18));

/// Input field border radius (12 px matching HTML mockup).
const _kInputRadius = BorderRadius.all(Radius.circular(12));

/// CTA button border radius (14 px).
const _kCtaRadius = BorderRadius.all(Radius.circular(14));

/// Default input border — white 10% opacity.
const _kInputBorderDefault = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x1AFFFFFF), width: 1),
);

/// Focused input border — camel 36% opacity.
const _kInputBorderFocused = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x5CB89A7A), width: 1.5),
);

/// Error input border — errorRust solid.
const _kInputBorderError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.errorRust, width: 1),
);

/// Focused-error input border.
const _kInputBorderFocusedError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.errorRust, width: 1.5),
);

/// CTA gradient — mocha linear.
const _kCtaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4A2E10), BrandColors.mocha, BrandColors.latte],
  stops: [0.0, 0.6, 1.0],
);

/// CTA box shadow — mocha glow.
const List<BoxShadow> _kCtaShadow = [
  BoxShadow(
    color: Color(0xAD3A240C), // rgba(58,36,12,0.68)
    blurRadius: 24,
    offset: Offset(0, 4),
  ),
];

// ---------------------------------------------------------------------------
// Intent option data class (UNCHANGED — pure Dart, no Flutter imports used in class)
// ---------------------------------------------------------------------------

/// Pure data descriptor for a registration intent card.
class _IntentOption {
  const _IntentOption({required this.role, required this.materialIcon});

  final UserRole role;

  /// Material icon matching the role card icon in the HTML mockup.
  final IconData materialIcon;
}

/// The three self-registration intent options.
///
/// Icons chosen to match the HTML SVG icons:
///   CLIENT → person icon
///   SALON_OWNER → store/building icon
///   INDEPENDENT_MASTER → content_cut (scissors) icon
const List<_IntentOption> _kIntentOptions = [
  _IntentOption(role: UserRole.client, materialIcon: Icons.person_outline),
  _IntentOption(role: UserRole.salonOwner, materialIcon: Icons.store_outlined),
  _IntentOption(
    role: UserRole.independentMaster,
    materialIcon: Icons.content_cut_outlined,
  ),
];

// ---------------------------------------------------------------------------
// L10n helper functions (UNCHANGED)
// ---------------------------------------------------------------------------

String _intentTitle(_IntentOption option, AppLocalizations l10n) =>
    switch (option.role) {
      UserRole.independentMaster => l10n.intentIndependentTitle,
      UserRole.salonOwner => l10n.intentSalonTitle,
      UserRole.client => l10n.intentClientTitle,
      _ => '',
    };

String _intentDesc(_IntentOption option, AppLocalizations l10n) =>
    switch (option.role) {
      UserRole.independentMaster => l10n.intentIndependentDesc,
      UserRole.salonOwner => l10n.intentSalonDesc,
      UserRole.client => l10n.intentClientDesc,
      _ => '',
    };

// ---------------------------------------------------------------------------
// RegisterScreen
// ---------------------------------------------------------------------------

/// Register screen for new Beautica accounts — Warm Mocha design.
///
/// Step 0: glassmorphism role picker cards.
/// Step 1 (all roles): credentials (email + password) in a glass card.
/// Step 2 (all roles): details (name/phone or businessName/address/phone).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // Intent state (UNCHANGED)
  // ---------------------------------------------------------------------------

  bool _intentSelected = false;

  /// Nullable — null means the user has not yet chosen a role (Step 0).
  UserRole? _selectedRole;

  _IntentOption get _selectedOption => _kIntentOptions.firstWhere(
    (o) => o.role == _selectedRole,
    orElse: () => _kIntentOptions.first,
  );

  // ---------------------------------------------------------------------------
  // Universal multi-step state (UNCHANGED)
  // ---------------------------------------------------------------------------

  int _registrationStep = 0;

  final _step1FormKey = GlobalKey<FormState>();
  final _step2FormKey = GlobalKey<FormState>();

  // ---------------------------------------------------------------------------
  // Form controllers (UNCHANGED)
  // ---------------------------------------------------------------------------

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _buttonPressed = false;

  Map<String, String> _serverErrors = const {};

  // ---------------------------------------------------------------------------
  // Entrance animation — Step 1 form stagger (5 items, 600 ms) (UNCHANGED)
  // ---------------------------------------------------------------------------

  late final AnimationController _entranceCtrl;

  late final List<Animation<double>> _opacities;
  late final List<Animation<Offset>> _slides;

  Widget _staggered(int index, Widget child) => FadeTransition(
    opacity: _opacities[index],
    child: SlideTransition(position: _slides[index], child: child),
  );

  // ---------------------------------------------------------------------------
  // Intent animation — Step 0 card stagger (3 items, 500 ms) (UNCHANGED)
  // ---------------------------------------------------------------------------

  late final AnimationController _intentCtrl;

  late final List<Animation<double>> _intentOpacities;
  late final List<Animation<Offset>> _intentSlides;

  Widget _intentStaggered(int index, Widget child) => FadeTransition(
    opacity: _intentOpacities[index],
    child: SlideTransition(position: _intentSlides[index], child: child),
  );

  // ---------------------------------------------------------------------------
  // Lifecycle (UNCHANGED)
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _opacities = [
      for (var i = 0; i < 5; i++)
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: Interval(
              (i * 0.12).clamp(0.0, 1.0),
              (i * 0.12 + 0.5).clamp(0.0, 1.0),
              curve: Curves.easeOut,
            ),
          ),
        ),
    ];
    _slides = [
      for (var i = 0; i < 5; i++)
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
    ];

    _intentCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _intentOpacities = [
      for (var i = 0; i < 3; i++)
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _intentCtrl,
            curve: Interval(
              (i * 0.15).clamp(0.0, 1.0),
              (i * 0.15 + 0.5).clamp(0.0, 1.0),
              curve: Curves.easeOut,
            ),
          ),
        ),
    ];
    _intentSlides = [
      for (var i = 0; i < 3; i++)
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
    ];

    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOn();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _intentCtrl.value = 1.0;
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
  // Intent selection (UNCHANGED)
  // ---------------------------------------------------------------------------

  void _selectIntent(_IntentOption option) {
    setState(() {
      _selectedRole = option.role;
      _intentSelected = true;
      _registrationStep = 0;
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
      _registrationStep = 0;
    });
    _entranceCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _intentCtrl.value = 1.0;
    } else {
      _intentCtrl.forward();
    }
  }

  // ---------------------------------------------------------------------------
  // Universal multi-step navigation (UNCHANGED)
  // ---------------------------------------------------------------------------

  void _advanceStep() {
    if (!(_step1FormKey.currentState?.validate() ?? false)) return;
    setState(() => _registrationStep = 1);
    _entranceCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _entranceCtrl.value = 1.0;
    } else {
      _entranceCtrl.forward();
    }
  }

  void _retreatStep() {
    setState(() => _registrationStep = 0);
    _entranceCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _entranceCtrl.value = 1.0;
    } else {
      _entranceCtrl.forward();
    }
  }

  // ---------------------------------------------------------------------------
  // Submit logic (UNCHANGED)
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    setState(() => _serverErrors = const {});

    final role = _selectedRole;
    if (role == null) return;

    if (!(_step2FormKey.currentState?.validate() ?? false)) return;

    final isSalon = role == UserRole.salonOwner;

    await ref
        .read(authProvider.notifier)
        .register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: isSalon ? '' : _firstNameController.text.trim(),
          lastName: isSalon ? '' : _lastNameController.text.trim(),
          role: role,
          businessName: isSalon ? _businessNameController.text.trim() : null,
          address: isSalon ? _addressController.text.trim() : null,
          phone: _phoneController.text.trim(),
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
      loading: () {},
      error: (e, _) {
        if (e is ValidationFailure && e.fieldErrors.isNotEmpty) {
          final hasStep1Error =
              e.fieldErrors.containsKey('email') ||
              e.fieldErrors.containsKey('password');
          setState(() {
            _serverErrors = e.fieldErrors;
            if (hasStep1Error) _registrationStep = 0;
          });
          if (hasStep1Error) {
            _entranceCtrl.reset();
            if (MediaQuery.of(context).disableAnimations) {
              _entranceCtrl.value = 1.0;
            } else {
              _entranceCtrl.forward();
            }
          }
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
        backgroundColor: BrandColors.errorRust,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppSpacing.sm)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Field decoration helper — warm mocha style
  // ---------------------------------------------------------------------------

  // The static uppercase label now lives in an [AuthFieldLabel] above each
  // field (Defect 1 — design parity with sign-up-page.html). The string
  // passed here is therefore used as the in-field placeholder, mirroring the
  // login screen's pattern and the mockup's `placeholder` attribute. No
  // logic/validator/l10n key changes — purely the visual surface.
  InputDecoration _fieldDecor(
    String label, {
    String? errorText,
    Widget? suffixIcon,
    String? hintText,
    Widget? prefixIcon,
  }) => InputDecoration(
    hintText: hintText ?? label,
    errorText: errorText,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: const Color(0x12FFFFFF), // white 7%
    labelStyle: const TextStyle(color: Color(0x6BFFFFFF)),
    floatingLabelStyle: const TextStyle(color: BrandColors.camel),
    errorStyle: const TextStyle(color: BrandColors.errorRust, fontSize: 11),
    hintStyle: const TextStyle(color: Color(0x2EFFFFFF)),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    border: _kInputBorderDefault,
    enabledBorder: _kInputBorderDefault,
    focusedBorder: _kInputBorderFocused,
    errorBorder: _kInputBorderError,
    focusedErrorBorder: _kInputBorderFocusedError,
    isDense: true,
  );

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Shared top geometry — identical to login + every register
          //    step so the brand row never jumps on setState() step change.
          const SizedBox(height: 24),

          // ── Brand row (shared across step 0 and steps 1–2)
          const _RegBrandRow(key: Key('brand-row')),

          const SizedBox(height: 36),

          // ── Step-specific content below the (static) brand row.
          _intentSelected
              ? _buildFormView(context, l10n, isLoading)
              : _buildIntentPickerView(context, l10n),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Static animation transition builder — allocated once
  // ---------------------------------------------------------------------------

  static Widget _stepTransition(Widget child, Animation<double> animation) =>
      FadeTransition(opacity: animation, child: child);

  // ---------------------------------------------------------------------------
  // Step 0 — Intent picker view (WARM MOCHA redesign)
  // ---------------------------------------------------------------------------

  Widget _buildIntentPickerView(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Brand row + its surrounding 24/36 gaps now live in build()'s
        // shared parent so step 0 and steps 1–2 share identical top geometry.

        // ── Headline + accent + sub-text
        _intentStaggered(0, _RegisterHeadlineBlock(l10n: l10n)),

        const SizedBox(height: AppSpacing.lg),

        // ── Role cards (3 items, staggered)
        _intentStaggered(
          0,
          _RoleCard(
            option: _kIntentOptions[0],
            isSelected: _selectedRole == _kIntentOptions[0].role,
            onTap: () => _selectIntent(_kIntentOptions[0]),
            l10n: l10n,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _intentStaggered(
          1,
          _RoleCard(
            option: _kIntentOptions[1],
            isSelected: _selectedRole == _kIntentOptions[1].role,
            onTap: () => _selectIntent(_kIntentOptions[1]),
            l10n: l10n,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _intentStaggered(
          2,
          _RoleCard(
            option: _kIntentOptions[2],
            isSelected: _selectedRole == _kIntentOptions[2].role,
            onTap: () => _selectIntent(_kIntentOptions[2]),
            l10n: l10n,
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // ── CTA — "Продовжити" (enabled only when a role is selected)
        _intentStaggered(
          2,
          _MochaCtaButton(
            onPressed: _selectedRole != null
                ? () => _selectIntent(_selectedOption)
                : null,
            onTapDown: () => setState(() => _buttonPressed = true),
            onTapUp: () => setState(() => _buttonPressed = false),
            onTapCancel: () => setState(() => _buttonPressed = false),
            isPressed: _buttonPressed,
            isLoading: false,
            label: l10n.registerContinue,
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // ── "Already have account?" row
        // Uses key btn-go-to-login-from-intent to distinguish from the
        // step-2 login link (btn-go-to-login) — required by widget tests.
        _intentStaggered(2, _buildLoginLinkRow(l10n, false, fromIntent: true)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1+ — Universal form view
  // ---------------------------------------------------------------------------

  Widget _buildFormView(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    final role = _selectedRole;
    if (role == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Brand row + its surrounding 24/36 gaps now live in build()'s
        // shared parent so the brand row stays put on every step change.

        // ── 3-step progress indicator (Деталі / Верифікація / Готово)
        // Steps 0 and 1 of _registrationStep map to progress step 0 (Details)
        // and step 1 (Details complete). The visual indicator shows:
        //   _registrationStep 0 → step 1 active, steps 2-3 inactive
        //   _registrationStep 1 → step 1 done, step 2 active, step 3 inactive
        _WarmMochaStepIndicator(currentStep: _registrationStep, l10n: l10n),

        const SizedBox(height: AppSpacing.md),

        // ── Selected intent badge — tapping resets to Step 0 (step 1 only)
        Center(
          child: _SelectedBadge(
            option: _selectedOption,
            l10n: l10n,
            onTap: _registrationStep == 0 ? _resetToIntentPicker : null,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Step-specific form content
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: _stepTransition,
          child: _registrationStep == 0
              ? _buildStep1(context, l10n, isLoading)
              : _buildStep2(context, l10n, isLoading, role),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Credentials form (UNCHANGED logic, warm mocha visual)
  // ---------------------------------------------------------------------------

  Widget _buildStep1(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    return _Step1Form(
      step1FormKey: _step1FormKey,
      emailController: _emailController,
      passwordController: _passwordController,
      serverErrors: _serverErrors,
      isLoading: isLoading,
      opacities: _opacities,
      slides: _slides,
      fieldDecor: _fieldDecor,
      onNext: _advanceStep,
      onNavigateToLogin: () =>
          context.canPop() ? context.pop() : context.go(RouteNames.login),
      l10n: l10n,
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Role-specific details (UNCHANGED logic, warm mocha visual)
  // ---------------------------------------------------------------------------

  Widget _buildStep2(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
    UserRole role,
  ) {
    final isSalon = role == UserRole.salonOwner;

    return Form(
      key: _step2FormKey,
      child: Column(
        key: const ValueKey('registration-step-2'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _staggered(
            0,
            Text(
              isSalon ? l10n.registerSalonStep2Title : l10n.registerStep2Title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Glass card wrapping the form fields (sign-up-page.html
          //    `.glass-card`). Step 1/2 fields previously sat bare on the
          //    background — Defect 1.
          _RegGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSalon) ...[
                  _staggered(
                    1,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthFieldLabel(l10n.registerBusinessNameLabel),
                        TextFormField(
                          key: const Key('field-businessName'),
                          controller: _businessNameController,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(
                            color: BrandColors.cream,
                            fontSize: 14,
                          ),
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
                      ],
                    ),
                  ),
                  // .field-group { margin-bottom: 14px }
                  const SizedBox(height: 14),

                  _staggered(
                    2,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthFieldLabel(l10n.registerAddressLabel),
                        TextFormField(
                          key: const Key('field-address'),
                          controller: _addressController,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(
                            color: BrandColors.cream,
                            fontSize: 14,
                          ),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  _staggered(
                    1,
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AuthFieldLabel(l10n.firstNameLabel),
                              TextFormField(
                                key: const Key('field-firstName'),
                                controller: _firstNameController,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                  color: BrandColors.cream,
                                  fontSize: 14,
                                ),
                                decoration: _fieldDecor(
                                  l10n.firstNameLabel,
                                  errorText: _serverErrors['firstName'],
                                ),
                                validator: (v) => validateName(v, l10n),
                                enabled: !isLoading,
                                autocorrect: false,
                                enableIMEPersonalizedLearning: false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AuthFieldLabel(l10n.lastNameLabel),
                              TextFormField(
                                key: const Key('field-lastName'),
                                controller: _lastNameController,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(
                                  color: BrandColors.cream,
                                  fontSize: 14,
                                ),
                                decoration: _fieldDecor(
                                  l10n.lastNameLabel,
                                  errorText: _serverErrors['lastName'],
                                ),
                                validator: (v) => validateName(v, l10n),
                                enabled: !isLoading,
                                autocorrect: false,
                                enableIMEPersonalizedLearning: false,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                _staggered(
                  3,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthFieldLabel(l10n.registerPhoneLabel),
                      TextFormField(
                        key: const Key('field-phone'),
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          color: BrandColors.cream,
                          fontSize: 14,
                        ),
                        inputFormatters: const [_UkrainianPhoneFormatter()],
                        decoration: _fieldDecor(
                          l10n.registerPhoneLabel,
                          hintText: '+380 XX XXX XX XX',
                          errorText: _serverErrors['phoneNumber'],
                        ),
                        validator: (v) {
                          final trimmed = v?.trim() ?? '';
                          if (trimmed.isEmpty || trimmed == '+380') {
                            return l10n.errPhoneRequired;
                          }
                          if (!_reUkrainianPhone.hasMatch(trimmed)) {
                            return l10n.errPhoneInvalidFormat;
                          }
                          return null;
                        },
                        enabled: !isLoading,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                        onFieldSubmitted: (_) => isLoading ? null : _submit(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          _staggered(4, _buildStep2Buttons(l10n, isLoading)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared sub-builders
  // ---------------------------------------------------------------------------

  Widget _buildStep2Buttons(AppLocalizations l10n, bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MochaCtaButton(
          buttonKey: const Key('btn-submit-register'),
          onPressed: isLoading ? null : _submit,
          onTapDown: () => setState(() => _buttonPressed = true),
          onTapUp: () => setState(() => _buttonPressed = false),
          onTapCancel: () => setState(() => _buttonPressed = false),
          isPressed: _buttonPressed,
          isLoading: isLoading,
          label: l10n.registerSubmit,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          key: const Key('btn-back-step'),
          onPressed: isLoading ? null : _retreatStep,
          style: TextButton.styleFrom(foregroundColor: const Color(0xB3FFFFFF)),
          child: Text(l10n.registerBackStep),
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildLoginLinkRow(l10n, isLoading),
      ],
    );
  }

  Widget _buildLoginLinkRow(
    AppLocalizations l10n,
    bool isLoading, {
    bool fromIntent = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          l10n.registerHaveAccount,
          style: const TextStyle(color: Color(0x4DFFFFFF), fontSize: 13),
        ),
        TextButton(
          key: Key(
            fromIntent ? 'btn-go-to-login-from-intent' : 'btn-go-to-login',
          ),
          onPressed: isLoading
              ? null
              : () => context.canPop()
                    ? context.pop()
                    : context.go(RouteNames.login),
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.camel,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          child: Text(l10n.registerSignIn),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _WarmMochaStepIndicator — 3-step progress row
// ---------------------------------------------------------------------------

/// 3-step progress indicator matching sign-up-page.html + done-page.html.
///
/// Step states:
///   done     → camel-tint circle background, camel text, camel connecting line
///   active   → camel filled circle (solid), bright white label
///   inactive → white 15% border circle, dim white label, dim connector
///
/// Maps [currentStep] (0 = step 1 active, 1 = step 2 active) onto 3 visual
/// positions. Steps 1-based in UI: position 1 = Деталі, 2 = Верифікація,
/// 3 = Готово. Position 1 is always at least active; position 2 becomes active
/// when _registrationStep == 1; position 3 is always inactive in this flow.
///
/// Explicit children — no List.generate inside build().
class _WarmMochaStepIndicator extends StatelessWidget {
  const _WarmMochaStepIndicator({
    required this.currentStep,
    required this.l10n,
  });

  final int currentStep;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    // Map: currentStep 0 → uiStep 1 active; currentStep 1 → uiStep 2 active.
    // UI position 3 is always inactive.
    const step1State = _StepState.active;
    final step2State = currentStep >= 1
        ? _StepState.active
        : _StepState.inactive;
    const step3State = _StepState.inactive;

    final connector1Done = currentStep >= 1;

    return Row(
      children: [
        // Step 1 — Деталі
        _StepDot(state: step1State, label: l10n.progressStepDetails, number: 1),
        // Connector 1→2
        _StepConnector(done: connector1Done),
        // Step 2 — Верифікація
        _StepDot(
          state: step2State,
          label: l10n.progressStepVerification,
          number: 2,
        ),
        // Connector 2→3
        const _StepConnector(done: false),
        // Step 3 — Готово
        _StepDot(state: step3State, label: l10n.progressStepDone, number: 3),
      ],
    );
  }
}

/// State enum for a step indicator dot.
enum _StepState { done, active, inactive }

/// A single step dot + label pair.
///
/// done     → camel-tint circle + camel text
/// active   → solid camel circle + bright text
/// inactive → white-border circle + dim text
class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.state,
    required this.label,
    required this.number,
  });

  final _StepState state;
  final String label;
  final int number;

  // Static style constants — allocated once.
  static const _kCircleSize = 22.0;

  static const _kDoneDecoration = BoxDecoration(
    color: Color(0x38B89A7A), // camel 22%
    shape: BoxShape.circle,
  );

  static const _kActiveDecoration = BoxDecoration(
    color: BrandColors.camel,
    shape: BoxShape.circle,
  );

  static const _kInactiveDecoration = BoxDecoration(
    shape: BoxShape.circle,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x26FFFFFF), width: 1.5), // white 15%
    ),
  );

  @override
  Widget build(BuildContext context) {
    final BoxDecoration decoration;
    final TextStyle labelStyle;
    final Widget child;

    switch (state) {
      case _StepState.done:
        decoration = _kDoneDecoration;
        labelStyle = const TextStyle(
          color: Color(0x73FFFFFF),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        );
        child = const Icon(Icons.check, size: 11, color: BrandColors.camel);
      case _StepState.active:
        decoration = _kActiveDecoration;
        labelStyle = const TextStyle(
          color: Color(0xD9FFFFFF),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        );
        child = Text(
          '$number',
          style: const TextStyle(
            color: Color(0xFF3A2810), // prog-color dark
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        );
      case _StepState.inactive:
        decoration = _kInactiveDecoration;
        labelStyle = const TextStyle(
          color: Color(0x33FFFFFF),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
        );
        child = Text(
          '$number',
          style: const TextStyle(
            color: Color(0x33FFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _kCircleSize,
          height: _kCircleSize,
          decoration: decoration,
          alignment: Alignment.center,
          child: child,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(label, style: labelStyle),
      ],
    );
  }
}

/// Horizontal connector line between two step dots.
class _StepConnector extends StatelessWidget {
  const _StepConnector({required this.done});

  final bool done;

  static const _kDoneDecoration = BoxDecoration(
    color: Color(0x40B89A7A), // camel 25%
  );
  static const _kInactiveDecoration = BoxDecoration(
    color: Color(0x14FFFFFF), // white 8%
  );

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      height: 1,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: done ? _kDoneDecoration : _kInactiveDecoration,
    ),
  );
}

// ---------------------------------------------------------------------------
// _RegGlassCard — glassmorphism container (same treatment as login _GlassCard)
// ---------------------------------------------------------------------------

/// Glassmorphism card matching the HTML `.glass-card` used on
/// sign-up-page.html to wrap the step 1 / step 2 form fields.
///
/// background rgba(255,255,255,0.065), border rgba(255,255,255,0.1),
/// border-radius 22px, padding 22 18 20, backdrop-filter blur(20px) ≈ sigma 12.
class _RegGlassCard extends StatelessWidget {
  const _RegGlassCard({required this.child});

  final Widget child;

  static const _kRadius = BorderRadius.all(Radius.circular(22));

  static final _kBlur = ImageFilter.blur(sigmaX: 12, sigmaY: 12);

  static const _kDecoration = BoxDecoration(
    color: Color(0x11FFFFFF), // rgba(255,255,255,0.065)
    borderRadius: _kRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x1AFFFFFF), width: 1), // white 10%
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: _kRadius,
      child: BackdropFilter(
        filter: _kBlur,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
          decoration: _kDecoration,
          child: child,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _Step1Form — PERF MEDIUM-2 isolation boundary (UNCHANGED logic)
// ---------------------------------------------------------------------------

/// Step-1 credential form extracted into its own [StatefulWidget].
///
/// Owning the [Form] widget here confines [AutovalidateMode.onUserInteraction]
/// rebuilds to this small subtree.
class _Step1Form extends StatefulWidget {
  const _Step1Form({
    required this.step1FormKey,
    required this.emailController,
    required this.passwordController,
    required this.serverErrors,
    required this.isLoading,
    required this.opacities,
    required this.slides,
    required this.fieldDecor,
    required this.onNext,
    required this.onNavigateToLogin,
    required this.l10n,
  });

  final GlobalKey<FormState> step1FormKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final Map<String, String> serverErrors;
  final bool isLoading;
  final List<Animation<double>> opacities;
  final List<Animation<Offset>> slides;
  final InputDecoration Function(
    String label, {
    String? errorText,
    Widget? suffixIcon,
    String? hintText,
    Widget? prefixIcon,
  })
  fieldDecor;
  final VoidCallback onNext;
  final VoidCallback onNavigateToLogin;
  final AppLocalizations l10n;

  @override
  State<_Step1Form> createState() => _Step1FormState();
}

class _Step1FormState extends State<_Step1Form> {
  bool _buttonPressed = false;

  Widget _staggered(int index, Widget child) => FadeTransition(
    opacity: widget.opacities[index],
    child: SlideTransition(position: widget.slides[index], child: child),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return Form(
      key: widget.step1FormKey,
      child: Column(
        key: const ValueKey('registration-step-1'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _staggered(
            0,
            Text(
              l10n.registerStep1Title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Glass card wrapping the credential fields (sign-up-page.html
          //    `.glass-card`). Step 1 fields previously sat bare — Defect 1.
          _RegGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _staggered(
                  2,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthFieldLabel(l10n.loginEmailLabel),
                      TextFormField(
                        key: const Key('field-email'),
                        controller: widget.emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(
                          color: BrandColors.cream,
                          fontSize: 14,
                        ),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        decoration: widget.fieldDecor(
                          l10n.loginEmailLabel,
                          errorText: widget.serverErrors['email'],
                          prefixIcon: const Icon(
                            Icons.email_outlined,
                            color: Color(0x40FFFFFF),
                            size: 18,
                          ),
                        ),
                        validator: (v) => validateEmail(v, l10n),
                        enabled: !widget.isLoading,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                      ),
                    ],
                  ),
                ),
                // .field-group { margin-bottom: 14px }
                const SizedBox(height: 14),

                _staggered(
                  3,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AuthFieldLabel(l10n.loginPasswordLabel),
                      _PasswordFieldWithStrength(
                        controller: widget.passwordController,
                        serverError: widget.serverErrors['password'],
                        isLoading: widget.isLoading,
                        fieldDecor: widget.fieldDecor,
                        onSubmit: widget.isLoading ? null : widget.onNext,
                        l10n: l10n,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Next button — mocha gradient
          _staggered(
            4,
            _MochaCtaButton(
              buttonKey: const Key('btn-next-step'),
              onPressed: widget.isLoading ? null : widget.onNext,
              onTapDown: () => setState(() => _buttonPressed = true),
              onTapUp: () => setState(() => _buttonPressed = false),
              onTapCancel: () => setState(() => _buttonPressed = false),
              isPressed: _buttonPressed,
              isLoading: widget.isLoading,
              label: l10n.registerNextStep,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                l10n.registerHaveAccount,
                style: const TextStyle(color: Color(0x4DFFFFFF), fontSize: 13),
              ),
              TextButton(
                key: const Key('btn-go-to-login'),
                onPressed: widget.isLoading ? null : widget.onNavigateToLogin,
                style: TextButton.styleFrom(
                  foregroundColor: BrandColors.camel,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                child: Text(l10n.registerSignIn),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _UkrainianPhoneFormatter (UNCHANGED)
// ---------------------------------------------------------------------------

/// [TextInputFormatter] that enforces a Ukrainian phone number mask.
///
/// Always prefixes with '+380 ' (non-deletable). Accepts only digits after
/// the prefix. Max 13 raw digits total (3 from '380' + 10 more).
class _UkrainianPhoneFormatter extends TextInputFormatter {
  const _UkrainianPhoneFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawDigits = newValue.text.replaceAll(RegExp(r'\D'), '');

    final String digits;
    if (rawDigits.startsWith('380')) {
      digits = rawDigits;
    } else if (rawDigits.startsWith('38')) {
      digits = '3$rawDigits';
    } else if (rawDigits.startsWith('3')) {
      digits = '38$rawDigits';
    } else if (rawDigits.startsWith('0')) {
      digits = '380${rawDigits.substring(1)}';
    } else {
      digits = '380$rawDigits';
    }

    final clamped = digits.length > 13 ? digits.substring(0, 13) : digits;

    final sb = StringBuffer('+');
    for (var i = 0; i < clamped.length; i++) {
      if (i == 3 || i == 5 || i == 8 || i == 10) sb.write(' ');
      sb.write(clamped[i]);
    }

    final formatted = sb.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ---------------------------------------------------------------------------
// _RoleCard — glassmorphism role picker card (WARM MOCHA redesign)
// ---------------------------------------------------------------------------

/// Tappable glassmorphism role card matching role-selection-page.html.
///
/// Unselected: white 5.5% bg, white 8% border, dim icon.
/// Selected: camel 8% bg, camel 42% border, camel icon circle, filled checkmark.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
    required this.l10n,
  });

  final _IntentOption option;
  final bool isSelected;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  static const _kIconSize = 44.0;
  static const _kCheckSize = 22.0;

  // CSS blur(20px) ≈ Flutter sigma ~12 (not 20).
  static final _kBlur = ImageFilter.blur(sigmaX: 12, sigmaY: 12);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: _kRoleCardRadius,
        child: BackdropFilter(
          filter: _kBlur,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0x14B89A7A) // camel 8%
                  : const Color(0x0EFFFFFF), // white 5.5%
              borderRadius: _kRoleCardRadius,
              border: Border.all(
                color: isSelected
                    ? const Color(0x6BB89A7A) // camel 42%
                    : const Color(0x14FFFFFF), // white 8%
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // ── Icon circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _kIconSize,
                  height: _kIconSize,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0x24B89A7A) // camel 14%
                        : const Color(0x12FFFFFF), // white 7%
                    borderRadius: const BorderRadius.all(Radius.circular(13)),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0x59B89A7A) // camel 35%
                          : const Color(0x1AFFFFFF), // white 10%
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    option.materialIcon,
                    size: 22,
                    color: isSelected
                        ? BrandColors.camel
                        : const Color(0x73FFFFFF), // white 45%
                  ),
                ),

                const SizedBox(width: AppSpacing.md),

                // ── Title + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xE0FFFFFF),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.01,
                        ),
                        child: Text(_intentTitle(option, l10n)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _intentDesc(option, l10n),
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0x6BFFFFFF) // white 42%
                              : const Color(0x47FFFFFF), // white 28%
                          fontSize: 11.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.xs),

                // ── Checkmark circle
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _kCheckSize,
                  height: _kCheckSize,
                  decoration: BoxDecoration(
                    color: isSelected ? BrandColors.camel : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? BrandColors.camel
                          : const Color(0x26FFFFFF), // white 15%
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          size: 12,
                          color: Color(0xFF3A2810), // prog-color dark
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SelectedBadge — compact pill showing the selected role (WARM MOCHA)
// ---------------------------------------------------------------------------

/// Compact camel-bordered pill showing the selected intent — tapping returns
/// to Step 0.
///
/// [onTap] is nullable — passing null disables the tap (used on step 2
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

  static const _kDecoration = BoxDecoration(
    color: Color(0x1AB89A7A), // camel 10%
    borderRadius: BorderRadius.all(Radius.circular(24)),
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x66B89A7A), width: 1), // camel 40%
    ),
  );

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: _kDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(option.materialIcon, size: 14, color: BrandColors.camel),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _intentTitle(option, l10n),
            style: const TextStyle(
              color: BrandColors.camel,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.edit_outlined,
              color: Color(0xB3B89A7A), // camel 70%
              size: 14,
            ),
          ],
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// _PasswordFieldWithStrength (UNCHANGED logic, warm mocha decoration)
// ---------------------------------------------------------------------------

/// Password [TextFormField] paired with a [PasswordStrengthIndicator].
///
/// Owns its own [State] so keystrokes on the password field call setState only
/// on this small subtree — never on the root [_RegisterScreenState].
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
  final InputDecoration Function(
    String label, {
    String? errorText,
    Widget? suffixIcon,
    String? hintText,
    Widget? prefixIcon,
  })
  fieldDecor;
  final VoidCallback? onSubmit;
  final AppLocalizations l10n;

  @override
  State<_PasswordFieldWithStrength> createState() =>
      _PasswordFieldWithStrengthState();
}

class _PasswordFieldWithStrengthState
    extends State<_PasswordFieldWithStrength> {
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
          style: const TextStyle(color: BrandColors.cream, fontSize: 14),
          decoration: widget.fieldDecor(
            l10n.loginPasswordLabel,
            errorText: widget.serverError,
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: Color(0x40FFFFFF),
              size: 18,
            ),
            suffixIcon: IconButton(
              key: const Key('btn-toggle-password'),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0x47FFFFFF),
                size: 18,
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

// ---------------------------------------------------------------------------
// _MochaCtaButton — gradient CTA button (same pattern as login_screen.dart)
// ---------------------------------------------------------------------------

/// Gradient CTA button matching the HTML `.cta-btn`:
///   gradient #4A2E10→#6A4A28→#8A6840, height 52px, radius 14px, mocha glow.
///
/// Uses [ElevatedButton] with a transparent background so that the gradient
/// [Ink] decoration is visible. The [Key] is placed on the [ElevatedButton]
/// so that `tester.widget<ElevatedButton>(find.byKey(...))` in tests continues
/// to work.
class _MochaCtaButton extends StatelessWidget {
  const _MochaCtaButton({
    this.buttonKey,
    required this.onPressed,
    required this.onTapDown,
    required this.onTapUp,
    required this.onTapCancel,
    required this.isPressed,
    required this.isLoading,
    required this.label,
  });

  /// Key forwarded to the inner [ElevatedButton] — allows tests to locate and
  /// cast the button via `tester.widget<ElevatedButton>(find.byKey(...))`.
  /// The outer [_MochaCtaButton] wrapper widget is intentionally keyless so
  /// that `find.byKey` returns exactly one result.
  final Key? buttonKey;
  final VoidCallback? onPressed;
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;
  final bool isPressed;
  final bool isLoading;
  final String label;

  static final _kButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.transparent,
    foregroundColor: Colors.white,
    disabledBackgroundColor: const Color(0xFF3A2810),
    disabledForegroundColor: const Color(0x80FFFFFF),
    minimumSize: const Size(double.infinity, 52),
    shape: const RoundedRectangleBorder(borderRadius: _kCtaRadius),
    elevation: 0,
    shadowColor: Colors.transparent,
    padding: EdgeInsets.zero,
  );

  static const _kGradientDecoration = BoxDecoration(
    gradient: _kCtaGradient,
    borderRadius: _kCtaRadius,
    boxShadow: _kCtaShadow,
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: onTapCancel,
      child: AnimatedScale(
        scale: isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Ink(
          decoration: onPressed != null
              ? _kGradientDecoration
              : const BoxDecoration(),
          child: ElevatedButton(
            key: buttonKey,
            onPressed: onPressed,
            style: _kButtonStyle,
            child: isLoading
                ? const SizedBox(
                    width: AppSpacing.md,
                    height: AppSpacing.md,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: BrandColors.cream,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RegBrandRow — monogram B + BEAUTICA (register screen variant)
// ---------------------------------------------------------------------------

/// Brand row for the register screen — identical pattern to login screen's
/// _BrandRow but declared separately to avoid cross-file coupling.
class _RegBrandRow extends StatelessWidget {
  const _RegBrandRow({super.key});

  static final _kBlur = ImageFilter.blur(sigmaX: 8, sigmaY: 8);

  static const _kMonogramDecoration = BoxDecoration(
    color: Color(0x1AFFFFFF),
    borderRadius: BorderRadius.all(Radius.circular(10)),
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x33FFFFFF), width: 1),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: BackdropFilter(
            filter: _kBlur,
            child: Container(
              width: 34,
              height: 34,
              decoration: _kMonogramDecoration,
              alignment: Alignment.center,
              child: const Text(
                'B',
                style: TextStyle(
                  color: Color(0xF2FFFFFF),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        const Text(
          'BEAUTICA',
          style: TextStyle(
            color: Color(0xEBFFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _RegisterHeadlineBlock — role picker headline
// ---------------------------------------------------------------------------

/// Headline block for the role picker step matching role-selection-page.html.
///
/// Main headline: Manrope 700, 26 sp, white.
/// Italic accent: Cormorant Garamond italic 600, camel.
/// Sub-text: 13 sp, white 35%.
class _RegisterHeadlineBlock extends StatelessWidget {
  const _RegisterHeadlineBlock({required this.l10n});

  final AppLocalizations l10n;

  static final _kAccentStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.camel,
      fontSize: 30,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      height: 1.22,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: '${l10n.registerHeadline}\n',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              height: 1.22,
            ),
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Text(l10n.registerHeadlineAccent, style: _kAccentStyle),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.registerSubText,
          style: const TextStyle(
            color: Color(0x59FFFFFF), // white 35%
            fontSize: 13,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}
