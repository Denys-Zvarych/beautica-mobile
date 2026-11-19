// Phone-first hardening M8 — the identity error-code contract.
//
// `tool/contract/identity-error-codes.json` is a byte copy of the backend
// golden (`beautica-backend/src/test/resources/contract/identity-error-codes.json`,
// synced by `scripts/sync_error_codes.sh`): every `IdentityException.Code`,
// `VerificationException.Code`, `EMAIL_NOT_VERIFIED` and the `INVITE_*`
// codes, each with its HTTP status. This test fails when the
// backend adds a code the app neither maps to a typed failure nor lists in
// [kIgnoredIdentityCodes] with a reason, or when a mapped code drifts.
//
// Each mapped code is driven through a REAL Dio carrying the production
// `ErrorMapperInterceptor`, with the backend's `{success:false, data:{code}}`
// envelope at the JSON status, on a path where the app really receives it.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/error_mapper_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Codes the app deliberately does not map, with the reason.
const Map<String, String> kIgnoredIdentityCodes = <String, String>{
  'PHONE_CHANGE_REQUIRES_OTP':
      'answered only to a profile PATCH carrying a different phone; the app '
      'never sends one — phone changes go through /users/me/phone/otp (M517)',
  'INVITE_PHONE_REQUIRED':
      'answered only to old builds sending an email-only invite; this app '
      'always sends the phone (M521)',
};

/// Mapped codes: a path the app receives the code on, and the typed failure
/// it must become.
final Map<String, (String path, bool Function(Failure f) isExpected)>
_kMapped = <String, (String, bool Function(Failure))>{
  'PHONE_NOT_UA_MOBILE': (
    '/api/v1/auth/register/phone/otp/send',
    (Failure f) =>
        f is PhoneIdentityFailure &&
        f.code == PhoneIdentityErrorCode.phoneNotUaMobile,
  ),
  'PHONE_ALREADY_REGISTERED': (
    '/api/v1/users/me/phone/otp/verify',
    (Failure f) =>
        f is PhoneIdentityFailure &&
        f.code == PhoneIdentityErrorCode.phoneAlreadyRegistered,
  ),
  'REGISTRATION_TICKET_INVALID': (
    '/api/v1/auth/register',
    (Failure f) =>
        f is PhoneIdentityFailure &&
        f.code == PhoneIdentityErrorCode.registrationTicketInvalid,
  ),
  'APP_CHECK_FAILED': (
    '/api/v1/auth/forgot-password',
    (Failure f) =>
        f is PhoneIdentityFailure &&
        f.code == PhoneIdentityErrorCode.appCheckFailed,
  ),
  'APP_CHECK_UNAVAILABLE': (
    '/api/v1/auth/forgot-password',
    (Failure f) =>
        f is PhoneIdentityFailure &&
        f.code == PhoneIdentityErrorCode.appCheckUnavailable,
  ),
  'PHONE_NOT_VERIFIED': (
    '/api/v1/bookings',
    (Failure f) => f is PhoneNotVerifiedFailure,
  ),
  'INVITE_PHONE_MISMATCH': (
    '/api/v1/auth/invite/accept',
    (Failure f) =>
        f is PhoneIdentityFailure &&
        f.code == PhoneIdentityErrorCode.invitePhoneMismatch,
  ),
  'INVITE_SMS_LIMIT': (
    '/api/v1/salons/s-1/invite',
    (Failure f) =>
        f is PhoneIdentityFailure &&
        f.code == PhoneIdentityErrorCode.inviteSmsLimit,
  ),
  // M7 / AUTH-D19 — on the phone paths a wrong, expired or exhausted code is
  // always INVALID_CODE.
  'INVALID_CODE': (
    '/api/v1/users/me/phone/otp/verify',
    (Failure f) =>
        f is PhoneIdentityFailure &&
        f.code == PhoneIdentityErrorCode.invalidCode,
  ),
  // Email paths only (the phone paths never send it, AUTH-D19).
  'CODE_EXPIRED': (
    '/api/v1/users/me/email/verify',
    (Failure f) =>
        f is VerificationFailure && f.code == VerificationErrorCode.codeExpired,
  ),
  'ALREADY_VERIFIED': (
    '/api/v1/auth/verify-email',
    (Failure f) =>
        f is VerificationFailure &&
        f.code == VerificationErrorCode.alreadyVerified,
  ),
  'CURRENT_PASSWORD_INVALID': (
    '/api/v1/users/me/phone/otp/verify',
    (Failure f) => f is CurrentPasswordInvalidFailure,
  ),
  // Login — 403 on an unverified email account (the login screen's
  // «підтвердьте email» branch).
  'EMAIL_NOT_VERIFIED': (
    '/api/v1/auth/login',
    (Failure f) => f is UnauthorizedFailure && f.emailNotVerified,
  ),
  // Invite accept — a spent / unknown token is a 400 with no field errors,
  // which `AuthNotifier._inviteHandoffReason` hands off to /login as
  // `inviteNoLongerValid`.
  for (final String code in <String>[
    'INVITE_EXPIRED',
    'INVITE_NOT_FOUND',
    'INVITE_REVOKED',
    'INVITE_USED',
  ])
    code: (
      '/api/v1/auth/invite/accept',
      (Failure f) => f is ValidationFailure && f.fieldErrors.isEmpty,
    ),
  // Invite accept — the inviting salon is inactive: a 409 whose `errorCode`
  // the handoff maps to `salonInactive` (AUTH-17, AUTH-E03).
  'INVITE_SALON_INACTIVE': (
    '/api/v1/auth/invite/accept',
    (Failure f) =>
        f is ServerFailure &&
        f.statusCode == 409 &&
        f.errorCode == 'INVITE_SALON_INACTIVE',
  ),
};

