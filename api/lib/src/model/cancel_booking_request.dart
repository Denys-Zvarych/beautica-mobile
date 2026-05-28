//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cancel_booking_request.g.dart';

/// CancelBookingRequest
///
/// Properties:
/// * [cancellationReason]
/// * [comment]
@BuiltValue()
abstract class CancelBookingRequest
    implements Built<CancelBookingRequest, CancelBookingRequestBuilder> {
  @BuiltValueField(wireName: r'cancellationReason')
  CancelBookingRequestCancellationReasonEnum get cancellationReason;
  // enum cancellationReasonEnum {  CLIENT_NO_SHOW,  CLIENT_CANCELLED,  PROVIDER_UNAVAILABLE,  DUPLICATE,  OTHER,  };

  @BuiltValueField(wireName: r'comment')
  String? get comment;

  CancelBookingRequest._();

  factory CancelBookingRequest([void updates(CancelBookingRequestBuilder b)]) =
      _$CancelBookingRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CancelBookingRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CancelBookingRequest> get serializer =>
      _$CancelBookingRequestSerializer();
}

class _$CancelBookingRequestSerializer
    implements PrimitiveSerializer<CancelBookingRequest> {
  @override
  final Iterable<Type> types = const [
    CancelBookingRequest,
    _$CancelBookingRequest
  ];

  @override
  final String wireName = r'CancelBookingRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CancelBookingRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'cancellationReason';
    yield serializers.serialize(
      object.cancellationReason,
      specifiedType: const FullType(CancelBookingRequestCancellationReasonEnum),
    );
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
    CancelBookingRequest object, {
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
    required CancelBookingRequestBuilder result,
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
                const FullType(CancelBookingRequestCancellationReasonEnum),
          ) as CancelBookingRequestCancellationReasonEnum;
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
  CancelBookingRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CancelBookingRequestBuilder();
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

class CancelBookingRequestCancellationReasonEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT_NO_SHOW')
  static const CancelBookingRequestCancellationReasonEnum CLIENT_NO_SHOW =
      _$cancelBookingRequestCancellationReasonEnum_CLIENT_NO_SHOW;
  @BuiltValueEnumConst(wireName: r'CLIENT_CANCELLED')
  static const CancelBookingRequestCancellationReasonEnum CLIENT_CANCELLED =
      _$cancelBookingRequestCancellationReasonEnum_CLIENT_CANCELLED;
  @BuiltValueEnumConst(wireName: r'PROVIDER_UNAVAILABLE')
  static const CancelBookingRequestCancellationReasonEnum PROVIDER_UNAVAILABLE =
      _$cancelBookingRequestCancellationReasonEnum_PROVIDER_UNAVAILABLE;
  @BuiltValueEnumConst(wireName: r'DUPLICATE')
  static const CancelBookingRequestCancellationReasonEnum DUPLICATE =
      _$cancelBookingRequestCancellationReasonEnum_DUPLICATE;
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const CancelBookingRequestCancellationReasonEnum OTHER =
      _$cancelBookingRequestCancellationReasonEnum_OTHER;

  static Serializer<CancelBookingRequestCancellationReasonEnum>
      get serializer => _$cancelBookingRequestCancellationReasonEnumSerializer;

  const CancelBookingRequestCancellationReasonEnum._(String name) : super(name);

  static BuiltSet<CancelBookingRequestCancellationReasonEnum> get values =>
      _$cancelBookingRequestCancellationReasonEnumValues;
  static CancelBookingRequestCancellationReasonEnum valueOf(String name) =>
      _$cancelBookingRequestCancellationReasonEnumValueOf(name);
}
