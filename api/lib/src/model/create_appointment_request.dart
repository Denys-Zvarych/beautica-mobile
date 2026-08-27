//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_appointment_request.g.dart';

/// CreateAppointmentRequest
///
/// Properties:
/// * [masterId]
/// * [masterServiceIds]
/// * [startsAt]
/// * [idempotencyKey]
/// * [clientComment]
/// * [allowClientOverlap]
@BuiltValue()
abstract class CreateAppointmentRequest
    implements
        Built<CreateAppointmentRequest, CreateAppointmentRequestBuilder> {
  @BuiltValueField(wireName: r'masterId')
  String get masterId;

  @BuiltValueField(wireName: r'masterServiceIds')
  BuiltList<String> get masterServiceIds;

  @BuiltValueField(wireName: r'startsAt')
  DateTime get startsAt;

  @BuiltValueField(wireName: r'idempotencyKey')
  String? get idempotencyKey;

  @BuiltValueField(wireName: r'clientComment')
  String? get clientComment;

  @BuiltValueField(wireName: r'allowClientOverlap')
  bool? get allowClientOverlap;

  CreateAppointmentRequest._();

  factory CreateAppointmentRequest(
          [void updates(CreateAppointmentRequestBuilder b)]) =
      _$CreateAppointmentRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateAppointmentRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateAppointmentRequest> get serializer =>
      _$CreateAppointmentRequestSerializer();
}

class _$CreateAppointmentRequestSerializer
    implements PrimitiveSerializer<CreateAppointmentRequest> {
  @override
  final Iterable<Type> types = const [
    CreateAppointmentRequest,
    _$CreateAppointmentRequest
  ];

  @override
  final String wireName = r'CreateAppointmentRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateAppointmentRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'masterId';
    yield serializers.serialize(
      object.masterId,
      specifiedType: const FullType(String),
    );
    yield r'masterServiceIds';
    yield serializers.serialize(
      object.masterServiceIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
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
    if (object.allowClientOverlap != null) {
      yield r'allowClientOverlap';
      yield serializers.serialize(
        object.allowClientOverlap,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateAppointmentRequest object, {
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
    required CreateAppointmentRequestBuilder result,
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
        case r'masterServiceIds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.masterServiceIds.replace(valueDes);
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
        case r'allowClientOverlap':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.allowClientOverlap = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateAppointmentRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateAppointmentRequestBuilder();
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
