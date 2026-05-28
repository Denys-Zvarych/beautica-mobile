//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'media_file_response.g.dart';

/// MediaFileResponse
///
/// Properties:
/// * [id]
/// * [entityType]
/// * [entityId]
/// * [mediaType]
/// * [url]
/// * [createdAt]
@BuiltValue()
abstract class MediaFileResponse
    implements Built<MediaFileResponse, MediaFileResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String? get id;

  @BuiltValueField(wireName: r'entityType')
  MediaFileResponseEntityTypeEnum? get entityType;
  // enum entityTypeEnum {  USER,  SALON,  MASTER,  };

  @BuiltValueField(wireName: r'entityId')
  String? get entityId;

  @BuiltValueField(wireName: r'mediaType')
  MediaFileResponseMediaTypeEnum? get mediaType;
  // enum mediaTypeEnum {  AVATAR,  PORTFOLIO,  };

  @BuiltValueField(wireName: r'url')
  String? get url;

  @BuiltValueField(wireName: r'createdAt')
  DateTime? get createdAt;

  MediaFileResponse._();

  factory MediaFileResponse([void updates(MediaFileResponseBuilder b)]) =
      _$MediaFileResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MediaFileResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MediaFileResponse> get serializer =>
      _$MediaFileResponseSerializer();
}

class _$MediaFileResponseSerializer
    implements PrimitiveSerializer<MediaFileResponse> {
  @override
  final Iterable<Type> types = const [MediaFileResponse, _$MediaFileResponse];

  @override
  final String wireName = r'MediaFileResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MediaFileResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.id != null) {
      yield r'id';
      yield serializers.serialize(
        object.id,
        specifiedType: const FullType(String),
      );
    }
    if (object.entityType != null) {
      yield r'entityType';
      yield serializers.serialize(
        object.entityType,
        specifiedType: const FullType(MediaFileResponseEntityTypeEnum),
      );
    }
    if (object.entityId != null) {
      yield r'entityId';
      yield serializers.serialize(
        object.entityId,
        specifiedType: const FullType(String),
      );
    }
    if (object.mediaType != null) {
      yield r'mediaType';
      yield serializers.serialize(
        object.mediaType,
        specifiedType: const FullType(MediaFileResponseMediaTypeEnum),
      );
    }
    if (object.url != null) {
      yield r'url';
      yield serializers.serialize(
        object.url,
        specifiedType: const FullType(String),
      );
    }
    if (object.createdAt != null) {
      yield r'createdAt';
      yield serializers.serialize(
        object.createdAt,
        specifiedType: const FullType(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    MediaFileResponse object, {
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
    required MediaFileResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'entityType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaFileResponseEntityTypeEnum),
          ) as MediaFileResponseEntityTypeEnum;
          result.entityType = valueDes;
          break;
        case r'entityId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.entityId = valueDes;
          break;
        case r'mediaType':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MediaFileResponseMediaTypeEnum),
          ) as MediaFileResponseMediaTypeEnum;
          result.mediaType = valueDes;
          break;
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        case r'createdAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MediaFileResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MediaFileResponseBuilder();
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

class MediaFileResponseEntityTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'USER')
  static const MediaFileResponseEntityTypeEnum USER =
      _$mediaFileResponseEntityTypeEnum_USER;
  @BuiltValueEnumConst(wireName: r'SALON')
  static const MediaFileResponseEntityTypeEnum SALON =
      _$mediaFileResponseEntityTypeEnum_SALON;
  @BuiltValueEnumConst(wireName: r'MASTER')
  static const MediaFileResponseEntityTypeEnum MASTER =
      _$mediaFileResponseEntityTypeEnum_MASTER;

  static Serializer<MediaFileResponseEntityTypeEnum> get serializer =>
      _$mediaFileResponseEntityTypeEnumSerializer;

  const MediaFileResponseEntityTypeEnum._(String name) : super(name);

  static BuiltSet<MediaFileResponseEntityTypeEnum> get values =>
      _$mediaFileResponseEntityTypeEnumValues;
  static MediaFileResponseEntityTypeEnum valueOf(String name) =>
      _$mediaFileResponseEntityTypeEnumValueOf(name);
}

class MediaFileResponseMediaTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'AVATAR')
  static const MediaFileResponseMediaTypeEnum AVATAR =
      _$mediaFileResponseMediaTypeEnum_AVATAR;
  @BuiltValueEnumConst(wireName: r'PORTFOLIO')
  static const MediaFileResponseMediaTypeEnum PORTFOLIO =
      _$mediaFileResponseMediaTypeEnum_PORTFOLIO;

  static Serializer<MediaFileResponseMediaTypeEnum> get serializer =>
      _$mediaFileResponseMediaTypeEnumSerializer;

  const MediaFileResponseMediaTypeEnum._(String name) : super(name);

  static BuiltSet<MediaFileResponseMediaTypeEnum> get values =>
      _$mediaFileResponseMediaTypeEnumValues;
  static MediaFileResponseMediaTypeEnum valueOf(String name) =>
      _$mediaFileResponseMediaTypeEnumValueOf(name);
}
