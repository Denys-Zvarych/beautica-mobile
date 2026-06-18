//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/location_filter.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'salon_search_request.g.dart';

/// SalonSearchRequest
///
/// Properties:
/// * [location]
/// * [category]
/// * [page]
/// * [size]
@BuiltValue()
abstract class SalonSearchRequest
    implements Built<SalonSearchRequest, SalonSearchRequestBuilder> {
  @BuiltValueField(wireName: r'location')
  LocationFilter? get location;

  @BuiltValueField(wireName: r'category')
  String? get category;

  @BuiltValueField(wireName: r'page')
  int? get page;

  @BuiltValueField(wireName: r'size')
  int? get size;

  SalonSearchRequest._();

  factory SalonSearchRequest([void updates(SalonSearchRequestBuilder b)]) =
      _$SalonSearchRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SalonSearchRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SalonSearchRequest> get serializer =>
      _$SalonSearchRequestSerializer();
}

class _$SalonSearchRequestSerializer
    implements PrimitiveSerializer<SalonSearchRequest> {
  @override
  final Iterable<Type> types = const [SalonSearchRequest, _$SalonSearchRequest];

  @override
  final String wireName = r'SalonSearchRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SalonSearchRequest object, {
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
    SalonSearchRequest object, {
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
    required SalonSearchRequestBuilder result,
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
  SalonSearchRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SalonSearchRequestBuilder();
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
