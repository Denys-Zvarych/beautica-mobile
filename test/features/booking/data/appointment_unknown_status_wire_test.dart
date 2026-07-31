// The WIRE-LAYER proof that an unrecognised backend status on a multi-service
// VISIT — at the visit level or on one of its line items — survives
// deserialization as [BookingStatus.unknown] instead of taking the whole visit
// down.
//
// WHY THIS FILE EXISTS (and why `appointment_mapper_test.dart` was not enough)
// ---------------------------------------------------------------------------
// Identical reasoning to `booking_unknown_status_wire_test.dart`, applied to
// the appointment DTOs, which carried exactly the same defect:
// `AppointmentDetailResponseStatusEnum` and `AppointmentItemResponseStatusEnum`
// are built_value `EnumClass`es with only the members the committed OpenAPI
// snapshot declares and NO unknown fallback, so `standardSerializers` threw
// `ArgumentError` on any other wire value — inside the generated client,
// BEFORE `AppointmentMapper` ran. `appointment_mapper_test.dart` cannot catch
// that: a DTO it BUILDS ITSELF can only ever hold a legal enum member, so its
// keep-and-deny assertions were vacuous on the real network path.
//
// So these tests start from JSON and drive it through the SAME
// [beauticaSerializers] the production `appointmentApiProvider` uses. Both
// halves of the fix are load-bearing and both are asserted here:
//   1. the tolerance plugin STRIPS the unrecognised value (DTO decodes,
//      `status == null`), and
//   2. `AppointmentMapper` DEGRADES that null to [BookingStatus.unknown]
//      rather than throwing [ServerFailure] — without which step 1 alone
//      would turn a graceful degrade into a hard failure, strictly worse than
//      the throw it replaced.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/beautica_serializers.dart';
import 'package:beautica_mobile/features/booking/data/appointment_mapper.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:built_value/serializer.dart';
import 'package:flutter_test/flutter_test.dart';

/// One `AppointmentItemResponse` line exactly as the backend renders it, with
/// [status] injectable so a test can supply a value this build predates.
Map<String, dynamic> _itemJson({
  required String bookingId,
  required String status,
}) => <String, dynamic>{
  'bookingId': bookingId,
  'masterServiceId': 'assign-$bookingId',
  'serviceName': 'Манікюр з покриттям',
  'status': status,
  // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
  'startsAt': '2026-08-14T10:00:00',
  // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
  'endsAt': '2026-08-14T11:30:00',
  'durationMinutesAtBooking': 90,
  'priceAtBooking': 500,
  'priceMaxAtBooking': null,
};

/// One `AppointmentDetailResponse` (a multi-service visit) as the backend
/// renders it, with the visit-level [status] injectable.
Map<String, dynamic> _visitJson({
  required String status,
  List<Map<String, dynamic>>? items,
}) => <String, dynamic>{
  'id': 'appointment-1',
  'status': status,
  'masterId': 'master-aaa',
  'masterFirstName': 'Софія',
  'masterLastName': 'Бондар',
  'masterType': 'INDEPENDENT_MASTER',
  // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
  'startsAt': '2026-08-14T10:00:00',
  // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
  'endsAt': '2026-08-14T11:30:00',
  'totalDurationMinutes': 90,
  'totalPrice': 500,
  'totalPriceMax': null,
  'canReview': false,
  'items':
      items ??
      <Map<String, dynamic>>[
        _itemJson(bookingId: 'booking-1', status: 'CONFIRMED'),
      ],
};

AppointmentDetailResponse _decode(Map<String, dynamic> json) =>
    beauticaSerializers.deserialize(
          json,
          specifiedType: const FullType(AppointmentDetailResponse),
        )
        as AppointmentDetailResponse;

