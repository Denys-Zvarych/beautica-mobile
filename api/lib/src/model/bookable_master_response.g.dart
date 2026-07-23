// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bookable_master_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookableMasterResponse extends BookableMasterResponse {
  @override
  final String? masterId;
  @override
  final String? masterServiceId;
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? professionalTitle;
  @override
  final String? avatarUrl;
  @override
  final num? avgRating;
  @override
  final int? reviewCount;

  factory _$BookableMasterResponse(
          [void Function(BookableMasterResponseBuilder)? updates]) =>
      (BookableMasterResponseBuilder()..update(updates))._build();

  _$BookableMasterResponse._(
      {this.masterId,
      this.masterServiceId,
      this.firstName,
      this.lastName,
      this.professionalTitle,
      this.avatarUrl,
      this.avgRating,
      this.reviewCount})
      : super._();
  @override
  BookableMasterResponse rebuild(
          void Function(BookableMasterResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookableMasterResponseBuilder toBuilder() =>
      BookableMasterResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookableMasterResponse &&
        masterId == other.masterId &&
        masterServiceId == other.masterServiceId &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        professionalTitle == other.professionalTitle &&
        avatarUrl == other.avatarUrl &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterServiceId.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, professionalTitle.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookableMasterResponse')
          ..add('masterId', masterId)
          ..add('masterServiceId', masterServiceId)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('professionalTitle', professionalTitle)
          ..add('avatarUrl', avatarUrl)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount))
        .toString();
  }
}

class BookableMasterResponseBuilder
    implements Builder<BookableMasterResponse, BookableMasterResponseBuilder> {
  _$BookableMasterResponse? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _masterServiceId;
  String? get masterServiceId => _$this._masterServiceId;
  set masterServiceId(String? masterServiceId) =>
      _$this._masterServiceId = masterServiceId;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _professionalTitle;
  String? get professionalTitle => _$this._professionalTitle;
  set professionalTitle(String? professionalTitle) =>
      _$this._professionalTitle = professionalTitle;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  BookableMasterResponseBuilder() {
    BookableMasterResponse._defaults(this);
  }

  BookableMasterResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _masterServiceId = $v.masterServiceId;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _professionalTitle = $v.professionalTitle;
      _avatarUrl = $v.avatarUrl;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookableMasterResponse other) {
    _$v = other as _$BookableMasterResponse;
  }

  @override
  void update(void Function(BookableMasterResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookableMasterResponse build() => _build();

  _$BookableMasterResponse _build() {
    final _$result = _$v ??
        _$BookableMasterResponse._(
          masterId: masterId,
          masterServiceId: masterServiceId,
          firstName: firstName,
          lastName: lastName,
          professionalTitle: professionalTitle,
          avatarUrl: avatarUrl,
          avgRating: avgRating,
          reviewCount: reviewCount,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
