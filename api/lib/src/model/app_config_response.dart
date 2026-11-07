//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:beautica_api/src/model/android_app_config.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'app_config_response.g.dart';

/// Client compatibility config
///
/// Properties:
/// * [android]
@BuiltValue()
abstract class AppConfigResponse
    implements Built<AppConfigResponse, AppConfigResponseBuilder> {
  @BuiltValueField(wireName: r'android')
  AndroidAppConfig get android;

  AppConfigResponse._();

  factory AppConfigResponse([void updates(AppConfigResponseBuilder b)]) =
      _$AppConfigResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppConfigResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppConfigResponse> get serializer =>
      _$AppConfigResponseSerializer();
}

class _$AppConfigResponseSerializer
    implements PrimitiveSerializer<AppConfigResponse> {
  @override
  final Iterable<Type> types = const [AppConfigResponse, _$AppConfigResponse];

  @override
  final String wireName = r'AppConfigResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppConfigResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'android';
    yield serializers.serialize(
      object.android,
      specifiedType: const FullType(AndroidAppConfig),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AppConfigResponse object, {
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
    required AppConfigResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'android':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AndroidAppConfig),
          ) as AndroidAppConfig;
          result.android.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppConfigResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppConfigResponseBuilder();
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
