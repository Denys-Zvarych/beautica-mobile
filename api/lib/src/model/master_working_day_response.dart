//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'master_working_day_response.g.dart';

/// MasterWorkingDayResponse
///
/// Properties:
/// * [date]
/// * [working]
@BuiltValue()
abstract class MasterWorkingDayResponse
    implements
        Built<MasterWorkingDayResponse, MasterWorkingDayResponseBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'working')
  bool? get working;

  MasterWorkingDayResponse._();

  factory MasterWorkingDayResponse(
          [void updates(MasterWorkingDayResponseBuilder b)]) =
      _$MasterWorkingDayResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MasterWorkingDayResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MasterWorkingDayResponse> get serializer =>
      _$MasterWorkingDayResponseSerializer();
}

class _$MasterWorkingDayResponseSerializer
    implements PrimitiveSerializer<MasterWorkingDayResponse> {
  @override
  final Iterable<Type> types = const [
    MasterWorkingDayResponse,
    _$MasterWorkingDayResponse
  ];

  @override
  final String wireName = r'MasterWorkingDayResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MasterWorkingDayResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType(Date),
      );
    }
    if (object.working != null) {
      yield r'working';
      yield serializers.serialize(
        object.working,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MasterWorkingDayResponse object, {
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
    required MasterWorkingDayResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.date = valueDes;
          break;
        case r'working':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.working = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MasterWorkingDayResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MasterWorkingDayResponseBuilder();
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
