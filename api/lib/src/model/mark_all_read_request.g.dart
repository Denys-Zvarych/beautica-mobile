// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mark_all_read_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MarkAllReadRequest extends MarkAllReadRequest {
  @override
  final DateTime? upTo;

  factory _$MarkAllReadRequest(
          [void Function(MarkAllReadRequestBuilder)? updates]) =>
      (MarkAllReadRequestBuilder()..update(updates))._build();

  _$MarkAllReadRequest._({this.upTo}) : super._();
  @override
  MarkAllReadRequest rebuild(
          void Function(MarkAllReadRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MarkAllReadRequestBuilder toBuilder() =>
      MarkAllReadRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MarkAllReadRequest && upTo == other.upTo;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, upTo.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MarkAllReadRequest')
          ..add('upTo', upTo))
        .toString();
  }
}

class MarkAllReadRequestBuilder
    implements Builder<MarkAllReadRequest, MarkAllReadRequestBuilder> {
  _$MarkAllReadRequest? _$v;

  DateTime? _upTo;
  DateTime? get upTo => _$this._upTo;
  set upTo(DateTime? upTo) => _$this._upTo = upTo;

  MarkAllReadRequestBuilder() {
    MarkAllReadRequest._defaults(this);
  }

  MarkAllReadRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _upTo = $v.upTo;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MarkAllReadRequest other) {
    _$v = other as _$MarkAllReadRequest;
  }

  @override
  void update(void Function(MarkAllReadRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MarkAllReadRequest build() => _build();

  _$MarkAllReadRequest _build() {
    final _$result = _$v ??
        _$MarkAllReadRequest._(
          upTo: upTo,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
