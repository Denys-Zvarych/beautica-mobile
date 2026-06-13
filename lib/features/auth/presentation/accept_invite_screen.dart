// Phase 2.20 — Accept Invite screen — VelvetTouch design.
//
// SOURCE OF TRUTH:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/accept_invite_screen.dart
//
// Adaptations from the design source:
//   - StatefulWidget → ConsumerStatefulWidget + ConsumerState<AcceptInviteScreen>
//   - Constructor param: final String token (not pre-filled email/role/expiry)
//   - Reads acceptInviteProvider(token) for validate; branches on AsyncValue
//   - On accept: calls ref.read(authProvider.notifier).acceptInvite(...)
//   - AuthRole enum → UserRole + UserRoleL10n extension
//   - popUntil migrated to context.go(RouteNames.home) via router redirect
//   - VelvetColors.* → BrandColors.*; VelvetText.*/VelvetSpacing.* unchanged
//   - ScreenProtector lifecycle (screen has password field) — !kDebugMode guarded
//   - All strings via AppLocalizations (both UA + EN ARB keys added Phase 2.20)
//   - ValueKey<String> on all interactive widgets
//
// No BackdropFilter, no glassmorphism, no AuthGradientBackground.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../shared/formatters/ua_phone_input_formatter.dart';
import '../../../shared/validators/name_validator.dart';
import '../../../shared/validators/phone_validator.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/user_role.dart';
import '../state/accept_invite_notifier.dart';
import 'auth_notifier.dart';
import 'user_role_l10n.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/password_checklist.dart';

