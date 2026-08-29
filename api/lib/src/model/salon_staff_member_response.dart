//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_staff_member_response.g.dart';

/// SalonStaffMemberResponse
///
/// Properties:
/// * [userId]
/// * [masterId]
/// * [role]
/// * [firstName]
/// * [lastName]
/// * [professionalTitle]
/// * [avatarUrl]
/// * [phoneNumber]
/// * [instagram]
/// * [bio]
/// * [avgRating]
/// * [reviewCount]
/// * [serviceCount]
@BuiltValue()
abstract class SalonStaffMemberResponse
    implements
        Built<SalonStaffMemberResponse, SalonStaffMemberResponseBuilder> {
  @BuiltValueField(wireName: r'userId')
  String? get userId;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'role')
  SalonStaffMemberResponseRoleEnum? get role;
  // enum roleEnum {  CLIENT,  SALON_OWNER,  SALON_ADMIN,  SALON_MASTER,  INDEPENDENT_MASTER,  };

  @BuiltValueField(wireName: r'firstName')
  String? get firstName;

  @BuiltValueField(wireName: r'lastName')
  String? get lastName;

  @BuiltValueField(wireName: r'professionalTitle')
  String? get professionalTitle;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'phoneNumber')
  String? get phoneNumber;

  @BuiltValueField(wireName: r'instagram')
  String? get instagram;

  @BuiltValueField(wireName: r'bio')
  String? get bio;

  @BuiltValueField(wireName: r'avgRating')
  num? get avgRating;

  @BuiltValueField(wireName: r'reviewCount')
  int? get reviewCount;

  @BuiltValueField(wireName: r'serviceCount')
  int? get serviceCount;

  SalonStaffMemberResponse._();

  factory SalonStaffMemberResponse(
          [void updates(SalonStaffMemberResponseBuilder b)]) =
      _$SalonStaffMemberResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonStaffMemberResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonStaffMemberResponse> get serializer =>
      _$SalonStaffMemberResponseSerializer();
}

class _$SalonStaffMemberResponseSerializer
    implements PrimitiveSerializer<SalonStaffMemberResponse> {
  @override
  final Iterable<Type> types = const [
    SalonStaffMemberResponse,
    _$SalonStaffMemberResponse
  ];

  @override
  final String wireName = r'SalonStaffMemberResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonStaffMemberResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.userId != null) {
      yield r'userId';
      yield serializers.serialize(
        object.userId,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterId != null) {
      yield r'masterId';
      yield serializers.serialize(
        object.masterId,
        specifiedType: const FullType(String),
      );
    }
    if (object.role != null) {
      yield r'role';
      yield serializers.serialize(
        object.role,
        specifiedType: const FullType(SalonStaffMemberResponseRoleEnum),
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
    if (object.professionalTitle != null) {
      yield r'professionalTitle';
      yield serializers.serialize(
        object.professionalTitle,
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
    if (object.phoneNumber != null) {
      yield r'phoneNumber';
      yield serializers.serialize(
        object.phoneNumber,
        specifiedType: const FullType(String),
      );
    }
    if (object.instagram != null) {
      yield r'instagram';
      yield serializers.serialize(
        object.instagram,
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
    if (object.serviceCount != null) {
      yield r'serviceCount';
      yield serializers.serialize(
        object.serviceCount,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonStaffMemberResponse object, {
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
    required SalonStaffMemberResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'userId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SalonStaffMemberResponseRoleEnum),
          ) as SalonStaffMemberResponseRoleEnum;
          result.role = valueDes;
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
        case r'professionalTitle':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.professionalTitle = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        case r'phoneNumber':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phoneNumber = valueDes;
          break;
        case r'instagram':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.instagram = valueDes;
          break;
        case r'bio':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bio = valueDes;
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
        case r'serviceCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.serviceCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonStaffMemberResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonStaffMemberResponseBuilder();
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

class SalonStaffMemberResponseRoleEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CLIENT')
  static const SalonStaffMemberResponseRoleEnum CLIENT =
      _$salonStaffMemberResponseRoleEnum_CLIENT;
  @BuiltValueEnumConst(wireName: r'SALON_OWNER')
  static const SalonStaffMemberResponseRoleEnum SALON_OWNER =
      _$salonStaffMemberResponseRoleEnum_SALON_OWNER;
  @BuiltValueEnumConst(wireName: r'SALON_ADMIN')
  static const SalonStaffMemberResponseRoleEnum SALON_ADMIN =
      _$salonStaffMemberResponseRoleEnum_SALON_ADMIN;
  @BuiltValueEnumConst(wireName: r'SALON_MASTER')
  static const SalonStaffMemberResponseRoleEnum SALON_MASTER =
      _$salonStaffMemberResponseRoleEnum_SALON_MASTER;
  @BuiltValueEnumConst(wireName: r'INDEPENDENT_MASTER')
  static const SalonStaffMemberResponseRoleEnum INDEPENDENT_MASTER =
      _$salonStaffMemberResponseRoleEnum_INDEPENDENT_MASTER;

  static Serializer<SalonStaffMemberResponseRoleEnum> get serializer =>
      _$salonStaffMemberResponseRoleEnumSerializer;

  const SalonStaffMemberResponseRoleEnum._(String name) : super(name);

  static BuiltSet<SalonStaffMemberResponseRoleEnum> get values =>
      _$salonStaffMemberResponseRoleEnumValues;
  static SalonStaffMemberResponseRoleEnum valueOf(String name) =>
      _$salonStaffMemberResponseRoleEnumValueOf(name);
}
