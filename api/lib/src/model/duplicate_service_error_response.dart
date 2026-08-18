//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/duplicate_service_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'duplicate_service_error_response.g.dart';

/// 409 response body when a provider adds a service they already offer. Branch on `data.code` (DUPLICATE_SERVICE), never on `message`, which is generic copy shared with the other 409s.
///
/// Properties:
/// * [success] - Always false on this response.
/// * [data] - The duplicate-service detail payload.
/// * [message] - Generic human-readable copy. Not branchable.
@BuiltValue()
abstract class DuplicateServiceErrorResponse
    implements
        Built<DuplicateServiceErrorResponse,
            DuplicateServiceErrorResponseBuilder> {
  /// Always false on this response.
  @BuiltValueField(wireName: r'success')
  bool? get success;

  /// The duplicate-service detail payload.
  @BuiltValueField(wireName: r'data')
  DuplicateServiceResponse? get data;

  /// Generic human-readable copy. Not branchable.
  @BuiltValueField(wireName: r'message')
  String? get message;

  DuplicateServiceErrorResponse._();

  factory DuplicateServiceErrorResponse(
          [void updates(DuplicateServiceErrorResponseBuilder b)]) =
      _$DuplicateServiceErrorResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DuplicateServiceErrorResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DuplicateServiceErrorResponse> get serializer =>
      _$DuplicateServiceErrorResponseSerializer();
}

class _$DuplicateServiceErrorResponseSerializer
    implements PrimitiveSerializer<DuplicateServiceErrorResponse> {
  @override
  final Iterable<Type> types = const [
    DuplicateServiceErrorResponse,
    _$DuplicateServiceErrorResponse
  ];

  @override
  final String wireName = r'DuplicateServiceErrorResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DuplicateServiceErrorResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.success != null) {
      yield r'success';
      yield serializers.serialize(
        object.success,
        specifiedType: const FullType(bool),
      );
    }
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(DuplicateServiceResponse),
      );
    }
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DuplicateServiceErrorResponse object, {
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
    required DuplicateServiceErrorResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DuplicateServiceResponse),
          ) as DuplicateServiceResponse;
          result.data.replace(valueDes);
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DuplicateServiceErrorResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DuplicateServiceErrorResponseBuilder();
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
