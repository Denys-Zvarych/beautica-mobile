// Phase 2.16 — Registration wizard Step 1. M515 (AUTH-D11 / AUTH-41): the
// phone step of the phone-first wizard (phone -> SMS code -> password ->
// name -> address). Ported literally from the approved preview
// docs/signup-designs/PhoneFirstAuth/lib/screens/register_flow.dart
// (`RegisterPhoneStep`).
//
// Lifecycle:
//   1. Role picked on the role-selection screen → `registerDraftProvider`.
//   2. The user types a phone, ticks the consent (AUTH-26 stays on step 1)
//      and taps «Надіслати код».
//   3. The phone is checked locally (Ukrainian mobile only, AUTH-D15) BEFORE
//      any request, normalised to `+380…`, and `POST
//      /auth/register/phone/otp/send` runs (App Check header via the
//      interceptor). 200 → draft.updatePhone → /register/code.
//   4. 429 / 403 APP_CHECK_FAILED / 503 APP_CHECK_UNAVAILABLE /
//      400 PHONE_NOT_UA_MOBILE render an inline banner; the code step sends
//      the user back here with 409 PHONE_ALREADY_REGISTERED («Увійти»).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/network/app_check_prefetch.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/feedback/show_velvet_snack.dart';
import '../../../shared/formatters/ua_phone_input_formatter.dart';
import '../../../shared/validators/identifier_classifier.dart';
import '../../../shared/widgets/terms_consent_checkbox.dart';
import '../state/register_draft_notifier.dart';
import 'auth_notifier.dart';
import 'register_flow_shell.dart';
import 'widgets/auth_icon_tile.dart';
import 'widgets/auth_scaffold.dart';

/// Step 1 of the phone-first registration wizard — phone + consent.
class RegisterStep1Screen extends ConsumerStatefulWidget {
  const RegisterStep1Screen({super.key, this.initialSendError});

  /// Banner to show on arrival — the code step returns here with
  /// [PhoneIdentityErrorCode.phoneAlreadyRegistered] (409).
  final PhoneIdentityErrorCode? initialSendError;

  @override
  ConsumerState<RegisterStep1Screen> createState() =>
      _RegisterStep1ScreenState();
}

class _RegisterStep1ScreenState extends ConsumerState<RegisterStep1Screen> {
  final TextEditingController _phoneController = TextEditingController();

  String? _phoneError;
  late PhoneIdentityErrorCode? _sendError = widget.initialSendError;

