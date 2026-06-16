//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'location_filter.g.dart';

/// LocationFilter
///
/// Properties:
/// * [cityId]
/// * [districtId]
@BuiltValue()
abstract class LocationFilter
    implements Built<LocationFilter, LocationFilterBuilder> {
  @BuiltValueField(wireName: r'cityId')
  String? get cityId;

  @BuiltValueField(wireName: r'districtId')
  String? get districtId;

  LocationFilter._();

  factory LocationFilter([void updates(LocationFilterBuilder b)]) =
      _$LocationFilter;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LocationFilterBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LocationFilter> get serializer =>
      _$LocationFilterSerializer();
}

class _$LocationFilterSerializer
    implements PrimitiveSerializer<LocationFilter> {
  @override
  final Iterable<Type> types = const [LocationFilter, _$LocationFilter];

  @override
  final String wireName = r'LocationFilter';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LocationFilter object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.cityId != null) {
      yield r'cityId';
      yield serializers.serialize(
        object.cityId,
        specifiedType: const FullType(String),
      );
    }
    if (object.districtId != null) {
      yield r'districtId';
      yield serializers.serialize(
        object.districtId,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    LocationFilter object, {
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
    required LocationFilterBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'cityId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cityId = valueDes;
          break;
        case r'districtId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.districtId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LocationFilter deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LocationFilterBuilder();
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
