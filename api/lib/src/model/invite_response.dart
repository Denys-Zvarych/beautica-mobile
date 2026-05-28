//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'invite_response.g.dart';

/// InviteResponse
///
/// Properties:
/// * [invitedEmail]
/// * [expiresAt]
@BuiltValue()
abstract class InviteResponse
    implements Built<InviteResponse, InviteResponseBuilder> {
  @BuiltValueField(wireName: r'invitedEmail')
  String? get invitedEmail;

  @BuiltValueField(wireName: r'expiresAt')
  DateTime? get expiresAt;

  InviteResponse._();

  factory InviteResponse([void updates(InviteResponseBuilder b)]) =
      _$InviteResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InviteResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InviteResponse> get serializer =>
      _$InviteResponseSerializer();
}

class _$InviteResponseSerializer
    implements PrimitiveSerializer<InviteResponse> {
  @override
  final Iterable<Type> types = const [InviteResponse, _$InviteResponse];

  @override
  final String wireName = r'InviteResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InviteResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.invitedEmail != null) {
      yield r'invitedEmail';
      yield serializers.serialize(
        object.invitedEmail,
        specifiedType: const FullType(String),
      );
    }
    if (object.expiresAt != null) {
      yield r'expiresAt';
      yield serializers.serialize(
        object.expiresAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InviteResponse object, {
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
    required InviteResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'invitedEmail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.invitedEmail = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InviteResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InviteResponseBuilder();
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
