// Phase 2.6 — Register screen.
//
// ConsumerStatefulWidget: owns TextEditingControllers, a FormKey, the selected
// role, and a map of server-side field errors for inline display.
//
// Layout contract:
//   Scaffold → Center → SingleChildScrollView → ConstrainedBox(maxWidth 400)
//   → Padding → Form → Column with:
//     SegmentedButton<UserRole> (role picker, only independentMaster enabled)
//     firstName TextFormField
//     lastName TextFormField
//     email TextFormField
//     password TextFormField (obscured)
//     submit ElevatedButton
//     "Already have account?" TextButton → pop / go(login)
//
// Submit flow:
//   1. Validate form locally, including server-error injection.
//   2. Call authProvider.notifier.register().
//   3. On success → navigate to home.
//   4. On ValidationFailure → extract fieldErrors, set _serverErrors, re-validate
//      so each field shows its inline error.
//   5. On other Failure → SnackBar.
//
// All user-visible strings go through AppLocalizations (UA primary).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/email_validator.dart';
import '../../../shared/validators/name_validator.dart';
import '../../../shared/validators/password_validator.dart';
import '../domain/user_role.dart';
import 'auth_notifier.dart';
import 'user_role_l10n.dart';

/// Register screen for new INDEPENDENT_MASTER accounts.
///
/// All roles except [UserRole.independentMaster] are rendered as disabled
/// segments with a tooltip indicating they are coming soon.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  UserRole _selectedRole = UserRole.independentMaster;

  /// Server-side field errors injected after a [ValidationFailure].
  /// The matching TextFormField validators return these messages on the next
  /// [_formKey.currentState!.validate()] call.
  Map<String, String> _serverErrors = const {};

  @override
  void initState() {
    super.initState();
    // Protect credentials from task-switcher screenshots and screen recording.
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOn();
    }
  }

  @override
  void dispose() {
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOff();
    }
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Clear any previous server errors before revalidating.
    setState(() => _serverErrors = const {});

    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(authProvider.notifier)
        .register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
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
        context.go(RouteNames.home);
      },
      loading: () {
        // Guard only — should not happen right after await.
      },
      error: (e, _) {
        if (e is ValidationFailure && e.fieldErrors.isNotEmpty) {
          // Surface field-level errors inline via errorText on each field.
          // setState triggers a rebuild which sets errorText on each
          // InputDecoration from _serverErrors, making the error visible.
          setState(() => _serverErrors = e.fieldErrors);
        } else {
          final message = e is Failure
              ? e.userMessage(context)
              : AppLocalizations.of(context).errUnknown;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.registerTitle)),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.roleLabel),
                    const SizedBox(height: AppSpacing.xs),
                    _RoleSelector(
                      selectedRole: _selectedRole,
                      isLoading: isLoading,
                      onChanged: (role) => setState(() => _selectedRole = role),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const Key('field-firstName'),
                      controller: _firstNameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.firstNameLabel,
                        // Server-side errors are shown via errorText.
                        // Client-side errors come from the validator.
                        errorText: _serverErrors['firstName'],
                      ),
                      validator: (v) => validateName(v, l10n),
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const Key('field-lastName'),
                      controller: _lastNameController,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.lastNameLabel,
                        errorText: _serverErrors['lastName'],
                      ),
                      validator: (v) => validateName(v, l10n),
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const Key('field-email'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.loginEmailLabel,
                        errorText: _serverErrors['email'],
                      ),
                      validator: (v) => validateEmail(v, l10n),
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const Key('field-password'),
                      controller: _passwordController,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.loginPasswordLabel,
                        errorText: _serverErrors['password'],
                      ),
                      validator: (v) => validatePassword(v, l10n),
                      enabled: !isLoading,
                      onFieldSubmitted: (_) => isLoading ? null : _submit(),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton(
                      key: const Key('btn-submit-register'),
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              height: AppSpacing.md,
                              width: AppSpacing.md,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.registerSubmit),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(l10n.registerHaveAccount),
                        TextButton(
                          key: const Key('btn-go-to-login'),
                          onPressed: isLoading
                              ? null
                              : () => context.canPop()
                                    ? context.pop()
                                    : context.go(RouteNames.login),
                          child: Text(l10n.registerSignIn),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Role segment picker.
///
/// Only [UserRole.independentMaster] is enabled for the MVP; all other roles
/// display a tooltip indicating they are coming soon. Extracted to keep
/// [_RegisterScreenState.build] readable.
class _RoleSelector extends StatelessWidget {
  const _RoleSelector({
    required this.selectedRole,
    required this.isLoading,
    required this.onChanged,
  });

  final UserRole selectedRole;
  final bool isLoading;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget segmentLabel(UserRole role) {
      final text = Text(role.label(l10n));
      if (role == UserRole.independentMaster) return text;
      return Tooltip(message: l10n.roleComingSoon, child: text);
    }

    return SegmentedButton<UserRole>(
      key: const Key('field-role'),
      segments: UserRole.values
          .map(
            (r) => ButtonSegment<UserRole>(
              value: r,
              label: segmentLabel(r),
              enabled: r == UserRole.independentMaster,
            ),
          )
          .toList(),
      selected: {selectedRole},
      onSelectionChanged: isLoading
          ? null
          : (selected) => onChanged(selected.first),
      multiSelectionEnabled: false,
    );
  }
}
