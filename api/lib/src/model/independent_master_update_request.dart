//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'independent_master_update_request.g.dart';

/// IndependentMasterUpdateRequest
///
/// Properties:
/// * [cityId]
/// * [districtId]
/// * [street]
/// * [buildingNo]
/// * [locationNote]
@BuiltValue()
abstract class IndependentMasterUpdateRequest
    implements
        Built<IndependentMasterUpdateRequest,
            IndependentMasterUpdateRequestBuilder> {
  @BuiltValueField(wireName: r'cityId')
  String get cityId;

  @BuiltValueField(wireName: r'districtId')
  String? get districtId;

  @BuiltValueField(wireName: r'street')
  String? get street;

  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  IndependentMasterUpdateRequest._();

  factory IndependentMasterUpdateRequest(
          [void updates(IndependentMasterUpdateRequestBuilder b)]) =
      _$IndependentMasterUpdateRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(IndependentMasterUpdateRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<IndependentMasterUpdateRequest> get serializer =>
      _$IndependentMasterUpdateRequestSerializer();
}

class _$IndependentMasterUpdateRequestSerializer
    implements PrimitiveSerializer<IndependentMasterUpdateRequest> {
  @override
  final Iterable<Type> types = const [
    IndependentMasterUpdateRequest,
    _$IndependentMasterUpdateRequest
  ];

  @override
  final String wireName = r'IndependentMasterUpdateRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    IndependentMasterUpdateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'cityId';
    yield serializers.serialize(
      object.cityId,
      specifiedType: const FullType(String),
    );
    if (object.districtId != null) {
      yield r'districtId';
      yield serializers.serialize(
        object.districtId,
        specifiedType: const FullType(String),
      );
    }
    if (object.street != null) {
      yield r'street';
      yield serializers.serialize(
        object.street,
        specifiedType: const FullType(String),
      );
    }
    if (object.buildingNo != null) {
      yield r'buildingNo';
      yield serializers.serialize(
        object.buildingNo,
        specifiedType: const FullType(String),
      );
    }
    if (object.locationNote != null) {
      yield r'locationNote';
      yield serializers.serialize(
        object.locationNote,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    IndependentMasterUpdateRequest object, {
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
    required IndependentMasterUpdateRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cityId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cityId = valueDes;
          break;
        case r'districtId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.districtId = valueDes;
          break;
        case r'street':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.street = valueDes;
          break;
        case r'buildingNo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.buildingNo = valueDes;
          break;
        case r'locationNote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.locationNote = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  IndependentMasterUpdateRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = IndependentMasterUpdateRequestBuilder();
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
