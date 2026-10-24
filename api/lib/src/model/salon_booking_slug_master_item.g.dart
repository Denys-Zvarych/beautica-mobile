// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_booking_slug_master_item.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonBookingSlugMasterItem extends SalonBookingSlugMasterItem {
  @override
  final String masterSlug;
  @override
  final String name;
  @override
  final String? avatarUrl;
  @override
  final String? professionalTitle;
  @override
  final num? avgRating;
  @override
  final int reviewCount;

  factory _$SalonBookingSlugMasterItem(
          [void Function(SalonBookingSlugMasterItemBuilder)? updates]) =>
      (SalonBookingSlugMasterItemBuilder()..update(updates))._build();

  _$SalonBookingSlugMasterItem._(
      {required this.masterSlug,
      required this.name,
      this.avatarUrl,
      this.professionalTitle,
      this.avgRating,
      required this.reviewCount})
      : super._();
  @override
  SalonBookingSlugMasterItem rebuild(
          void Function(SalonBookingSlugMasterItemBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonBookingSlugMasterItemBuilder toBuilder() =>
      SalonBookingSlugMasterItemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonBookingSlugMasterItem &&
        masterSlug == other.masterSlug &&
        name == other.name &&
        avatarUrl == other.avatarUrl &&
        professionalTitle == other.professionalTitle &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterSlug.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, professionalTitle.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonBookingSlugMasterItem')
          ..add('masterSlug', masterSlug)
          ..add('name', name)
          ..add('avatarUrl', avatarUrl)
          ..add('professionalTitle', professionalTitle)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount))
        .toString();
  }
}

class SalonBookingSlugMasterItemBuilder
    implements
        Builder<SalonBookingSlugMasterItem, SalonBookingSlugMasterItemBuilder> {
  _$SalonBookingSlugMasterItem? _$v;

  String? _masterSlug;
  String? get masterSlug => _$this._masterSlug;
  set masterSlug(String? masterSlug) => _$this._masterSlug = masterSlug;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  String? _professionalTitle;
  String? get professionalTitle => _$this._professionalTitle;
  set professionalTitle(String? professionalTitle) =>
      _$this._professionalTitle = professionalTitle;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  SalonBookingSlugMasterItemBuilder() {
    SalonBookingSlugMasterItem._defaults(this);
  }

  SalonBookingSlugMasterItemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterSlug = $v.masterSlug;
      _name = $v.name;
      _avatarUrl = $v.avatarUrl;
      _professionalTitle = $v.professionalTitle;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonBookingSlugMasterItem other) {
    _$v = other as _$SalonBookingSlugMasterItem;
  }

  @override
  void update(void Function(SalonBookingSlugMasterItemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonBookingSlugMasterItem build() => _build();

  _$SalonBookingSlugMasterItem _build() {
    final _$result = _$v ??
        _$SalonBookingSlugMasterItem._(
          masterSlug: BuiltValueNullFieldError.checkNotNull(
              masterSlug, r'SalonBookingSlugMasterItem', 'masterSlug'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'SalonBookingSlugMasterItem', 'name'),
          avatarUrl: avatarUrl,
          professionalTitle: professionalTitle,
          avgRating: avgRating,
          reviewCount: BuiltValueNullFieldError.checkNotNull(
              reviewCount, r'SalonBookingSlugMasterItem', 'reviewCount'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
