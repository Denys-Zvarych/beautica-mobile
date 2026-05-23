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
//   - Navigator.popUntil → context.go(RouteNames.home) via router redirect
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
import 'package:screen_protector/screen_protector.dart';

import '../../../core/errors/failures.dart';
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

  /// Password policy rules — 12-char min for the invite path.
  late final List<PasswordRule> _rules = passwordRules(minLength: 12);

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  // ── Validation helpers ────────────────────────────────────────────────

  bool get _passwordMeetsRules => _rules.every((r) => r.test(_passwordValue));

  bool get _formValid =>
      _passwordMeetsRules &&
      _firstNameValue.trim().isNotEmpty &&
      _lastNameValue.trim().isNotEmpty;

  // ── Action ────────────────────────────────────────────────────────────

  Future<void> _accept() async {
    if (_loading || !_formValid) return;

    setState(() {
      _loading = true;
      _inlineError = null;
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
        final message = e is Failure ? e.userMessage(context) : l10n.errUnknown;
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
            onChanged: (String v) => setState(() => _passwordValue = v),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          // Invite path requires a 12-character minimum (vs 8 for self-register).
          PasswordChecklist(value: _passwordValue, rules: _rules),
          const SizedBox(height: VelvetSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: NeumorphicTextField(
                  key: const ValueKey<String>('invite_first_name'),
                  label: l10n.inviteFirstNameLabel,
                  controller: _firstName,
                  hintText: 'Марія',
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  autofillHints: const <String>[AutofillHints.givenName],
                  enabled: !_loading,
                  onChanged: (String v) => setState(() => _firstNameValue = v),
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: NeumorphicTextField(
                  key: const ValueKey<String>('invite_last_name'),
                  label: l10n.inviteLastNameLabel,
                  controller: _lastName,
                  hintText: 'Бондар',
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  autofillHints: const <String>[AutofillHints.familyName],
                  enabled: !_loading,
                  onChanged: (String v) => setState(() => _lastNameValue = v),
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
            maxLength: 20,
            prefixIcon: const Icon(Icons.phone_outlined),
            helperText: l10n.invitePhoneHelper,
            enabled: !_loading,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[\+\d\s\-\(\)]')),
            ],
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
