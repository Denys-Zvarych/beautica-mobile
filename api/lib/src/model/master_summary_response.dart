//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'master_summary_response.g.dart';

/// MasterSummaryResponse
///
/// Properties:
/// * [masterId]
/// * [firstName]
/// * [lastName]
/// * [avatarUrl]
/// * [avgRating]
/// * [reviewCount]
/// * [masterType]
@BuiltValue()
abstract class MasterSummaryResponse
    implements Built<MasterSummaryResponse, MasterSummaryResponseBuilder> {
  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'firstName')
  String? get firstName;

  @BuiltValueField(wireName: r'lastName')
  String? get lastName;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  @BuiltValueField(wireName: r'reviewCount')
  int? get reviewCount;

  @BuiltValueField(wireName: r'masterType')
  MasterSummaryResponseMasterTypeEnum? get masterType;
  // enum masterTypeEnum {  SALON_MASTER,  INDEPENDENT_MASTER,  SALON_OWNER,  };

  MasterSummaryResponse._();

  factory MasterSummaryResponse(
      [void updates(MasterSummaryResponseBuilder b)]) = _$MasterSummaryResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MasterSummaryResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MasterSummaryResponse> get serializer =>
      _$MasterSummaryResponseSerializer();
}

class _$MasterSummaryResponseSerializer
    implements PrimitiveSerializer<MasterSummaryResponse> {
  @override
  final Iterable<Type> types = const [
    MasterSummaryResponse,
    _$MasterSummaryResponse
  ];

  @override
  final String wireName = r'MasterSummaryResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MasterSummaryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.firstName != null) {
      yield r'firstName';
      yield serializers.serialize(
        object.firstName,
        specifiedType: const FullType(String),
      );
    }
    if (object.lastName != null) {
      yield r'lastName';
      yield serializers.serialize(
        object.lastName,
        specifiedType: const FullType(String),
      );
    }
    if (object.avatarUrl != null) {
      yield r'avatarUrl';
      yield serializers.serialize(
        object.avatarUrl,
        specifiedType: const FullType(String),
      );
    }
    if (object.avgRating != null) {
      yield r'avgRating';
      yield serializers.serialize(
        object.avgRating,
        specifiedType: const FullType(num),
      );
    }
    if (object.reviewCount != null) {
      yield r'reviewCount';
      yield serializers.serialize(
        object.reviewCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.masterType != null) {
      yield r'masterType';
      yield serializers.serialize(
        object.masterType,
        specifiedType: const FullType(MasterSummaryResponseMasterTypeEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MasterSummaryResponse object, {
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
    required MasterSummaryResponseBuilder result,
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
        case r'firstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.firstName = valueDes;
          break;
        case r'lastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.lastName = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        case r'avgRating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.avgRating = valueDes;
          break;
        case r'reviewCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.reviewCount = valueDes;
          break;
        case r'masterType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MasterSummaryResponseMasterTypeEnum),
          ) as MasterSummaryResponseMasterTypeEnum;
          result.masterType = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MasterSummaryResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MasterSummaryResponseBuilder();
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

class MasterSummaryResponseMasterTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const MasterSummaryResponseMasterTypeEnum SALON_MASTER =
      _$masterSummaryResponseMasterTypeEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const MasterSummaryResponseMasterTypeEnum INDEPENDENT_MASTER =
      _$masterSummaryResponseMasterTypeEnum_INDEPENDENT_MASTER;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const MasterSummaryResponseMasterTypeEnum SALON_OWNER =
      _$masterSummaryResponseMasterTypeEnum_SALON_OWNER;

  static Serializer<MasterSummaryResponseMasterTypeEnum> get serializer =>
      _$masterSummaryResponseMasterTypeEnumSerializer;

  const MasterSummaryResponseMasterTypeEnum._(String name) : super(name);

  static BuiltSet<MasterSummaryResponseMasterTypeEnum> get values =>
      _$masterSummaryResponseMasterTypeEnumValues;
  static MasterSummaryResponseMasterTypeEnum valueOf(String name) =>
      _$masterSummaryResponseMasterTypeEnumValueOf(name);
}
