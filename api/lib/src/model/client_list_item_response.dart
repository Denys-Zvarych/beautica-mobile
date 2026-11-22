//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'client_list_item_response.g.dart';

/// ClientListItemResponse
///
/// Properties:
/// * [kind]
/// * [userId]
/// * [guestBookingId]
/// * [displayName]
/// * [avatarUrl]
/// * [lastVisitAt]
/// * [nextVisitAt]
/// * [completedVisits]
/// * [ratingAvg]
/// * [ratingCount]
/// * [blocked]
@BuiltValue()
abstract class ClientListItemResponse
    implements Built<ClientListItemResponse, ClientListItemResponseBuilder> {
  @BuiltValueField(wireName: r'kind')
  ClientListItemResponseKindEnum? get kind;
  // enum kindEnum {  REGISTERED,  GUEST,  };

  @BuiltValueField(wireName: r'userId')
  String? get userId;

  @BuiltValueField(wireName: r'guestBookingId')
  String? get guestBookingId;

  @BuiltValueField(wireName: r'displayName')
  String? get displayName;

  @BuiltValueField(wireName: r'avatarUrl')
  String? get avatarUrl;

  @BuiltValueField(wireName: r'lastVisitAt')
  DateTime? get lastVisitAt;

  @BuiltValueField(wireName: r'nextVisitAt')
  DateTime? get nextVisitAt;

  @BuiltValueField(wireName: r'completedVisits')
  int? get completedVisits;

  @BuiltValueField(wireName: r'ratingAvg')
  num? get ratingAvg;

  @BuiltValueField(wireName: r'ratingCount')
  int? get ratingCount;

  @BuiltValueField(wireName: r'blocked')
  bool? get blocked;

  ClientListItemResponse._();

  factory ClientListItemResponse(
          [void updates(ClientListItemResponseBuilder b)]) =
      _$ClientListItemResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClientListItemResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ClientListItemResponse> get serializer =>
      _$ClientListItemResponseSerializer();
}

class _$ClientListItemResponseSerializer
    implements PrimitiveSerializer<ClientListItemResponse> {
  @override
  final Iterable<Type> types = const [
    ClientListItemResponse,
    _$ClientListItemResponse
  ];

  @override
  final String wireName = r'ClientListItemResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClientListItemResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.kind != null) {
      yield r'kind';
      yield serializers.serialize(
        object.kind,
        specifiedType: const FullType(ClientListItemResponseKindEnum),
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
    if (object.completedVisits != null) {
      yield r'completedVisits';
      yield serializers.serialize(
        object.completedVisits,
        specifiedType: const FullType(int),
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
    if (object.blocked != null) {
      yield r'blocked';
      yield serializers.serialize(
        object.blocked,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClientListItemResponse object, {
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
    required ClientListItemResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ClientListItemResponseKindEnum),
          ) as ClientListItemResponseKindEnum;
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
        case r'completedVisits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.completedVisits = valueDes;
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
        case r'blocked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.blocked = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ClientListItemResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClientListItemResponseBuilder();
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

class ClientListItemResponseKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'REGISTERED')
  static const ClientListItemResponseKindEnum REGISTERED =
      _$clientListItemResponseKindEnum_REGISTERED;
  @BuiltValueEnumConst(wireName: r'GUEST')
  static const ClientListItemResponseKindEnum GUEST =
      _$clientListItemResponseKindEnum_GUEST;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const ClientListItemResponseKindEnum unknownDefaultOpenApi =
      _$clientListItemResponseKindEnum_unknownDefaultOpenApi;

  static Serializer<ClientListItemResponseKindEnum> get serializer =>
      _$clientListItemResponseKindEnumSerializer;

  const ClientListItemResponseKindEnum._(String name) : super(name);

  static BuiltSet<ClientListItemResponseKindEnum> get values =>
      _$clientListItemResponseKindEnumValues;
  static ClientListItemResponseKindEnum valueOf(String name) =>
      _$clientListItemResponseKindEnumValueOf(name);
}
