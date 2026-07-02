//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/salon_service_category_group.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_service_catalog_response.g.dart';

/// SalonServiceCatalogResponse
///
/// Properties:
/// * [categories]
@BuiltValue()
abstract class SalonServiceCatalogResponse
    implements
        Built<SalonServiceCatalogResponse, SalonServiceCatalogResponseBuilder> {
  @BuiltValueField(wireName: r'categories')
  BuiltList<SalonServiceCategoryGroup>? get categories;

  SalonServiceCatalogResponse._();

  factory SalonServiceCatalogResponse(
          [void updates(SalonServiceCatalogResponseBuilder b)]) =
      _$SalonServiceCatalogResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonServiceCatalogResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonServiceCatalogResponse> get serializer =>
      _$SalonServiceCatalogResponseSerializer();
}

class _$SalonServiceCatalogResponseSerializer
    implements PrimitiveSerializer<SalonServiceCatalogResponse> {
  @override
  final Iterable<Type> types = const [
    SalonServiceCatalogResponse,
    _$SalonServiceCatalogResponse
  ];

  @override
  final String wireName = r'SalonServiceCatalogResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonServiceCatalogResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.categories != null) {
      yield r'categories';
      yield serializers.serialize(
        object.categories,
        specifiedType:
            const FullType(BuiltList, [FullType(SalonServiceCategoryGroup)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SalonServiceCatalogResponse object, {
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
    required SalonServiceCatalogResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'categories':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(
                BuiltList, [FullType(SalonServiceCategoryGroup)]),
          ) as BuiltList<SalonServiceCategoryGroup>;
          result.categories.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SalonServiceCatalogResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonServiceCatalogResponseBuilder();
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
