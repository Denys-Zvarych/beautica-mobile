// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'served_master.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ServedMaster extends ServedMaster {
  @override
  final String? masterId;
  @override
  final String? name;
  @override
  final String? avatarUrl;

  factory _$ServedMaster([void Function(ServedMasterBuilder)? updates]) =>
      (ServedMasterBuilder()..update(updates))._build();

  _$ServedMaster._({this.masterId, this.name, this.avatarUrl}) : super._();
  @override
  ServedMaster rebuild(void Function(ServedMasterBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ServedMasterBuilder toBuilder() => ServedMasterBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ServedMaster &&
        masterId == other.masterId &&
        name == other.name &&
        avatarUrl == other.avatarUrl;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ServedMaster')
          ..add('masterId', masterId)
          ..add('name', name)
          ..add('avatarUrl', avatarUrl))
        .toString();
  }
}

class ServedMasterBuilder
    implements Builder<ServedMaster, ServedMasterBuilder> {
  _$ServedMaster? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  ServedMasterBuilder() {
    ServedMaster._defaults(this);
  }

  ServedMasterBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _name = $v.name;
      _avatarUrl = $v.avatarUrl;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ServedMaster other) {
    _$v = other as _$ServedMaster;
  }

  @override
  void update(void Function(ServedMasterBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ServedMaster build() => _build();

  _$ServedMaster _build() {
    final _$result = _$v ??
        _$ServedMaster._(
          masterId: masterId,
          name: name,
          avatarUrl: avatarUrl,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
