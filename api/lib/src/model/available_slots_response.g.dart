// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'available_slots_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AvailableSlotsResponse extends AvailableSlotsResponse {
  @override
  final Date? date;
  @override
  final BuiltList<AvailableSlotResponse>? slots;

  factory _$AvailableSlotsResponse(
          [void Function(AvailableSlotsResponseBuilder)? updates]) =>
      (AvailableSlotsResponseBuilder()..update(updates))._build();

  _$AvailableSlotsResponse._({this.date, this.slots}) : super._();
  @override
  AvailableSlotsResponse rebuild(
          void Function(AvailableSlotsResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AvailableSlotsResponseBuilder toBuilder() =>
      AvailableSlotsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AvailableSlotsResponse &&
        date == other.date &&
        slots == other.slots;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, slots.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AvailableSlotsResponse')
          ..add('date', date)
          ..add('slots', slots))
        .toString();
  }
}

class AvailableSlotsResponseBuilder
    implements Builder<AvailableSlotsResponse, AvailableSlotsResponseBuilder> {
  _$AvailableSlotsResponse? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  ListBuilder<AvailableSlotResponse>? _slots;
  ListBuilder<AvailableSlotResponse> get slots =>
      _$this._slots ??= ListBuilder<AvailableSlotResponse>();
  set slots(ListBuilder<AvailableSlotResponse>? slots) => _$this._slots = slots;

  AvailableSlotsResponseBuilder() {
    AvailableSlotsResponse._defaults(this);
  }

  AvailableSlotsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _slots = $v.slots?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AvailableSlotsResponse other) {
    _$v = other as _$AvailableSlotsResponse;
  }

  @override
  void update(void Function(AvailableSlotsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AvailableSlotsResponse build() => _build();

  _$AvailableSlotsResponse _build() {
    _$AvailableSlotsResponse _$result;
    try {
      _$result = _$v ??
          _$AvailableSlotsResponse._(
            date: date,
            slots: _slots?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'slots';
        _slots?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AvailableSlotsResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
