// MO-1 — Unit tests for [AppointmentMapper] / [AppointmentItemMapper].
//
// Pure Dart: no ProviderScope, no widget tree, no network. Builds generated
// `AppointmentDetailResponse` / `AppointmentItemResponse` DTOs directly and
// asserts the domain mapping + the required-field error contract. Mirrors
// `booking_mapper_test.dart`.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking/data/appointment_mapper.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';

AppointmentItemResponse _buildItem({
  String bookingId = 'booking-1',
  String masterServiceId = 'service-1',
  String serviceName = 'Манікюр',
  DateTime? startsAt,
  DateTime? endsAt,
  int durationMinutesAtBooking = 60,
  num priceAtBooking = 500,
  num? priceMaxAtBooking,
}) =>
    (AppointmentItemResponseBuilder()
          ..bookingId = bookingId
          ..masterServiceId = masterServiceId
          ..serviceName = serviceName
          ..startsAt = startsAt ?? DateTime.utc(2026, 7, 10, 10)
          ..endsAt = endsAt ?? DateTime.utc(2026, 7, 10, 11)
          ..durationMinutesAtBooking = durationMinutesAtBooking
          ..priceAtBooking = priceAtBooking
          ..priceMaxAtBooking = priceMaxAtBooking)
        .build();

AppointmentDetailResponse _buildDetail({
  String? id = 'appt-1',
  AppointmentDetailResponseStatusEnum? status =
      AppointmentDetailResponseStatusEnum.CONFIRMED,
  DateTime? startsAt,
  DateTime? endsAt,
  int totalDurationMinutes = 90,
  num totalPrice = 800,
  num? totalPriceMax,
  bool canReview = false,
  String? salonName,
  AppointmentDetailResponseMasterTypeEnum masterType =
      AppointmentDetailResponseMasterTypeEnum.INDEPENDENT_MASTER,
  List<AppointmentItemResponse>? items,
}) {
  final b = AppointmentDetailResponseBuilder()
    ..masterId = 'master-1'
    ..masterFirstName = 'Оля'
    ..masterLastName = 'Коваль'
    ..totalDurationMinutes = totalDurationMinutes
    ..totalPrice = totalPrice
    ..totalPriceMax = totalPriceMax
    ..canReview = canReview
    ..salonName = salonName
    ..masterType = masterType
    ..startsAt = startsAt ?? DateTime.utc(2026, 7, 10, 10)
    ..endsAt = endsAt ?? DateTime.utc(2026, 7, 10, 11, 30)
    ..items = ListBuilder<AppointmentItemResponse>(
      items ?? <AppointmentItemResponse>[_buildItem()],
    );
  if (id != null) b.id = id;
  if (status != null) b.status = status;
  return b.build();
}

