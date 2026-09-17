//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/effective_day_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_master_effective_schedule_response.g.dart';

/// SalonMasterEffectiveScheduleResponse
///
/// Properties:
/// * [masterId]
/// * [days]
@BuiltValue()
abstract class SalonMasterEffectiveScheduleResponse
    implements
        Built<SalonMasterEffectiveScheduleResponse,
            SalonMasterEffectiveScheduleResponseBuilder> {
  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'days')
  BuiltList<EffectiveDayResponse>? get days;

  SalonMasterEffectiveScheduleResponse._();

  factory SalonMasterEffectiveScheduleResponse(
          [void updates(SalonMasterEffectiveScheduleResponseBuilder b)]) =
      _$SalonMasterEffectiveScheduleResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonMasterEffectiveScheduleResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonMasterEffectiveScheduleResponse> get serializer =>
      _$SalonMasterEffectiveScheduleResponseSerializer();
}

class _$SalonMasterEffectiveScheduleResponseSerializer
    implements PrimitiveSerializer<SalonMasterEffectiveScheduleResponse> {
  @override
  final Iterable<Type> types = const [
    SalonMasterEffectiveScheduleResponse,
    _$SalonMasterEffectiveScheduleResponse
  ];

  @override
  final String wireName = r'SalonMasterEffectiveScheduleResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonMasterEffectiveScheduleResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.days != null) {
      yield r'days';
      yield serializers.serialize(
        object.days,
        specifiedType:
            const FullType(BuiltList, [FullType(EffectiveDayResponse)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonMasterEffectiveScheduleResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SalonMasterEffectiveScheduleResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'days':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(EffectiveDayResponse)]),
          ) as BuiltList<EffectiveDayResponse>;
          result.days.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonMasterEffectiveScheduleResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonMasterEffectiveScheduleResponseBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}
