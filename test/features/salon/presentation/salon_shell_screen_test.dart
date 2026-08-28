// Phase 21.8 QA follow-up — widget tests for [SalonShellScreen].
//
// Before this file the shell had almost no direct coverage: only the
// router-tier `role_landing_chrome_test.dart` mounted it, and only through
// ONE fixture (a salon the owner already owns) that never exercises tab
// switching, the LAZY TABS mechanism, or the provider's per-salonId reset.
//
// Covers:
//   1. Салон renders by default; Записи/Команда/Профіль are lazy
//      (`SizedBox.shrink`) until first visited.
//   2. Tapping each `SalonBottomNav` tile switches the visible body
//      (`IndexedStack.index`).
//   3. Салон vs Команда host the SAME `SalonManagementProfileScreen` with
//      `initialTab` 0 (unset) vs 1 respectively.
//   4. Once visited, a tab's real widget REPLACES the lazy placeholder
//      permanently (not just for the one frame it was selected).
//   5. Switching away and back to a visited tab preserves that tab's State
//      object — the whole point of the lazy-but-never-disposed design
//      (`IndexedStack` never uses Offstage/TickerMode for its non-current
//      children, so nothing here needs `AutomaticKeepAliveClientMixin`).
//   6. `salonShellProvider` is family-keyed on `salonId` — selecting a tab
//      for one salon leaves a DIFFERENT salon's provider instance untouched
//      at its default (0).
//
// Ownership-bounce coverage (the H1b double-mount hazard + the AsyncData
// concrete-subtype gate) lives in `role_landing_chrome_test.dart` (H1b) and
// its own regression group below — see that file and
// `salon_management_profile_screen_test.dart` for the sibling gate.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_management_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_shell_provider.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_management_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_shell_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_shell_tab_placeholder.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const String _kSalonId = 'shell-salon-1';
const String _kOtherSalonId = 'shell-salon-2';

const _stubOwner = User(
  id: 'owner-shell-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Власник',
);

const _stubAdmin = User(
  id: 'admin-shell-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Адміністратор',
  salonId: _kSalonId,
);

const _stubSalon = Salon(id: _kSalonId, name: 'Salon Shell Test');

class _OwnerAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubOwner, accessToken: 'tok');
}

class _AdminAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubAdmin, accessToken: 'tok');
}

/// [MySalons] stub that resolves immediately to a list CONTAINING
/// [_kSalonId] — the owner genuinely owns the shell's salon, so
/// `_bounceIfNotOwned` never fires and does not interfere with the tab
/// mechanics under test here.
class _OwnedMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[_stubSalon];
}

/// [SalonManagementProfile] stub that resolves immediately — settles both
/// the Салон and Команда tabs (same family key, `_kSalonId`) off the real
/// Dio stack.
class _SettledSalonManagementProfile extends SalonManagementProfile {
  @override
  Future<SalonManagementProfileData> build(String salonId) async =>
      (_stubSalon, const <SalonMasterSummary>[]);
}

List<Object> _ownerOverrides() => <Object>[
  authProvider.overrideWith(_OwnerAuthNotifier.new),
  mySalonsProvider.overrideWith(_OwnedMySalons.new),
  salonManagementProfileProvider(
    _kSalonId,
  ).overrideWith(_SettledSalonManagementProfile.new),
];

List<Object> _adminOverrides() => <Object>[
  authProvider.overrideWith(_AdminAuthNotifier.new),
  salonManagementProfileProvider(
    _kSalonId,
  ).overrideWith(_SettledSalonManagementProfile.new),
];

