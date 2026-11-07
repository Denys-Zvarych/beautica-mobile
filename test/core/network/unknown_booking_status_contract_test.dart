// Phase 438 D7 — a backend status / role value this build predates must
// decode and map to a SAFE domain value, never throw.
//
// Decodes REAL JSON through the generated `standardSerializers` (the raw
// `enumUnknownDefaultCase=true` fallback — the property
// `regenerate_api.sh --check` now pins) AND through the app's
// `beauticaSerializers` (fallback + `UnknownEnumTolerancePlugin`), then runs
// the production mappers:
//   - BookingDetailResponse.status  → BookingStatus.unknown
//   - AppointmentDetailResponse (visit + nested AppointmentItemResponse
//     status)                       → Appointment.status unknown, item kept
//   - SalonStaffMemberResponse.role → SalonStaffRole.master (least privilege)
//
// Mutation-checked: making the generated BookingDetailResponseStatusEnum
// `valueOf` throw on an unknown name (i.e. dropping `fallback: true`) turns
// the `standardSerializers` BookingDetailResponse case RED.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/network/api_enum_names.dart';
import 'package:beautica_mobile/core/network/beautica_serializers.dart';
import 'package:beautica_mobile/features/booking/data/appointment_mapper.dart';
import 'package:beautica_mobile/features/booking/data/booking_mapper.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/salon/data/salon_mapper.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:built_value/serializer.dart';
import 'package:flutter_test/flutter_test.dart';

const String _future = 'FUTURE_VALUE';

T _decode<T>(Serializers s, Serializer<T> serializer, Map<String, Object?> j) =>
    s.deserializeWith(serializer, j) as T;

Map<String, Object?> _bookingJson() => <String, Object?>{
  'id': 'b-1',
  'status': _future,
  'startsAt': '2026-11-10T10:00:00.000Z',
  'endsAt': '2026-11-10T11:00:00.000Z',
};

Map<String, Object?> _visitJson() => <String, Object?>{
  'id': 'a-1',
  'status': _future,
  'startsAt': '2026-11-10T10:00:00.000Z',
  'endsAt': '2026-11-10T11:00:00.000Z',
  'items': <Object?>[
    <String, Object?>{
      'bookingId': 'b-1',
      'masterServiceId': 'ms-1',
      'startsAt': '2026-11-10T10:00:00.000Z',
      'endsAt': '2026-11-10T11:00:00.000Z',
      'status': _future,
    },
  ],
};

Map<String, Object?> _staffJson() => <String, Object?>{
  'userId': 'u-1',
  'firstName': 'Олена',
  'lastName': 'Ковальчук',
  'role': _future,
};

void main() {
  final Map<String, Serializers> serializers = <String, Serializers>{
    'standardSerializers': standardSerializers,
    'beauticaSerializers': beauticaSerializers,
  };

  for (final MapEntry<String, Serializers> s in serializers.entries) {
    group('${s.key}: unknown wire value "$_future"', () {
      test('BookingDetailResponse.status decodes and maps to '
          'BookingStatus.unknown', () {
        late final BookingDetailResponse dto;
        expect(
          () => dto = _decode(
            s.value,
            BookingDetailResponse.serializer,
            _bookingJson(),
          ),
          returnsNormally,
        );
        final BookingDetailResponseStatusEnum? status = dto.status;
        expect(status == null || isOpenApiUnknownDefault(status), isTrue);

        final Booking booking = BookingMapper.fromDto(dto);
        expect(booking.status, BookingStatus.unknown);
      });

      test('AppointmentDetailResponse (visit + item status) decodes; the '
          'visit maps to unknown and the item is kept', () {
        late final AppointmentDetailResponse dto;
        expect(
          () => dto = _decode(
            s.value,
            AppointmentDetailResponse.serializer,
            _visitJson(),
          ),
          returnsNormally,
        );
        final AppointmentItemResponseStatusEnum? itemStatus =
            dto.items?.single.status;
        expect(
          itemStatus == null || isOpenApiUnknownDefault(itemStatus),
          isTrue,
        );

        final Appointment visit = AppointmentMapper.fromDto(dto);
        expect(visit.status, BookingStatus.unknown);
        expect(visit.items.single.bookingId, 'b-1');
      });

      test('SalonStaffMemberResponse.role decodes and maps to the '
          'least-privileged role', () {
        late final SalonStaffMemberResponse dto;
        expect(
          () => dto = _decode(
            s.value,
            SalonStaffMemberResponse.serializer,
            _staffJson(),
          ),
          returnsNormally,
        );
        final List<SalonStaffMember> roster =
            SalonStaffMemberMapper.fromDtoList(<SalonStaffMemberResponse>[dto]);
        expect(roster.single.role, SalonStaffRole.master);
      });
    });
  }
}
