// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appointment_cancel_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppointmentCancelRequest extends AppointmentCancelRequest {
  @override
  final String? clientCancellationNote;

  factory _$AppointmentCancelRequest(
          [void Function(AppointmentCancelRequestBuilder)? updates]) =>
      (AppointmentCancelRequestBuilder()..update(updates))._build();

  _$AppointmentCancelRequest._({this.clientCancellationNote}) : super._();
  @override
  AppointmentCancelRequest rebuild(
          void Function(AppointmentCancelRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppointmentCancelRequestBuilder toBuilder() =>
      AppointmentCancelRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppointmentCancelRequest &&
        clientCancellationNote == other.clientCancellationNote;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, clientCancellationNote.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppointmentCancelRequest')
          ..add('clientCancellationNote', clientCancellationNote))
        .toString();
  }
}

class AppointmentCancelRequestBuilder
    implements
        Builder<AppointmentCancelRequest, AppointmentCancelRequestBuilder> {
  _$AppointmentCancelRequest? _$v;

  String? _clientCancellationNote;
  String? get clientCancellationNote => _$this._clientCancellationNote;
  set clientCancellationNote(String? clientCancellationNote) =>
      _$this._clientCancellationNote = clientCancellationNote;

  AppointmentCancelRequestBuilder() {
    AppointmentCancelRequest._defaults(this);
  }

  AppointmentCancelRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _clientCancellationNote = $v.clientCancellationNote;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppointmentCancelRequest other) {
    _$v = other as _$AppointmentCancelRequest;
  }

  @override
  void update(void Function(AppointmentCancelRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppointmentCancelRequest build() => _build();

  _$AppointmentCancelRequest _build() {
    final _$result = _$v ??
        _$AppointmentCancelRequest._(
          clientCancellationNote: clientCancellationNote,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
