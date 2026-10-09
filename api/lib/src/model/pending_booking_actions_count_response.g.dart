// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_booking_actions_count_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PendingBookingActionsCountResponse
    extends PendingBookingActionsCountResponse {
  @override
  final int? count;
  @override
  final int? toClose;
  @override
  final int? toRateClient;

  factory _$PendingBookingActionsCountResponse(
          [void Function(PendingBookingActionsCountResponseBuilder)?
              updates]) =>
      (PendingBookingActionsCountResponseBuilder()..update(updates))._build();

  _$PendingBookingActionsCountResponse._(
      {this.count, this.toClose, this.toRateClient})
      : super._();
  @override
  PendingBookingActionsCountResponse rebuild(
          void Function(PendingBookingActionsCountResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PendingBookingActionsCountResponseBuilder toBuilder() =>
      PendingBookingActionsCountResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PendingBookingActionsCountResponse &&
        count == other.count &&
        toClose == other.toClose &&
        toRateClient == other.toRateClient;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, count.hashCode);
    _$hash = $jc(_$hash, toClose.hashCode);
    _$hash = $jc(_$hash, toRateClient.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PendingBookingActionsCountResponse')
          ..add('count', count)
          ..add('toClose', toClose)
          ..add('toRateClient', toRateClient))
        .toString();
  }
}

class PendingBookingActionsCountResponseBuilder
    implements
        Builder<PendingBookingActionsCountResponse,
            PendingBookingActionsCountResponseBuilder> {
  _$PendingBookingActionsCountResponse? _$v;

  int? _count;
  int? get count => _$this._count;
  set count(int? count) => _$this._count = count;

  int? _toClose;
  int? get toClose => _$this._toClose;
  set toClose(int? toClose) => _$this._toClose = toClose;

  int? _toRateClient;
  int? get toRateClient => _$this._toRateClient;
  set toRateClient(int? toRateClient) => _$this._toRateClient = toRateClient;

  PendingBookingActionsCountResponseBuilder() {
    PendingBookingActionsCountResponse._defaults(this);
  }

  PendingBookingActionsCountResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _count = $v.count;
      _toClose = $v.toClose;
      _toRateClient = $v.toRateClient;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PendingBookingActionsCountResponse other) {
    _$v = other as _$PendingBookingActionsCountResponse;
  }

  @override
  void update(
      void Function(PendingBookingActionsCountResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PendingBookingActionsCountResponse build() => _build();

  _$PendingBookingActionsCountResponse _build() {
    final _$result = _$v ??
        _$PendingBookingActionsCountResponse._(
          count: count,
          toClose: toClose,
          toRateClient: toRateClient,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
