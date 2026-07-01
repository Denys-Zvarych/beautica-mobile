//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'cancel_token_info_response.g.dart';

/// CancelTokenInfoResponse
///
/// Properties:
/// * [masterName]
/// * [serviceName]
/// * [startsAt]
/// * [cancellable]
/// * [windowClosesAt]
@BuiltValue()
abstract class CancelTokenInfoResponse
    implements Built<CancelTokenInfoResponse, CancelTokenInfoResponseBuilder> {
  @BuiltValueField(wireName: r'masterName')
  String? get masterName;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'cancellable')
  bool? get cancellable;

  @BuiltValueField(wireName: r'windowClosesAt')
  DateTime? get windowClosesAt;

  CancelTokenInfoResponse._();

  factory CancelTokenInfoResponse(
          [void updates(CancelTokenInfoResponseBuilder b)]) =
      _$CancelTokenInfoResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CancelTokenInfoResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CancelTokenInfoResponse> get serializer =>
      _$CancelTokenInfoResponseSerializer();
}

class _$CancelTokenInfoResponseSerializer
    implements PrimitiveSerializer<CancelTokenInfoResponse> {
  @override
  final Iterable<Type> types = const [
    CancelTokenInfoResponse,
    _$CancelTokenInfoResponse
  ];

  @override
  final String wireName = r'CancelTokenInfoResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CancelTokenInfoResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterName != null) {
      yield r'masterName';
      yield serializers.serialize(
        object.masterName,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceName != null) {
      yield r'serviceName';
      yield serializers.serialize(
        object.serviceName,
        specifiedType: const FullType(String),
      );
    }
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.cancellable != null) {
      yield r'cancellable';
      yield serializers.serialize(
        object.cancellable,
        specifiedType: const FullType(bool),
      );
    }
    if (object.windowClosesAt != null) {
      yield r'windowClosesAt';
      yield serializers.serialize(
        object.windowClosesAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CancelTokenInfoResponse object, {
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
    required CancelTokenInfoResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'masterName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterName = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'cancellable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.cancellable = valueDes;
          break;
        case r'windowClosesAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.windowClosesAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CancelTokenInfoResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CancelTokenInfoResponseBuilder();
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
