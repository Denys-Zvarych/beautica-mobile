// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_review_item_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestReviewItemRequest extends GuestReviewItemRequest {
  @override
  final String bookingId;
  @override
  final int rating;
  @override
  final String? comment;

  factory _$GuestReviewItemRequest(
          [void Function(GuestReviewItemRequestBuilder)? updates]) =>
      (GuestReviewItemRequestBuilder()..update(updates))._build();

  _$GuestReviewItemRequest._(
      {required this.bookingId, required this.rating, this.comment})
      : super._();
  @override
  GuestReviewItemRequest rebuild(
          void Function(GuestReviewItemRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestReviewItemRequestBuilder toBuilder() =>
      GuestReviewItemRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestReviewItemRequest &&
        bookingId == other.bookingId &&
        rating == other.rating &&
        comment == other.comment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestReviewItemRequest')
          ..add('bookingId', bookingId)
          ..add('rating', rating)
          ..add('comment', comment))
        .toString();
  }
}

class GuestReviewItemRequestBuilder
    implements Builder<GuestReviewItemRequest, GuestReviewItemRequestBuilder> {
  _$GuestReviewItemRequest? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  GuestReviewItemRequestBuilder() {
    GuestReviewItemRequest._defaults(this);
  }

  GuestReviewItemRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _rating = $v.rating;
      _comment = $v.comment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestReviewItemRequest other) {
    _$v = other as _$GuestReviewItemRequest;
  }

  @override
  void update(void Function(GuestReviewItemRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestReviewItemRequest build() => _build();

  _$GuestReviewItemRequest _build() {
    final _$result = _$v ??
        _$GuestReviewItemRequest._(
          bookingId: BuiltValueNullFieldError.checkNotNull(
              bookingId, r'GuestReviewItemRequest', 'bookingId'),
          rating: BuiltValueNullFieldError.checkNotNull(
              rating, r'GuestReviewItemRequest', 'rating'),
          comment: comment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
