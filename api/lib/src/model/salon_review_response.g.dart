// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonReviewResponse extends SalonReviewResponse {
  @override
  final String? id;
  @override
  final String? masterId;
  @override
  final String? masterFirstName;
  @override
  final String? masterLastName;
  @override
  final String? clientDisplayName;
  @override
  final String? serviceName;
  @override
  final int? rating;
  @override
  final String? comment;
  @override
  final DateTime? createdAt;

  factory _$SalonReviewResponse(
          [void Function(SalonReviewResponseBuilder)? updates]) =>
      (SalonReviewResponseBuilder()..update(updates))._build();

  _$SalonReviewResponse._(
      {this.id,
      this.masterId,
      this.masterFirstName,
      this.masterLastName,
      this.clientDisplayName,
      this.serviceName,
      this.rating,
      this.comment,
      this.createdAt})
      : super._();
  @override
  SalonReviewResponse rebuild(
          void Function(SalonReviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonReviewResponseBuilder toBuilder() =>
      SalonReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonReviewResponse &&
        id == other.id &&
        masterId == other.masterId &&
        masterFirstName == other.masterFirstName &&
        masterLastName == other.masterLastName &&
        clientDisplayName == other.clientDisplayName &&
        serviceName == other.serviceName &&
        rating == other.rating &&
        comment == other.comment &&
        createdAt == other.createdAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterFirstName.hashCode);
    _$hash = $jc(_$hash, masterLastName.hashCode);
    _$hash = $jc(_$hash, clientDisplayName.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonReviewResponse')
          ..add('id', id)
          ..add('masterId', masterId)
          ..add('masterFirstName', masterFirstName)
          ..add('masterLastName', masterLastName)
          ..add('clientDisplayName', clientDisplayName)
          ..add('serviceName', serviceName)
          ..add('rating', rating)
          ..add('comment', comment)
          ..add('createdAt', createdAt))
        .toString();
  }
}

class SalonReviewResponseBuilder
    implements Builder<SalonReviewResponse, SalonReviewResponseBuilder> {
  _$SalonReviewResponse? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _masterFirstName;
  String? get masterFirstName => _$this._masterFirstName;
  set masterFirstName(String? masterFirstName) =>
      _$this._masterFirstName = masterFirstName;

  String? _masterLastName;
  String? get masterLastName => _$this._masterLastName;
  set masterLastName(String? masterLastName) =>
      _$this._masterLastName = masterLastName;

  String? _clientDisplayName;
  String? get clientDisplayName => _$this._clientDisplayName;
  set clientDisplayName(String? clientDisplayName) =>
      _$this._clientDisplayName = clientDisplayName;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  int? _rating;
  int? get rating => _$this._rating;
  set rating(int? rating) => _$this._rating = rating;

  String? _comment;
  String? get comment => _$this._comment;
  set comment(String? comment) => _$this._comment = comment;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  SalonReviewResponseBuilder() {
    SalonReviewResponse._defaults(this);
  }

  SalonReviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _masterId = $v.masterId;
      _masterFirstName = $v.masterFirstName;
      _masterLastName = $v.masterLastName;
      _clientDisplayName = $v.clientDisplayName;
      _serviceName = $v.serviceName;
      _rating = $v.rating;
      _comment = $v.comment;
      _createdAt = $v.createdAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonReviewResponse other) {
    _$v = other as _$SalonReviewResponse;
  }

  @override
  void update(void Function(SalonReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonReviewResponse build() => _build();

  _$SalonReviewResponse _build() {
    final _$result = _$v ??
        _$SalonReviewResponse._(
          id: id,
          masterId: masterId,
          masterFirstName: masterFirstName,
          masterLastName: masterLastName,
          clientDisplayName: clientDisplayName,
          serviceName: serviceName,
          rating: rating,
          comment: comment,
          createdAt: createdAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
