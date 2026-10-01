// Phase 364 — `routeFor`: the pure (target, role) -> route table.
//
// Table-driven over EVERY role x target; `null` marks the n/a combinations.
// The expected strings are built from the SAME `RouteNames` builders the router
// registers, so a renamed route breaks here, not silently in production.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_navigation.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
