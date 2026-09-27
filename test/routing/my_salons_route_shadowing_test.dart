// Phase 21.1 QA follow-up — pins the RESOLVED screen TYPE for
// `/salons/mine`, not merely that SOME `GoRoute` in the tree happens to
// carry a matching `path` string. Mirrors `test/routing/
// salon_bookings_route_shadowing_test.dart` / `test/routing/
// master_bookings_route_shadowing_test.dart`'s own rationale exactly — see
// those files' headers for the full falsification story (a reordered/
// deleted literal sibling left the OLD suite green because the dynamic
// sibling silently absorbed the path).
//
// WHY THIS FILE EXISTS
// ---------------------
// `app_router.dart` registers `/salons/mine` as a STANDALONE top-level
// literal `GoRoute`, declared BEFORE the dynamic `/salons/:salonId` sibling
// immediately below it (`RouteNames.mySalons`'s own doc: "A LITERAL path
// under the same `/salons/` prefix ... declared BEFORE the dynamic"). go_router
// resolves literal-vs-dynamic segments PURELY by declaration order among
// siblings — nothing except that ordering (and an inline comment on each
// route warning it must never change) enforces it.
//
// `grep -a -rn "find.byType(MySalonsScreen)" test/` returned ZERO hits
// anywhere in the suite before this file (mobile-qa Phase 21.1 audit).
// `test/routing/navigation_links_test.dart`-style location-string checks
// (`router.configuration.findMatch(...).uri.toString() == '/salons/mine'`)
// cannot catch this: the string is IDENTICAL whether the literal `mySalons`
// route or the shadowing `/salons/:salonId` route (with `salonId ==
// 'mine'`) resolved it — deleting the literal route would leave a
// string-only suite green while a SALON_OWNER silently landed on
// `PublicSalonProfileScreen` (the CLIENT-facing public profile) instead of
// their own hub.
//
// MUTATION-VERIFIED (mobile-qa, 2026-08-28) — commenting out the
// `RouteNames.mySalons` `GoRoute` in `app_router.dart` turns this test RED:
// `router.go(RouteNames.mySalons)` then resolves `PublicSalonProfileScreen`
// (with `salonId == 'mine'`) instead, and `find.byType(MySalonsScreen)`
// reports zero matches. Restoring the route turns it back GREEN with a
// clean `git diff`. See the QA report for the exact commands run.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';

// ---------------------------------------------------------------------------
// Fixtures — mirrors salon_bookings_route_shadowing_test.dart's own.
// ---------------------------------------------------------------------------

const _fakeSalonOwner = User(
  id: 'owner-1',
  email: 'owner@example.com',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Власниця',
);

const _authenticatedSalonOwnerSession = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _fakeSalonOwner, accessToken: 'token'),
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

/// [MySalons] stub that resolves IMMEDIATELY — keeps the hub off
/// `SkeletonShimmerScope`'s never-settling repeating shimmer (see
/// `salon_manage_route_guard_test.dart`'s `pumpRouterAs` doc for the full
/// trap) and off the real Dio-backed `salonRepositoryProvider`.
class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[
    Salon(id: 'salon-owner-1', name: 'Test Salon', isPrimary: true),
  ];
}

class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  group('app_router — /salons/mine resolves MySalonsScreen, not the '
      '/salons/:salonId shadow', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(_authenticatedSalonOwnerSession),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          mySalonsProvider.overrideWith(_SettledMySalons.new),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('/salons/mine resolves MySalonsScreen', (tester) async {
      final container = makeContainer();
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pumpAndSettle();

      router.go(RouteNames.mySalons);
      await tester.pumpAndSettle();

      expect(
        find.byType(MySalonsScreen),
        findsOneWidget,
        reason:
            'the route must resolve to the OWNER\'s hub, not the public '
            'salon profile shadow (a missing/reordered literal route)',
      );
      expect(
        find.byType(PublicSalonProfileScreen),
        findsNothing,
        reason:
            'if the dynamic /salons/:salonId sibling absorbed "mine" as '
            'a salonId, this would render instead',
      );
    });
  });
}
