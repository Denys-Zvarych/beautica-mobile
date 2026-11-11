// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'telegram_availability.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TelegramAvailability extends TelegramAvailability {
  @override
  final bool? available;
  @override
  final bool? linked;

  factory _$TelegramAvailability(
          [void Function(TelegramAvailabilityBuilder)? updates]) =>
      (TelegramAvailabilityBuilder()..update(updates))._build();

  _$TelegramAvailability._({this.available, this.linked}) : super._();
  @override
  TelegramAvailability rebuild(
          void Function(TelegramAvailabilityBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TelegramAvailabilityBuilder toBuilder() =>
      TelegramAvailabilityBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TelegramAvailability &&
        available == other.available &&
        linked == other.linked;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, available.hashCode);
    _$hash = $jc(_$hash, linked.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TelegramAvailability')
          ..add('available', available)
          ..add('linked', linked))
        .toString();
  }
}

class TelegramAvailabilityBuilder
    implements Builder<TelegramAvailability, TelegramAvailabilityBuilder> {
  _$TelegramAvailability? _$v;

  bool? _available;
  bool? get available => _$this._available;
  set available(bool? available) => _$this._available = available;

  bool? _linked;
  bool? get linked => _$this._linked;
  set linked(bool? linked) => _$this._linked = linked;

  TelegramAvailabilityBuilder() {
    TelegramAvailability._defaults(this);
  }

  TelegramAvailabilityBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _available = $v.available;
      _linked = $v.linked;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TelegramAvailability other) {
    _$v = other as _$TelegramAvailability;
  }

  @override
  void update(void Function(TelegramAvailabilityBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TelegramAvailability build() => _build();

  _$TelegramAvailability _build() {
    final _$result = _$v ??
        _$TelegramAvailability._(
          available: available,
          linked: linked,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
