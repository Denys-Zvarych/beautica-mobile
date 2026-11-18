// M517 — the ONE code step for every signed-in contact confirmation, hosted on
// the shared M515 [PhoneCodeStep] (design: docs/signup-designs/PhoneFirstAuth/
// lib/screens/phone_account_screens.dart `PhoneCodeStep` push /
// `PhoneChangeCodeScreen`, email_prompt_screens.dart `EmailCodeScreen`):
//
//   phoneAdd          SMS code only (AUTH-D12 first add, AUTH-D19 no password)
//   phoneChange       SMS code + current password (AUTH-D13 / AUTH-D19)
//   notificationEmail emailed code + current password (AUTH-50 / AUTH-D19)
//
// Outcomes:
//   200                              phoneAdd → the session refresh drops the
//                                    blocking gate (router redirect);
//                                    otherwise pop(true) to the caller.
//   400 CURRENT_PASSWORD_INVALID     «Невірний поточний пароль» under the
//                                    password field; counted towards the
//                                    client-side lockout mirror, which turns
//                                    the step [PhoneCodeStep.locked].
//   400 INVALID_CODE / CODE_EXPIRED  banner under the resend row.
//   409 PHONE_ALREADY_REGISTERED /
//       EMAIL_ALREADY_REGISTERED     banner: the contact belongs to another
//                                    account.
//
// SEC: an OTP + the current password are typed here — screenshot guard on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/time/clock_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/role_home.dart';
import '../../../routing/route_names.dart';
import '../../../shared/feedback/show_velvet_snack.dart';
import '../../../shared/formatters/ua_phone_input_formatter.dart';
import '../domain/auth_session.dart';
import '../domain/contact_verify_args.dart';
import '../state/current_password_lockout_notifier.dart';
import 'auth_notifier.dart';
import 'widgets/phone_code_step.dart';

/// Seconds the resend row waits after a 429 that carries no usable seconds.
const int _kContactResendFallbackSeconds = 60;

/// The shared contact-code step (see the file header).
class ContactVerifyScreen extends ConsumerStatefulWidget {
  const ContactVerifyScreen({super.key, required this.args});

  final ContactVerifyArgs args;

  @override
  ConsumerState<ContactVerifyScreen> createState() =>
      _ContactVerifyScreenState();
}

class _ContactVerifyScreenState extends ConsumerState<ContactVerifyScreen> {
  String? _codeError;
  String? _passwordError;

  late final ScreenProtectionManager _screenProtection;

  /// Fires at the instant the current-password lock lifts, so a step left open
  /// while locked unlocks by itself (AUTH-D19). Cancelled on dispose.
  Timer? _unlockTimer;
  DateTime? _unlockTimerAt;

  /// The args this step was OPENED with. go_router re-parses the stack on
  /// every redirect-key auth change (see `authRouterKey` — e.g. an
  /// `invalidate(authProvider)` or a server-side role change; profile-only
  /// emissions no longer refresh the router) and a restored push loses its
  /// non-codec `extra`, rebuilding this page (same key, same State) with
  /// placeholder args — so the first args are kept for the life of the State
  /// and later ones ignored. Defence in depth.
  late final ContactVerifyArgs _args = widget.args;

