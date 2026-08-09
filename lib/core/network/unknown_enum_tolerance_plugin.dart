// Phase 7.1 (completion) — wire-layer tolerance for backend enum values this
// build does not know about.
//
// THE DEFECT THIS EXISTS FOR
// --------------------------
// `BookingStatus.fromWire` (`features/booking/domain/booking_status.dart`) and
// `BookingMapper.fromDto`'s "an unrecognised status decodes to
// BookingStatus.unknown" contract were BOTH unreachable on the real wire path.
// The generated DTO enum is a built_value `EnumClass` with exactly the five
// members the committed OpenAPI snapshot declares and NO unknown fallback, so
// `standardSerializers.deserialize` throws `ArgumentError` on any other wire
// value — inside the generated client, BEFORE the domain mapper is ever
// called. Proven at the API seam:
//
//   [probe] status=RESCHEDULED  outcome=THREW DioException [unknown]:
//     Deserializing to 'BookingDetailResponseStatusEnum' failed due to:
//     Invalid argument(s): RESCHEDULED
//
// The blast radius was NOT a nice error screen. The repository maps that
// `DioException` to a `Failure`, which is neither an `Error` nor a
// `ProviderException`, so Riverpod 3's `defaultRetry` retried ~10 times over
// ~38s with the element stuck in `AsyncLoading` — an indefinite spinner on the
// booking detail. And because `getMyBookings` deserializes the WHOLE page
// envelope in one call, a single unknown-status row blanked the entire «Мої
// записи» page (`BookingMapper.fromDtoList`'s `on Failure { continue; }`
// resilience loop never got to run — the throw happened one layer below it).
//
// WHY THE FIX LIVES HERE AND NOT IN `api/`
// ----------------------------------------
// `api/` is generated from the committed OpenAPI snapshot and is clobbered by
// every `regenerate_api.sh` run, so the tolerance cannot be a hand-edit there.
// It also cannot be a custom `Serializer<BookingDetailResponseStatusEnum>`:
// `EnumClass` members are const-interned instances created by the generated
// `_$…` file through a PRIVATE constructor, so no sixth "UNKNOWN" member can
// be minted from outside that library — a replacement serializer would have
// nothing legal to return.
//
// What it CAN do is stop the value from reaching the enum serializer at all.
// This plugin runs during `beforeDeserialize` and STRIPS an unrecognised enum
// value out of the DTO payload, so the field deserializes as ABSENT rather
// than throwing. The domain mapper then reads `dto.status == null` and decodes
// it to `BookingStatus.unknown` — keep-and-deny, exactly the doctrine
// `booking_status.dart` already argues for (`unknown` keeps the row visible
// while granting none of `confirmed`'s capabilities, notably the purely-local
// `canAddToCalendar`).
//
// The cost of this shape is that the mapper no longer sees the raw wire
// string; that diagnostic is emitted HERE instead, once per offending field.
//
// SCOPE
// -----
// [kBeauticaToleratedEnums] covers the three status enums that share this
// defect: `BookingDetailResponse.status`, `AppointmentDetailResponse.status`
// and `AppointmentItemResponse.status`.
//
// ⚠ A ROW HERE IS HALF A FIX. Stripping the field only moves the problem from
// "the serializer throws" to "the mapper sees null" — so every row must be
// paired with a mapper that treats a null as the domain's unknown/read-only
// state, or a graceful degrade becomes a hard `ServerFailure`, which is
// strictly WORSE than the throw it replaced. The pairing today:
//
//   BookingDetailResponse.status     → `booking_mapper.dart` (null → unknown)
//   AppointmentDetailResponse.status → `appointment_mapper.dart` (null →
//                                       unknown)
//   AppointmentItemResponse.status   → nothing to pair. `AppointmentItem` has
//                                       no `status` field and
//                                       `AppointmentItemMapper` never reads
//                                       it; the row exists purely because an
//                                       item's enum serializer would abort the
//                                       PARENT visit's deserialization. See
//                                       that mapper's doc.
//
// Adding a fourth row means doing the mapper half first. The api class holding
// the DTO must also be built on [beauticaSerializers] rather than the
// generated `standardSerializers` (see `beautica_serializers.dart`) — a row
// here is inert for any api class that was never migrated.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:flutter/foundation.dart';

