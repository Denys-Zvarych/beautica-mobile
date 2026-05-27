//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/location_filter.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'master_search_request.g.dart';

/// MasterSearchRequest
///
/// Properties:
/// * [location]
/// * [category]
/// * [minPrice]
/// * [maxPrice]
/// * [minRating]
/// * [page]
/// * [size]
@BuiltValue()
abstract class MasterSearchRequest
    implements Built<MasterSearchRequest, MasterSearchRequestBuilder> {
  @BuiltValueField(wireName: r'location')
  LocationFilter? get location;

  @BuiltValueField(wireName: r'category')
  String? get category;

  @BuiltValueField(wireName: r'minPrice')
  num? get minPrice;

  @BuiltValueField(wireName: r'maxPrice')
  num? get maxPrice;

  @BuiltValueField(wireName: r'minRating')
  num? get minRating;

  @BuiltValueField(wireName: r'page')
  int? get page;

  @BuiltValueField(wireName: r'size')
  int? get size;

  MasterSearchRequest._();

  factory MasterSearchRequest([void updates(MasterSearchRequestBuilder b)]) =
      _$MasterSearchRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MasterSearchRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MasterSearchRequest> get serializer =>
      _$MasterSearchRequestSerializer();
}

class _$MasterSearchRequestSerializer
    implements PrimitiveSerializer<MasterSearchRequest> {
  @override
  final Iterable<Type> types = const [
    MasterSearchRequest,
    _$MasterSearchRequest
  ];

  @override
  final String wireName = r'MasterSearchRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MasterSearchRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.location != null) {
      yield r'location';
      yield serializers.serialize(
        object.location,
        specifiedType: const FullType(LocationFilter),
      );
    }
    if (object.category != null) {
      yield r'category';
      yield serializers.serialize(
        object.category,
        specifiedType: const FullType(String),
      );
    }
    if (object.minPrice != null) {
      yield r'minPrice';
      yield serializers.serialize(
        object.minPrice,
        specifiedType: const FullType(num),
      );
    }
    if (object.maxPrice != null) {
      yield r'maxPrice';
      yield serializers.serialize(
        object.maxPrice,
        specifiedType: const FullType(num),
      );
    }
    if (object.minRating != null) {
      yield r'minRating';
      yield serializers.serialize(
        object.minRating,
        specifiedType: const FullType(num),
      );
    }
    if (object.page != null) {
      yield r'page';
      yield serializers.serialize(
        object.page,
        specifiedType: const FullType(int),
      );
    }
    if (object.size != null) {
      yield r'size';
      yield serializers.serialize(
        object.size,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MasterSearchRequest object, {
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
    required MasterSearchRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LocationFilter),
          ) as LocationFilter;
          result.location.replace(valueDes);
          break;
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.category = valueDes;
          break;
        case r'minPrice':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.minPrice = valueDes;
          break;
        case r'maxPrice':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.maxPrice = valueDes;
          break;
        case r'minRating':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.minRating = valueDes;
          break;
        case r'page':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.page = valueDes;
          break;
        case r'size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.size = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MasterSearchRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MasterSearchRequestBuilder();
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
