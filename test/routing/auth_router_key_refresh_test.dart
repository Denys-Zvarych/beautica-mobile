// M517 port (e758bc74, 2026-11-18; Sentry 162160464) — `AuthRefreshNotifier`
// refreshes go_router ONLY when a redirect-relevant auth field changes
// (`authRouterKey`).
//
// WHY
// ---------------------------------------------------------------------------
// A go_router refresh re-parses the last REPORTED route stack through the
// codec restore branch (go_router 17.2.3). With the notifier firing on every
// `authProvider` emission, a profile-only emission (token refresh,
// `refreshUser`, avatar patch) therefore:
//   (a) replaced a pushed route's non-JSON `extra` with `null`;
//   (b) gave the restored imperative match a NEW Completer, so the original
//       `push` future never resolved (flutter#128122);
//   (c) resurrected a route popped in the same frame (not yet reported).
// A key change (role, salon, ...) must STILL re-run the redirects.
//
// HARNESS: the REAL `AuthRefreshNotifier` as `refreshListenable`, a fake
// `authProvider` whose state the test assigns directly, `context.push` for
// the imperative case (see memory project_gorouter_imperative_match_fullpath).
//
// FALSIFIED (2026-11-18): with the old `ref.listen(authProvider, ...)` put
// back, the (a), (b) and (c) cases go RED and the key-change controls stay
// GREEN.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/routing/auth_refresh_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const User _master = User(
  id: 'u-1',
  email: 'm@example.com',
  role: UserRole.independentMaster,
  phoneNumber: '+380501112233',
);

/// Settles to [initial]; the test then assigns `state` directly, the same
/// way production `AuthNotifier` does after the build has settled.
class _SettableAuthNotifier extends AuthNotifier {
  _SettableAuthNotifier(this.initial);

  final User initial;

  @override
  Future<AuthSession> build() async =>
      AuthSession.authenticated(user: initial, accessToken: 'token-0');

  void emit(AuthSession session) => state = AsyncData<AuthSession>(session);
}

/// A non-JSON `extra` — exactly what the codec-less restore drops.
class _Args {
  const _Args(this.label);
  final String label;
}

class _Harness {
  _Harness(this.container, this.notifier, this.router);

  final ProviderContainer container;
  final _SettableAuthNotifier notifier;
  final GoRouter router;

  /// Every `extra` the child route builder received, in order.
  final List<Object?> childExtras = <Object?>[];
}

