//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guest_cancel_token.g.dart';

/// GuestCancelToken
///
/// Properties:
/// * [value]
/// * [legacy]
@BuiltValue()
abstract class GuestCancelToken
    implements Built<GuestCancelToken, GuestCancelTokenBuilder> {
  @BuiltValueField(wireName: r'value')
  String? get value;

  @BuiltValueField(wireName: r'legacy')
  bool? get legacy;

  GuestCancelToken._();

  factory GuestCancelToken([void updates(GuestCancelTokenBuilder b)]) =
      _$GuestCancelToken;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuestCancelTokenBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuestCancelToken> get serializer =>
      _$GuestCancelTokenSerializer();
}

class _$GuestCancelTokenSerializer
    implements PrimitiveSerializer<GuestCancelToken> {
  @override
  final Iterable<Type> types = const [GuestCancelToken, _$GuestCancelToken];

  @override
  final String wireName = r'GuestCancelToken';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuestCancelToken object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.value != null) {
      yield r'value';
      yield serializers.serialize(
        object.value,
        specifiedType: const FullType(String),
      );
    }
    if (object.legacy != null) {
      yield r'legacy';
      yield serializers.serialize(
        object.legacy,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuestCancelToken object, {
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
    required GuestCancelTokenBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'value':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.value = valueDes;
          break;
        case r'legacy':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.legacy = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuestCancelToken deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuestCancelTokenBuilder();
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
