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
//   * SALON_ADMIN, salonId null                      -> a self-describing
//     `SessionIncompleteFailure` + a retry that re-fetches the profile, and
//     the forward-to-shell that follows once it arrives. NEVER blank, and
//     never the dead-end bare `UnknownFailure` it used to be.
//   * authProvider AsyncError w/ stale session       -> retryable ErrorState,
//     and NEVER a forward into the previous account's shell.

// `hide AsyncError`: `dart:async` declares an unrelated, non-generic
// `AsyncError`, which shadows Riverpod's `AsyncError<T>` state below.
import 'dart:async' hide AsyncError;

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
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  _AdminAuthNotifier(this.salonId, {this.salonIdAfterRefresh});

  final String? salonId;

  /// When non-null, [refreshUser] republishes the session carrying THIS
  /// salonId — standing in for `GET /users/me` supplying the binding a
  /// `POST /auth/invite/accept` session arrived without.
  ///
  /// Defaults to null so every pre-existing call site is untouched: with it
  /// unset this notifier delegates to the real [AuthNotifier.refreshUser].
  final String? salonIdAfterRefresh;

  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: _adminUser(salonId: salonId),
    accessToken: 'tok',
  );

  @override
  Future<void> refreshUser() async {
    final String? refreshed = salonIdAfterRefresh;
    if (refreshed == null) return super.refreshUser();
    state = AsyncData(
      AuthSession.authenticated(
        user: _adminUser(salonId: refreshed),
        accessToken: 'tok',
      ),
    );
  }
}

/// Settles to an [Authenticated] SALON_ADMIN session, then lets the test body
/// drive a REAL post-settle `state = AsyncError(...)` transition.
///
/// A notifier whose `build()` is an `async` body that RETURNS cannot express
/// this shape — Riverpod overwrites whatever `state` it assigned with an
/// `AsyncData` on the next microtask. The `AsyncError`-carrying-a-stale-value
/// shape can only be produced the way production produces it: assigning
/// `state` AFTER the build has settled, which is exactly what [AuthNotifier]
/// does when a token refresh / `/users/me` re-read fails. Mirrors
/// `test/routing/resolved_session_stale_value_test.dart`'s notifier of the
/// same shape, one layer down (the screen instead of the router guard).
class _TransitionableAdminAuthNotifier extends AuthNotifier {
  _TransitionableAdminAuthNotifier(this.salonId);

