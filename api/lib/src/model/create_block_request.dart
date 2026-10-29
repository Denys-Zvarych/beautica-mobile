//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_block_request.g.dart';

/// CreateBlockRequest
///
/// Properties:
/// * [bookingId]
@BuiltValue()
abstract class CreateBlockRequest
    implements Built<CreateBlockRequest, CreateBlockRequestBuilder> {
  @BuiltValueField(wireName: r'bookingId')
  String get bookingId;

  CreateBlockRequest._();

  factory CreateBlockRequest([void updates(CreateBlockRequestBuilder b)]) =
      _$CreateBlockRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateBlockRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateBlockRequest> get serializer =>
      _$CreateBlockRequestSerializer();
}

class _$CreateBlockRequestSerializer
    implements PrimitiveSerializer<CreateBlockRequest> {
  @override
  final Iterable<Type> types = const [CreateBlockRequest, _$CreateBlockRequest];

  @override
  final String wireName = r'CreateBlockRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateBlockRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'bookingId';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateBlockRequest object, {
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
    required CreateBlockRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'bookingId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateBlockRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateBlockRequestBuilder();
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
