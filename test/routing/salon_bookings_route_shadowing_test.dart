// Phase 250 — pins the RESOLVED screen TYPE for `/salon/bookings/new`, not
// merely that SOME `GoRoute` in the tree happens to carry a matching `path`
// string. Mirrors `test/routing/master_bookings_route_shadowing_test.dart`'s
// own rationale exactly — see that file's header for the full falsification
// story (commenting out the literal route left the OLD suite green because
// `:bookingId` silently absorbed the path).
//
// ## Why this route has no LIVE dynamic sibling to shadow it (today)
//
// `/salon/bookings/new` is registered as a STANDALONE top-level `GoRoute` —
// there is no `/salon/bookings/:bookingId` sibling yet (that would arrive
// with a future salon booking-detail phase). So THIS phase cannot reproduce
// the master wizard's exact "reorder two siblings" mutation — there is only
// one route to reorder against. The mutation this file DOES perform (see the
// bottom of this header) is the one that IS reachable today: deleting the
// route entirely and confirming the pin goes red, exactly the falsification
// `master_bookings_route_shadowing_test.dart` used BEFORE `archive`/`new`
// existed as a pair. The moment a future phase adds a dynamic
// `/salon/bookings/:bookingId` sibling under a shared parent, this test's
// assertion (resolved widget type, not merely "some route matched") is
// exactly what would catch that shadowing regression too — no rewrite
// needed, only a second `testWidgets` case mirroring the master file's pair.
//
// MUTATION-VERIFIED (see phase-250 report) — commenting out the
// `/salon/bookings/new` `GoRoute` in `app_router.dart` turns this test RED:
// `router.go(RouteNames.salonStaffBookingNew, extra: ...)` then resolves
// nothing under that path (go_router has no other route claiming that exact
// three-segment literal), and `find.byType(SalonCreateBookingScreen)`
// reports zero matches. Restoring the route turns it back GREEN.

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_masters_roster_notifier.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
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
// Fixtures — mirrors master_bookings_route_shadowing_test.dart's own.
// ---------------------------------------------------------------------------

const _fakeSalonOwner = User(
  id: 'owner-1',
  email: 'owner@example.com',
  role: UserRole.salonOwner,
  firstName: 'Настя',
  lastName: 'Салон',
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

/// [MySalons] stub that resolves immediately to an empty list. `mySalonsProvider`
/// is now `@Riverpod(keepAlive: true)` (mobile-perf HIGH follow-up,
/// 2026-08-28), so the plain `mySalonsProvider.overrideWith((ref) async =>
/// ...)` function override this file previously used no longer type-checks —
/// a keepAlive-class provider's `overrideWith` takes a notifier FACTORY, not
/// a build function.
class _SettledMySalons extends MySalons {
  @override
  Future<List<Salon>> build() async => const <Salon>[];
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
  group('app_router — /salon/bookings/new resolves its OWN screen', () {
    setUp(
      () => AppStartTime.setStartForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      ),
    );
    tearDown(AppStartTime.resetForTest);

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        retry: beauticaProviderRetry,
        overrides: [
          authProvider.overrideWith(
            () => _FixedAuthNotifier(_authenticatedSalonOwnerSession),
          ),
          authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
          secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
          // The screen's own data — never needs to SETTLE for this test
          // (which only asserts the resolved WIDGET TYPE), but must not
          // throw synchronously while building the provider graph.
          salonMastersRosterProvider.overrideWith((ref, salonId) async => []),
          salonMasterServiceCoverageProvider.overrideWith(
            (ref, args) async => {},
          ),
          salonServiceCatalogProvider.overrideWith((ref, salonId) async => []),
          // Phase 21.1 follow-up — the authenticated SALON_OWNER session's
          // global redirect (isAuthenticated + isAtSplash -> roleHomePath)
          // resolves to RouteNames.mySalons before this test's own
          // router.go() navigates away, momentarily mounting MySalonsScreen.
          // Settling mySalonsProvider keeps that transient mount off the
          // real Dio-backed salonRepositoryProvider (leaked-timer
          // regression — same shape every other override in this file
          // guards against).
          mySalonsProvider.overrideWith(_SettledMySalons.new),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    testWidgets('/salon/bookings/new resolves SalonCreateBookingScreen', (
      tester,
    ) async {
      final container = makeContainer();
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _RouterApp(router: router),
        ),
      );
      await tester.pump();

      router.go(RouteNames.salonStaffBookingNew, extra: 'salon-1');
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(SalonCreateBookingScreen),
        findsOneWidget,
        reason:
            'the route must resolve to the SALON wizard, not the home '
            'shell fallback (a missing/misrouted `new` segment) or any '
            'other screen',
      );
    });
  });
}

// Role-gate coverage (SALON_OWNER/SALON_ADMIN-only for `/salon/*`) lives as
// pure `authRedirectForLocation` cases in `test/routing/auth_redirect_test
// .dart`, mirroring that file's own `/master/working-hours` role-gate group
// — a widget-pumped variant here would additionally need to settle the
// CLIENT home shell's own unrelated provider graph (bottom-nav tiles, etc.)
// just to prove a redirect this file has no other reason to touch.
