// M517 (AUTH-D12) — «Додайте номер телефону», the BLOCKING full-screen step
// for every role without a verified phone. Ported literally from
// docs/signup-designs/PhoneFirstAuth/lib/screens/phone_account_screens.dart
// `AddPhoneScreen` (approved 2026-11-18): AuthScaffold (no back) > icon tile >
// heading > body > phone field > send-error banner > «Вийти з акаунта».
//
// Reached only through the auth redirect (`auth_redirect.dart`), which sends a
// `mustAddPhone` session here from any location — at app open, or over an
// open app after a 409 PHONE_NOT_VERIFIED — and keeps it here, so no other
// screen or its data is mounted while this shows. No back (PopScope), no skip,
// no «use email instead» (AUTH-D15); «Вийти» is the only other action.
//
// «Надіслати код» → Ukrainian mobile check (inline, before any request) →
// `POST /users/me/phone/otp/send` (App Check header from the M515 interceptor)
// → [RouteNames.addPhoneVerify] (code only, AUTH-D19). The number may differ
// from an unverified legacy profile phone; once confirmed it replaces it
// (AUTH-44).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/navigation/single_flight.dart';
import '../../../routing/route_names.dart';
import '../../../shared/feedback/show_velvet_snack.dart';
import '../../../shared/formatters/ua_phone_input_formatter.dart';
import '../../../shared/validators/identifier_classifier.dart';
import '../domain/contact_verify_args.dart';
import 'auth_notifier.dart';
import 'widgets/auth_icon_tile.dart';
import 'widgets/auth_scaffold.dart';

/// The blocking add-phone step (see the file header).
class AddPhoneScreen extends ConsumerStatefulWidget {
  const AddPhoneScreen({super.key});

  @override
  ConsumerState<AddPhoneScreen> createState() => _AddPhoneScreenState();
}

class _AddPhoneScreenState extends ConsumerState<AddPhoneScreen> {
  final TextEditingController _phone = TextEditingController();
  String? _error;
  PhoneIdentityErrorCode? _sendError;
  bool _sending = false;
  bool _loggingOut = false;

  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? phone = normalizeUaMobile(_phone.text);
    if (phone == null) {
      setState(() => _error = l10n.errPhoneNotUaMobile);
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref.read(authProvider.notifier).sendPhoneCode(phone: phone);
      if (!mounted) return;
      await context.pushOnce<bool>(
        RouteNames.addPhoneVerify,
        extra: ContactVerifyArgs(
          kind: ContactVerifyKind.phoneAdd,
          target: phone,
        ),
      );
    } on PhoneIdentityFailure catch (f) {
      if (!mounted) return;
      setState(() {
        if (f.code == PhoneIdentityErrorCode.phoneNotUaMobile) {
          _error = l10n.errPhoneNotUaMobile;
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

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    // The unauthenticated bounce in the auth redirect then routes to /login.
    await ref.read(authProvider.notifier).logout();
    if (mounted) setState(() => _loggingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final PhoneIdentityErrorCode? sendError = _sendError;

    return PopScope(
      canPop: false,
      child: AuthScaffold(
        showBack: false,
        bottomBar: NeumorphicButton(
          key: const ValueKey<String>('add_phone_submit'),
          label: l10n.registerSendCode,
          loading: _sending,
          onPressed: null,
          onPressedAsync: _sending ? null : _submit,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const AuthIconTile(icon: Icons.phone_iphone_rounded),
            const SizedBox(height: VelvetSpacing.lg),
            Text(
              l10n.addPhoneHeadline,
              style: VelvetText.heading(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              l10n.addPhoneBody,
              style: VelvetText.body(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.xl),
            NeumorphicTextField(
              key: const ValueKey<String>('add_phone'),
              label: l10n.phoneLabel,
              controller: _phone,
              hintText: l10n.registerPhoneHint,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              maxLength: 17,
              prefixIcon: const Icon(Icons.phone_outlined),
              errorText: _error,
              enabled: !_sending,
              inputFormatters: const <TextInputFormatter>[
                UaPhoneInputFormatter(),
              ],
              autocorrect: false,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              onChanged: (_) {
                if (_error != null || _sendError != null) {
                  setState(() {
                    _error = null;
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
                message:
                    sendError == PhoneIdentityErrorCode.phoneAlreadyRegistered
                    ? l10n.errPhoneInUse
                    : PhoneIdentityFailure(
                        code: sendError,
                      ).userMessage(context),
              ),
            ],
            const SizedBox(height: VelvetSpacing.lg),
            Center(
              child: Semantics(
                button: true,
                child: GestureDetector(
                  key: const ValueKey<String>('add_phone_logout'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _loggingOut ? null : _logout,
                  child: Padding(
                    padding: const EdgeInsets.all(VelvetSpacing.xs),
                    child: Text(l10n.addPhoneLogout, style: VelvetText.link()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
