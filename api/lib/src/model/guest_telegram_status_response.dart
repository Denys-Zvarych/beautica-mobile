//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_telegram_status_response.g.dart';

/// GuestTelegramStatusResponse
///
/// Properties:
/// * [available]
/// * [linked]
/// * [offerChoice]
@BuiltValue()
abstract class GuestTelegramStatusResponse
    implements
        Built<GuestTelegramStatusResponse, GuestTelegramStatusResponseBuilder> {
  @BuiltValueField(wireName: r'available')
  bool? get available;

  @BuiltValueField(wireName: r'linked')
  bool? get linked;

  @BuiltValueField(wireName: r'offerChoice')
  bool? get offerChoice;

  GuestTelegramStatusResponse._();

  factory GuestTelegramStatusResponse(
          [void updates(GuestTelegramStatusResponseBuilder b)]) =
      _$GuestTelegramStatusResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestTelegramStatusResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestTelegramStatusResponse> get serializer =>
      _$GuestTelegramStatusResponseSerializer();
}

class _$GuestTelegramStatusResponseSerializer
    implements PrimitiveSerializer<GuestTelegramStatusResponse> {
  @override
  final Iterable<Type> types = const [
    GuestTelegramStatusResponse,
    _$GuestTelegramStatusResponse
  ];

  @override
  final String wireName = r'GuestTelegramStatusResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestTelegramStatusResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.available != null) {
      yield r'available';
      yield serializers.serialize(
        object.available,
        specifiedType: const FullType(bool),
      );
    }
    if (object.linked != null) {
      yield r'linked';
      yield serializers.serialize(
        object.linked,
        specifiedType: const FullType(bool),
      );
    }
    if (object.offerChoice != null) {
      yield r'offerChoice';
      yield serializers.serialize(
        object.offerChoice,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestTelegramStatusResponse object, {
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
    required GuestTelegramStatusResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'available':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.available = valueDes;
          break;
        case r'linked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.linked = valueDes;
          break;
        case r'offerChoice':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.offerChoice = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestTelegramStatusResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestTelegramStatusResponseBuilder();
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
