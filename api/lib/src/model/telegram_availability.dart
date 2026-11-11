//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'telegram_availability.g.dart';

/// TelegramAvailability
///
/// Properties:
/// * [available]
/// * [linked]
@BuiltValue()
abstract class TelegramAvailability
    implements Built<TelegramAvailability, TelegramAvailabilityBuilder> {
  @BuiltValueField(wireName: r'available')
  bool? get available;

  @BuiltValueField(wireName: r'linked')
  bool? get linked;

  TelegramAvailability._();

  factory TelegramAvailability([void updates(TelegramAvailabilityBuilder b)]) =
      _$TelegramAvailability;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TelegramAvailabilityBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TelegramAvailability> get serializer =>
      _$TelegramAvailabilitySerializer();
}

class _$TelegramAvailabilitySerializer
    implements PrimitiveSerializer<TelegramAvailability> {
  @override
  final Iterable<Type> types = const [
    TelegramAvailability,
    _$TelegramAvailability
  ];

  @override
  final String wireName = r'TelegramAvailability';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TelegramAvailability object, {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    TelegramAvailability object, {
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
    required TelegramAvailabilityBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TelegramAvailability deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TelegramAvailabilityBuilder();
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
