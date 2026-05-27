//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/working_hours_response.dart';
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/public_salon_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'master_detail_response.g.dart';

/// MasterDetailResponse
///
/// Properties:
/// * [masterId]
/// * [firstName]
/// * [lastName]
/// * [city]
/// * [bio]
/// * [avatarUrl]
/// * [avgRating]
/// * [reviewCount]
/// * [masterType]
/// * [salon]
/// * [workingHours]
@BuiltValue()
abstract class MasterDetailResponse
    implements Built<MasterDetailResponse, MasterDetailResponseBuilder> {
  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'firstName')
  String? get firstName;

  @BuiltValueField(wireName: r'lastName')
  String? get lastName;

  @BuiltValueField(wireName: r'city')
  String? get city;

  @BuiltValueField(wireName: r'bio')
  String? get bio;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  @BuiltValueField(wireName: r'reviewCount')
  int? get reviewCount;

  @BuiltValueField(wireName: r'masterType')
  MasterDetailResponseMasterTypeEnum? get masterType;
  // enum masterTypeEnum {  SALON_MASTER,  INDEPENDENT_MASTER,  SALON_OWNER,  };

  @BuiltValueField(wireName: r'salon')
  PublicSalonResponse? get salon;

  @BuiltValueField(wireName: r'workingHours')
  BuiltList<WorkingHoursResponse>? get workingHours;

  MasterDetailResponse._();

  factory MasterDetailResponse([void updates(MasterDetailResponseBuilder b)]) =
      _$MasterDetailResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MasterDetailResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MasterDetailResponse> get serializer =>
      _$MasterDetailResponseSerializer();
}

class _$MasterDetailResponseSerializer
    implements PrimitiveSerializer<MasterDetailResponse> {
  @override
  final Iterable<Type> types = const [
    MasterDetailResponse,
    _$MasterDetailResponse
  ];

  @override
  final String wireName = r'MasterDetailResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MasterDetailResponse object, {
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
    if (object.city != null) {
      yield r'city';
      yield serializers.serialize(
        object.city,
        specifiedType: const FullType(String),
      );
    }
    if (object.bio != null) {
      yield r'bio';
      yield serializers.serialize(
        object.bio,
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
        specifiedType: const FullType(MasterDetailResponseMasterTypeEnum),
      );
    }
    if (object.salon != null) {
      yield r'salon';
      yield serializers.serialize(
        object.salon,
        specifiedType: const FullType(PublicSalonResponse),
      );
    }
    if (object.workingHours != null) {
      yield r'workingHours';
      yield serializers.serialize(
        object.workingHours,
        specifiedType:
            const FullType(BuiltList, [FullType(WorkingHoursResponse)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MasterDetailResponse object, {
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
    required MasterDetailResponseBuilder result,
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
        case r'city':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.city = valueDes;
          break;
        case r'bio':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bio = valueDes;
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
            specifiedType: const FullType(MasterDetailResponseMasterTypeEnum),
          ) as MasterDetailResponseMasterTypeEnum;
          result.masterType = valueDes;
          break;
        case r'salon':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PublicSalonResponse),
          ) as PublicSalonResponse;
          result.salon.replace(valueDes);
          break;
        case r'workingHours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(WorkingHoursResponse)]),
          ) as BuiltList<WorkingHoursResponse>;
          result.workingHours.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MasterDetailResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MasterDetailResponseBuilder();
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

class MasterDetailResponseMasterTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const MasterDetailResponseMasterTypeEnum SALON_MASTER =
      _$masterDetailResponseMasterTypeEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const MasterDetailResponseMasterTypeEnum INDEPENDENT_MASTER =
      _$masterDetailResponseMasterTypeEnum_INDEPENDENT_MASTER;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const MasterDetailResponseMasterTypeEnum SALON_OWNER =
      _$masterDetailResponseMasterTypeEnum_SALON_OWNER;

  static Serializer<MasterDetailResponseMasterTypeEnum> get serializer =>
      _$masterDetailResponseMasterTypeEnumSerializer;

  const MasterDetailResponseMasterTypeEnum._(String name) : super(name);

  static BuiltSet<MasterDetailResponseMasterTypeEnum> get values =>
      _$masterDetailResponseMasterTypeEnumValues;
  static MasterDetailResponseMasterTypeEnum valueOf(String name) =>
      _$masterDetailResponseMasterTypeEnumValueOf(name);
}