  ContactVerifyKind get _kind => _args.kind;
  bool get _isEmail => _kind == ContactVerifyKind.notificationEmail;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
    // Opened without a target (a deep link / restored stack): nothing to
    // confirm — back to where the target is entered.
    if (_args.target.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (_kind) {
          case ContactVerifyKind.phoneAdd:
            context.go(RouteNames.addPhone);
          case ContactVerifyKind.notificationEmail:
            context.go(RouteNames.notificationEmail);
          case ContactVerifyKind.phoneChange:
            _leave(false);
        }
      });
    }
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    _screenProtection.release();
    super.dispose();
  }

  /// (Re)arms [_unlockTimer] for [unlocksAt]; a no-op when already armed for
  /// that instant, a cancel when not locked.
  void _scheduleUnlockRebuild(DateTime? unlocksAt) {
    if (unlocksAt == _unlockTimerAt) return;
    _unlockTimer?.cancel();
    _unlockTimer = null;
    _unlockTimerAt = unlocksAt;
    if (unlocksAt == null) return;
    // instant-ok: the lock lifts at an absolute instant (15-minute window).
    final Duration wait = unlocksAt.difference(ref.read(clockProvider)());
    _unlockTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      _unlockTimerAt = null;
      if (mounted) setState(() {});
    });
  }

  String get _userId {
    final AuthSession? s = ref.read(authProvider).value;
    return s is Authenticated ? s.user.id : '';
  }

  Future<void> _confirm(String code, String password) async {
    final AuthNotifier auth = ref.read(authProvider.notifier);
    setState(() {
      _codeError = null;
      _passwordError = null;
    });
    try {
      // Only the first add refreshes the session here (that refresh IS the
      // exit: the redirect drops the blocking step). A change / email pops
      // first and the caller refreshes after navigating, so the caller
      // owns the refresh timing (a redirect-key emission while these pushed
      // steps are up would still make go_router re-parse the stack — see
      // authRouterKey).
      switch (_kind) {
        case ContactVerifyKind.phoneAdd:
          await auth.verifyPhoneCode(phone: _args.target, code: code);
        case ContactVerifyKind.phoneChange:
          await auth.verifyPhoneCode(
            phone: _args.target,
            code: code,
            currentPassword: password,
            refreshSession: false,
          );
        case ContactVerifyKind.notificationEmail:
          await auth.verifyNotificationEmailCode(
            email: _args.target,
            code: code,
            currentPassword: password,
            refreshSession: false,
          );
      }
      ref.read(currentPasswordLockoutProvider.notifier).clear(_userId);
      // phoneAdd: the refreshed session (phone verified) makes the auth
      // redirect REPLACE the whole blocking stack with the role home — never
      // pop here (the stack is already being torn down).
      if (!mounted || _kind == ContactVerifyKind.phoneAdd) return;
      _leave();
    } on CurrentPasswordInvalidFailure catch (f) {
      ref.read(currentPasswordLockoutProvider.notifier).recordFailure(_userId);
      if (!mounted) return;
      setState(() => _passwordError = f.userMessage(context));
    } on PhoneIdentityFailure catch (f) {
      if (!mounted) return;
      final AppLocalizations l10n = AppLocalizations.of(context);
      setState(
        () =>
            _codeError = f.code == PhoneIdentityErrorCode.phoneAlreadyRegistered
            ? l10n.errPhoneInUse
            : f.userMessage(context),
      );
    } on EmailAlreadyRegisteredFailure {
      if (!mounted) return;
      setState(() => _codeError = AppLocalizations.of(context).errEmailInUse);
    } on VerificationFailure catch (f) {
      if (!mounted) return;
      setState(() => _codeError = f.userMessage(context));
    } on Failure catch (f) {
      if (!mounted) return;
      showErrorSnack(context, f.userMessage(context));
    }
  }

  void _leave([bool confirmed = true]) {
    if (context.canPop()) {
      context.pop(confirmed);
      return;
    }
    final AuthSession? s = ref.read(authProvider).value;
    context.go(
      s is Authenticated ? roleHomePath(s.user.role) : RouteNames.login,
    );
  }

  Future<int?> _resend() async {
    final AuthNotifier auth = ref.read(authProvider.notifier);
    try {
      if (_isEmail) {
        await auth.requestNotificationEmailCode(email: _args.target);
      } else {
        await auth.sendPhoneCode(phone: _args.target);
      }
      if (mounted) setState(() => _codeError = null);
      return kPhoneCodeResendCooldownSeconds;
    } on ResendThrottledFailure catch (f) {
      if (mounted) setState(() => _codeError = f.userMessage(context));
      return f.retryAfterSeconds ?? _kContactResendFallbackSeconds;
    } on PhoneIdentityFailure catch (f) {
      if (mounted) setState(() => _codeError = f.userMessage(context));
      // A throttled send keeps the link disabled; other rejections allow an
      // immediate retry.
      return f.code == PhoneIdentityErrorCode.rateLimited
          ? _kContactResendFallbackSeconds
          : null;
    } on Failure catch (f) {
      if (mounted) setState(() => _codeError = f.userMessage(context));
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Rebuild when the lockout tally changes (a wrong password just counted).
    ref.watch(currentPasswordLockoutProvider);
    final bool locked =
        _args.requiresCurrentPassword &&
        ref.read(currentPasswordLockoutProvider.notifier).isLocked(_userId);
    _scheduleUnlockRebuild(
      locked
          ? ref.read(currentPasswordLockoutProvider.notifier).unlocksAt(_userId)
          : null,
    );

    final String target = _isEmail
        ? _args.target
        : UaPhoneInputFormatter.display(_args.target);

    return PhoneCodeStep(
      icon: _isEmail ? Icons.mark_email_read_outlined : Icons.sms_outlined,
      headline: switch (_kind) {
        ContactVerifyKind.phoneAdd => null,
        ContactVerifyKind.phoneChange => l10n.phoneChangeCodeHeadline,
        ContactVerifyKind.notificationEmail => l10n.emailCodeHeadline,
      },
      description: _isEmail
          ? l10n.resetOtpCardDesc
          : l10n.phoneCodeSmsDescription,
      target: target,
      requireCurrentPassword: _args.requiresCurrentPassword,
      passwordError: _passwordError,
      locked: locked,
      codeError: _codeError,
      onBack: () {
        _leave(false);
      },
      onCodeChanged: (_) {
        if (_codeError != null) setState(() => _codeError = null);
      },
      onConfirm: _confirm,
      onResend: _resend,
    );
  }
}
