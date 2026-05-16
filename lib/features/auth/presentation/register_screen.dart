// Register screen — Warm Mocha visual parity rebuild (Phase 2.x).
//
// SOURCE OF TRUTH: docs/signup-designs/role-selection-page.html and
// docs/signup-designs/sign-up-page.html. Every visible element, copy string,
// font, colour, gradient, spacing and icon is transcribed literally from
// those two files (literal CSS px / hex values, NOT AppSpacing/BrandColors
// tokens, per the parity directive — token snapping previously caused pixel
// drift on these screens).
//
// Two views, one screen:
//   • Role selection (role-selection-page.html) — three glassmorphism role
//     cards. Tapping a card ONLY selects it (sets _selectedRole). Advancing
//     to the form REQUIRES pressing the always-filled "Продовжити" CTA.
//   • Registration details (sign-up-page.html) — a SINGLE screen with all
//     fields (Ім'я, Прізвище, Електронна пошта, Телефон, Пароль; salon owners
//     additionally get Назва салону / Адреса салону in the same card). A
//     display-only 3-step progress row (Деталі / Верифікація / Готово), the
//     "Welcome to Premium / beauty services" headline, a 3-criteria password
//     helper row, the terms line, and the "Вже є акаунт? Увійти" row.
//
// Verification/Done are FUTURE phases — the progress row past step 1 is
// display-only and submit still calls context.go(RouteNames.home).
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
import '../../../shared/widgets/password_criteria_row.dart';
import '../domain/user_role.dart';
import 'auth_role_icons.dart';
import 'auth_notifier.dart';

// ---------------------------------------------------------------------------
// Phone validation regex — module-level so it is compiled once.
// ---------------------------------------------------------------------------

/// Matches a fully-formatted Ukrainian phone number: +380 XX XXX XX XX.
final RegExp _reUkrainianPhone = RegExp(r'^\+380\s\d{2}\s\d{3}\s\d{2}\s\d{2}$');

// ---------------------------------------------------------------------------
// Static style constants — literal CSS values (NOT tokens), allocated once.
// ---------------------------------------------------------------------------

/// role-selection-page.html .role-card { border-radius: 18px }.
const _kRoleCardRadius = BorderRadius.all(Radius.circular(18));

/// sign-up-page.html input { border-radius: 12px }.
const _kInputRadius = BorderRadius.all(Radius.circular(12));

/// sign-up-page.html .cta-btn { border-radius: 14px }.
const _kCtaRadius = BorderRadius.all(Radius.circular(14));

/// sign-up-page.html .glass-card { border-radius: 22px }.
const _kGlassRadius = BorderRadius.all(Radius.circular(22));

/// input { border: 1px solid rgba(255,255,255,0.1) }.
const _kInputBorderDefault = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x1AFFFFFF), width: 1),
);

/// input:focus { border-color: var(--input-focus) rgba(184,154,122,0.36) }.
const _kInputBorderFocused = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: Color(0x5CB89A7A), width: 1.5),
);

const _kInputBorderError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.errorRust, width: 1),
);

const _kInputBorderFocusedError = OutlineInputBorder(
  borderRadius: _kInputRadius,
  borderSide: BorderSide(color: BrandColors.errorRust, width: 1.5),
);

/// --cta-grad: linear-gradient(135deg, #4a2e10 0%, #6a4a28 60%, #8a6840 100%).
/// Literal hex stops (NOT BrandColors tokens) per parity directive #3.
const _kCtaGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF4A2E10), Color(0xFF6A4A28), Color(0xFF8A6840)],
  stops: [0.0, 0.6, 1.0],
);

/// .cta-btn { box-shadow: 0 4px 24px rgba(58,36,12,0.68) }.
const List<BoxShadow> _kCtaShadow = [
  BoxShadow(color: Color(0xAD3A240C), blurRadius: 24, offset: Offset(0, 4)),
];

// ---------------------------------------------------------------------------
// Intent option data class
// ---------------------------------------------------------------------------

/// Pure data descriptor for a role-selection card.
class _IntentOption {
  const _IntentOption({required this.role, required this.glyph});

  final UserRole role;

  /// Line-art glyph painted to match the role-selection-page.html SVG path.
  final AuthRoleGlyph glyph;
}