/// Answers every request with [status] and the identity envelope for [code].
final class _EnvelopeAdapter implements HttpClientAdapter {
  _EnvelopeAdapter(this.status, this.code);

  final int status;
  final String code;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(<String, Object?>{
      'success': false,
      'message': 'irrelevant',
      'data': <String, Object?>{'code': code},
    }),
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<Failure> _map(String path, int status, String code) async {
  final Dio dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..httpClientAdapter = _EnvelopeAdapter(status, code)
    ..interceptors.add(ErrorMapperInterceptor());
  try {
    await dio.post<Object?>(path);
  } on DioException catch (e) {
    final Object? error = e.error;
    if (error is Failure) return error;
    fail('$code on $path was not mapped to a Failure: $error');
  }
  fail('$code on $path did not fail');
}

List<({String code, int status, String family})> _loadContract() {
  final Object? decoded = jsonDecode(
    File('tool/contract/identity-error-codes.json').readAsStringSync(),
  );
  if (decoded is! List<Object?>) fail('contract JSON is not a list');
  return <({String code, int status, String family})>[
    for (final Object? row in decoded)
      if (row case {
        'code': final String code,
        'status': final int status,
        'family': final String family,
      })
        (code: code, status: status, family: family)
      else
        throw FormatException('malformed contract row: $row'),
  ];
}

void main() {
  final List<({String code, int status, String family})> contract =
      _loadContract();
  final Set<String> codes = <String>{for (final r in contract) r.code};

  test('contract is non-empty, unique and sorted by code', () {
    expect(contract, isNotEmpty);
    expect(codes, hasLength(contract.length), reason: 'duplicate codes');
    final List<String> order = <String>[for (final r in contract) r.code];
    expect(order, List<String>.of(order)..sort());
  });

  test('every backend code is mapped or explicitly ignored', () {
    final Set<String> unhandled = codes
        .difference(_kMapped.keys.toSet())
        .difference(kIgnoredIdentityCodes.keys.toSet());
    expect(
      unhandled,
      isEmpty,
      reason:
          'new backend code(s) — map them in ErrorMapperInterceptor (and add '
          'them to _kMapped) or list them in kIgnoredIdentityCodes with a '
          'reason',
    );
  });

  test('no stale mapping: every table entry is still a backend code', () {
    expect(_kMapped.keys.toSet().difference(codes), isEmpty);
    expect(kIgnoredIdentityCodes.keys.toSet().difference(codes), isEmpty);
    expect(
      _kMapped.keys.toSet().intersection(kIgnoredIdentityCodes.keys.toSet()),
      isEmpty,
    );
  });

  group(
    'each mapped code becomes its typed failure at its contract status',
    () {
      for (final r in contract) {
        final (String, bool Function(Failure))? entry = _kMapped[r.code];
        if (entry == null) continue;
        final (String path, bool Function(Failure) isExpected) = entry;
        test('${r.status} ${r.code} on $path', () async {
          final Failure f = await _map(path, r.status, r.code);
          expect(isExpected(f), isTrue, reason: 'mapped to $f');
        });
      }
    },
  );

  // M7 — the phone verify path has no CODE_EXPIRED arm: a stray one is never
  // shown as the email «code expired» copy.
  test(
    'CODE_EXPIRED on the phone verify path is not a VerificationFailure',
    () async {
      final Failure f = await _map(
        '/api/v1/users/me/phone/otp/verify',
        400,
        'CODE_EXPIRED',
      );
      expect(f, isNot(isA<VerificationFailure>()));
    },
  );

  // M1 — a phone-send 429 carries the server's Retry-After.
  test(
    '429 on the phone send carries Retry-After as retryAfterSeconds',
    () async {
      final Dio dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _RetryAfterAdapter()
        ..interceptors.add(ErrorMapperInterceptor());
      try {
        await dio.post<Object?>('/api/v1/users/me/phone/otp/send');
        fail('did not fail');
      } on DioException catch (e) {
        final Object? f = e.error;
        expect(f, isA<PhoneIdentityFailure>());
        f as PhoneIdentityFailure;
        expect(f.code, PhoneIdentityErrorCode.rateLimited);
        expect(f.retryAfterSeconds, 42);
      }
    },
  );
}

final class _RetryAfterAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(<String, Object?>{'success': false, 'message': 'slow down'}),
    429,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      'retry-after': <String>['42'],
    },
  );

  @override
  void close({bool force = false}) {}
}