  // Phase 443 — required terms + privacy consent; the CTA stays disabled
  // until ticked, persisted to the draft on submit.
  bool _termsAccepted = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // Phone-first hardening P2: attest ahead of the SMS send.
    ref.read(appCheckTokenPrefetcherProvider).prefetch();
    // Pre-fill from the draft (back from the code step).
    final draft = ref.read(registerDraftProvider);
    if (draft != null) {
      _phoneController.text = const UaPhoneInputFormatter()
          .formatEditUpdate(
            TextEditingValue.empty,
            TextEditingValue(text: draft.phone),
          )
          .text;
      _termsAccepted = draft.termsAccepted;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // ── Submit ──────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    // Phase 443 D3 — also guards the keyboard path past the disabled CTA.
    if (!_termsAccepted || _sending) return;
    final l10n = AppLocalizations.of(context);
    final String? phone = normalizeUaMobile(_phoneController.text);
    if (phone == null) {
      setState(() => _phoneError = l10n.errPhoneNotUaMobile);
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref.read(authProvider.notifier).sendRegistrationCode(phone: phone);
      if (!mounted) return;
      ref
          .read(registerDraftProvider.notifier)
          .updatePhone(phone: phone, termsAccepted: _termsAccepted);
      if (kDebugMode) {
        log(
          'Phone step: code sent — advancing to /register/code',
          name: 'auth.register.phone',
          level: 800,
        );
      }
      context.go(RouteNames.registerCode);
    } on PhoneIdentityFailure catch (f) {
      if (!mounted) return;
      setState(() {
        if (f.code == PhoneIdentityErrorCode.phoneNotUaMobile) {
          _phoneError = l10n.errPhoneNotUaMobile;
        } else {
          _sendError = f.code;
        }
      });
    } on Failure catch (f) {
      if (!mounted) return;
      showErrorSnack(context, f.userMessage(context));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _goToLogin() {
    // Navigate BEFORE nulling the draft — see the shell's null-role guard.
    context.go(RouteNames.login);
    // Security (Phase 2.16 HIGH-1) — wipe the in-progress draft.
    ref.read(registerDraftProvider.notifier).reset();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final PhoneIdentityErrorCode? sendError = _sendError;

    return AuthScaffold(
      showBack: true,
      onBack: () => context.go(RouteNames.registerRole),
      bottomBar: Semantics(
        hint: _termsAccepted ? null : l10n.termsConsentRequiredHint,
        child: NeumorphicButton(
          key: const ValueKey<String>('step1_submit'),
          label: l10n.registerSendCode,
          loading: _sending,
          onPressed: null,
          onPressedAsync: _termsAccepted && !_sending ? _submit : null,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AuthIconTile(
            icon: Icons.phone_iphone_rounded,
            tileKey: Key('step1_icon_tile'),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          WizardStepChrome(
            step: 1,
            headline: l10n.registerHeadline,
            totalSteps: kPhoneFirstRegisterSteps,
          ),

          // ── Phone ──────────────────────────────────────────────────────
          NeumorphicTextField(
            key: const ValueKey<String>('step1_phone'),
            label: l10n.step2FieldPhoneLabel,
            controller: _phoneController,
            hintText: l10n.registerPhoneHint,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            maxLength: 17,
            prefixIcon: const Icon(Icons.phone_outlined),
            helperText: l10n.registerPhoneHelper,
            errorText: _phoneError,
            enabled: !_sending,
            inputFormatters: const <TextInputFormatter>[
              UaPhoneInputFormatter(),
            ],
            autocorrect: false,
            autofillHints: const <String>[AutofillHints.telephoneNumber],
            onChanged: (_) {
              if (_phoneError != null || _sendError != null) {
                setState(() {
                  _phoneError = null;
                  _sendError = null;
                });
              }
            },
            onSubmitted: (_) => _submit(),
          ),

          if (sendError != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            AuthBanner(
              key: const ValueKey<String>('phone_send_error'),
              icon: sendError == PhoneIdentityErrorCode.appCheckFailed
                  ? Icons.system_update_alt_rounded
                  : Icons.error_outline_rounded,
              color: BrandColors.error,
              message: PhoneIdentityFailure(
                code: sendError,
              ).userMessage(context),
              actionLabel:
                  sendError == PhoneIdentityErrorCode.phoneAlreadyRegistered
                  ? l10n.registerSignIn
                  : null,
              onAction:
                  sendError == PhoneIdentityErrorCode.phoneAlreadyRegistered
                  ? _goToLogin
                  : null,
            ),
          ],
          const SizedBox(height: VelvetSpacing.md),

          // ── Terms consent (required, phase 443) ───────────────────────
          TermsConsentCheckbox(
            idPrefix: 'step1',
            value: _termsAccepted,
            onChanged: (bool v) => setState(() => _termsAccepted = v),
          ),
          const SizedBox(height: VelvetSpacing.sm),

          // ── "Вже маєте акаунт з email? Увійдіть" (AUTH-D28) ────────────
          Center(
            child: GestureDetector(
              key: const ValueKey<String>('step1_login_link'),
              onTap: _goToLogin,
              child: Padding(
                padding: const EdgeInsets.all(VelvetSpacing.xs),
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: l10n.registerHaveEmailAccount,
                        style: VelvetText.body(),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: l10n.registerSignInImperative,
                        style: VelvetText.link(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.sm),
        ],
      ),
    );
  }
}
