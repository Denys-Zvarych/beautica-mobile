// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_link_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BookingLinkResponseKindEnum _$bookingLinkResponseKindEnum_MASTER =
    const BookingLinkResponseKindEnum._('MASTER');
const BookingLinkResponseKindEnum _$bookingLinkResponseKindEnum_SALON =
    const BookingLinkResponseKindEnum._('SALON');
const BookingLinkResponseKindEnum
    _$bookingLinkResponseKindEnum_unknownDefaultOpenApi =
    const BookingLinkResponseKindEnum._('unknownDefaultOpenApi');

BookingLinkResponseKindEnum _$bookingLinkResponseKindEnumValueOf(String name) {
  switch (name) {
    case 'MASTER':
      return _$bookingLinkResponseKindEnum_MASTER;
    case 'SALON':
      return _$bookingLinkResponseKindEnum_SALON;
    case 'unknownDefaultOpenApi':
      return _$bookingLinkResponseKindEnum_unknownDefaultOpenApi;
    default:
      return _$bookingLinkResponseKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<BookingLinkResponseKindEnum>
    _$bookingLinkResponseKindEnumValues =
    BuiltSet<BookingLinkResponseKindEnum>(const <BookingLinkResponseKindEnum>[
  _$bookingLinkResponseKindEnum_MASTER,
  _$bookingLinkResponseKindEnum_SALON,
  _$bookingLinkResponseKindEnum_unknownDefaultOpenApi,
]);

Serializer<BookingLinkResponseKindEnum>
    _$bookingLinkResponseKindEnumSerializer =
    _$BookingLinkResponseKindEnumSerializer();

class _$BookingLinkResponseKindEnumSerializer
    implements PrimitiveSerializer<BookingLinkResponseKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'MASTER': 'MASTER',
    'SALON': 'SALON',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'MASTER': 'MASTER',
    'SALON': 'SALON',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[BookingLinkResponseKindEnum];
  @override
  final String wireName = 'BookingLinkResponseKindEnum';

  @override
  Object serialize(Serializers serializers, BookingLinkResponseKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BookingLinkResponseKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BookingLinkResponseKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BookingLinkResponse extends BookingLinkResponse {
  @override
  final BookingLinkResponseKindEnum kind;
  @override
  final String slug;
  @override
  final String url;
  @override
  final String displayName;
  @override
  final String? salonId;
  @override
  final bool bookable;

  factory _$BookingLinkResponse(
          [void Function(BookingLinkResponseBuilder)? updates]) =>
      (BookingLinkResponseBuilder()..update(updates))._build();

  _$BookingLinkResponse._(
      {required this.kind,
      required this.slug,
      required this.url,
      required this.displayName,
      this.salonId,
      required this.bookable})
      : super._();
  @override
  BookingLinkResponse rebuild(
          void Function(BookingLinkResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookingLinkResponseBuilder toBuilder() =>
      BookingLinkResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookingLinkResponse &&
        kind == other.kind &&
        slug == other.slug &&
        url == other.url &&
        displayName == other.displayName &&
        salonId == other.salonId &&
        bookable == other.bookable;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, slug.hashCode);
    _$hash = $jc(_$hash, url.hashCode);
    _$hash = $jc(_$hash, displayName.hashCode);
    _$hash = $jc(_$hash, salonId.hashCode);
    _$hash = $jc(_$hash, bookable.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookingLinkResponse')
          ..add('kind', kind)
          ..add('slug', slug)
          ..add('url', url)
          ..add('displayName', displayName)
          ..add('salonId', salonId)
          ..add('bookable', bookable))
        .toString();
  }
}

class BookingLinkResponseBuilder
    implements Builder<BookingLinkResponse, BookingLinkResponseBuilder> {
  _$BookingLinkResponse? _$v;

  BookingLinkResponseKindEnum? _kind;
  BookingLinkResponseKindEnum? get kind => _$this._kind;
  set kind(BookingLinkResponseKindEnum? kind) => _$this._kind = kind;

  String? _slug;
  String? get slug => _$this._slug;
  set slug(String? slug) => _$this._slug = slug;

  String? _url;
  String? get url => _$this._url;
  set url(String? url) => _$this._url = url;

  String? _displayName;
  String? get displayName => _$this._displayName;
  set displayName(String? displayName) => _$this._displayName = displayName;

  String? _salonId;
  String? get salonId => _$this._salonId;
  set salonId(String? salonId) => _$this._salonId = salonId;

  bool? _bookable;
  bool? get bookable => _$this._bookable;
  set bookable(bool? bookable) => _$this._bookable = bookable;

  BookingLinkResponseBuilder() {
    BookingLinkResponse._defaults(this);
  }

  BookingLinkResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _slug = $v.slug;
      _url = $v.url;
      _displayName = $v.displayName;
      _salonId = $v.salonId;
      _bookable = $v.bookable;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookingLinkResponse other) {
    _$v = other as _$BookingLinkResponse;
  }

  @override
  void update(void Function(BookingLinkResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookingLinkResponse build() => _build();

  _$BookingLinkResponse _build() {
    final _$result = _$v ??
        _$BookingLinkResponse._(
          kind: BuiltValueNullFieldError.checkNotNull(
              kind, r'BookingLinkResponse', 'kind'),
          slug: BuiltValueNullFieldError.checkNotNull(
              slug, r'BookingLinkResponse', 'slug'),
          url: BuiltValueNullFieldError.checkNotNull(
              url, r'BookingLinkResponse', 'url'),
          displayName: BuiltValueNullFieldError.checkNotNull(
              displayName, r'BookingLinkResponse', 'displayName'),
          salonId: salonId,
          bookable: BuiltValueNullFieldError.checkNotNull(
              bookable, r'BookingLinkResponse', 'bookable'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
