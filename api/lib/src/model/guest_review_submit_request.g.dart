// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_review_submit_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestReviewSubmitRequest extends GuestReviewSubmitRequest {
  @override
  final String? turnstileToken;
  @override
  final BuiltList<GuestReviewItemRequest> items;

  factory _$GuestReviewSubmitRequest(
          [void Function(GuestReviewSubmitRequestBuilder)? updates]) =>
      (GuestReviewSubmitRequestBuilder()..update(updates))._build();

  _$GuestReviewSubmitRequest._({this.turnstileToken, required this.items})
      : super._();
  @override
  GuestReviewSubmitRequest rebuild(
          void Function(GuestReviewSubmitRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestReviewSubmitRequestBuilder toBuilder() =>
      GuestReviewSubmitRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestReviewSubmitRequest &&
        turnstileToken == other.turnstileToken &&
        items == other.items;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, turnstileToken.hashCode);
    _$hash = $jc(_$hash, items.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestReviewSubmitRequest')
          ..add('turnstileToken', turnstileToken)
          ..add('items', items))
        .toString();
  }
}

class GuestReviewSubmitRequestBuilder
    implements
        Builder<GuestReviewSubmitRequest, GuestReviewSubmitRequestBuilder> {
  _$GuestReviewSubmitRequest? _$v;

  String? _turnstileToken;
  String? get turnstileToken => _$this._turnstileToken;
  set turnstileToken(String? turnstileToken) =>
      _$this._turnstileToken = turnstileToken;

  ListBuilder<GuestReviewItemRequest>? _items;
  ListBuilder<GuestReviewItemRequest> get items =>
      _$this._items ??= ListBuilder<GuestReviewItemRequest>();
  set items(ListBuilder<GuestReviewItemRequest>? items) =>
      _$this._items = items;

  GuestReviewSubmitRequestBuilder() {
    GuestReviewSubmitRequest._defaults(this);
  }

  GuestReviewSubmitRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _turnstileToken = $v.turnstileToken;
      _items = $v.items.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestReviewSubmitRequest other) {
    _$v = other as _$GuestReviewSubmitRequest;
  }

  @override
  void update(void Function(GuestReviewSubmitRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestReviewSubmitRequest build() => _build();

  _$GuestReviewSubmitRequest _build() {
    _$GuestReviewSubmitRequest _$result;
    try {
      _$result = _$v ??
          _$GuestReviewSubmitRequest._(
            turnstileToken: turnstileToken,
            items: items.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'items';
        items.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'GuestReviewSubmitRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
