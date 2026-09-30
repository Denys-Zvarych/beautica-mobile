// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mark_all_read_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MarkAllReadResponse extends MarkAllReadResponse {
  @override
  final int? updated;

  factory _$MarkAllReadResponse(
          [void Function(MarkAllReadResponseBuilder)? updates]) =>
      (MarkAllReadResponseBuilder()..update(updates))._build();

  _$MarkAllReadResponse._({this.updated}) : super._();
  @override
  MarkAllReadResponse rebuild(
          void Function(MarkAllReadResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MarkAllReadResponseBuilder toBuilder() =>
      MarkAllReadResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MarkAllReadResponse && updated == other.updated;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, updated.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MarkAllReadResponse')
          ..add('updated', updated))
        .toString();
  }
}

class MarkAllReadResponseBuilder
    implements Builder<MarkAllReadResponse, MarkAllReadResponseBuilder> {
  _$MarkAllReadResponse? _$v;

  int? _updated;
  int? get updated => _$this._updated;
  set updated(int? updated) => _$this._updated = updated;

  MarkAllReadResponseBuilder() {
    MarkAllReadResponse._defaults(this);
  }

  MarkAllReadResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _updated = $v.updated;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MarkAllReadResponse other) {
    _$v = other as _$MarkAllReadResponse;
  }

  @override
  void update(void Function(MarkAllReadResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MarkAllReadResponse build() => _build();

  _$MarkAllReadResponse _build() {
    final _$result = _$v ??
        _$MarkAllReadResponse._(
          updated: updated,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
