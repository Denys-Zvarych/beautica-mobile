// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_slug_info_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BookingSlugInfoResponseMasterTypeEnum
    _$bookingSlugInfoResponseMasterTypeEnum_SALON_MASTER =
    const BookingSlugInfoResponseMasterTypeEnum._('SALON_MASTER');
const BookingSlugInfoResponseMasterTypeEnum
    _$bookingSlugInfoResponseMasterTypeEnum_INDEPENDENT_MASTER =
    const BookingSlugInfoResponseMasterTypeEnum._('INDEPENDENT_MASTER');
const BookingSlugInfoResponseMasterTypeEnum
    _$bookingSlugInfoResponseMasterTypeEnum_SALON_OWNER =
    const BookingSlugInfoResponseMasterTypeEnum._('SALON_OWNER');
const BookingSlugInfoResponseMasterTypeEnum
    _$bookingSlugInfoResponseMasterTypeEnum_unknownDefaultOpenApi =
    const BookingSlugInfoResponseMasterTypeEnum._('unknownDefaultOpenApi');

BookingSlugInfoResponseMasterTypeEnum
    _$bookingSlugInfoResponseMasterTypeEnumValueOf(String name) {
  switch (name) {
    case 'SALON_MASTER':
      return _$bookingSlugInfoResponseMasterTypeEnum_SALON_MASTER;
    case 'INDEPENDENT_MASTER':
      return _$bookingSlugInfoResponseMasterTypeEnum_INDEPENDENT_MASTER;
    case 'SALON_OWNER':
      return _$bookingSlugInfoResponseMasterTypeEnum_SALON_OWNER;
    case 'unknownDefaultOpenApi':
      return _$bookingSlugInfoResponseMasterTypeEnum_unknownDefaultOpenApi;
    default:
      return _$bookingSlugInfoResponseMasterTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<BookingSlugInfoResponseMasterTypeEnum>
    _$bookingSlugInfoResponseMasterTypeEnumValues = BuiltSet<
        BookingSlugInfoResponseMasterTypeEnum>(const <BookingSlugInfoResponseMasterTypeEnum>[
  _$bookingSlugInfoResponseMasterTypeEnum_SALON_MASTER,
  _$bookingSlugInfoResponseMasterTypeEnum_INDEPENDENT_MASTER,
  _$bookingSlugInfoResponseMasterTypeEnum_SALON_OWNER,
  _$bookingSlugInfoResponseMasterTypeEnum_unknownDefaultOpenApi,
]);

Serializer<BookingSlugInfoResponseMasterTypeEnum>
    _$bookingSlugInfoResponseMasterTypeEnumSerializer =
    _$BookingSlugInfoResponseMasterTypeEnumSerializer();

class _$BookingSlugInfoResponseMasterTypeEnumSerializer
    implements PrimitiveSerializer<BookingSlugInfoResponseMasterTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'SALON_OWNER': 'SALON_OWNER',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'SALON_MASTER': 'SALON_MASTER',
    'INDEPENDENT_MASTER': 'INDEPENDENT_MASTER',
    'SALON_OWNER': 'SALON_OWNER',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[
    BookingSlugInfoResponseMasterTypeEnum
  ];
  @override
  final String wireName = 'BookingSlugInfoResponseMasterTypeEnum';

  @override
  Object serialize(
          Serializers serializers, BookingSlugInfoResponseMasterTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BookingSlugInfoResponseMasterTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BookingSlugInfoResponseMasterTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BookingSlugInfoResponse extends BookingSlugInfoResponse {
  @override
  final String masterName;
  @override
  final String? avatarUrl;
  @override
  final String? bio;
  @override
  final BuiltList<ServiceSummaryDto> services;
  @override
  final String masterId;
  @override
  final BookingSlugInfoResponseMasterTypeEnum masterType;
  @override
  final String? professionalTitle;
  @override
  final String? city;
  @override
  final String? region;
  @override
  final BookingSlugSalonRef? salon;
  @override
  final num? avgRating;
  @override
  final int reviewCount;
  @override
  final BuiltList<CategoryRef> categories;
  @override
  final BuiltList<MediaFileResponse> portfolio;
  @override
  final BuiltList<ReviewResponse> latestReviews;
  @override
  final bool bookable;
  @override
  final DateTime updatedAt;
  @override
  final BuiltList<RatingBucket> ratingDistribution;
  @override
  final String? street;
  @override
  final String? buildingNo;
  @override
  final String? locationNote;

  factory _$BookingSlugInfoResponse(
          [void Function(BookingSlugInfoResponseBuilder)? updates]) =>
      (BookingSlugInfoResponseBuilder()..update(updates))._build();

  _$BookingSlugInfoResponse._(
      {required this.masterName,
      this.avatarUrl,
      this.bio,
      required this.services,
      required this.masterId,
      required this.masterType,
      this.professionalTitle,
      this.city,
      this.region,
      this.salon,
      this.avgRating,
      required this.reviewCount,
      required this.categories,
      required this.portfolio,
      required this.latestReviews,
      required this.bookable,
      required this.updatedAt,
      required this.ratingDistribution,
      this.street,
      this.buildingNo,
      this.locationNote})
      : super._();
  @override
  BookingSlugInfoResponse rebuild(
          void Function(BookingSlugInfoResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookingSlugInfoResponseBuilder toBuilder() =>
      BookingSlugInfoResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookingSlugInfoResponse &&
        masterName == other.masterName &&
        avatarUrl == other.avatarUrl &&
        bio == other.bio &&
        services == other.services &&
        masterId == other.masterId &&
        masterType == other.masterType &&
        professionalTitle == other.professionalTitle &&
        city == other.city &&
        region == other.region &&
        salon == other.salon &&
        avgRating == other.avgRating &&
        reviewCount == other.reviewCount &&
        categories == other.categories &&
        portfolio == other.portfolio &&
        latestReviews == other.latestReviews &&
        bookable == other.bookable &&
        updatedAt == other.updatedAt &&
        ratingDistribution == other.ratingDistribution &&
        street == other.street &&
        buildingNo == other.buildingNo &&
        locationNote == other.locationNote;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterName.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, bio.hashCode);
    _$hash = $jc(_$hash, services.hashCode);
    _$hash = $jc(_$hash, masterId.hashCode);
    _$hash = $jc(_$hash, masterType.hashCode);
    _$hash = $jc(_$hash, professionalTitle.hashCode);
    _$hash = $jc(_$hash, city.hashCode);
    _$hash = $jc(_$hash, region.hashCode);
    _$hash = $jc(_$hash, salon.hashCode);
    _$hash = $jc(_$hash, avgRating.hashCode);
    _$hash = $jc(_$hash, reviewCount.hashCode);
    _$hash = $jc(_$hash, categories.hashCode);
    _$hash = $jc(_$hash, portfolio.hashCode);
    _$hash = $jc(_$hash, latestReviews.hashCode);
    _$hash = $jc(_$hash, bookable.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, ratingDistribution.hashCode);
    _$hash = $jc(_$hash, street.hashCode);
    _$hash = $jc(_$hash, buildingNo.hashCode);
    _$hash = $jc(_$hash, locationNote.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookingSlugInfoResponse')
          ..add('masterName', masterName)
          ..add('avatarUrl', avatarUrl)
          ..add('bio', bio)
          ..add('services', services)
          ..add('masterId', masterId)
          ..add('masterType', masterType)
          ..add('professionalTitle', professionalTitle)
          ..add('city', city)
          ..add('region', region)
          ..add('salon', salon)
          ..add('avgRating', avgRating)
          ..add('reviewCount', reviewCount)
          ..add('categories', categories)
          ..add('portfolio', portfolio)
          ..add('latestReviews', latestReviews)
          ..add('bookable', bookable)
          ..add('updatedAt', updatedAt)
          ..add('ratingDistribution', ratingDistribution)
          ..add('street', street)
          ..add('buildingNo', buildingNo)
          ..add('locationNote', locationNote))
        .toString();
  }
}

class BookingSlugInfoResponseBuilder
    implements
        Builder<BookingSlugInfoResponse, BookingSlugInfoResponseBuilder> {
  _$BookingSlugInfoResponse? _$v;

  String? _masterName;
  String? get masterName => _$this._masterName;
  set masterName(String? masterName) => _$this._masterName = masterName;

  String? _avatarUrl;
  String? get avatarUrl => _$this._avatarUrl;
  set avatarUrl(String? avatarUrl) => _$this._avatarUrl = avatarUrl;

  String? _bio;
  String? get bio => _$this._bio;
  set bio(String? bio) => _$this._bio = bio;

  ListBuilder<ServiceSummaryDto>? _services;
  ListBuilder<ServiceSummaryDto> get services =>
      _$this._services ??= ListBuilder<ServiceSummaryDto>();
  set services(ListBuilder<ServiceSummaryDto>? services) =>
      _$this._services = services;

  String? _masterId;
  String? get masterId => _$this._masterId;
  set masterId(String? masterId) => _$this._masterId = masterId;

  BookingSlugInfoResponseMasterTypeEnum? _masterType;
  BookingSlugInfoResponseMasterTypeEnum? get masterType => _$this._masterType;
  set masterType(BookingSlugInfoResponseMasterTypeEnum? masterType) =>
      _$this._masterType = masterType;

  String? _professionalTitle;
  String? get professionalTitle => _$this._professionalTitle;
  set professionalTitle(String? professionalTitle) =>
      _$this._professionalTitle = professionalTitle;

  String? _city;
  String? get city => _$this._city;
  set city(String? city) => _$this._city = city;

  String? _region;
  String? get region => _$this._region;
  set region(String? region) => _$this._region = region;

  BookingSlugSalonRefBuilder? _salon;
  BookingSlugSalonRefBuilder get salon =>
      _$this._salon ??= BookingSlugSalonRefBuilder();
  set salon(BookingSlugSalonRefBuilder? salon) => _$this._salon = salon;

  num? _avgRating;
  num? get avgRating => _$this._avgRating;
  set avgRating(num? avgRating) => _$this._avgRating = avgRating;

  int? _reviewCount;
  int? get reviewCount => _$this._reviewCount;
  set reviewCount(int? reviewCount) => _$this._reviewCount = reviewCount;

  ListBuilder<CategoryRef>? _categories;
  ListBuilder<CategoryRef> get categories =>
      _$this._categories ??= ListBuilder<CategoryRef>();
  set categories(ListBuilder<CategoryRef>? categories) =>
      _$this._categories = categories;

  ListBuilder<MediaFileResponse>? _portfolio;
  ListBuilder<MediaFileResponse> get portfolio =>
      _$this._portfolio ??= ListBuilder<MediaFileResponse>();
  set portfolio(ListBuilder<MediaFileResponse>? portfolio) =>
      _$this._portfolio = portfolio;

  ListBuilder<ReviewResponse>? _latestReviews;
  ListBuilder<ReviewResponse> get latestReviews =>
      _$this._latestReviews ??= ListBuilder<ReviewResponse>();
  set latestReviews(ListBuilder<ReviewResponse>? latestReviews) =>
      _$this._latestReviews = latestReviews;

  bool? _bookable;
  bool? get bookable => _$this._bookable;
  set bookable(bool? bookable) => _$this._bookable = bookable;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  ListBuilder<RatingBucket>? _ratingDistribution;
  ListBuilder<RatingBucket> get ratingDistribution =>
      _$this._ratingDistribution ??= ListBuilder<RatingBucket>();
  set ratingDistribution(ListBuilder<RatingBucket>? ratingDistribution) =>
      _$this._ratingDistribution = ratingDistribution;

  String? _street;
  String? get street => _$this._street;
  set street(String? street) => _$this._street = street;

  String? _buildingNo;
  String? get buildingNo => _$this._buildingNo;
  set buildingNo(String? buildingNo) => _$this._buildingNo = buildingNo;

  String? _locationNote;
  String? get locationNote => _$this._locationNote;
  set locationNote(String? locationNote) => _$this._locationNote = locationNote;

  BookingSlugInfoResponseBuilder() {
    BookingSlugInfoResponse._defaults(this);
  }

  BookingSlugInfoResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterName = $v.masterName;
      _avatarUrl = $v.avatarUrl;
      _bio = $v.bio;
      _services = $v.services.toBuilder();
      _masterId = $v.masterId;
      _masterType = $v.masterType;
      _professionalTitle = $v.professionalTitle;
      _city = $v.city;
      _region = $v.region;
      _salon = $v.salon?.toBuilder();
      _avgRating = $v.avgRating;
      _reviewCount = $v.reviewCount;
      _categories = $v.categories.toBuilder();
      _portfolio = $v.portfolio.toBuilder();
      _latestReviews = $v.latestReviews.toBuilder();
      _bookable = $v.bookable;
      _updatedAt = $v.updatedAt;
      _ratingDistribution = $v.ratingDistribution.toBuilder();
      _street = $v.street;
      _buildingNo = $v.buildingNo;
      _locationNote = $v.locationNote;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookingSlugInfoResponse other) {
    _$v = other as _$BookingSlugInfoResponse;
  }

  @override
  void update(void Function(BookingSlugInfoResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookingSlugInfoResponse build() => _build();

  _$BookingSlugInfoResponse _build() {
    _$BookingSlugInfoResponse _$result;
    try {
      _$result = _$v ??
          _$BookingSlugInfoResponse._(
            masterName: BuiltValueNullFieldError.checkNotNull(
                masterName, r'BookingSlugInfoResponse', 'masterName'),
            avatarUrl: avatarUrl,
            bio: bio,
            services: services.build(),
            masterId: BuiltValueNullFieldError.checkNotNull(
                masterId, r'BookingSlugInfoResponse', 'masterId'),
            masterType: BuiltValueNullFieldError.checkNotNull(
                masterType, r'BookingSlugInfoResponse', 'masterType'),
            professionalTitle: professionalTitle,
            city: city,
            region: region,
            salon: _salon?.build(),
            avgRating: avgRating,
            reviewCount: BuiltValueNullFieldError.checkNotNull(
                reviewCount, r'BookingSlugInfoResponse', 'reviewCount'),
            categories: categories.build(),
            portfolio: portfolio.build(),
            latestReviews: latestReviews.build(),
            bookable: BuiltValueNullFieldError.checkNotNull(
                bookable, r'BookingSlugInfoResponse', 'bookable'),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'BookingSlugInfoResponse', 'updatedAt'),
            ratingDistribution: ratingDistribution.build(),
            street: street,
            buildingNo: buildingNo,
            locationNote: locationNote,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'services';
        services.build();

        _$failedField = 'salon';
        _salon?.build();

        _$failedField = 'categories';
        categories.build();
        _$failedField = 'portfolio';
        portfolio.build();
        _$failedField = 'latestReviews';
        latestReviews.build();

        _$failedField = 'ratingDistribution';
        ratingDistribution.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BookingSlugInfoResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
