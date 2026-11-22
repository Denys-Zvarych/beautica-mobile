//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/item.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'client_visit_response.g.dart';

/// ClientVisitResponse
///
/// Properties:
/// * [visitKey]
/// * [startsAt]
/// * [salonId]
/// * [items]
@BuiltValue()
abstract class ClientVisitResponse
    implements Built<ClientVisitResponse, ClientVisitResponseBuilder> {
  @BuiltValueField(wireName: r'visitKey')
  String? get visitKey;

  @BuiltValueField(wireName: r'startsAt')
  DateTime? get startsAt;

  @BuiltValueField(wireName: r'salonId')
  String? get salonId;

  @BuiltValueField(wireName: r'items')
  BuiltList<Item>? get items;

  ClientVisitResponse._();

  factory ClientVisitResponse([void updates(ClientVisitResponseBuilder b)]) =
      _$ClientVisitResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ClientVisitResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ClientVisitResponse> get serializer =>
      _$ClientVisitResponseSerializer();
}

class _$ClientVisitResponseSerializer
    implements PrimitiveSerializer<ClientVisitResponse> {
  @override
  final Iterable<Type> types = const [
    ClientVisitResponse,
    _$ClientVisitResponse
  ];

  @override
  final String wireName = r'ClientVisitResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ClientVisitResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.visitKey != null) {
      yield r'visitKey';
      yield serializers.serialize(
        object.visitKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.startsAt != null) {
      yield r'startsAt';
      yield serializers.serialize(
        object.startsAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.salonId != null) {
      yield r'salonId';
      yield serializers.serialize(
        object.salonId,
        specifiedType: const FullType(String),
      );
    }
    if (object.items != null) {
      yield r'items';
      yield serializers.serialize(
        object.items,
        specifiedType: const FullType(BuiltList, [FullType(Item)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ClientVisitResponse object, {
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
    required ClientVisitResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'visitKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.visitKey = valueDes;
          break;
        case r'startsAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startsAt = valueDes;
          break;
        case r'salonId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.salonId = valueDes;
          break;
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Item)]),
          ) as BuiltList<Item>;
          result.items.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ClientVisitResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ClientVisitResponseBuilder();
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
