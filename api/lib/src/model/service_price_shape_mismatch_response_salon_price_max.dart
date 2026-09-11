//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'dart:core';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/any_of.dart';

part 'service_price_shape_mismatch_response_salon_price_max.g.dart';

/// The salon definition's ceiling; null when the salon prices FIXED.
@BuiltValue()
abstract class ServicePriceShapeMismatchResponseSalonPriceMax
    implements
        Built<ServicePriceShapeMismatchResponseSalonPriceMax,
            ServicePriceShapeMismatchResponseSalonPriceMaxBuilder> {
  /// Any Of [String], [num]
  AnyOf get anyOf;

  ServicePriceShapeMismatchResponseSalonPriceMax._();

  factory ServicePriceShapeMismatchResponseSalonPriceMax(
          [void updates(
              ServicePriceShapeMismatchResponseSalonPriceMaxBuilder b)]) =
      _$ServicePriceShapeMismatchResponseSalonPriceMax;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(
          ServicePriceShapeMismatchResponseSalonPriceMaxBuilder b) =>
      b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServicePriceShapeMismatchResponseSalonPriceMax>
      get serializer =>
          _$ServicePriceShapeMismatchResponseSalonPriceMaxSerializer();
}

class _$ServicePriceShapeMismatchResponseSalonPriceMaxSerializer
    implements
        PrimitiveSerializer<ServicePriceShapeMismatchResponseSalonPriceMax> {
  @override
  final Iterable<Type> types = const [
    ServicePriceShapeMismatchResponseSalonPriceMax,
    _$ServicePriceShapeMismatchResponseSalonPriceMax
  ];

  @override
  final String wireName = r'ServicePriceShapeMismatchResponseSalonPriceMax';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServicePriceShapeMismatchResponseSalonPriceMax object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    ServicePriceShapeMismatchResponseSalonPriceMax object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final anyOf = object.anyOf;
    return serializers.serialize(anyOf,
        specifiedType: FullType(
            AnyOf, anyOf.valueTypes.map((type) => FullType(type)).toList()))!;
  }

  @override
  ServicePriceShapeMismatchResponseSalonPriceMax deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServicePriceShapeMismatchResponseSalonPriceMaxBuilder();
    Object? anyOfDataSrc;
    final targetType = const FullType(AnyOf, [
      FullType(num),
      FullType(String),
    ]);
    anyOfDataSrc = serialized;
    result.anyOf = serializers.deserialize(anyOfDataSrc,
        specifiedType: targetType) as AnyOf;
    return result.build();
  }
}
