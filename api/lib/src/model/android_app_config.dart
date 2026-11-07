//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'android_app_config.g.dart';

/// Android version window
///
/// Properties:
/// * [minVersionCode] - Minimum supported Android versionCode (pubspec +N build number)
/// * [latestVersionCode] - Latest Android versionCode on Google Play
/// * [storeUrl] - Google Play listing URL
@BuiltValue()
abstract class AndroidAppConfig
    implements Built<AndroidAppConfig, AndroidAppConfigBuilder> {
  /// Minimum supported Android versionCode (pubspec +N build number)
  @BuiltValueField(wireName: r'minVersionCode')
  int get minVersionCode;

  /// Latest Android versionCode on Google Play
  @BuiltValueField(wireName: r'latestVersionCode')
  int get latestVersionCode;

  /// Google Play listing URL
  @BuiltValueField(wireName: r'storeUrl')
  String get storeUrl;

  AndroidAppConfig._();

  factory AndroidAppConfig([void updates(AndroidAppConfigBuilder b)]) =
      _$AndroidAppConfig;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AndroidAppConfigBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AndroidAppConfig> get serializer =>
      _$AndroidAppConfigSerializer();
}

class _$AndroidAppConfigSerializer
    implements PrimitiveSerializer<AndroidAppConfig> {
  @override
  final Iterable<Type> types = const [AndroidAppConfig, _$AndroidAppConfig];

  @override
  final String wireName = r'AndroidAppConfig';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AndroidAppConfig object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'minVersionCode';
    yield serializers.serialize(
      object.minVersionCode,
      specifiedType: const FullType(int),
    );
    yield r'latestVersionCode';
    yield serializers.serialize(
      object.latestVersionCode,
      specifiedType: const FullType(int),
    );
    yield r'storeUrl';
    yield serializers.serialize(
      object.storeUrl,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AndroidAppConfig object, {
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
    required AndroidAppConfigBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'minVersionCode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.minVersionCode = valueDes;
          break;
        case r'latestVersionCode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.latestVersionCode = valueDes;
          break;
        case r'storeUrl':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.storeUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AndroidAppConfig deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AndroidAppConfigBuilder();
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
