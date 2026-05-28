//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'avatar_response.g.dart';

/// AvatarResponse
///
/// Properties:
/// * [avatarUrl]
@BuiltValue()
abstract class AvatarResponse
    implements Built<AvatarResponse, AvatarResponseBuilder> {
  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  AvatarResponse._();

  factory AvatarResponse([void updates(AvatarResponseBuilder b)]) =
      _$AvatarResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AvatarResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AvatarResponse> get serializer =>
      _$AvatarResponseSerializer();
}

class _$AvatarResponseSerializer
    implements PrimitiveSerializer<AvatarResponse> {
  @override
  final Iterable<Type> types = const [AvatarResponse, _$AvatarResponse];

  @override
  final String wireName = r'AvatarResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AvatarResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AvatarResponse object, {
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
    required AvatarResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AvatarResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AvatarResponseBuilder();
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
