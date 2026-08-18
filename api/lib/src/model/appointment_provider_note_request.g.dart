// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appointment_provider_note_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppointmentProviderNoteRequest extends AppointmentProviderNoteRequest {
  @override
  final String? providerComment;

  factory _$AppointmentProviderNoteRequest(
          [void Function(AppointmentProviderNoteRequestBuilder)? updates]) =>
      (AppointmentProviderNoteRequestBuilder()..update(updates))._build();

  _$AppointmentProviderNoteRequest._({this.providerComment}) : super._();
  @override
  AppointmentProviderNoteRequest rebuild(
          void Function(AppointmentProviderNoteRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppointmentProviderNoteRequestBuilder toBuilder() =>
      AppointmentProviderNoteRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppointmentProviderNoteRequest &&
        providerComment == other.providerComment;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, providerComment.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppointmentProviderNoteRequest')
          ..add('providerComment', providerComment))
        .toString();
  }
}

class AppointmentProviderNoteRequestBuilder
    implements
        Builder<AppointmentProviderNoteRequest,
            AppointmentProviderNoteRequestBuilder> {
  _$AppointmentProviderNoteRequest? _$v;

  String? _providerComment;
  String? get providerComment => _$this._providerComment;
  set providerComment(String? providerComment) =>
      _$this._providerComment = providerComment;

  AppointmentProviderNoteRequestBuilder() {
    AppointmentProviderNoteRequest._defaults(this);
  }

  AppointmentProviderNoteRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _providerComment = $v.providerComment;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppointmentProviderNoteRequest other) {
    _$v = other as _$AppointmentProviderNoteRequest;
  }

  @override
  void update(void Function(AppointmentProviderNoteRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppointmentProviderNoteRequest build() => _build();

  _$AppointmentProviderNoteRequest _build() {
    final _$result = _$v ??
        _$AppointmentProviderNoteRequest._(
          providerComment: providerComment,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
