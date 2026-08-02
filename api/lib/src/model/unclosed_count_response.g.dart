// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unclosed_count_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UnclosedCountResponse extends UnclosedCountResponse {
  @override
  final int? count;

  factory _$UnclosedCountResponse(
          [void Function(UnclosedCountResponseBuilder)? updates]) =>
      (UnclosedCountResponseBuilder()..update(updates))._build();

  _$UnclosedCountResponse._({this.count}) : super._();
  @override
  UnclosedCountResponse rebuild(
          void Function(UnclosedCountResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UnclosedCountResponseBuilder toBuilder() =>
      UnclosedCountResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UnclosedCountResponse && count == other.count;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UnclosedCountResponse')
          ..add('count', count))
        .toString();
  }
}

class UnclosedCountResponseBuilder
    implements Builder<UnclosedCountResponse, UnclosedCountResponseBuilder> {
  _$UnclosedCountResponse? _$v;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  UnclosedCountResponseBuilder() {
    UnclosedCountResponse._defaults(this);
  }

  UnclosedCountResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _count = $v.count;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UnclosedCountResponse other) {
    _$v = other as _$UnclosedCountResponse;
  }

  @override
  void update(void Function(UnclosedCountResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UnclosedCountResponse build() => _build();

  _$UnclosedCountResponse _build() {
    final _$result = _$v ??
        _$UnclosedCountResponse._(
          count: count,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
