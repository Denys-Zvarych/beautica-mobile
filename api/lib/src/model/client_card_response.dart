//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/rating_bucket.dart';
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/served_master.dart';
import 'package:beautica_api/src/model/stats.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'client_card_response.g.dart';

/// ClientCardResponse
///
/// Properties:
/// * [kind]
/// * [userId]
/// * [guestBookingId]
/// * [displayName]
/// * [avatarUrl]
/// * [phone]
/// * [blocked]
/// * [ratingAvg]
/// * [ratingCount]
/// * [ratingDistribution]
/// * [firstVisitAt]
/// * [lastVisitAt]
/// * [nextVisitAt]
/// * [stats]
/// * [servedByMasters]
@BuiltValue()
abstract class ClientCardResponse
    implements Built<ClientCardResponse, ClientCardResponseBuilder> {
  @BuiltValueField(wireName: r'kind')
  ClientCardResponseKindEnum? get kind;
  // enum kindEnum {  REGISTERED,  GUEST,  };

  @BuiltValueField(wireName: r'userId')
  String? get userId;

  @BuiltValueField(wireName: r'guestBookingId')
  String? get guestBookingId;

  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'phone')
  String? get phone;

  @BuiltValueField(wireName: r'blocked')
  bool? get blocked;

  @BuiltValueField(wireName: r'ratingAvg')
  num? get ratingAvg;

  @BuiltValueField(wireName: r'ratingCount')
  int? get ratingCount;

  @BuiltValueField(wireName: r'ratingDistribution')
  BuiltList<RatingBucket>? get ratingDistribution;

  @BuiltValueField(wireName: r'firstVisitAt')
  DateTime? get firstVisitAt;

  @BuiltValueField(wireName: r'lastVisitAt')
  DateTime? get lastVisitAt;

  @BuiltValueField(wireName: r'nextVisitAt')
  DateTime? get nextVisitAt;

  @BuiltValueField(wireName: r'stats')
  Stats? get stats;

  @BuiltValueField(wireName: r'servedByMasters')
  BuiltList<ServedMaster>? get servedByMasters;

  ClientCardResponse._();

  factory ClientCardResponse([void updates(ClientCardResponseBuilder b)]) =
      _$ClientCardResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClientCardResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ClientCardResponse> get serializer =>
      _$ClientCardResponseSerializer();
}

class _$ClientCardResponseSerializer
    implements PrimitiveSerializer<ClientCardResponse> {
  @override
  final Iterable<Type> types = const [ClientCardResponse, _$ClientCardResponse];

  @override
  final String wireName = r'ClientCardResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClientCardResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.kind != null) {
      yield r'kind';
      yield serializers.serialize(
        object.kind,
        specifiedType: const FullType(ClientCardResponseKindEnum),
      );
    }
    if (object.userId != null) {
      yield r'userId';
      yield serializers.serialize(
        object.userId,
        specifiedType: const FullType(String),
      );
    }
    if (object.guestBookingId != null) {
      yield r'guestBookingId';
      yield serializers.serialize(
        object.guestBookingId,
        specifiedType: const FullType(String),
      );
    }
    if (object.displayName != null) {
      yield r'displayName';
      yield serializers.serialize(
        object.displayName,
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
    if (object.phone != null) {
      yield r'phone';
      yield serializers.serialize(
        object.phone,
        specifiedType: const FullType(String),
      );
    }
    if (object.blocked != null) {
      yield r'blocked';
      yield serializers.serialize(
        object.blocked,
        specifiedType: const FullType(bool),
      );
    }
    if (object.ratingAvg != null) {
      yield r'ratingAvg';
      yield serializers.serialize(
        object.ratingAvg,
        specifiedType: const FullType(num),
      );
    }
    if (object.ratingCount != null) {
      yield r'ratingCount';
      yield serializers.serialize(
        object.ratingCount,
        specifiedType: const FullType(int),
      );
    }
    if (object.ratingDistribution != null) {
      yield r'ratingDistribution';
      yield serializers.serialize(
        object.ratingDistribution,
        specifiedType: const FullType(BuiltList, [FullType(RatingBucket)]),
      );
    }
    if (object.firstVisitAt != null) {
      yield r'firstVisitAt';
      yield serializers.serialize(
        object.firstVisitAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.lastVisitAt != null) {
      yield r'lastVisitAt';
      yield serializers.serialize(
        object.lastVisitAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.nextVisitAt != null) {
      yield r'nextVisitAt';
      yield serializers.serialize(
        object.nextVisitAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.stats != null) {
      yield r'stats';
      yield serializers.serialize(
        object.stats,
        specifiedType: const FullType(Stats),
      );
    }
    if (object.servedByMasters != null) {
      yield r'servedByMasters';
      yield serializers.serialize(
        object.servedByMasters,
        specifiedType: const FullType(BuiltList, [FullType(ServedMaster)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClientCardResponse object, {
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
    required ClientCardResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ClientCardResponseKindEnum),
          ) as ClientCardResponseKindEnum;
          result.kind = valueDes;
          break;
        case r'userId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'guestBookingId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guestBookingId = valueDes;
          break;
        case r'displayName':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.displayName = valueDes;
          break;
        case r'avatarUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.avatarUrl = valueDes;
          break;
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        case r'blocked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.blocked = valueDes;
          break;
        case r'ratingAvg':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.ratingAvg = valueDes;
          break;
        case r'ratingCount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ratingCount = valueDes;
          break;
        case r'ratingDistribution':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RatingBucket)]),
          ) as BuiltList<RatingBucket>;
          result.ratingDistribution.replace(valueDes);
          break;
        case r'firstVisitAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.firstVisitAt = valueDes;
          break;
        case r'lastVisitAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.lastVisitAt = valueDes;
          break;
        case r'nextVisitAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.nextVisitAt = valueDes;
          break;
        case r'stats':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Stats),
          ) as Stats;
          result.stats.replace(valueDes);
          break;
        case r'servedByMasters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ServedMaster)]),
          ) as BuiltList<ServedMaster>;
          result.servedByMasters.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ClientCardResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClientCardResponseBuilder();
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

class ClientCardResponseKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'REGISTERED')
  static const ClientCardResponseKindEnum REGISTERED =
      _$clientCardResponseKindEnum_REGISTERED;
  @BuiltValueEnumConst(wireName: r'GUEST')
  static const ClientCardResponseKindEnum GUEST =
      _$clientCardResponseKindEnum_GUEST;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ClientCardResponseKindEnum unknownDefaultOpenApi =
      _$clientCardResponseKindEnum_unknownDefaultOpenApi;

  static Serializer<ClientCardResponseKindEnum> get serializer =>
      _$clientCardResponseKindEnumSerializer;

  const ClientCardResponseKindEnum._(String name) : super(name);

  static BuiltSet<ClientCardResponseKindEnum> get values =>
      _$clientCardResponseKindEnumValues;
  static ClientCardResponseKindEnum valueOf(String name) =>
      _$clientCardResponseKindEnumValueOf(name);
}
