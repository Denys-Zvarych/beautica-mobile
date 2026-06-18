// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'my_review_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MyReviewResponse extends MyReviewResponse {
  @override
  final String? id;
  @override
  final String? masterId;
  @override
  final String? masterFirstName;
  @override
  final String? masterLastName;
  @override
  final String? serviceName;
  @override
  final int? rating;
  @override
  final String? comment;
  @override
  final DateTime? createdAt;
  @override
  final String? bookingId;

  factory _$MyReviewResponse(
          [void Function(MyReviewResponseBuilder)? updates]) =>
      (MyReviewResponseBuilder()..update(updates))._build();

  _$MyReviewResponse._(
      {this.id,
      this.masterId,
      this.masterFirstName,
      this.masterLastName,
      this.serviceName,
      this.rating,
      this.comment,
      this.createdAt,
      this.bookingId})
      : super._();
  @override
  MyReviewResponse rebuild(void Function(MyReviewResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MyReviewResponseBuilder toBuilder() =>
      MyReviewResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MyReviewResponse &&
        id == other.id &&
        masterId == other.masterId &&
        masterFirstName == other.masterFirstName &&
        masterLastName == other.masterLastName &&
        serviceName == other.serviceName &&
        rating == other.rating &&
        comment == other.comment &&
        createdAt == other.createdAt &&
        bookingId == other.bookingId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterFirstName.hashCode);
    _$hash = $jc(_$hash, masterLastName.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, rating.hashCode);
    _$hash = $jc(_$hash, comment.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MyReviewResponse')
          ..add('id', id)
          ..add('masterId', masterId)
          ..add('masterFirstName', masterFirstName)
          ..add('masterLastName', masterLastName)
          ..add('serviceName', serviceName)
          ..add('rating', rating)
          ..add('comment', comment)
          ..add('createdAt', createdAt)
          ..add('bookingId', bookingId))
        .toString();
  }
}

class MyReviewResponseBuilder
    implements Builder<MyReviewResponse, MyReviewResponseBuilder> {
  _$MyReviewResponse? _$v;

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

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  MyReviewResponseBuilder() {
    MyReviewResponse._defaults(this);
  }

  MyReviewResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _masterId = $v.masterId;
      _masterFirstName = $v.masterFirstName;
      _masterLastName = $v.masterLastName;
      _serviceName = $v.serviceName;
      _rating = $v.rating;
      _comment = $v.comment;
      _createdAt = $v.createdAt;
      _bookingId = $v.bookingId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MyReviewResponse other) {
    _$v = other as _$MyReviewResponse;
  }

  @override
  void update(void Function(MyReviewResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MyReviewResponse build() => _build();

  _$MyReviewResponse _build() {
    final _$result = _$v ??
        _$MyReviewResponse._(
          id: id,
          masterId: masterId,
          masterFirstName: masterFirstName,
          masterLastName: masterLastName,
          serviceName: serviceName,
          rating: rating,
          comment: comment,
          createdAt: createdAt,
          bookingId: bookingId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
