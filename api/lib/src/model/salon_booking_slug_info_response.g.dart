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
  @override
  final String? region;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final DateTime updatedAt;
  @override
  final String? description;
  @override
  final String? locationNote;
  @override
  final BuiltList<MediaFileResponse> portfolio;
  @override
  final BuiltList<SalonServiceCategoryGroup> serviceCategories;
  @override
  final BuiltList<RatingBucket> ratingDistribution;
  @override
  final BuiltList<SalonReviewResponse> latestReviews;

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
      required this.masters,
      this.region,
      this.street,
      this.buildingNo,
      required this.updatedAt,
      this.description,
      this.locationNote,
      required this.portfolio,
      required this.serviceCategories,
      required this.ratingDistribution,
      required this.latestReviews})
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
        masters == other.masters &&
        region == other.region &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        updatedAt == other.updatedAt &&
        description == other.description &&
        locationNote == other.locationNote &&
        portfolio == other.portfolio &&
        serviceCategories == other.serviceCategories &&
        ratingDistribution == other.ratingDistribution &&
        latestReviews == other.latestReviews;
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
    _$hash = $jc(_$hash, region.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jc(_$hash, portfolio.hashCode);
    _$hash = $jc(_$hash, serviceCategories.hashCode);
    _$hash = $jc(_$hash, ratingDistribution.hashCode);
    _$hash = $jc(_$hash, latestReviews.hashCode);
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
          ..add('masters', masters)
          ..add('region', region)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('updatedAt', updatedAt)
          ..add('description', description)
          ..add('locationNote', locationNote)
          ..add('portfolio', portfolio)
          ..add('serviceCategories', serviceCategories)
          ..add('ratingDistribution', ratingDistribution)
          ..add('latestReviews', latestReviews))
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

  String? _region;
  String? get region => _$this._region;
  set region(String? region) => _$this._region = region;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  ListBuilder<MediaFileResponse>? _portfolio;
  ListBuilder<MediaFileResponse> get portfolio =>
      _$this._portfolio ??= ListBuilder<MediaFileResponse>();
  set portfolio(ListBuilder<MediaFileResponse>? portfolio) =>
      _$this._portfolio = portfolio;

  ListBuilder<SalonServiceCategoryGroup>? _serviceCategories;
  ListBuilder<SalonServiceCategoryGroup> get serviceCategories =>
      _$this._serviceCategories ??= ListBuilder<SalonServiceCategoryGroup>();
  set serviceCategories(
          ListBuilder<SalonServiceCategoryGroup>? serviceCategories) =>
      _$this._serviceCategories = serviceCategories;

  ListBuilder<RatingBucket>? _ratingDistribution;
  ListBuilder<RatingBucket> get ratingDistribution =>
      _$this._ratingDistribution ??= ListBuilder<RatingBucket>();
  set ratingDistribution(ListBuilder<RatingBucket>? ratingDistribution) =>
      _$this._ratingDistribution = ratingDistribution;

  ListBuilder<SalonReviewResponse>? _latestReviews;
  ListBuilder<SalonReviewResponse> get latestReviews =>
      _$this._latestReviews ??= ListBuilder<SalonReviewResponse>();
  set latestReviews(ListBuilder<SalonReviewResponse>? latestReviews) =>
      _$this._latestReviews = latestReviews;

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
      _region = $v.region;
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _updatedAt = $v.updatedAt;
      _description = $v.description;
      _locationNote = $v.locationNote;
      _portfolio = $v.portfolio.toBuilder();
      _serviceCategories = $v.serviceCategories.toBuilder();
      _ratingDistribution = $v.ratingDistribution.toBuilder();
      _latestReviews = $v.latestReviews.toBuilder();
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
            region: region,
            street: street,
            buildingNo: buildingNo,
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'SalonBookingSlugInfoResponse', 'updatedAt'),
            description: description,
            locationNote: locationNote,
            portfolio: portfolio.build(),
            serviceCategories: serviceCategories.build(),
            ratingDistribution: ratingDistribution.build(),
            latestReviews: latestReviews.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'masters';
        masters.build();

        _$failedField = 'portfolio';
        portfolio.build();
        _$failedField = 'serviceCategories';
        serviceCategories.build();
        _$failedField = 'ratingDistribution';
        ratingDistribution.build();
        _$failedField = 'latestReviews';
        latestReviews.build();
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
