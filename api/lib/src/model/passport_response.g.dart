// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'passport_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PassportResponse extends PassportResponse {
  @override
  final BuiltList<String>? favoriteProcedures;
  @override
  final BuiltList<String>? favoriteDistricts;
  @override
  final BudgetBand? budget;
  @override
  final int? bookingsConsidered;

  factory _$PassportResponse(
          [void Function(PassportResponseBuilder)? updates]) =>
      (PassportResponseBuilder()..update(updates))._build();

  _$PassportResponse._(
      {this.favoriteProcedures,
      this.favoriteDistricts,
      this.budget,
      this.bookingsConsidered})
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
        favoriteProcedures == other.favoriteProcedures &&
        favoriteDistricts == other.favoriteDistricts &&
        budget == other.budget &&
        bookingsConsidered == other.bookingsConsidered;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, favoriteProcedures.hashCode);
    _$hash = $jc(_$hash, favoriteDistricts.hashCode);
    _$hash = $jc(_$hash, budget.hashCode);
    _$hash = $jc(_$hash, bookingsConsidered.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PassportResponse')
          ..add('favoriteProcedures', favoriteProcedures)
          ..add('favoriteDistricts', favoriteDistricts)
          ..add('budget', budget)
          ..add('bookingsConsidered', bookingsConsidered))
        .toString();
  }
}

class PassportResponseBuilder
    implements Builder<PassportResponse, PassportResponseBuilder> {
  _$PassportResponse? _$v;

  ListBuilder<String>? _favoriteProcedures;
  ListBuilder<String> get favoriteProcedures =>
      _$this._favoriteProcedures ??= ListBuilder<String>();
  set favoriteProcedures(ListBuilder<String>? favoriteProcedures) =>
      _$this._favoriteProcedures = favoriteProcedures;

  ListBuilder<String>? _favoriteDistricts;
  ListBuilder<String> get favoriteDistricts =>
      _$this._favoriteDistricts ??= ListBuilder<String>();
  set favoriteDistricts(ListBuilder<String>? favoriteDistricts) =>
      _$this._favoriteDistricts = favoriteDistricts;

  BudgetBandBuilder? _budget;
  BudgetBandBuilder get budget => _$this._budget ??= BudgetBandBuilder();
  set budget(BudgetBandBuilder? budget) => _$this._budget = budget;

  int? _bookingsConsidered;
  int? get bookingsConsidered => _$this._bookingsConsidered;
  set bookingsConsidered(int? bookingsConsidered) =>
      _$this._bookingsConsidered = bookingsConsidered;

  PassportResponseBuilder() {
    PassportResponse._defaults(this);
  }

  PassportResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _favoriteProcedures = $v.favoriteProcedures?.toBuilder();
      _favoriteDistricts = $v.favoriteDistricts?.toBuilder();
      _budget = $v.budget?.toBuilder();
      _bookingsConsidered = $v.bookingsConsidered;
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
            favoriteProcedures: _favoriteProcedures?.build(),
            favoriteDistricts: _favoriteDistricts?.build(),
            budget: _budget?.build(),
            bookingsConsidered: bookingsConsidered,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'favoriteProcedures';
        _favoriteProcedures?.build();
        _$failedField = 'favoriteDistricts';
        _favoriteDistricts?.build();
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