/// Which `(DTO type → field → known wire values)` triples are tolerated.
///
/// The value sets are derived from the GENERATED enum's own members, so a
/// regen that adds a backend status automatically stops stripping it. The
/// derivation uses `EnumClass.name`, which equals the emitted wire value for
/// every member of these enums (each is annotated
/// `@BuiltValueEnumConst(wireName: r'<SAME NAME>')`). If a future spec ever
/// introduces a member whose `wireName` diverges from its Dart name, the worst
/// case is that ONE member gets stripped and rendered as `unknown` — the
/// fail-safe direction, never a throw.
///
/// Deeply unmodifiable. It is public so tests can assert its contents and so
/// `beautica_serializers.dart` can pass it in, but it is process-wide
/// configuration read on every deserialize — a stray write from anywhere in
/// the app (or from one test, leaking into the next in the same VM) would
/// silently change decode behaviour everywhere. The `Set`s are sealed too, not
/// just the outer map: sealing only the outer level still leaves
/// `kBeauticaToleratedEnums[X]!['status']!.add(...)` wide open.
final Map<Type, Map<String, Set<String>>> kBeauticaToleratedEnums =
    Map<Type, Map<String, Set<String>>>.unmodifiable(
      <Type, Map<String, Set<String>>>{
        BookingDetailResponse: _wireValuesOf(
          BookingDetailResponseStatusEnum.values,
        ),
        AppointmentDetailResponse: _wireValuesOf(
          AppointmentDetailResponseStatusEnum.values,
        ),
        AppointmentItemResponse: _wireValuesOf(
          AppointmentItemResponseStatusEnum.values,
        ),
      },
    );

/// Builds a sealed `{'status': {…known wire values…}}` entry from a generated
/// enum's own members.
///
/// Every tolerated field is named `status` today; this helper exists so that
/// stays a single literal rather than three, and so the unmodifiable wrapping
/// cannot be forgotten on a future row.
Map<String, Set<String>> _wireValuesOf(Iterable<EnumClass> members) =>
    Map<String, Set<String>>.unmodifiable(<String, Set<String>>{
      'status': Set<String>.unmodifiable(
        members.map((EnumClass v) => v.name).toSet(),
      ),
    });

/// Strips unrecognised enum wire values out of a built_value payload during
/// `beforeDeserialize`, so the offending field deserializes as absent instead
/// of throwing `ArgumentError` out of the enum serializer.
///
/// Register it on the app's [Serializers] (see `beautica_serializers.dart`),
/// never on the generated `standardSerializers` in place.
@immutable
class UnknownEnumTolerancePlugin implements SerializerPlugin {
  const UnknownEnumTolerancePlugin(this.tolerated);

  /// `DTO type → field name → the wire values this build understands`.
  final Map<Type, Map<String, Set<String>>> tolerated;

  static const String _tag = 'core.network.enum_tolerance';

  @override
  Object? beforeDeserialize(Object? object, FullType specifiedType) {
    final Map<String, Set<String>>? fields = tolerated[specifiedType.root];
    if (fields == null) return object;
    // Both shapes are handled so this plugin is INDEPENDENT of its position
    // relative to `StandardJsonPlugin`. built_value runs plugins in
    // registration order (`built_json_serializers.dart`), and
    // `StandardJsonPlugin.beforeDeserialize` rewrites a JSON `Map` into
    // built_value's flat `[key, value, key, value, …]` list — so appended
    // after it (the normal case) this sees the List, and prepended it would
    // see the Map. Neither ordering may silently disable the tolerance.
    if (object is List) return _sanitizeFlatList(object, fields);
    if (object is Map) return _sanitizeMap(object, fields);
    return object;
  }

