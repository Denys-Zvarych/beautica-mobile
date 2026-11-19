// Phase 2.16 / M515 — Widget tests for [RegisterStep1Screen], the PHONE step
// of the phone-first registration wizard (AUTH-D11 / AUTH-41).
//
// Covered scenarios:
//   1. Phone field + 1/4 wizard chrome + phone icon tile render; no email or
//      password field (those moved / were dropped).
//   2. A non-UA-mobile number shows «Потрібен український мобільний номер»
//      inline and sends NOTHING (AUTH-D15).
//   3. A valid number is normalised to +380…, the code is sent, the draft
//      holds the phone + tick, and the wizard advances to /register/code.
//   4. 429 / 403 APP_CHECK_FAILED / 503 APP_CHECK_UNAVAILABLE render the
//      preview's inline banner copy and stay on step 1.
//   5. 409 PHONE_ALREADY_REGISTERED arrival banner carries «Увійти» → /login.
//   6. Step 1 never registers (the POST runs on the address step).
//   7. auth_scaffold_back → /register/role; step1_login_link → /login + reset.
//  18-21. Terms / privacy links (unchanged).
//  22-25. Consent gate (phase 443).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/register_flow_shell.dart';
import 'package:beautica_mobile/features/auth/presentation/register_step_1_screen.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GoRouter _makeRouter() => GoRouter(
  initialLocation: RouteNames.register,
  redirect: (context, state) => null,
  routes: [
    GoRoute(
      path: RouteNames.register,
      // RegisterStep1Screen now returns its own AuthScaffold (full Scaffold).
      // Place it directly as the route widget — no wrapper needed.
      builder: (context, state) => const RegisterStep1Screen(),
    ),
    GoRoute(
      path: RouteNames.registerCode,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('code-step'))),
    ),
    GoRoute(
      path: RouteNames.registerRole,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('role-selection'))),
    ),
    GoRoute(
      path: RouteNames.login,
      builder: (context, state) =>
          const Scaffold(body: Center(child: Text('login'))),
    ),
  ],
);

Widget _buildApp({
  required GoRouter router,
  required ProviderContainer container,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk'),
  ),
);

ProviderContainer _makeContainer({UserRole? role = UserRole.client}) {
  final repo = FakeAuthRepository();
  final storage = FakeSecureStorage();
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authRepositoryProvider.overrideWith((_) => repo),
      secureStorageProvider.overrideWith((_) => storage),
    ],
  );
  if (role != null) {
    container.read(registerDraftProvider.notifier).start(role);
  }
  return container;
}

/// Asserts the [FakeAuthRepository.registerCalls] list is empty — i.e. Step 1
/// did NOT fire a registration POST.
void _assertNoRegisterPostFired(FakeAuthRepository repo) {
  expect(
    repo.registerCalls,
    isEmpty,
    reason:
        'register_step_1_screen.dart must NOT call AuthNotifier.register — '
        'the real POST happens at the end of Step 3 (Phase 2.19)',
  );
}

/// Variant that returns the [FakeAuthRepository] handle alongside the container.
({ProviderContainer container, FakeAuthRepository repo})
_makeContainerWithRepo({UserRole? role = UserRole.client}) {
  final repo = FakeAuthRepository();
  final storage = FakeSecureStorage();
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: [
      authRepositoryProvider.overrideWith((_) => repo),
      secureStorageProvider.overrideWith((_) => storage),
    ],
  );
  if (role != null) {
    container.read(registerDraftProvider.notifier).start(role);
  }
  return (container: container, repo: repo);
}

/// Phase 443 — ticks the required terms-consent checkbox (no-op if ticked)
/// so `step1_submit` is enabled.
Future<void> _tickTerms(WidgetTester tester) async {
  final Finder box = find.byKey(const ValueKey<String>('step1_terms_checkbox'));
  if (tester.widget<Checkbox>(box).value != true) {
    await tester.ensureVisible(box);
    await tester.tap(box);
    await tester.pump();
  }
}

/// Mock [UrlLauncherPlatform] — `launchUrl(uri, mode: ...)` routes through
/// `UrlLauncherPlatform.instance.launchUrl(url, options)`, so swapping the
/// instance asserts the exact URL + mode without firing a real intent.
class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

/// Finds the inline [TextSpan] carrying [identifier] inside the terms line.
TextSpan? _linkSpan(WidgetTester tester, String identifier) {
  final RichText rich = tester.widget<RichText>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('step1_terms_line')),
      matching: find.byType(RichText),
    ),
  );
  TextSpan? found;
  rich.text.visitChildren((InlineSpan span) {
    if (span is TextSpan && span.semanticsIdentifier == identifier) {
      found = span;
      return false;
    }
    return true;
  });
  return found;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  final router = _makeRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(_buildApp(router: router, container: container));
  await tester.pumpAndSettle();
}

