// Phase 359 — NotificationMapper: per-type x per-target matrix, params
// (salon name), nullability policy. Decoding goes through the REAL
// `standardSerializers`. Run with `TZ=UTC` too.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/features/notifications/data/notification_mapper.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:built_value/serializer.dart';
import 'package:flutter_test/flutter_test.dart';

// The mapper drops any row whose id is not a UUID (the id goes into a URL
// path), so every fixture id is one.
const String _idDefault = '00000000-0000-4000-8000-000000000001';
const String _idOk = '00000000-0000-4000-8000-0000000000aa';
const String _idNoTs = '00000000-0000-4000-8000-0000000000bb';
const String _idA = '00000000-0000-4000-8000-00000000000a';
const String _idB = '00000000-0000-4000-8000-00000000000b';
const String _bk1 = '00000000-0000-4000-8000-0000000000b1';
const String _ap1 = '00000000-0000-4000-8000-0000000000a1';
const String _sl1 = '00000000-0000-4000-8000-0000000000c1';
const String _sl9 = '00000000-0000-4000-8000-0000000000c9';
const String _bk7 = '00000000-0000-4000-8000-0000000000b7';

Map<String, Object?> _row({
  Object? id = _idDefault,
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
    'bookingId': _bk1,
    'appointmentId': _ap1,
    'salonId': _sl1,
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
            bookingId: _bk1,
            appointmentId: _ap1,
            salonId: _sl1,
          ),
        );
      });

      test('should_mapType_${e.key}_withSalonTeamTarget', () {
        final n = _one(
          _row(type: e.key, target: {'kind': 'SALON_TEAM', 'salonId': _sl9}),
        );
        expect(n.type, e.value);
        expect(n.target, const NotificationTarget.salonTeam(salonId: _sl9));
      });

      test('should_mapType_${e.key}_withReviewTarget', () {
        final n = _one(
          _row(
            type: e.key,
            target: {'kind': 'BOOKING_REVIEW', 'bookingId': _bk7},
          ),
        );
        expect(n.type, e.value);
        expect(
          n.target,
          const NotificationTarget.bookingReview(bookingId: _bk7),
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
            'bookingId': _bk1,
            'appointmentId': '  ',
            'salonId': '',
          },
        ),
      );
      expect(n.target, const NotificationTarget.booking(bookingId: _bk1));
    });

    group('target id shape', () {
      for (final String bad in <String>['..', 'a/b', '?x', 'not-a-uuid']) {
        test('should_yieldNoTarget_when_bookingIdIs_$bad', () {
          expect(
            _one(_row(target: {'kind': 'BOOKING', 'bookingId': bad})).target,
            const NotificationTarget.none(),
          );
          expect(
            _one(
              _row(target: {'kind': 'BOOKING_REVIEW', 'bookingId': bad}),
            ).target,
            const NotificationTarget.none(),
          );
        });
        test('should_yieldNoTarget_when_salonIdIs_$bad', () {
          expect(
            _one(_row(target: {'kind': 'SALON_TEAM', 'salonId': bad})).target,
            const NotificationTarget.none(),
          );
          expect(
            _one(
              _row(
                target: {'kind': 'BOOKING', 'bookingId': _bk1, 'salonId': bad},
              ),
            ).target,
            const NotificationTarget.none(),
          );
        });
      }

      for (final String bad in <String>['..', 'a/b', '?x', 'not-a-uuid']) {
        test(
          'should_dropAppointmentIdButKeepBooking_when_appointmentIdIs_$bad',
          () {
            expect(
              _one(
                _row(
                  target: {
                    'kind': 'BOOKING',
                    'bookingId': _bk1,
                    'appointmentId': bad,
                    'salonId': _sl1,
                  },
                ),
              ).target,
              const NotificationTarget.booking(bookingId: _bk1, salonId: _sl1),
            );
          },
        );
      }

      test('should_keepTarget_when_idsAreValidUuids', () {
        expect(
          _one(_row(target: bookingTarget)).target,
          const NotificationTarget.booking(
            bookingId: _bk1,
            appointmentId: _ap1,
            salonId: _sl1,
          ),
        );
      });
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
        _page([_row(id: _idNoTs, createdAt: null), _row(id: _idOk)]),
      );
      expect(page.items.map((e) => e.id), <String>[_idOk]);
    });

    test('should_dropRow_when_idMissingOrBlank', () {
      final page = NotificationMapper.pageFromDto(
        _page([_row(id: null), _row(id: '   '), _row(id: _idOk)]),
      );
      expect(page.items.map((e) => e.id), <String>[_idOk]);
    });

    test('should_dropRow_when_idIsNotAUuid', () {
      final page = NotificationMapper.pageFromDto(
        _page([
          _row(id: 'n1'),
          _row(id: '../../users/me'),
          _row(id: '00000000-0000-4000-8000-00000000000g'),
          _row(id: '${_idOk}0'),
          _row(id: '%20$_idOk'),
          _row(id: _idOk),
        ]),
      );
      expect(page.items.map((e) => e.id), <String>[_idOk]);
    });

    test('should_keepRow_when_uuidIsUpperCase', () {
      final String upper = _idOk.toUpperCase();
      expect(_one(_row(id: upper)).id, upper);
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
        _page([_row(id: _idA), _row(id: _idB)]),
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

  group('push payload (phase 068)', () {
    Map<String, dynamic> d(Map<String, dynamic> extra) => <String, dynamic>{
      'v': '1',
      'notificationId': _idOk,
      'type': 'BOOKING_CREATED',
      ...extra,
    };

    NotificationTarget feedTarget(Map<String, Object?> target) =>
        NotificationMapper.fromDto(
          api.standardSerializers.deserialize(
                _row(type: 'BOOKING_CREATED', target: target),
                specifiedType: const FullType(api.NotificationResponse),
              )
              as api.NotificationResponse,
        )!.target;

    test('parity with the feed mapper for every targetKind', () {
      final cases = <Map<String, Object?>>[
        {
          'kind': 'BOOKING',
          'bookingId': _bk1,
          'appointmentId': _ap1,
          'salonId': _sl1,
        },
        {'kind': 'BOOKING', 'bookingId': _bk1},
        {'kind': 'BOOKING_REVIEW', 'bookingId': _bk1},
        {'kind': 'SALON_TEAM', 'salonId': _sl1},
        {'kind': 'NONE'},
        {'kind': 'BOOKING'},
        {'kind': 'BOOKING', 'bookingId': 'not-a-uuid'},
        {'kind': 'BOOKING', 'bookingId': _bk1, 'appointmentId': '../x'},
        {'kind': 'SALON_TEAM', 'salonId': 'x'},
        {'kind': 'WAT', 'bookingId': _bk1},
      ];
      for (final c in cases) {
        final push = <String, dynamic>{
          'targetKind': c['kind'],
          'bookingId': ?c['bookingId'],
          'appointmentId': ?c['appointmentId'],
          'salonId': ?c['salonId'],
        };
        expect(
          NotificationMapper.targetFromPushData(push),
          feedTarget(c),
          reason: '$c',
        );
      }
    });

    test('targetKind absent / non-string -> NoTarget', () {
      expect(
        NotificationMapper.targetFromPushData({}),
        const NotificationTarget.none(),
      );
      expect(
        NotificationMapper.targetFromPushData({
          'targetKind': 7,
          'bookingId': _bk1,
        }),
        const NotificationTarget.none(),
      );
    });

    test('push: a non-UUID appointmentId is dropped, the booking kept', () {
      final tap = NotificationMapper.pushTapFromData(
        d({
          'targetKind': 'BOOKING',
          'bookingId': _bk1,
          'appointmentId': 'a/b?x=1',
        }),
      )!;
      expect(tap.target, const NotificationTarget.booking(bookingId: _bk1));
    });

    test('pushTapFromData decodes id, type and target', () {
      final tap = NotificationMapper.pushTapFromData(
        d({'targetKind': 'BOOKING', 'bookingId': _bk1}),
      )!;
      expect(tap.notificationId, _idOk);
      expect(tap.type, AppNotificationType.bookingCreated);
      expect(tap.target, const NotificationTarget.booking(bookingId: _bk1));
    });

    test('missing / blank / non-UUID / non-string notificationId -> null', () {
      expect(
        NotificationMapper.pushTapFromData({'type': 'BOOKING_CREATED'}),
        isNull,
      );
      expect(
        NotificationMapper.pushTapFromData(d({'notificationId': ' '})),
        isNull,
      );
      expect(
        NotificationMapper.pushTapFromData(d({'notificationId': 'x'})),
        isNull,
      );
      expect(
        NotificationMapper.pushTapFromData(d({'notificationId': 1})),
        isNull,
      );
    });

    test('unknown / absent type -> unknown + NoTarget', () {
      for (final extra in <Map<String, dynamic>>[
        {'type': 'FROM_THE_FUTURE', 'targetKind': 'BOOKING', 'bookingId': _bk1},
        {'type': null, 'targetKind': 'BOOKING', 'bookingId': _bk1},
      ]) {
        final tap = NotificationMapper.pushTapFromData(d(extra))!;
        expect(tap.type, AppNotificationType.unknown);
        expect(tap.target, const NotificationTarget.none());
      }
    });

    test('unknown v is not gated; known keys still parse', () {
      final tap = NotificationMapper.pushTapFromData(
        d({'v': '2', 'targetKind': 'SALON_TEAM', 'salonId': _sl1}),
      )!;
      expect(tap.target, const NotificationTarget.salonTeam(salonId: _sl1));
    });
  });
}
