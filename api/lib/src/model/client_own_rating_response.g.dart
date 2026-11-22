// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_own_rating_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ClientOwnRatingResponse extends ClientOwnRatingResponse {
  @override
  final String? bookingId;
  @override
  final DateTime? visitAt;
  @override
  final String? serviceName;
  @override
  final int? stars;

  factory _$ClientOwnRatingResponse(
          [void Function(ClientOwnRatingResponseBuilder)? updates]) =>
      (ClientOwnRatingResponseBuilder()..update(updates))._build();

  _$ClientOwnRatingResponse._(
      {this.bookingId, this.visitAt, this.serviceName, this.stars})
      : super._();
  @override
  ClientOwnRatingResponse rebuild(
          void Function(ClientOwnRatingResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ClientOwnRatingResponseBuilder toBuilder() =>
      ClientOwnRatingResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClientOwnRatingResponse &&
        bookingId == other.bookingId &&
        visitAt == other.visitAt &&
        serviceName == other.serviceName &&
        stars == other.stars;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, bookingId.hashCode);
    _$hash = $jc(_$hash, visitAt.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, stars.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ClientOwnRatingResponse')
          ..add('bookingId', bookingId)
          ..add('visitAt', visitAt)
          ..add('serviceName', serviceName)
          ..add('stars', stars))
        .toString();
  }
}

class ClientOwnRatingResponseBuilder
    implements
        Builder<ClientOwnRatingResponse, ClientOwnRatingResponseBuilder> {
  _$ClientOwnRatingResponse? _$v;

  String? _bookingId;
  String? get bookingId => _$this._bookingId;
  set bookingId(String? bookingId) => _$this._bookingId = bookingId;

  DateTime? _visitAt;
  DateTime? get visitAt => _$this._visitAt;
  set visitAt(DateTime? visitAt) => _$this._visitAt = visitAt;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  int? _stars;
  int? get stars => _$this._stars;
  set stars(int? stars) => _$this._stars = stars;

  ClientOwnRatingResponseBuilder() {
    ClientOwnRatingResponse._defaults(this);
  }

  ClientOwnRatingResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _bookingId = $v.bookingId;
      _visitAt = $v.visitAt;
      _serviceName = $v.serviceName;
      _stars = $v.stars;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClientOwnRatingResponse other) {
    _$v = other as _$ClientOwnRatingResponse;
  }

  @override
  void update(void Function(ClientOwnRatingResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClientOwnRatingResponse build() => _build();

  _$ClientOwnRatingResponse _build() {
    final _$result = _$v ??
        _$ClientOwnRatingResponse._(
          bookingId: bookingId,
          visitAt: visitAt,
          serviceName: serviceName,
          stars: stars,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
