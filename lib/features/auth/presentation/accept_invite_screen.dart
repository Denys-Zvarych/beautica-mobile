// Phase 2.20 — Accept Invite screen — VelvetTouch design.
//
// SOURCE OF TRUTH:
//   docs/signup-designs/VelvetTouchDesign/lib/screens/accept_invite_screen.dart
//   M521 (staff invite by phone): docs/signup-designs/PhoneFirstAuth/lib/
//   screens/invite_screens.dart — phone step -> SMS code ([PhoneCodeStep],
//   M515) -> password + name + consent; the preview card shows the salon and
//   the MASKED invited phone. The preview's three pushed pages are steps of
//   this ONE route here (App Link `/invite/accept?token=` unchanged).
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
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/time/clock_provider.dart';
import '../../../routing/route_names.dart';
import '../../../shared/feedback/show_velvet_snack.dart';
import '../../../shared/formatters/ua_phone_input_formatter.dart';
import '../../../shared/validators/name_validator.dart';
import '../../../shared/validators/password_validator.dart';
import '../../../shared/validators/identifier_classifier.dart';
import '../../../shared/widgets/terms_consent_checkbox.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/invite_details.dart';
import '../domain/user_role.dart';
import '../state/accept_invite_notifier.dart';
import '../state/login_notice_notifier.dart';
import 'auth_notifier.dart';
import 'user_role_l10n.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/password_checklist.dart';
import 'widgets/phone_code_step.dart';

/// The three steps of the phone-matched accept (M521, AUTH-D16) — kept INSIDE
/// the one `/invite/accept?token=` route so the App Link stays unchanged and
/// the single-use registration ticket never travels through the router.
enum _InviteStep { phone, code, details }

/// Accept-invite screen — Phase 2.20, reworked for phone invites by M521.
///
/// [token] is the single-use invite token parsed from the `?token=` query
/// parameter by the router. The screen validates it on mount (via
/// [acceptInviteProvider]) and shows the salon, the masked invited phone, the
/// role and the expiry. The invitee then types the invited phone, confirms it
/// with the M515 SMS-code step ([PhoneCodeStep]; App Check via the M515
/// interceptor), and finally sets password + name + consent. Accept sends the
/// registration ticket (B520, AUTH-52). On success, [AuthNotifier.acceptInvite]
/// transitions the session to [Authenticated] and the router guard forwards
/// to the home shell automatically.
class AcceptInviteScreen extends ConsumerStatefulWidget {
  const AcceptInviteScreen({super.key, required this.token});

  /// Single-use invite token from the SMS link.
  final String token;

  @override
  ConsumerState<AcceptInviteScreen> createState() => _AcceptInviteScreenState();
}

