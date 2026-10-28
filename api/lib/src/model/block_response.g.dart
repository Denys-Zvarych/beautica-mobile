// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'block_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BlockResponseKindEnum _$blockResponseKindEnum_CLIENT =
    const BlockResponseKindEnum._('CLIENT');
const BlockResponseKindEnum _$blockResponseKindEnum_GUEST =
    const BlockResponseKindEnum._('GUEST');
const BlockResponseKindEnum _$blockResponseKindEnum_unknownDefaultOpenApi =
    const BlockResponseKindEnum._('unknownDefaultOpenApi');

BlockResponseKindEnum _$blockResponseKindEnumValueOf(String name) {
  switch (name) {
    case 'CLIENT':
      return _$blockResponseKindEnum_CLIENT;
    case 'GUEST':
      return _$blockResponseKindEnum_GUEST;
    case 'unknownDefaultOpenApi':
      return _$blockResponseKindEnum_unknownDefaultOpenApi;
    default:
      return _$blockResponseKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<BlockResponseKindEnum> _$blockResponseKindEnumValues =
    BuiltSet<BlockResponseKindEnum>(const <BlockResponseKindEnum>[
  _$blockResponseKindEnum_CLIENT,
  _$blockResponseKindEnum_GUEST,
  _$blockResponseKindEnum_unknownDefaultOpenApi,
]);

Serializer<BlockResponseKindEnum> _$blockResponseKindEnumSerializer =
    _$BlockResponseKindEnumSerializer();

class _$BlockResponseKindEnumSerializer
    implements PrimitiveSerializer<BlockResponseKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'CLIENT': 'CLIENT',
    'GUEST': 'GUEST',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'CLIENT': 'CLIENT',
    'GUEST': 'GUEST',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[BlockResponseKindEnum];
  @override
  final String wireName = 'BlockResponseKindEnum';

  @override
  Object serialize(Serializers serializers, BlockResponseKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BlockResponseKindEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BlockResponseKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BlockResponse extends BlockResponse {
  @override
  final String? id;
  @override
  final BlockResponseKindEnum? kind;
  @override
  final String? displayName;
  @override
  final String? avatarUrl;
  @override
  final String? maskedPhone;
  @override
  final DateTime? createdAt;

  factory _$BlockResponse([void Function(BlockResponseBuilder)? updates]) =>
      (BlockResponseBuilder()..update(updates))._build();

  _$BlockResponse._(
      {this.id,
      this.kind,
      this.displayName,
      this.avatarUrl,
      this.maskedPhone,
      this.createdAt})
      : super._();
  @override
  BlockResponse rebuild(void Function(BlockResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BlockResponseBuilder toBuilder() => BlockResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BlockResponse &&
        id == other.id &&
        kind == other.kind &&
        displayName == other.displayName &&
        avatarUrl == other.avatarUrl &&
        maskedPhone == other.maskedPhone &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, maskedPhone.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BlockResponse')
          ..add('id', id)
          ..add('kind', kind)
          ..add('displayName', displayName)
          ..add('avatarUrl', avatarUrl)
          ..add('maskedPhone', maskedPhone)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class BlockResponseBuilder
    implements Builder<BlockResponse, BlockResponseBuilder> {
  _$BlockResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  BlockResponseKindEnum? _kind;
  BlockResponseKindEnum? get kind => _$this._kind;
  set kind(BlockResponseKindEnum? kind) => _$this._kind = kind;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  String? _maskedPhone;
  String? get maskedPhone => _$this._maskedPhone;
  set maskedPhone(String? maskedPhone) => _$this._maskedPhone = maskedPhone;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  BlockResponseBuilder() {
    BlockResponse._defaults(this);
  }

  BlockResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _kind = $v.kind;
      _displayName = $v.displayName;
      _avatarUrl = $v.avatarUrl;
      _maskedPhone = $v.maskedPhone;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BlockResponse other) {
    _$v = other as _$BlockResponse;
  }

  @override
  void update(void Function(BlockResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BlockResponse build() => _build();

  _$BlockResponse _build() {
    final _$result = _$v ??
        _$BlockResponse._(
          id: id,
          kind: kind,
          displayName: displayName,
          avatarUrl: avatarUrl,
          maskedPhone: maskedPhone,
          createdAt: createdAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