/// The three self-registration role options, in role-selection-page.html
/// order: Клієнт, Власник салону, Незалежний майстер.
const List<_IntentOption> _kIntentOptions = [
  _IntentOption(role: UserRole.client, glyph: AuthRoleGlyph.client),
  _IntentOption(role: UserRole.salonOwner, glyph: AuthRoleGlyph.salonOwner),
  _IntentOption(
    role: UserRole.independentMaster,
    glyph: AuthRoleGlyph.independentMaster,
  ),
];

// ---------------------------------------------------------------------------
// L10n helpers
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

/// Register screen — role selection then a single-screen details form.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with TickerProviderStateMixin {
  // ── View state ─────────────────────────────────────────────────────────
  //
  // _showDetails == false → role-selection view.
  // _showDetails == true  → single-screen registration details form.
  bool _showDetails = false;

  /// Null until the user picks a role. Selecting a card sets this; it does
  /// NOT advance the view (that requires the "Продовжити" CTA).
  UserRole? _selectedRole;

  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _businessNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _buttonPressed = false;
  bool _ctaPressed = false;

  Map<String, String> _serverErrors = const {};

  // ── Entrance animation — role cards (3 items, 500 ms) ──────────────────
  late final AnimationController _intentCtrl;
  late final List<Animation<double>> _intentOpacities;
  late final List<Animation<Offset>> _intentSlides;

  Widget _intentStaggered(int index, Widget child) => FadeTransition(
    opacity: _intentOpacities[index],
    child: SlideTransition(position: _intentSlides[index], child: child),
  );

  // ── Entrance animation — details form (5 items, 600 ms) ────────────────
  late final AnimationController _entranceCtrl;
  late final List<Animation<double>> _opacities;
  late final List<Animation<Offset>> _slides;

  Widget _staggered(int index, Widget child) => FadeTransition(
    opacity: _opacities[index],
    child: SlideTransition(position: _slides[index], child: child),
  );

  @override
  void initState() {
    super.initState();

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
              (i * 0.1).clamp(0.0, 1.0),
              (i * 0.1 + 0.5).clamp(0.0, 1.0),
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
              (i * 0.1).clamp(0.0, 1.0),
              (i * 0.1 + 0.5).clamp(0.0, 1.0),
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
    _intentCtrl.dispose();
    _entranceCtrl.dispose();
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

  // ── Role selection ─────────────────────────────────────────────────────

  /// Card tap → select ONLY. Does not advance (parity directive: advancing
  /// requires the "Продовжити" CTA).
  void _selectRole(UserRole role) {
    setState(() => _selectedRole = role);
    if (kDebugMode) {
      log('Role selected: ${role.toWire}', name: 'auth.register', level: 800);
    }
  }

  /// "Продовжити" CTA → advance to the single-screen details form.
  void _continueToDetails() {
    if (_selectedRole == null) return;
    setState(() => _showDetails = true);
    _entranceCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _entranceCtrl.value = 1.0;
    } else {
      _entranceCtrl.forward();
    }
  }

  void _backToRoleSelection() {
    setState(() => _showDetails = false);
    _intentCtrl.reset();
    if (MediaQuery.of(context).disableAnimations) {
      _intentCtrl.value = 1.0;
    } else {
      _intentCtrl.forward();
    }
  }

  // ── Submit ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    setState(() => _serverErrors = const {});

    final role = _selectedRole;
    if (role == null) return;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final isSalon = role == UserRole.salonOwner;

    await ref
        .read(authProvider.notifier)
        .register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
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
        // Verification/done are future phases — keep the existing path.
        context.go(RouteNames.home);
      },
      loading: () {},
      error: (e, _) {
        if (e is ValidationFailure && e.fieldErrors.isNotEmpty) {
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
        backgroundColor: BrandColors.errorRust,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppSpacing.sm)),
        ),
      ),
    );
  }

  // ── Field decoration — sign-up-page.html input rules ───────────────────

  InputDecoration _fieldDecor(
    String placeholder, {
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) => InputDecoration(
    hintText: placeholder,
    errorText: errorText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    // input { background: rgba(255,255,255,0.07) }.
    fillColor: const Color(0x12FFFFFF),
    // input::placeholder { color: rgba(255,255,255,0.18) }.
    hintStyle: const TextStyle(color: Color(0x2EFFFFFF)),
    errorStyle: const TextStyle(color: BrandColors.errorRust, fontSize: 11),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: _kInputBorderDefault,
    enabledBorder: _kInputBorderDefault,
    focusedBorder: _kInputBorderFocused,
    errorBorder: _kInputBorderError,
    focusedErrorBorder: _kInputBorderFocusedError,
    isDense: true,
  );

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Shared top geometry — identical to login so the brand row never
          // jumps when switching between screens / views.
          const SizedBox(height: 24),
          const _RegBrandRow(key: Key('brand-row')),
          const SizedBox(height: 36),
          _showDetails
              ? _buildDetailsView(context, l10n, isLoading)
              : _buildRoleSelectionView(context, l10n),
        ],
      ),
    );
  }

  // ── Role-selection view (role-selection-page.html) ─────────────────────

  Widget _buildRoleSelectionView(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // .headline + .sub-text block.
        _intentStaggered(0, _RoleHeadlineBlock(l10n: l10n)),

        // .screen-header padding-bottom 20 + .roles-list start.
        const SizedBox(height: 20),

        // .roles-list { gap: 12px; padding: 0 14px }.
        _RoleSelectionField(
          // The role picker is the screen's primary interactive surface;
          // keyed `field-role` for widget tests (parity directive).
          key: const Key('field-role'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _intentStaggered(
                0,
                _RoleCard(
                  option: _kIntentOptions[0],
                  isSelected: _selectedRole == _kIntentOptions[0].role,
                  onTap: () => _selectRole(_kIntentOptions[0].role),
                  l10n: l10n,
                ),
              ),
              const SizedBox(height: 12),
              _intentStaggered(
                1,
                _RoleCard(
                  option: _kIntentOptions[1],
                  isSelected: _selectedRole == _kIntentOptions[1].role,
                  onTap: () => _selectRole(_kIntentOptions[1].role),
                  l10n: l10n,
                ),
              ),
              const SizedBox(height: 12),
              _intentStaggered(
                2,
                _RoleCard(
                  option: _kIntentOptions[2],
                  isSelected: _selectedRole == _kIntentOptions[2].role,
                  onTap: () => _selectRole(_kIntentOptions[2].role),
                  l10n: l10n,
                ),
              ),
            ],
          ),
        ),

        // .roles-list { margin-bottom: 20px }.
        const SizedBox(height: 20),

        // .cta-wrap > .cta-btn — ALWAYS the mocha gradient (the design has
        // no disabled/empty state). Pressing it requires a selected role.
        _intentStaggered(
          2,
          _MochaCtaButton(
            buttonKey: const Key('btn-continue-role'),
            onPressed: _selectedRole != null ? _continueToDetails : null,
            onTapDown: () => setState(() => _ctaPressed = true),
            onTapUp: () => setState(() => _ctaPressed = false),
            onTapCancel: () => setState(() => _ctaPressed = false),
            isPressed: _ctaPressed,
            isLoading: false,
            label: l10n.registerContinue,
          ),
        ),

        // .login-row { margin-top: 20px }.
        const SizedBox(height: 20),
        _intentStaggered(
          2,
          _LoginLinkRow(
            l10n: l10n,
            fromIntent: true,
            onTap: () =>
                context.canPop() ? context.pop() : context.go(RouteNames.login),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Single-screen registration details (sign-up-page.html) ─────────────

  Widget _buildDetailsView(
    BuildContext context,
    AppLocalizations l10n,
    bool isLoading,
  ) {
    final role = _selectedRole;
    if (role == null) return const SizedBox.shrink();
    final isSalon = role == UserRole.salonOwner;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .headline + .progress-row block.
          _staggered(0, _DetailsHeadlineBlock(l10n: l10n)),

          // .progress-row { margin-top: 36px }.
          const SizedBox(height: 36),
          _staggered(0, _ProgressRow(l10n: l10n)),

          // .screen-header padding-bottom 20 → glass-card start.
          const SizedBox(height: 20),

          _staggered(
            1,
            _RegGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isSalon) ...[
                    _LabeledField(
                      label: l10n.registerBusinessNameLabel,
                      child: TextFormField(
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
                          prefixIcon: const _FieldIcon(
                            icon: Icons.storefront_outlined,
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? l10n.errNameRequired
                            : null,
                        enabled: !isLoading,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _LabeledField(
                      label: l10n.registerAddressLabel,
                      child: TextFormField(
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
                          prefixIcon: const _FieldIcon(
                            icon: Icons.location_on_outlined,
                          ),
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
                    const SizedBox(height: 14),
                  ],

                  // .row-2 { display:grid; grid-template-columns:1fr 1fr;
                  //          gap:10px }  — Ім'я / Прізвище.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _LabeledField(
                          label: l10n.firstNameLabel,
                          child: TextFormField(
                            key: const Key('field-firstName'),
                            controller: _firstNameController,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(
                              color: BrandColors.cream,
                              fontSize: 14,
                            ),
                            decoration: _fieldDecor(
                              l10n.registerFirstNamePlaceholder,
                              errorText: _serverErrors['firstName'],
                              prefixIcon: const _FieldIcon(
                                icon: Icons.person_outline,
                              ),
                            ),
                            validator: (v) => validateName(v, l10n),
                            enabled: !isLoading,
                            autocorrect: false,
                            enableIMEPersonalizedLearning: false,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _LabeledField(
                          label: l10n.lastNameLabel,
                          child: TextFormField(
                            key: const Key('field-lastName'),
                            controller: _lastNameController,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(
                              color: BrandColors.cream,
                              fontSize: 14,
                            ),
                            decoration: _fieldDecor(
                              l10n.registerLastNamePlaceholder,
                              errorText: _serverErrors['lastName'],
                              prefixIcon: const _FieldIcon(
                                icon: Icons.person_outline,
                              ),
                            ),
                            validator: (v) => validateName(v, l10n),
                            enabled: !isLoading,
                            autocorrect: false,
                            enableIMEPersonalizedLearning: false,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // .field-group { margin-bottom: 14px }.
                  const SizedBox(height: 14),

                  // Електронна пошта.
                  _LabeledField(
                    label: l10n.loginEmailLabel,
                    child: TextFormField(
                      key: const Key('field-email'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        color: BrandColors.cream,
                        fontSize: 14,
                      ),
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      decoration: _fieldDecor(
                        l10n.registerEmailPlaceholder,
                        errorText: _serverErrors['email'],
                        prefixIcon: const _FieldIcon(icon: Icons.mail_outline),
                      ),
                      validator: (v) => validateEmail(v, l10n),
                      enabled: !isLoading,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Телефон.
                  _LabeledField(
                    label: l10n.registerPhoneLabel,
                    child: TextFormField(
                      key: const Key('field-phone'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(
                        color: BrandColors.cream,
                        fontSize: 14,
                      ),
                      inputFormatters: const [_UkrainianPhoneFormatter()],
                      decoration: _fieldDecor(
                        l10n.registerPhonePlaceholder,
                        errorText: _serverErrors['phoneNumber'],
                        prefixIcon: const _FieldIcon(
                          icon: Icons.phone_iphone_outlined,
                        ),
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
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Пароль + 3-criteria helper row.
                  _LabeledField(
                    label: l10n.loginPasswordLabel,
                    child: _PasswordFieldWithCriteria(
                      controller: _passwordController,
                      serverError: _serverErrors['password'],
                      isLoading: isLoading,
                      fieldDecor: _fieldDecor,
                      onSubmit: isLoading ? null : _submit,
                      l10n: l10n,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // .cta-btn { margin-top: 8px } (outside the glass card here for
          // the same vertical rhythm as the rest of the auth surface).
          const SizedBox(height: 16),

          _staggered(
            3,
            _MochaCtaButton(
              buttonKey: const Key('btn-submit-register'),
              onPressed: isLoading ? null : _submit,
              onTapDown: () => setState(() => _buttonPressed = true),
              onTapUp: () => setState(() => _buttonPressed = false),
              onTapCancel: () => setState(() => _buttonPressed = false),
              isPressed: _buttonPressed,
              isLoading: isLoading,
              label: l10n.registerContinue,
            ),
          ),

          // .terms { margin-top: 12px }.
          const SizedBox(height: 12),
          _staggered(4, _TermsLine(l10n: l10n)),

          // Back to role selection — preserves the chosen role's data.
          const SizedBox(height: 8),
          _staggered(
            4,
            TextButton(
              key: const Key('btn-back-step'),
              onPressed: isLoading ? null : _backToRoleSelection,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xB3FFFFFF),
              ),
              child: Text(l10n.registerBackStep),
            ),
          ),

          // .login-row { margin-top: 20px }.
          const SizedBox(height: 12),
          _staggered(
            4,
            _LoginLinkRow(
              l10n: l10n,
              fromIntent: false,
              onTap: isLoading
                  ? null
                  : () => context.canPop()
                        ? context.pop()
                        : context.go(RouteNames.login),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RoleSelectionField — keyed wrapper so `field-role` resolves in tests
// ---------------------------------------------------------------------------

/// Thin keyed wrapper around the three role cards. The role picker is the
/// register screen's primary "field"; widget tests reference it via the
/// `field-role` [Key].
class _RoleSelectionField extends StatelessWidget {
  const _RoleSelectionField({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

// ---------------------------------------------------------------------------
// _LabeledField — uppercase label + 6px gap + field (sign-up-page.html label)
// ---------------------------------------------------------------------------

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [AuthFieldLabel(label), child],
  );
}

// ---------------------------------------------------------------------------
// _FieldIcon — left prefix icon (sign-up-page.html .input-icon)
// ---------------------------------------------------------------------------

/// sign-up-page.html .input-icon { color: rgba(255,255,255,0.25) } and
/// .input-icon svg { width:15px; height:15px }. Rendered at 18 to keep a
/// comfortable hit/visual size; colour matched literally.
class _FieldIcon extends StatelessWidget {
  const _FieldIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(
    icon,
    color: const Color(0x40FFFFFF), // white ~25%
    size: 18,
  );
}

// ---------------------------------------------------------------------------
// _ProgressRow — display-only 3-step indicator (sign-up-page.html)
// ---------------------------------------------------------------------------

/// sign-up-page.html .progress-row. Display-only: step 1 (Деталі) active,
/// steps 2 (Верифікація) and 3 (Готово) inactive — Verification/Done are
/// future phases. Wrapped in one merged [Semantics] node so a screen reader
/// announces "Step 1 of 3: Details" instead of six loose fragments.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          '${l10n.progressStepDetails} '
          '(1/3) · ${l10n.progressStepVerification} · '
          '${l10n.progressStepDone}',
      excludeSemantics: true,
      child: Row(
        children: [
          _ProgressItem(
            number: 1,
            label: l10n.progressStepDetails,
            active: true,
          ),
          const _ProgressLine(),
          _ProgressItem(
            number: 2,
            label: l10n.progressStepVerification,
            active: false,
          ),
          const _ProgressLine(),
          _ProgressItem(number: 3, label: l10n.progressStepDone, active: false),
        ],
      ),
    );
  }
}

/// sign-up-page.html .prog-item — a 22px numbered circle + uppercase label.
class _ProgressItem extends StatelessWidget {
  const _ProgressItem({
    required this.number,
    required this.label,
    required this.active,
  });

  final int number;
  final String label;
  final bool active;

  // .prog-item.active .prog-num { background: var(--accent) #b89a7a;
  //   color: var(--prog-color) #3a2810 }.
  static const _kActiveCircle = BoxDecoration(
    color: BrandColors.camel,
    shape: BoxShape.circle,
  );
  // .prog-item.inactive .prog-num { border: 1.5px solid
  //   rgba(255,255,255,0.15); color: rgba(255,255,255,0.2) }.
  static const _kInactiveCircle = BoxDecoration(
    shape: BoxShape.circle,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x26FFFFFF), width: 1.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // .prog-num { width:22px; height:22px; border-radius:50% }.
        Container(
          width: 22,
          height: 22,
          decoration: active ? _kActiveCircle : _kInactiveCircle,
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: TextStyle(
              // active → #3a2810; inactive → rgba(255,255,255,0.2).
              color: active ? const Color(0xFF3A2810) : const Color(0x33FFFFFF),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // .prog-item { gap: 6px }.
        const SizedBox(width: 6),
        // .prog-item { font-size:10px; font-weight:700; text-transform:
        //   uppercase; letter-spacing:0.07em }. active → rgba(255,255,255,
        //   0.85); inactive → rgba(255,255,255,0.2).
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: active ? const Color(0xD9FFFFFF) : const Color(0x33FFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
      ],
    );
  }
}

/// sign-up-page.html .prog-line { flex:1; height:1px;
/// background: rgba(255,255,255,0.08); margin: 0 8px }.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine();

  @override
  Widget build(BuildContext context) => const Expanded(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: ColoredBox(
        color: Color(0x14FFFFFF),
        child: SizedBox(height: 1, width: double.infinity),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// _RegGlassCard — glassmorphism card (sign-up-page.html .glass-card)
// ---------------------------------------------------------------------------

/// sign-up-page.html .glass-card { background: rgba(255,255,255,0.065);
/// border: 1px solid rgba(255,255,255,0.1); border-radius: 22px;
/// padding: 22px 18px 20px; backdrop-filter: blur(20px) }.
class _RegGlassCard extends StatelessWidget {
  const _RegGlassCard({required this.child});

  final Widget child;

  static final _kBlur = ImageFilter.blur(sigmaX: 12, sigmaY: 12);

  static const _kDecoration = BoxDecoration(
    color: Color(0x11FFFFFF), // rgba(255,255,255,0.065)
    borderRadius: _kGlassRadius,
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x1AFFFFFF), width: 1), // white 10%
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: _kGlassRadius,
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
// _UkrainianPhoneFormatter (UNCHANGED logic)
// ---------------------------------------------------------------------------

/// [TextInputFormatter] enforcing a Ukrainian phone mask: always prefixes
/// '+380 ' and accepts only digits after it (max 13 raw digits).
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
// _RoleCard — glassmorphism role picker card (role-selection-page.html)
// ---------------------------------------------------------------------------

/// role-selection-page.html .role-card.
///
/// Unselected: bg rgba(255,255,255,0.055), border rgba(255,255,255,0.08).
/// Selected:   bg rgba(184,154,122,0.08), border rgba(184,154,122,0.42),
///             camel icon circle + filled camel check.
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

  static final _kBlur = ImageFilter.blur(sigmaX: 12, sigmaY: 12);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${_intentTitle(option, l10n)}. ${_intentDesc(option, l10n)}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: _kRoleCardRadius,
          child: BackdropFilter(
            filter: _kBlur,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              // .role-card { padding: 16px 16px }.
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0x14B89A7A) // rgba(184,154,122,0.08)
                    : const Color(0x0EFFFFFF), // rgba(255,255,255,0.055)
                borderRadius: _kRoleCardRadius,
                border: Border.all(
                  color: isSelected
                      ? const Color(0x6BB89A7A) // rgba(184,154,122,0.42)
                      : const Color(0x14FFFFFF), // rgba(255,255,255,0.08)
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // .role-icon { width:44px; height:44px; border-radius:13px }.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0x24B89A7A) // rgba(184,154,122,0.14)
                          : const Color(0x12FFFFFF), // rgba(255,255,255,0.07)
                      borderRadius: const BorderRadius.all(Radius.circular(13)),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0x59B89A7A) // rgba(184,154,122,0.35)
                            : const Color(0x1AFFFFFF), // rgba(255,255,255,0.1)
                        width: 1,
                      ),
                    ),
                    child: AuthRoleIcon(
                      glyph: option.glyph,
                      // .role-icon { color: rgba(255,255,255,0.45) };
                      // .selected .role-icon { color: var(--accent) }.
                      color: isSelected
                          ? BrandColors.camel
                          : const Color(0x73FFFFFF),
                    ),
                  ),

                  // .role-card { gap: 14px }.
                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // .role-title { font-size:14px; font-weight:600;
                        //   color:rgba(255,255,255,0.88) }; selected → #fff.
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xE0FFFFFF),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.14,
                          ),
                          child: Text(_intentTitle(option, l10n)),
                        ),
                        // .role-title { margin-bottom: 3px }.
                        const SizedBox(height: 3),
                        // .role-desc { font-size:11.5px;
                        //   color:rgba(255,255,255,0.28); line-height:1.45 };
                        //   selected → rgba(255,255,255,0.42).
                        Text(
                          _intentDesc(option, l10n),
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0x6BFFFFFF)
                                : const Color(0x47FFFFFF),
                            fontSize: 11.5,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 14),

                  // .role-check { width:22px; height:22px; border-radius:50%;
                  //   border:1.5px solid rgba(255,255,255,0.15) }; selected →
                  //   bg+border var(--accent), check glyph #3a2810.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? BrandColors.camel
                          : Colors.transparent,
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
                            color: Color(0xFF3A2810),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PasswordFieldWithCriteria — password field + 3-criteria helper row
// ---------------------------------------------------------------------------

/// Password [TextFormField] paired with [PasswordCriteriaRow]
/// (sign-up-page.html .helper-row). Owns its own [State] so keystrokes only
/// rebuild this small subtree.
class _PasswordFieldWithCriteria extends StatefulWidget {
  const _PasswordFieldWithCriteria({
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
    String placeholder, {
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  })
  fieldDecor;
  final VoidCallback? onSubmit;
  final AppLocalizations l10n;

  @override
  State<_PasswordFieldWithCriteria> createState() =>
      _PasswordFieldWithCriteriaState();
}

class _PasswordFieldWithCriteriaState
    extends State<_PasswordFieldWithCriteria> {
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
            l10n.registerPasswordPlaceholder,
            errorText: widget.serverError,
            prefixIcon: const _FieldIcon(icon: Icons.lock_outline),
            // sign-up-page.html .pass-toggle (eye icon).
            suffixIcon: IconButton(
              key: const Key('btn-toggle-password'),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0x47FFFFFF), // rgba(255,255,255,0.28)
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
        // sign-up-page.html .helper-row (replaces the old strength bar).
        PasswordCriteriaRow(
          key: const Key('password-criteria-row'),
          password: _currentPassword,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _TermsLine — terms + privacy line (sign-up-page.html .terms)
// ---------------------------------------------------------------------------

/// sign-up-page.html:390 `.terms`:
///   "Реєструючись, ви погоджуєтесь з нашими<br/>
///    <a>Умовами</a> та <a>Політикою конфіденційності</a>"
///
/// font-size 10.5px, colour rgba(255,255,255,0.2), centred, line-height 1.65;
/// links are camel w500. Links are non-functional (future phase) but MUST be
/// present and styled per design (parity directive #2) — they are not greyed.
class _TermsLine extends StatelessWidget {
  const _TermsLine({required this.l10n});

  final AppLocalizations l10n;

  static const _kBase = TextStyle(
    fontSize: 10.5,
    color: Color(0x33FFFFFF), // rgba(255,255,255,0.2)
    height: 1.65,
  );
  static const _kLink = TextStyle(
    fontSize: 10.5,
    color: BrandColors.camel,
    fontWeight: FontWeight.w500,
    height: 1.65,
  );

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: _kBase,
        children: [
          // .terms has an explicit <br/> after the prefix.
          TextSpan(text: '${l10n.registerTermsPrefix}\n'),
          TextSpan(text: l10n.registerTermsTerms, style: _kLink),
          TextSpan(text: l10n.registerTermsConjunction),
          TextSpan(text: l10n.registerTermsPrivacy, style: _kLink),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

// ---------------------------------------------------------------------------
// _LoginLinkRow — "Вже є акаунт? Увійти" (.login-row)
// ---------------------------------------------------------------------------

/// sign-up-page.html / role-selection-page.html .login-row:
///   <p>Вже є акаунт? &nbsp;<a>Увійти</a></p>
/// p → font-size 13px, rgba(255,255,255,0.3); a → camel w600.
class _LoginLinkRow extends StatelessWidget {
  const _LoginLinkRow({
    required this.l10n,
    required this.fromIntent,
    required this.onTap,
  });

  final AppLocalizations l10n;

  /// Distinguishes the role-selection login link (`btn-go-to-login-from-intent`)
  /// from the details-screen one (`btn-go-to-login`) — required by tests.
  final bool fromIntent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: BrandColors.camel,
            disabledForegroundColor: BrandColors.camel,
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
// _MochaCtaButton — gradient CTA with trailing right-arrow
// ---------------------------------------------------------------------------

/// .cta-btn { background: var(--cta-grad); height:52px; border-radius:14px;
/// display:flex; gap:8px } + a trailing right-arrow SVG (M4 9h10M9 4l5 5-5 5).
///
/// The gradient is ALWAYS rendered (the design has no disabled/empty state).
/// When [onPressed] is null the button is non-tappable but keeps the filled
/// mocha look per parity directive — it must not look disabled.
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
    // Keep the filled look even when non-interactive (no disabled state in
    // the design).
    disabledBackgroundColor: Colors.transparent,
    disabledForegroundColor: Colors.white,
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
          // ALWAYS the gradient — no empty BoxDecoration fallback.
          decoration: _kGradientDecoration,
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
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      // .cta-btn { gap: 8px } + trailing arrow SVG.
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward,
                        color: Colors.white,
                        size: 18,
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
// _RegBrandRow — monogram B + BEAUTICA (.brand-row)
// ---------------------------------------------------------------------------

/// role-selection-page.html / sign-up-page.html .brand-row:
/// 34×34 frosted monogram (white 10% bg, white 20% border, blur 8) +
/// "BEAUTICA" uppercase Manrope 700 16px, letter-spacing 0.1em.
class _RegBrandRow extends StatelessWidget {
  const _RegBrandRow({super.key});

  static final _kBlur = ImageFilter.blur(sigmaX: 8, sigmaY: 8);

  static const _kMonogramDecoration = BoxDecoration(
    color: Color(0x1AFFFFFF), // white 10%
    borderRadius: BorderRadius.all(Radius.circular(10)),
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x33FFFFFF), width: 1), // white 20%
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
                  color: Color(0xF2FFFFFF), // white 95%
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        // .brand-row { gap: 10px }.
        const SizedBox(width: 10),
        Text(
          'BEAUTICA',
          style: GoogleFonts.manrope(
            textStyle: const TextStyle(
              color: Color(0xEBFFFFFF), // white 92%
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6, // 0.1em × 16
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _RoleHeadlineBlock — role-selection headline (.headline + .sub-text)
// ---------------------------------------------------------------------------

/// role-selection-page.html:304-305
///   <div class="headline">Ласкаво просимо!<br/><em>Хто ви?</em></div>
///   <p class="sub-text">Оберіть роль, …</p>
/// .headline 26px Manrope 700 #fff; em Cormorant Garamond italic 600 1.15em
/// camel; .sub-text 13px rgba(255,255,255,0.35).
class _RoleHeadlineBlock extends StatelessWidget {
  const _RoleHeadlineBlock({required this.l10n});

  final AppLocalizations l10n;

  static final _kHeadlineStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  );

  static final _kAccentStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.camel,
      fontSize: 30, // 1.15 × 26
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
            style: _kHeadlineStyle,
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Text(l10n.registerHeadlineAccent, style: _kAccentStyle),
              ),
            ],
          ),
        ),
        // .sub-text { margin-top: 10px }.
        const SizedBox(height: 10),
        Text(
          l10n.registerSubText,
          style: GoogleFonts.manrope(
            textStyle: const TextStyle(
              color: Color(0x59FFFFFF), // rgba(255,255,255,0.35)
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _DetailsHeadlineBlock — sign-up-page.html headline (NO sub-text)
// ---------------------------------------------------------------------------

/// sign-up-page.html:334
///   <div class="headline">Welcome to Premium<br/><em>beauty services</em></div>
/// Followed directly by the .progress-row (no .sub-text on this screen).
class _DetailsHeadlineBlock extends StatelessWidget {
  const _DetailsHeadlineBlock({required this.l10n});

  final AppLocalizations l10n;

  static final _kHeadlineStyle = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  );

  static final _kAccentStyle = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.camel,
      fontSize: 30, // 1.15 × 26
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
      height: 1.22,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '${l10n.registerDetailsHeadline}\n',
        style: _kHeadlineStyle,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text(
              l10n.registerDetailsHeadlineAccent,
              style: _kAccentStyle,
            ),
          ),
        ],
      ),
    );
  }
}
