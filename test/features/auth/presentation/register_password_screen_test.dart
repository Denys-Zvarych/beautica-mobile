// M515 — Widget tests for [RegisterPasswordScreen] (step 3 of the phone-first
// wizard): checklist + strict validator gate, mismatch, draft write, nav.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_flow_shell.dart';
import 'package:beautica_mobile/features/auth/presentation/register_password_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/password_checklist.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

ProviderContainer _container() {
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  container.read(registerDraftProvider.notifier).start(UserRole.client);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  final router = GoRouter(
    initialLocation: RouteNames.registerPassword,
    routes: [
      GoRoute(
        path: RouteNames.registerPassword,
        builder: (context, state) => const RegisterPasswordScreen(),
      ),
      GoRoute(
        path: RouteNames.registerStep2,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('name-step'))),
      ),
      GoRoute(
        path: RouteNames.registerCode,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('code-step'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String pw, String confirm) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('step1_password')),
    pw,
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('step1_confirm')),
    confirm,
  );
  await tester.tap(find.byKey(const ValueKey<String>('reg_password_submit')));
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('uk'));

  testWidgets('renders 3-of-4 chrome, both fields and the checklist', (
    tester,
  ) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(tester, c);

    expect(
      tester.widget<WizardStepChrome>(find.byType(WizardStepChrome)).step,
      3,
    );
    expect(find.text(l10n.registerPasswordHeadline), findsWidgets);
    expect(find.byType(PasswordChecklist), findsOneWidget);
  });

  testWidgets('a weak password is blocked by the strict validator', (
    tester,
  ) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(tester, c);

    await _fill(tester, 'abc', 'abc');

    expect(find.text('name-step'), findsNothing);
    expect(c.read(registerDraftProvider)?.password, isEmpty);
  });

  testWidgets('a mismatch shows errPasswordsMismatch', (tester) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(tester, c);

    await _fill(tester, 'Secret1234', 'Secret12345');

    expect(find.text(l10n.errPasswordsMismatch), findsOneWidget);
    expect(find.text('name-step'), findsNothing);
  });

  testWidgets('a valid password is stored and the wizard goes to the name '
      'step', (tester) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(tester, c);

    await _fill(tester, 'Secret1234', 'Secret1234');

    expect(find.text('name-step'), findsOneWidget);
    expect(c.read(registerDraftProvider)?.password, 'Secret1234');
    expect(c.read(registerDraftProvider)?.email, isEmpty);
  });

  testWidgets('back goes to the code step', (tester) async {
    final c = _container();
    addTearDown(c.dispose);
    await _pump(tester, c);

    await tester.tap(find.byKey(const ValueKey<String>('auth_scaffold_back')));
    await tester.pumpAndSettle();
    expect(find.text('code-step'), findsOneWidget);
  });
}
