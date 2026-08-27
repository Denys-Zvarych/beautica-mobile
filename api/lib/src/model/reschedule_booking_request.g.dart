// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reschedule_booking_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RescheduleBookingRequest extends RescheduleBookingRequest {
  @override
  final DateTime newStartsAt;
  @override
  final bool? allowClientOverlap;

  factory _$RescheduleBookingRequest(
          [void Function(RescheduleBookingRequestBuilder)? updates]) =>
      (RescheduleBookingRequestBuilder()..update(updates))._build();

  _$RescheduleBookingRequest._(
      {required this.newStartsAt, this.allowClientOverlap})
      : super._();
  @override
  RescheduleBookingRequest rebuild(
          void Function(RescheduleBookingRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RescheduleBookingRequestBuilder toBuilder() =>
      RescheduleBookingRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RescheduleBookingRequest &&
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
    return (newBuiltValueToStringHelper(r'RescheduleBookingRequest')
          ..add('newStartsAt', newStartsAt)
          ..add('allowClientOverlap', allowClientOverlap))
        .toString();
  }
}

class RescheduleBookingRequestBuilder
    implements
        Builder<RescheduleBookingRequest, RescheduleBookingRequestBuilder> {
  _$RescheduleBookingRequest? _$v;

  DateTime? _newStartsAt;
  DateTime? get newStartsAt => _$this._newStartsAt;
  set newStartsAt(DateTime? newStartsAt) => _$this._newStartsAt = newStartsAt;

  bool? _allowClientOverlap;
  bool? get allowClientOverlap => _$this._allowClientOverlap;
  set allowClientOverlap(bool? allowClientOverlap) =>
      _$this._allowClientOverlap = allowClientOverlap;

  RescheduleBookingRequestBuilder() {
    RescheduleBookingRequest._defaults(this);
  }

  RescheduleBookingRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _newStartsAt = $v.newStartsAt;
      _allowClientOverlap = $v.allowClientOverlap;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RescheduleBookingRequest other) {
    _$v = other as _$RescheduleBookingRequest;
  }

  @override
  void update(void Function(RescheduleBookingRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RescheduleBookingRequest build() => _build();

  _$RescheduleBookingRequest _build() {
    final _$result = _$v ??
        _$RescheduleBookingRequest._(
          newStartsAt: BuiltValueNullFieldError.checkNotNull(
              newStartsAt, r'RescheduleBookingRequest', 'newStartsAt'),
          allowClientOverlap: allowClientOverlap,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
