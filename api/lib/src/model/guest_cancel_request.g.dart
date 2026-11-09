// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_cancel_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestCancelRequest extends GuestCancelRequest {
  @override
  final BuiltList<String>? bookingIds;

  factory _$GuestCancelRequest(
          [void Function(GuestCancelRequestBuilder)? updates]) =>
      (GuestCancelRequestBuilder()..update(updates))._build();

  _$GuestCancelRequest._({this.bookingIds}) : super._();
  @override
  GuestCancelRequest rebuild(
          void Function(GuestCancelRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestCancelRequestBuilder toBuilder() =>
      GuestCancelRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestCancelRequest && bookingIds == other.bookingIds;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingIds.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestCancelRequest')
          ..add('bookingIds', bookingIds))
        .toString();
  }
}

class GuestCancelRequestBuilder
    implements Builder<GuestCancelRequest, GuestCancelRequestBuilder> {
  _$GuestCancelRequest? _$v;

  ListBuilder<String>? _bookingIds;
  ListBuilder<String> get bookingIds =>
      _$this._bookingIds ??= ListBuilder<String>();
  set bookingIds(ListBuilder<String>? bookingIds) =>
      _$this._bookingIds = bookingIds;

  GuestCancelRequestBuilder() {
    GuestCancelRequest._defaults(this);
  }

  GuestCancelRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingIds = $v.bookingIds?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestCancelRequest other) {
    _$v = other as _$GuestCancelRequest;
  }

  @override
  void update(void Function(GuestCancelRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestCancelRequest build() => _build();

  _$GuestCancelRequest _build() {
    _$GuestCancelRequest _$result;
    try {
      _$result = _$v ??
          _$GuestCancelRequest._(
            bookingIds: _bookingIds?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'bookingIds';
        _bookingIds?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'GuestCancelRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