/// Accept-invite screen — Phase 2.20.
///
/// [token] is the single-use invite token parsed from the `?token=` query
/// parameter by the router. The screen validates it on mount (via
/// [acceptInviteProvider]) and shows a form for the invited user to set
/// their password and enter their name. On success, [AuthNotifier.acceptInvite]
/// transitions the session to [Authenticated] and the router guard forwards
/// to the home shell automatically.
class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key, required this.token});

  /// Single-use invite token from the emailed deep link.
  final String token;

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  String _passwordValue = '';
  String _firstNameValue = '';
  String _lastNameValue = '';
  String? _inlineError;
  bool _loading = false;

  /// True once the user tapped Accept at least once — surfaces the client-side
  /// name/phone validators inline (not before the first submit attempt).
  bool _submitted = false;

  /// Server-side field errors from the last [ValidationFailure], keyed by the
  /// backend field name (firstName / lastName / phone / password). Cleared when
  /// the user edits the corresponding field.
  Map<String, String> _fieldErrors = const <String, String>{};

  /// Password policy rules — 12-char min for the invite path.
  /// Initialised in [didChangeDependencies] so AppLocalizations is available.
  List<PasswordRule>? _rules;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rules ??= passwordRules(AppLocalizations.of(context), minLength: 12);
  }

  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws. Hold the keepAlive manager instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot guard via the app-wide manager (single
    // owner of the native toggle; internally !kDebugMode-guarded).
    // MASVS-PLATFORM MS6 (MEDIUM-2, Phase 2.20 audit): FLAG_SECURE takes effect
    // at onWindowFocusChanged, not at the Dart frame boundary. This is the same
    // accepted one-frame gap on all PII auth screens in this codebase.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  // ── Validation helpers ────────────────────────────────────────────────

  // _rules is guaranteed non-null after didChangeDependencies runs.
  bool get _passwordMeetsRules => _rules!.every((r) => r.test(_passwordValue));

  bool get _formValid =>
      _passwordMeetsRules &&
      _firstNameValue.trim().isNotEmpty &&
      _lastNameValue.trim().isNotEmpty;

  /// Inline first-name error: server error first, then client validator
  /// (non-blank + max-length 100), only after the first submit attempt.
  String? _firstNameError(AppLocalizations l10n) {
    final serverErr = _fieldErrors['firstName'];
    if (serverErr != null) return serverErr;
    if (!_submitted) return null;
    return validateName(_firstName.text, l10n);
  }

  /// Inline last-name error: server error first, then client validator.
  String? _lastNameError(AppLocalizations l10n) {
    final serverErr = _fieldErrors['lastName'];
    if (serverErr != null) return serverErr;
    if (!_submitted) return null;
    return validateName(_lastName.text, l10n);
  }

  /// Inline phone error: server error first, then client format validator. The
  /// phone is OPTIONAL — an empty value is valid and skips format validation.
  String? _phoneError(AppLocalizations l10n) {
    final serverErr = _fieldErrors['phone'] ?? _fieldErrors['phoneNumber'];
    if (serverErr != null) return serverErr;
    if (!_submitted) return null;
    if (_phone.text.trim().isEmpty) return null; // optional
    return validatePhone(_phone.text.trim(), l10n);
  }

  /// Inline password error from the server (the client checklist already
  /// enforces the policy live, so there is no client validator here).
  String? get _passwordServerError => _fieldErrors['password'];

  void _clearServerError(String key) {
    if (_fieldErrors.containsKey(key)) {
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(
          Map<String, String>.from(_fieldErrors)..remove(key),
        );
      });
    }
  }

  // ── Action ────────────────────────────────────────────────────────────

  Future<void> _accept() async {
    if (_loading || !_formValid) return;

    final l10n = AppLocalizations.of(context);

    // Client-side validation before the network call. Names: non-blank +
    // max-length 100. Phone: OPTIONAL — empty is valid; a non-empty value must
    // match the Ukrainian phone format. Surfaced inline via the *Error getters.
    setState(() => _submitted = true);
    final bool clientInvalid =
        validateName(_firstName.text, l10n) != null ||
        validateName(_lastName.text, l10n) != null ||
        (_phone.text.trim().isNotEmpty &&
            validatePhone(_phone.text.trim(), l10n) != null);
    if (clientInvalid) {
      setState(() {});
      return;
    }

    setState(() {
      _loading = true;
      _inlineError = null;
      _fieldErrors = const <String, String>{};
    });

    await ref
        .read(authProvider.notifier)
        .acceptInvite(
          token: widget.token,
          password: _password.text,
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
          phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        );

    if (!mounted) return;

    final authState = ref.read(authProvider);
    authState.when(
      data: (_) {
        // Session is now Authenticated — the router redirect forwards to /home.
        // Show a snackbar as a positive confirmation before the transition.
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.inviteSuccessSnackbar)));
        if (kDebugMode) {
          log(
            'Accept-invite: success — routing to home',
            name: 'auth.invite',
            level: 800,
          );
        }
      },
      loading: () {
        // Defensive — should not happen immediately after await.
      },
      error: (e, _) {
        final l10n = AppLocalizations.of(context);
        // A ValidationFailure with field errors maps onto each field's inline
        // errorText (firstName / lastName / phone / password) instead of
        // collapsing to a single banner. The banner is kept only as the
        // fallback for an empty field map (serverMessage → generic) or any
        // non-validation failure.
        if (e is ValidationFailure && e.fieldErrors.isNotEmpty) {
          setState(() {
            _loading = false;
            _fieldErrors = Map<String, String>.unmodifiable(e.fieldErrors);
            _inlineError = null;
          });
          return;
        }
        final String message;
        if (e is ValidationFailure) {
          final serverMessage = e.serverMessage?.trim();
          message = (serverMessage != null && serverMessage.isNotEmpty)
              ? serverMessage
              : l10n.errValidation;
        } else {
          message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
        }
        setState(() {
          _loading = false;
          _inlineError = message;
        });
      },
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inviteAsync = ref.watch(acceptInviteProvider(widget.token));

    return inviteAsync.when(
      loading: () => AuthScaffold(
        showBack: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const VelvetHeader(),
            Text(l10n.inviteHeading, style: VelvetText.heading()),
            const SizedBox(height: VelvetSpacing.lg),
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
      error: (e, _) => AuthScaffold(
        showBack: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const VelvetHeader(),
            Text(l10n.inviteHeading, style: VelvetText.heading()),
            const SizedBox(height: VelvetSpacing.lg),
            AuthBanner(
              icon: Icons.error_outline_rounded,
              message: l10n.inviteInvalidError,
              color: BrandColors.error,
            ),
          ],
        ),
      ),
      data: (invite) =>
          _buildForm(l10n, invite.email, invite.role, invite.expiresInHours),
    );
  }

  Widget _buildForm(
    AppLocalizations l10n,
    String email,
    UserRole role,
    int expiresInHours,
  ) {
    return AuthScaffold(
      showBack: false,
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('invite_accept'),
        label: l10n.inviteAcceptCta,
        icon: Icons.group_add_rounded,
        loading: _loading,
        onPressed: (_formValid && !_loading) ? _accept : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const VelvetHeader(),
          Text(l10n.inviteHeading, style: VelvetText.heading()),
          const SizedBox(height: VelvetSpacing.sm),
          Text(l10n.inviteSubtitle, style: VelvetText.body()),
          const SizedBox(height: VelvetSpacing.lg),
          _InvitePreview(
            email: email,
            role: role,
            expiresInHours: expiresInHours,
            l10n: l10n,
          ),
          const SizedBox(height: VelvetSpacing.xl),
          NeumorphicTextField(
            key: const ValueKey<String>('invite_password'),
            label: l10n.invitePasswordLabel,
            controller: _password,
            hintText: '••••••••••••',
            obscureToggle: true,
            maxLength: 128,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            autofillHints: const <String>[AutofillHints.newPassword],
            enabled: !_loading,
            errorText: _passwordServerError,
            onChanged: (String v) {
              _clearServerError('password');
              setState(() => _passwordValue = v);
            },
          ),
          const SizedBox(height: VelvetSpacing.sm),
          // Invite path requires a 12-character minimum (vs 8 for self-register).
          // _rules is guaranteed non-null after didChangeDependencies runs.
          PasswordChecklist(value: _passwordValue, rules: _rules!),
          const SizedBox(height: VelvetSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: NeumorphicTextField(
                  key: const ValueKey<String>('invite_first_name'),
                  label: l10n.inviteFirstNameLabel,
                  controller: _firstName,
                  hintText: l10n.registerFirstNamePlaceholder,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  autofillHints: const <String>[AutofillHints.givenName],
                  enabled: !_loading,
                  errorText: _firstNameError(l10n),
                  onChanged: (String v) {
                    _clearServerError('firstName');
                    setState(() => _firstNameValue = v);
                  },
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: NeumorphicTextField(
                  key: const ValueKey<String>('invite_last_name'),
                  label: l10n.inviteLastNameLabel,
                  controller: _lastName,
                  hintText: l10n.registerLastNamePlaceholder,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  autofillHints: const <String>[AutofillHints.familyName],
                  enabled: !_loading,
                  errorText: _lastNameError(l10n),
                  onChanged: (String v) {
                    _clearServerError('lastName');
                    setState(() => _lastNameValue = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md),
          NeumorphicTextField(
            key: const ValueKey<String>('invite_phone'),
            label: l10n.invitePhoneLabel,
            controller: _phone,
            hintText: '+380 XX XXX XX XX',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            maxLength: 17,
            prefixIcon: const Icon(Icons.phone_outlined),
            helperText: l10n.invitePhoneHelper,
            enabled: !_loading,
            errorText: _phoneError(l10n),
            inputFormatters: const <TextInputFormatter>[
              UaPhoneInputFormatter(),
            ],
            onChanged: (String v) {
              _clearServerError('phone');
              _clearServerError('phoneNumber');
              if (_submitted) setState(() {});
            },
            onSubmitted: (!_loading && _formValid) ? (_) => _accept() : null,
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
}

/// Read-only summary of the invitation: the locked email, the assigned role
/// and the expiry window. Rendered as an inset well so it reads as "fixed,
/// not editable".
class _InvitePreview extends StatelessWidget {
  const _InvitePreview({
    required this.email,
    required this.role,
    required this.expiresInHours,
    required this.l10n,
  });

  final String email;
  final UserRole role;
  final int expiresInHours;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return NeumorphicInset(
      radius: VelvetRadii.card,
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.md + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _row(Icons.alternate_email_rounded, l10n.inviteEmailLabel, email),
            const SizedBox(height: VelvetSpacing.md),
            _row(role.icon, l10n.inviteRoleLabel, role.label(l10n)),
            const SizedBox(height: VelvetSpacing.md),
            _row(
              Icons.schedule_rounded,
              l10n.inviteExpiresLabel,
              l10n.inviteExpiresValue(expiresInHours),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 20, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: VelvetText.label()),
              const SizedBox(height: 2),
              Text(value, style: VelvetText.bodyStrong()),
            ],
          ),
        ),
      ],
    );
  }
}
