//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_telegram_link_response.g.dart';

/// GuestTelegramLinkResponse
///
/// Properties:
/// * [url]
/// * [expiresAt]
/// * [alreadyLinked]
@BuiltValue()
abstract class GuestTelegramLinkResponse
    implements
        Built<GuestTelegramLinkResponse, GuestTelegramLinkResponseBuilder> {
  @BuiltValueField(wireName: r'url')
  String? get url;

  @BuiltValueField(wireName: r'expiresAt')
  DateTime? get expiresAt;

  @BuiltValueField(wireName: r'alreadyLinked')
  bool? get alreadyLinked;

  GuestTelegramLinkResponse._();

  factory GuestTelegramLinkResponse(
          [void updates(GuestTelegramLinkResponseBuilder b)]) =
      _$GuestTelegramLinkResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestTelegramLinkResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestTelegramLinkResponse> get serializer =>
      _$GuestTelegramLinkResponseSerializer();
}

class _$GuestTelegramLinkResponseSerializer
    implements PrimitiveSerializer<GuestTelegramLinkResponse> {
  @override
  final Iterable<Type> types = const [
    GuestTelegramLinkResponse,
    _$GuestTelegramLinkResponse
  ];

  @override
  final String wireName = r'GuestTelegramLinkResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestTelegramLinkResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.url != null) {
      yield r'url';
      yield serializers.serialize(
        object.url,
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
    if (object.alreadyLinked != null) {
      yield r'alreadyLinked';
      yield serializers.serialize(
        object.alreadyLinked,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestTelegramLinkResponse object, {
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
    required GuestTelegramLinkResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'expiresAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.expiresAt = valueDes;
          break;
        case r'alreadyLinked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.alreadyLinked = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestTelegramLinkResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestTelegramLinkResponseBuilder();
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
