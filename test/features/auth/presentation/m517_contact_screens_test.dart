// M517 — widget tests for the signed-in contact screens:
//
//   AddPhoneScreen (AUTH-D12): no back / PopScope blocks, non-UA number refused
//     inline before any request, a valid number sends the code and opens the
//     code-only step, an App Check 403 shows the banner, «Вийти» logs out.
//   ContactVerifyScreen (AUTH-D19): first add sends no password; a change asks
//     for it, shows «Невірний поточний пароль», locks after 10 wrong passwords
//     and pops `true` on success; the email step maps INVALID_CODE / 409.
//   NotificationEmailScreen (AUTH-50): bad email refused inline; a valid one
//     requests the code and returns `true` once confirmed.
//   Phone-first hardening: AUTH-D28 duplicate state on the add-phone step
//     (verify-time 409 pops back here; support mailto; field editable;
//     «Вийти» kept), M1 resend 429 keeps the cooldown on the code step, M7
//     the phone path's exhausted / expired code is INVALID_CODE copy.
//   QA additions: the lockout is ONE tally shared by the phone-change and
//     email steps and never touches a first add; a correct password clears
//     it; an email CHANGE starts from the confirmed address and replaces it.
//
// The auth redirect is not mounted here (it has its own matrix in
// test/routing/auth_redirect_test.dart) — each screen is driven directly.

import 'package:beautica_mobile/core/diagnostics/crash_reporting_enabled_provider.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/app_check_prefetch.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/contact_verify_args.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/add_phone_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/contact_verify_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/notification_email_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/widgets/phone_code_step.dart';
import 'package:beautica_mobile/features/auth/state/current_password_lockout_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../../integration_test/support/app_harness.dart';
import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_diagnostics_store.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';

const User _legacy = User(
  id: 'u-legacy',
  role: UserRole.client,
  email: 'legacy@b.ua',
  phoneNumber: '0441234567',
  phoneVerified: false,
  phoneRequiredBy: '2026-11-18',
  emailVerified: true,
);

const User _verified = User(
  id: 'u-ok',
  role: UserRole.independentMaster,
  phoneNumber: '+380671234545',
  phoneVerified: true,
  emailVerified: false,
);

/// A settled session for [user]; [logout] only flips to unauthenticated.
class _AuthStub extends AuthNotifier {
  _AuthStub(this.user);

  final User user;
  int logoutCalls = 0;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: user, accessToken: 't');

  @override
  Future<void> logout() async {
    logoutCalls++;
    state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
  }
}

final class _Harness {
  _Harness(
    this.user, {
    DateTime Function()? clock,
    AppCheckTokenPrefetcher? prefetcher,
  }) {
    container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [
        authRepositoryProvider.overrideWith((_) => repo),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        authProvider.overrideWith(() => auth),
        diagnosticsStoreProvider.overrideWithValue(FakeDiagnosticsStore()),
        if (clock != null) clockProvider.overrideWithValue(clock),
        if (prefetcher != null)
          appCheckTokenPrefetcherProvider.overrideWithValue(prefetcher),
      ],
    );
  }

  final User user;
  final FakeAuthRepository repo = FakeAuthRepository();
  late final _AuthStub auth = _AuthStub(user);
  late final ProviderContainer container;
  Object? hostResult = 'none';
}

