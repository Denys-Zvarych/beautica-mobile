// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_favorite_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AddFavoriteRequestTargetTypeEnum
    _$addFavoriteRequestTargetTypeEnum_MASTER =
    const AddFavoriteRequestTargetTypeEnum._('MASTER');
const AddFavoriteRequestTargetTypeEnum
    _$addFavoriteRequestTargetTypeEnum_SALON =
    const AddFavoriteRequestTargetTypeEnum._('SALON');

AddFavoriteRequestTargetTypeEnum _$addFavoriteRequestTargetTypeEnumValueOf(
    String name) {
  switch (name) {
    case 'MASTER':
      return _$addFavoriteRequestTargetTypeEnum_MASTER;
    case 'SALON':
      return _$addFavoriteRequestTargetTypeEnum_SALON;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AddFavoriteRequestTargetTypeEnum>
    _$addFavoriteRequestTargetTypeEnumValues = BuiltSet<
        AddFavoriteRequestTargetTypeEnum>(const <AddFavoriteRequestTargetTypeEnum>[
  _$addFavoriteRequestTargetTypeEnum_MASTER,
  _$addFavoriteRequestTargetTypeEnum_SALON,
]);

Serializer<AddFavoriteRequestTargetTypeEnum>
    _$addFavoriteRequestTargetTypeEnumSerializer =
    _$AddFavoriteRequestTargetTypeEnumSerializer();

class _$AddFavoriteRequestTargetTypeEnumSerializer
    implements PrimitiveSerializer<AddFavoriteRequestTargetTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'MASTER': 'MASTER',
    'SALON': 'SALON',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'MASTER': 'MASTER',
    'SALON': 'SALON',
  };

  @override
  final Iterable<Type> types = const <Type>[AddFavoriteRequestTargetTypeEnum];
  @override
  final String wireName = 'AddFavoriteRequestTargetTypeEnum';

  @override
  Object serialize(
          Serializers serializers, AddFavoriteRequestTargetTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AddFavoriteRequestTargetTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AddFavoriteRequestTargetTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AddFavoriteRequest extends AddFavoriteRequest {
  @override
  final AddFavoriteRequestTargetTypeEnum targetType;
  @override
  final String targetId;

  factory _$AddFavoriteRequest(
          [void Function(AddFavoriteRequestBuilder)? updates]) =>
      (AddFavoriteRequestBuilder()..update(updates))._build();

  _$AddFavoriteRequest._({required this.targetType, required this.targetId})
      : super._();
  @override
  AddFavoriteRequest rebuild(
          void Function(AddFavoriteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AddFavoriteRequestBuilder toBuilder() =>
      AddFavoriteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AddFavoriteRequest &&
        targetType == other.targetType &&
        targetId == other.targetId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, targetType.hashCode);
    _$hash = $jc(_$hash, targetId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AddFavoriteRequest')
          ..add('targetType', targetType)
          ..add('targetId', targetId))
        .toString();
  }
}

class AddFavoriteRequestBuilder
    implements Builder<AddFavoriteRequest, AddFavoriteRequestBuilder> {
  _$AddFavoriteRequest? _$v;

  AddFavoriteRequestTargetTypeEnum? _targetType;
  AddFavoriteRequestTargetTypeEnum? get targetType => _$this._targetType;
  set targetType(AddFavoriteRequestTargetTypeEnum? targetType) =>
      _$this._targetType = targetType;

  String? _targetId;
  String? get targetId => _$this._targetId;
  set targetId(String? targetId) => _$this._targetId = targetId;

  AddFavoriteRequestBuilder() {
    AddFavoriteRequest._defaults(this);
  }

  AddFavoriteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _targetType = $v.targetType;
      _targetId = $v.targetId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AddFavoriteRequest other) {
    _$v = other as _$AddFavoriteRequest;
  }

  @override
  void update(void Function(AddFavoriteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AddFavoriteRequest build() => _build();

  _$AddFavoriteRequest _build() {
    final _$result = _$v ??
        _$AddFavoriteRequest._(
          targetType: BuiltValueNullFieldError.checkNotNull(
              targetType, r'AddFavoriteRequest', 'targetType'),
          targetId: BuiltValueNullFieldError.checkNotNull(
              targetId, r'AddFavoriteRequest', 'targetId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
