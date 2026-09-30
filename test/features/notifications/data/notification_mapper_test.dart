// Phase 359 — NotificationMapper: per-type x per-target matrix, params
// (salon name), nullability policy. Decoding goes through the REAL
// `standardSerializers`. Run with `TZ=UTC` too.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/features/notifications/data/notification_mapper.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:built_value/serializer.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _row({
  Object? id = 'n1',
  Object? type = 'BOOKING_CREATED',
  Object? createdAt = '2026-09-30T13:00:00+03:00',
  Object? read,
  Object? target,
  Object? params,
}) => <String, Object?>{
  'id': ?id,
  'type': ?type,
  'createdAt': ?createdAt,
  'read': ?read,
  'target': ?target,
  'params': ?params,
};

api.PageResponseNotificationResponse _page(
  List<Map<String, Object?>> rows, {
  Map<String, Object?> extra = const <String, Object?>{},
}) =>
    api.standardSerializers.deserialize(<String, Object?>{
          'success': true,
          'data': rows,
          ...extra,
        }, specifiedType: const FullType(api.PageResponseNotificationResponse))
        as api.PageResponseNotificationResponse;

AppNotification _one(Map<String, Object?> row) =>
    NotificationMapper.pageFromDto(_page([row])).items.single;

void main() {
  const wire = <String, AppNotificationType>{
    'BOOKING_CREATED': AppNotificationType.bookingCreated,
    'BOOKING_CANCELLED_BY_CLIENT': AppNotificationType.bookingCancelledByClient,
    'BOOKING_DECLINED': AppNotificationType.bookingDeclined,
    'BOOKING_NOT_COMPLETED': AppNotificationType.bookingNotCompleted,
    'BOOKING_RESCHEDULED': AppNotificationType.bookingRescheduled,
    'REVIEW_REQUESTED': AppNotificationType.reviewRequested,
    'BOOKING_CANCELLED_SALON_CLOSED':
        AppNotificationType.bookingCancelledSalonClosed,
    'BOOKING_CANCELLED_MASTER_REMOVED':
        AppNotificationType.bookingCancelledMasterRemoved,
    'REVIEW_RECEIVED': AppNotificationType.reviewReceived,
    'INVITE_ACCEPTED': AppNotificationType.inviteAccepted,
  };

  const bookingTarget = <String, Object?>{
    'kind': 'BOOKING',
    'bookingId': 'b1',
    'appointmentId': 'ap1',
    'salonId': 's1',
  };

  group('type x target matrix', () {
    test('should_coverEveryEnumValueExceptUnknown', () {
      expect(
        wire.values.toSet(),
        AppNotificationType.values.toSet()..remove(AppNotificationType.unknown),
      );
    });

    for (final e in wire.entries) {
      test('should_mapType_${e.key}_withBookingTarget', () {
        final n = _one(_row(type: e.key, target: bookingTarget));
        expect(n.type, e.value);
        expect(
          n.target,
          const NotificationTarget.booking(
            bookingId: 'b1',
            appointmentId: 'ap1',
            salonId: 's1',
          ),
        );
      });

      test('should_mapType_${e.key}_withSalonTeamTarget', () {
        final n = _one(
          _row(type: e.key, target: {'kind': 'SALON_TEAM', 'salonId': 's9'}),
        );
        expect(n.type, e.value);
        expect(n.target, const NotificationTarget.salonTeam(salonId: 's9'));
      });

      test('should_mapType_${e.key}_withReviewTarget', () {
        final n = _one(
          _row(
            type: e.key,
            target: {'kind': 'BOOKING_REVIEW', 'bookingId': 'b7'},
          ),
        );
        expect(n.type, e.value);
        expect(
          n.target,
          const NotificationTarget.bookingReview(bookingId: 'b7'),
        );
      });
    }

    test('should_yieldNoTarget_when_targetAbsent', () {
      expect(_one(_row()).target, const NotificationTarget.none());
    });

    test('should_yieldUnknownAndNoTarget_when_typeAbsent', () {
      final n = _one(_row(type: null, target: bookingTarget));
      expect(n.type, AppNotificationType.unknown);
      expect(n.target, const NotificationTarget.none());
    });

    test('should_blankAppointmentAndSalonIds_notPropagate', () {
      final n = _one(
        _row(
          target: {
            'kind': 'BOOKING',
            'bookingId': 'b1',
            'appointmentId': '  ',
            'salonId': '',
          },
        ),
      );
      expect(n.target, const NotificationTarget.booking(bookingId: 'b1'));
    });

    test('should_yieldNoTarget_when_bookingIdBlank', () {
      final n = _one(_row(target: {'kind': 'BOOKING', 'bookingId': '   '}));
      expect(n.target, const NotificationTarget.none());
    });

    test('should_yieldNoTarget_when_reviewKindWithoutBookingId', () {
      final n = _one(_row(target: {'kind': 'BOOKING_REVIEW'}));
      expect(n.target, const NotificationTarget.none());
    });
  });

  group('params', () {
    test('should_carrySalonNameAndTrimBlanks', () {
      final n = _one(
        _row(
          params: {
            'salonName': '  Салон Б  ',
            'counterpartName': '   ',
            'serviceName': 'Манікюр',
          },
        ),
      );
      expect(n.params.salonName, 'Салон Б');
      expect(n.params.counterpartName, isNull);
      expect(n.params.serviceName, 'Манікюр');
    });

    test('should_mapKnownSubjectRole', () {
      final n = _one(
        _row(params: {'subjectName': 'Іра', 'subjectRole': 'SALON_MASTER'}),
      );
      expect(n.params.subjectName, 'Іра');
      expect(n.params.subjectRole, 'SALON_MASTER');
    });

    test('should_emitParamsEmpty_when_paramsAbsent', () {
      expect(_one(_row()).params, NotificationParams.empty);
    });

    test('should_normalizeStartsAtToUtc', () {
      final n = _one(_row(params: {'startsAt': '2026-10-01T12:30:00+03:00'}));
      expect(n.params.startsAt, DateTime.utc(2026, 10, 1, 9, 30));
      expect(n.params.startsAt!.isUtc, isTrue);
    });
  });

  group('row policy', () {
    test('should_dropRow_when_createdAtMissing', () {
      final page = NotificationMapper.pageFromDto(
        _page([_row(id: 'no-ts', createdAt: null), _row(id: 'ok')]),
      );
      expect(page.items.map((e) => e.id), <String>['ok']);
    });

    test('should_dropRow_when_idMissingOrBlank', () {
      final page = NotificationMapper.pageFromDto(
        _page([_row(id: null), _row(id: '   '), _row(id: 'ok')]),
      );
      expect(page.items.map((e) => e.id), <String>['ok']);
    });

    test('should_defaultReadToFalse_when_absent', () {
      expect(_one(_row()).read, isFalse);
      expect(_one(_row(read: true)).read, isTrue);
    });

    test('should_normalizeCreatedAtToUtc', () {
      final n = _one(_row(createdAt: '2026-09-30T13:00:00+03:00'));
      expect(n.createdAt, DateTime.utc(2026, 9, 30, 10));
      expect(n.createdAt.isUtc, isTrue);
    });
  });

  group('page', () {
    test('should_applyDefaults_when_paginationFieldsAbsent', () {
      final p = NotificationMapper.pageFromDto(
        _page([_row(id: 'a'), _row(id: 'b')]),
      );
      expect(p.page, 0);
      expect(p.size, 2);
      expect(p.totalElements, 2);
      expect(p.totalPages, 1);
      expect(p.hasNext, isFalse);
    });

    test('should_reportHasNext_when_morePagesExist', () {
      final p = NotificationMapper.pageFromDto(
        _page(
          [_row()],
          extra: {'page': 0, 'size': 1, 'totalElements': 3, 'totalPages': 3},
        ),
      );
      expect(p.hasNext, isTrue);
      final last = NotificationMapper.pageFromDto(
        _page(
          [_row()],
          extra: {'page': 2, 'size': 1, 'totalElements': 3, 'totalPages': 3},
        ),
      );
      expect(last.hasNext, isFalse);
    });

    test('should_returnEmptyPage_when_dataAbsent', () {
      final dto =
          api.standardSerializers.deserialize(
                <String, Object?>{'success': true},
                specifiedType: const FullType(
                  api.PageResponseNotificationResponse,
                ),
              )
              as api.PageResponseNotificationResponse;
      final p = NotificationMapper.pageFromDto(dto);
      expect(p.items, isEmpty);
      expect(p.hasNext, isFalse);
    });
  });
}
