// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'master_search_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MasterSearchResult extends MasterSearchResult {
  @override
  final String? masterId;
  @override
  final String? firstName;
  @override
  final String? lastName;
  @override
  final String? cityLabel;
  @override
  final String? districtLabel;
  @override
  final double? avgRating;
  @override
  final int? reviewCount;
  @override
  final String? avatarUrl;
  @override
  final num? minEffectivePrice;

  factory _$MasterSearchResult(
          [void Function(MasterSearchResultBuilder)? updates]) =>
      (MasterSearchResultBuilder()..update(updates))._build();

  _$MasterSearchResult._(
      {this.masterId,
      this.firstName,
      this.lastName,
      this.cityLabel,
      this.districtLabel,
      this.avgRating,
      this.reviewCount,
      this.avatarUrl,
      this.minEffectivePrice})
      : super._();
  @override
  MasterSearchResult rebuild(
          void Function(MasterSearchResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MasterSearchResultBuilder toBuilder() =>
      MasterSearchResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MasterSearchResult &&
        masterId == other.masterId &&
        firstName == other.firstName &&
        lastName == other.lastName &&
        cityLabel == other.cityLabel &&
        districtLabel == other.districtLabel &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        avatarUrl == other.avatarUrl &&
        minEffectivePrice == other.minEffectivePrice;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, firstName.hashCode);
    _$hash = $jc(_$hash, lastName.hashCode);
    _$hash = $jc(_$hash, cityLabel.hashCode);
    _$hash = $jc(_$hash, districtLabel.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, minEffectivePrice.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MasterSearchResult')
          ..add('masterId', masterId)
          ..add('firstName', firstName)
          ..add('lastName', lastName)
          ..add('cityLabel', cityLabel)
          ..add('districtLabel', districtLabel)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('avatarUrl', avatarUrl)
          ..add('minEffectivePrice', minEffectivePrice))
        .toString();
  }
}

class MasterSearchResultBuilder
    implements Builder<MasterSearchResult, MasterSearchResultBuilder> {
  _$MasterSearchResult? _$v;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  String? _firstName;
  String? get firstName => _$this._firstName;
  set firstName(String? firstName) => _$this._firstName = firstName;

  String? _lastName;
  String? get lastName => _$this._lastName;
  set lastName(String? lastName) => _$this._lastName = lastName;

  String? _cityLabel;
  String? get cityLabel => _$this._cityLabel;
  set cityLabel(String? cityLabel) => _$this._cityLabel = cityLabel;

  String? _districtLabel;
  String? get districtLabel => _$this._districtLabel;
  set districtLabel(String? districtLabel) =>
      _$this._districtLabel = districtLabel;

  double? _avgRating;
  double? get avgRating => _$this._avgRating;
  set avgRating(double? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  num? _minEffectivePrice;
  num? get minEffectivePrice => _$this._minEffectivePrice;
  set minEffectivePrice(num? minEffectivePrice) =>
      _$this._minEffectivePrice = minEffectivePrice;

  MasterSearchResultBuilder() {
    MasterSearchResult._defaults(this);
  }

  MasterSearchResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterId = $v.masterId;
      _firstName = $v.firstName;
      _lastName = $v.lastName;
      _cityLabel = $v.cityLabel;
      _districtLabel = $v.districtLabel;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _avatarUrl = $v.avatarUrl;
      _minEffectivePrice = $v.minEffectivePrice;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MasterSearchResult other) {
    _$v = other as _$MasterSearchResult;
  }

  @override
  void update(void Function(MasterSearchResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MasterSearchResult build() => _build();

  _$MasterSearchResult _build() {
    final _$result = _$v ??
        _$MasterSearchResult._(
          masterId: masterId,
          firstName: firstName,
          lastName: lastName,
          cityLabel: cityLabel,
          districtLabel: districtLabel,
          avgRating: avgRating,
          reviewCount: reviewCount,
          avatarUrl: avatarUrl,
          minEffectivePrice: minEffectivePrice,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