  final String? salonId;

  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: _adminUser(salonId: salonId),
    accessToken: 'tok',
  );

  void forceError(Object error) {
    state = AsyncError<AuthSession>(error, StackTrace.current);
  }
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

    // Regression (2026-09-06) — INVERTED. This test used to assert
    // `findsNothing` for the retry button, on the premise that "a missing
    // salonId on an authenticated admin's own profile is not a
    // transient/retryable condition". That premise was wrong, and it pinned a
    // live bug: `UserMapper.fromAuthResponse` was DISCARDING the `salonId` the
    // backend populates on `POST /auth/invite/accept`, and `acceptInvite` is
    // the one session-establishing flow that never follows with `repo.me()`.
    // So a freshly-created SALON_ADMIN landed here on a bare `UnknownFailure`
    // — «Щось пішло не так. Спробуйте ще раз.» — with no way forward at all.
    //
    // The condition IS recoverable, by exactly one route: re-fetch the
    // profile. Hence [SessionIncompleteFailure] plus a retry wired to
    // [AuthNotifier.refreshUser].
    testWidgets(
      'salonId null (session not fully hydrated) -> a SELF-DESCRIBING '
      'SessionIncompleteFailure WITH a retry, never a dead-end UnknownFailure',
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

        // The failure TYPE, not just "some error" — an `UnknownFailure` here
        // renders the generic fallback copy and is the defect this replaced.
        final ErrorState state = tester.widget<ErrorState>(
          find.byType(ErrorState),
        );
        expect(state.failure, isA<SessionIncompleteFailure>());
        expect(state.failure, isNot(isA<UnknownFailure>()));
        expect(state.onRetry, isNotNull);
        expect(
          find.byKey(const Key('error_state_retry_button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the retry re-fetches the profile and, once salonId arrives, the screen '
      'forwards to that salon\'s shell on its own',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(
              () => _AdminAuthNotifier(
                null,
                salonIdAfterRefresh: 'salon-admin-rehydrated',
              ),
            ),
          ],
        );
        await tester.pumpAndSettle();

        // Precondition: the dead-end arm, not the shell.
        expect(find.byType(ErrorState), findsOneWidget);
        expect(
          find.byKey(const Key('shell-stub-salon-admin-rehydrated')),
          findsNothing,
        );

        await tester.tap(find.byKey(const Key('error_state_retry_button')));
        await tester.pumpAndSettle();

        // `build` is a `ref.watch(authProvider)`, so the republished session
        // re-enters it and `_goToShell` forwards without any further tap.
        expect(find.byType(ErrorState), findsNothing);
        expect(
          find.byKey(const Key('shell-stub-salon-admin-rehydrated')),
          findsOneWidget,
        );
      },
    );

    // mobile-qa MEDIUM (cycle 2, 2026-09-05) — the STALE-SESSION arm.
    //
    // Phase 21.16 changed `salonHomeGuard` (`app_router.dart`) to admit an
    // unresolved session rather than bounce on a stale role. That is the right
    // call for the guard — bouncing on the previous account's role is a wrong
    // decision a later re-evaluation cannot un-make — but it hands THIS screen
    // a frame it never used to see. Its session read was a bare
    // `authAsync.value`, and `copyWithPrevious` keeps the previous account's
    // `AsyncData` attached to a later `AsyncError`, so the admin arm below
    // would read the PREVIOUS account's `user.salonId` and `context.go`
    // straight into that salon's shell — another tenant's salon, on this
    // device, with no error anywhere.
    //
    // The fixture is deliberately a SALON_ADMIN with a non-null `salonId`:
    // that is the one role/shape where the stale read produces a visibly
    // different destination (`shell-stub-salon-stale`) instead of merely a
    // different reason for the same outcome. MUTATION CHECK: restoring
    // `final AuthSession? session = authAsync.value;` in
    // `salon_home_resolver_screen.dart` turns this test RED on the
    // `shell-stub-salon-stale` assertion.
    testWidgets(
      'an AsyncError carrying a STALE authenticated session forwards nowhere '
      '— it shows a retryable ErrorState instead of entering the previous '
      'account\'s salon shell',
      (tester) async {
        final notifier = _TransitionableAdminAuthNotifier('salon-stale');
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[authProvider.overrideWith(() => notifier)],
        );
        await tester.pumpAndSettle();
        // Sanity: the SETTLED session does forward — so the negative
        // assertions below cannot pass merely because this fixture never
        // routes anywhere.
        expect(
          find.byKey(const Key('shell-stub-salon-stale')),
          findsOneWidget,
          reason:
              'the settled baseline. Without it a broken _router() would make '
              'the whole test vacuous.',
        );

        // Now go back to the resolver and drive the production transition.
        notifier.forceError(const NetworkFailure());
        await tester.pumpAndSettle();

        final BuildContext context = tester.element(
          find.byKey(const Key('shell-stub-salon-stale')),
        );
        GoRouter.of(context).go(RouteNames.salonHome);

        // fixed-wait-ok (pump-bounded): the resolver holds
        // `SkeletonShimmerScope`'s
        // REPEATING shimmer on an unresolved session, so `pumpAndSettle` can
        // never return. Bounded, and generously — the forward this pins the
        // absence of is scheduled from a POST-FRAME callback, so too few
        // pumps would report "did not forward" without having pumped the
        // frame that would.
        for (int i = 0; i < 20; i++) {
          // fixed-wait-ok: one 50 ms step of the bounded loop above — the
          // step itself is arbitrary; the LOOP is the wait.
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(
          find.byKey(const Key('shell-stub-salon-stale')),
          findsNothing,
          reason:
              'THE finding: a bare `.value` read takes the previous account\'s '
              'salonId and enters that salon\'s shell.',
        );
        // mobile-security LOW (2026-09-05) — the positive half of "no
        // forward" MOVED. It used to be the skeleton; `AsyncError` and
        // `AsyncLoading` are now separate arms in the screen, because an
        // errored session is terminal and a skeleton over it spins forever
        // with no affordance. The load-bearing assertion is unchanged and
        // sits immediately above: NO forward into the stale account's shell.
        expect(
          find.byType(ErrorState),
          findsOneWidget,
          reason:
              'an errored session is "known to be broken", not "not known '
              'yet" — it gets the retryable error body, not an unbounded '
              'skeleton. Also the positive half of "no forward": a build-time '
              'exception cannot pass as a passing test.',
        );
        expect(
          find.byKey(const Key('salon-home-resolver-loading')),
          findsNothing,
          reason:
              'and specifically NOT the skeleton — that arm is reserved for '
              'AsyncLoading / settled-Unauthenticated.',
        );
        // The affordance is the whole point of splitting the arm — an
        // `AsyncError` is terminal, so without a retry button the user is
        // stuck. `ErrorState` omits the button entirely when `onRetry` is
        // null, so its presence is what pins that `onRetry` was passed.
        // (Not tapped here: this fixture's `authProvider` override rebuilds
        // to the SAME admin session, so a tap would legitimately forward and
        // would pin the fixture rather than the screen.)
        expect(
          find.byKey(const Key('error_state_retry_button')),
          findsOneWidget,
          reason:
              'MUTATION CHECK: dropping `onRetry` from the new AsyncError arm '
              'in salon_home_resolver_screen.dart turns this RED.',
        );
      },
    );
  });
}
