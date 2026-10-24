//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'category_ref.g.dart';

/// CategoryRef
///
/// Properties:
/// * [id]
/// * [name]
/// * [key] - Category key shared with ServiceSummaryDto.category (phase 383).
@BuiltValue()
abstract class CategoryRef implements Built<CategoryRef, CategoryRefBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// Category key shared with ServiceSummaryDto.category (phase 383).
  @BuiltValueField(wireName: r'key')
  String get key;

  CategoryRef._();

  factory CategoryRef([void updates(CategoryRefBuilder b)]) = _$CategoryRef;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CategoryRefBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CategoryRef> get serializer => _$CategoryRefSerializer();
}

class _$CategoryRefSerializer implements PrimitiveSerializer<CategoryRef> {
  @override
  final Iterable<Type> types = const [CategoryRef, _$CategoryRef];

  @override
  final String wireName = r'CategoryRef';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CategoryRef object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'key';
    yield serializers.serialize(
      object.key,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CategoryRef object, {
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
    required CategoryRefBuilder result,
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
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.key = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CategoryRef deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CategoryRefBuilder();
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
