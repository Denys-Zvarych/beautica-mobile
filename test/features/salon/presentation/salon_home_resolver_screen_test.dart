// Phase 21.8 QA follow-up — widget tests for [SalonHomeResolverScreen].
//
// The shared SALON_OWNER/SALON_ADMIN landing had ZERO direct coverage before
// this file — only reached incidentally through the router-tier
// `role_landing_chrome_test.dart`, whose ONE fixture (single salon) never
// exercises the selection chain, the zero-salon fallback, the error/retry
// surface, or the admin null-salonId guard.
//
// Covers the full matrix documented on the screen itself. Phase 288 replaced
// the owner's `isPrimary` pick with the last-visited chain (D1);
// `lastVisitedSalonProvider` is overridden DIRECTLY in every owner case,
// never through a storage fake:
//   * SALON_OWNER, mySalons AsyncLoading             -> loading skeleton (8),
//     and the pointer read has already STARTED — it overlaps the fetch (11).
//   * SALON_OWNER, pointer AsyncLoading              -> loading skeleton, no
//     forward (9).
//   * SALON_OWNER, pointer = B for this user         -> shell B, even though A
//     is `isPrimary` (1).
//   * SALON_OWNER, no pointer                         -> first salon (2), and
//     `isPrimary` is ignored — single, all-null or several-true (5).
//   * SALON_OWNER, pointer to a salon not in the list -> first salon (3).
//   * SALON_OWNER, pointer from ANOTHER user          -> first salon (4).
//   * SALON_OWNER, zero salons                       -> RouteNames.mySalons,
//     even while the pointer read never completes — the read may start, but
//     the empty branch never WAITS on it (6).
//   * SALON_OWNER, AsyncError                        -> ErrorState + working
//     retry (10).
//   * SALON_ADMIN, salonId set                       -> synchronous go to
//     shell, and the pointer is never read (7).
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
import 'package:beautica_mobile/features/salon/application/last_visited_salon_provider.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/last_visited_salon.dart';
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

/// Overrides `lastVisitedSalonProvider` to resolve to [pointer].
Object _pointer(LastVisitedSalon? pointer) =>
    lastVisitedSalonProvider.overrideWith((ref) async => pointer);

/// Overrides `lastVisitedSalonProvider` with a read that NEVER completes.
Object _pointerNeverResolves() => lastVisitedSalonProvider.overrideWith(
  (ref) => Completer<LastVisitedSalon?>().future,
);

/// A pointer recorded by the signed-in owner ([_stubOwner]).
LastVisitedSalon _ownPointer(String salonId) =>
    LastVisitedSalon(userId: _stubOwner.id, salonId: salonId);

/// Salons A, B, C where A is `isPrimary` and B is not — so the pre-Phase-288
/// rule would pick A, and a pointer to B must MOVE the destination.
const List<Salon> _abc = <Salon>[
  Salon(id: 'salon-a', name: 'A', isPrimary: true),
  Salon(id: 'salon-b', name: 'B', isPrimary: false),
  Salon(id: 'salon-c', name: 'C', isPrimary: false),
];

/// [MySalons] stub that resolves to [salons], then lets the test drive a
/// REAL post-settle `state = AsyncLoading()` — which Riverpod turns into an
/// `AsyncLoading` still CARRYING the previous list (`copyWithPrevious`), the
/// shape the screen's concrete-subtype gate exists for. (`ref.invalidate`
/// cannot produce it here: a seamless reload settles as
/// `AsyncData(isLoading: true)`.)
class _ReloadableMySalons extends MySalons {
  _ReloadableMySalons(this.salons);

  final List<Salon> salons;

  @override
  Future<List<Salon>> build() async => salons;

