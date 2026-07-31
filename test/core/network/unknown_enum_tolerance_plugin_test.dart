// Unit tests for [UnknownEnumTolerancePlugin] and [kBeauticaToleratedEnums].
//
// The feature-level wire tests (`booking_unknown_status_wire_test.dart`,
// `appointment_unknown_status_wire_test.dart`) exercise this plugin only
// through `beauticaSerializers`, which APPENDS it — so `StandardJsonPlugin`
// always runs first and the plugin only ever sees built_value's flat
// `[key, value, …]` list. This file covers the two things those tests
// structurally cannot:
//
//   1. The raw-`Map` branch (`_sanitizeMap`), reachable only when the plugin
//      is PREPENDED. Registration order is a one-token change in
//      `beautica_serializers.dart` with a SILENT failure mode: without that
//      branch, prepending would hand `beforeDeserialize` a `Map` it does not
//      recognise, the tolerance would quietly stop applying, and the enum
//      serializer would start throwing again — with no existing test failing.
//   2. The immutability of `kBeauticaToleratedEnums`, which is process-wide
//      configuration consulted on every deserialize.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/network/unknown_enum_tolerance_plugin.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mirror image of production's arrangement: the tolerance plugin
/// registered BEFORE `StandardJsonPlugin`, so it sees the raw JSON `Map`
/// rather than built_value's flat list.
///
/// Built from the generated `serializers` (the PLUGIN-FREE instance), not from
/// `standardSerializers` — the latter already carries a `StandardJsonPlugin`
/// and `SerializersBuilder.addPlugin` only ever appends, so there is no way to
/// get ahead of it starting from there. This mirrors
/// `serializers.dart:449-450`, with one extra plugin inserted first.
final Serializers _prependedSerializers =
    (serializers.toBuilder()
          ..addPlugin(UnknownEnumTolerancePlugin(kBeauticaToleratedEnums))
          ..addPlugin(StandardJsonPlugin()))
        .build();

Map<String, dynamic> _rowJson({required String status}) => <String, dynamic>{
  'id': 'booking-1',
  'masterId': 'master-aaa',
  'masterFirstName': 'Софія',
  'masterLastName': 'Бондар',
  'masterType': 'INDEPENDENT_MASTER',
  'masterServiceId': 'pub-assign-1',
  'serviceName': 'Манікюр з покриттям',
  'durationMinutesAtBooking': 90,
  'priceAtBooking': 500,
  'startsAt': '2026-08-14T10:00:00',
  'endsAt': '2026-08-14T11:30:00',
  'status': status,
  'canReview': false,
};

void main() {
  final UnknownEnumTolerancePlugin plugin = UnknownEnumTolerancePlugin(
    kBeauticaToleratedEnums,
  );
  const FullType bookingType = FullType(BookingDetailResponse);

  group('beforeDeserialize — raw Map form (plugin registered FIRST)', () {
    test('strips an unrecognised value out of a JSON map', () {
      final Object? out = plugin.beforeDeserialize(<String, Object?>{
        'id': 'booking-1',
        'status': 'RESCHEDULED',
      }, bookingType);

      expect(out, isA<Map<Object?, Object?>>());
      expect((out as Map<Object?, Object?>).containsKey('status'), isFalse);
      expect(out['id'], 'booking-1', reason: 'siblings must be untouched');
    });

    test('returns the ORIGINAL map instance when nothing is stripped — the '
        'common path must not allocate', () {
      final Map<String, Object?> input = <String, Object?>{
        'id': 'booking-1',
        'status': 'CONFIRMED',
      };
      expect(plugin.beforeDeserialize(input, bookingType), same(input));
    });

    test('a full deserialize through a PREPENDED registration still tolerates '
        'the unknown status — registration order is not load-bearing', () {
      final BookingDetailResponse dto =
          _prependedSerializers.deserialize(
                _rowJson(status: 'RESCHEDULED'),
                specifiedType: bookingType,
              )
              as BookingDetailResponse;
      expect(dto.status, isNull);
      expect(dto.id, 'booking-1');
    });

    test('the PREPENDED arrangement still decodes a known status normally', () {
      final BookingDetailResponse dto =
          _prependedSerializers.deserialize(
                _rowJson(status: 'COMPLETED'),
                specifiedType: bookingType,
              )
              as BookingDetailResponse;
      expect(dto.status, BookingDetailResponseStatusEnum.COMPLETED);
    });
  });

  group('beforeDeserialize — flat list form (production arrangement)', () {
    test('drops BOTH entries of the offending key/value pair', () {
      final Object? out = plugin.beforeDeserialize(<Object?>[
        'id',
        'booking-1',
        'status',
        'RESCHEDULED',
        'serviceName',
        'Манікюр',
      ], bookingType);

      expect(out, <Object?>['id', 'booking-1', 'serviceName', 'Манікюр']);
    });

    test('returns the ORIGINAL list instance when nothing is stripped', () {
      final List<Object?> input = <Object?>['status', 'CONFIRMED'];
      expect(plugin.beforeDeserialize(input, bookingType), same(input));
    });
  });

  group('scope', () {
    test('a type NOT in the table is passed through verbatim', () {
      final Map<String, Object?> input = <String, Object?>{
        'status': 'SOMETHING_ELSE',
      };
      expect(
        plugin.beforeDeserialize(input, const FullType(CityResponse)),
        same(input),
      );
    });

    test('the three status enums are registered, and their known-value sets '
        'are derived from the GENERATED members', () {
      expect(
        kBeauticaToleratedEnums.keys.toSet(),
        <Type>{
          BookingDetailResponse,
          AppointmentDetailResponse,
          AppointmentItemResponse,
        },
        reason:
            'every row here also needs its mapper to accept a null status — '
            'see the table doc before adding one',
      );
      expect(
        kBeauticaToleratedEnums[BookingDetailResponse]?['status'],
        BookingDetailResponseStatusEnum.values.map((v) => v.name).toSet(),
      );
      expect(
        kBeauticaToleratedEnums[AppointmentItemResponse]?['status'],
        AppointmentItemResponseStatusEnum.values.map((v) => v.name).toSet(),
      );
    });
  });

  group('kBeauticaToleratedEnums is deeply unmodifiable', () {
    test('the outer map rejects writes', () {
      expect(
        () => kBeauticaToleratedEnums[CityResponse] = <String, Set<String>>{},
        throwsUnsupportedError,
      );
    });

    test('the per-type field map rejects writes', () {
      expect(
        () => kBeauticaToleratedEnums[BookingDetailResponse]!['status'] =
            <String>{},
        throwsUnsupportedError,
      );
    });

    test('the known-value sets reject writes — sealing only the outer level '
        'would leave this wide open', () {
      expect(
        () => kBeauticaToleratedEnums[BookingDetailResponse]!['status']!.add(
          'RESCHEDULED',
        ),
        throwsUnsupportedError,
      );
    });
  });
}
