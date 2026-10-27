// Branch fix/login-unverified-403 — E2E: legal links + OTP keyboard re-show.
//
// 1. Logged-in INDEPENDENT_MASTER → master menu → «Акаунт» → «Правова
//    інформація» → «Політика конфіденційності»: the platform launcher receives
//    exactly `https://beautica.app/privacy` in externalApplication mode, and
//    the user stays on /settings.
// 2. Registration step 1 → the inline «Умови використання» link: the launcher
//    receives exactly `https://beautica.app/terms`; no in-app navigation.
// 3. Registration wizard → /verification: the IME is hidden while the OTP
//    field keeps focus (Android back / hide), a tap on a code cell re-shows it.
//    This drives the framework's TestTextInput channel, not a real IME — a
//    real-keyboard check needs Patrol (see the QA report).
//
// The platform launcher is mocked (no browser under flutter-tester), same
// pattern as guest_phone_tap_to_call_flow_test.dart. Taps are key-based except
// the inline TextSpan link, which has no widget of its own and is hit by its
// localised substring scoped to the keyed terms line.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../test/helpers/overflow_guard.dart';
import 'support/app_harness.dart';

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

final AppLocalizationsUk _l10n = AppLocalizationsUk();
const ValueKey<String> _termsLine = ValueKey<String>('step1_terms_line');
const ValueKey<String> _otpInput = ValueKey<String>('verify_code_input');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockUrlLauncher launcher;
  late UrlLauncherPlatform original;

  setUp(() {
    installOverflowGuard();
    original = UrlLauncherPlatform.instance;
    launcher = _MockUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    registerFallbackValue(const LaunchOptions());
    when(() => launcher.launchUrl(any(), any())).thenAnswer((_) async => true);
  });
  tearDown(() async {
    UrlLauncherPlatform.instance = original;
    await AppHarness.tearDownHarness();
  });

  /// The single launch: returns (url, mode).
  (String, PreferredLaunchMode) singleLaunch() {
    final List<dynamic> captured = verify(
      () => launcher.launchUrl(captureAny(), captureAny()),
    ).captured;
    expect(captured, hasLength(2), reason: 'exactly one launch');
    return (captured[0] as String, (captured[1] as LaunchOptions).mode);
  }

  /// /register/role → CLIENT → /register (step 1).
  Future<GoRouter> openStep1(WidgetTester tester, FakeBackend fb) async {
    final GoRouter router = await AppHarness.boot(tester, fb);
    router.go(RouteNames.registerRole);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('role_client')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('role_continue')));
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.register);
    return router;
  }

  testWidgets('Account «Політика конфіденційності» opens '
      'https://beautica.app/privacy in the external browser', (tester) async {
    final fb = FakeBackend()..currentRole = UserRole.independentMaster;
    final GoRouter router = await AppHarness.boot(tester, fb);
    await AppHarness.loginAs(tester, fb, UserRole.independentMaster);

    await tester.tap(find.byKey(const Key('btn-menu-master')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('row-account')));
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.settings);

    const Key row = Key('row-privacy-policy');
    await tester.ensureVisible(find.byKey(row));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(row));
    await tester.pumpAndSettle();

    final (String url, PreferredLaunchMode mode) = singleLaunch();
    expect(url, 'https://beautica.app/privacy');
    expect(mode, PreferredLaunchMode.externalApplication);
    AppHarness.expectLocation(router, RouteNames.settings);
    expect(find.text(_l10n.externalLinkOpenError), findsNothing);
  });

  testWidgets('registration step 1 «Умови використання» link opens '
      'https://beautica.app/terms in the external browser', (tester) async {
    final GoRouter router = await openStep1(tester, FakeBackend());

    await tester.ensureVisible(find.byKey(_termsLine));
    await tester.pumpAndSettle();
    await tester.tapOnText(
      find.textRange.ofSubstring(
        _l10n.registerTermsTerms,
        descendentOf: find.byKey(_termsLine),
      ),
    );
    await tester.pumpAndSettle();

    final (String url, PreferredLaunchMode mode) = singleLaunch();
    expect(url, 'https://beautica.app/terms');
    expect(mode, PreferredLaunchMode.externalApplication);
    AppHarness.expectLocation(router, RouteNames.register);
  });

  testWidgets('/verification: a tap on a code cell re-shows the keyboard '
      'hidden while the OTP field kept focus', (tester) async {
    final fb = FakeBackend();
    final GoRouter router = await openStep1(tester, fb);

    await tester.enterText(
      find.byKey(const ValueKey<String>('step1_email')),
      'new@beautica.ua',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('step1_password')),
      'Secret1234',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('step1_confirm')),
      'Secret1234',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('step1_submit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('step2_first_name')),
      'Тест',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('step2_last_name')),
      'Клієнт',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('step2_phone')),
      '+380501111111',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('step2_submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('address_skip')));
    await tester.pumpAndSettle();
    AppHarness.expectLocation(router, RouteNames.verification);

    // Autofocus opened the IME on arrival.
    final EditableTextState editable = tester.state<EditableTextState>(
      find.descendant(
        of: find.byKey(_otpInput),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.widget.focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    // Android back / IME hide: keyboard gone, focus kept.
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(editable.widget.focusNode.hasFocus, isTrue);

    // Tap the first visible code CELL — not the 1x1 hidden TextField at the
    // centre, and not the row's blank padding (the GestureDetector defers to
    // its children for hit-testing).
    final Finder otpRow = find
        .ancestor(
          of: find.byKey(_otpInput),
          matching: find.byType(GestureDetector),
        )
        .first;
    final Finder firstCell = find
        .descendant(of: otpRow, matching: find.byType(AnimatedContainer))
        .first;
    await tester.tap(firstCell);
    await tester.pump();

    expect(
      tester.testTextInput.isVisible,
      isTrue,
      reason: 'tapping a code cell must re-show the IME',
    );
    expect(editable.widget.focusNode.hasFocus, isTrue);
  });
}
