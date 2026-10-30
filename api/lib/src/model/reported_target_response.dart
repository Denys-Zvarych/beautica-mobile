//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'reported_target_response.g.dart';

/// ReportedTargetResponse
///
/// Properties:
/// * [targetType]
/// * [targetId]
@BuiltValue()
abstract class ReportedTargetResponse
    implements Built<ReportedTargetResponse, ReportedTargetResponseBuilder> {
  @BuiltValueField(wireName: r'targetType')
  ReportedTargetResponseTargetTypeEnum? get targetType;
  // enum targetTypeEnum {  REVIEW,  CLIENT_REVIEW,  PORTFOLIO_PHOTO,  MASTER_PROFILE,  SALON_PROFILE,  CLIENT_PROFILE,  };

  @BuiltValueField(wireName: r'targetId')
  String? get targetId;

  ReportedTargetResponse._();

  factory ReportedTargetResponse(
          [void updates(ReportedTargetResponseBuilder b)]) =
      _$ReportedTargetResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReportedTargetResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReportedTargetResponse> get serializer =>
      _$ReportedTargetResponseSerializer();
}

class _$ReportedTargetResponseSerializer
    implements PrimitiveSerializer<ReportedTargetResponse> {
  @override
  final Iterable<Type> types = const [
    ReportedTargetResponse,
    _$ReportedTargetResponse
  ];

  @override
  final String wireName = r'ReportedTargetResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReportedTargetResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.targetType != null) {
      yield r'targetType';
      yield serializers.serialize(
        object.targetType,
        specifiedType: const FullType(ReportedTargetResponseTargetTypeEnum),
      );
    }
    if (object.targetId != null) {
      yield r'targetId';
      yield serializers.serialize(
        object.targetId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReportedTargetResponse object, {
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
    required ReportedTargetResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'targetType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReportedTargetResponseTargetTypeEnum),
          ) as ReportedTargetResponseTargetTypeEnum;
          result.targetType = valueDes;
          break;
        case r'targetId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReportedTargetResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReportedTargetResponseBuilder();
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

class ReportedTargetResponseTargetTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'REVIEW')
  static const ReportedTargetResponseTargetTypeEnum REVIEW =
      _$reportedTargetResponseTargetTypeEnum_REVIEW;
  @BuiltValueEnumConst(wireName: r'CLIENT_REVIEW')
  static const ReportedTargetResponseTargetTypeEnum CLIENT_REVIEW =
      _$reportedTargetResponseTargetTypeEnum_CLIENT_REVIEW;
  @BuiltValueEnumConst(wireName: r'PORTFOLIO_PHOTO')
  static const ReportedTargetResponseTargetTypeEnum PORTFOLIO_PHOTO =
      _$reportedTargetResponseTargetTypeEnum_PORTFOLIO_PHOTO;
  @BuiltValueEnumConst(wireName: r'MASTER_PROFILE')
  static const ReportedTargetResponseTargetTypeEnum MASTER_PROFILE =
      _$reportedTargetResponseTargetTypeEnum_MASTER_PROFILE;
  @BuiltValueEnumConst(wireName: r'SALON_PROFILE')
  static const ReportedTargetResponseTargetTypeEnum SALON_PROFILE =
      _$reportedTargetResponseTargetTypeEnum_SALON_PROFILE;
  @BuiltValueEnumConst(wireName: r'CLIENT_PROFILE')
  static const ReportedTargetResponseTargetTypeEnum CLIENT_PROFILE =
      _$reportedTargetResponseTargetTypeEnum_CLIENT_PROFILE;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ReportedTargetResponseTargetTypeEnum unknownDefaultOpenApi =
      _$reportedTargetResponseTargetTypeEnum_unknownDefaultOpenApi;

  static Serializer<ReportedTargetResponseTargetTypeEnum> get serializer =>
      _$reportedTargetResponseTargetTypeEnumSerializer;

  const ReportedTargetResponseTargetTypeEnum._(String name) : super(name);

  static BuiltSet<ReportedTargetResponseTargetTypeEnum> get values =>
      _$reportedTargetResponseTargetTypeEnumValues;
  static ReportedTargetResponseTargetTypeEnum valueOf(String name) =>
      _$reportedTargetResponseTargetTypeEnumValueOf(name);
}
