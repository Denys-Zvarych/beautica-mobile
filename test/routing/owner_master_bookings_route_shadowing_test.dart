// Phase 383 (24.1f) — `/owner/master/bookings/archive` resolves to ITS OWN
// literal `GoRoute` and nothing else can absorb it.
//
// `app_router.dart` registers, as siblings under the owner `/owner/master/*`
// ShellRoute, two LITERALS only:
//   • `/owner/master/bookings`          → MasterBookingsScreen
//   • `/owner/master/bookings/archive`  → MasterArchiveScreen
// Booking detail reuses the owner-admitted `/salon/bookings/:bookingId`, so
// there is deliberately NO dynamic segment under `/owner/master/bookings/`
// that could swallow `archive` as an id (the literal-before-dynamic trap the
// `/master/*` and `/salon/*` trees have to order around).
//
// A location-STRING check cannot tell which route matched (the string is the
// same whichever sibling absorbed it), so this asserts on the matched ROUTE
// OBJECT's own `path`, via go_router's own matcher on the PRODUCTION tree.
//
// MUTATION: added a `GoRoute(path: '${RouteNames.ownerMasterBookings}/:id')`
// sibling BEFORE the archive literal → the archive leaf's path became
// `/owner/master/bookings/:id` and the first test failed; the "no dynamic
// sibling" test failed on `/owner/master/bookings/b1` resolving. Restored.
//
// Layer: Unit over the real `appRouterProvider` route tree (no pump).

import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

class _OwnerAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'user-owner-U',
      email: 'owner@beautica.test',
      role: UserRole.salonOwner,
      hasMasterProfile: true,
    ),
    accessToken: 'token',
  );
}

GoRouter _productionRouter() {
  final container = makeTestContainer(
    overrides: [
      authProvider.overrideWith(_OwnerAuth.new),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
    ],
  );
  final GoRouter router = container.read(appRouterProvider);
  addTearDown(router.dispose);
  return router;
}

/// The matched LEAF route's own declared path — what tells two siblings with
/// the same location string apart.
String? _leafPath(GoRouter router, String location) {
  final RouteMatchList match = router.configuration.findMatch(
    Uri.parse(location),
  );
  if (match.isError || match.matches.isEmpty) return null;
  final RouteBase leaf = match.last.route;
  return leaf is GoRoute ? leaf.path : null;
}

void main() {
  test('/owner/master/bookings/archive matches ONLY its own literal route', () {
    final GoRouter router = _productionRouter();
    expect(
      _leafPath(router, RouteNames.ownerMasterBookingsArchive),
      RouteNames.ownerMasterBookingsArchive,
    );
  });

  test('/owner/master/bookings matches its own literal route', () {
    final GoRouter router = _productionRouter();
    expect(
      _leafPath(router, RouteNames.ownerMasterBookings),
      RouteNames.ownerMasterBookings,
    );
  });

  // Phase 383 (decision 2026-10-07) — the walk-in chain literals.
  test('/owner/master/bookings/new matches ONLY its own literal route '
      '(never the list, the archive or a detail)', () {
    final GoRouter router = _productionRouter();
    expect(
      _leafPath(router, RouteNames.ownerMasterBookingNew),
      RouteNames.ownerMasterBookingNew,
    );
  });

  test('/owner/master/bookings/new/services matches the `services` child of '
      'the owner `new` route', () {
    final GoRouter router = _productionRouter();
    final RouteMatchList match = router.configuration.findMatch(
      Uri.parse(RouteNames.ownerMasterBookingNewServices),
    );
    expect(match.isError, isFalse);
    // Walks INTO the owner ShellRoute's match (a top-level `matches` entry is
    // the shell, not its GoRoute children).
    final List<String> paths = <String>[];
    void collect(List<RouteMatchBase> matches) {
      for (final RouteMatchBase m in matches) {
        final RouteBase route = m.route;
        if (route is GoRoute) paths.add(route.path);
        if (m is ShellRouteMatch) collect(m.matches);
      }
    }

    collect(match.matches);
    expect(paths.last, 'services');
    expect(paths, contains(RouteNames.ownerMasterBookingNew));
    expect(paths, isNot(contains(RouteNames.ownerMasterBookingsArchive)));
    expect(paths, isNot(contains(RouteNames.masterBookings)));
  });

  test('no dynamic sibling lives under /owner/master/bookings/ — an id there '
      'is a router no-match (detail goes to /salon/bookings/:id)', () {
    final GoRouter router = _productionRouter();
    expect(
      router.configuration
          .findMatch(Uri.parse('${RouteNames.ownerMasterBookings}/b1'))
          .isError,
      isTrue,
    );
    expect(
      _leafPath(router, RouteNames.salonStaffBookingDetail('b1')),
      '${RouteNames.salonStaffBookings}/:bookingId',
      reason: 'the owner master-mode detail target must stay registered',
    );
  });
}
