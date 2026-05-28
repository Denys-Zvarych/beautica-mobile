// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_file_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MediaFileResponseEntityTypeEnum _$mediaFileResponseEntityTypeEnum_USER =
    const MediaFileResponseEntityTypeEnum._('USER');
const MediaFileResponseEntityTypeEnum _$mediaFileResponseEntityTypeEnum_SALON =
    const MediaFileResponseEntityTypeEnum._('SALON');
const MediaFileResponseEntityTypeEnum _$mediaFileResponseEntityTypeEnum_MASTER =
    const MediaFileResponseEntityTypeEnum._('MASTER');

MediaFileResponseEntityTypeEnum _$mediaFileResponseEntityTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'USER':
      return _$mediaFileResponseEntityTypeEnum_USER;
    case 'SALON':
      return _$mediaFileResponseEntityTypeEnum_SALON;
    case 'MASTER':
      return _$mediaFileResponseEntityTypeEnum_MASTER;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MediaFileResponseEntityTypeEnum>
    _$mediaFileResponseEntityTypeEnumValues = BuiltSet<
        MediaFileResponseEntityTypeEnum>(const <MediaFileResponseEntityTypeEnum>[
  _$mediaFileResponseEntityTypeEnum_USER,
  _$mediaFileResponseEntityTypeEnum_SALON,
  _$mediaFileResponseEntityTypeEnum_MASTER,
]);

const MediaFileResponseMediaTypeEnum _$mediaFileResponseMediaTypeEnum_AVATAR =
    const MediaFileResponseMediaTypeEnum._('AVATAR');
const MediaFileResponseMediaTypeEnum
    _$mediaFileResponseMediaTypeEnum_PORTFOLIO =
    const MediaFileResponseMediaTypeEnum._('PORTFOLIO');

MediaFileResponseMediaTypeEnum _$mediaFileResponseMediaTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'AVATAR':
      return _$mediaFileResponseMediaTypeEnum_AVATAR;
    case 'PORTFOLIO':
      return _$mediaFileResponseMediaTypeEnum_PORTFOLIO;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MediaFileResponseMediaTypeEnum>
    _$mediaFileResponseMediaTypeEnumValues = BuiltSet<
        MediaFileResponseMediaTypeEnum>(const <MediaFileResponseMediaTypeEnum>[
  _$mediaFileResponseMediaTypeEnum_AVATAR,
  _$mediaFileResponseMediaTypeEnum_PORTFOLIO,
]);

Serializer<MediaFileResponseEntityTypeEnum>
    _$mediaFileResponseEntityTypeEnumSerializer =
    _$MediaFileResponseEntityTypeEnumSerializer();
Serializer<MediaFileResponseMediaTypeEnum>
    _$mediaFileResponseMediaTypeEnumSerializer =
    _$MediaFileResponseMediaTypeEnumSerializer();

class _$MediaFileResponseEntityTypeEnumSerializer
    implements PrimitiveSerializer<MediaFileResponseEntityTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'USER': 'USER',
    'SALON': 'SALON',
    'MASTER': 'MASTER',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'USER': 'USER',
    'SALON': 'SALON',
    'MASTER': 'MASTER',
  };

  @override
  final Iterable<Type> types = const <Type>[MediaFileResponseEntityTypeEnum];
  @override
  final String wireName = 'MediaFileResponseEntityTypeEnum';

  @override
  Object serialize(
          Serializers serializers, MediaFileResponseEntityTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  MediaFileResponseEntityTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MediaFileResponseEntityTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$MediaFileResponseMediaTypeEnumSerializer
    implements PrimitiveSerializer<MediaFileResponseMediaTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'AVATAR': 'AVATAR',
    'PORTFOLIO': 'PORTFOLIO',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'AVATAR': 'AVATAR',
    'PORTFOLIO': 'PORTFOLIO',
  };

  @override
  final Iterable<Type> types = const <Type>[MediaFileResponseMediaTypeEnum];
  @override
  final String wireName = 'MediaFileResponseMediaTypeEnum';

  @override
  Object serialize(
          Serializers serializers, MediaFileResponseMediaTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  MediaFileResponseMediaTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      MediaFileResponseMediaTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$MediaFileResponse extends MediaFileResponse {
  @override
  final String? id;
  @override
  final MediaFileResponseEntityTypeEnum? entityType;
  @override
  final String? entityId;
  @override
  final MediaFileResponseMediaTypeEnum? mediaType;
  @override
  final String? url;
  @override
  final DateTime? createdAt;

  factory _$MediaFileResponse(
          [void Function(MediaFileResponseBuilder)? updates]) =>
      (MediaFileResponseBuilder()..update(updates))._build();

  _$MediaFileResponse._(
      {this.id,
      this.entityType,
      this.entityId,
      this.mediaType,
      this.url,
      this.createdAt})
      : super._();
  @override
  MediaFileResponse rebuild(void Function(MediaFileResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MediaFileResponseBuilder toBuilder() =>
      MediaFileResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MediaFileResponse &&
        id == other.id &&
        entityType == other.entityType &&
        entityId == other.entityId &&
        mediaType == other.mediaType &&
        url == other.url &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, entityType.hashCode);
    _$hash = $jc(_$hash, entityId.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MediaFileResponse')
          ..add('id', id)
          ..add('entityType', entityType)
          ..add('entityId', entityId)
          ..add('mediaType', mediaType)
          ..add('url', url)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class MediaFileResponseBuilder
    implements Builder<MediaFileResponse, MediaFileResponseBuilder> {
  _$MediaFileResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  MediaFileResponseEntityTypeEnum? _entityType;
  MediaFileResponseEntityTypeEnum? get entityType => _$this._entityType;
  set entityType(MediaFileResponseEntityTypeEnum? entityType) =>
      _$this._entityType = entityType;

  String? _entityId;
  String? get entityId => _$this._entityId;
  set entityId(String? entityId) => _$this._entityId = entityId;

  MediaFileResponseMediaTypeEnum? _mediaType;
  MediaFileResponseMediaTypeEnum? get mediaType => _$this._mediaType;
  set mediaType(MediaFileResponseMediaTypeEnum? mediaType) =>
      _$this._mediaType = mediaType;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  MediaFileResponseBuilder() {
    MediaFileResponse._defaults(this);
  }

  MediaFileResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _entityType = $v.entityType;
      _entityId = $v.entityId;
      _mediaType = $v.mediaType;
      _url = $v.url;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MediaFileResponse other) {
    _$v = other as _$MediaFileResponse;
  }

  @override
  void update(void Function(MediaFileResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MediaFileResponse build() => _build();

  _$MediaFileResponse _build() {
    final _$result = _$v ??
        _$MediaFileResponse._(
          id: id,
          entityType: entityType,
          entityId: entityId,
          mediaType: mediaType,
          url: url,
          createdAt: createdAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