  void startReloading() => state = const AsyncLoading<List<Salon>>();
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
    testWidgets(
      '8 should_notNavigate_when_mySalonsIsStillLoading — the loading '
      'skeleton renders',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(_NeverResolvingMySalons.new),
            _pointer(_ownPointer('salon-a')),
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
      },
    );

    // Phase 288 audit (mobile-perf MEDIUM) — the pointer read must OVERLAP
    // the network fetch, not start after it. MUTATION CHECK: moving the
    // `lastVisitedSalonProvider` watch back below the `salons.isEmpty` branch
    // turns this RED.
    testWidgets(
      '11 should_startPointerRead_when_mySalonsIsStillLoading — the storage '
      'read overlaps the network fetch',
      (tester) async {
        bool pointerRead = false;
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(_NeverResolvingMySalons.new),
            lastVisitedSalonProvider.overrideWith((ref) async {
              pointerRead = true;
              return _ownPointer('salon-a');
            }),
          ],
        );
        // Bounded pump — mySalonsProvider never resolves.
        await tester.pump();

        expect(
          pointerRead,
          isTrue,
          reason: 'the slot read must start while mySalons is still loading',
        );
        expect(
          find.byKey(const Key('salon-home-resolver-loading')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('shell-stub-salon-a')), findsNothing);
      },
    );

    // D4 pin for the `mySalonsProvider` concrete-subtype gate. Case 8 alone
    // cannot catch a gate relaxed to `.value`: a first-ever `AsyncLoading`
    // has no value either way. This fixture produces the shape that CAN —
    // a re-loading `AsyncLoading` still carrying the previous list.
    // MUTATION CHECK: `final List<Salon>? salons = mySalonsAsync.value;`
    // turns this RED (forwards into `salon-stale`).
    testWidgets(
      '8b should_notNavigate_when_mySalonsIsReloadingWithAStaleValue',
      (tester) async {
        final Completer<LastVisitedSalon?> pointerRead =
            Completer<LastVisitedSalon?>();
        final _ReloadableMySalons notifier = _ReloadableMySalons(const <Salon>[
          Salon(id: 'salon-stale', name: 'Stale'),
        ]);
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(() => notifier),
            lastVisitedSalonProvider.overrideWith((ref) => pointerRead.future),
          ],
        );
        // fixed-wait-ok (pump-bounded): repeating shimmer.
        await tester.pump();
        await tester.pump();

        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(SalonHomeResolverScreen)),
        );
        // Precondition: the list resolved; only the pointer holds the gate.
        expect(container.read(mySalonsProvider), isA<AsyncData<List<Salon>>>());

        notifier.startReloading();
        await tester.pump();
        final AsyncValue<List<Salon>> reloading = container.read(
          mySalonsProvider,
        );
        expect(reloading, isA<AsyncLoading<List<Salon>>>());
        expect(
          reloading.value,
          isNotNull,
          reason: 'the fixture must carry a stale value, or this is vacuous',
        );

        pointerRead.complete(null);
        for (int i = 0; i < 10; i++) {
          // fixed-wait-ok: one step of a bounded loop — the forward this pins
          // the absence of is post-frame.
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(find.byKey(const Key('shell-stub-salon-stale')), findsNothing);
        expect(
          find.byKey(const Key('salon-home-resolver-loading')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '9 should_notNavigate_when_pointerIsStillLoading — salons resolved, '
      'the slot read never completes -> skeleton, no forward',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(() => _ResolvedMySalons(_abc)),
            _pointerNeverResolves(),
          ],
        );
        // fixed-wait-ok (pump-bounded): the shimmer repeats, so
        // pumpAndSettle never returns; the forward this pins the absence of
        // is post-frame, so pump several frames.
        for (int i = 0; i < 10; i++) {
          // fixed-wait-ok: one step of the bounded loop above.
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(
          find.byKey(const Key('salon-home-resolver-loading')),
          findsOneWidget,
        );
        for (final Salon s in _abc) {
          expect(find.byKey(Key('shell-stub-${s.id}')), findsNothing);
        }
      },
    );

    testWidgets(
      '1 should_openLastVisitedSalon_when_ownerRelaunches — pointer = B, '
      'A is isPrimary -> shell B',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(() => _ResolvedMySalons(_abc)),
            _pointer(_ownPointer('salon-b')),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shell-stub-salon-b')), findsOneWidget);
        expect(find.byKey(const Key('shell-stub-salon-a')), findsNothing);
      },
    );

    testWidgets('2 should_openFirstSalon_when_noLastVisitedStored', (
      tester,
    ) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(_OwnerAuthNotifier.new),
          mySalonsProvider.overrideWith(() => _ResolvedMySalons(_abc)),
          _pointer(null),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shell-stub-salon-a')), findsOneWidget);
    });

    testWidgets(
      '3 should_openFirstSalon_when_lastVisitedSalonIsNoLongerInTheList — '
      'a stale pointer self-heals, never navigates to the missing salon',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(() => _ResolvedMySalons(_abc)),
            _pointer(_ownPointer('salon-deleted')),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shell-stub-salon-a')), findsOneWidget);
        expect(find.byKey(const Key('shell-stub-salon-deleted')), findsNothing);
      },
    );

    testWidgets(
      '4 should_openFirstSalon_when_storedUserIdDoesNotMatchSession',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(() => _ResolvedMySalons(_abc)),
            _pointer(
              const LastVisitedSalon(
                userId: 'someone-else',
                salonId: 'salon-b',
              ),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('shell-stub-salon-a')), findsOneWidget);
        expect(find.byKey(const Key('shell-stub-salon-b')), findsNothing);
      },
    );

    group('5 should_ignoreIsPrimary_when_noPointer', () {
      final Map<String, List<Salon>> fixtures = <String, List<Salon>>{
        'B alone is isPrimary': const <Salon>[
          Salon(id: 'salon-a', name: 'A', isPrimary: false),
          Salon(id: 'salon-b', name: 'B', isPrimary: true),
          Salon(id: 'salon-c', name: 'C', isPrimary: false),
        ],
        'isPrimary all null': const <Salon>[
          Salon(id: 'salon-a', name: 'A'),
          Salon(id: 'salon-b', name: 'B'),
        ],
        'several isPrimary true (bad data)': const <Salon>[
          Salon(id: 'salon-a', name: 'A', isPrimary: false),
          Salon(id: 'salon-b', name: 'B', isPrimary: true),
          Salon(id: 'salon-c', name: 'C', isPrimary: true),
        ],
      };
      for (final MapEntry<String, List<Salon>> f in fixtures.entries) {
        testWidgets('${f.key} -> the FIRST salon (A)', (tester) async {
          await tester.pumpRoutedApp(
            _router(),
            overrides: <Object>[
              authProvider.overrideWith(_OwnerAuthNotifier.new),
              mySalonsProvider.overrideWith(() => _ResolvedMySalons(f.value)),
              _pointer(null),
            ],
          );
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('shell-stub-salon-a')), findsOneWidget);
        });
      }
    });

    testWidgets(
      '6 should_forwardToMySalons_when_ownerHasNoSalons — even while the '
      'pointer read never completes (the empty branch does not wait on '
      'storage)',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(
              () => _ResolvedMySalons(const <Salon>[]),
            ),
            _pointerNeverResolves(),
          ],
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('my-salons-stub')), findsOneWidget);
      },
    );

    testWidgets(
      '10 should_showErrorWithRetry_when_mySalonsFails — ErrorState renders '
      'with a WORKING retry that recovers to the resolved shell',
      (tester) async {
        final flaky = _FlakyMySalons(const <Salon>[
          Salon(id: 'salon-recovered', name: 'Recovered', isPrimary: true),
        ]);
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            authProvider.overrideWith(_OwnerAuthNotifier.new),
            mySalonsProvider.overrideWith(() => flaky),
            _pointer(null),
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
    testWidgets('7 should_useSessionSalonId_when_roleIsSalonAdmin — forwards '
        'SYNCHRONOUSLY to that salon\'s shell (no mySalonsProvider watch, and '
        'the last-visited pointer is never read)', (tester) async {
      bool pointerRead = false;
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          authProvider.overrideWith(
            () => _AdminAuthNotifier('salon-admin-own'),
          ),
          lastVisitedSalonProvider.overrideWith((ref) async {
            pointerRead = true;
            // A pointer that WOULD move the admin, were it consulted.
            return const LastVisitedSalon(
              userId: 'admin-resolver-1',
              salonId: 'salon-elsewhere',
            );
          }),
        ],
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('shell-stub-salon-admin-own')),
        findsOneWidget,
      );
      expect(
        pointerRead,
        isFalse,
        reason: 'the admin arm must never touch the lastSalon slot',
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
