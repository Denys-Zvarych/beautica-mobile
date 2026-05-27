//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'catalog_category_response.g.dart';

/// CatalogCategoryResponse
///
/// Properties:
/// * [id]
/// * [nameUk]
/// * [nameEn]
/// * [sortOrder]
@BuiltValue()
abstract class CatalogCategoryResponse
    implements Built<CatalogCategoryResponse, CatalogCategoryResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'nameUk')
  String? get nameUk;

  @BuiltValueField(wireName: r'nameEn')
  String? get nameEn;

  @BuiltValueField(wireName: r'sortOrder')
  int? get sortOrder;

  CatalogCategoryResponse._();

  factory CatalogCategoryResponse(
          [void updates(CatalogCategoryResponseBuilder b)]) =
      _$CatalogCategoryResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CatalogCategoryResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CatalogCategoryResponse> get serializer =>
      _$CatalogCategoryResponseSerializer();
}

class _$CatalogCategoryResponseSerializer
    implements PrimitiveSerializer<CatalogCategoryResponse> {
  @override
  final Iterable<Type> types = const [
    CatalogCategoryResponse,
    _$CatalogCategoryResponse
  ];

  @override
  final String wireName = r'CatalogCategoryResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CatalogCategoryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.nameUk != null) {
      yield r'nameUk';
      yield serializers.serialize(
        object.nameUk,
        specifiedType: const FullType(String),
      );
    }
    if (object.nameEn != null) {
      yield r'nameEn';
      yield serializers.serialize(
        object.nameEn,
        specifiedType: const FullType(String),
      );
    }
    if (object.sortOrder != null) {
      yield r'sortOrder';
      yield serializers.serialize(
        object.sortOrder,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CatalogCategoryResponse object, {
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
    required CatalogCategoryResponseBuilder result,
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
        case r'nameUk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameUk = valueDes;
          break;
        case r'nameEn':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameEn = valueDes;
          break;
        case r'sortOrder':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sortOrder = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CatalogCategoryResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CatalogCategoryResponseBuilder();
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
