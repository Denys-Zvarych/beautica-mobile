// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registration_otp_send_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const RegistrationOtpSendRequestSmsFormatEnum
    _$registrationOtpSendRequestSmsFormatEnum_DOMAIN_BOUND =
    const RegistrationOtpSendRequestSmsFormatEnum._('DOMAIN_BOUND');
const RegistrationOtpSendRequestSmsFormatEnum
    _$registrationOtpSendRequestSmsFormatEnum_PLAIN =
    const RegistrationOtpSendRequestSmsFormatEnum._('PLAIN');
const RegistrationOtpSendRequestSmsFormatEnum
    _$registrationOtpSendRequestSmsFormatEnum_unknownDefaultOpenApi =
    const RegistrationOtpSendRequestSmsFormatEnum._('unknownDefaultOpenApi');

RegistrationOtpSendRequestSmsFormatEnum
    _$registrationOtpSendRequestSmsFormatEnumValueOf(String name) {
  switch (name) {
    case 'DOMAIN_BOUND':
      return _$registrationOtpSendRequestSmsFormatEnum_DOMAIN_BOUND;
    case 'PLAIN':
      return _$registrationOtpSendRequestSmsFormatEnum_PLAIN;
    case 'unknownDefaultOpenApi':
      return _$registrationOtpSendRequestSmsFormatEnum_unknownDefaultOpenApi;
    default:
      return _$registrationOtpSendRequestSmsFormatEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<RegistrationOtpSendRequestSmsFormatEnum>
    _$registrationOtpSendRequestSmsFormatEnumValues = BuiltSet<
        RegistrationOtpSendRequestSmsFormatEnum>(const <RegistrationOtpSendRequestSmsFormatEnum>[
  _$registrationOtpSendRequestSmsFormatEnum_DOMAIN_BOUND,
  _$registrationOtpSendRequestSmsFormatEnum_PLAIN,
  _$registrationOtpSendRequestSmsFormatEnum_unknownDefaultOpenApi,
]);

Serializer<RegistrationOtpSendRequestSmsFormatEnum>
    _$registrationOtpSendRequestSmsFormatEnumSerializer =
    _$RegistrationOtpSendRequestSmsFormatEnumSerializer();

class _$RegistrationOtpSendRequestSmsFormatEnumSerializer
    implements PrimitiveSerializer<RegistrationOtpSendRequestSmsFormatEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'DOMAIN_BOUND': 'DOMAIN_BOUND',
    'PLAIN': 'PLAIN',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'DOMAIN_BOUND': 'DOMAIN_BOUND',
    'PLAIN': 'PLAIN',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[
    RegistrationOtpSendRequestSmsFormatEnum
  ];
  @override
  final String wireName = 'RegistrationOtpSendRequestSmsFormatEnum';

  @override
  Object serialize(Serializers serializers,
          RegistrationOtpSendRequestSmsFormatEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  RegistrationOtpSendRequestSmsFormatEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      RegistrationOtpSendRequestSmsFormatEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$RegistrationOtpSendRequest extends RegistrationOtpSendRequest {
  @override
  final String phone;
  @override
  final RegistrationOtpSendRequestSmsFormatEnum? smsFormat;

  factory _$RegistrationOtpSendRequest(
          [void Function(RegistrationOtpSendRequestBuilder)? updates]) =>
      (RegistrationOtpSendRequestBuilder()..update(updates))._build();

  _$RegistrationOtpSendRequest._({required this.phone, this.smsFormat})
      : super._();
  @override
  RegistrationOtpSendRequest rebuild(
          void Function(RegistrationOtpSendRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RegistrationOtpSendRequestBuilder toBuilder() =>
      RegistrationOtpSendRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RegistrationOtpSendRequest &&
        phone == other.phone &&
        smsFormat == other.smsFormat;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, phone.hashCode);
    _$hash = $jc(_$hash, smsFormat.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RegistrationOtpSendRequest')
          ..add('phone', phone)
          ..add('smsFormat', smsFormat))
        .toString();
  }
}

class RegistrationOtpSendRequestBuilder
    implements
        Builder<RegistrationOtpSendRequest, RegistrationOtpSendRequestBuilder> {
  _$RegistrationOtpSendRequest? _$v;

  String? _phone;
  String? get phone => _$this._phone;
  set phone(String? phone) => _$this._phone = phone;

  RegistrationOtpSendRequestSmsFormatEnum? _smsFormat;
  RegistrationOtpSendRequestSmsFormatEnum? get smsFormat => _$this._smsFormat;
  set smsFormat(RegistrationOtpSendRequestSmsFormatEnum? smsFormat) =>
      _$this._smsFormat = smsFormat;

  RegistrationOtpSendRequestBuilder() {
    RegistrationOtpSendRequest._defaults(this);
  }

  RegistrationOtpSendRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _phone = $v.phone;
      _smsFormat = $v.smsFormat;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RegistrationOtpSendRequest other) {
    _$v = other as _$RegistrationOtpSendRequest;
  }

  @override
  void update(void Function(RegistrationOtpSendRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RegistrationOtpSendRequest build() => _build();

  _$RegistrationOtpSendRequest _build() {
    final _$result = _$v ??
        _$RegistrationOtpSendRequest._(
          phone: BuiltValueNullFieldError.checkNotNull(
              phone, r'RegistrationOtpSendRequest', 'phone'),
          smsFormat: smsFormat,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
