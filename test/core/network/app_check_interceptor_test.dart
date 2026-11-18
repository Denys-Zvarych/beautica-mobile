// M515 (AUTH-D14 / AUTH-54) — `X-Firebase-AppCheck` goes on the SMS-sending
// paths only; never elsewhere; never when Firebase is uninitialised (null
// token) or the SDK throws (the request still goes out).

import 'dart:async';

import 'package:beautica_mobile/core/config/app_check_config.dart';
import 'package:beautica_mobile/core/network/app_check_interceptor.dart';
import 'package:beautica_mobile/core/network/app_check_paths.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

final class _CapturingHandler extends RequestInterceptorHandler {
  RequestOptions? passed;

  @override
  void next(RequestOptions requestOptions) => passed = requestOptions;
}

Future<RequestOptions> _run(
  AppCheckInterceptor interceptor,
  String path,
) async {
  final _CapturingHandler handler = _CapturingHandler();
  await interceptor.onRequest(RequestOptions(path: path), handler);
  expect(handler.passed, isNotNull, reason: 'the request must always proceed');
  return handler.passed!;
}

void main() {
  group('isAppCheckPath', () {
    // Pinned by literal: the test below iterates `kAppCheckPaths` itself, so
    // dropping a path from the set would not turn it red on its own.
    test('the static list is exactly the five SMS-sending paths', () {
      expect(kAppCheckPaths, <String>{
        '/api/v1/auth/register/phone/otp/send',
        '/api/v1/users/me/phone/otp/send',
        '/api/v1/auth/forgot-password',
        '/api/v1/users/me/change-password/request-otp',
        '/api/v1/auth/invite',
      });
    });

    test('every SMS-sending path, incl. the dynamic salon invite', () {
      for (final String p in <String>[
        ...kAppCheckPaths,
        '/api/v1/salons/0b5c/invite',
        '/api/v1/auth/register/phone/otp/send?x=1',
      ]) {
        expect(isAppCheckPath(p), isTrue, reason: p);
      }
    });

    test('not the verify step, login or other salon routes', () {
      for (final String p in <String>[
        '/api/v1/auth/register/phone/otp/verify',
        '/api/v1/auth/login',
        '/api/v1/salons/0b5c/invites',
        '/api/v1/salons/0b5c/invite/abc',
      ]) {
        expect(isAppCheckPath(p), isFalse, reason: p);
      }
    });
  });

  group('AppCheckInterceptor', () {
    test('attaches the token on an SMS-sending path', () async {
      final RequestOptions o = await _run(
        AppCheckInterceptor(() async => 'tok-1'),
        '/api/v1/auth/register/phone/otp/send',
      );
      expect(o.headers[kAppCheckHeader], 'tok-1');
    });

    test('never asks for a token on any other path', () async {
      var asked = 0;
      final RequestOptions o = await _run(
        AppCheckInterceptor(() async {
          asked++;
          return 'tok-1';
        }),
        '/api/v1/auth/login',
      );
      expect(o.headers.containsKey(kAppCheckHeader), isFalse);
      expect(asked, 0);
    });

    test('Firebase not initialised (null token) → no header', () async {
      final RequestOptions o = await _run(
        AppCheckInterceptor(() async => null),
        '/api/v1/auth/register/phone/otp/send',
      );
      expect(o.headers.containsKey(kAppCheckHeader), isFalse);
    });

    test('getToken throws → no header, request proceeds', () async {
      final RequestOptions o = await _run(
        AppCheckInterceptor(() async => throw StateError('sdk')),
        '/api/v1/salons/s1/invite',
      );
      expect(o.headers.containsKey(kAppCheckHeader), isFalse);
    });
  });

  // M515 audit (perf MEDIUM) — the WHOLE token fetch (Firebase init wait +
  // getToken) is capped, so a stalled attestation never pins an SMS request.
  group('appCheckToken (production token source)', () {
    const String smsPath = '/api/v1/auth/register/phone/otp/send';

    void expectProceedsAfterCap(AppCheckInterceptor interceptor) {
      fakeAsync((FakeAsync async) {
        final _CapturingHandler handler = _CapturingHandler();
        unawaited(
          interceptor.onRequest(RequestOptions(path: smsPath), handler),
        );
        async.elapse(kAppCheckTokenTimeout - const Duration(milliseconds: 1));
        expect(handler.passed, isNull, reason: 'still within the cap');
        async.elapse(const Duration(milliseconds: 1));
        expect(handler.passed, isNotNull, reason: 'proceeds at the cap');
        expect(handler.passed!.headers.containsKey(kAppCheckHeader), isFalse);
      });
    }

    test('the cap is 5 seconds', () {
      expect(kAppCheckTokenTimeout, const Duration(seconds: 5));
    });

    test('stalled getToken → request proceeds after the cap, no header', () {
      expectProceedsAfterCap(
        AppCheckInterceptor(
          () => appCheckToken(
            firebaseReady: () async => true,
            getToken: () => Completer<String?>().future,
          ),
        ),
      );
    });

    test('stalled Firebase init → request proceeds after the cap', () {
      var asked = 0;
      expectProceedsAfterCap(
        AppCheckInterceptor(
          () => appCheckToken(
            firebaseReady: () => Completer<bool>().future,
            getToken: () async {
              asked++;
              return 'tok-1';
            },
          ),
        ),
      );
      expect(asked, 0);
    });

    test('Firebase ready → the SDK token is returned', () async {
      expect(
        await appCheckToken(
          firebaseReady: () async => true,
          getToken: () async => 'tok-1',
        ),
        'tok-1',
      );
    });

    test('Firebase not initialised → null, getToken never called', () async {
      var asked = 0;
      expect(
        await appCheckToken(
          firebaseReady: () async => false,
          getToken: () async {
            asked++;
            return 'tok-1';
          },
        ),
        isNull,
      );
      expect(asked, 0);
    });

    test('getToken throws → null (never rethrows)', () async {
      expect(
        await appCheckToken(
          firebaseReady: () async => true,
          getToken: () async => throw StateError('sdk'),
        ),
        isNull,
      );
    });
  });
}
