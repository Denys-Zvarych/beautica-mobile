// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appointment_item_reschedule_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppointmentItemRescheduleRequest
    extends AppointmentItemRescheduleRequest {
  @override
  final DateTime newStartsAt;
  @override
  final bool? allowClientOverlap;

  factory _$AppointmentItemRescheduleRequest(
          [void Function(AppointmentItemRescheduleRequestBuilder)? updates]) =>
      (AppointmentItemRescheduleRequestBuilder()..update(updates))._build();

  _$AppointmentItemRescheduleRequest._(
      {required this.newStartsAt, this.allowClientOverlap})
      : super._();
  @override
  AppointmentItemRescheduleRequest rebuild(
          void Function(AppointmentItemRescheduleRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppointmentItemRescheduleRequestBuilder toBuilder() =>
      AppointmentItemRescheduleRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppointmentItemRescheduleRequest &&
        newStartsAt == other.newStartsAt &&
        allowClientOverlap == other.allowClientOverlap;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, newStartsAt.hashCode);
    _$hash = $jc(_$hash, allowClientOverlap.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppointmentItemRescheduleRequest')
          ..add('newStartsAt', newStartsAt)
          ..add('allowClientOverlap', allowClientOverlap))
        .toString();
  }
}

class AppointmentItemRescheduleRequestBuilder
    implements
        Builder<AppointmentItemRescheduleRequest,
            AppointmentItemRescheduleRequestBuilder> {
  _$AppointmentItemRescheduleRequest? _$v;

  DateTime? _newStartsAt;
  DateTime? get newStartsAt => _$this._newStartsAt;
  set newStartsAt(DateTime? newStartsAt) => _$this._newStartsAt = newStartsAt;

  bool? _allowClientOverlap;
  bool? get allowClientOverlap => _$this._allowClientOverlap;
  set allowClientOverlap(bool? allowClientOverlap) =>
      _$this._allowClientOverlap = allowClientOverlap;

  AppointmentItemRescheduleRequestBuilder() {
    AppointmentItemRescheduleRequest._defaults(this);
  }

  AppointmentItemRescheduleRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _newStartsAt = $v.newStartsAt;
      _allowClientOverlap = $v.allowClientOverlap;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppointmentItemRescheduleRequest other) {
    _$v = other as _$AppointmentItemRescheduleRequest;
  }

  @override
  void update(void Function(AppointmentItemRescheduleRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppointmentItemRescheduleRequest build() => _build();

  _$AppointmentItemRescheduleRequest _build() {
    final _$result = _$v ??
        _$AppointmentItemRescheduleRequest._(
          newStartsAt: BuiltValueNullFieldError.checkNotNull(
              newStartsAt, r'AppointmentItemRescheduleRequest', 'newStartsAt'),
          allowClientOverlap: allowClientOverlap,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
