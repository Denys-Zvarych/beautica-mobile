// Phase 7.1 (completion) — the WIRE-LAYER proof that an unrecognised backend
// booking status survives deserialization as [BookingStatus.unknown].
//
// WHY THIS FILE EXISTS (and why `booking_mapper_test.dart` was not enough)
// ---------------------------------------------------------------------------
// `booking_mapper_test.dart` proves `BookingMapper.fromDto` degrades an unknown
// status gracefully — by handing it a DTO it BUILT ITSELF. That can never fail,
// because a `BookingDetailResponse` built in Dart can only ever carry one of the
// five `BookingDetailResponseStatusEnum` members. The DTO type is the exact
// layer where the real defect lived: `standardSerializers` threw `ArgumentError`
// out of the generated enum serializer on any sixth wire value, one layer BELOW
// the mapper, so `BookingStatus.unknown` and `fromDtoList`'s resilience loop
// were unreachable dead code on every real response.
//
// So these tests start from JSON — the thing the socket actually delivers —
// and drive it through the SAME [beauticaSerializers] the production
// `bookingApiProvider` and `HttpBookingRepository._deserialize` use. A
// regression that drops the tolerance plugin fails here even though the mapper
// suite stays green.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/network/beautica_serializers.dart';
import 'package:beautica_mobile/features/booking/data/booking_mapper.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:built_value/serializer.dart';
import 'package:flutter_test/flutter_test.dart';

/// One `BookingDetailResponse` row exactly as the backend renders it, with
/// [status] injectable so a test can supply a value this build predates.
Map<String, dynamic> _rowJson({
  required String id,
  required String status,
}) => <String, dynamic>{
  'id': id,
  'masterId': 'master-aaa',
  'masterFirstName': 'Софія',
  'masterLastName': 'Бондар',
  'masterType': 'INDEPENDENT_MASTER',
  'masterServiceId': 'pub-assign-1',
  'serviceName': 'Манікюр з покриттям',
  'categoryName': 'NAIL_SERVICE',
  'durationMinutesAtBooking': 90,
  'priceAtBooking': 500,
  'priceMaxAtBooking': null,
  // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
  'startsAt': '2026-08-14T10:00:00',
  // future-date-ok: pinned deserialization INPUT — the fixed wire string IS the assertion; the mapper under test never reads the wall clock.
  'endsAt': '2026-08-14T11:30:00',
  'status': status,
  'canReview': false,
};

