// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'passport_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PassportResponse extends PassportResponse {
  @override
  final BuiltList<String>? favoriteDistricts;
  @override
  final BuiltList<String>? favoriteCities;
  @override
  final BudgetBand? budget;
  @override
  final int? bookingsConsidered;
  @override
  final int? reviewsWritten;
  @override
  final int? memberSinceYear;

  factory _$PassportResponse(
          [void Function(PassportResponseBuilder)? updates]) =>
      (PassportResponseBuilder()..update(updates))._build();

  _$PassportResponse._(
      {this.favoriteDistricts,
      this.favoriteCities,
      this.budget,
      this.bookingsConsidered,
      this.reviewsWritten,
      this.memberSinceYear})
      : super._();
  @override
  PassportResponse rebuild(void Function(PassportResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PassportResponseBuilder toBuilder() =>
      PassportResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PassportResponse &&
        favoriteDistricts == other.favoriteDistricts &&
        favoriteCities == other.favoriteCities &&
        budget == other.budget &&
        bookingsConsidered == other.bookingsConsidered &&
        reviewsWritten == other.reviewsWritten &&
        memberSinceYear == other.memberSinceYear;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, favoriteDistricts.hashCode);
    _$hash = $jc(_$hash, favoriteCities.hashCode);
    _$hash = $jc(_$hash, budget.hashCode);
    _$hash = $jc(_$hash, bookingsConsidered.hashCode);
    _$hash = $jc(_$hash, reviewsWritten.hashCode);
    _$hash = $jc(_$hash, memberSinceYear.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PassportResponse')
          ..add('favoriteDistricts', favoriteDistricts)
          ..add('favoriteCities', favoriteCities)
          ..add('budget', budget)
          ..add('bookingsConsidered', bookingsConsidered)
          ..add('reviewsWritten', reviewsWritten)
          ..add('memberSinceYear', memberSinceYear))
        .toString();
  }
}

class PassportResponseBuilder
    implements Builder<PassportResponse, PassportResponseBuilder> {
  _$PassportResponse? _$v;

  ListBuilder<String>? _favoriteDistricts;
  ListBuilder<String> get favoriteDistricts =>
      _$this._favoriteDistricts ??= ListBuilder<String>();
  set favoriteDistricts(ListBuilder<String>? favoriteDistricts) =>
      _$this._favoriteDistricts = favoriteDistricts;

  ListBuilder<String>? _favoriteCities;
  ListBuilder<String> get favoriteCities =>
      _$this._favoriteCities ??= ListBuilder<String>();
  set favoriteCities(ListBuilder<String>? favoriteCities) =>
      _$this._favoriteCities = favoriteCities;

  BudgetBandBuilder? _budget;
  BudgetBandBuilder get budget => _$this._budget ??= BudgetBandBuilder();
  set budget(BudgetBandBuilder? budget) => _$this._budget = budget;

  int? _bookingsConsidered;
  int? get bookingsConsidered => _$this._bookingsConsidered;
  set bookingsConsidered(int? bookingsConsidered) =>
      _$this._bookingsConsidered = bookingsConsidered;

  int? _reviewsWritten;
  int? get reviewsWritten => _$this._reviewsWritten;
  set reviewsWritten(int? reviewsWritten) =>
      _$this._reviewsWritten = reviewsWritten;

  int? _memberSinceYear;
  int? get memberSinceYear => _$this._memberSinceYear;
  set memberSinceYear(int? memberSinceYear) =>
      _$this._memberSinceYear = memberSinceYear;

  PassportResponseBuilder() {
    PassportResponse._defaults(this);
  }

  PassportResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _favoriteDistricts = $v.favoriteDistricts?.toBuilder();
      _favoriteCities = $v.favoriteCities?.toBuilder();
      _budget = $v.budget?.toBuilder();
      _bookingsConsidered = $v.bookingsConsidered;
      _reviewsWritten = $v.reviewsWritten;
      _memberSinceYear = $v.memberSinceYear;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PassportResponse other) {
    _$v = other as _$PassportResponse;
  }

  @override
  void update(void Function(PassportResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PassportResponse build() => _build();

  _$PassportResponse _build() {
    _$PassportResponse _$result;
    try {
      _$result = _$v ??
          _$PassportResponse._(
            favoriteDistricts: _favoriteDistricts?.build(),
            favoriteCities: _favoriteCities?.build(),
            budget: _budget?.build(),
            bookingsConsidered: bookingsConsidered,
            reviewsWritten: reviewsWritten,
            memberSinceYear: memberSinceYear,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'favoriteDistricts';
        _favoriteDistricts?.build();
        _$failedField = 'favoriteCities';
        _favoriteCities?.build();
        _$failedField = 'budget';
        _budget?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PassportResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
