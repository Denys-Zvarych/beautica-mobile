//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'booking_link_response.g.dart';

/// A ready-to-share public booking link owned by the caller. MASTER: INDEPENDENT_MASTER only. SALON: SALON_OWNER (one per active owned salon, no MASTER link) and SALON_ADMIN (bound salon)
///
/// Properties:
/// * [kind] - MASTER = the caller's own master booking page; SALON = a salon booking page (phase 376)
/// * [status] - Phase 378: ACTIVE, or REVOKED (slug and url null, bookable false)
/// * [slug] - Public slug; null when status is REVOKED. Never changes on rename; changes only by an explicit regenerate (the old slug is retired for good)
/// * [url] - Absolute https canonical URL (the app adds its own share-channel flag): MASTER https://beautica.app/book/{slug}, SALON https://beautica.app/book/s/{slug}; null when status is REVOKED
/// * [displayName] - Master full name, or salon name for SALON links
/// * [salonId] - Salon id for SALON links; null for MASTER links
/// * [bookable] - false = clients see the page but cannot book yet (MASTER: no active service or no schedule; SALON: no bookable master)
@BuiltValue()
abstract class BookingLinkResponse
    implements Built<BookingLinkResponse, BookingLinkResponseBuilder> {
  /// MASTER = the caller's own master booking page; SALON = a salon booking page (phase 376)
  @BuiltValueField(wireName: r'kind')
  BookingLinkResponseKindEnum get kind;
  // enum kindEnum {  MASTER,  SALON,  };

  /// Phase 378: ACTIVE, or REVOKED (slug and url null, bookable false)
  @BuiltValueField(wireName: r'status')
  BookingLinkResponseStatusEnum get status;
  // enum statusEnum {  ACTIVE,  REVOKED,  };

  /// Public slug; null when status is REVOKED. Never changes on rename; changes only by an explicit regenerate (the old slug is retired for good)
  @BuiltValueField(wireName: r'slug')
  String? get slug;

  /// Absolute https canonical URL (the app adds its own share-channel flag): MASTER https://beautica.app/book/{slug}, SALON https://beautica.app/book/s/{slug}; null when status is REVOKED
  @BuiltValueField(wireName: r'url')
  String? get url;

  /// Master full name, or salon name for SALON links
  @BuiltValueField(wireName: r'displayName')
  String get displayName;

  /// Salon id for SALON links; null for MASTER links
  @BuiltValueField(wireName: r'salonId')
  String? get salonId;

  /// false = clients see the page but cannot book yet (MASTER: no active service or no schedule; SALON: no bookable master)
  @BuiltValueField(wireName: r'bookable')
  bool get bookable;

  BookingLinkResponse._();

  factory BookingLinkResponse([void updates(BookingLinkResponseBuilder b)]) =
      _$BookingLinkResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingLinkResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingLinkResponse> get serializer =>
      _$BookingLinkResponseSerializer();
}

class _$BookingLinkResponseSerializer
    implements PrimitiveSerializer<BookingLinkResponse> {
  @override
  final Iterable<Type> types = const [
    BookingLinkResponse,
    _$BookingLinkResponse
  ];

  @override
  final String wireName = r'BookingLinkResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingLinkResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(BookingLinkResponseKindEnum),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(BookingLinkResponseStatusEnum),
    );
    yield r'slug';
    yield object.slug == null
        ? null
        : serializers.serialize(
            object.slug,
            specifiedType: const FullType.nullable(String),
          );
    yield r'url';
    yield object.url == null
        ? null
        : serializers.serialize(
            object.url,
            specifiedType: const FullType.nullable(String),
          );
    yield r'displayName';
    yield serializers.serialize(
      object.displayName,
      specifiedType: const FullType(String),
    );
    if (object.salonId != null) {
      yield r'salonId';
      yield serializers.serialize(
        object.salonId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'bookable';
    yield serializers.serialize(
      object.bookable,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingLinkResponse object, {
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
    required BookingLinkResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookingLinkResponseKindEnum),
          ) as BookingLinkResponseKindEnum;
          result.kind = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BookingLinkResponseStatusEnum),
          ) as BookingLinkResponseStatusEnum;
          result.status = valueDes;
          break;
        case r'slug':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.slug = valueDes;
          break;
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.url = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'salonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.salonId = valueDes;
          break;
        case r'bookable':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.bookable = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BookingLinkResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingLinkResponseBuilder();
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

class BookingLinkResponseKindEnum extends EnumClass {
  /// MASTER = the caller's own master booking page; SALON = a salon booking page (phase 376)
  @BuiltValueEnumConst(wireName: r'MASTER')
  static const BookingLinkResponseKindEnum MASTER =
      _$bookingLinkResponseKindEnum_MASTER;

  /// MASTER = the caller's own master booking page; SALON = a salon booking page (phase 376)
  @BuiltValueEnumConst(wireName: r'SALON')
  static const BookingLinkResponseKindEnum SALON =
      _$bookingLinkResponseKindEnum_SALON;

  /// MASTER = the caller's own master booking page; SALON = a salon booking page (phase 376)
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const BookingLinkResponseKindEnum unknownDefaultOpenApi =
      _$bookingLinkResponseKindEnum_unknownDefaultOpenApi;

  static Serializer<BookingLinkResponseKindEnum> get serializer =>
      _$bookingLinkResponseKindEnumSerializer;

  const BookingLinkResponseKindEnum._(String name) : super(name);

  static BuiltSet<BookingLinkResponseKindEnum> get values =>
      _$bookingLinkResponseKindEnumValues;
  static BookingLinkResponseKindEnum valueOf(String name) =>
      _$bookingLinkResponseKindEnumValueOf(name);
}

class BookingLinkResponseStatusEnum extends EnumClass {
  /// Phase 378: ACTIVE, or REVOKED (slug and url null, bookable false)
  @BuiltValueEnumConst(wireName: r'ACTIVE')
  static const BookingLinkResponseStatusEnum ACTIVE =
      _$bookingLinkResponseStatusEnum_ACTIVE;

  /// Phase 378: ACTIVE, or REVOKED (slug and url null, bookable false)
  @BuiltValueEnumConst(wireName: r'REVOKED')
  static const BookingLinkResponseStatusEnum REVOKED =
      _$bookingLinkResponseStatusEnum_REVOKED;

  /// Phase 378: ACTIVE, or REVOKED (slug and url null, bookable false)
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const BookingLinkResponseStatusEnum unknownDefaultOpenApi =
      _$bookingLinkResponseStatusEnum_unknownDefaultOpenApi;

  static Serializer<BookingLinkResponseStatusEnum> get serializer =>
      _$bookingLinkResponseStatusEnumSerializer;

  const BookingLinkResponseStatusEnum._(String name) : super(name);

  static BuiltSet<BookingLinkResponseStatusEnum> get values =>
      _$bookingLinkResponseStatusEnumValues;
  static BookingLinkResponseStatusEnum valueOf(String name) =>
      _$bookingLinkResponseStatusEnumValueOf(name);
}
