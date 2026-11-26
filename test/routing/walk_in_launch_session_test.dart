// M543 (CLI-80, CLI-D15, BOOK-80) — «Записати» vs. the SESSION, on the
// PRODUCTION router. `clients_routes_test.dart` pins the binding for a
// settled session; this file pins what happens around it.
//
//   1. Late-settling role (D2): the card route's launcher is decided per
//      BUILD from the STRICT settled role — `null` (no button) while the
//      session is loading or seamlessly refreshing, non-null once it settles.
//      A cold card location is parked on /splash for the whole loading
//      window, so the hidden state is never even rendered.
//   2. Logout / role change while the salon wizard is open from a card
//      launch (D6): the top-level redirect re-resolves the stack to /login or
//      the role home, the `WalkInLaunch` extra does not survive, and nothing
//      carries the prefill's PII. A router-key change that still ADMITS the
//      wizard restores the stack through go_router's JSON codec, which drops
//      the (non-JSON) `WalkInLaunch` — the salon wizard then degrades to the
//      missing-extra fallback (pops back to the card) instead of throwing.
//
// Layer: routing unit (route builders / redirect / restore seams of the real
// `appRouterProvider`); no network, no storage.

import 'dart:async';
import 'dart:convert';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart'
    show WalkInGuest;
import 'package:beautica_mobile/features/booking/domain/walk_in_launch.dart';
import 'package:beautica_mobile/features/booking/presentation/salon_create_booking_screen.dart';
import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/test_container.dart';

const String _kSalonId = 's-1';
const String _kFirst = 'Оксана';
const String _kLast = 'Мельник';
const String _kPhone = '+380671234567';

const ClientPrefill _prefill = ClientPrefill(
  firstName: _kFirst,
  lastName: _kLast,
  phone: _kPhone,
);

const WalkInLaunch _launch = WalkInLaunch(
  prefill: _prefill,
  salonId: _kSalonId,
);

const String _imCard = '${RouteNames.masterClients}/user/u-1';
const String _salonCard = '/salons/$_kSalonId/clients/user/u-1';

AuthSession _signedIn(UserRole role) => AuthSession.authenticated(
  user: User(
    id: 'u-${role.name}',
    email: 'a@b.c',
    role: role,
    salonId: _kSalonId,
  ),
  accessToken: 't',
);

/// Each `build()` waits on the next [gates] completer — the session settles
/// only when the test completes it. [emit] sets a settled state directly.
class _GatedAuth extends AuthNotifier {
  final List<Completer<AuthSession>> gates = <Completer<AuthSession>>[];

  @override
  Future<AuthSession> build() {
    final Completer<AuthSession> gate = Completer<AuthSession>();
    gates.add(gate);
    return gate.future;
  }

  void emit(AuthSession session) => state = AsyncData<AuthSession>(session);
}

class _Harness {
  _Harness() {
    container = makeTestContainer(
      overrides: <Object>[
        authProvider.overrideWith(() => auth),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ],
    );
    container.listen(authProvider, (_, _) {});
    router = container.read(appRouterProvider);
    addTearDown(router.dispose);
  }

  final _GatedAuth auth = _GatedAuth();
  late final ProviderContainer container;
  late final GoRouter router;

  Future<void> settle(UserRole role) async {
    auth.gates.last.complete(_signedIn(role));
    await container.read(authProvider.future);
  }

  RouteMatchList match(String location, {Object? extra}) {
    final RouteMatchList m = router.configuration.findMatch(
      Uri.parse(location),
      extra: extra,
    );
    expect(m.isError, isFalse, reason: location);
    return m;
  }

  /// The production card leaf for [location], built NOW.
  ClientCardScreen card(BuildContext context, String location) {
    final RouteMatchList m = match(location);
    return m.last.route.builder!(
          context,
          router.configuration.buildTopLevelGoRouterState(m),
        )
        as ClientCardScreen;
  }

  /// The production redirect chain (top-level + route-level) for [from].
  Future<RouteMatchList> resolve(
    BuildContext context,
    RouteMatchList from,
  ) async => router.configuration.redirect(
    context,
    from,
    redirectHistory: <RouteMatchList>[],
  );
}

