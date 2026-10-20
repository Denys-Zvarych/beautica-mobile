// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'salon_booking_slug_info_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SalonBookingSlugInfoResponse extends SalonBookingSlugInfoResponse {
  @override
  final String salonId;
  @override
  final String name;
  @override
  final String? city;
  @override
  final String? avatarUrl;
  @override
  final String? coverImageUrl;
  @override
  final num? avgRating;
  @override
  final int reviewCount;
  @override
  final bool bookable;
  @override
  final BuiltList<SalonBookingSlugMasterItem> masters;

  factory _$SalonBookingSlugInfoResponse(
          [void Function(SalonBookingSlugInfoResponseBuilder)? updates]) =>
      (SalonBookingSlugInfoResponseBuilder()..update(updates))._build();

  _$SalonBookingSlugInfoResponse._(
      {required this.salonId,
      required this.name,
      this.city,
      this.avatarUrl,
      this.coverImageUrl,
      this.avgRating,
      required this.reviewCount,
      required this.bookable,
      required this.masters})
      : super._();
  @override
  SalonBookingSlugInfoResponse rebuild(
          void Function(SalonBookingSlugInfoResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SalonBookingSlugInfoResponseBuilder toBuilder() =>
      SalonBookingSlugInfoResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SalonBookingSlugInfoResponse &&
        salonId == other.salonId &&
        name == other.name &&
        city == other.city &&
        avatarUrl == other.avatarUrl &&
        coverImageUrl == other.coverImageUrl &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        bookable == other.bookable &&
        masters == other.masters;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, city.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, coverImageUrl.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, bookable.hashCode);
    _$hash = $jc(_$hash, masters.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SalonBookingSlugInfoResponse')
          ..add('salonId', salonId)
          ..add('name', name)
          ..add('city', city)
          ..add('avatarUrl', avatarUrl)
          ..add('coverImageUrl', coverImageUrl)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('bookable', bookable)
          ..add('masters', masters))
        .toString();
  }
}

class SalonBookingSlugInfoResponseBuilder
    implements
        Builder<SalonBookingSlugInfoResponse,
            SalonBookingSlugInfoResponseBuilder> {
  _$SalonBookingSlugInfoResponse? _$v;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _city;
  String? get city => _$this._city;
  set city(String? city) => _$this._city = city;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  String? _coverImageUrl;
  String? get coverImageUrl => _$this._coverImageUrl;
  set coverImageUrl(String? coverImageUrl) =>
      _$this._coverImageUrl = coverImageUrl;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  bool? _bookable;
  bool? get bookable => _$this._bookable;
  set bookable(bool? bookable) => _$this._bookable = bookable;

  ListBuilder<SalonBookingSlugMasterItem>? _masters;
  ListBuilder<SalonBookingSlugMasterItem> get masters =>
      _$this._masters ??= ListBuilder<SalonBookingSlugMasterItem>();
  set masters(ListBuilder<SalonBookingSlugMasterItem>? masters) =>
      _$this._masters = masters;

  SalonBookingSlugInfoResponseBuilder() {
    SalonBookingSlugInfoResponse._defaults(this);
  }

  SalonBookingSlugInfoResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _salonId = $v.salonId;
      _name = $v.name;
      _city = $v.city;
      _avatarUrl = $v.avatarUrl;
      _coverImageUrl = $v.coverImageUrl;
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _bookable = $v.bookable;
      _masters = $v.masters.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SalonBookingSlugInfoResponse other) {
    _$v = other as _$SalonBookingSlugInfoResponse;
  }

  @override
  void update(void Function(SalonBookingSlugInfoResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SalonBookingSlugInfoResponse build() => _build();

  _$SalonBookingSlugInfoResponse _build() {
    _$SalonBookingSlugInfoResponse _$result;
    try {
      _$result = _$v ??
          _$SalonBookingSlugInfoResponse._(
            salonId: BuiltValueNullFieldError.checkNotNull(
                salonId, r'SalonBookingSlugInfoResponse', 'salonId'),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'SalonBookingSlugInfoResponse', 'name'),
            city: city,
            avatarUrl: avatarUrl,
            coverImageUrl: coverImageUrl,
            avgRating: avgRating,
            reviewCount: BuiltValueNullFieldError.checkNotNull(
                reviewCount, r'SalonBookingSlugInfoResponse', 'reviewCount'),
            bookable: BuiltValueNullFieldError.checkNotNull(
                bookable, r'SalonBookingSlugInfoResponse', 'bookable'),
            masters: masters.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'masters';
        masters.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SalonBookingSlugInfoResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
