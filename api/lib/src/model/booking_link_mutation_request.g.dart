// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_link_mutation_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookingLinkMutationRequest extends BookingLinkMutationRequest {
  @override
  final String? currentSlug;

  factory _$BookingLinkMutationRequest(
          [void Function(BookingLinkMutationRequestBuilder)? updates]) =>
      (BookingLinkMutationRequestBuilder()..update(updates))._build();

  _$BookingLinkMutationRequest._({this.currentSlug}) : super._();
  @override
  BookingLinkMutationRequest rebuild(
          void Function(BookingLinkMutationRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookingLinkMutationRequestBuilder toBuilder() =>
      BookingLinkMutationRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookingLinkMutationRequest &&
        currentSlug == other.currentSlug;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, currentSlug.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookingLinkMutationRequest')
          ..add('currentSlug', currentSlug))
        .toString();
  }
}

class BookingLinkMutationRequestBuilder
    implements
        Builder<BookingLinkMutationRequest, BookingLinkMutationRequestBuilder> {
  _$BookingLinkMutationRequest? _$v;

  String? _currentSlug;
  String? get currentSlug => _$this._currentSlug;
  set currentSlug(String? currentSlug) => _$this._currentSlug = currentSlug;

  BookingLinkMutationRequestBuilder() {
    BookingLinkMutationRequest._defaults(this);
  }

  BookingLinkMutationRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _currentSlug = $v.currentSlug;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookingLinkMutationRequest other) {
    _$v = other as _$BookingLinkMutationRequest;
  }

  @override
  void update(void Function(BookingLinkMutationRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookingLinkMutationRequest build() => _build();

  _$BookingLinkMutationRequest _build() {
    final _$result = _$v ??
        _$BookingLinkMutationRequest._(
          currentSlug: currentSlug,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
