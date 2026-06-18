// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const FavoriteResponseTargetTypeEnum _$favoriteResponseTargetTypeEnum_MASTER =
    const FavoriteResponseTargetTypeEnum._('MASTER');
const FavoriteResponseTargetTypeEnum _$favoriteResponseTargetTypeEnum_SALON =
    const FavoriteResponseTargetTypeEnum._('SALON');

FavoriteResponseTargetTypeEnum _$favoriteResponseTargetTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'MASTER':
      return _$favoriteResponseTargetTypeEnum_MASTER;
    case 'SALON':
      return _$favoriteResponseTargetTypeEnum_SALON;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<FavoriteResponseTargetTypeEnum>
    _$favoriteResponseTargetTypeEnumValues = BuiltSet<
        FavoriteResponseTargetTypeEnum>(const <FavoriteResponseTargetTypeEnum>[
  _$favoriteResponseTargetTypeEnum_MASTER,
  _$favoriteResponseTargetTypeEnum_SALON,
]);

Serializer<FavoriteResponseTargetTypeEnum>
    _$favoriteResponseTargetTypeEnumSerializer =
    _$FavoriteResponseTargetTypeEnumSerializer();

class _$FavoriteResponseTargetTypeEnumSerializer
    implements PrimitiveSerializer<FavoriteResponseTargetTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'MASTER': 'MASTER',
    'SALON': 'SALON',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'MASTER': 'MASTER',
    'SALON': 'SALON',
  };

  @override
  final Iterable<Type> types = const <Type>[FavoriteResponseTargetTypeEnum];
  @override
  final String wireName = 'FavoriteResponseTargetTypeEnum';

  @override
  Object serialize(
          Serializers serializers, FavoriteResponseTargetTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  FavoriteResponseTargetTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      FavoriteResponseTargetTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$FavoriteResponse extends FavoriteResponse {
  @override
  final String? id;
  @override
  final FavoriteResponseTargetTypeEnum? targetType;
  @override
  final String? targetId;
  @override
  final DateTime? createdAt;

  factory _$FavoriteResponse(
          [void Function(FavoriteResponseBuilder)? updates]) =>
      (FavoriteResponseBuilder()..update(updates))._build();

  _$FavoriteResponse._(
      {this.id, this.targetType, this.targetId, this.createdAt})
      : super._();
  @override
  FavoriteResponse rebuild(void Function(FavoriteResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  FavoriteResponseBuilder toBuilder() =>
      FavoriteResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is FavoriteResponse &&
        id == other.id &&
        targetType == other.targetType &&
        targetId == other.targetId &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, targetType.hashCode);
    _$hash = $jc(_$hash, targetId.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'FavoriteResponse')
          ..add('id', id)
          ..add('targetType', targetType)
          ..add('targetId', targetId)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class FavoriteResponseBuilder
    implements Builder<FavoriteResponse, FavoriteResponseBuilder> {
  _$FavoriteResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  FavoriteResponseTargetTypeEnum? _targetType;
  FavoriteResponseTargetTypeEnum? get targetType => _$this._targetType;
  set targetType(FavoriteResponseTargetTypeEnum? targetType) =>
      _$this._targetType = targetType;

  String? _targetId;
  String? get targetId => _$this._targetId;
  set targetId(String? targetId) => _$this._targetId = targetId;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  FavoriteResponseBuilder() {
    FavoriteResponse._defaults(this);
  }

  FavoriteResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _targetType = $v.targetType;
      _targetId = $v.targetId;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(FavoriteResponse other) {
    _$v = other as _$FavoriteResponse;
  }

  @override
  void update(void Function(FavoriteResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  FavoriteResponse build() => _build();

  _$FavoriteResponse _build() {
    final _$result = _$v ??
        _$FavoriteResponse._(
          id: id,
          targetType: targetType,
          targetId: targetId,
          createdAt: createdAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
