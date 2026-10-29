//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_review_response.g.dart';

/// SalonReviewResponse
///
/// Properties:
/// * [id]
/// * [masterId]
/// * [masterFirstName]
/// * [masterLastName]
/// * [clientDisplayName]
/// * [serviceName]
/// * [rating]
/// * [comment]
/// * [createdAt]
/// * [authoredByViewer] - True when the authenticated caller wrote this review (the app hides «Поскаржитися» on it); always false for an anonymous caller and on booking-link (slug) pages.
/// * [source_] - Who wrote the review (phase 399): APP = a client account in the app; GUEST_LINK = a booking-link guest through an SMS invite, clientDisplayName is then the guest's «Ім'я П.» snapshot.
@BuiltValue()
abstract class SalonReviewResponse
    implements Built<SalonReviewResponse, SalonReviewResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'masterId')
  String? get masterId;

  @BuiltValueField(wireName: r'masterFirstName')
  String? get masterFirstName;

  @BuiltValueField(wireName: r'masterLastName')
  String? get masterLastName;

  @BuiltValueField(wireName: r'clientDisplayName')
  String? get clientDisplayName;

  @BuiltValueField(wireName: r'serviceName')
  String? get serviceName;

  @BuiltValueField(wireName: r'rating')
  int? get rating;

  @BuiltValueField(wireName: r'comment')
  String? get comment;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  /// True when the authenticated caller wrote this review (the app hides «Поскаржитися» on it); always false for an anonymous caller and on booking-link (slug) pages.
  @BuiltValueField(wireName: r'authoredByViewer')
  bool? get authoredByViewer;

  /// Who wrote the review (phase 399): APP = a client account in the app; GUEST_LINK = a booking-link guest through an SMS invite, clientDisplayName is then the guest's «Ім'я П.» snapshot.
  @BuiltValueField(wireName: r'source')
  SalonReviewResponseSource_Enum? get source_;
  // enum source_Enum {  APP,  GUEST_LINK,  };

  SalonReviewResponse._();

  factory SalonReviewResponse([void updates(SalonReviewResponseBuilder b)]) =
      _$SalonReviewResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonReviewResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonReviewResponse> get serializer =>
      _$SalonReviewResponseSerializer();
}

class _$SalonReviewResponseSerializer
    implements PrimitiveSerializer<SalonReviewResponse> {
  @override
  final Iterable<Type> types = const [
    SalonReviewResponse,
    _$SalonReviewResponse
  ];

  @override
  final String wireName = r'SalonReviewResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonReviewResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
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
    if (object.masterFirstName != null) {
      yield r'masterFirstName';
      yield serializers.serialize(
        object.masterFirstName,
        specifiedType: const FullType(String),
      );
    }
    if (object.masterLastName != null) {
      yield r'masterLastName';
      yield serializers.serialize(
        object.masterLastName,
        specifiedType: const FullType(String),
      );
    }
    if (object.clientDisplayName != null) {
      yield r'clientDisplayName';
      yield serializers.serialize(
        object.clientDisplayName,
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
    if (object.rating != null) {
      yield r'rating';
      yield serializers.serialize(
        object.rating,
        specifiedType: const FullType(int),
      );
    }
    if (object.comment != null) {
      yield r'comment';
      yield serializers.serialize(
        object.comment,
        specifiedType: const FullType(String),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.authoredByViewer != null) {
      yield r'authoredByViewer';
      yield serializers.serialize(
        object.authoredByViewer,
        specifiedType: const FullType(bool),
      );
    }
    if (object.source_ != null) {
      yield r'source';
      yield serializers.serialize(
        object.source_,
        specifiedType: const FullType(SalonReviewResponseSource_Enum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonReviewResponse object, {
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
    required SalonReviewResponseBuilder result,
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
        case r'masterId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterId = valueDes;
          break;
        case r'masterFirstName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterFirstName = valueDes;
          break;
        case r'masterLastName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.masterLastName = valueDes;
          break;
        case r'clientDisplayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientDisplayName = valueDes;
          break;
        case r'serviceName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceName = valueDes;
          break;
        case r'rating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rating = valueDes;
          break;
        case r'comment':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.comment = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'authoredByViewer':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.authoredByViewer = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SalonReviewResponseSource_Enum),
          ) as SalonReviewResponseSource_Enum;
          result.source_ = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonReviewResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonReviewResponseBuilder();
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

class SalonReviewResponseSource_Enum extends EnumClass {
  /// Who wrote the review (phase 399): APP = a client account in the app; GUEST_LINK = a booking-link guest through an SMS invite, clientDisplayName is then the guest's «Ім'я П.» snapshot.
  @BuiltValueEnumConst(wireName: r'APP')
  static const SalonReviewResponseSource_Enum APP =
      _$salonReviewResponseSourceEnum_APP;

  /// Who wrote the review (phase 399): APP = a client account in the app; GUEST_LINK = a booking-link guest through an SMS invite, clientDisplayName is then the guest's «Ім'я П.» snapshot.
  @BuiltValueEnumConst(wireName: r'GUEST_LINK')
  static const SalonReviewResponseSource_Enum GUEST_LINK =
      _$salonReviewResponseSourceEnum_GUEST_LINK;

  /// Who wrote the review (phase 399): APP = a client account in the app; GUEST_LINK = a booking-link guest through an SMS invite, clientDisplayName is then the guest's «Ім'я П.» snapshot.
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const SalonReviewResponseSource_Enum unknownDefaultOpenApi =
      _$salonReviewResponseSourceEnum_unknownDefaultOpenApi;

  static Serializer<SalonReviewResponseSource_Enum> get serializer =>
      _$salonReviewResponseSourceEnumSerializer;

  const SalonReviewResponseSource_Enum._(String name) : super(name);

  static BuiltSet<SalonReviewResponseSource_Enum> get values =>
      _$salonReviewResponseSourceEnumValues;
  static SalonReviewResponseSource_Enum valueOf(String name) =>
      _$salonReviewResponseSourceEnumValueOf(name);
}