  @override
  Object? afterDeserialize(Object? object, FullType specifiedType) => object;

  @override
  Object? beforeSerialize(Object? object, FullType specifiedType) => object;

  @override
  Object? afterSerialize(Object? object, FullType specifiedType) => object;

  /// built_value's flat `[key, value, key, value, …]` wire form. Drops BOTH
  /// entries of an offending pair. Returns the ORIGINAL list untouched when
  /// nothing is stripped — this runs once per row of every bookings page, so
  /// the common path must not allocate.
  List<Object?> _sanitizeFlatList(
    List<Object?> serialized,
    Map<String, Set<String>> fields,
  ) {
    List<Object?>? sanitized;
    for (int i = 0; i + 1 < serialized.length; i += 2) {
      final Object? key = serialized[i];
      if (key is! String) continue;
      final Set<String>? known = fields[key];
      if (known == null) continue;
      final Object? value = serialized[i + 1];
      if (value is! String || known.contains(value)) continue;
      _logStripped(key, value);
      sanitized ??= List<Object?>.of(serialized);
      // Mark the pair; compacted in one pass below so indices stay valid.
      sanitized[i] = _stripped;
      sanitized[i + 1] = _stripped;
    }
    if (sanitized == null) return serialized;
    return sanitized
        .where((Object? e) => !identical(e, _stripped))
        .toList(growable: false);
  }

  /// The raw JSON `Map` form (this plugin registered BEFORE
  /// `StandardJsonPlugin`). Same contract: original map back when nothing is
  /// stripped.
  ///
  /// UNREACHABLE IN PRODUCTION AS WIRED TODAY, ON PURPOSE.
  /// `beautica_serializers.dart` appends this plugin, so `StandardJsonPlugin`
  /// always runs first and this branch only ever sees the flat list — which is
  /// exactly the fragility it defends against. Order there is a one-token
  /// change (`addPlugin` position) with a SILENT failure mode: without this
  /// branch, prepending would hand `beforeDeserialize` a `Map` it does not
  /// recognise, the tolerance would quietly stop applying, and the enum
  /// serializer would start throwing again — with no test failing, because
  /// every wire test drives the appended arrangement. Kept and covered
  /// directly by `unknown_enum_tolerance_plugin_test.dart`, which builds a
  /// PREPENDED `Serializers` and asserts the tolerance still holds, so the
  /// branch is neither dead nor unverified.
  Map<Object?, Object?> _sanitizeMap(
    Map<Object?, Object?> serialized,
    Map<String, Set<String>> fields,
  ) {
    Map<Object?, Object?>? sanitized;
    for (final MapEntry<String, Set<String>> field in fields.entries) {
      if (!serialized.containsKey(field.key)) continue;
      final Object? value = serialized[field.key];
      if (value is! String || field.value.contains(value)) continue;
      _logStripped(field.key, value);
      sanitized ??= Map<Object?, Object?>.of(serialized);
      sanitized.remove(field.key);
    }
    return sanitized ?? serialized;
  }

  void _logStripped(String field, String value) {
    // kDebugMode-gated to match every sibling log on this path
    // (`booking_mapper.dart`, `booking_repository.dart`, `BookingStatus
    // ._unknown`) — an ungated version would emit one line per row, i.e. 20
    // identical release logs for a single bookings page.
    if (kDebugMode) {
      log(
        'Unrecognised wire value "$value" for enum field "$field" — stripped '
        'so the DTO deserializes with it absent. The backend enum has likely '
        'gained a member; regenerate the OpenAPI client.',
        name: _tag,
        level: 900,
      );
    }
  }

  /// Private sentinel marking a flat-list slot for removal. A plain `null`
  /// would be ambiguous — `null` is a legitimate serialized VALUE.
  static const Object _stripped = Object();
}
