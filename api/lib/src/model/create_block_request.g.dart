// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_block_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateBlockRequest extends CreateBlockRequest {
  @override
  final String bookingId;

  factory _$CreateBlockRequest(
          [void Function(CreateBlockRequestBuilder)? updates]) =>
      (CreateBlockRequestBuilder()..update(updates))._build();

  _$CreateBlockRequest._({required this.bookingId}) : super._();
  @override
  CreateBlockRequest rebuild(
          void Function(CreateBlockRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateBlockRequestBuilder toBuilder() =>
      CreateBlockRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateBlockRequest && bookingId == other.bookingId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateBlockRequest')
          ..add('bookingId', bookingId))
        .toString();
  }
}

class CreateBlockRequestBuilder
    implements Builder<CreateBlockRequest, CreateBlockRequestBuilder> {
  _$CreateBlockRequest? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  CreateBlockRequestBuilder() {
    CreateBlockRequest._defaults(this);
  }

  CreateBlockRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateBlockRequest other) {
    _$v = other as _$CreateBlockRequest;
  }

  @override
  void update(void Function(CreateBlockRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateBlockRequest build() => _build();

  _$CreateBlockRequest _build() {
    final _$result = _$v ??
        _$CreateBlockRequest._(
          bookingId: BuiltValueNullFieldError.checkNotNull(
              bookingId, r'CreateBlockRequest', 'bookingId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
