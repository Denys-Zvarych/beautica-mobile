// Shell-owned ClientTopBar behaviour net (2026-06-24 wordmark-jump hoist).
//
// The CLIENT top bar (wordmark · bell · burger) is now mounted ONCE by
// [ClientShell] above `navigationShell`, NOT per branch screen. This test pins
// the per-branch bar CONFIG that used to be asserted inside the individual
// screen tests (home_hub_screen_test / search_filters_screen_test /
// passport_screen_test) but no longer can be — those screens no longer build a
// bar. It boots the REAL [appRouter] as an authenticated CLIENT, hops each
// branch via the real bottom-nav tiles, and asserts:
//   • the per-branch bell + burger Keys (home → btn-menu-client, passport →
//     btn-menu-passport, favorites/bookings → their own keys, search omits the
//     burger);
//   • the burger icon (Icons.tune_rounded) + the bell button presence;
//   • tapping the burger pushes the CLIENT settings hub (/client/menu).
//
// Finders key off Keys + Types + route constants — never raw Ukrainian text
// (mobile-qa M2). Pumps are bounded (pumpAndSettle after each hop; the staggered
// reveal is a one-shot SlideTransition that settles).

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/home/presentation/client_settings_hub_screen.dart';
import 'package:beautica_mobile/features/shell/presentation/client_shell.dart';
import 'package:beautica_mobile/features/shell/presentation/widgets/client_top_bar.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes/fake_auth_repository.dart';
import '../../helpers/fakes/fake_secure_storage.dart';

void main() {
  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  group('shell-owned ClientTopBar — per-branch config', () {
    testWidgets('home (branch 0) mounts the bar with btn-menu-client + bell', (
      tester,
    ) async {
      final harness = await _ShellHarness.boot(tester);

      // Landed on /home with the shell + its single bar.
      expect(harness.currentLocation, equals(RouteNames.clientHome));
      expect(find.byType(ClientShell), findsOneWidget);
      expect(find.byType(ClientTopBar), findsOneWidget);

      // Home: bell + burger present, burger uses the preserved btn-menu-client
      // Key and the tune_rounded glyph.
      expect(find.byKey(const Key('home_hub_bell_button')), findsOneWidget);
      expect(find.byKey(const Key('btn-menu-client')), findsOneWidget);
      expect(find.byType(NeumorphicIconButton), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      harness.dispose();
    });

    testWidgets('tapping the home burger pushes the CLIENT settings hub', (
      tester,
    ) async {
      final harness = await _ShellHarness.boot(tester);

      await tester.tap(find.byKey(const Key('btn-menu-client')));
      await tester.pumpAndSettle();

      // The push lands ClientSettingsHubScreen (/client/menu) ON TOP of the
      // shell branch — so the shell's base `.uri` stays /home while the topmost
      // matched location is /client/menu. Assert both: the destination screen
      // rendered AND the topmost route is the settings hub.
      expect(
        find.byType(ClientSettingsHubScreen),
        findsOneWidget,
        reason: 'shell burger onTap must push the CLIENT settings hub screen',
      );
      expect(
        harness.topLocation,
        equals(RouteNames.clientMenu),
        reason: 'topmost pushed route must be RouteNames.clientMenu',
      );

      harness.dispose();
    });

    testWidgets('search (branch 2) omits the burger — bell only', (
      tester,
    ) async {
      final harness = await _ShellHarness.boot(tester);
      await harness.goBranch(kClientSearchBranch);

      expect(harness.currentLocation, equals(RouteNames.clientSearch));
      // Bell still present under its search Key…
      expect(find.byKey(const Key('search_bell_button')), findsOneWidget);
      // …but the burger is omitted on Пошук: the only NeumorphicIconButton in
      // the bar is the burger, so a zero count proves it did not render.
      expect(find.byType(NeumorphicIconButton), findsNothing);

      harness.dispose();
    });

    testWidgets('passport (branch 4) keeps the btn-menu-passport burger Key', (
      tester,
    ) async {
      final harness = await _ShellHarness.boot(tester);
      await harness.goBranch(kClientPassportBranch);

      expect(harness.currentLocation, equals(RouteNames.clientPassport));
      expect(find.byKey(const Key('passport_bell_button')), findsOneWidget);
      expect(find.byKey(const Key('btn-menu-passport')), findsOneWidget);

      harness.dispose();
    });

    testWidgets('favorites (branch 1) + bookings (branch 3) show the burger', (
      tester,
    ) async {
      final harness = await _ShellHarness.boot(tester);

      await harness.goBranch(kClientFavoritesBranch);
      expect(harness.currentLocation, equals(RouteNames.clientFavorites));
      expect(find.byKey(const Key('btn-menu-favorites')), findsOneWidget);

      await harness.goBranch(kClientBookingsBranch);
      expect(harness.currentLocation, equals(RouteNames.clientBookings));
      expect(find.byKey(const Key('btn-menu-bookings')), findsOneWidget);

      harness.dispose();
    });
  });
}

// ---------------------------------------------------------------------------
// Harness — boots the real router as an authenticated CLIENT.
// ---------------------------------------------------------------------------

class _ShellHarness {
  _ShellHarness._(this.tester, this.container, this.router);

  final WidgetTester tester;
  final ProviderContainer container;
  final GoRouter router;

  static Future<_ShellHarness> boot(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(_clientSession())),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk', 'UA'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return _ShellHarness._(tester, container, router);
  }

  String get currentLocation =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// The topmost matched location — reflects a route PUSHED on top of the shell
  /// (the shell's base `.uri` does not change on a push, only on a goBranch).
  String get topLocation =>
      router.routerDelegate.currentConfiguration.last.matchedLocation;

  Future<void> goBranch(int branchIndex) async {
    final Finder control = branchIndex == kClientSearchBranch
        ? find.byKey(const Key('client-nav-search-center'))
        : find.byKey(Key('client-nav-tile-$branchIndex'));
    expect(control, findsOneWidget);
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  void dispose() {
    router.dispose();
    container.dispose();
  }
}

AsyncData<AuthSession> _clientSession() => const AsyncData<AuthSession>(
  AuthSession.authenticated(
    user: User(
      id: 'u-client',
      email: 'client@example.com',
      role: UserRole.client,
      firstName: 'Test',
      lastName: 'Client',
    ),
    accessToken: 'token',
  ),
);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);

  final AsyncValue<AuthSession> _fixed;

  @override
  Future<AuthSession> build() async {
    state = _fixed;
    return _fixed.value ?? const AuthSession.unauthenticated();
  }
}
