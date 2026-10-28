//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'report_response.g.dart';

/// ReportResponse
///
/// Properties:
/// * [id]
/// * [status]
/// * [createdAt]
@BuiltValue()
abstract class ReportResponse
    implements Built<ReportResponse, ReportResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'status')
  ReportResponseStatusEnum? get status;
  // enum statusEnum {  OPEN,  RESOLVED,  };

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  ReportResponse._();

  factory ReportResponse([void updates(ReportResponseBuilder b)]) =
      _$ReportResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ReportResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ReportResponse> get serializer =>
      _$ReportResponseSerializer();
}

class _$ReportResponseSerializer
    implements PrimitiveSerializer<ReportResponse> {
  @override
  final Iterable<Type> types = const [ReportResponse, _$ReportResponse];

  @override
  final String wireName = r'ReportResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ReportResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.status != null) {
      yield r'status';
      yield serializers.serialize(
        object.status,
        specifiedType: const FullType(ReportResponseStatusEnum),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ReportResponse object, {
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
    required ReportResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ReportResponseStatusEnum),
          ) as ReportResponseStatusEnum;
          result.status = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ReportResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ReportResponseBuilder();
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

class ReportResponseStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'OPEN')
  static const ReportResponseStatusEnum OPEN = _$reportResponseStatusEnum_OPEN;
  @BuiltValueEnumConst(wireName: r'RESOLVED')
  static const ReportResponseStatusEnum RESOLVED =
      _$reportResponseStatusEnum_RESOLVED;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ReportResponseStatusEnum unknownDefaultOpenApi =
      _$reportResponseStatusEnum_unknownDefaultOpenApi;

  static Serializer<ReportResponseStatusEnum> get serializer =>
      _$reportResponseStatusEnumSerializer;

  const ReportResponseStatusEnum._(String name) : super(name);

  static BuiltSet<ReportResponseStatusEnum> get values =>
      _$reportResponseStatusEnumValues;
  static ReportResponseStatusEnum valueOf(String name) =>
      _$reportResponseStatusEnumValueOf(name);
}
