// Phase 364 — `routeFor`: the pure (target, role) -> route table.
//
// Table-driven over EVERY role x target; `null` marks the n/a combinations.
// The expected strings are built from the SAME `RouteNames` builders the router
// registers, so a renamed route breaks here, not silently in production.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_navigation.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';

const String _bk = 'bk-1';
const String _salon = 'salon-b';

enum _Mys { owned, other, error, never }

class _FakeMySalons extends MySalons {
  _FakeMySalons(this.mode);
  final _Mys mode;

  @override
  Future<List<Salon>> build() async => switch (mode) {
    _Mys.owned => const <Salon>[Salon(id: _salon, name: 'B')],
    _Mys.other => const <Salon>[Salon(id: 'salon-a', name: 'A')],
    _Mys.error => throw StateError('boom'),
    _Mys.never => await Completer<List<Salon>>().future,
  };
}

class _GatedMySalons extends MySalons {
  _GatedMySalons(this.gate);
  final Completer<List<Salon>> gate;

  @override
  Future<List<Salon>> build() => gate.future;
}

/// A session the test can change DURING the pending ownership check.
class _MutableAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(id: 'u1', email: 'u@b.c', role: UserRole.salonOwner),
    accessToken: 'tkn',
  );

  void setRole(UserRole role) => state = AsyncData<AuthSession>(
    AuthSession.authenticated(
      user: User(id: 'u1', email: 'u@b.c', role: role),
      accessToken: 'tkn',
    ),
  );

  void signOut() =>
      state = const AsyncData<AuthSession>(AuthSession.unauthenticated());
}

/// Keeps the auto-dispose session alive, as the running app does.
class _KeepAuthAlive extends ConsumerWidget {
  const _KeepAuthAlive({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authProvider.select(authUserRoleOrNull));
    return child;
  }
}

const NotificationTarget _booking = NotificationTarget.booking(
  bookingId: _bk,
  salonId: _salon,
);
const NotificationTarget _visit = NotificationTarget.booking(
  bookingId: _bk,
  appointmentId: 'ap-1',
);
const NotificationTarget _review = NotificationTarget.bookingReview(
  bookingId: _bk,
);
const NotificationTarget _team = NotificationTarget.salonTeam(salonId: _salon);
const NotificationTarget _none = NotificationTarget.none();

