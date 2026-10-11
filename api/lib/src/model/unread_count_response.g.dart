// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unread_count_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UnreadCountResponse extends UnreadCountResponse {
  @override
  final int? count;

  factory _$UnreadCountResponse(
          [void Function(UnreadCountResponseBuilder)? updates]) =>
      (UnreadCountResponseBuilder()..update(updates))._build();

  _$UnreadCountResponse._({this.count}) : super._();
  @override
  UnreadCountResponse rebuild(
          void Function(UnreadCountResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UnreadCountResponseBuilder toBuilder() =>
      UnreadCountResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UnreadCountResponse && count == other.count;
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
    return (newBuiltValueToStringHelper(r'UnreadCountResponse')
          ..add('count', count))
        .toString();
  }
}

class UnreadCountResponseBuilder
    implements Builder<UnreadCountResponse, UnreadCountResponseBuilder> {
  _$UnreadCountResponse? _$v;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  UnreadCountResponseBuilder() {
    UnreadCountResponse._defaults(this);
  }

  UnreadCountResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _count = $v.count;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UnreadCountResponse other) {
    _$v = other as _$UnreadCountResponse;
  }

  @override
  void update(void Function(UnreadCountResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UnreadCountResponse build() => _build();

  _$UnreadCountResponse _build() {
    final _$result = _$v ??
        _$UnreadCountResponse._(
          count: count,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
