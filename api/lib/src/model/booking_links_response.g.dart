// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_links_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookingLinksResponse extends BookingLinksResponse {
  @override
  final bool shareEnabled;
  @override
  final BuiltList<BookingLinkResponse> links;

  factory _$BookingLinksResponse(
          [void Function(BookingLinksResponseBuilder)? updates]) =>
      (BookingLinksResponseBuilder()..update(updates))._build();

  _$BookingLinksResponse._({required this.shareEnabled, required this.links})
      : super._();
  @override
  BookingLinksResponse rebuild(
          void Function(BookingLinksResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookingLinksResponseBuilder toBuilder() =>
      BookingLinksResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookingLinksResponse &&
        shareEnabled == other.shareEnabled &&
        links == other.links;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, shareEnabled.hashCode);
    _$hash = $jc(_$hash, links.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookingLinksResponse')
          ..add('shareEnabled', shareEnabled)
          ..add('links', links))
        .toString();
  }
}

class BookingLinksResponseBuilder
    implements Builder<BookingLinksResponse, BookingLinksResponseBuilder> {
  _$BookingLinksResponse? _$v;

  bool? _shareEnabled;
  bool? get shareEnabled => _$this._shareEnabled;
  set shareEnabled(bool? shareEnabled) => _$this._shareEnabled = shareEnabled;

  ListBuilder<BookingLinkResponse>? _links;
  ListBuilder<BookingLinkResponse> get links =>
      _$this._links ??= ListBuilder<BookingLinkResponse>();
  set links(ListBuilder<BookingLinkResponse>? links) => _$this._links = links;

  BookingLinksResponseBuilder() {
    BookingLinksResponse._defaults(this);
  }

  BookingLinksResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _shareEnabled = $v.shareEnabled;
      _links = $v.links.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookingLinksResponse other) {
    _$v = other as _$BookingLinksResponse;
  }

  @override
  void update(void Function(BookingLinksResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookingLinksResponse build() => _build();

  _$BookingLinksResponse _build() {
    _$BookingLinksResponse _$result;
    try {
      _$result = _$v ??
          _$BookingLinksResponse._(
            shareEnabled: BuiltValueNullFieldError.checkNotNull(
                shareEnabled, r'BookingLinksResponse', 'shareEnabled'),
            links: links.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'links';
        links.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BookingLinksResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
