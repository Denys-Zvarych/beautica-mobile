// M515 (AUTH-41) — step 2 of the phone-first registration wizard: the SMS code
// for the phone entered on step 1. The shared [PhoneCodeStep] with the wizard
// header in its `header` slot (preview `RegisterCodeStep`,
// docs/signup-designs/PhoneFirstAuth/lib/screens/register_flow.dart).
//
// «Підтвердити» → `POST /auth/register/phone/otp/verify` → the single-use
// registration ticket is stored in the in-memory draft → /register/password.
//   400 INVALID_CODE              → inline banner under the resend row.
//   409 PHONE_ALREADY_REGISTERED  → back to step 1 with the «Увійти» banner
//                                   (the backend answers it only after the
//                                   code proved ownership, AUTH-42).
// «Надіслати знову» re-sends through the same App Check-guarded endpoint.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/feedback/show_velvet_snack.dart';
import '../../../shared/formatters/ua_phone_input_formatter.dart';
import '../state/register_draft_notifier.dart';
import 'auth_notifier.dart';
import 'register_flow_shell.dart';
import 'widgets/auth_icon_tile.dart';
import 'widgets/phone_code_step.dart';

/// Step 2 of the phone-first registration wizard — the SMS code.
class RegisterCodeScreen extends ConsumerStatefulWidget {
  const RegisterCodeScreen({super.key});

  @override
  ConsumerState<RegisterCodeScreen> createState() => _RegisterCodeScreenState();
}

class _RegisterCodeScreenState extends ConsumerState<RegisterCodeScreen> {
  String? _codeError;

  String get _phone => ref.read(registerDraftProvider)?.phone ?? '';

  Future<void> _confirm(String code, String _) async {
    final String phone = _phone;
    if (phone.isEmpty) {
      context.go(RouteNames.register);
      return;
    }
    try {
      final String ticket = await ref
          .read(authProvider.notifier)
          .verifyRegistrationCode(phone: phone, code: code);
      if (!mounted) return;
      ref.read(registerDraftProvider.notifier).setRegistrationTicket(ticket);
      context.go(RouteNames.registerPassword);
    } on PhoneIdentityFailure catch (f) {
      if (!mounted) return;
      if (f.code == PhoneIdentityErrorCode.phoneAlreadyRegistered) {
        // `extra`, never a query param (kSensitiveQueryKeys).
        context.go(RouteNames.register, extra: f.code);
        return;
      }
      setState(() => _codeError = f.userMessage(context));
    } on Failure catch (f) {
      if (!mounted) return;
      showErrorSnack(context, f.userMessage(context));
    }
  }

  Future<int?> _resend() async {
    final String phone = _phone;
    try {
      await ref.read(authProvider.notifier).sendRegistrationCode(phone: phone);
      if (mounted) setState(() => _codeError = null);
      return kPhoneCodeResendCooldownSeconds;
    } on Failure catch (f) {
      if (mounted) setState(() => _codeError = f.userMessage(context));
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String phone =
        ref.watch(registerDraftProvider.select((d) => d?.phone)) ?? '';
    return PhoneCodeStep(
      onBack: () => context.go(RouteNames.register),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AuthIconTile(icon: Icons.sms_outlined),
          const SizedBox(height: VelvetSpacing.lg),
          WizardStepChrome(
            step: 2,
            headline: l10n.phoneCodeHeadline,
            totalSteps: kPhoneFirstRegisterSteps,
          ),
        ],
      ),
      description: l10n.phoneCodeSmsDescription,
      target: const UaPhoneInputFormatter()
          .formatEditUpdate(
            TextEditingValue.empty,
            TextEditingValue(text: phone),
          )
          .text,
      codeError: _codeError,
      onCodeChanged: (_) {
        if (_codeError != null) setState(() => _codeError = null);
      },
      onConfirm: _confirm,
      onResend: _resend,
    );
  }
}
