//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mark_all_read_response.g.dart';

/// MarkAllReadResponse
///
/// Properties:
/// * [updated]
@BuiltValue()
abstract class MarkAllReadResponse
    implements Built<MarkAllReadResponse, MarkAllReadResponseBuilder> {
  @BuiltValueField(wireName: r'updated')
  int? get updated;

  MarkAllReadResponse._();

  factory MarkAllReadResponse([void updates(MarkAllReadResponseBuilder b)]) =
      _$MarkAllReadResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MarkAllReadResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MarkAllReadResponse> get serializer =>
      _$MarkAllReadResponseSerializer();
}

class _$MarkAllReadResponseSerializer
    implements PrimitiveSerializer<MarkAllReadResponse> {
  @override
  final Iterable<Type> types = const [
    MarkAllReadResponse,
    _$MarkAllReadResponse
  ];

  @override
  final String wireName = r'MarkAllReadResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MarkAllReadResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.updated != null) {
      yield r'updated';
      yield serializers.serialize(
        object.updated,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MarkAllReadResponse object, {
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
    required MarkAllReadResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'updated':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.updated = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MarkAllReadResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MarkAllReadResponseBuilder();
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
