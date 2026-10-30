//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_report_request.g.dart';

/// CreateReportRequest
///
/// Properties:
/// * [targetType]
/// * [targetId]
/// * [reason]
/// * [comment] - Optional; required (min 5 characters) when reason is OTHER
@BuiltValue()
abstract class CreateReportRequest
    implements Built<CreateReportRequest, CreateReportRequestBuilder> {
  @BuiltValueField(wireName: r'targetType')
  CreateReportRequestTargetTypeEnum get targetType;
  // enum targetTypeEnum {  REVIEW,  CLIENT_REVIEW,  PORTFOLIO_PHOTO,  MASTER_PROFILE,  SALON_PROFILE,  CLIENT_PROFILE,  };

  @BuiltValueField(wireName: r'targetId')
  String get targetId;

  @BuiltValueField(wireName: r'reason')
  CreateReportRequestReasonEnum get reason;
  // enum reasonEnum {  SPAM,  OFFENSIVE,  HARASSMENT,  FALSE_INFO,  SEXUAL_CONTENT,  OTHER,  };

  /// Optional; required (min 5 characters) when reason is OTHER
  @BuiltValueField(wireName: r'comment')
  String? get comment;

  CreateReportRequest._();

  factory CreateReportRequest([void updates(CreateReportRequestBuilder b)]) =
      _$CreateReportRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateReportRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateReportRequest> get serializer =>
      _$CreateReportRequestSerializer();
}

class _$CreateReportRequestSerializer
    implements PrimitiveSerializer<CreateReportRequest> {
  @override
  final Iterable<Type> types = const [
    CreateReportRequest,
    _$CreateReportRequest
  ];

  @override
  final String wireName = r'CreateReportRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateReportRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'targetType';
    yield serializers.serialize(
      object.targetType,
      specifiedType: const FullType(CreateReportRequestTargetTypeEnum),
    );
    yield r'targetId';
    yield serializers.serialize(
      object.targetId,
      specifiedType: const FullType(String),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(CreateReportRequestReasonEnum),
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
    CreateReportRequest object, {
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
    required CreateReportRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'targetType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CreateReportRequestTargetTypeEnum),
          ) as CreateReportRequestTargetTypeEnum;
          result.targetType = valueDes;
          break;
        case r'targetId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.targetId = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CreateReportRequestReasonEnum),
          ) as CreateReportRequestReasonEnum;
          result.reason = valueDes;
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
  CreateReportRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateReportRequestBuilder();
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

class CreateReportRequestTargetTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'REVIEW')
  static const CreateReportRequestTargetTypeEnum REVIEW =
      _$createReportRequestTargetTypeEnum_REVIEW;
  @BuiltValueEnumConst(wireName: r'CLIENT_REVIEW')
  static const CreateReportRequestTargetTypeEnum CLIENT_REVIEW =
      _$createReportRequestTargetTypeEnum_CLIENT_REVIEW;
  @BuiltValueEnumConst(wireName: r'PORTFOLIO_PHOTO')
  static const CreateReportRequestTargetTypeEnum PORTFOLIO_PHOTO =
      _$createReportRequestTargetTypeEnum_PORTFOLIO_PHOTO;
  @BuiltValueEnumConst(wireName: r'MASTER_PROFILE')
  static const CreateReportRequestTargetTypeEnum MASTER_PROFILE =
      _$createReportRequestTargetTypeEnum_MASTER_PROFILE;
  @BuiltValueEnumConst(wireName: r'SALON_PROFILE')
  static const CreateReportRequestTargetTypeEnum SALON_PROFILE =
      _$createReportRequestTargetTypeEnum_SALON_PROFILE;
  @BuiltValueEnumConst(wireName: r'CLIENT_PROFILE')
  static const CreateReportRequestTargetTypeEnum CLIENT_PROFILE =
      _$createReportRequestTargetTypeEnum_CLIENT_PROFILE;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const CreateReportRequestTargetTypeEnum unknownDefaultOpenApi =
      _$createReportRequestTargetTypeEnum_unknownDefaultOpenApi;

  static Serializer<CreateReportRequestTargetTypeEnum> get serializer =>
      _$createReportRequestTargetTypeEnumSerializer;

  const CreateReportRequestTargetTypeEnum._(String name) : super(name);

  static BuiltSet<CreateReportRequestTargetTypeEnum> get values =>
      _$createReportRequestTargetTypeEnumValues;
  static CreateReportRequestTargetTypeEnum valueOf(String name) =>
      _$createReportRequestTargetTypeEnumValueOf(name);
}

class CreateReportRequestReasonEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'SPAM')
  static const CreateReportRequestReasonEnum SPAM =
      _$createReportRequestReasonEnum_SPAM;
  @BuiltValueEnumConst(wireName: r'OFFENSIVE')
  static const CreateReportRequestReasonEnum OFFENSIVE =
      _$createReportRequestReasonEnum_OFFENSIVE;
  @BuiltValueEnumConst(wireName: r'HARASSMENT')
  static const CreateReportRequestReasonEnum HARASSMENT =
      _$createReportRequestReasonEnum_HARASSMENT;
  @BuiltValueEnumConst(wireName: r'FALSE_INFO')
  static const CreateReportRequestReasonEnum FALSE_INFO =
      _$createReportRequestReasonEnum_FALSE_INFO;
  @BuiltValueEnumConst(wireName: r'SEXUAL_CONTENT')
  static const CreateReportRequestReasonEnum SEXUAL_CONTENT =
      _$createReportRequestReasonEnum_SEXUAL_CONTENT;
  @BuiltValueEnumConst(wireName: r'OTHER')
  static const CreateReportRequestReasonEnum OTHER =
      _$createReportRequestReasonEnum_OTHER;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const CreateReportRequestReasonEnum unknownDefaultOpenApi =
      _$createReportRequestReasonEnum_unknownDefaultOpenApi;

  static Serializer<CreateReportRequestReasonEnum> get serializer =>
      _$createReportRequestReasonEnumSerializer;

  const CreateReportRequestReasonEnum._(String name) : super(name);

  static BuiltSet<CreateReportRequestReasonEnum> get values =>
      _$createReportRequestReasonEnumValues;
  static CreateReportRequestReasonEnum valueOf(String name) =>
      _$createReportRequestReasonEnumValueOf(name);
}
