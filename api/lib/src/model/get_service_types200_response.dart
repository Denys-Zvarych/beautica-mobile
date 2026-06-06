//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/service_type_response.dart';
import 'package:beautica_api/src/model/api_response_list_service_type_response.dart';
import 'package:beautica_api/src/model/api_response_list_platform_service_type_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'get_service_types200_response.g.dart';

/// GetServiceTypes200Response
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
/// * [errors]
@BuiltValue()
abstract class GetServiceTypes200Response
    implements
        Built<GetServiceTypes200Response, GetServiceTypes200ResponseBuilder> {
  /// One Of [ApiResponseListPlatformServiceTypeResponse], [ApiResponseListServiceTypeResponse]
  OneOf get oneOf;

  GetServiceTypes200Response._();

  factory GetServiceTypes200Response(
          [void updates(GetServiceTypes200ResponseBuilder b)]) =
      _$GetServiceTypes200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetServiceTypes200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetServiceTypes200Response> get serializer =>
      _$GetServiceTypes200ResponseSerializer();
}

class _$GetServiceTypes200ResponseSerializer
    implements PrimitiveSerializer<GetServiceTypes200Response> {
  @override
  final Iterable<Type> types = const [
    GetServiceTypes200Response,
    _$GetServiceTypes200Response
  ];

  @override
  final String wireName = r'GetServiceTypes200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetServiceTypes200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    GetServiceTypes200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  GetServiceTypes200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetServiceTypes200ResponseBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(ApiResponseListPlatformServiceTypeResponse),
      FullType(ApiResponseListServiceTypeResponse),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}
