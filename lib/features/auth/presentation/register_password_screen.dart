// M515 (AUTH-D11) — step 3 of the phone-first registration wizard: password +
// confirmation with the live [PasswordChecklist]. Fields moved verbatim from
// the pre-M515 step 1 (preview `RegisterPasswordStep`,
// docs/signup-designs/PhoneFirstAuth/lib/screens/register_flow.dart).
//
// «Далі» → validated by the shared strict validator (the same policy as the
// backend's @StrongPassword) → draft → /register/step-2 (name).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/velvet_geometry.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/password_validator.dart';
import '../state/register_draft_notifier.dart';
import 'register_flow_shell.dart';
import 'widgets/auth_icon_tile.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/password_checklist.dart';

/// Step 3 of the phone-first registration wizard — password.
class RegisterPasswordScreen extends ConsumerStatefulWidget {
  const RegisterPasswordScreen({super.key});

  @override
  ConsumerState<RegisterPasswordScreen> createState() =>
      _RegisterPasswordScreenState();
}

class _RegisterPasswordScreenState
    extends ConsumerState<RegisterPasswordScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  String _passwordValue = '';
  String? _passwordError;
  String? _confirmError;
  List<PasswordRule>? _rules;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once — needs AppLocalizations, unavailable in initState.
    _rules ??= passwordRules(AppLocalizations.of(context));
  }

  @override
  void initState() {
    super.initState();
    // Pre-fill from the draft (back from the name step).
    final draft = ref.read(registerDraftProvider);
    if (draft != null) {
      _passwordController.text = draft.password;
      _confirmController.text = draft.confirmPassword;
      _passwordValue = draft.password;
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final String? pwErr = validateNewPassword(_passwordController.text, l10n);
    final String? confirmErr =
        _confirmController.text != _passwordController.text
        ? l10n.errPasswordsMismatch
        : (_confirmController.text.isEmpty ? l10n.errPasswordRequired : null);
    if (pwErr != null || confirmErr != null) {
      setState(() {
        _passwordError = pwErr;
        _confirmError = confirmErr;
      });
      return;
    }
    final draft = ref.read(registerDraftProvider);
    ref
        .read(registerDraftProvider.notifier)
        .updateStep1(
          email: draft?.email ?? '',
          password: _passwordController.text,
          confirmPassword: _confirmController.text,
        );
    context.go(RouteNames.registerStep2);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      showBack: true,
      onBack: () => context.go(RouteNames.registerCode),
      bottomBar: NeumorphicButton(
        key: const ValueKey<String>('reg_password_submit'),
        label: l10n.registerContinue,
        onPressed: _submit,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const AuthIconTile(icon: Icons.key_outlined),
          const SizedBox(height: VelvetSpacing.lg),
          WizardStepChrome(
            step: 3,
            headline: l10n.registerPasswordHeadline,
            totalSteps: kPhoneFirstRegisterSteps,
          ),
          NeumorphicTextField(
            key: const ValueKey<String>('step1_password'),
            label: l10n.loginPasswordLabel,
            controller: _passwordController,
            hintText: '••••••••',
            obscureToggle: true,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            maxLength: 128,
            textInputAction: TextInputAction.next,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            autofillHints: const <String>[AutofillHints.newPassword],
            errorText: _passwordError,
            onChanged: (v) => setState(() {
              _passwordValue = v;
              _passwordError = null;
            }),
          ),
          const SizedBox(height: VelvetSpacing.xs),
          // _rules is non-null after didChangeDependencies.
          PasswordChecklist(value: _passwordValue, rules: _rules!),
          const SizedBox(height: VelvetSpacing.sm),
          NeumorphicTextField(
            key: const ValueKey<String>('step1_confirm'),
            label: l10n.registerConfirmPasswordLabel,
            controller: _confirmController,
            hintText: '••••••••',
            obscureToggle: true,
            enableSuggestions: false,
            autocorrect: false,
            enableIMEPersonalizedLearning: false,
            maxLength: 128,
            textInputAction: TextInputAction.done,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            autofillHints: const <String>[AutofillHints.newPassword],
            errorText: _confirmError,
            onChanged: (_) {
              if (_confirmError != null) setState(() => _confirmError = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: VelvetSpacing.lg),
        ],
      ),
    );
  }
}
