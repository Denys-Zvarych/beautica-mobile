// Phase 21.3 QA follow-up — pins the RESOLVED screen TYPE for
// `/salons/register`, not merely that SOME `GoRoute` in the tree happens to
// carry a matching `path` string. Mirrors `test/routing/
// my_salons_route_shadowing_test.dart` / `test/routing/
// salon_bookings_route_shadowing_test.dart`'s own rationale exactly — see
// those files' headers for the full falsification story (a reordered/
// deleted literal sibling left the OLD suite green because the dynamic
// sibling silently absorbed the path).
//
// WHY THIS FILE EXISTS
// ---------------------
// `app_router.dart` registers `/salons/register` as a STANDALONE top-level
// literal `GoRoute` — the THIRD literal under the `/salons/` prefix
// (alongside `/salons/mine` and `/salons/home`) — declared BEFORE the
// dynamic `/salons/:salonId` sibling immediately below it
// (`RouteNames.registerSalon`'s own doc: "registered BEFORE the dynamic
// /salons/:salonId route ... otherwise /salons/register would resolve to
// the public-profile route with salonId == 'register'"). go_router resolves
// literal-vs-dynamic segments PURELY by declaration order among siblings —
// nothing except that ordering (and an inline comment on each route warning
// it must never change) enforces it.
//
// `grep -a -rn "find.byType(RegisterSalonScreen)" test/` returned exactly
// ONE hit before this file — `register_salon_screen_test.dart`'s own
// `SALON_OWNER-only gate` group — but that file drives a HAND-ROLLED
// two-route `GoRouter` (`_router()`), never the real `app_router.dart`, so
// it cannot see a declaration-order regression in the real route tree.
// `test/features/salon/presentation/my_salons_screen_test.dart`'s own CTA
// test similarly builds a hand-rolled stub `GoRouter`. And
// `test/routing/navigation_links_test.dart`'s NL-R01 only asserts
// `match.isError == false` — that stays green even if `/salons/register`
// were shadowed, because the dynamic `/salons/:salonId` sibling still
// resolves the SAME location string without error; the string is IDENTICAL
// whether the literal `registerSalon` route or the shadowing
// `/salons/:salonId` route (with `salonId == 'register'`) resolved it.
// Deleting/reordering the literal route would therefore leave both of those
// existing suites green while a SALON_OWNER silently landed on
// `PublicSalonProfileScreen` (the CLIENT-facing public profile) instead of
// the «+ Додати салон» form.
//
// MUTATION-VERIFIED (mobile-qa, 2026-08-29) — moving the
// `RouteNames.registerSalon` `GoRoute` registration in `app_router.dart` to
// AFTER the dynamic `/salons/:salonId` sibling turns this test RED:
// `router.go(RouteNames.registerSalon)` then resolves `PublicSalonProfileScreen`
// (with `salonId == 'register'`) instead, and `find.byType(RegisterSalonScreen)`
// reports zero matches. Restoring the original order turns it back GREEN
// with a clean `git diff`. See the QA report for the exact commands run.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/public_salon_profile_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/register_salon_screen.dart';
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
// Fixtures — mirrors my_salons_route_shadowing_test.dart's own.
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

/// [MySalons] stub that resolves IMMEDIATELY — keeps the hub/register form
/// off `SkeletonShimmerScope`'s never-settling repeating shimmer (see
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
  group('app_router — /salons/register resolves RegisterSalonScreen, not '
      'the /salons/:salonId shadow', () {
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

    testWidgets('/salons/register resolves RegisterSalonScreen', (
      tester,
    ) async {
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

      router.go(RouteNames.registerSalon);
      await tester.pumpAndSettle();

      expect(
        find.byType(RegisterSalonScreen),
        findsOneWidget,
        reason:
            'the route must resolve to the «+ Додати салон» form, not the '
            'public salon profile shadow (a missing/reordered literal '
            'route)',
      );
      expect(
        find.byType(PublicSalonProfileScreen),
        findsNothing,
        reason:
            'if the dynamic /salons/:salonId sibling absorbed "register" as '
            'a salonId, this would render instead',
      );
    });
  });
}
