//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/location_filter.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'search_suggestion_request.g.dart';

/// SearchSuggestionRequest
///
/// Properties:
/// * [q]
/// * [limit]
/// * [location]
@BuiltValue()
abstract class SearchSuggestionRequest
    implements Built<SearchSuggestionRequest, SearchSuggestionRequestBuilder> {
  @BuiltValueField(wireName: r'q')
  String get q;

  @BuiltValueField(wireName: r'limit')
  int? get limit;

  @BuiltValueField(wireName: r'location')
  LocationFilter? get location;

  SearchSuggestionRequest._();

  factory SearchSuggestionRequest(
          [void updates(SearchSuggestionRequestBuilder b)]) =
      _$SearchSuggestionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SearchSuggestionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SearchSuggestionRequest> get serializer =>
      _$SearchSuggestionRequestSerializer();
}

class _$SearchSuggestionRequestSerializer
    implements PrimitiveSerializer<SearchSuggestionRequest> {
  @override
  final Iterable<Type> types = const [
    SearchSuggestionRequest,
    _$SearchSuggestionRequest
  ];

  @override
  final String wireName = r'SearchSuggestionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SearchSuggestionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'q';
    yield serializers.serialize(
      object.q,
      specifiedType: const FullType(String),
    );
    if (object.limit != null) {
      yield r'limit';
      yield serializers.serialize(
        object.limit,
        specifiedType: const FullType(int),
      );
    }
    if (object.location != null) {
      yield r'location';
      yield serializers.serialize(
        object.location,
        specifiedType: const FullType(LocationFilter),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SearchSuggestionRequest object, {
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
    required SearchSuggestionRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'q':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.q = valueDes;
          break;
        case r'limit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.limit = valueDes;
          break;
        case r'location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LocationFilter),
          ) as LocationFilter;
          result.location.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SearchSuggestionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SearchSuggestionRequestBuilder();
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