void main() {
  group('unrecognised VISIT status at the wire seam', () {
    test('a visit status this build does not know decodes to '
        'BookingStatus.unknown instead of throwing out of the generated enum '
        'serializer', () {
      // `RESCHEDULED` is not one of the five members the committed OpenAPI
      // snapshot declares. Before the tolerance plugin this line threw:
      //   Deserializing to 'AppointmentDetailResponseStatusEnum' failed due
      //   to: Invalid argument(s): RESCHEDULED
      final AppointmentDetailResponse dto = _decode(
        _visitJson(status: 'RESCHEDULED'),
      );

      expect(
        dto.status,
        isNull,
        reason:
            'the unrecognised value is STRIPPED, because the generated '
            'EnumClass has no member that could represent it',
      );

      // Second half of the fix: the mapper must DEGRADE the stripped field,
      // not reject it. It used to list `status` among the fields whose
      // absence is a broken contract → ServerFailure.
      final Appointment visit = AppointmentMapper.fromDto(dto);
      expect(
        visit.status,
        BookingStatus.unknown,
        reason: 'the stripped status must surface as unknown, not an error',
      );
      // Keep-and-deny: the visit stays visible but grants no capability.
      expect(visit.id, 'appointment-1');
      expect(visit.items, hasLength(1));
      expect(visit.totalPrice, 500.0);
    });

    test('every KNOWN visit status still decodes to its real member — the '
        'plugin must not swallow values this build does understand', () {
      const Map<String, BookingStatus> expected = <String, BookingStatus>{
        'CONFIRMED': BookingStatus.confirmed,
        'COMPLETED': BookingStatus.completed,
        'DECLINED': BookingStatus.declined,
        'CANCELLED': BookingStatus.cancelled,
        'NOT_COMPLETED': BookingStatus.notCompleted,
      };
      for (final MapEntry<String, BookingStatus> e in expected.entries) {
        final AppointmentDetailResponse dto = _decode(
          _visitJson(status: e.key),
        );
        expect(dto.status?.name, e.key);
        expect(AppointmentMapper.fromDto(dto).status, e.value);
      }
    });
  });

  group('unrecognised ITEM status at the wire seam', () {
    test('an unrecognised status on ONE line item does not take the whole '
        'visit down', () {
      // The item's status is nested INSIDE the visit's payload, so its enum
      // serializer would abort the parent's deserialization — even though
      // `AppointmentItem` has no `status` field and the value is discarded
      // immediately after. That is why `AppointmentItemResponse` needs its own
      // row in `kBeauticaToleratedEnums` despite having no mapper work.
      final AppointmentDetailResponse dto = _decode(
        _visitJson(
          status: 'CONFIRMED',
          items: <Map<String, dynamic>>[
            _itemJson(bookingId: 'booking-1', status: 'CONFIRMED'),
            _itemJson(bookingId: 'booking-2', status: 'PARTIALLY_REFUNDED'),
          ],
        ),
      );

      expect(dto.items, hasLength(2));
      expect(dto.items?[0].status?.name, 'CONFIRMED');
      expect(dto.items?[1].status, isNull);

      final Appointment visit = AppointmentMapper.fromDto(dto);
      // The VISIT status is untouched — stripping an item's status must not
      // leak into the header.
      expect(visit.status, BookingStatus.confirmed);
      expect(visit.items, hasLength(2));
      expect(
        visit.items.map((AppointmentItem i) => i.bookingId).toList(),
        <String>['booking-1', 'booking-2'],
      );
    });
  });

  group('the tolerance is scoped, not blanket', () {
    test('the UNTOLERATED generated serializers still throw for BOTH '
        'appointment DTOs — proving the tolerance comes from the plugin and '
        'not from built_value', () {
      expect(
        () => standardSerializers.deserialize(
          _visitJson(status: 'RESCHEDULED'),
          specifiedType: const FullType(AppointmentDetailResponse),
        ),
        throwsA(
          isA<DeserializationError>().having(
            (DeserializationError e) => e.toString(),
            'toString()',
            allOf(
              contains('RESCHEDULED'),
              contains('AppointmentDetailResponseStatusEnum'),
            ),
          ),
        ),
      );

      expect(
        () => standardSerializers.deserialize(
          _visitJson(
            status: 'CONFIRMED',
            items: <Map<String, dynamic>>[
              _itemJson(bookingId: 'booking-1', status: 'PARTIALLY_REFUNDED'),
            ],
          ),
          specifiedType: const FullType(AppointmentDetailResponse),
        ),
        throwsA(
          isA<DeserializationError>().having(
            (DeserializationError e) => e.toString(),
            'toString()',
            allOf(
              contains('PARTIALLY_REFUNDED'),
              contains('AppointmentItemResponseStatusEnum'),
            ),
          ),
        ),
      );
    });

    test('a field NOT in the tolerance table still throws — masterType is '
        'deliberately untolerated, so this pins the table down as the whole '
        'contract rather than an approximation of it', () {
      // If someone widens the plugin to strip any unrecognised enum anywhere,
      // this test goes red — which is the point. Widening is a decision, not
      // an implementation detail.
      final Map<String, dynamic> json = _visitJson(status: 'CONFIRMED');
      json['masterType'] = 'FRANCHISE_MASTER';
      expect(
        () => beauticaSerializers.deserialize(
          json,
          specifiedType: const FullType(AppointmentDetailResponse),
        ),
        throwsA(isA<DeserializationError>()),
      );
    });
  });

  group('a genuinely broken contract still fails', () {
    test('a visit missing id/startsAt/endsAt is STILL a ServerFailure — '
        'relaxing the status guard must not have relaxed the others', () {
      final Map<String, dynamic> json = _visitJson(status: 'CONFIRMED');
      json.remove('startsAt');
      final AppointmentDetailResponse dto = _decode(json);
      expect(
        () => AppointmentMapper.fromDto(dto),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}
