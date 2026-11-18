// M517 (AUTH-D17, AUTH-50) — «Email для сповіщень»: add or change the optional
// notifications email, for every role. Ported literally from
// docs/signup-designs/PhoneFirstAuth/lib/screens/email_prompt_screens.dart
// `EmailEntryScreen` (approved 2026-11-18): SectionScaffold > intro > the
// email VelvetField > pinned «Надіслати код».
//
// Reached from the profile row, the client booking-success card and the
// provider home card. «Надіслати код» → `POST /users/me/email/request-code` →
// [RouteNames.notificationEmailVerify] (code + current password, AUTH-D19) →
// back here with `true` → pop(true) to the caller. The email is stored only
// once confirmed (AUTH-50).
//
// SEC: an email address is typed here — screenshot guard on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../core/widgets/velvet_field.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/role_home.dart';
import '../../../core/navigation/single_flight.dart';
import '../../../routing/route_names.dart';
import '../../../shared/feedback/show_velvet_snack.dart';
import '../../../shared/validators/email_validator.dart';
import '../../master/presentation/widgets/section_scaffold.dart';
import '../domain/auth_session.dart';
import '../domain/contact_verify_args.dart';
import 'auth_notifier.dart';

/// Notifications-email entry (see the file header).
class NotificationEmailScreen extends ConsumerStatefulWidget {
  const NotificationEmailScreen({super.key});

  @override
  ConsumerState<NotificationEmailScreen> createState() =>
      _NotificationEmailScreenState();
}

class _NotificationEmailScreenState
    extends ConsumerState<NotificationEmailScreen> {
  late final TextEditingController _email;
  String? _error;
  bool _sending = false;

  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
    // Change = start from the confirmed address (preview `current`).
    final AuthSession? s = ref.read(authProvider).value;
    _email = TextEditingController(
      text: s is Authenticated ? s.user.confirmedEmail ?? '' : '',
    );
  }

  @override
  void dispose() {
    _screenProtection.release();
    _email.dispose();
    super.dispose();
  }

  void _close([bool changed = false]) {
    if (context.canPop()) {
      context.pop(changed);
      return;
    }
    final AuthSession? s = ref.read(authProvider).value;
    context.go(
      s is Authenticated ? roleHomePath(s.user.role) : RouteNames.login,
    );
  }

  Future<void> _submit() async {
    if (_sending) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String email = _email.text.trim();
    final String? invalid = validateEmail(email, l10n);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(authProvider.notifier)
          .requestNotificationEmailCode(email: email);
      if (!mounted) return;
      final bool? confirmed = await context.pushOnce<bool>(
        RouteNames.notificationEmailVerify,
        extra: ContactVerifyArgs(
          kind: ContactVerifyKind.notificationEmail,
          target: email,
        ),
      );
      if (!mounted) return;
      // Confirmed → back to the caller (row / card), as the preview does.
      // After the frame: the code step's pop resolved this push BEFORE
      // go_router dropped its match, so a pop in the same turn would hit the
      // code step again. The session (emailVerified + the address the row
      // shows) then refreshes; a profile-only emission no longer re-parses
      // the router stack (AuthRefreshNotifier keys on redirect fields only).
      if (confirmed == true) {
        final AuthNotifier auth = ref.read(authProvider.notifier);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _close(true);
          unawaited(auth.refreshUser());
        });
      }
    } on ResendThrottledFailure catch (f) {
      if (!mounted) return;
      setState(() => _error = f.userMessage(context));
    } on Failure catch (f) {
      if (!mounted) return;
      showErrorSnack(context, f.userMessage(context));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SectionScaffold(
      title: l10n.profileNotificationEmailTitle,
      backKey: const Key('btn-back-notification-email'),
      backSemanticLabel: l10n.notificationEmailBackSemantics,
      onBack: _close,
      footer: NeumorphicButton(
        key: const Key('btn-email-send-code'),
        label: l10n.registerSendCode,
        icon: Icons.send_rounded,
        loading: _sending,
        onPressed: null,
        onPressedAsync: _sending ? null : _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
            child: Text(l10n.notificationEmailIntro, style: VelvetText.body()),
          ),
          VelvetField(
            fieldKey: const Key('field-notification-email'),
            label: l10n.notificationEmailLabel,
            controller: _email,
            enabled: !_sending,
            keyboardType: TextInputType.emailAddress,
            hint: l10n.notificationEmailHint,
            errorText: _error,
            helperText: l10n.notificationEmailHelper,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
    );
  }
}
