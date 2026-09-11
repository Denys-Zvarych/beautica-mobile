//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'dart:core';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/any_of.dart';

part 'service_price_shape_mismatch_response_salon_price_min.g.dart';

/// The salon definition's floor (base_price), in both modes.
@BuiltValue()
abstract class ServicePriceShapeMismatchResponseSalonPriceMin
    implements
        Built<ServicePriceShapeMismatchResponseSalonPriceMin,
            ServicePriceShapeMismatchResponseSalonPriceMinBuilder> {
  /// Any Of [String], [num]
  AnyOf get anyOf;

  ServicePriceShapeMismatchResponseSalonPriceMin._();

  factory ServicePriceShapeMismatchResponseSalonPriceMin(
          [void updates(
              ServicePriceShapeMismatchResponseSalonPriceMinBuilder b)]) =
      _$ServicePriceShapeMismatchResponseSalonPriceMin;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(
          ServicePriceShapeMismatchResponseSalonPriceMinBuilder b) =>
      b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServicePriceShapeMismatchResponseSalonPriceMin>
      get serializer =>
          _$ServicePriceShapeMismatchResponseSalonPriceMinSerializer();
}

class _$ServicePriceShapeMismatchResponseSalonPriceMinSerializer
    implements
        PrimitiveSerializer<ServicePriceShapeMismatchResponseSalonPriceMin> {
  @override
  final Iterable<Type> types = const [
    ServicePriceShapeMismatchResponseSalonPriceMin,
    _$ServicePriceShapeMismatchResponseSalonPriceMin
  ];

  @override
  final String wireName = r'ServicePriceShapeMismatchResponseSalonPriceMin';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServicePriceShapeMismatchResponseSalonPriceMin object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    ServicePriceShapeMismatchResponseSalonPriceMin object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final anyOf = object.anyOf;
    return serializers.serialize(anyOf,
        specifiedType: FullType(
            AnyOf, anyOf.valueTypes.map((type) => FullType(type)).toList()))!;
  }

  @override
  ServicePriceShapeMismatchResponseSalonPriceMin deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServicePriceShapeMismatchResponseSalonPriceMinBuilder();
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
