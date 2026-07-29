// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appointment_reschedule_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppointmentRescheduleRequest extends AppointmentRescheduleRequest {
  @override
  final DateTime newStartsAt;

  factory _$AppointmentRescheduleRequest(
          [void Function(AppointmentRescheduleRequestBuilder)? updates]) =>
      (AppointmentRescheduleRequestBuilder()..update(updates))._build();

  _$AppointmentRescheduleRequest._({required this.newStartsAt}) : super._();
  @override
  AppointmentRescheduleRequest rebuild(
          void Function(AppointmentRescheduleRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppointmentRescheduleRequestBuilder toBuilder() =>
      AppointmentRescheduleRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppointmentRescheduleRequest &&
        newStartsAt == other.newStartsAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, newStartsAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppointmentRescheduleRequest')
          ..add('newStartsAt', newStartsAt))
        .toString();
  }
}

class AppointmentRescheduleRequestBuilder
    implements
        Builder<AppointmentRescheduleRequest,
            AppointmentRescheduleRequestBuilder> {
  _$AppointmentRescheduleRequest? _$v;

  DateTime? _newStartsAt;
  DateTime? get newStartsAt => _$this._newStartsAt;
  set newStartsAt(DateTime? newStartsAt) => _$this._newStartsAt = newStartsAt;

  AppointmentRescheduleRequestBuilder() {
    AppointmentRescheduleRequest._defaults(this);
  }

  AppointmentRescheduleRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _newStartsAt = $v.newStartsAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppointmentRescheduleRequest other) {
    _$v = other as _$AppointmentRescheduleRequest;
  }

  @override
  void update(void Function(AppointmentRescheduleRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppointmentRescheduleRequest build() => _build();

  _$AppointmentRescheduleRequest _build() {
    final _$result = _$v ??
        _$AppointmentRescheduleRequest._(
          newStartsAt: BuiltValueNullFieldError.checkNotNull(
              newStartsAt, r'AppointmentRescheduleRequest', 'newStartsAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
