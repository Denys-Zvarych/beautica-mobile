//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'mark_all_read_request.g.dart';

/// MarkAllReadRequest
///
/// Properties:
/// * [upTo] - Mark every still-unread item created at or before this instant. Defaults to the server's current time when omitted or null.
@BuiltValue()
abstract class MarkAllReadRequest
    implements Built<MarkAllReadRequest, MarkAllReadRequestBuilder> {
  /// Mark every still-unread item created at or before this instant. Defaults to the server's current time when omitted or null.
  @BuiltValueField(wireName: r'upTo')
  DateTime? get upTo;

  MarkAllReadRequest._();

  factory MarkAllReadRequest([void updates(MarkAllReadRequestBuilder b)]) =
      _$MarkAllReadRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MarkAllReadRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MarkAllReadRequest> get serializer =>
      _$MarkAllReadRequestSerializer();
}

class _$MarkAllReadRequestSerializer
    implements PrimitiveSerializer<MarkAllReadRequest> {
  @override
  final Iterable<Type> types = const [MarkAllReadRequest, _$MarkAllReadRequest];

  @override
  final String wireName = r'MarkAllReadRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MarkAllReadRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.upTo != null) {
      yield r'upTo';
      yield serializers.serialize(
        object.upTo,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MarkAllReadRequest object, {
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
    required MarkAllReadRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'upTo':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.upTo = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MarkAllReadRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MarkAllReadRequestBuilder();
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