Future<_Harness> _pumpHarness(WidgetTester tester) async {
  final _SettableAuthNotifier notifier = _SettableAuthNotifier(_master);
  final ProviderContainer container = ProviderContainer(
    overrides: [authProvider.overrideWith(() => notifier)],
  );
  addTearDown(container.dispose);
  await container.read(authProvider.future);

  late final _Harness harness;
  final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
    final AuthRefreshNotifier refresh = AuthRefreshNotifier(ref);
    ref.onDispose(refresh.dispose);
    return GoRouter(
      initialLocation: '/root',
      refreshListenable: refresh,
      redirect: (context, state) {
        final AuthSession? session = container.read(authProvider).value;
        final User? user = session is Authenticated ? session.user : null;
        final String loc = state.matchedLocation;
        if (user == null) return null;
        if (user.role == UserRole.client && loc.startsWith('/root')) {
          return '/client';
        }
        return null;
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/root',
          builder: (context, state) => const _Page(label: 'root'),
          routes: <RouteBase>[
            GoRoute(
              path: 'child',
              builder: (context, state) {
                harness.childExtras.add(state.extra);
                final Object? extra = state.extra;
                return _ChildPage(
                  label: extra is _Args ? extra.label : 'placeholder',
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/client',
          builder: (context, state) => const _Page(label: 'client'),
        ),
      ],
    );
  });
  final GoRouter router = container.read(routerProvider);
  harness = _Harness(container, notifier, router);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

class _Page extends StatelessWidget {
  const _Page({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text('page:$label', key: ValueKey<String>('page-$label')));
}

class _ChildPage extends StatelessWidget {
  const _ChildPage({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Text('child:$label', key: const ValueKey<String>('child')),
  );
}

AuthSession _session(User user, {String token = 'token-1'}) =>
    AuthSession.authenticated(user: user, accessToken: token);

/// A profile-only emission: new token, email and phone — no redirect field.
AuthSession _profileOnly() => _session(
  _master.copyWith(email: 'new@example.com', phoneNumber: '+380509998877'),
  token: 'token-2',
);

BuildContext _rootContext(WidgetTester tester) =>
    tester.element(find.byKey(const ValueKey<String>('page-root')));

void main() {
  group('authRouterKey', () {
    final AuthRouterKey base = authRouterKey(
      AsyncData<AuthSession>(_session(_master)),
    );

    test('equal for redirect-irrelevant changes', () {
      expect(
        authRouterKey(
          AsyncData<AuthSession>(_session(_master, token: 'other-token')),
        ),
        base,
      );
      expect(
        authRouterKey(
          AsyncData<AuthSession>(
            _session(_master.copyWith(email: 'x@example.com')),
          ),
        ),
        base,
      );
      expect(
        authRouterKey(
          AsyncData<AuthSession>(
            _session(
              _master.copyWith(
                phoneNumber: '+380000000000',
                firstName: 'A',
                avatarUrl: 'https://cdn.example/a.jpg',
              ),
            ),
          ),
        ),
        base,
      );
    });

    final Map<String, AsyncValue<AuthSession>> changed =
        <String, AsyncValue<AuthSession>>{
          'isLoading': const AsyncLoading<AuthSession>(),
          'isData': const AsyncError<AuthSession>('boom', StackTrace.empty),
          'authenticated': const AsyncData<AuthSession>(
            AuthSession.unauthenticated(),
          ),
          'userId': AsyncData<AuthSession>(
            _session(_master.copyWith(id: 'u-2')),
          ),
          'role': AsyncData<AuthSession>(
            _session(_master.copyWith(role: UserRole.client)),
          ),
          'salonId': AsyncData<AuthSession>(
            _session(_master.copyWith(salonId: 's-1')),
          ),
        };
    for (final MapEntry<String, AsyncValue<AuthSession>> e in changed.entries) {
      test('differs when ${e.key} changes', () {
        expect(authRouterKey(e.value), isNot(base));
      });
    }
  });

  group('profile-only emission leaves the route stack alone', () {
    testWidgets('(a) a pushed non-JSON extra survives', (tester) async {
      final _Harness h = await _pumpHarness(tester);
      const _Args args = _Args('opened');

      unawaited(_rootContext(tester).push<Object?>('/root/child', extra: args));
      await tester.pumpAndSettle();
      expect(find.text('child:opened'), findsOneWidget);

      h.notifier.emit(_profileOnly());
      await tester.pumpAndSettle();

      expect(h.childExtras, isNotEmpty);
      expect(h.childExtras, everyElement(same(args)));
      expect(find.text('child:opened'), findsOneWidget);
      expect(find.text('child:placeholder'), findsNothing);
    });

    testWidgets('(b) the original push future resolves with the pop result', (
      tester,
    ) async {
      final _Harness h = await _pumpHarness(tester);
      Object? result;
      bool completed = false;

      unawaited(
        _rootContext(tester)
            .push<Object?>('/root/child', extra: const _Args('opened'))
            .then((value) {
              completed = true;
              result = value;
            }),
      );
      await tester.pumpAndSettle();

      h.notifier.emit(_profileOnly());
      await tester.pumpAndSettle();

      h.router.pop('ok');
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(result, 'ok');
      expect(find.byKey(const ValueKey<String>('page-root')), findsOneWidget);
    });

    testWidgets('(c) a route popped in the same frame is not resurrected', (
      tester,
    ) async {
      final _Harness h = await _pumpHarness(tester);

      unawaited(
        _rootContext(
          tester,
        ).push<Object?>('/root/child', extra: const _Args('opened')),
      );
      await tester.pumpAndSettle();
      final int builtBefore = h.childExtras.length;

      // The AppBar back button pops on the Navigator, which go_router learns
      // of only at its post-frame report — the emission lands in between.
      await tester.pageBack();
      h.notifier.emit(_profileOnly());
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(_ChildPage), findsNothing);
      expect(h.childExtras.length, builtBefore);
      expect(find.byKey(const ValueKey<String>('page-root')), findsOneWidget);
    });
  });

  group('redirect-key change still re-runs the redirect', () {
    testWidgets('role change redirects', (tester) async {
      final _Harness h = await _pumpHarness(tester);
      expect(find.byKey(const ValueKey<String>('page-root')), findsOneWidget);

      h.notifier.emit(_session(_master.copyWith(role: UserRole.client)));
      await tester.pumpAndSettle();

      expect(h.router.state.matchedLocation, '/client');
      expect(find.byKey(const ValueKey<String>('page-client')), findsOneWidget);
    });
  });
}
