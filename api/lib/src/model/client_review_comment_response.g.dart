// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_review_comment_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ClientReviewCommentResponse extends ClientReviewCommentResponse {
  @override
  final String? reviewId;
  @override
  final String? visitMonth;
  @override
  final int? stars;
  @override
  final String? comment;
  @override
  final bool? own;

  factory _$ClientReviewCommentResponse(
          [void Function(ClientReviewCommentResponseBuilder)? updates]) =>
      (ClientReviewCommentResponseBuilder()..update(updates))._build();

  _$ClientReviewCommentResponse._(
      {this.reviewId, this.visitMonth, this.stars, this.comment, this.own})
      : super._();
  @override
  ClientReviewCommentResponse rebuild(
          void Function(ClientReviewCommentResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClientReviewCommentResponseBuilder toBuilder() =>
      ClientReviewCommentResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClientReviewCommentResponse &&
        reviewId == other.reviewId &&
        visitMonth == other.visitMonth &&
        stars == other.stars &&
        comment == other.comment &&
        own == other.own;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, reviewId.hashCode);
    _$hash = $jc(_$hash, visitMonth.hashCode);
    _$hash = $jc(_$hash, stars.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jc(_$hash, own.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClientReviewCommentResponse')
          ..add('reviewId', reviewId)
          ..add('visitMonth', visitMonth)
          ..add('stars', stars)
          ..add('comment', comment)
          ..add('own', own))
        .toString();
  }
}

class ClientReviewCommentResponseBuilder
    implements
        Builder<ClientReviewCommentResponse,
            ClientReviewCommentResponseBuilder> {
  _$ClientReviewCommentResponse? _$v;

  String? _reviewId;
  String? get reviewId => _$this._reviewId;
  set reviewId(String? reviewId) => _$this._reviewId = reviewId;

  String? _visitMonth;
  String? get visitMonth => _$this._visitMonth;
  set visitMonth(String? visitMonth) => _$this._visitMonth = visitMonth;

  int? _stars;
  int? get stars => _$this._stars;
  set stars(int? stars) => _$this._stars = stars;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  bool? _own;
  bool? get own => _$this._own;
  set own(bool? own) => _$this._own = own;

  ClientReviewCommentResponseBuilder() {
    ClientReviewCommentResponse._defaults(this);
  }

  ClientReviewCommentResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _reviewId = $v.reviewId;
      _visitMonth = $v.visitMonth;
      _stars = $v.stars;
      _comment = $v.comment;
      _own = $v.own;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClientReviewCommentResponse other) {
    _$v = other as _$ClientReviewCommentResponse;
  }

  @override
  void update(void Function(ClientReviewCommentResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClientReviewCommentResponse build() => _build();

  _$ClientReviewCommentResponse _build() {
    final _$result = _$v ??
        _$ClientReviewCommentResponse._(
          reviewId: reviewId,
          visitMonth: visitMonth,
          stars: stars,
          comment: comment,
          own: own,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