Future<GoRouter> _pump(
  WidgetTester tester,
  _Harness h, {
  required String initialLocation,
  Object? initialExtra,
}) async {
  await h.container.read(authProvider.future);
  final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    initialExtra: initialExtra,
    routes: <RouteBase>[
      GoRoute(
        path: '/host',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('host-open'),
              onPressed: () async {
                h.hostResult = await context.push<bool>(
                  RouteNames.phoneChangeVerify,
                  extra: const ContactVerifyArgs(
                    kind: ContactVerifyKind.phoneChange,
                    target: '+380931112233',
                  ),
                );
              },
              child: const Text('host'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/email-host',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('email-host-open'),
              onPressed: () async {
                h.hostResult = await context.push<bool>(
                  RouteNames.notificationEmail,
                );
              },
              child: const Text('email-host'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: RouteNames.addPhone,
        builder: (context, state) => const AddPhoneScreen(),
      ),
      for (final String path in <String>[
        RouteNames.addPhoneVerify,
        RouteNames.phoneChangeVerify,
        RouteNames.notificationEmailVerify,
      ])
        GoRoute(
          path: path,
          builder: (context, state) =>
              ContactVerifyScreen(args: state.extra! as ContactVerifyArgs),
        ),
      GoRoute(
        path: RouteNames.notificationEmail,
        builder: (context, state) => const NotificationEmailScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: h.container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _key(String k) => find.byKey(ValueKey<String>(k));

/// `launchUrl` routes through [UrlLauncherPlatform.instance] (AUTH-D28 mailto).
class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

/// Records [n] wrong current passwords for [h]'s account, as the verify
/// steps do on each 400 CURRENT_PASSWORD_INVALID.
void _failPasswords(_Harness h, int n) {
  final CurrentPasswordLockoutNotifier lockout = h.container.read(
    currentPasswordLockoutProvider.notifier,
  );
  for (int i = 0; i < n; i++) {
    lockout.recordFailure(h.user.id);
  }
}

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<NeumorphicButton>(_key('phone_code_submit')).onPressedAsync !=
    null;

Future<void> _tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enterCodeAndPassword(
  WidgetTester tester, {
  String code = '123456',
  String? password,
}) async {
  await tester.enterText(_key('phone_code_input'), code);
  if (password != null) {
    await tester.enterText(_key('phone_code_current_password'), password);
  }
  await tester.pump();
}

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));

  group('AddPhoneScreen (AUTH-D12)', () {
    testWidgets('opening the add-phone step starts exactly one App Check '
        'prefetch (AUTH-D27 d, P2)', (tester) async {
      int fetches = 0;
      final AppCheckTokenPrefetcher prefetcher = AppCheckTokenPrefetcher(
        fetch: () async => 'tok-${++fetches}',
        canPrefetch: () => true,
        clock: () => DateTime.utc(2026, 11, 19, 10),
      );
      final _Harness h = _Harness(_legacy, prefetcher: prefetcher);
      addTearDown(h.container.dispose);

      await _pump(tester, h, initialLocation: RouteNames.addPhone);

      expect(fetches, 1);
      expect(await prefetcher.take(), 'tok-1', reason: 'no second fetch');
      expect(fetches, 1);
    });

    testWidgets('blocking: no back affordance and PopScope refuses a pop', (
      tester,
    ) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      await _pump(tester, h, initialLocation: RouteNames.addPhone);

      expect(_key('auth_scaffold_back'), findsNothing);
      expect(
        find.byWidgetPredicate((Widget w) => w is PopScope && !w.canPop),
        findsOneWidget,
      );
      expect(_key('add_phone_logout'), findsOneWidget);
    });

    testWidgets('a non-UA number is refused inline with no request', (
      tester,
    ) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      await _pump(tester, h, initialLocation: RouteNames.addPhone);

      await tester.enterText(_key('add_phone'), '0441234567');
      await _tapAndSettle(tester, _key('add_phone_submit'));

      expect(find.text(l10n.errPhoneNotUaMobile), findsOneWidget);
      expect(h.repo.sendPhoneCodeCalls, isEmpty);
    });

    testWidgets('a different valid number sends the code and opens the '
        'code-only step (legacy phone replaced, AUTH-44)', (tester) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      final GoRouter router = await _pump(
        tester,
        h,
        initialLocation: RouteNames.addPhone,
      );

      await tester.enterText(_key('add_phone'), '093 111 22 33');
      await _tapAndSettle(tester, _key('add_phone_submit'));

      expect(h.repo.sendPhoneCodeCalls, <String>['+380931112233']);
      expect(AppHarness.location(router), RouteNames.addPhoneVerify);
      expect(_key('phone_code_current_password'), findsNothing);

      h.repo.userAfterPhoneVerify = _legacy.copyWith(
        phoneNumber: '+380931112233',
        phoneVerified: true,
        phoneRequiredBy: null,
      );
      await _enterCodeAndPassword(tester);
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(h.repo.verifyPhoneCodeCalls.single.currentPassword, isNull);
      final AuthSession? s = h.container.read(authProvider).value;
      expect(s is Authenticated ? s.user.mustAddPhone : null, isFalse);
    });

    testWidgets('403 APP_CHECK_FAILED shows the send banner', (tester) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      h.repo.sendPhoneCodeFailure = const PhoneIdentityFailure(
        code: PhoneIdentityErrorCode.appCheckFailed,
      );
      await _pump(tester, h, initialLocation: RouteNames.addPhone);

      await tester.enterText(_key('add_phone'), '0931112233');
      await _tapAndSettle(tester, _key('add_phone_submit'));

      expect(_key('phone_send_error'), findsOneWidget);
      expect(find.text(l10n.errAppCheckFailed), findsOneWidget);
    });

    testWidgets('«Вийти» logs out', (tester) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      await _pump(tester, h, initialLocation: RouteNames.addPhone);

      await _tapAndSettle(tester, _key('add_phone_logout'));

      expect(h.auth.logoutCalls, 1);
    });
  });

  group('ContactVerifyScreen — phone change (AUTH-D19)', () {
    testWidgets('wrong password → inline error; success pops true', (
      tester,
    ) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      await _pump(tester, h, initialLocation: '/host');
      await _tapAndSettle(tester, find.byKey(const Key('host-open')));

      expect(_key('phone_code_current_password'), findsOneWidget);
      h.repo.verifyPhoneCodeFailure = const CurrentPasswordInvalidFailure();
      await _enterCodeAndPassword(tester, password: 'nope');
      await _tapAndSettle(tester, _key('phone_code_submit'));
      expect(find.text(l10n.errCurrentPasswordInvalid), findsOneWidget);
      expect(h.hostResult, 'none');

      h.repo.verifyPhoneCodeFailure = null;
      await _enterCodeAndPassword(tester, code: '654321', password: 'Right1');
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(h.repo.verifyPhoneCodeCalls.last.currentPassword, 'Right1');
      expect(h.hostResult, isTrue);
    });

    testWidgets('10 wrong passwords lock the step (banner, CTA off)', (
      tester,
    ) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      h.repo.verifyPhoneCodeFailure = const CurrentPasswordInvalidFailure();
      await _pump(tester, h, initialLocation: '/host');
      await _tapAndSettle(tester, find.byKey(const Key('host-open')));

      for (int i = 0; i < 10; i++) {
        await _enterCodeAndPassword(tester, password: 'wrong$i');
        await _tapAndSettle(tester, _key('phone_code_submit'));
      }

      expect(find.text(l10n.phoneCodeLocked), findsOneWidget);
      expect(
        tester
            .widget<NeumorphicButton>(_key('phone_code_submit'))
            .onPressedAsync,
        isNull,
      );
      expect(h.repo.verifyPhoneCodeCalls, hasLength(10));
    });

    testWidgets('409 PHONE_ALREADY_REGISTERED names another account', (
      tester,
    ) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      h.repo.verifyPhoneCodeFailure = const PhoneIdentityFailure(
        code: PhoneIdentityErrorCode.phoneAlreadyRegistered,
      );
      await _pump(tester, h, initialLocation: '/host');
      await _tapAndSettle(tester, find.byKey(const Key('host-open')));

      await _enterCodeAndPassword(tester, password: 'Right1');
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(find.text(l10n.errPhoneInUse), findsOneWidget);
    });

    testWidgets('a correct password clears the count: 9 wrong, then right, '
        'then 1 wrong does not lock', (tester) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      await _pump(tester, h, initialLocation: '/host');
      await _tapAndSettle(tester, find.byKey(const Key('host-open')));

      h.repo.verifyPhoneCodeFailure = const CurrentPasswordInvalidFailure();
      for (int i = 0; i < 9; i++) {
        await _enterCodeAndPassword(tester, password: 'wrong$i');
        await _tapAndSettle(tester, _key('phone_code_submit'));
      }
      h.repo.verifyPhoneCodeFailure = null;
      await _enterCodeAndPassword(tester, password: 'Right1');
      await _tapAndSettle(tester, _key('phone_code_submit'));
      expect(h.hostResult, isTrue);

      await _tapAndSettle(tester, find.byKey(const Key('host-open')));
      h.repo.verifyPhoneCodeFailure = const CurrentPasswordInvalidFailure();
      await _enterCodeAndPassword(tester, password: 'wrong-again');
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(find.text(l10n.errCurrentPasswordInvalid), findsOneWidget);
      expect(find.text(l10n.phoneCodeLocked), findsNothing);
      expect(_submitEnabled(tester), isTrue);
    });

    // Audit LOW (item 5): a step left open while locked unlocks by itself
    // when the 15-minute window ends (a timer at the unlock instant).
    testWidgets('an open locked step unlocks when the window ends', (
      tester,
    ) async {
      DateTime now = DateTime.utc(2026, 11, 18, 10);
      final _Harness h = _Harness(_verified, clock: () => now);
      addTearDown(h.container.dispose);
      _failPasswords(h, 10);
      await _pump(tester, h, initialLocation: '/host');
      await _tapAndSettle(tester, find.byKey(const Key('host-open')));
      expect(find.text(l10n.phoneCodeLocked), findsOneWidget);

      now = now.add(const Duration(minutes: 14, seconds: 59));
      // fixed-wait-ok: advances fake time to the 15-min unlock instant.
      await tester.pump(const Duration(minutes: 14, seconds: 59));
      expect(find.text(l10n.phoneCodeLocked), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      // fixed-wait-ok: advances fake time to the 15-min unlock instant.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(
        find.text(l10n.phoneCodeLocked),
        findsNothing,
        reason: 'no user action — the timer rebuilt the step',
      );
      await _enterCodeAndPassword(tester, password: 'Right1');
      expect(_submitEnabled(tester), isTrue);
    });

    testWidgets('a locked account cannot even send the correct password: '
        'reopening the step stays locked and sends nothing', (tester) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      _failPasswords(h, 10);
      await _pump(tester, h, initialLocation: '/host');
      await _tapAndSettle(tester, find.byKey(const Key('host-open')));

      await _enterCodeAndPassword(tester, password: 'Right1');
      await tester.tap(_key('phone_code_submit'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text(l10n.phoneCodeLocked), findsOneWidget);
      expect(h.repo.verifyPhoneCodeCalls, isEmpty);
      expect(h.hostResult, 'none');
    });
  });

  group('lockout scope (AUTH-D19: one tally for both paths, never a first '
      'add)', () {
    testWidgets('10 wrong passwords on the phone path lock the EMAIL step '
        'too', (tester) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      _failPasswords(h, 10);
      await _pump(tester, h, initialLocation: '/email-host');
      await _tapAndSettle(tester, find.byKey(const Key('email-host-open')));
      await tester.enterText(
        find.byKey(const Key('field-notification-email')),
        'olena@b.ua',
      );
      await _tapAndSettle(tester, find.byKey(const Key('btn-email-send-code')));

      await _enterCodeAndPassword(tester, password: 'Right1');
      await tester.tap(_key('phone_code_submit'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text(l10n.phoneCodeLocked), findsOneWidget);
      expect(_submitEnabled(tester), isFalse);
      expect(h.repo.verifyNotificationEmailCodeCalls, isEmpty);
    });

    testWidgets('a locked tally never blocks the first add (code only, no '
        'password)', (tester) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      _failPasswords(h, 10);
      await _pump(tester, h, initialLocation: RouteNames.addPhone);
      await tester.enterText(_key('add_phone'), '093 111 22 33');
      await _tapAndSettle(tester, _key('add_phone_submit'));

      expect(find.text(l10n.phoneCodeLocked), findsNothing);
      await _enterCodeAndPassword(tester);
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(h.repo.verifyPhoneCodeCalls, hasLength(1));
    });

    testWidgets('another account on the device is not locked by the first '
        "one's tally", (tester) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      final CurrentPasswordLockoutNotifier lockout = h.container.read(
        currentPasswordLockoutProvider.notifier,
      );
      for (int i = 0; i < 10; i++) {
        lockout.recordFailure('some-other-account');
      }
      await _pump(tester, h, initialLocation: '/host');
      await _tapAndSettle(tester, find.byKey(const Key('host-open')));
      await _enterCodeAndPassword(tester, password: 'Right1');

      expect(find.text(l10n.phoneCodeLocked), findsNothing);
      expect(_submitEnabled(tester), isTrue);
    });
  });

  group('NotificationEmailScreen + email code step (AUTH-50)', () {
    testWidgets('a malformed email is refused inline with no request', (
      tester,
    ) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      await _pump(tester, h, initialLocation: RouteNames.notificationEmail);

      await tester.enterText(
        find.byKey(const Key('field-notification-email')),
        'not-an-email',
      );
      await _tapAndSettle(tester, find.byKey(const Key('btn-email-send-code')));

      expect(find.text(l10n.errEmailInvalid), findsOneWidget);
      expect(h.repo.requestNotificationEmailCodeCalls, isEmpty);
    });

    testWidgets('code + password confirm the email and return true; a wrong '
        'code shows the code banner first', (tester) async {
      final _Harness h = _Harness(_verified);
      addTearDown(h.container.dispose);
      await _pump(tester, h, initialLocation: '/email-host');
      await _tapAndSettle(tester, find.byKey(const Key('email-host-open')));

      await tester.enterText(
        find.byKey(const Key('field-notification-email')),
        ' olena@b.ua ',
      );
      await _tapAndSettle(tester, find.byKey(const Key('btn-email-send-code')));
      expect(h.repo.requestNotificationEmailCodeCalls, <String>['olena@b.ua']);
      expect(find.textContaining('olena@b.ua'), findsOneWidget);
      expect(_key('phone_code_current_password'), findsOneWidget);

      h.repo.verifyNotificationEmailCodeFailure = const VerificationFailure(
        code: VerificationErrorCode.invalidCode,
      );
      await _enterCodeAndPassword(tester, password: 'Right1');
      await _tapAndSettle(tester, _key('phone_code_submit'));
      expect(find.text(l10n.verificationErrInvalidCode), findsOneWidget);

      h.repo.verifyNotificationEmailCodeFailure = null;
      h.repo.userAfterEmailVerify = _verified.copyWith(
        email: 'olena@b.ua',
        emailVerified: true,
      );
      await _enterCodeAndPassword(tester, code: '654321', password: 'Right1');
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(h.repo.verifyNotificationEmailCodeCalls.last.email, 'olena@b.ua');
      expect(h.hostResult, isTrue);
      final AuthSession? s = h.container.read(authProvider).value;
      expect(s is Authenticated ? s.user.confirmedEmail : null, 'olena@b.ua');
    });

    testWidgets('email CHANGE: the entry starts from the confirmed address; a '
        'new one is confirmed with code + password and replaces it', (
      tester,
    ) async {
      final User withEmail = _verified.copyWith(
        email: 'old@b.ua',
        emailVerified: true,
      );
      final _Harness h = _Harness(withEmail);
      addTearDown(h.container.dispose);
      await _pump(tester, h, initialLocation: '/email-host');
      await _tapAndSettle(tester, find.byKey(const Key('email-host-open')));

      final Finder field = find.descendant(
        of: find.byKey(const Key('field-notification-email')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(field).controller.text, 'old@b.ua');

      await tester.enterText(
        find.byKey(const Key('field-notification-email')),
        'new@b.ua',
      );
      await _tapAndSettle(tester, find.byKey(const Key('btn-email-send-code')));
      expect(h.repo.requestNotificationEmailCodeCalls, <String>['new@b.ua']);
      expect(_key('phone_code_current_password'), findsOneWidget);

      h.repo.userAfterEmailVerify = withEmail.copyWith(email: 'new@b.ua');
      await _enterCodeAndPassword(tester, password: 'Right1');
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(
        h.repo.verifyNotificationEmailCodeCalls.single.currentPassword,
        'Right1',
      );
      expect(h.hostResult, isTrue);
      final AuthSession? s = h.container.read(authProvider).value;
      expect(s is Authenticated ? s.user.confirmedEmail : null, 'new@b.ua');
    });

    testWidgets('email CHANGE with a wrong current password keeps the old '
        'address and counts toward the lockout', (tester) async {
      final User withEmail = _verified.copyWith(
        email: 'old@b.ua',
        emailVerified: true,
      );
      final _Harness h = _Harness(withEmail);
      addTearDown(h.container.dispose);
      h.repo.verifyNotificationEmailCodeFailure =
          const CurrentPasswordInvalidFailure();
      await _pump(tester, h, initialLocation: '/email-host');
      await _tapAndSettle(tester, find.byKey(const Key('email-host-open')));
      await tester.enterText(
        find.byKey(const Key('field-notification-email')),
        'new@b.ua',
      );
      await _tapAndSettle(tester, find.byKey(const Key('btn-email-send-code')));

      await _enterCodeAndPassword(tester, password: 'nope');
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(find.text(l10n.errCurrentPasswordInvalid), findsOneWidget);
      expect(h.hostResult, 'none');
      expect(
        h.container
            .read(currentPasswordLockoutProvider)[withEmail.id]
            ?.failures,
        1,
      );
      final AuthSession? s = h.container.read(authProvider).value;
      expect(s is Authenticated ? s.user.confirmedEmail : null, 'old@b.ua');
    });
  });

  group(
    'AddPhoneScreen — AUTH-D28 duplicate (409 PHONE_ALREADY_REGISTERED)',
    () {
      late _MockUrlLauncher launcher;
      late UrlLauncherPlatform originalPlatform;

      setUpAll(() => registerFallbackValue(const LaunchOptions()));
      setUp(() {
        originalPlatform = UrlLauncherPlatform.instance;
        launcher = _MockUrlLauncher();
        UrlLauncherPlatform.instance = launcher;
      });
      tearDown(() => UrlLauncherPlatform.instance = originalPlatform);

      /// Number → code step → code rejected with the verify-time 409.
      Future<GoRouter> reachDuplicate(WidgetTester tester, _Harness h) async {
        h.repo.verifyPhoneCodeFailure = const PhoneIdentityFailure(
          code: PhoneIdentityErrorCode.phoneAlreadyRegistered,
        );
        final GoRouter router = await _pump(
          tester,
          h,
          initialLocation: RouteNames.addPhone,
        );
        await tester.enterText(_key('add_phone'), '093 111 22 33');
        await _tapAndSettle(tester, _key('add_phone_submit'));
        expect(AppHarness.location(router), RouteNames.addPhoneVerify);
        await _enterCodeAndPassword(tester);
        await _tapAndSettle(tester, _key('phone_code_submit'));
        return router;
      }

      testWidgets('verify-time 409 returns to the add-phone step with the D28 '
          'copy, support action, editable field and «Вийти»', (tester) async {
        final _Harness h = _Harness(_legacy);
        addTearDown(h.container.dispose);
        final GoRouter router = await reachDuplicate(tester, h);

        expect(AppHarness.location(router), RouteNames.addPhone);
        expect(_key('add_phone_duplicate'), findsOneWidget);
        expect(find.text(l10n.addPhoneDuplicateMessage), findsOneWidget);
        // i18n-finder-ok: pins the AUTH-D28 uk copy verbatim (uk locale).
        expect(
          find.text(
            'Цей номер уже прив\'язаний до іншого акаунта. Можливо, ви вже '
            'зареєструвалися за цим номером — увійдіть у той акаунт або '
            'напишіть у підтримку, ми допоможемо.',
          ),
          findsOneWidget,
          reason: 'uk copy exactly as AUTH-D28',
        );
        // i18n-finder-ok: pins the AUTH-D28 uk copy verbatim (the test runs
        // in the uk locale); the key-based lookup is asserted above.
        expect(find.text('Написати в підтримку'), findsOneWidget);
        expect(_key('phone_send_error'), findsNothing);
        expect(_key('add_phone_logout'), findsOneWidget);
        expect(
          tester.widget<NeumorphicTextField>(_key('add_phone')).enabled,
          isTrue,
        );
        expect(h.auth.logoutCalls, 0);
      });

      testWidgets('«Написати в підтримку» opens a mailto to support with the '
          'subject', (tester) async {
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);
        final _Harness h = _Harness(_legacy);
        addTearDown(h.container.dispose);
        await reachDuplicate(tester, h);

        await _tapAndSettle(tester, _key('auth_banner_action'));

        final List<dynamic> captured = verify(
          () => launcher.launchUrl(captureAny(), any()),
        ).captured;
        final Uri uri = Uri.parse(captured.single as String);
        expect(uri.scheme, 'mailto');
        expect(uri.path, 'support@beautica.app');
        expect(
          uri.queryParameters['subject'],
          l10n.addPhoneSupportEmailSubject,
        );
        expect(
          find.text(l10n.addPhoneSupportOpenError('support@beautica.app')),
          findsNothing,
        );
      });

      testWidgets('no mail app → snack naming the support address', (
        tester,
      ) async {
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => false);
        final _Harness h = _Harness(_legacy);
        addTearDown(h.container.dispose);
        await reachDuplicate(tester, h);

        await _tapAndSettle(tester, _key('auth_banner_action'));

        expect(
          find.text(l10n.addPhoneSupportOpenError('support@beautica.app')),
          findsOneWidget,
        );
      });

      testWidgets(
        'editing the number clears the state; «Вийти» still logs out',
        (tester) async {
          final _Harness h = _Harness(_legacy);
          addTearDown(h.container.dispose);
          await reachDuplicate(tester, h);

          await tester.enterText(_key('add_phone'), '093 111 22 3');
          await tester.pump();
          expect(_key('add_phone_duplicate'), findsNothing);

          await _tapAndSettle(tester, _key('add_phone_logout'));
          expect(h.auth.logoutCalls, 1);
        },
      );

      testWidgets('a 409 on send (defensive) shows the same state', (
        tester,
      ) async {
        final _Harness h = _Harness(_legacy);
        addTearDown(h.container.dispose);
        h.repo.sendPhoneCodeFailure = const PhoneIdentityFailure(
          code: PhoneIdentityErrorCode.phoneAlreadyRegistered,
        );
        await _pump(tester, h, initialLocation: RouteNames.addPhone);

        await tester.enterText(_key('add_phone'), '0931112233');
        await _tapAndSettle(tester, _key('add_phone_submit'));

        expect(_key('add_phone_duplicate'), findsOneWidget);
        expect(_key('phone_send_error'), findsNothing);
      });
    },
  );

  group('ContactVerifyScreen — phone add code step', () {
    Future<void> openCodeStep(WidgetTester tester, _Harness h) async {
      await _pump(tester, h, initialLocation: RouteNames.addPhone);
      await tester.enterText(_key('add_phone'), '0931112233');
      await _tapAndSettle(tester, _key('add_phone_submit'));
    }

    Future<void> tapResend(WidgetTester tester) async {
      await tester.tap(_key('phone_code_resend'));
      await tester.pump();
      await tester.pump();
    }

    // M7 — the phone path never answers CODE_EXPIRED (AUTH-D19): an
    // exhausted or expired phone code arrives as INVALID_CODE and shows the
    // «Невірний код» copy, never the email «code expired» copy.
    testWidgets('M7: exhausted / expired phone code → INVALID_CODE copy', (
      tester,
    ) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      h.repo.verifyPhoneCodeFailure = const PhoneIdentityFailure(
        code: PhoneIdentityErrorCode.invalidCode,
      );
      await openCodeStep(tester, h);

      await _enterCodeAndPassword(tester);
      await _tapAndSettle(tester, _key('phone_code_submit'));

      expect(find.text(l10n.errPhoneCodeInvalid), findsOneWidget);
      expect(find.text(l10n.verificationErrCodeExpired), findsNothing);
      expect(_key('add_phone_duplicate'), findsNothing);
    });

    testWidgets('M1: resend 429 keeps the cooldown (60 s fallback)', (
      tester,
    ) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      await openCodeStep(tester, h);
      expect(h.repo.sendPhoneCodeCalls, hasLength(1));

      h.repo.sendPhoneCodeFailure = const PhoneIdentityFailure(
        code: PhoneIdentityErrorCode.rateLimited,
      );
      // fixed-wait-ok: TTL crossing — the arrival cooldown must fully elapse.
      await tester.pump(
        const Duration(seconds: kPhoneCodeResendCooldownSeconds),
      );
      await tapResend(tester);
      expect(h.repo.sendPhoneCodeCalls, hasLength(2));
      expect(find.text(l10n.errPhoneCodeRateLimited), findsOneWidget);

      await tapResend(tester);
      expect(h.repo.sendPhoneCodeCalls, hasLength(2));
      // fixed-wait-ok: TTL crossing — one second short of the 429 cooldown.
      await tester.pump(
        const Duration(seconds: kPhoneCodeResendCooldownSeconds - 1),
      );
      await tapResend(tester);
      expect(h.repo.sendPhoneCodeCalls, hasLength(2));
      // fixed-wait-ok: TTL crossing — the 429 cooldown fully elapses.
      await tester.pump(const Duration(seconds: 1));
      await tapResend(tester);
      expect(h.repo.sendPhoneCodeCalls, hasLength(3));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('M1: resend 429 with Retry-After 0 still waits 60 s', (
      tester,
    ) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      await openCodeStep(tester, h);

      h.repo.sendPhoneCodeFailure = const PhoneIdentityFailure(
        code: PhoneIdentityErrorCode.rateLimited,
        retryAfterSeconds: 0,
      );
      // fixed-wait-ok: TTL crossing — the arrival cooldown must fully elapse.
      await tester.pump(
        const Duration(seconds: kPhoneCodeResendCooldownSeconds),
      );
      await tapResend(tester);
      expect(h.repo.sendPhoneCodeCalls, hasLength(2));
      await tapResend(tester);
      expect(h.repo.sendPhoneCodeCalls, hasLength(2), reason: 'not unlocked');
      // fixed-wait-ok: TTL crossing — the 60 s fallback fully elapses.
      await tester.pump(
        const Duration(seconds: kPhoneCodeResendCooldownSeconds),
      );
      await tapResend(tester);
      expect(h.repo.sendPhoneCodeCalls, hasLength(3));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('M1: a network error on resend re-enables the link at once', (
      tester,
    ) async {
      final _Harness h = _Harness(_legacy);
      addTearDown(h.container.dispose);
      await openCodeStep(tester, h);

      h.repo.sendPhoneCodeFailure = const NetworkFailure();
      // fixed-wait-ok: TTL crossing — the arrival cooldown must fully elapse.
      await tester.pump(
        const Duration(seconds: kPhoneCodeResendCooldownSeconds),
      );
      await tapResend(tester);
      await tapResend(tester);
      expect(h.repo.sendPhoneCodeCalls, hasLength(3));

      await tester.pumpWidget(const SizedBox());
    });
  });
}
