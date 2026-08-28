// Phase 21.8 QA follow-up — widget tests for [SalonHomeResolverScreen].
//
// The shared SALON_OWNER/SALON_ADMIN landing had ZERO direct coverage before
// this file — only reached incidentally through the router-tier
// `role_landing_chrome_test.dart`, whose ONE fixture (single primary salon)
// never exercises the isPrimary edge cases, the zero-salon fallback, the
// error/retry surface, or the admin null-salonId guard.
//
// Covers the full matrix documented on the screen itself:
//   * SALON_OWNER, AsyncLoading                    -> loading skeleton.
//   * SALON_OWNER, one isPrimary                    -> go to that salon's shell.
//   * SALON_OWNER, no isPrimary at all (all null)    -> first salon in list.
//   * SALON_OWNER, SEVERAL isPrimary                -> first salon (firstWhere,
//     never singleWhere, which would throw on bad data).
//   * SALON_OWNER, zero salons                       -> RouteNames.mySalons.
//   * SALON_OWNER, AsyncError                        -> ErrorState + working retry.
//   * SALON_ADMIN, salonId set                       -> synchronous go to shell.
//   * SALON_ADMIN, salonId null                      -> ErrorState, NEVER blank.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_home_resolver_screen.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

const _stubOwner = User(
  id: 'owner-resolver-1',
  email: 'owner@beautica.ua',
  role: UserRole.salonOwner,
  firstName: 'Оксана',
  lastName: 'Власник',
);

User _adminUser({String? salonId}) => User(
  id: 'admin-resolver-1',
  email: 'admin@beautica.ua',
  role: UserRole.salonAdmin,
  firstName: 'Ірина',
  lastName: 'Адміністратор',
  salonId: salonId,
);

class _OwnerAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async =>
      const AuthSession.authenticated(user: _stubOwner, accessToken: 'tok');
}

class _AdminAuthNotifier extends AuthNotifier {
  _AdminAuthNotifier(this.salonId);

  final String? salonId;

  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: _adminUser(salonId: salonId),
    accessToken: 'tok',
  );
}

/// [MySalons] stub that resolves immediately to [salons].
class _ResolvedMySalons extends MySalons {
  _ResolvedMySalons(this.salons);

  final List<Salon> salons;

  @override
  Future<List<Salon>> build() async => salons;
}

/// [MySalons] stub that NEVER resolves — pins the AsyncLoading skeleton
/// deliberately.
class _NeverResolvingMySalons extends MySalons {
  @override
  Future<List<Salon>> build() => Completer<List<Salon>>().future;
}

/// [MySalons] stub whose build THROWS on the first attempt, then resolves to
/// [salons] on any later rebuild — lets the retry test drive the error ->
/// retry -> resolved round trip via the screen's own `onRetry`.
class _FlakyMySalons extends MySalons {
  _FlakyMySalons(this.salons);

  final List<Salon> salons;
  int attempts = 0;

  @override
  Future<List<Salon>> build() async {
    attempts++;
    if (attempts == 1) {
      // async throw — NOT a sync `thenThrow`-shaped throw — so this goes
      // through the SAME AsyncError path a real Dio failure would (mobile-qa
      // AsyncValue/thenThrow trap: a sync throw during provider build can
      // bypass how a genuine async failure settles).
      await Future<void>.delayed(Duration.zero);
      throw const NetworkFailure();
    }
    return salons;
  }
}

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.salonHome,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.salonHome,
      builder: (context, state) => const SalonHomeResolverScreen(),
    ),
    GoRoute(
      path: '/salons/:salonId/shell',
      builder: (context, state) => Scaffold(
        key: Key('shell-stub-${state.pathParameters['salonId']}'),
        body: Text('shell for ${state.pathParameters['salonId']}'),
      ),
    ),
    GoRoute(
      path: RouteNames.mySalons,
      builder: (context, state) =>
          const Scaffold(key: Key('my-salons-stub'), body: SizedBox()),
    ),
  ],
);

