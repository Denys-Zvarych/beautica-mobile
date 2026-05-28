// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_review_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateReviewRequest extends CreateReviewRequest {
  @override
  final String bookingId;
  @override
  final int rating;
  @override
  final String? comment;

  factory _$CreateReviewRequest(
          [void Function(CreateReviewRequestBuilder)? updates]) =>
      (CreateReviewRequestBuilder()..update(updates))._build();

  _$CreateReviewRequest._(
      {required this.bookingId, required this.rating, this.comment})
      : super._();
  @override
  CreateReviewRequest rebuild(
          void Function(CreateReviewRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateReviewRequestBuilder toBuilder() =>
      CreateReviewRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateReviewRequest &&
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
    return (newBuiltValueToStringHelper(r'CreateReviewRequest')
          ..add('bookingId', bookingId)
          ..add('rating', rating)
          ..add('comment', comment))
        .toString();
  }
}

class CreateReviewRequestBuilder
    implements Builder<CreateReviewRequest, CreateReviewRequestBuilder> {
  _$CreateReviewRequest? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  CreateReviewRequestBuilder() {
    CreateReviewRequest._defaults(this);
  }

  CreateReviewRequestBuilder get _$this {
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
  void replace(CreateReviewRequest other) {
    _$v = other as _$CreateReviewRequest;
  }

  @override
  void update(void Function(CreateReviewRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateReviewRequest build() => _build();

  _$CreateReviewRequest _build() {
    final _$result = _$v ??
        _$CreateReviewRequest._(
          bookingId: BuiltValueNullFieldError.checkNotNull(
              bookingId, r'CreateReviewRequest', 'bookingId'),
          rating: BuiltValueNullFieldError.checkNotNull(
              rating, r'CreateReviewRequest', 'rating'),
          comment: comment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
