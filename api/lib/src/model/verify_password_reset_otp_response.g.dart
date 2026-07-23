// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'verify_password_reset_otp_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$VerifyPasswordResetOtpResponse extends VerifyPasswordResetOtpResponse {
  @override
  final String? resetTicket;

  factory _$VerifyPasswordResetOtpResponse(
          [void Function(VerifyPasswordResetOtpResponseBuilder)? updates]) =>
      (VerifyPasswordResetOtpResponseBuilder()..update(updates))._build();

  _$VerifyPasswordResetOtpResponse._({this.resetTicket}) : super._();
  @override
  VerifyPasswordResetOtpResponse rebuild(
          void Function(VerifyPasswordResetOtpResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  VerifyPasswordResetOtpResponseBuilder toBuilder() =>
      VerifyPasswordResetOtpResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is VerifyPasswordResetOtpResponse &&
        resetTicket == other.resetTicket;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, resetTicket.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'VerifyPasswordResetOtpResponse')
          ..add('resetTicket', resetTicket))
        .toString();
  }
}

class VerifyPasswordResetOtpResponseBuilder
    implements
        Builder<VerifyPasswordResetOtpResponse,
            VerifyPasswordResetOtpResponseBuilder> {
  _$VerifyPasswordResetOtpResponse? _$v;

  String? _resetTicket;
  String? get resetTicket => _$this._resetTicket;
  set resetTicket(String? resetTicket) => _$this._resetTicket = resetTicket;

  VerifyPasswordResetOtpResponseBuilder() {
    VerifyPasswordResetOtpResponse._defaults(this);
  }

  VerifyPasswordResetOtpResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _resetTicket = $v.resetTicket;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(VerifyPasswordResetOtpResponse other) {
    _$v = other as _$VerifyPasswordResetOtpResponse;
  }

  @override
  void update(void Function(VerifyPasswordResetOtpResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  VerifyPasswordResetOtpResponse build() => _build();

  _$VerifyPasswordResetOtpResponse _build() {
    final _$result = _$v ??
        _$VerifyPasswordResetOtpResponse._(
          resetTicket: resetTicket,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