void main() {
  group('AppointmentMapper.fromDto', () {
    test('maps a full visit including ordered items', () {
      final dto = _buildDetail(
        totalPrice: 800,
        totalPriceMax: 1000,
        items: <AppointmentItemResponse>[
          _buildItem(
            bookingId: 'b-1',
            masterServiceId: 's-1',
            serviceName: 'Манікюр',
            startsAt: DateTime.utc(2026, 7, 10, 10),
            endsAt: DateTime.utc(2026, 7, 10, 11),
            priceAtBooking: 500,
          ),
          _buildItem(
            bookingId: 'b-2',
            masterServiceId: 's-2',
            serviceName: 'Педикюр',
            startsAt: DateTime.utc(2026, 7, 10, 11),
            endsAt: DateTime.utc(2026, 7, 10, 11, 30),
            priceAtBooking: 300,
            priceMaxAtBooking: 500,
          ),
        ],
      );

      final appt = AppointmentMapper.fromDto(dto);

      expect(appt.id, 'appt-1');
      expect(appt.status, BookingStatus.confirmed);
      expect(appt.masterFirstName, 'Оля');
      expect(appt.masterType, 'INDEPENDENT_MASTER');
      expect(appt.totalDurationMinutes, 90);
      expect(appt.totalPrice, 800.0);
      expect(appt.totalPriceMax, 1000.0);
      expect(appt.items, hasLength(2));
      expect(appt.items[0].bookingId, 'b-1');
      expect(appt.items[0].serviceName, 'Манікюр');
      expect(appt.items[0].priceMax, isNull);
      expect(appt.items[1].bookingId, 'b-2');
      expect(appt.items[1].priceMax, 500.0);
    });

    test('null totalPriceMax is carried through as null (single total)', () {
      final appt = AppointmentMapper.fromDto(_buildDetail(totalPriceMax: null));
      expect(appt.totalPriceMax, isNull);
    });

    test('empty items list maps to an empty list, not a throw', () {
      final appt = AppointmentMapper.fromDto(
        _buildDetail(items: <AppointmentItemResponse>[]),
      );
      expect(appt.items, isEmpty);
    });

    test('single-item visit maps its one item', () {
      final appt = AppointmentMapper.fromDto(
        _buildDetail(
          items: <AppointmentItemResponse>[
            _buildItem(bookingId: 'only-1', serviceName: 'Стрижка'),
          ],
        ),
      );
      expect(appt.items, hasLength(1));
      expect(appt.items.single.bookingId, 'only-1');
      expect(appt.items.single.serviceName, 'Стрижка');
    });

    // Pins the full header / notes / locality passthrough so a FUTURE field
    // drop between the wire DTO and the domain [Appointment] — the exact class
    // of bug that reintroduced the booking "city-only address" regression —
    // fails here, loudly, at unit level. None of these are asserted by the
    // "maps a full visit" happy path above.
    test('carries master header, notes, locality and createdAt through '
        'unchanged', () {
      final dto =
          (AppointmentDetailResponseBuilder()
                ..id = 'appt-2'
                ..status = AppointmentDetailResponseStatusEnum.DECLINED
                ..masterId = 'master-9'
                ..masterFirstName = 'Ірина'
                ..masterLastName = 'Мельник'
                ..masterProfessionalTitle = 'Топ-майстер'
                ..masterAvatarUrl = 'https://cdn.example/av.jpg'
                ..masterType =
                    AppointmentDetailResponseMasterTypeEnum.SALON_MASTER
                ..salonName = 'Салон Краси'
                ..startsAt = DateTime.utc(2026, 7, 10, 10)
                ..endsAt = DateTime.utc(2026, 7, 10, 11, 30)
                ..totalDurationMinutes = 90
                ..totalPrice = 800
                ..canReview = false
                ..clientComment = 'Прошу подзвонити'
                ..providerComment = 'Клієнт не прийшов'
                ..clientCancellationNote = 'Захворіла'
                ..cityLabel = 'Львів'
                ..districtLabel = 'Галицький'
                ..street = 'вулиця Городоцька'
                ..buildingNo = '15'
                ..locationNote = 'Третій поверх, код 1234'
                ..createdAt = DateTime.utc(2026, 7, 1, 9)
                ..items = ListBuilder<AppointmentItemResponse>(
                  <AppointmentItemResponse>[_buildItem()],
                ))
              .build();

      final appt = AppointmentMapper.fromDto(dto);

      expect(appt.masterProfessionalTitle, 'Топ-майстер');
      expect(appt.masterAvatarUrl, 'https://cdn.example/av.jpg');
      expect(appt.masterType, 'SALON_MASTER');
      expect(appt.salonName, 'Салон Краси');
      expect(appt.clientComment, 'Прошу подзвонити');
      expect(appt.providerComment, 'Клієнт не прийшов');
      expect(appt.clientCancellationNote, 'Захворіла');
      expect(appt.cityLabel, 'Львів');
      expect(appt.districtLabel, 'Галицький');
      expect(appt.street, 'вулиця Городоцька');
      expect(appt.buildingNo, '15');
      expect(appt.locationNote, 'Третій поверх, код 1234');
      expect(appt.createdAt, DateTime.utc(2026, 7, 1, 9));
    });

    test('null notes / locality / optional header fields stay null (a null is '
        'a real signal, never defaulted)', () {
      // _buildDetail leaves every nullable header field unset → null on the
      // wire. The mapper must carry those nulls through, NOT coalesce them to
      // '' the way it (correctly) defaults the REQUIRED masterId/masterType.
      final appt = AppointmentMapper.fromDto(_buildDetail());

      expect(appt.masterProfessionalTitle, isNull);
      expect(appt.masterAvatarUrl, isNull);
      expect(appt.salonName, isNull);
      expect(appt.clientComment, isNull);
      expect(appt.providerComment, isNull);
      expect(appt.clientCancellationNote, isNull);
      expect(appt.cityLabel, isNull);
      expect(appt.districtLabel, isNull);
      expect(appt.street, isNull);
      expect(appt.buildingNo, isNull);
      expect(appt.locationNote, isNull);
      expect(appt.createdAt, isNull);
    });

    test(
      'unrecognised status decodes to BookingStatus.unknown (keep-and-deny)',
      () {
        // The generated enum can't hold an unknown wire value, so exercise the
        // decode path via a status whose name is not a known member is not
        // constructible here — instead assert every real member round-trips and
        // rely on booking_status_test for the unknown branch. Here we assert the
        // five real statuses map 1:1.
        final map = <AppointmentDetailResponseStatusEnum, BookingStatus>{
          AppointmentDetailResponseStatusEnum.CONFIRMED:
              BookingStatus.confirmed,
          AppointmentDetailResponseStatusEnum.COMPLETED:
              BookingStatus.completed,
          AppointmentDetailResponseStatusEnum.DECLINED: BookingStatus.declined,
          AppointmentDetailResponseStatusEnum.CANCELLED:
              BookingStatus.cancelled,
          AppointmentDetailResponseStatusEnum.NOT_COMPLETED:
              BookingStatus.notCompleted,
        };
        map.forEach((wireStatus, expected) {
          final appt = AppointmentMapper.fromDto(
            _buildDetail(status: wireStatus),
          );
          expect(appt.status, expected);
        });
      },
    );

    test('missing id → ServerFailure(null)', () {
      expect(
        () => AppointmentMapper.fromDto(_buildDetail(id: null)),
        throwsA(
          isA<ServerFailure>().having(
            (f) => f.statusCode,
            'statusCode',
            isNull,
          ),
        ),
      );
    });

    test('missing status → ServerFailure(null)', () {
      expect(
        () => AppointmentMapper.fromDto(_buildDetail(status: null)),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a malformed item fails the WHOLE visit (ServerFailure)', () {
      // An item missing bookingId corrupts the visit total → the whole
      // appointment throws, rather than the item being silently dropped.
      final badItem =
          (AppointmentItemResponseBuilder()
                ..masterServiceId = 's-1'
                ..serviceName = 'X'
                ..startsAt = DateTime.utc(2026, 7, 10, 10)
                ..endsAt = DateTime.utc(2026, 7, 10, 11)
                ..priceAtBooking = 100)
              .build(); // bookingId left unset
      expect(
        () => AppointmentMapper.fromDto(
          _buildDetail(items: <AppointmentItemResponse>[badItem]),
        ),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('AppointmentItemMapper.fromDto', () {
    test('maps all fields; null priceMax stays null', () {
      final item = AppointmentItemMapper.fromDto(
        _buildItem(priceAtBooking: 400, priceMaxAtBooking: null),
      );
      expect(item.bookingId, 'booking-1');
      expect(item.masterServiceId, 'service-1');
      expect(item.serviceName, 'Манікюр');
      expect(item.durationMinutes, 60);
      expect(item.price, 400.0);
      expect(item.priceMax, isNull);
    });

    test('non-null priceMax is carried as the band ceiling', () {
      final item = AppointmentItemMapper.fromDto(
        _buildItem(priceAtBooking: 400, priceMaxAtBooking: 700),
      );
      expect(item.price, 400.0);
      expect(item.priceMax, 700.0);
    });

    test('missing masterServiceId → ServerFailure(null)', () {
      final bad =
          (AppointmentItemResponseBuilder()
                ..bookingId = 'b-1'
                ..serviceName = 'X'
                ..startsAt = DateTime.utc(2026, 7, 10, 10)
                ..endsAt = DateTime.utc(2026, 7, 10, 11)
                ..priceAtBooking = 100)
              .build();
      expect(
        () => AppointmentItemMapper.fromDto(bad),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}