Future<BuildContext> _context(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox(key: Key('ctx')));
  return tester.element(find.byKey(const Key('ctx')));
}

void main() {
  group('late-settling role (D2)', () {
    for (final (UserRole role, String location) in <(UserRole, String)>[
      (UserRole.independentMaster, _imCard),
      (UserRole.salonOwner, _salonCard),
    ]) {
      testWidgets('${role.name}: cold $location → no «Записати» while the '
          'session loads; appears once the role settles', (tester) async {
        final _Harness h = _Harness();
        final BuildContext context = await _context(tester);
        expect(h.container.read(authProvider).isLoading, isTrue);

        expect(h.card(context, location).onBookClient, isNull);

        await h.settle(role);
        expect(h.card(context, location).onBookClient, isNotNull);
      });
    }

    testWidgets('a seamless session refresh (stale Authenticated carried) '
        'hides «Записати» until it settles again', (tester) async {
      final _Harness h = _Harness();
      final BuildContext context = await _context(tester);
      await h.settle(UserRole.independentMaster);
      expect(h.card(context, _imCard).onBookClient, isNotNull);

      h.container.invalidate(authProvider);
      // Flush the scheduled refresh (Riverpod schedules it on a 0 ms timer;
      // a bare `pump()` elapses no fake time, so it would stay pending).
      await tester.pump(Duration.zero);
      final AsyncValue<AuthSession> refreshing = h.container.read(authProvider);
      // The shape the lenient selector would still read a role from.
      expect(refreshing.isLoading, isTrue);
      expect(refreshing.value, isA<Authenticated>());

      expect(h.card(context, _imCard).onBookClient, isNull);

      await h.settle(UserRole.independentMaster);
      expect(h.card(context, _imCard).onBookClient, isNotNull);
    });

    testWidgets('a cold card location is parked on /splash while the '
        'session loads (the hidden state is never rendered)', (tester) async {
      final _Harness h = _Harness();
      final BuildContext context = await _context(tester);

      for (final String location in <String>[_imCard, _salonCard]) {
        final RouteMatchList to = await h.resolve(context, h.match(location));
        expect(to.uri.path, RouteNames.splash, reason: location);
      }
    });
  });

  // BOOK-80 / CLI-80 (user 2026-11-26) — the IM card launch of a complete
  // client pushes the service step directly; the production redirect chain
  // admits it with the WalkInGuest extra and bounces it without one.
  group('IM card launch skips the client step (BOOK-80)', () {
    const WalkInGuest guest = WalkInGuest(
      name: _kFirst,
      surname: _kLast,
      phone: _kPhone,
    );

    testWidgets('settled IM + WalkInGuest → admitted to the service step, '
        'the extra intact, no PII in the location', (tester) async {
      final _Harness h = _Harness();
      final BuildContext context = await _context(tester);
      await h.settle(UserRole.independentMaster);
      final RouteMatchList to = await h.resolve(
        context,
        h.match(RouteNames.masterBookingNewServices, extra: guest),
      );
      expect(to.uri.path, RouteNames.masterBookingNewServices);
      expect(to.extra, same(guest));
      for (final String pii in <String>[_kFirst, _kLast, _kPhone]) {
        expect('${to.uri}'.contains(pii), isFalse, reason: pii);
      }
    });

    testWidgets('no extra → bounced to the client step', (tester) async {
      final _Harness h = _Harness();
      final BuildContext context = await _context(tester);
      await h.settle(UserRole.independentMaster);
      final RouteMatchList to = await h.resolve(
        context,
        h.match(RouteNames.masterBookingNewServices),
      );
      expect(to.uri.path, RouteNames.masterBookingNew);
    });

    testWidgets('salon owner + WalkInGuest → never the IM service step', (
      tester,
    ) async {
      final _Harness h = _Harness();
      final BuildContext context = await _context(tester);
      await h.settle(UserRole.salonOwner);
      final RouteMatchList to = await h.resolve(
        context,
        h.match(RouteNames.masterBookingNewServices, extra: guest),
      );
      expect(to.uri.path, isNot(RouteNames.masterBookingNewServices));
    });
  });

  group('session change with the salon wizard open (D6)', () {
    Future<(_Harness, BuildContext)> ownerWithWizard(
      WidgetTester tester,
    ) async {
      final _Harness h = _Harness();
      final BuildContext context = await _context(tester);
      await h.settle(UserRole.salonOwner);
      final RouteMatchList open = await h.resolve(
        context,
        h.match(RouteNames.salonStaffBookingNew, extra: _launch),
      );
      // Precondition: the owner is admitted with the launch intact.
      expect(open.uri.path, RouteNames.salonStaffBookingNew);
      expect(open.extra, same(_launch));
      return (h, context);
    }

    void expectNoPii(Object? value, {required String reason}) {
      final String s = '$value';
      for (final String pii in <String>[
        _kFirst,
        _kLast,
        _kPhone,
        '671234567',
      ]) {
        expect(s.contains(pii), isFalse, reason: '$reason leaks «$pii»');
      }
    }

    for (final (String label, AuthSession session, String landing)
        in <(String, AuthSession, String)>[
          ('logout', const AuthSession.unauthenticated(), RouteNames.login),
          (
            'role → SALON_MASTER',
            _signedIn(UserRole.salonMaster),
            roleHomePath(UserRole.salonMaster),
          ),
          (
            'role → CLIENT',
            _signedIn(UserRole.client),
            roleHomePath(UserRole.client),
          ),
        ]) {
      testWidgets('$label → re-resolved to $landing, the WalkInLaunch is '
          'dropped, no PII in the location', (tester) async {
        final (_Harness h, BuildContext context) = await ownerWithWizard(
          tester,
        );

        h.auth.emit(session);
        final RouteMatchList to = await h.resolve(
          context,
          h.match(RouteNames.salonStaffBookingNew, extra: _launch),
        );

        expect(to.isError, isFalse);
        expect(to.uri.path, landing);
        expect(to.extra, isNull);
        expectNoPii(to.uri, reason: 'location');
      });
    }

    testWidgets('an admitting router-key change restores the stack WITHOUT '
        'the WalkInLaunch (and never serialises its PII)', (tester) async {
      final (_Harness h, BuildContext _) = await ownerWithWizard(tester);
      expect(h.router.configuration.extraCodec, isNull);
      expect(
        () => jsonEncode(_launch),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );

      // The real stack: card, «Записати» pushed on top of it.
      final RouteMatchList stack = h
          .match(_salonCard)
          .push(
            ImperativeRouteMatch(
              pageKey: const ValueKey<String>('wizard'),
              matches: h.match(RouteNames.salonStaffBookingNew, extra: _launch),
              completer: Completer<Object?>(),
            ),
          );
      final RouteInformation? restored = h.router.routeInformationParser
          .restoreRouteInformation(stack);

      expect(restored, isNotNull);
      final Map<Object?, Object?> state =
          restored!.state! as Map<Object?, Object?>;
      final Map<Object?, Object?> wizard =
          (state['imperativeMatches']! as List<Object?>).single!
              as Map<Object?, Object?>;
      expect(wizard['location'], RouteNames.salonStaffBookingNew);
      // go_router's JSON fallback: a non-JSON extra is encoded as `null`.
      expect((wizard['state']! as Map<Object?, Object?>)['encoded'], 'null');
      expectNoPii(restored.state, reason: 'restoration state');
      expectNoPii(restored.uri, reason: 'restoration uri');
    });

    testWidgets('the salon wizard page without its extra degrades to the '
        'missing-extra fallback, never the wizard', (tester) async {
      final (_Harness h, BuildContext context) = await ownerWithWizard(tester);
      final RouteMatchList m = h.match(RouteNames.salonStaffBookingNew);
      final Page<dynamic> page = m.last.route.pageBuilder!(
        context,
        h.router.configuration.buildTopLevelGoRouterState(m),
      );
      final Widget child = (page as MaterialPage<void>).child;

      expect(child, isNot(isA<SalonCreateBookingScreen>()));
      expect(child.runtimeType.toString(), '_MissingRouteExtra');
    });
  });
}
