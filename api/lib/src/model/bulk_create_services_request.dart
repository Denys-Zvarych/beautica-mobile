//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/bulk_service_item_request.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bulk_create_services_request.g.dart';

/// BulkCreateServicesRequest
///
/// Properties:
/// * [items]
@BuiltValue()
abstract class BulkCreateServicesRequest
    implements
        Built<BulkCreateServicesRequest, BulkCreateServicesRequestBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<BulkServiceItemRequest> get items;

  BulkCreateServicesRequest._();

  factory BulkCreateServicesRequest(
          [void updates(BulkCreateServicesRequestBuilder b)]) =
      _$BulkCreateServicesRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BulkCreateServicesRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BulkCreateServicesRequest> get serializer =>
      _$BulkCreateServicesRequestSerializer();
}

class _$BulkCreateServicesRequestSerializer
    implements PrimitiveSerializer<BulkCreateServicesRequest> {
  @override
  final Iterable<Type> types = const [
    BulkCreateServicesRequest,
    _$BulkCreateServicesRequest
  ];

  @override
  final String wireName = r'BulkCreateServicesRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BulkCreateServicesRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType:
          const FullType(BuiltList, [FullType(BulkServiceItemRequest)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BulkCreateServicesRequest object, {
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
    required BulkCreateServicesRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(BulkServiceItemRequest)]),
          ) as BuiltList<BulkServiceItemRequest>;
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
  BulkCreateServicesRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BulkCreateServicesRequestBuilder();
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