void main() {
  tearDown(resetNotificationNavigationStateForTest);

  group('routeFor', () {
    final Map<UserRole, Map<String, (NotificationTarget, String?)>> table =
        <UserRole, Map<String, (NotificationTarget, String?)>>{
          UserRole.client: <String, (NotificationTarget, String?)>{
            'booking': (_booking, RouteNames.notificationBookingDetail(_bk)),
            'visit': (_visit, RouteNames.notificationBookingDetail(_bk)),
            'review': (_review, RouteNames.notificationBookingReview(_bk)),
            'team': (_team, null),
            'none': (_none, null),
          },
          UserRole.independentMaster: <String, (NotificationTarget, String?)>{
            'booking': (_booking, RouteNames.masterBookingDetail(_bk)),
            'visit': (_visit, RouteNames.masterBookingDetail(_bk)),
            'review': (_review, null),
            'team': (_team, null),
            'none': (_none, null),
          },
          UserRole.salonOwner: <String, (NotificationTarget, String?)>{
            'booking': (_booking, RouteNames.salonStaffBookingDetail(_bk)),
            'visit': (_visit, RouteNames.salonStaffBookingDetail(_bk)),
            'review': (_review, null),
            'team': (_team, RouteNames.salonShell(_salon, openTeam: true)),
            'none': (_none, null),
          },
          UserRole.salonAdmin: <String, (NotificationTarget, String?)>{
            'booking': (_booking, RouteNames.salonStaffBookingDetail(_bk)),
            'visit': (_visit, RouteNames.salonStaffBookingDetail(_bk)),
            'review': (_review, null),
            'team': (_team, RouteNames.salonShell(_salon, openTeam: true)),
            'none': (_none, null),
          },
          UserRole.salonMaster: <String, (NotificationTarget, String?)>{
            'booking': (_booking, RouteNames.salonMasterBookingDetail(_bk)),
            'visit': (_visit, RouteNames.salonMasterBookingDetail(_bk)),
            'review': (_review, null),
            'team': (_team, null),
            'none': (_none, null),
          },
        };

    test('the table covers every role', () {
      expect(table.keys.toSet(), UserRole.values.toSet());
    });

    for (final MapEntry<UserRole, Map<String, (NotificationTarget, String?)>>
        role
        in table.entries) {
      for (final MapEntry<String, (NotificationTarget, String?)> cell
          in role.value.entries) {
        test('should_return_${cell.value.$2}_when_${role.key.name}_gets_'
            '${cell.key}', () {
          expect(routeFor(cell.value.$1, role.key), cell.value.$2);
        });
      }
    }

    test('should_returnNull_when_noSignedInRole', () {
      for (final NotificationTarget t in <NotificationTarget>[
        _booking,
        _review,
        _team,
        _none,
      ]) {
        expect(routeFor(t, null), isNull);
      }
    });

    test('should_neverReturnADifferentRouteForTheVisitThanForItsBooking', () {
      // A multi-service visit targets its representative booking: same route.
      for (final UserRole r in UserRole.values) {
        expect(routeFor(_visit, r), routeFor(_booking, r));
      }
    });
  });

  group('routeFor reviewReceived (phase 391)', () {
    const AppNotificationType rr = AppNotificationType.reviewReceived;
    const NotificationTarget noSalon = NotificationTarget.booking(
      bookingId: _bk,
    );
    const NotificationTarget emptySalon = NotificationTarget.booking(
      bookingId: _bk,
      salonId: '',
    );

    test('should_openSalonReviews_when_ownerOrAdmin', () {
      for (final UserRole r in <UserRole>[
        UserRole.salonOwner,
        UserRole.salonAdmin,
      ]) {
        expect(
          routeFor(_booking, r, type: rr),
          RouteNames.salonShell(_salon, openReviews: true),
          reason: r.name,
        );
      }
    });

    test('should_keepBookingDetail_when_otherRoles', () {
      expect(
        routeFor(_booking, UserRole.salonMaster, type: rr),
        RouteNames.salonMasterBookingDetail(_bk),
      );
      expect(
        routeFor(_booking, UserRole.independentMaster, type: rr),
        RouteNames.masterBookingDetail(_bk),
      );
      expect(
        routeFor(_booking, UserRole.client, type: rr),
        RouteNames.notificationBookingDetail(_bk),
      );
    });

    test('should_fallBackToBookingDetail_when_salonIdMissingOrEmpty', () {
      expect(
        routeFor(noSalon, UserRole.salonOwner, type: rr),
        RouteNames.salonStaffBookingDetail(_bk),
      );
      expect(
        routeFor(emptySalon, UserRole.salonOwner, type: rr),
        RouteNames.salonStaffBookingDetail(_bk),
      );
    });

    test('should_fallBackToBookingDetail_when_salonIdIsWhitespaceOnly', () {
      for (final String blank in <String>[' ', '   ', '\t', '\n ']) {
        expect(
          routeFor(
            NotificationTarget.booking(bookingId: _bk, salonId: blank),
            UserRole.salonOwner,
            type: rr,
          ),
          RouteNames.salonStaffBookingDetail(_bk),
          reason: 'blank "${blank.codeUnits}"',
        );
      }
    });

    test('should_assert_when_openTeamAndOpenReviewsTogether', () {
      expect(
        () => RouteNames.salonShell(_salon, openTeam: true, openReviews: true),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should_urlEncode_when_salonIdHasReservedCharacters', () {
      // The path segment is `Uri.encodeComponent`-ed by `salonPublicProfile`,
      // so `/`, `?` and `#` can never open a new path segment, query or
      // fragment. (The mapper additionally drops non-UUID ids upstream.)
      final String route = RouteNames.salonShell('a/b?c#d', openReviews: true);
      expect(route, '/salons/a%2Fb%3Fc%23d/shell?tab=reviews');
      final Uri uri = Uri.parse(route);
      expect(uri.queryParameters, <String, String>{'tab': 'reviews'});
      expect(uri.fragment, isEmpty);
      expect(uri.pathSegments, <String>['salons', 'a/b?c#d', 'shell']);
    });

    test('should_keepBookingDetail_when_otherType', () {
      expect(
        routeFor(
          _booking,
          UserRole.salonOwner,
          type: AppNotificationType.bookingCreated,
        ),
        RouteNames.salonStaffBookingDetail(_bk),
      );
    });

    test('should_leaveSalonShellStringsUnchanged_and_addReviewsQuery', () {
      expect(RouteNames.salonShell(_salon), '/salons/$_salon/shell');
      expect(
        RouteNames.salonShell(_salon, openTeam: true),
        '/salons/$_salon/shell?tab=team',
      );
      expect(
        RouteNames.salonShell(_salon, openReviews: true),
        '/salons/$_salon/shell?tab=reviews',
      );
      expect(kSalonShellTabReviews, 'reviews');
    });
  });

  group('isNotificationUnavailable', () {
    test('should_beTrue_when_bookingTypeHasNoTarget', () {
      for (final AppNotificationType t in AppNotificationType.values.where(
        isBookingNotificationType,
      )) {
        expect(
          isNotificationUnavailable(notif('n', type: t, target: _none)),
          isTrue,
          reason: t.name,
        );
      }
    });

    test('should_beFalse_when_nonBookingTypeHasNoTarget', () {
      for (final AppNotificationType t in <AppNotificationType>[
        AppNotificationType.unknown,
        AppNotificationType.inviteAccepted,
      ]) {
        expect(
          isNotificationUnavailable(notif('n', type: t, target: _none)),
          isFalse,
          reason: t.name,
        );
      }
    });

    test('should_classifyBookingAndReviewTypesOnly', () {
      expect(
        AppNotificationType.values.where(isBookingNotificationType).length,
        9,
      );
      expect(isBookingNotificationType(AppNotificationType.unknown), isFalse);
      expect(
        isBookingNotificationType(AppNotificationType.inviteAccepted),
        isFalse,
      );
    });

    test('should_beTrue_when_bookingParamsAreNull', () {
      expect(
        isNotificationUnavailable(
          notif('n', target: _booking, params: NotificationParams.empty),
        ),
        isTrue,
      );
    });

    test('should_beFalse_when_bookingHasParams', () {
      expect(isNotificationUnavailable(notif('n', target: _booking)), isFalse);
    });

    test('should_beFalse_when_teamTargetHasNoParams', () {
      expect(
        isNotificationUnavailable(
          notif('n', target: _team, params: NotificationParams.empty),
        ),
        isFalse,
      );
    });
  });

  group('openNotificationTarget (phase 069)', () {
    // Unmatched locations render `errorBuilder`, which records `state.uri`:
    // the pushed LOCATION (path + query) is what is compared, never a widget.
    Future<List<String>> pumpApp(
      WidgetTester tester,
      void Function(BuildContext) onReady, {
      _Mys mys = _Mys.owned,
      UserRole authRole = UserRole.salonOwner,
    }) async {
      final List<String> seen = <String>[];
      bool fired = false;
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext c, GoRouterState s) => Builder(
              builder: (BuildContext inner) {
                if (!fired) {
                  fired = true;
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => onReady(inner),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
        ],
        errorBuilder: (BuildContext c, GoRouterState s) {
          seen.add(s.uri.toString());
          return const SizedBox();
        },
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mySalonsProvider.overrideWith(() => _FakeMySalons(mys)),
            authProvider.overrideWith(() => FixedRoleAuth(authRole)),
          ],
          child: _KeepAuthAlive(
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return seen;
    }

    for (final UserRole role in UserRole.values) {
      for (final NotificationTarget target in <NotificationTarget>[
        _booking,
        _visit,
        _review,
        _team,
      ]) {
        testWidgets(
          'should_pushSameLocationAsOpenNotification_${role.name}_${target.runtimeType}',
          (WidgetTester tester) async {
            final List<String> viaItem = await pumpApp(
              tester,
              (BuildContext c) => openNotification(
                context: c,
                item: notif('n', target: target),
                role: role,
              ),
            );
            final List<String> viaTarget = await pumpApp(
              tester,
              (BuildContext c) => openNotificationTarget(
                context: c,
                target: target,
                role: role,
              ),
            );
            expect(viaTarget, viaItem);
            expect(viaTarget.length, routeFor(target, role) == null ? 0 : 1);
          },
        );
      }
    }

    for (final _Mys mys in <_Mys>[_Mys.other, _Mys.error]) {
      testWidgets(
        'should_fallBackToBookingDetail_when_ownerMySalons_${mys.name}',
        (tester) async {
          final List<String> seen = await pumpApp(
            tester,
            (BuildContext c) => openNotificationTarget(
              context: c,
              target: _booking,
              role: UserRole.salonOwner,
              type: AppNotificationType.reviewReceived,
            ),
            mys: mys,
          );
          expect(seen.length, 1);
          expect(
            seen.single,
            startsWith(RouteNames.salonStaffBookingDetail(_bk)),
          );
          expect(seen.single, contains('from=notification'));
          expect(seen.single, isNot(contains('/shell')));
        },
      );
    }

    testWidgets('should_fallBackToBookingDetail_when_ownerMySalonsTimesOut', (
      tester,
    ) async {
      final List<String> seen = <String>[];
      bool fired = false;
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext c, GoRouterState s) => Builder(
              builder: (BuildContext inner) {
                if (fired) return const SizedBox();
                fired = true;
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => unawaited(
                    openNotificationTarget(
                      context: inner,
                      target: _booking,
                      role: UserRole.salonOwner,
                      type: AppNotificationType.reviewReceived,
                      salonVerifyTimeout: const Duration(milliseconds: 50),
                    ),
                  ),
                );
                return const SizedBox();
              },
            ),
          ),
        ],
        errorBuilder: (BuildContext c, GoRouterState s) {
          seen.add(s.uri.toString());
          return const SizedBox();
        },
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mySalonsProvider.overrideWith(() => _FakeMySalons(_Mys.never)),
            authProvider.overrideWith(() => FixedRoleAuth(UserRole.salonOwner)),
          ],
          child: _KeepAuthAlive(
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(seen, isEmpty, reason: 'nothing navigates before the timeout');
      // fixed-wait-ok: crossing the injected 50ms verify timeout (fake clock)
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(seen.length, 1);
      expect(seen.single, startsWith(RouteNames.salonStaffBookingDetail(_bk)));
    });

    testWidgets('should_pushExactReviewsUrl_withoutFromNotification', (
      tester,
    ) async {
      final List<String> seen = await pumpApp(
        tester,
        (BuildContext c) => openNotificationTarget(
          context: c,
          target: _booking,
          role: UserRole.salonOwner,
          type: AppNotificationType.reviewReceived,
        ),
      );
      expect(seen, <String>['/salons/$_salon/shell?tab=reviews']);
    });

    testWidgets('should_pushExactReviewsUrl_viaOpenNotification', (
      tester,
    ) async {
      final List<String> seen = await pumpApp(
        tester,
        (BuildContext c) => openNotification(
          context: c,
          item: notif(
            'n',
            type: AppNotificationType.reviewReceived,
            target: _booking,
          ),
          role: UserRole.salonAdmin,
        ),
        authRole: UserRole.salonAdmin,
      );
      expect(seen, <String>['/salons/$_salon/shell?tab=reviews']);
    });

    testWidgets('should_stillDecorateFromNotification_when_otherType', (
      tester,
    ) async {
      final List<String> seen = await pumpApp(
        tester,
        (BuildContext c) => openNotificationTarget(
          context: c,
          target: _booking,
          role: UserRole.salonOwner,
          type: AppNotificationType.bookingCreated,
        ),
      );
      expect(seen.single, contains('from=notification'));
    });

    testWidgets('should_pushFallbackRoute_when_noRoute', (tester) async {
      final List<String> seen = await pumpApp(
        tester,
        (BuildContext c) => openNotificationTarget(
          context: c,
          target: _none,
          role: UserRole.client,
          fallbackRoute: RouteNames.notifications,
        ),
      );
      expect(seen, <String>[RouteNames.notifications]);
    });

    testWidgets('should_pushFallbackRoute_when_roleIsNull', (tester) async {
      final List<String> seen = await pumpApp(
        tester,
        (BuildContext c) => openNotificationTarget(
          context: c,
          target: _booking,
          role: null,
          fallbackRoute: RouteNames.notifications,
        ),
      );
      expect(seen, <String>[RouteNames.notifications]);
    });

    testWidgets('should_notUseFallback_when_routeExists', (tester) async {
      final List<String> seen = await pumpApp(
        tester,
        (BuildContext c) => openNotificationTarget(
          context: c,
          target: _booking,
          role: UserRole.independentMaster,
          fallbackRoute: RouteNames.notifications,
        ),
      );
      expect(seen.length, 1);
      expect(seen.single, contains(RouteNames.masterBookingDetail(_bk)));
    });

    testWidgets('should_stayPut_when_noRouteAndNoFallback', (tester) async {
      final List<String> seen = await pumpApp(
        tester,
        (BuildContext c) => openNotificationTarget(
          context: c,
          target: _none,
          role: UserRole.client,
        ),
      );
      expect(seen, isEmpty);
    });
  });

  group('openNotificationTarget pending owner verify (phase 391 audit)', () {
    late Completer<List<Salon>> gate;
    late _MutableAuth auth;
    late GoRouter router;
    late List<String> seen;
    late BuildContext homeCtx;

    Future<void> pumpGated(WidgetTester tester) async {
      gate = Completer<List<Salon>>();
      auth = _MutableAuth();
      seen = <String>[];
      // One ShellRoute owns the context the taps run from, so it stays mounted
      // across every go() below (a tap's `context.mounted` gate then does not
      // mask the location-fingerprint decision under test).
      router = GoRouter(
        routes: <RouteBase>[
          ShellRoute(
            builder: (BuildContext c, GoRouterState s, Widget child) => Builder(
              builder: (BuildContext inner) {
                homeCtx = inner;
                return child;
              },
            ),
            routes: <RouteBase>[
              GoRoute(
                path: '/salons/:id/shell',
                builder: (BuildContext c, GoRouterState s) {
                  // Only a PUSHED reviews landing counts as "seen"; a bare
                  // shell reached by go() is just a location.
                  if (s.uri.hasQuery) seen.add(s.uri.toString());
                  return const SizedBox();
                },
              ),
              for (final String path in <String>[
                '/',
                '/other',
                RouteNames.notifications,
                RouteNames.splash,
                RouteNames.salonHome,
              ])
                GoRoute(
                  path: path,
                  builder: (BuildContext c, GoRouterState s) =>
                      const SizedBox(),
                ),
            ],
          ),
        ],
        errorBuilder: (BuildContext c, GoRouterState s) {
          seen.add(s.uri.toString());
          return const SizedBox();
        },
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mySalonsProvider.overrideWith(() => _GatedMySalons(gate)),
            authProvider.overrideWith(() => auth),
          ],
          child: _KeepAuthAlive(
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    Future<void> tap(
      String id, {
      NotificationTarget target = _booking,
      String? fallback,
    }) => openNotificationTarget(
      context: homeCtx,
      target: target,
      role: UserRole.salonOwner,
      type: AppNotificationType.reviewReceived,
      notificationId: id,
      fallbackRoute: fallback,
    );

    Future<void> finish(WidgetTester tester) async {
      gate.complete(const <Salon>[Salon(id: _salon, name: 'B')]);
      await tester.pumpAndSettle();
    }

    testWidgets('should_pushSalonReviews_when_nothingChangesDuringVerify', (
      tester,
    ) async {
      await pumpGated(tester);
      unawaited(tap('n1'));
      await tester.pump();
      expect(seen, isEmpty);
      await finish(tester);
      expect(seen, <String>['/salons/$_salon/shell?tab=reviews']);
    });

    testWidgets('should_notPush_when_locationChangesDuringVerify', (
      tester,
    ) async {
      await pumpGated(tester);
      unawaited(tap('n1', fallback: RouteNames.notifications));
      await tester.pump();
      router.go('/other');
      await tester.pumpAndSettle();
      await finish(tester);
      expect(seen, isEmpty);
      // router-location-ok: a go() (not a push), so the raw read is accurate
      expect(router.routerDelegate.currentConfiguration.uri.path, '/other');
    });

    testWidgets('should_routeDifferentSecondTapToItsFallback_whileVerifying', (
      tester,
    ) async {
      await pumpGated(tester);
      unawaited(tap('n1'));
      await tester.pump();
      unawaited(
        tap(
          'n2',
          target: const NotificationTarget.booking(
            bookingId: 'bk-2',
            salonId: _salon,
          ),
          fallback: '/fallback-n2',
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, <String>['/fallback-n2']);
      await finish(tester);
      // The second tap moved the user, so the stale first push is suppressed
      // (no salon landing on top of its destination).
      expect(seen, <String>['/fallback-n2']);
    });

    testWidgets(
      'should_pushSalonReviews_when_appSettlesToRoleHomeDuringVerify',
      (tester) async {
        await pumpGated(tester);
        router.go(RouteNames.splash);
        await tester.pumpAndSettle();
        unawaited(tap('n1'));
        await tester.pump();
        router.go(RouteNames.salonHome); // owner's role home: app redirect
        await tester.pumpAndSettle();
        await finish(tester);
        expect(seen, <String>['/salons/$_salon/shell?tab=reviews']);
      },
    );

    testWidgets('should_pushFallbackRoute_when_appSettlesAndOwnershipFails', (
      tester,
    ) async {
      await pumpGated(tester);
      router.go(RouteNames.splash);
      await tester.pumpAndSettle();
      unawaited(tap('n1'));
      await tester.pump();
      router.go(RouteNames.salonHome);
      await tester.pumpAndSettle();
      gate.complete(const <Salon>[Salon(id: 'salon-a', name: 'A')]);
      await tester.pumpAndSettle();
      expect(seen, <String>[
        '${RouteNames.salonStaffBookingDetail(_bk)}?from=notification',
      ]);
    });

    testWidgets('should_notPush_when_tapFromNotificationsThenUserGoesHome', (
      tester,
    ) async {
      await pumpGated(tester);
      router.go(RouteNames.notifications);
      await tester.pumpAndSettle();
      unawaited(tap('n1'));
      await tester.pump();
      router.go(RouteNames.salonHome); // user backs out to role home
      await tester.pumpAndSettle();
      await finish(tester);
      expect(seen, isEmpty);
    });

    testWidgets('should_notPush_when_tapFromNotificationsThenBareSalonShell', (
      tester,
    ) async {
      await pumpGated(tester);
      router.go(RouteNames.notifications);
      await tester.pumpAndSettle();
      unawaited(tap('n1'));
      await tester.pump();
      router.go('/salons/$_salon/shell');
      await tester.pumpAndSettle();
      await finish(tester);
      expect(seen, isEmpty);
    });

    testWidgets('should_notPush_when_settleHappensButAnotherTapRan', (
      tester,
    ) async {
      await pumpGated(tester);
      router.go(RouteNames.splash);
      await tester.pumpAndSettle();
      unawaited(tap('n1'));
      await tester.pump();
      unawaited(tap('n2', target: _team, fallback: '/fallback-n2'));
      router.go(RouteNames.salonHome);
      await tester.pumpAndSettle();
      await finish(tester);
      // Latest tap wins: n1's stale push is skipped; only n2's own route ran.
      expect(seen.where((String l) => l.contains('tab=reviews')), isEmpty);
    });

    testWidgets('should_notPush_when_userNavigatesToNonHomeRoute', (
      tester,
    ) async {
      await pumpGated(tester);
      router.go(RouteNames.splash);
      await tester.pumpAndSettle();
      unawaited(tap('n1'));
      await tester.pump();
      router.go('/other');
      await tester.pumpAndSettle();
      await finish(tester);
      expect(seen, isEmpty);
    });

    testWidgets('should_dropSecondTapForSameId_whileVerifying', (tester) async {
      await pumpGated(tester);
      unawaited(tap('n1', fallback: '/fallback-n1'));
      await tester.pump();
      unawaited(tap('n1', fallback: '/fallback-n1'));
      await tester.pumpAndSettle();
      expect(seen, isEmpty);
      await finish(tester);
      expect(seen, <String>['/salons/$_salon/shell?tab=reviews']);
    });

    testWidgets('should_notPushSalon_when_userLogsOutDuringVerify', (
      tester,
    ) async {
      await pumpGated(tester);
      unawaited(tap('n1'));
      await tester.pump();
      auth.signOut();
      await finish(tester);
      expect(seen.where((String l) => l.contains('/shell')), isEmpty);
      expect(seen, isEmpty);
    });

    testWidgets('should_notPushSalon_when_roleChangesDuringVerify', (
      tester,
    ) async {
      await pumpGated(tester);
      unawaited(tap('n1'));
      await tester.pump();
      auth.setRole(UserRole.client);
      await finish(tester);
      expect(seen.where((String l) => l.contains('/shell')), isEmpty);
      expect(seen, isEmpty);
    });
  });
}
