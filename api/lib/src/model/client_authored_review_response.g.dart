// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_authored_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ClientAuthoredReviewResponse extends ClientAuthoredReviewResponse {
  @override
  final int? rating;
  @override
  final String? comment;

  factory _$ClientAuthoredReviewResponse(
          [void Function(ClientAuthoredReviewResponseBuilder)? updates]) =>
      (ClientAuthoredReviewResponseBuilder()..update(updates))._build();

  _$ClientAuthoredReviewResponse._({this.rating, this.comment}) : super._();
  @override
  ClientAuthoredReviewResponse rebuild(
          void Function(ClientAuthoredReviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClientAuthoredReviewResponseBuilder toBuilder() =>
      ClientAuthoredReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClientAuthoredReviewResponse &&
        rating == other.rating &&
        comment == other.comment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClientAuthoredReviewResponse')
          ..add('rating', rating)
          ..add('comment', comment))
        .toString();
  }
}

class ClientAuthoredReviewResponseBuilder
    implements
        Builder<ClientAuthoredReviewResponse,
            ClientAuthoredReviewResponseBuilder> {
  _$ClientAuthoredReviewResponse? _$v;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  ClientAuthoredReviewResponseBuilder() {
    ClientAuthoredReviewResponse._defaults(this);
  }

  ClientAuthoredReviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rating = $v.rating;
      _comment = $v.comment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClientAuthoredReviewResponse other) {
    _$v = other as _$ClientAuthoredReviewResponse;
  }

  @override
  void update(void Function(ClientAuthoredReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClientAuthoredReviewResponse build() => _build();

  _$ClientAuthoredReviewResponse _build() {
    final _$result = _$v ??
        _$ClientAuthoredReviewResponse._(
          rating: rating,
          comment: comment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
