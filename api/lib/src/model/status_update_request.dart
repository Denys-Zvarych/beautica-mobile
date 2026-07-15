//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'status_update_request.g.dart';

/// StatusUpdateRequest
///
/// Properties:
/// * [cancellationReason]
/// * [comment]
@BuiltValue()
abstract class StatusUpdateRequest
    implements Built<StatusUpdateRequest, StatusUpdateRequestBuilder> {
  @BuiltValueField(wireName: r'cancellationReason')
  StatusUpdateRequestCancellationReasonEnum? get cancellationReason;
  // enum cancellationReasonEnum {  CLIENT_NO_SHOW,  CLIENT_CANCELLED,  PROVIDER_UNAVAILABLE,  DUPLICATE,  OTHER,  };

  @BuiltValueField(wireName: r'comment')
  String? get comment;

  StatusUpdateRequest._();

  factory StatusUpdateRequest([void updates(StatusUpdateRequestBuilder b)]) =
      _$StatusUpdateRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StatusUpdateRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StatusUpdateRequest> get serializer =>
      _$StatusUpdateRequestSerializer();
}

class _$StatusUpdateRequestSerializer
    implements PrimitiveSerializer<StatusUpdateRequest> {
  @override
  final Iterable<Type> types = const [
    StatusUpdateRequest,
    _$StatusUpdateRequest
  ];

  @override
  final String wireName = r'StatusUpdateRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StatusUpdateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.cancellationReason != null) {
      yield r'cancellationReason';
      yield serializers.serialize(
        object.cancellationReason,
        specifiedType:
            const FullType(StatusUpdateRequestCancellationReasonEnum),
      );
    }
    if (object.comment != null) {
      yield r'comment';
      yield serializers.serialize(
        object.comment,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    StatusUpdateRequest object, {
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
    required StatusUpdateRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cancellationReason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(StatusUpdateRequestCancellationReasonEnum),
          ) as StatusUpdateRequestCancellationReasonEnum;
          result.cancellationReason = valueDes;
          break;
        case r'comment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.comment = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  StatusUpdateRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StatusUpdateRequestBuilder();
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

class StatusUpdateRequestCancellationReasonEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT_NO_SHOW')
  static const StatusUpdateRequestCancellationReasonEnum CLIENT_NO_SHOW =
      _$statusUpdateRequestCancellationReasonEnum_CLIENT_NO_SHOW;
  @BuiltValueEnumConst(wireName: r'CLIENT_CANCELLED')
  static const StatusUpdateRequestCancellationReasonEnum CLIENT_CANCELLED =
      _$statusUpdateRequestCancellationReasonEnum_CLIENT_CANCELLED;
  @BuiltValueEnumConst(wireName: r'PROVIDER_UNAVAILABLE')
  static const StatusUpdateRequestCancellationReasonEnum PROVIDER_UNAVAILABLE =
      _$statusUpdateRequestCancellationReasonEnum_PROVIDER_UNAVAILABLE;
  @BuiltValueEnumConst(wireName: r'DUPLICATE')
  static const StatusUpdateRequestCancellationReasonEnum DUPLICATE =
      _$statusUpdateRequestCancellationReasonEnum_DUPLICATE;
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const StatusUpdateRequestCancellationReasonEnum OTHER =
      _$statusUpdateRequestCancellationReasonEnum_OTHER;

  static Serializer<StatusUpdateRequestCancellationReasonEnum> get serializer =>
      _$statusUpdateRequestCancellationReasonEnumSerializer;

  const StatusUpdateRequestCancellationReasonEnum._(String name) : super(name);

  static BuiltSet<StatusUpdateRequestCancellationReasonEnum> get values =>
      _$statusUpdateRequestCancellationReasonEnumValues;
  static StatusUpdateRequestCancellationReasonEnum valueOf(String name) =>
      _$statusUpdateRequestCancellationReasonEnumValueOf(name);
}
