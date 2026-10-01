// Phase 359 — notification feed data layer: real-serializer decoding + mapper
// + repository failure mapping.
//
// Decoding goes through `standardSerializers` (what `notificationsApiProvider`
// wires), so unknown enum values are proven to survive the REAL wire path.
// Run with `TZ=UTC` too — dates are parsed as instants.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/notifications/data/notification_mapper.dart';
import 'package:beautica_mobile/features/notifications/data/notification_repository.dart';
import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements api.NotificationsApi {}

RequestOptions _ro() => RequestOptions(path: '/api/v1/notifications');

/// A deterministic UUID for a short readable label (the mapper drops rows whose
/// id is not a UUID). An empty label stays empty (the "blank id" case).
String _uid(String label) {
  if (label.isEmpty) return '';
  final String hex = label.codeUnits
      .map((int c) => c.toRadixString(16).padLeft(2, '0'))
      .join()
      .padLeft(12, '0');
  assert(hex.length == 12, 'label too long for the UUID tail');
  return '00000000-0000-4000-8000-$hex';
}

Map<String, Object?> _row(
  String id,
  String type, {
  Map<String, Object?>? target,
  Object? params = const <String, Object?>{},
}) => <String, Object?>{
  'id': _uid(id),
  'type': type,
  'createdAt': '2026-09-30T10:00:00Z',
  'read': false,
  'target': target ?? <String, Object?>{'kind': 'NONE'},
  'params': params,
};

api.PageResponseNotificationResponse _page(List<Map<String, Object?>> rows) =>
    api.standardSerializers.deserialize(<String, Object?>{
          'success': true,
          'data': rows,
          'page': 0,
          'size': 20,
          'totalElements': rows.length,
          'totalPages': 1,
        }, specifiedType: const FullType(api.PageResponseNotificationResponse))
        as api.PageResponseNotificationResponse;

DioException _status(int code) => DioException(
  requestOptions: _ro(),
  response: Response<dynamic>(requestOptions: _ro(), statusCode: code),
  type: DioExceptionType.badResponse,
);

