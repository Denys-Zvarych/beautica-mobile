// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guest_telegram_status_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$GuestTelegramStatusResponse extends GuestTelegramStatusResponse {
  @override
  final bool? available;
  @override
  final bool? linked;
  @override
  final bool? offerChoice;

  factory _$GuestTelegramStatusResponse(
          [void Function(GuestTelegramStatusResponseBuilder)? updates]) =>
      (GuestTelegramStatusResponseBuilder()..update(updates))._build();

  _$GuestTelegramStatusResponse._(
      {this.available, this.linked, this.offerChoice})
      : super._();
  @override
  GuestTelegramStatusResponse rebuild(
          void Function(GuestTelegramStatusResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  GuestTelegramStatusResponseBuilder toBuilder() =>
      GuestTelegramStatusResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is GuestTelegramStatusResponse &&
        available == other.available &&
        linked == other.linked &&
        offerChoice == other.offerChoice;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, available.hashCode);
    _$hash = $jc(_$hash, linked.hashCode);
    _$hash = $jc(_$hash, offerChoice.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'GuestTelegramStatusResponse')
          ..add('available', available)
          ..add('linked', linked)
          ..add('offerChoice', offerChoice))
        .toString();
  }
}

class GuestTelegramStatusResponseBuilder
    implements
        Builder<GuestTelegramStatusResponse,
            GuestTelegramStatusResponseBuilder> {
  _$GuestTelegramStatusResponse? _$v;

  bool? _available;
  bool? get available => _$this._available;
  set available(bool? available) => _$this._available = available;

  bool? _linked;
  bool? get linked => _$this._linked;
  set linked(bool? linked) => _$this._linked = linked;

  bool? _offerChoice;
  bool? get offerChoice => _$this._offerChoice;
  set offerChoice(bool? offerChoice) => _$this._offerChoice = offerChoice;

  GuestTelegramStatusResponseBuilder() {
    GuestTelegramStatusResponse._defaults(this);
  }

  GuestTelegramStatusResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _available = $v.available;
      _linked = $v.linked;
      _offerChoice = $v.offerChoice;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(GuestTelegramStatusResponse other) {
    _$v = other as _$GuestTelegramStatusResponse;
  }

  @override
  void update(void Function(GuestTelegramStatusResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  GuestTelegramStatusResponse build() => _build();

  _$GuestTelegramStatusResponse _build() {
    final _$result = _$v ??
        _$GuestTelegramStatusResponse._(
          available: available,
          linked: linked,
          offerChoice: offerChoice,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
