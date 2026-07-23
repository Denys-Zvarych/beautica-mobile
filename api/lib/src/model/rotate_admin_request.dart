//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rotate_admin_request.g.dart';

/// RotateAdminRequest
///
/// Properties:
/// * [destinationSalonId]
@BuiltValue()
abstract class RotateAdminRequest
    implements Built<RotateAdminRequest, RotateAdminRequestBuilder> {
  @BuiltValueField(wireName: r'destinationSalonId')
  String get destinationSalonId;

  RotateAdminRequest._();

  factory RotateAdminRequest([void updates(RotateAdminRequestBuilder b)]) =
      _$RotateAdminRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RotateAdminRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RotateAdminRequest> get serializer =>
      _$RotateAdminRequestSerializer();
}

class _$RotateAdminRequestSerializer
    implements PrimitiveSerializer<RotateAdminRequest> {
  @override
  final Iterable<Type> types = const [RotateAdminRequest, _$RotateAdminRequest];

  @override
  final String wireName = r'RotateAdminRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RotateAdminRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'destinationSalonId';
    yield serializers.serialize(
      object.destinationSalonId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RotateAdminRequest object, {
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
    required RotateAdminRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'destinationSalonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.destinationSalonId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RotateAdminRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RotateAdminRequestBuilder();
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