class _AcceptInviteScreenState extends ConsumerState<AcceptInviteScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _phone = TextEditingController();

  _InviteStep _step = _InviteStep.phone;

  // ── Phone + code steps ────────────────────────────────────────────────
  String? _phoneError;
  bool _sending = false;
  String? _codeError;

  /// `+380…` the SMS code went to (set when the send succeeded).
  String? _codePhone;

  /// Single-use B514 registration ticket for [_codePhone]; memory only.
  String? _ticket;

  // ── Details step ──────────────────────────────────────────────────────

  /// Drives ONLY the accept CTA's enabled state (the [PhoneCodeStep]
  /// `_ctaInputs` pattern): a keystroke rebuilds the CTA, not the screen.
  late final Listenable _ctaInputs = Listenable.merge(<Listenable>[
    _password,
    _firstName,
    _lastName,
  ]);

  String? _inlineError;
  bool _loading = false;

  /// Phase 443 — required terms + privacy consent (screen state, D4). The
  /// accept CTA stays disabled until it is ticked; forwarded to
  /// [AuthNotifier.acceptInvite] as `termsAccepted`.
  bool _termsAccepted = false;

  /// True once the user tapped Accept at least once — surfaces the client-side
  /// name validators inline (not before the first submit attempt).
  bool _submitted = false;

  /// Server-side field errors from the last [ValidationFailure], keyed by the
  /// backend field name (firstName / lastName / password). Cleared when the
  /// user edits the corresponding field.
  Map<String, String> _fieldErrors = const <String, String>{};

  /// Password policy rules — same shared policy every other auth form uses
  /// (min 8, ≥1 digit, ≥1 uppercase; see `passwordRules`'s default).
  /// Initialised in [didChangeDependencies] so AppLocalizations is available.
  List<PasswordRule>? _rules;

  /// Cached read-only invite summary. The preview depends only on the invite
  /// and the active locale — none of which change while the user is typing.
  /// Caching the instance lets the element layer skip its subtree on
  /// [setState] rebuilds; it is recreated only when one of
  /// its inputs actually changes (expiry countdown tick, locale switch).
  _InvitePreview? _invitePreview;

  _InvitePreview _previewFor(
    AppLocalizations l10n,
    InviteDetails invite,
    int expiresInHours,
  ) {
    final cached = _invitePreview;
    if (cached != null &&
        cached.phoneMasked == invite.phoneMasked &&
        cached.salonName == invite.salonName &&
        cached.role == invite.role &&
        cached.expiresInHours == expiresInHours &&
        identical(cached.l10n, l10n)) {
      return cached;
    }
    return _invitePreview = _InvitePreview(
      phoneMasked: invite.phoneMasked,
      salonName: invite.salonName,
      role: invite.role,
      expiresInHours: expiresInHours,
      l10n: l10n,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rules ??= passwordRules(AppLocalizations.of(context));
  }

  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws. Hold the keepAlive manager instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted app-switcher / data-leakage guard via the
    // app-wide manager (single owner of the native toggle; internally
    // !kDebugMode-guarded). It does NOT block screenshots — MASVS-PLATFORM MS6
    // (MEDIUM-2, Phase 2.20 audit) cited FLAG_SECURE here, and that half was
    // REVERSED on 2026-08-20 by product decision; see the header of
    // `lib/core/security/screen_protection.dart`. The native toggle still lands
    // asynchronously rather than at the Dart frame boundary, so the same
    // accepted one-frame gap applies on all PII auth screens in this codebase.
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

  // ── Step navigation ───────────────────────────────────────────────────

  /// Back from the code or details step returns to the phone step; a ticket
  /// already issued is dropped (it proves a phone the user may now change).
  void _backToPhone({String? error}) {
    setState(() {
      _step = _InviteStep.phone;
      _ticket = null;
      _codeError = null;
      _loading = false;
      _phoneError = error;
    });
  }

  // ── Phone step ────────────────────────────────────────────────────────

  Future<void> _sendCode(InviteDetails invite) async {
    if (_sending) return;
    final l10n = AppLocalizations.of(context);
    final String? phone = normalizeUaMobile(_phone.text);
    if (phone == null) {
      setState(() => _phoneError = l10n.errPhoneNotUaMobile);
      return;
    }
    // The visible tail of the masked phone already rules this number out —
    // no SMS for a certain 400 INVITE_PHONE_MISMATCH.
    if (!invite.phoneMayMatch(phone)) {
      setState(() => _phoneError = l10n.errInvitePhoneMismatch);
      return;
    }
    setState(() {
      _sending = true;
      _phoneError = null;
    });
    try {
      await ref.read(authProvider.notifier).sendRegistrationCode(phone: phone);
      if (!mounted) return;
      setState(() {
        _codePhone = phone;
        _codeError = null;
        _step = _InviteStep.code;
      });
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _phoneError = f.userMessage(context));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Code step ─────────────────────────────────────────────────────────

  Future<void> _confirmCode(String code, String _) async {
    final String? phone = _codePhone;
    if (phone == null) {
      _backToPhone();
      return;
    }
    try {
      final String ticket = await ref
          .read(authProvider.notifier)
          .verifyRegistrationCode(phone: phone, code: code);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _step = _InviteStep.details;
      });
    } on PhoneIdentityFailure catch (f) {
      if (!mounted) return;
      if (f.code == PhoneIdentityErrorCode.phoneAlreadyRegistered) {
        _backToPhone(error: f.userMessage(context));
        return;
      }
      setState(() => _codeError = f.userMessage(context));
    } on Failure catch (f) {
      if (!mounted) return;
      setState(() => _codeError = f.userMessage(context));
    }
  }

  Future<int?> _resendCode() async {
    final String? phone = _codePhone;
    if (phone == null) return null;
    try {
      await ref.read(authProvider.notifier).sendRegistrationCode(phone: phone);
      if (mounted) setState(() => _codeError = null);
      return kPhoneCodeResendCooldownSeconds;
    } on Failure catch (f) {
      if (mounted) setState(() => _codeError = f.userMessage(context));
      return null;
    }
  }

  // ── Details step: validation helpers ──────────────────────────────────

  // _rules is guaranteed non-null after didChangeDependencies runs.
  bool get _passwordMeetsRules => _rules!.every((r) => r.test(_password.text));

  bool get _formValid =>
      _termsAccepted &&
      _passwordMeetsRules &&
      _firstName.text.trim().isNotEmpty &&
      _lastName.text.trim().isNotEmpty;

  /// A details-field keystroke: drops that field's server error and, only
  /// once a submit was attempted (client errors are visible), rebuilds so the
  /// inline client error tracks the text. Otherwise only the CTA
  /// ([_ctaInputs]) and the password checklist rebuild.
  void _onDetailsChanged(String key) {
    if (_fieldErrors.containsKey(key) || _submitted) {
      setState(() {
        _fieldErrors = Map<String, String>.unmodifiable(
          Map<String, String>.from(_fieldErrors)..remove(key),
        );
      });
    }
  }

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

  /// Inline password error: server error first, then the same hard-gate
  /// validator register_step_1_screen/reset_password_screen use
  /// (`validateNewPassword` — min 8, max 128, ≥1 digit, ≥1 uppercase).
  String? _passwordError(AppLocalizations l10n) {
    final serverErr = _fieldErrors['password'];
    if (serverErr != null) return serverErr;
    if (!_submitted) return null;
    return validateNewPassword(_password.text, l10n);
  }

  // ── Details step: action ──────────────────────────────────────────────

  Future<void> _accept() async {
    if (_loading || !_formValid) return;
    final String? ticket = _ticket;
    if (ticket == null) {
      _backToPhone();
      return;
    }

    final l10n = AppLocalizations.of(context);

    // Client-side validation before the network call — the same hard gate
    // every other auth form applies (password + names). The phone is proven
    // by the ticket, not re-sent (B520).
    final bool clientInvalid =
        validateNewPassword(_password.text, l10n) != null ||
        validateName(_firstName.text, l10n) != null ||
        validateName(_lastName.text, l10n) != null;
    if (clientInvalid) {
      setState(() => _submitted = true);
      return;
    }

    setState(() {
      _submitted = true;
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
          termsAccepted: _termsAccepted,
          registrationTicket: ticket,
        );

    if (!mounted) return;

    final authState = ref.read(authProvider);
    authState.when(
      data: (_) {
        // Session is now Authenticated — the router redirect forwards to /home.
        // Show a snack as a positive confirmation before the transition.
        final l10n = AppLocalizations.of(context);
        showSuccessSnack(context, l10n.inviteSuccessSnackbar);
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
        // M521 (AUTH-52) — the ticket's phone is not the invited one, the
        // ticket expired, or the phone was claimed meanwhile: the invite and
        // the ticket are both left unspent (B520 rolls back), so the user
        // goes back to the phone step with the reason under the field.
        if (e is PhoneIdentityFailure &&
            (e.code == PhoneIdentityErrorCode.invitePhoneMismatch ||
                e.code == PhoneIdentityErrorCode.registrationTicketInvalid ||
                e.code == PhoneIdentityErrorCode.phoneAlreadyRegistered)) {
          _backToPhone(error: e.userMessage(context));
          return;
        }
        // A ValidationFailure with field errors maps onto each field's inline
        // errorText (firstName / lastName / password) instead of collapsing
        // to a single banner.
        if (e is ValidationFailure && e.fieldErrors.isNotEmpty) {
          setState(() {
            _loading = false;
            _fieldErrors = Map<String, String>.unmodifiable(e.fieldErrors);
            _inlineError = null;
          });
          return;
        }
        // Invite-accept post-success design (2026-09-01): the HTTP 2xx is
        // the point of no return, so these cases (response unusable /
        // dropped after send / invite already spent) must never dead-end on
        // a "try again" banner — the retry can never succeed on a single-use
        // token. Hand off to /login with the reason + the confirmed phone
        // (the login identifier accepts it) instead. `go`, not `push` — the
        // spent invite screen must leave the navigation stack.
        if (e is InviteHandoffFailure) {
          ref
              .read(loginNoticeProvider.notifier)
              .show(e.reason, email: _codePhone);
          setState(() => _loading = false);
          if (!mounted) return;
          context.go(RouteNames.login);
          return;
        }
        // ValidationFailure.userMessage() already returns the localized
        // errValidation copy. The raw serverMessage fallback was removed
        // (mobile-security, 2026-08): it could surface untranslated/technical
        // backend text on this live-narrated banner.
        final String message = e is Failure
            ? e.userMessage(context)
            : l10n.errUnknown;
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

    // The screen-container key is present in ALL THREE async states
    // (loading / error / data) so it mounts on the first frame, independent of
    // the token-validation network call. The patrol native deep-link test
    // asserts on this key the instant go_router mounts the screen — see
    // integration_test/patrol/deep_link_patrol_test.dart.
    return KeyedSubtree(
      key: const ValueKey<String>('accept_invite_screen'),
      child: inviteAsync.when(
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
                // Highest-value copy fix for the reported incident: this is
                // where the user lands re-opening a CONSUMED invite link
                // (e.g. after the accept already succeeded once). Give the
                // existing banner an action instead of a dead end — pure
                // reuse of [AuthBanner], no new widget, no new key.
                actionLabel: l10n.loginSubmit,
                onAction: () {
                  ref
                      .read(loginNoticeProvider.notifier)
                      .show(InviteHandoffReason.inviteNoLongerValid);
                  context.go(RouteNames.login);
                },
              ),
            ],
          ),
        ),
        data: (invite) {
          final preview = _previewFor(
            l10n,
            invite,
            invite.expiresInHoursFrom(ref.watch(clockProvider)()),
          );
          // System back on the code / details step steps back to the phone
          // step instead of leaving the invite (and losing the typed phone).
          return PopScope(
            canPop: _step == _InviteStep.phone,
            onPopInvokedWithResult: (bool didPop, Object? _) {
              if (!didPop && !_loading) _backToPhone();
            },
            child: switch (_step) {
              _InviteStep.phone => _buildPhoneStep(l10n, invite, preview),
              _InviteStep.code => _buildCodeStep(l10n, preview),
              _InviteStep.details => _buildDetailsStep(l10n, preview),
            },
          );
        },
      ),
    );
  }

  /// Heading + subtitle + invite card — the same block on all three steps
  /// (preview `_inviteHeader`).
  Widget _inviteHeader(
    AppLocalizations l10n,
    String subtitle,
    _InvitePreview preview,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const VelvetHeader(),
        Text(l10n.inviteHeading, style: VelvetText.heading()),
        const SizedBox(height: VelvetSpacing.sm),
        Text(subtitle, style: VelvetText.body()),
        const SizedBox(height: VelvetSpacing.lg),
        preview,
        const SizedBox(height: VelvetSpacing.xl),
      ],
    );
  }

  Widget _buildPhoneStep(
    AppLocalizations l10n,
    InviteDetails invite,
    _InvitePreview preview,
  ) {
    final String? error = _phoneError;
    return AuthScaffold(
      showBack: false,
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('invite_send_code'),
        label: l10n.registerSendCode,
        loading: _sending,
        onPressed: _sending ? null : () => _sendCode(invite),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _inviteHeader(l10n, l10n.inviteSubtitle, preview),
          NeumorphicTextField(
            key: const ValueKey<String>('invite_phone'),
            label: l10n.invitePhoneLabel,
            controller: _phone,
            hintText: l10n.registerPhoneHint,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            maxLength: 17,
            prefixIcon: const Icon(Icons.phone_outlined),
            enabled: !_sending,
            helperText: error == null ? l10n.invitePhoneHelper : null,
            errorText: error,
            inputFormatters: const <TextInputFormatter>[
              UaPhoneInputFormatter(),
            ],
            autofillHints: const <String>[AutofillHints.telephoneNumber],
            onChanged: (String _) {
              if (_phoneError != null) setState(() => _phoneError = null);
            },
            onSubmitted: (String _) => _sendCode(invite),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeStep(AppLocalizations l10n, _InvitePreview preview) {
    return PhoneCodeStep(
      onBack: _backToPhone,
      header: _inviteHeader(l10n, l10n.inviteCodeSubtitle, preview),
      description: l10n.phoneCodeSmsDescription,
      target: UaPhoneInputFormatter.display(_codePhone ?? ''),
      codeError: _codeError,
      onCodeChanged: (_) {
        if (_codeError != null) setState(() => _codeError = null);
      },
      onConfirm: _confirmCode,
      onResend: _resendCode,
    );
  }

  Widget _buildDetailsStep(AppLocalizations l10n, _InvitePreview preview) {
    return AuthScaffold(
      showBack: false,
      bottomBar: Semantics(
        hint: _termsAccepted ? null : l10n.termsConsentRequiredHint,
        child: ListenableBuilder(
          listenable: _ctaInputs,
          builder: (BuildContext context, Widget? _) => NeumorphicButton(
            key: const ValueKey<String>('invite_accept'),
            label: l10n.inviteAcceptCta,
            icon: Icons.group_add_rounded,
            loading: _loading,
            onPressed: (_formValid && !_loading) ? _accept : null,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _inviteHeader(l10n, l10n.inviteDetailsSubtitle, preview),
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
            errorText: _passwordError(l10n),
            onChanged: (String _) => _onDetailsChanged('password'),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          // Same shared policy as register/reset (min 8, ≥1 digit, ≥1
          // uppercase — see `passwordRules`'s default).
          // _rules is guaranteed non-null after didChangeDependencies runs.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _password,
            builder: (BuildContext context, TextEditingValue v, Widget? _) =>
                PasswordChecklist(value: v.text, rules: _rules!),
          ),
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
                  onChanged: (String _) => _onDetailsChanged('firstName'),
                ),
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: NeumorphicTextField(
                  key: const ValueKey<String>('invite_last_name'),
                  label: l10n.inviteLastNameLabel,
                  controller: _lastName,
                  hintText: l10n.registerLastNamePlaceholder,
                  textInputAction: TextInputAction.done,
                  maxLength: 100,
                  autofillHints: const <String>[AutofillHints.familyName],
                  enabled: !_loading,
                  errorText: _lastNameError(l10n),
                  onChanged: (String _) => _onDetailsChanged('lastName'),
                  // [_accept] itself ignores the call while loading or while
                  // the form is invalid (the field no longer rebuilds per
                  // keystroke, so the guard cannot live in the build).
                  onSubmitted: (String _) => _accept(),
                ),
              ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.md),
          // ── Terms consent (required, phase 443) ─────────────────────────
          TermsConsentCheckbox(
            idPrefix: 'invite',
            value: _termsAccepted,
            enabled: !_loading,
            onChanged: (bool v) => setState(() => _termsAccepted = v),
          ),
          if (_inlineError case final String inlineError) ...<Widget>[
            const SizedBox(height: VelvetSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                inlineError,
                style: VelvetText.feedback(BrandColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Read-only summary of the invitation: the salon, the masked invited phone
/// (B520 — a forwarded link never reveals the number), the assigned role and
/// the expiry window. Rendered as an inset well so it reads as "fixed,
/// not editable".
class _InvitePreview extends StatelessWidget {
  const _InvitePreview({
    required this.phoneMasked,
    required this.salonName,
    required this.role,
    required this.expiresInHours,
    required this.l10n,
  });

  final String phoneMasked;
  final String salonName;
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
            if (salonName.isNotEmpty) ...<Widget>[
              _row(Icons.storefront_outlined, l10n.inviteSalonLabel, salonName),
              const SizedBox(height: VelvetSpacing.md),
            ],
            _row(
              Icons.phone_outlined,
              l10n.invitePhoneMaskedLabel,
              phoneMasked,
            ),
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
