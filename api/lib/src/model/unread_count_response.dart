//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'unread_count_response.g.dart';

/// UnreadCountResponse
///
/// Properties:
/// * [count]
@BuiltValue()
abstract class UnreadCountResponse
    implements Built<UnreadCountResponse, UnreadCountResponseBuilder> {
  @BuiltValueField(wireName: r'count')
  int? get count;

  UnreadCountResponse._();

  factory UnreadCountResponse([void updates(UnreadCountResponseBuilder b)]) =
      _$UnreadCountResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UnreadCountResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UnreadCountResponse> get serializer =>
      _$UnreadCountResponseSerializer();
}

class _$UnreadCountResponseSerializer
    implements PrimitiveSerializer<UnreadCountResponse> {
  @override
  final Iterable<Type> types = const [
    UnreadCountResponse,
    _$UnreadCountResponse
  ];

  @override
  final String wireName = r'UnreadCountResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UnreadCountResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.count != null) {
      yield r'count';
      yield serializers.serialize(
        object.count,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UnreadCountResponse object, {
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
    required UnreadCountResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UnreadCountResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UnreadCountResponseBuilder();
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