void main() {
  group('default tab + lazy construction', () {
    testWidgets('Салон renders by default; the other 3 tabs are lazy '
        'placeholders until visited', (tester) async {
      await tester.pumpApp(
        const SalonShellScreen(salonId: _kSalonId),
        overrides: _ownerOverrides(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SalonBottomNav), findsOneWidget);
      expect(find.byKey(const Key('salon-shell-tab-salon')), findsOneWidget);
      // The other 3 slots are still the trivial lazy placeholder — the real
      // hosts have never been built. `skipOffstage: false` is REQUIRED here:
      // `IndexedStack` keeps its non-current children mounted but marks them
      // offstage, and `find.byKey`'s default `skipOffstage: true` silently
      // excludes them — without this the assertion would pass (or fail)
      // for the wrong reason regardless of whether the lazy child is really
      // there (mobile-qa M14: a finder that can't see the thing it is
      // checking is a vacuous assertion in disguise).
      expect(
        find.byKey(const Key('salon-shell-tab-1-lazy'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-shell-tab-2-lazy'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-shell-tab-3-lazy'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byType(SalonShellTabPlaceholder, skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('salon-shell-tab-team'), skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('tab switching (IndexedStack via SalonBottomNav taps)', () {
    testWidgets('tapping each nav item switches the visible body', (
      tester,
    ) async {
      await tester.pumpApp(
        const SalonShellScreen(salonId: _kSalonId),
        overrides: _ownerOverrides(),
      );
      await tester.pumpAndSettle();

      // Tab 1 — Записи.
      await tester.tap(find.byKey(const Key('salon-nav-tile-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-shell-tab-bookings')), findsOneWidget);
      // The lazy placeholder key is GONE (not merely offstage) — visiting a
      // tab replaces it permanently, per the file-header LAZY TABS note.
      expect(
        find.byKey(const Key('salon-shell-tab-1-lazy'), skipOffstage: false),
        findsNothing,
      );

      // Tab 2 — Команда.
      await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-shell-tab-team')), findsOneWidget);

      // Tab 3 — Профіль (owner suffix).
      await tester.tap(find.byKey(const Key('salon-nav-tile-3')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('salon-shell-tab-profile-owner')),
        findsOneWidget,
      );

      // Back to tab 0 — Салон. The point of the lazy-but-never-disposed
      // design: all 3 previously-visited tabs (Записи/Команда/Профіль) must
      // STILL be mounted (offstage, not removed) — `skipOffstage: false`
      // proves presence rather than accepting the vacuous "not currently
      // visible" reading `findsNothing` would give by default.
      await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('salon-shell-tab-salon')), findsOneWidget);
      expect(
        find.byKey(const Key('salon-shell-tab-bookings'), skipOffstage: false),
        findsOneWidget,
        reason: 'a previously-visited tab must remain MOUNTED, just offstage',
      );
      expect(
        find.byKey(const Key('salon-shell-tab-team'), skipOffstage: false),
        findsOneWidget,
        reason: 'a previously-visited tab must remain MOUNTED, just offstage',
      );
      expect(
        find.byKey(
          const Key('salon-shell-tab-profile-owner'),
          skipOffstage: false,
        ),
        findsOneWidget,
        reason: 'a previously-visited tab must remain MOUNTED, just offstage',
      );
    });

    testWidgets('admin Профіль tab uses the admin key suffix', (tester) async {
      await tester.pumpApp(
        const SalonShellScreen(salonId: _kSalonId),
        overrides: _adminOverrides(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-nav-tile-3')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('salon-shell-tab-profile-admin')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('salon-shell-tab-profile-owner')),
        findsNothing,
      );
    });
  });

  group('Салон vs Команда initialTab', () {
    testWidgets(
      'Салон hosts SalonManagementProfileScreen with initialTab unset '
      '(defaults to 0); Команда hosts the SAME screen with initialTab 1',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();

        final salonTab = tester.widget<SalonManagementProfileScreen>(
          find.byKey(const Key('salon-shell-tab-salon')),
        );
        expect(salonTab.initialTab, isNull);
        expect(salonTab.embedded, isTrue);
        expect(salonTab.salonId, equals(_kSalonId));

        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();

        final teamTab = tester.widget<SalonManagementProfileScreen>(
          find.byKey(const Key('salon-shell-tab-team')),
        );
        expect(teamTab.initialTab, equals(1));
        expect(teamTab.embedded, isTrue);
        expect(teamTab.salonId, equals(_kSalonId));
      },
    );
  });

  group('lazy child state survives switching away and back', () {
    testWidgets(
      'the Команда tab keeps the SAME State instance after switching to '
      'another tab and back — proving IndexedStack never disposes it',
      (tester) async {
        await tester.pumpApp(
          const SalonShellScreen(salonId: _kSalonId),
          overrides: _ownerOverrides(),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();
        final State teamStateBefore = tester.state(
          find.byKey(const Key('salon-shell-tab-team')),
        );

        // Switch away to Салон, then to Записи, then BACK to Команда.
        await tester.tap(find.byKey(const Key('salon-nav-tile-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('salon-nav-tile-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
        await tester.pumpAndSettle();

        final State teamStateAfter = tester.state(
          find.byKey(const Key('salon-shell-tab-team')),
        );
        expect(
          identical(teamStateBefore, teamStateAfter),
          isTrue,
          reason:
              'the Команда tab\'s State must be the SAME object across a '
              'round trip through two other tabs — a fresh State here would '
              'mean the lazy child was rebuilt/disposed, defeating the '
              'documented "survives every subsequent switch" guarantee.',
        );
      },
    );
  });

  group('salonShellProvider family isolation', () {
    testWidgets('selecting a tab for one salonId leaves a DIFFERENT salonId\'s '
        'provider instance at its default (0)', (tester) async {
      final container = ProviderContainer(
        // ignore: avoid_dynamic_calls
        overrides: _ownerOverrides().cast(),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('uk'),
            home: SalonShellScreen(salonId: _kSalonId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('salon-nav-tile-2')));
      await tester.pumpAndSettle();

      expect(container.read(salonShellProvider(_kSalonId)), equals(2));
      expect(
        container.read(salonShellProvider(_kOtherSalonId)),
        equals(0),
        reason:
            'salonShellProvider is family-keyed on salonId — selecting a '
            'tab for $_kSalonId must never leak into a different salon\'s '
            'provider instance.',
      );
    });
  });

  // -------------------------------------------------------------------
  // mobile-qa gap-closure (2026-08-28) — the shell's OWN `_bounceIfNotOwned`
  // (`salon_shell_screen.dart:141`) gates on the SAME concrete `AsyncData`
  // subtype as `salon_management_profile_screen.dart`'s sibling listener
  // (see that file's own mutation-verified regression group) and
  // `app_router.dart`'s `salonManageGuard`. Pinned here with the identical
  // technique (driving `mySalonsProvider` directly via the notifier's own
  // `state` setter, bypassing `build()`, so the listener is never exposed to
  // an intermediate genuinely-resolved mismatched frame — see the sibling
  // file's group doc for why that intermediate shape is not the interesting
  // case).
  //
  // Sanity mutation-checked (not re-run as part of this suite): replacing
  // `if (next is! AsyncData<List<Salon>>) return;` with a bare
  // `final salons = next.value; if (salons == null) return;` in
  // `salon_shell_screen.dart` turns this test RED for the same reason the
  // sibling screen's mutation does.
  group('shell _bounceIfNotOwned does not trust a stale .value '
      '(mobile-security MEDIUM follow-up gap-closure)', () {
    testWidgets('AsyncError with a previous .value that does NOT contain the '
        'shell\'s salonId is treated as UNRESOLVED -> the shell stays '
        'mounted, never bounced on stale/wrong data', (tester) async {
      final container = ProviderContainer(
        // ignore: avoid_dynamic_calls
        overrides: _ownerOverrides().cast(),
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: RouteNames.salonShell(_kSalonId),
        routes: <RouteBase>[
          GoRoute(
            path: '/salons/:salonId/shell',
            builder: (context, state) =>
                SalonShellScreen(salonId: state.pathParameters['salonId']!),
          ),
          GoRoute(
            path: RouteNames.salonHome,
            builder: (context, state) =>
                const Scaffold(key: Key('shell-bounce-target')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SalonShellScreen), findsOneWidget);

      // Drive mySalonsProvider DIRECTLY into an AsyncError carrying a
      // stale, MISMATCHED .value via copyWithPrevious — see the sibling
      // regression group in `salon_management_profile_screen_test.dart`
      // for why this is the only public-API-reachable way to construct
      // this exact state shape, and why `copyWithPrevious` (`@internal`
      // to the riverpod package) is deliberately used here regardless.
      final AsyncError<List<Salon>> staleError = AsyncError<List<Salon>>(
        const NetworkFailure(),
        StackTrace.current,
      );
      const AsyncData<List<Salon>> stalePrevious = AsyncData<List<Salon>>(
        <Salon>[Salon(id: 'a-different-salon-entirely', name: 'Different')],
      );
      // ignore: invalid_use_of_internal_member
      container.read(mySalonsProvider.notifier).state = staleError
          // ignore: invalid_use_of_internal_member
          .copyWithPrevious(stalePrevious);
      await tester.pumpAndSettle();

      expect(
        container.read(mySalonsProvider),
        isA<AsyncError<List<Salon>>>(),
        reason:
            'the state must actually BE an AsyncError for this test to '
            'exercise the concrete-subtype gate at all',
      );
      expect(
        find.byType(SalonShellScreen),
        findsOneWidget,
        reason:
            'an AsyncError state — even one carrying a stale, '
            'non-owning .value — must be treated as UNRESOLVED and '
            'never bounce the shell away',
      );
      expect(find.byKey(const Key('shell-bounce-target')), findsNothing);
    });
  });
}
