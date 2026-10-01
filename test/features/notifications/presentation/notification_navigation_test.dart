// Phase 364 — `routeFor`: the pure (target, role) -> route table.
//
// Table-driven over EVERY role x target; `null` marks the n/a combinations.
// The expected strings are built from the SAME `RouteNames` builders the router
// registers, so a renamed route breaks here, not silently in production.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_navigation.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';

const String _bk = 'bk-1';
const String _salon = 'salon-b';

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
      void Function(BuildContext) onReady,
    ) async {
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
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
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
}
