//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_profile_request.g.dart';

/// UpdateProfileRequest
///
/// Properties:
/// * [firstName]
/// * [lastName]
/// * [phoneNumber]
/// * [cityId]
/// * [districtId]
/// * [street]
/// * [buildingNo]
/// * [locationNote]
@BuiltValue()
abstract class UpdateProfileRequest
    implements Built<UpdateProfileRequest, UpdateProfileRequestBuilder> {
  @BuiltValueField(wireName: r'firstName')
  String? get firstName;

  @BuiltValueField(wireName: r'lastName')
  String? get lastName;

  @BuiltValueField(wireName: r'phoneNumber')
  String? get phoneNumber;

  @BuiltValueField(wireName: r'cityId')
  String? get cityId;

  @BuiltValueField(wireName: r'districtId')
  String? get districtId;

  @BuiltValueField(wireName: r'street')
  String? get street;

  @BuiltValueField(wireName: r'buildingNo')
  String? get buildingNo;

  @BuiltValueField(wireName: r'locationNote')
  String? get locationNote;

  UpdateProfileRequest._();

  factory UpdateProfileRequest([void updates(UpdateProfileRequestBuilder b)]) =
      _$UpdateProfileRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateProfileRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateProfileRequest> get serializer =>
      _$UpdateProfileRequestSerializer();
}

class _$UpdateProfileRequestSerializer
    implements PrimitiveSerializer<UpdateProfileRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateProfileRequest,
    _$UpdateProfileRequest
  ];

  @override
  final String wireName = r'UpdateProfileRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateProfileRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.firstName != null) {
      yield r'firstName';
      yield serializers.serialize(
        object.firstName,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastName != null) {
      yield r'lastName';
      yield serializers.serialize(
        object.lastName,
        specifiedType: const FullType(String),
      );
    }
    if (object.phoneNumber != null) {
      yield r'phoneNumber';
      yield serializers.serialize(
        object.phoneNumber,
        specifiedType: const FullType(String),
      );
    }
    if (object.cityId != null) {
      yield r'cityId';
      yield serializers.serialize(
        object.cityId,
        specifiedType: const FullType(String),
      );
    }
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
    UpdateProfileRequest object, {
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
    required UpdateProfileRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'firstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.firstName = valueDes;
          break;
        case r'lastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastName = valueDes;
          break;
        case r'phoneNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phoneNumber = valueDes;
          break;
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
  UpdateProfileRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateProfileRequestBuilder();
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
