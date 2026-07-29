// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ClientReviewResponse extends ClientReviewResponse {
  @override
  final String? id;
  @override
  final String? bookingId;
  @override
  final String? clientId;
  @override
  final String? authorMasterId;
  @override
  final int? rating;
  @override
  final String? comment;
  @override
  final DateTime? createdAt;

  factory _$ClientReviewResponse(
          [void Function(ClientReviewResponseBuilder)? updates]) =>
      (ClientReviewResponseBuilder()..update(updates))._build();

  _$ClientReviewResponse._(
      {this.id,
      this.bookingId,
      this.clientId,
      this.authorMasterId,
      this.rating,
      this.comment,
      this.createdAt})
      : super._();
  @override
  ClientReviewResponse rebuild(
          void Function(ClientReviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClientReviewResponseBuilder toBuilder() =>
      ClientReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClientReviewResponse &&
        id == other.id &&
        bookingId == other.bookingId &&
        clientId == other.clientId &&
        authorMasterId == other.authorMasterId &&
        rating == other.rating &&
        comment == other.comment &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, clientId.hashCode);
    _$hash = $jc(_$hash, authorMasterId.hashCode);
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClientReviewResponse')
          ..add('id', id)
          ..add('bookingId', bookingId)
          ..add('clientId', clientId)
          ..add('authorMasterId', authorMasterId)
          ..add('rating', rating)
          ..add('comment', comment)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class ClientReviewResponseBuilder
    implements Builder<ClientReviewResponse, ClientReviewResponseBuilder> {
  _$ClientReviewResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  String? _clientId;
  String? get clientId => _$this._clientId;
  set clientId(String? clientId) => _$this._clientId = clientId;

  String? _authorMasterId;
  String? get authorMasterId => _$this._authorMasterId;
  set authorMasterId(String? authorMasterId) =>
      _$this._authorMasterId = authorMasterId;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  ClientReviewResponseBuilder() {
    ClientReviewResponse._defaults(this);
  }

  ClientReviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _bookingId = $v.bookingId;
      _clientId = $v.clientId;
      _authorMasterId = $v.authorMasterId;
      _rating = $v.rating;
      _comment = $v.comment;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClientReviewResponse other) {
    _$v = other as _$ClientReviewResponse;
  }

  @override
  void update(void Function(ClientReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClientReviewResponse build() => _build();

  _$ClientReviewResponse _build() {
    final _$result = _$v ??
        _$ClientReviewResponse._(
          id: id,
          bookingId: bookingId,
          clientId: clientId,
          authorMasterId: authorMasterId,
          rating: rating,
          comment: comment,
          createdAt: createdAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
