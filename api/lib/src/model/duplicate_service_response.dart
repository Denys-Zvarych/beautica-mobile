//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'duplicate_service_response.g.dart';

/// Payload under `data` of the 409 DUPLICATE_SERVICE response. Branch on `code`; both detail fields may be null and the client must render without them.
///
/// Properties:
/// * [code] - Stable machine-readable error code. Always present — the only field the client branches on.
/// * [serviceName] - Human-readable label for the conflicting service, so the client can name it without a second round-trip: the service TYPE's name when the service-layer pre-check caught the conflict, the name the caller just SUBMITTED when the DB index caught a race instead. Null only on the bulk path.
/// * [existingServiceDefId] - Id of the existing service definition, for a deep-link. Null when the DB index caught the conflict rather than the service-layer pre-check.
@BuiltValue()
abstract class DuplicateServiceResponse
    implements
        Built<DuplicateServiceResponse, DuplicateServiceResponseBuilder> {
  /// Stable machine-readable error code. Always present — the only field the client branches on.
  @BuiltValueField(wireName: r'code')
  String? get code;

  /// Human-readable label for the conflicting service, so the client can name it without a second round-trip: the service TYPE's name when the service-layer pre-check caught the conflict, the name the caller just SUBMITTED when the DB index caught a race instead. Null only on the bulk path.
  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  /// Id of the existing service definition, for a deep-link. Null when the DB index caught the conflict rather than the service-layer pre-check.
  @BuiltValueField(wireName: r'existingServiceDefId')
  String? get existingServiceDefId;

  DuplicateServiceResponse._();

  factory DuplicateServiceResponse(
          [void updates(DuplicateServiceResponseBuilder b)]) =
      _$DuplicateServiceResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DuplicateServiceResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DuplicateServiceResponse> get serializer =>
      _$DuplicateServiceResponseSerializer();
}

class _$DuplicateServiceResponseSerializer
    implements PrimitiveSerializer<DuplicateServiceResponse> {
  @override
  final Iterable<Type> types = const [
    DuplicateServiceResponse,
    _$DuplicateServiceResponse
  ];

  @override
  final String wireName = r'DuplicateServiceResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DuplicateServiceResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.existingServiceDefId != null) {
      yield r'existingServiceDefId';
      yield serializers.serialize(
        object.existingServiceDefId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DuplicateServiceResponse object, {
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
    required DuplicateServiceResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.serviceName = valueDes;
          break;
        case r'existingServiceDefId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.existingServiceDefId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DuplicateServiceResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DuplicateServiceResponseBuilder();
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
