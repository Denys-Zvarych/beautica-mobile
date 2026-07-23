//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rotate_master_request.g.dart';

/// RotateMasterRequest
///
/// Properties:
/// * [destinationSalonId]
@BuiltValue()
abstract class RotateMasterRequest
    implements Built<RotateMasterRequest, RotateMasterRequestBuilder> {
  @BuiltValueField(wireName: r'destinationSalonId')
  String get destinationSalonId;

  RotateMasterRequest._();

  factory RotateMasterRequest([void updates(RotateMasterRequestBuilder b)]) =
      _$RotateMasterRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RotateMasterRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RotateMasterRequest> get serializer =>
      _$RotateMasterRequestSerializer();
}

class _$RotateMasterRequestSerializer
    implements PrimitiveSerializer<RotateMasterRequest> {
  @override
  final Iterable<Type> types = const [
    RotateMasterRequest,
    _$RotateMasterRequest
  ];

  @override
  final String wireName = r'RotateMasterRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RotateMasterRequest object, {
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
    RotateMasterRequest object, {
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
    required RotateMasterRequestBuilder result,
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
  RotateMasterRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RotateMasterRequestBuilder();
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