Future<void> _submitPhone(WidgetTester tester, String phone) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('step1_phone')),
    phone,
  );
  await _tickTerms(tester);
  await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('uk'));

  group('RegisterStep1Screen (M515 phone step)', () {
    testWidgets('1. phone field, 1-of-4 chrome and phone tile; no email / '
        'password fields', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(find.byKey(const ValueKey<String>('step1_phone')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('step1_email')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('step1_password')),
        findsNothing,
      );
      expect(find.text(l10n.registerPhoneHelper), findsOneWidget);
      expect(find.text(l10n.registerSendCode), findsOneWidget);
      expect(find.byKey(const Key('step1_icon_tile')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('step1_icon_tile')),
          matching: find.byIcon(Icons.phone_iphone_rounded),
        ),
        findsOneWidget,
      );
      // 4 progress dots (phone -> code -> password -> name).
      expect(
        find.descendant(
          of: find.byType(WizardStepChrome),
          matching: find.byType(AnimatedContainer),
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('2. a non-UA-mobile number is refused inline, nothing sent', (
      tester,
    ) async {
      final h = _makeContainerWithRepo();
      addTearDown(h.container.dispose);
      await _pump(tester, h.container);

      await _submitPhone(tester, '+48 512 345 678');

      expect(find.text(l10n.errPhoneNotUaMobile), findsOneWidget);
      expect(h.repo.sendRegistrationCodeCalls, isEmpty);
      expect(find.text('code-step'), findsNothing);
    });

    testWidgets('3. a valid number is normalised, sent, stored and the wizard '
        'advances to /register/code', (tester) async {
      final h = _makeContainerWithRepo();
      addTearDown(h.container.dispose);
      await _pump(tester, h.container);

      await _submitPhone(tester, '0671234567');

      expect(h.repo.sendRegistrationCodeCalls, <String>['+380671234567']);
      expect(find.text('code-step'), findsOneWidget);
      final draft = h.container.read(registerDraftProvider);
      expect(draft?.phone, '+380671234567');
      expect(draft?.termsAccepted, isTrue);
      _assertNoRegisterPostFired(h.repo);
    });

    for (final (PhoneIdentityErrorCode code, String copy)
        in <(PhoneIdentityErrorCode, String)>[
          (
            PhoneIdentityErrorCode.rateLimited,
            'Забагато запитів коду. Спробуйте пізніше.',
          ),
          (
            PhoneIdentityErrorCode.appCheckFailed,
            'Не вдалося підтвердити, що запит надіслано із застосунку Beautica. '
                'Оновіть застосунок із Google Play і спробуйте ще раз.',
          ),
          (
            PhoneIdentityErrorCode.appCheckUnavailable,
            'Перевірка тимчасово недоступна. Спробуйте за хвилину.',
          ),
        ]) {
      testWidgets('4. ${code.name} shows the preview copy and stays', (
        tester,
      ) async {
        final h = _makeContainerWithRepo();
        addTearDown(h.container.dispose);
        h.repo.sendRegistrationCodeFailure = PhoneIdentityFailure(code: code);
        await _pump(tester, h.container);

        await _submitPhone(tester, '0671234567');

        expect(
          find.byKey(const ValueKey<String>('phone_send_error')),
          findsOneWidget,
        );
        expect(find.text(copy), findsOneWidget);
        expect(find.text('code-step'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('auth_banner_action')),
          findsNothing,
        );
      });
    }

    testWidgets('5. 409 PHONE_ALREADY_REGISTERED banner offers «Увійти» → '
        '/login', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: RouteNames.register,
        routes: [
          GoRoute(
            path: RouteNames.register,
            builder: (context, state) => const RegisterStep1Screen(
              initialSendError: PhoneIdentityErrorCode.phoneAlreadyRegistered,
            ),
          ),
          GoRoute(
            path: RouteNames.login,
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('login'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      expect(find.text(l10n.errPhoneAlreadyRegistered), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('auth_banner_action')),
      );
      await tester.pumpAndSettle();
      expect(find.text('login'), findsOneWidget);
      expect(container.read(registerDraftProvider), isNull);
    });

    testWidgets('7a. auth_scaffold_back → /register/role, draft kept', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pump(tester, container);

      await tester.tap(
        find.byKey(const ValueKey<String>('auth_scaffold_back')),
      );
      await tester.pumpAndSettle();

      expect(find.text('role-selection'), findsOneWidget);
      expect(container.read(registerDraftProvider), isNotNull);
    });

    testWidgets('7b. step1_login_link → /login and resets the draft', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pump(tester, container);

      final Finder link = find.byKey(
        const ValueKey<String>('step1_login_link'),
      );
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(container.read(registerDraftProvider), isNull);
    });
  });

  group('RegisterStep1Screen — terms / privacy links', () {
    late _MockUrlLauncher launcher;
    late UrlLauncherPlatform originalPlatform;
    final AppLocalizations l10n = lookupAppLocalizations(const Locale('uk'));

    setUpAll(() => registerFallbackValue(const LaunchOptions()));

    setUp(() {
      originalPlatform = UrlLauncherPlatform.instance;
      launcher = _MockUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    tearDown(() => UrlLauncherPlatform.instance = originalPlatform);

    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();
    }

    Future<void> tapLink(WidgetTester tester, String text) async {
      await tester.tapOnText(
        find.textRange.ofSubstring(
          text,
          descendentOf: find.byKey(const ValueKey<String>('step1_terms_line')),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final (String name, String Function() label, String url)
        in <(String, String Function(), String)>[
          (
            '18. terms',
            () => l10n.registerTermsTerms,
            'https://beautica.app/terms',
          ),
          (
            '19. privacy',
            () => l10n.registerTermsPrivacy,
            'https://beautica.app/privacy',
          ),
        ]) {
      testWidgets('$name link launches $url in the external browser', (
        tester,
      ) async {
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);
        await pumpScreen(tester);

        await tapLink(tester, label());

        final List<dynamic> captured = verify(
          () => launcher.launchUrl(captureAny(), captureAny()),
        ).captured;
        expect(captured, hasLength(2), reason: 'exactly one launch');
        expect(captured[0], url);
        expect(
          (captured[1] as LaunchOptions).mode,
          PreferredLaunchMode.externalApplication,
        );
        // Still on Step 1 — the link never navigates in-app.
        expect(find.text('step-2'), findsNothing);
        expect(find.text(l10n.externalLinkOpenError), findsNothing);
      });
    }

    testWidgets('20. a failed launch shows the externalLinkOpenError snack', (
      tester,
    ) async {
      when(
        () => launcher.launchUrl(any(), any()),
      ).thenAnswer((_) async => false);
      await pumpScreen(tester);

      await tapLink(tester, l10n.registerTermsPrivacy);

      expect(find.text(l10n.externalLinkOpenError), findsOneWidget);
    });

    testWidgets('21. both link spans carry a stable semanticsIdentifier and '
        'a tap recognizer', (tester) async {
      await pumpScreen(tester);

      final TextSpan? terms = _linkSpan(tester, 'step1_terms_link');
      final TextSpan? privacy = _linkSpan(tester, 'step1_privacy_link');
      expect(terms?.text, l10n.registerTermsTerms);
      expect(privacy?.text, l10n.registerTermsPrivacy);
      expect(terms?.recognizer, isNotNull);
      expect(privacy?.recognizer, isNotNull);
      verifyNever(() => launcher.launchUrl(any(), any()));
    });
  });

  group('RegisterStep1Screen — terms consent gate (phase 443)', () {
    NeumorphicButton submit(WidgetTester tester) =>
        tester.widget<NeumorphicButton>(
          find.byKey(const ValueKey<String>('step1_submit')),
        );

    testWidgets('22. step1_submit is disabled until the box is ticked, and '
        'unticking disables it again', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pump(tester, container);

      expect(submit(tester).onPressedAsync, isNull);
      await _tickTerms(tester);
      expect(submit(tester).onPressedAsync, isNotNull);
      await tester.tap(
        find.byKey(const ValueKey<String>('step1_terms_checkbox')),
      );
      await tester.pump();
      expect(submit(tester).onPressedAsync, isNull);
    });

    testWidgets('23. tapping the disabled submit sends nothing', (
      tester,
    ) async {
      final h = _makeContainerWithRepo();
      addTearDown(h.container.dispose);
      await _pump(tester, h.container);

      await tester.enterText(
        find.byKey(const ValueKey<String>('step1_phone')),
        '0671234567',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('step1_submit')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('code-step'), findsNothing);
      expect(h.repo.sendRegistrationCodeCalls, isEmpty);
    });

    testWidgets('24. the tick and phone survive a back-navigation to Step 1', (
      tester,
    ) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      final router = _makeRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router: router, container: container));
      await tester.pumpAndSettle();

      await _submitPhone(tester, '0671234567');
      expect(find.text('code-step'), findsOneWidget);

      router.go(RouteNames.register);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey<String>('step1_terms_checkbox')),
            )
            .value,
        isTrue,
      );
      expect(find.text('+380 67 123 45 67'), findsOneWidget);
      expect(submit(tester).onPressedAsync, isNotNull);
    });

    testWidgets('25. disabled submit carries the consent-required semantics '
        'hint; it is gone once ticked', (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await _pump(tester, container);

      Finder hint() => find.byWidgetPredicate(
        (Widget w) =>
            w is Semantics &&
            w.properties.hint == l10n.termsConsentRequiredHint,
      );
      expect(hint(), findsOneWidget);
      await _tickTerms(tester);
      expect(hint(), findsNothing);
    });
  });
}
