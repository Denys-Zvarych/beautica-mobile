//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'favorite_category_view.g.dart';

/// FavoriteCategoryView
///
/// Properties:
/// * [code]
/// * [label]
@BuiltValue()
abstract class FavoriteCategoryView
    implements Built<FavoriteCategoryView, FavoriteCategoryViewBuilder> {
  @BuiltValueField(wireName: r'code')
  String? get code;

  @BuiltValueField(wireName: r'label')
  String? get label;

  FavoriteCategoryView._();

  factory FavoriteCategoryView([void updates(FavoriteCategoryViewBuilder b)]) =
      _$FavoriteCategoryView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(FavoriteCategoryViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<FavoriteCategoryView> get serializer =>
      _$FavoriteCategoryViewSerializer();
}

class _$FavoriteCategoryViewSerializer
    implements PrimitiveSerializer<FavoriteCategoryView> {
  @override
  final Iterable<Type> types = const [
    FavoriteCategoryView,
    _$FavoriteCategoryView
  ];

  @override
  final String wireName = r'FavoriteCategoryView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    FavoriteCategoryView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.code != null) {
      yield r'code';
      yield serializers.serialize(
        object.code,
        specifiedType: const FullType(String),
      );
    }
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    FavoriteCategoryView object, {
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
    required FavoriteCategoryViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  FavoriteCategoryView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = FavoriteCategoryViewBuilder();
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
