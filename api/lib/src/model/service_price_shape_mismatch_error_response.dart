//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/service_price_shape_mismatch_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'service_price_shape_mismatch_error_response.g.dart';

/// 400 response body when a bulk item's price shape cannot be represented against the salon definition it would reuse. Branch on `data.code` (SERVICE_PRICE_SHAPE_MISMATCH), never on `message`, which is generic copy.
///
/// Properties:
/// * [success] - Always false on this response.
/// * [data] - The price-shape-mismatch detail payload.
/// * [message] - Generic human-readable copy. Not branchable.
@BuiltValue()
abstract class ServicePriceShapeMismatchErrorResponse
    implements
        Built<ServicePriceShapeMismatchErrorResponse,
            ServicePriceShapeMismatchErrorResponseBuilder> {
  /// Always false on this response.
  @BuiltValueField(wireName: r'success')
  bool? get success;

  /// The price-shape-mismatch detail payload.
  @BuiltValueField(wireName: r'data')
  ServicePriceShapeMismatchResponse? get data;

  /// Generic human-readable copy. Not branchable.
  @BuiltValueField(wireName: r'message')
  String? get message;

  ServicePriceShapeMismatchErrorResponse._();

  factory ServicePriceShapeMismatchErrorResponse(
          [void updates(ServicePriceShapeMismatchErrorResponseBuilder b)]) =
      _$ServicePriceShapeMismatchErrorResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServicePriceShapeMismatchErrorResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServicePriceShapeMismatchErrorResponse> get serializer =>
      _$ServicePriceShapeMismatchErrorResponseSerializer();
}

class _$ServicePriceShapeMismatchErrorResponseSerializer
    implements PrimitiveSerializer<ServicePriceShapeMismatchErrorResponse> {
  @override
  final Iterable<Type> types = const [
    ServicePriceShapeMismatchErrorResponse,
    _$ServicePriceShapeMismatchErrorResponse
  ];

  @override
  final String wireName = r'ServicePriceShapeMismatchErrorResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServicePriceShapeMismatchErrorResponse object, {
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
        specifiedType: const FullType(ServicePriceShapeMismatchResponse),
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
    ServicePriceShapeMismatchErrorResponse object, {
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
    required ServicePriceShapeMismatchErrorResponseBuilder result,
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
            specifiedType: const FullType(ServicePriceShapeMismatchResponse),
          ) as ServicePriceShapeMismatchResponse;
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
  ServicePriceShapeMismatchErrorResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServicePriceShapeMismatchErrorResponseBuilder();
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
