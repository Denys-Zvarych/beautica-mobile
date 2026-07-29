// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_client_review_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateClientReviewRequest extends CreateClientReviewRequest {
  @override
  final String bookingId;
  @override
  final int rating;
  @override
  final String? comment;

  factory _$CreateClientReviewRequest(
          [void Function(CreateClientReviewRequestBuilder)? updates]) =>
      (CreateClientReviewRequestBuilder()..update(updates))._build();

  _$CreateClientReviewRequest._(
      {required this.bookingId, required this.rating, this.comment})
      : super._();
  @override
  CreateClientReviewRequest rebuild(
          void Function(CreateClientReviewRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateClientReviewRequestBuilder toBuilder() =>
      CreateClientReviewRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateClientReviewRequest &&
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
    return (newBuiltValueToStringHelper(r'CreateClientReviewRequest')
          ..add('bookingId', bookingId)
          ..add('rating', rating)
          ..add('comment', comment))
        .toString();
  }
}

class CreateClientReviewRequestBuilder
    implements
        Builder<CreateClientReviewRequest, CreateClientReviewRequestBuilder> {
  _$CreateClientReviewRequest? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  CreateClientReviewRequestBuilder() {
    CreateClientReviewRequest._defaults(this);
  }

  CreateClientReviewRequestBuilder get _$this {
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
  void replace(CreateClientReviewRequest other) {
    _$v = other as _$CreateClientReviewRequest;
  }

  @override
  void update(void Function(CreateClientReviewRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateClientReviewRequest build() => _build();

  _$CreateClientReviewRequest _build() {
    final _$result = _$v ??
        _$CreateClientReviewRequest._(
          bookingId: BuiltValueNullFieldError.checkNotNull(
              bookingId, r'CreateClientReviewRequest', 'bookingId'),
          rating: BuiltValueNullFieldError.checkNotNull(
              rating, r'CreateClientReviewRequest', 'rating'),
          comment: comment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
