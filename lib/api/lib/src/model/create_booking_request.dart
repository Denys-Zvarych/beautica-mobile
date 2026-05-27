//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_booking_request.g.dart';

/// CreateBookingRequest
///
/// Properties:
/// * [masterId]
/// * [masterServiceId]
/// * [startsAt]
/// * [idempotencyKey]
/// * [clientComment]
@BuiltValue()
abstract class CreateBookingRequest
    implements Built<CreateBookingRequest, CreateBookingRequestBuilder> {
  @BuiltValueField(wireName: r'masterId')
  String get masterId;

  @BuiltValueField(wireName: r'masterServiceId')
  String get masterServiceId;

  @BuiltValueField(wireName: r'startsAt')
  DateTime get startsAt;

  @BuiltValueField(wireName: r'idempotencyKey')
  String? get idempotencyKey;

  @BuiltValueField(wireName: r'clientComment')
  String? get clientComment;

  CreateBookingRequest._();

  factory CreateBookingRequest([void updates(CreateBookingRequestBuilder b)]) =
      _$CreateBookingRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateBookingRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateBookingRequest> get serializer =>
      _$CreateBookingRequestSerializer();
}

class _$CreateBookingRequestSerializer
    implements PrimitiveSerializer<CreateBookingRequest> {
  @override
  final Iterable<Type> types = const [
    CreateBookingRequest,
    _$CreateBookingRequest
  ];

  @override
  final String wireName = r'CreateBookingRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'masterId';
    yield serializers.serialize(
      object.masterId,
      specifiedType: const FullType(String),
    );
    yield r'masterServiceId';
    yield serializers.serialize(
      object.masterServiceId,
      specifiedType: const FullType(String),
    );
    yield r'startsAt';
    yield serializers.serialize(
      object.startsAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.idempotencyKey != null) {
      yield r'idempotencyKey';
      yield serializers.serialize(
        object.idempotencyKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.clientComment != null) {
      yield r'clientComment';
      yield serializers.serialize(
        object.clientComment,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateBookingRequest object, {
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
    required CreateBookingRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'masterServiceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterServiceId = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'idempotencyKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.idempotencyKey = valueDes;
          break;
        case r'clientComment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientComment = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateBookingRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateBookingRequestBuilder();
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
