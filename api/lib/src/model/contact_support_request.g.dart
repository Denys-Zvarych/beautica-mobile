// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contact_support_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ContactSupportRequest extends ContactSupportRequest {
  @override
  final String message;
  @override
  final String? subject;

  factory _$ContactSupportRequest(
          [void Function(ContactSupportRequestBuilder)? updates]) =>
      (ContactSupportRequestBuilder()..update(updates))._build();

  _$ContactSupportRequest._({required this.message, this.subject}) : super._();
  @override
  ContactSupportRequest rebuild(
          void Function(ContactSupportRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ContactSupportRequestBuilder toBuilder() =>
      ContactSupportRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ContactSupportRequest &&
        message == other.message &&
        subject == other.subject;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, message.hashCode);
    _$hash = $jc(_$hash, subject.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ContactSupportRequest')
          ..add('message', message)
          ..add('subject', subject))
        .toString();
  }
}

class ContactSupportRequestBuilder
    implements Builder<ContactSupportRequest, ContactSupportRequestBuilder> {
  _$ContactSupportRequest? _$v;

  String? _message;
  String? get message => _$this._message;
  set message(String? message) => _$this._message = message;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  ContactSupportRequestBuilder() {
    ContactSupportRequest._defaults(this);
  }

  ContactSupportRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _message = $v.message;
      _subject = $v.subject;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ContactSupportRequest other) {
    _$v = other as _$ContactSupportRequest;
  }

  @override
  void update(void Function(ContactSupportRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ContactSupportRequest build() => _build();

  _$ContactSupportRequest _build() {
    final _$result = _$v ??
        _$ContactSupportRequest._(
          message: BuiltValueNullFieldError.checkNotNull(
              message, r'ContactSupportRequest', 'message'),
          subject: subject,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
