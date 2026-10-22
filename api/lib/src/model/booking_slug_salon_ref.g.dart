// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_slug_salon_ref.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BookingSlugSalonRef extends BookingSlugSalonRef {
  @override
  final String name;
  @override
  final String? bookingSlug;

  factory _$BookingSlugSalonRef(
          [void Function(BookingSlugSalonRefBuilder)? updates]) =>
      (BookingSlugSalonRefBuilder()..update(updates))._build();

  _$BookingSlugSalonRef._({required this.name, this.bookingSlug}) : super._();
  @override
  BookingSlugSalonRef rebuild(
          void Function(BookingSlugSalonRefBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BookingSlugSalonRefBuilder toBuilder() =>
      BookingSlugSalonRefBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BookingSlugSalonRef &&
        name == other.name &&
        bookingSlug == other.bookingSlug;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, bookingSlug.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BookingSlugSalonRef')
          ..add('name', name)
          ..add('bookingSlug', bookingSlug))
        .toString();
  }
}

class BookingSlugSalonRefBuilder
    implements Builder<BookingSlugSalonRef, BookingSlugSalonRefBuilder> {
  _$BookingSlugSalonRef? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _bookingSlug;
  String? get bookingSlug => _$this._bookingSlug;
  set bookingSlug(String? bookingSlug) => _$this._bookingSlug = bookingSlug;

  BookingSlugSalonRefBuilder() {
    BookingSlugSalonRef._defaults(this);
  }

  BookingSlugSalonRefBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _bookingSlug = $v.bookingSlug;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BookingSlugSalonRef other) {
    _$v = other as _$BookingSlugSalonRef;
  }

  @override
  void update(void Function(BookingSlugSalonRefBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BookingSlugSalonRef build() => _build();

  _$BookingSlugSalonRef _build() {
    final _$result = _$v ??
        _$BookingSlugSalonRef._(
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'BookingSlugSalonRef', 'name'),
          bookingSlug: bookingSlug,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
