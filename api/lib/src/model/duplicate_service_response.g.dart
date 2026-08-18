// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'duplicate_service_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DuplicateServiceResponse extends DuplicateServiceResponse {
  @override
  final String? code;
  @override
  final String? serviceName;
  @override
  final String? existingServiceDefId;

  factory _$DuplicateServiceResponse(
          [void Function(DuplicateServiceResponseBuilder)? updates]) =>
      (DuplicateServiceResponseBuilder()..update(updates))._build();

  _$DuplicateServiceResponse._(
      {this.code, this.serviceName, this.existingServiceDefId})
      : super._();
  @override
  DuplicateServiceResponse rebuild(
          void Function(DuplicateServiceResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DuplicateServiceResponseBuilder toBuilder() =>
      DuplicateServiceResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DuplicateServiceResponse &&
        code == other.code &&
        serviceName == other.serviceName &&
        existingServiceDefId == other.existingServiceDefId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, serviceName.hashCode);
    _$hash = $jc(_$hash, existingServiceDefId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DuplicateServiceResponse')
          ..add('code', code)
          ..add('serviceName', serviceName)
          ..add('existingServiceDefId', existingServiceDefId))
        .toString();
  }
}

class DuplicateServiceResponseBuilder
    implements
        Builder<DuplicateServiceResponse, DuplicateServiceResponseBuilder> {
  _$DuplicateServiceResponse? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _serviceName;
  String? get serviceName => _$this._serviceName;
  set serviceName(String? serviceName) => _$this._serviceName = serviceName;

  String? _existingServiceDefId;
  String? get existingServiceDefId => _$this._existingServiceDefId;
  set existingServiceDefId(String? existingServiceDefId) =>
      _$this._existingServiceDefId = existingServiceDefId;

  DuplicateServiceResponseBuilder() {
    DuplicateServiceResponse._defaults(this);
  }

  DuplicateServiceResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _serviceName = $v.serviceName;
      _existingServiceDefId = $v.existingServiceDefId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DuplicateServiceResponse other) {
    _$v = other as _$DuplicateServiceResponse;
  }

  @override
  void update(void Function(DuplicateServiceResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DuplicateServiceResponse build() => _build();

  _$DuplicateServiceResponse _build() {
    final _$result = _$v ??
        _$DuplicateServiceResponse._(
          code: code,
          serviceName: serviceName,
          existingServiceDefId: existingServiceDefId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
