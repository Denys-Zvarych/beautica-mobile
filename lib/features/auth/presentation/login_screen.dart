// Phase 2.5 — Login screen.
//
// ConsumerStatefulWidget: owns TextEditingControllers and a FormKey for the
// local form state. Network-side state lives in [authProvider].
//
// Layout contract:
//   Scaffold → Center → SingleChildScrollView → ConstrainedBox(maxWidth 400)
//   → Padding → Form → Column with email field, password field, submit button,
//   and a link to the register screen.
//
// Submit flow:
//   1. Validate form locally (validators from lib/shared/validators/).
//   2. Call authProvider.notifier.login() — state transitions to AsyncLoading.
//   3. On AsyncData<Authenticated> → navigate to home.
//   4. On AsyncError → show SnackBar with failure.userMessage(context).
//
// All user-visible strings are fetched through AppLocalizations (UA primary).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failures.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/validators/email_validator.dart';
import '../../../shared/validators/password_validator.dart';
import 'auth_notifier.dart';

/// Login screen for the Beautica app.
///
/// Presents email + password fields and submits to [AuthNotifier.login].
/// Navigates to [RouteNames.home] on success; surfaces [Failure.userMessage]
/// in a [SnackBar] on error.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Protect credentials from task-switcher screenshots and screen recording.
    if (!kDebugMode) {
      FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    }
  }

  @override
  void dispose() {
    if (!kDebugMode) {
      FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
    }
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    await ref.read(authProvider.notifier).login(email, password);

    if (!mounted) return;

    final authState = ref.read(authProvider);
    authState.when(
      data: (_) {
        if (kDebugMode) {
          log(
            'Login screen: navigating to home',
            name: 'auth.login',
            level: 800,
          );
        }
        context.go(RouteNames.home);
      },
      loading: () {
        // Still loading — shouldn't happen right after await, but guard.
      },
      error: (e, _) {
        final message = e is Failure
            ? e.userMessage(context)
            : AppLocalizations.of(context).errUnknown;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.loginTitle)),
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
                    TextFormField(
                      key: const Key('field-email'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.loginEmailLabel,
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
                      ),
                      validator: (v) => validatePassword(v, l10n),
                      enabled: !isLoading,
                      onFieldSubmitted: (_) => isLoading ? null : _submit(),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton(
                      key: const Key('btn-submit-login'),
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              height: AppSpacing.md,
                              width: AppSpacing.md,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.loginSubmit),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(l10n.loginNoAccount),
                        TextButton(
                          key: const Key('btn-go-to-register'),
                          onPressed: isLoading
                              ? null
                              : () => context.push(RouteNames.register),
                          child: Text(l10n.loginCreateAccount),
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
