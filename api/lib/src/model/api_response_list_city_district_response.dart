//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:beautica_api/src/model/city_district_response.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'api_response_list_city_district_response.g.dart';

/// ApiResponseListCityDistrictResponse
///
/// Properties:
/// * [success]
/// * [data]
/// * [message]
@BuiltValue()
abstract class ApiResponseListCityDistrictResponse
    implements
        Built<ApiResponseListCityDistrictResponse,
            ApiResponseListCityDistrictResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  BuiltList<CityDistrictResponse>? get data;

  @BuiltValueField(wireName: r'message')
  String? get message;

  ApiResponseListCityDistrictResponse._();

  factory ApiResponseListCityDistrictResponse(
          [void updates(ApiResponseListCityDistrictResponseBuilder b)]) =
      _$ApiResponseListCityDistrictResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApiResponseListCityDistrictResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApiResponseListCityDistrictResponse> get serializer =>
      _$ApiResponseListCityDistrictResponseSerializer();
}

class _$ApiResponseListCityDistrictResponseSerializer
    implements PrimitiveSerializer<ApiResponseListCityDistrictResponse> {
  @override
  final Iterable<Type> types = const [
    ApiResponseListCityDistrictResponse,
    _$ApiResponseListCityDistrictResponse
  ];

  @override
  final String wireName = r'ApiResponseListCityDistrictResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApiResponseListCityDistrictResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.success != null) {
      yield r'success';
      yield serializers.serialize(
        object.success,
        specifiedType: const FullType(bool),
      );
    }
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType:
            const FullType(BuiltList, [FullType(CityDistrictResponse)]),
      );
    }
    if (object.message != null) {
      yield r'message';
      yield serializers.serialize(
        object.message,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ApiResponseListCityDistrictResponse object, {
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
    required ApiResponseListCityDistrictResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(CityDistrictResponse)]),
          ) as BuiltList<CityDistrictResponse>;
          result.data.replace(valueDes);
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApiResponseListCityDistrictResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApiResponseListCityDistrictResponseBuilder();
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
