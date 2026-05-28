// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'available_slot_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AvailableSlotResponse extends AvailableSlotResponse {
  @override
  final DateTime? startsAt;
  @override
  final DateTime? endsAt;

  factory _$AvailableSlotResponse(
          [void Function(AvailableSlotResponseBuilder)? updates]) =>
      (AvailableSlotResponseBuilder()..update(updates))._build();

  _$AvailableSlotResponse._({this.startsAt, this.endsAt}) : super._();
  @override
  AvailableSlotResponse rebuild(
          void Function(AvailableSlotResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AvailableSlotResponseBuilder toBuilder() =>
      AvailableSlotResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AvailableSlotResponse &&
        startsAt == other.startsAt &&
        endsAt == other.endsAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, startsAt.hashCode);
    _$hash = $jc(_$hash, endsAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AvailableSlotResponse')
          ..add('startsAt', startsAt)
          ..add('endsAt', endsAt))
        .toString();
  }
}

class AvailableSlotResponseBuilder
    implements Builder<AvailableSlotResponse, AvailableSlotResponseBuilder> {
  _$AvailableSlotResponse? _$v;

  DateTime? _startsAt;
  DateTime? get startsAt => _$this._startsAt;
  set startsAt(DateTime? startsAt) => _$this._startsAt = startsAt;

  DateTime? _endsAt;
  DateTime? get endsAt => _$this._endsAt;
  set endsAt(DateTime? endsAt) => _$this._endsAt = endsAt;

  AvailableSlotResponseBuilder() {
    AvailableSlotResponse._defaults(this);
  }

  AvailableSlotResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _startsAt = $v.startsAt;
      _endsAt = $v.endsAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AvailableSlotResponse other) {
    _$v = other as _$AvailableSlotResponse;
  }

  @override
  void update(void Function(AvailableSlotResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AvailableSlotResponse build() => _build();

  _$AvailableSlotResponse _build() {
    final _$result = _$v ??
        _$AvailableSlotResponse._(
          startsAt: startsAt,
          endsAt: endsAt,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