void main() {
  group('unrecognised booking status at the wire seam', () {
    test('a status this build does not know decodes to BookingStatus.unknown '
        'instead of throwing out of the generated enum serializer', () {
      // `RESCHEDULED` is not one of the five members the committed OpenAPI
      // snapshot declares. Before the tolerance plugin this line threw:
      //   Deserializing to 'BookingDetailResponseStatusEnum' failed due to:
      //   Invalid argument(s): RESCHEDULED
      final BookingDetailResponse? dto =
          beauticaSerializers.deserialize(
                _rowJson(id: 'booking-1', status: 'RESCHEDULED'),
                specifiedType: const FullType(BookingDetailResponse),
              )
              as BookingDetailResponse?;

      expect(dto, isNotNull, reason: 'the row must still deserialize');
      expect(
        dto?.status,
        isNull,
        reason:
            'the unrecognised value is STRIPPED, because the generated '
            'EnumClass has no member that could represent it',
      );

      final Booking booking = BookingMapper.fromDto(dto!);
      expect(
        booking.status,
        BookingStatus.unknown,
        reason: 'the stripped status must surface as unknown, not an error',
      );
      // Keep-and-deny: the row is visible but grants nothing. Decoding to
      // `confirmed` would fail OPEN onto add-to-calendar + cancel/reschedule.
      expect(booking.id, 'booking-1');
      expect(booking.serviceName, 'Манікюр з покриттям');
    });

    test('every KNOWN status still decodes to its real member — the plugin '
        'must not swallow values this build does understand', () {
      const Map<String, BookingStatus> expected = <String, BookingStatus>{
        'CONFIRMED': BookingStatus.confirmed,
        'COMPLETED': BookingStatus.completed,
        'DECLINED': BookingStatus.declined,
        'CANCELLED': BookingStatus.cancelled,
        'NOT_COMPLETED': BookingStatus.notCompleted,
      };
      for (final MapEntry<String, BookingStatus> e in expected.entries) {
        final BookingDetailResponse dto =
            beauticaSerializers.deserialize(
                  _rowJson(id: 'b', status: e.key),
                  specifiedType: const FullType(BookingDetailResponse),
                )
                as BookingDetailResponse;
        expect(dto.status?.name, e.key);
        expect(BookingMapper.fromDto(dto).status, e.value);
      }
    });

    test('ONE unknown-status row in a page does not blank the whole page', () {
      // The collateral half of the same defect: `getMyBookings` used to
      // deserialize the WHOLE `ApiResponse<PageResponse<…>>` envelope in a
      // single call, so one bad row threw and «Мої записи» rendered empty.
      //
      // SCOPE — read this before extending the test: NO row here throws. With
      // the tolerance plugin installed an unrecognised status deserializes to
      // `unknown` and maps cleanly, so all three rows SURVIVE. What this test
      // pins is that an unknown status is KEPT (not dropped, not fatal) —
      // it does NOT exercise `fromDtoList`'s `on Failure { continue; }` skip
      // path, because nothing raises inside the loop.
      //
      // The skip path is owned by booking_mapper_test.dart's
      // 'a row that throws in the MIDDLE of the list is SKIPPED' test (a row
      // with an absent `id`, which really does throw ServerFailure during
      // mapping) and, end-to-end through the repository, by
      // booking_repository_test.dart's 'a row that DESERIALIZES but fails
      // MAPPING is skipped mid-page' test.
      final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[
        _rowJson(id: 'booking-1', status: 'CONFIRMED'),
        _rowJson(id: 'booking-2', status: 'RESCHEDULED'),
        _rowJson(id: 'booking-3', status: 'COMPLETED'),
      ];

      final List<BookingDetailResponse> dtos = rows
          .map(
            (Map<String, dynamic> r) =>
                beauticaSerializers.deserialize(
                      r,
                      specifiedType: const FullType(BookingDetailResponse),
                    )
                    as BookingDetailResponse,
          )
          .toList();

      final List<Booking> bookings = BookingMapper.fromDtoList(dtos);
      expect(bookings, hasLength(3));
      expect(bookings.map((Booking b) => b.status).toList(), <BookingStatus>[
        BookingStatus.confirmed,
        BookingStatus.unknown,
        BookingStatus.completed,
      ]);
    });

    test('the UNTOLERATED generated serializers still throw — proving the '
        'tolerance comes from the plugin and not from built_value', () {
      // Asserted PRECISELY, not `throwsA(anything)`. A bare `anything` cannot
      // tell "threw because of RESCHEDULED" from "threw for some unrelated
      // reason", so an incidental mutation to the shared [_rowJson] helper
      // (say `'startsAt': 'garbage'`) would keep this control GREEN while the
      // three real tests above went red — the control would silently stop
      // proving the thing it is named after, at exactly the moment its
      // evidence mattered.
      //
      // built_value wraps the enum serializer's `ArgumentError` in a
      // `DeserializationError` (`built_json_serializers.dart:142`), whose
      // `toString()` carries both the target type and the offending value.
      expect(
        () => standardSerializers.deserialize(
          _rowJson(id: 'booking-1', status: 'RESCHEDULED'),
          specifiedType: const FullType(BookingDetailResponse),
        ),
        throwsA(
          isA<DeserializationError>()
              .having(
                (DeserializationError e) => e.toString(),
                'toString()',
                contains('RESCHEDULED'),
              )
              .having(
                (DeserializationError e) => e.toString(),
                'toString()',
                contains('BookingDetailResponseStatusEnum'),
              ),
        ),
        reason:
            'if this ever stops throwing, the generated client gained its own '
            'unknown fallback and this whole plugin can be retired',
      );
    });
  });
}
