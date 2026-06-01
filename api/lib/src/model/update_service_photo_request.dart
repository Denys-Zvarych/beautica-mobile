//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_service_photo_request.g.dart';

/// UpdateServicePhotoRequest
///
/// Properties:
/// * [photoUrl]
@BuiltValue()
abstract class UpdateServicePhotoRequest
    implements
        Built<UpdateServicePhotoRequest, UpdateServicePhotoRequestBuilder> {
  @BuiltValueField(wireName: r'photoUrl')
  String get photoUrl;

  UpdateServicePhotoRequest._();

  factory UpdateServicePhotoRequest(
          [void updates(UpdateServicePhotoRequestBuilder b)]) =
      _$UpdateServicePhotoRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateServicePhotoRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateServicePhotoRequest> get serializer =>
      _$UpdateServicePhotoRequestSerializer();
}

class _$UpdateServicePhotoRequestSerializer
    implements PrimitiveSerializer<UpdateServicePhotoRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateServicePhotoRequest,
    _$UpdateServicePhotoRequest
  ];

  @override
  final String wireName = r'UpdateServicePhotoRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateServicePhotoRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'photoUrl';
    yield serializers.serialize(
      object.photoUrl,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateServicePhotoRequest object, {
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
    required UpdateServicePhotoRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'photoUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.photoUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateServicePhotoRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateServicePhotoRequestBuilder();
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