void main() {
  group('mapping', () {
    test('should_mapEveryType', () {
      const wire = <String, AppNotificationType>{
        'BOOKING_CREATED': AppNotificationType.bookingCreated,
        'BOOKING_CANCELLED_BY_CLIENT':
            AppNotificationType.bookingCancelledByClient,
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
      final page = NotificationMapper.pageFromDto(
        _page(<Map<String, Object?>>[
          for (final (int i, String k) in wire.keys.indexed) _row('t$i', k),
        ]),
      );
      expect(page.items.map((e) => e.type).toList(), wire.values.toList());
    });

    test('should_mapEveryTargetKind', () {
      final page = NotificationMapper.pageFromDto(
        _page(<Map<String, Object?>>[
          _row(
            'a',
            'BOOKING_CREATED',
            target: {
              'kind': 'BOOKING',
              'bookingId': 'b1',
              'appointmentId': 'ap1',
              'salonId': 's1',
            },
          ),
          _row(
            'b',
            'REVIEW_REQUESTED',
            target: {'kind': 'BOOKING_REVIEW', 'bookingId': 'b2'},
          ),
          _row(
            'c',
            'INVITE_ACCEPTED',
            target: {'kind': 'SALON_TEAM', 'salonId': 's2'},
          ),
          _row('d', 'BOOKING_DECLINED', target: {'kind': 'NONE'}),
        ]),
      );
      expect(
        page.items[0].target,
        const NotificationTarget.booking(
          bookingId: 'b1',
          appointmentId: 'ap1',
          salonId: 's1',
        ),
      );
      expect(
        page.items[1].target,
        const NotificationTarget.bookingReview(bookingId: 'b2'),
      );
      expect(
        page.items[2].target,
        const NotificationTarget.salonTeam(salonId: 's2'),
      );
      expect(page.items[3].target, const NotificationTarget.none());
    });

    test('should_fallBackToUnknownAndNoTarget_when_typeUnknown', () {
      late NotificationPage page;
      expect(
        () => page = NotificationMapper.pageFromDto(
          _page(<Map<String, Object?>>[
            _row(
              'x',
              'SOMETHING_NEW',
              target: {'kind': 'BOOKING', 'bookingId': 'b1'},
            ),
          ]),
        ),
        returnsNormally,
      );
      expect(page.items.single.type, AppNotificationType.unknown);
      expect(page.items.single.target, const NotificationTarget.none());
    });

    test('should_fallBackToNoTarget_when_kindUnknownOrIdMissing', () {
      final page = NotificationMapper.pageFromDto(
        _page(<Map<String, Object?>>[
          _row('a', 'BOOKING_CREATED', target: {'kind': 'GALAXY'}),
          _row('b', 'BOOKING_CREATED', target: {'kind': 'BOOKING'}),
          _row('c', 'INVITE_ACCEPTED', target: {'kind': 'SALON_TEAM'}),
        ]),
      );
      expect(
        page.items.map((e) => e.target),
        everyElement(const NotificationTarget.none()),
      );
    });

    test('should_tolerateNullParams_and_unknownSubjectRole', () {
      final page = NotificationMapper.pageFromDto(
        _page(<Map<String, Object?>>[
          _row('a', 'BOOKING_CREATED', params: null),
          _row(
            'b',
            'BOOKING_CREATED',
            params: {
              'counterpartName': 'Оля',
              'serviceName': 'Манікюр',
              'serviceCount': 2,
              'startsAt': '2026-10-01T09:30:00Z',
              'salonName': 'Салон Б',
              'subjectName': 'Іра',
              'subjectRole': 'ALIEN',
            },
          ),
        ]),
      );
      expect(page.items[0].params, NotificationParams.empty);
      final p = page.items[1].params;
      expect(p.counterpartName, 'Оля');
      expect(p.salonName, 'Салон Б');
      expect(p.serviceCount, 2);
      expect(p.startsAt, DateTime.utc(2026, 10, 1, 9, 30));
      expect(p.subjectRole, isNull);
    });

    test('should_dropRowWithoutId_notFailThePage', () {
      final bad = _row('', 'BOOKING_CREATED');
      final page = NotificationMapper.pageFromDto(
        _page(<Map<String, Object?>>[bad, _row('ok', 'BOOKING_CREATED')]),
      );
      expect(page.items.map((e) => e.id), <String>[_uid('ok')]);
    });
  });

  group('repository', () {
    late _MockApi mockApi;
    late HttpNotificationRepository repo;
    setUp(() {
      mockApi = _MockApi();
      repo = HttpNotificationRepository(mockApi);
    });

    test('should_returnMappedPage', () async {
      when(() => mockApi.listFeed(page: 0, size: 20)).thenAnswer(
        (_) async => Response(
          requestOptions: _ro(),
          data: _page(<Map<String, Object?>>[_row('a', 'BOOKING_CREATED')]),
        ),
      );
      final page = await repo.fetchPage(page: 0, size: 20);
      expect(page.items.single.id, _uid('a'));
      expect(page.hasNext, isFalse);
    });

    test('should_returnStableItemsList_when_readTwice', () async {
      when(() => mockApi.listFeed(page: 0, size: 20)).thenAnswer(
        (_) async => Response(
          requestOptions: _ro(),
          data: _page(<Map<String, Object?>>[_row('a', 'BOOKING_CREATED')]),
        ),
      );
      final page = await repo.fetchPage(page: 0, size: 20);
      expect(identical(page.items, page.items), isTrue);
      expect(() => page.items.add(page.items.first), throwsUnsupportedError);
    });

    test('should_throwNotFoundFailure_when_markRead404', () async {
      when(
        () => mockApi.markRead(id: 'gone'),
      ).thenAnswer((_) async => throw _status(404));
      await expectLater(repo.markRead('gone'), throwsA(isA<NotFoundFailure>()));
    });

    test('should_rethrowInterceptorFailure_when_429', () async {
      final err = DioException(
        requestOptions: _ro(),
        error: const NotificationsRateLimitedFailure(retryAfterSeconds: 30),
        type: DioExceptionType.badResponse,
      );
      when(() => mockApi.unreadCount()).thenAnswer((_) async => throw err);
      await expectLater(
        repo.unreadCount(),
        throwsA(
          isA<NotificationsRateLimitedFailure>().having(
            (f) => f.retryAfterSeconds,
            'retryAfterSeconds',
            30,
          ),
        ),
      );
    });

    test('should_mapOwn429_toNotificationsRateLimitedFailure', () async {
      DioException e429(Headers h) => DioException(
        requestOptions: _ro(),
        response: Response<dynamic>(
          requestOptions: _ro(),
          statusCode: 429,
          headers: h,
        ),
        type: DioExceptionType.badResponse,
      );
      when(() => mockApi.unreadCount()).thenAnswer(
        (_) async => throw e429(
          Headers.fromMap({
            'retry-after': ['30'],
          }),
        ),
      );
      await expectLater(
        repo.unreadCount(),
        throwsA(
          isA<NotificationsRateLimitedFailure>().having(
            (f) => f.retryAfterSeconds,
            'retryAfterSeconds',
            30,
          ),
        ),
      );
      when(
        () => mockApi.unreadCount(),
      ).thenAnswer((_) async => throw e429(Headers()));
      await expectLater(
        repo.unreadCount(),
        throwsA(
          isA<NotificationsRateLimitedFailure>().having(
            (f) => f.retryAfterSeconds,
            'retryAfterSeconds',
            isNull,
          ),
        ),
      );
    });

    test('should_mapBadCertificate_toCertificateFailure', () async {
      when(() => mockApi.unreadCount()).thenAnswer(
        (_) async => throw DioException(
          requestOptions: _ro(),
          type: DioExceptionType.badCertificate,
        ),
      );
      await expectLater(repo.unreadCount(), throwsA(isA<CertificateFailure>()));
    });

    test('should_mapTimeout_toNetworkFailure_and5xx_toServerFailure', () async {
      when(() => mockApi.unreadCount()).thenAnswer(
        (_) async => throw DioException(
          requestOptions: _ro(),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      await expectLater(repo.unreadCount(), throwsA(isA<NetworkFailure>()));
      when(
        () => mockApi.unreadCount(),
      ).thenAnswer((_) async => throw _status(503));
      await expectLater(
        repo.unreadCount(),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'status', 503),
        ),
      );
    });

    test('should_clampNegativeUnreadCountToZero_and_returnCount', () async {
      when(() => mockApi.unreadCount()).thenAnswer(
        (_) async => Response(
          requestOptions: _ro(),
          data:
              api.standardSerializers.deserialize(
                    <String, Object?>{
                      'success': true,
                      'data': {'count': 7},
                    },
                    specifiedType: const FullType(
                      api.ApiResponseUnreadCountResponse,
                    ),
                  )
                  as api.ApiResponseUnreadCountResponse,
        ),
      );
      expect(await repo.unreadCount(), 7);
    });

    test('should_sendUpToAsUtc_and_returnUpdated', () async {
      when(
        () => mockApi.markAllRead(
          markAllReadRequest: any(named: 'markAllReadRequest'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: _ro(),
          data:
              api.standardSerializers.deserialize(
                    <String, Object?>{
                      'success': true,
                      'data': {'updated': 3},
                    },
                    specifiedType: const FullType(
                      api.ApiResponseMarkAllReadResponse,
                    ),
                  )
                  as api.ApiResponseMarkAllReadResponse,
        ),
      );
      final n = await repo.markAllRead(upTo: DateTime.utc(2026, 9, 30, 10));
      expect(n, 3);
      final req =
          verify(
                () => mockApi.markAllRead(
                  markAllReadRequest: captureAny(named: 'markAllReadRequest'),
                ),
              ).captured.single
              as api.MarkAllReadRequest;
      expect(req.upTo, DateTime.utc(2026, 9, 30, 10));
    });
  });
}
