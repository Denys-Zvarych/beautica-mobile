//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'search_suggestion_response.g.dart';

/// SearchSuggestionResponse
///
/// Properties:
/// * [type]
/// * [label]
/// * [categoryKey]
/// * [serviceTypeSlug]
@BuiltValue()
abstract class SearchSuggestionResponse
    implements
        Built<SearchSuggestionResponse, SearchSuggestionResponseBuilder> {
  @BuiltValueField(wireName: r'type')
  SearchSuggestionResponseTypeEnum? get type;
  // enum typeEnum {  CATEGORY,  SERVICE,  };

  @BuiltValueField(wireName: r'label')
  String? get label;

  @BuiltValueField(wireName: r'categoryKey')
  String? get categoryKey;

  @BuiltValueField(wireName: r'serviceTypeSlug')
  String? get serviceTypeSlug;

  SearchSuggestionResponse._();

  factory SearchSuggestionResponse(
          [void updates(SearchSuggestionResponseBuilder b)]) =
      _$SearchSuggestionResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SearchSuggestionResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SearchSuggestionResponse> get serializer =>
      _$SearchSuggestionResponseSerializer();
}

class _$SearchSuggestionResponseSerializer
    implements PrimitiveSerializer<SearchSuggestionResponse> {
  @override
  final Iterable<Type> types = const [
    SearchSuggestionResponse,
    _$SearchSuggestionResponse
  ];

  @override
  final String wireName = r'SearchSuggestionResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SearchSuggestionResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.type != null) {
      yield r'type';
      yield serializers.serialize(
        object.type,
        specifiedType: const FullType(SearchSuggestionResponseTypeEnum),
      );
    }
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType(String),
      );
    }
    if (object.categoryKey != null) {
      yield r'categoryKey';
      yield serializers.serialize(
        object.categoryKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.serviceTypeSlug != null) {
      yield r'serviceTypeSlug';
      yield serializers.serialize(
        object.serviceTypeSlug,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SearchSuggestionResponse object, {
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
    required SearchSuggestionResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SearchSuggestionResponseTypeEnum),
          ) as SearchSuggestionResponseTypeEnum;
          result.type = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.label = valueDes;
          break;
        case r'categoryKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.categoryKey = valueDes;
          break;
        case r'serviceTypeSlug':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceTypeSlug = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SearchSuggestionResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SearchSuggestionResponseBuilder();
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

class SearchSuggestionResponseTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'CATEGORY')
  static const SearchSuggestionResponseTypeEnum CATEGORY =
      _$searchSuggestionResponseTypeEnum_CATEGORY;
  @BuiltValueEnumConst(wireName: r'SERVICE')
  static const SearchSuggestionResponseTypeEnum SERVICE =
      _$searchSuggestionResponseTypeEnum_SERVICE;
  @BuiltValueEnumConst(wireName: r'unknown_default_open_api', fallback: true)
  static const SearchSuggestionResponseTypeEnum unknownDefaultOpenApi =
      _$searchSuggestionResponseTypeEnum_unknownDefaultOpenApi;

  static Serializer<SearchSuggestionResponseTypeEnum> get serializer =>
      _$searchSuggestionResponseTypeEnumSerializer;

  const SearchSuggestionResponseTypeEnum._(String name) : super(name);

  static BuiltSet<SearchSuggestionResponseTypeEnum> get values =>
      _$searchSuggestionResponseTypeEnumValues;
  static SearchSuggestionResponseTypeEnum valueOf(String name) =>
      _$searchSuggestionResponseTypeEnumValueOf(name);
}