void main() {
  group('SALON_OWNER', () {
    testWidgets('AsyncLoading -> the loading skeleton renders', (tester) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_OwnerAuthNotifier.new),
          mySalonsProvider.overrideWith(_NeverResolvingMySalons.new),
        ],
      );
      // Bounded pump — mySalonsProvider never resolves, so pumpAndSettle
      // would hang on the repeating shimmer.
      await tester.pump();

      expect(
        find.byKey(const Key('salon-home-resolver-loading')),
        findsOneWidget,
      );
      expect(find.byType(SkeletonShimmerScope), findsOneWidget);
      expect(find.byKey(const Key('shell-stub-salon-a')), findsNothing);
    });

    testWidgets(
      'one isPrimary salon among others -> forwards to THAT salon\'s shell',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(
              () => _ResolvedMySalons(const <Salon>[
                Salon(id: 'salon-a', name: 'A', isPrimary: false),
                Salon(id: 'salon-b', name: 'B', isPrimary: true),
                Salon(id: 'salon-c', name: 'C', isPrimary: false),
              ]),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shell-stub-salon-b')), findsOneWidget);
      },
    );

    testWidgets(
      'no salon has isPrimary set (all null) -> falls back to the FIRST '
      'salon in the list',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(
              () => _ResolvedMySalons(const <Salon>[
                Salon(id: 'salon-first', name: 'First'),
                Salon(id: 'salon-second', name: 'Second'),
              ]),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shell-stub-salon-first')), findsOneWidget);
      },
    );

    testWidgets(
      'SEVERAL salons have isPrimary true (bad data) -> falls back to the '
      'FIRST salon instead of throwing (firstWhere, never singleWhere)',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(
              () => _ResolvedMySalons(const <Salon>[
                Salon(id: 'salon-p1', name: 'P1', isPrimary: true),
                Salon(id: 'salon-p2', name: 'P2', isPrimary: true),
              ]),
            ),
          ],
        );
        // If the production code used `singleWhere` this would THROW inside
        // build() instead of settling — pumpAndSettle would surface that as
        // a failed test via the uncaught FlutterError.
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shell-stub-salon-p1')), findsOneWidget);
      },
    );

    testWidgets(
      'zero salons -> forwards to the My Salons hub, not a shell with no '
      'salonId',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(
              () => _ResolvedMySalons(const <Salon>[]),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('my-salons-stub')), findsOneWidget);
      },
    );

    testWidgets(
      'AsyncError -> ErrorState renders with a WORKING retry that recovers '
      'to the resolved shell',
      (tester) async {
        final flaky = _FlakyMySalons(const <Salon>[
          Salon(id: 'salon-recovered', name: 'Recovered', isPrimary: true),
        ]);
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(() => flaky),
          ],
          // Disable the ambient retry policy so the AsyncError actually
          // settles and renders ErrorState instead of being retried away by
          // the production `beauticaProviderRetry` policy before the test
          // can observe it.
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(
          find.byKey(const Key('error_state_retry_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('shell-stub-salon-recovered')),
          findsNothing,
        );

        await tester.tap(find.byKey(const Key('error_state_retry_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('shell-stub-salon-recovered')),
          findsOneWidget,
          reason:
              'tapping retry must invalidate mySalonsProvider and, once '
              'it resolves, forward to the recovered salon\'s shell',
        );
      },
    );
  });

  group('SALON_ADMIN', () {
    testWidgets('salonId set -> forwards SYNCHRONOUSLY to that salon\'s shell '
        '(no mySalonsProvider watch at all)', (tester) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(
            () => _AdminAuthNotifier('salon-admin-own'),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shell-stub-salon-admin-own')),
        findsOneWidget,
      );
    });

    testWidgets(
      'salonId null (data problem) -> ErrorState, NEVER a blank screen',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(() => _AdminAuthNotifier(null)),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byType(ErrorState), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        // No retry button — a missing salonId on an authenticated admin's
        // own profile is not a transient/retryable condition.
        expect(find.byKey(const Key('error_state_retry_button')), findsNothing);
      },
    );
  });
}
