// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_slug_info_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookingSlugInfoResponse extends BookingSlugInfoResponse {
  @override
  final String? masterName;
  @override
  final String? avatarUrl;
  @override
  final String? bio;
  @override
  final BuiltList<ServiceSummaryDto>? services;

  factory _$BookingSlugInfoResponse(
          [void Function(BookingSlugInfoResponseBuilder)? updates]) =>
      (BookingSlugInfoResponseBuilder()..update(updates))._build();

  _$BookingSlugInfoResponse._(
      {this.masterName, this.avatarUrl, this.bio, this.services})
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
        services == other.services;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, masterName.hashCode);
    _$hash = $jc(_$hash, avatarUrl.hashCode);
    _$hash = $jc(_$hash, bio.hashCode);
    _$hash = $jc(_$hash, services.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookingSlugInfoResponse')
          ..add('masterName', masterName)
          ..add('avatarUrl', avatarUrl)
          ..add('bio', bio)
          ..add('services', services))
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

  BookingSlugInfoResponseBuilder() {
    BookingSlugInfoResponse._defaults(this);
  }

  BookingSlugInfoResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _masterName = $v.masterName;
      _avatarUrl = $v.avatarUrl;
      _bio = $v.bio;
      _services = $v.services?.toBuilder();
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
            masterName: masterName,
            avatarUrl: avatarUrl,
            bio: bio,
            services: _services?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'services';
        _services?.build();
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
