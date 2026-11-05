// Phase 410 (R.3 D6) — PII scrubber canaries.
//
// Falsified once during implementation: with the email regex disabled
// (`s.replaceAll(_email, ...)` commented out) the email canaries below went
// red, then green again with it restored.
import 'package:beautica_mobile/core/diagnostics/crash_scrubber.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

const String _email = 'canary@x.ua';
const String _phone = '+380501112233';
const String _jwt =
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyLTQyIn0.c2lnbmF0dXJlLXNpZ25hdHVyZQ';
const String _note = 'алергія на лак, дзвонити після 18:00';

/// Every canary that must never survive a scrub.
const List<String> _canaries = <String>[
  _email,
  _phone,
  '501112233',
  _jwt,
  '482913',
  'Bearer x',
  _note,
];

void _expectClean(String text) {
  for (final String c in _canaries) {
    expect(text, isNot(contains(c)), reason: 'canary "$c" leaked: $text');
  }
}

DioException _dio({String path = '/api/v1/users/me', String? query}) {
  final RequestOptions o = RequestOptions(
    baseUrl: 'https://api.beautica.app',
    path: query == null ? path : '$path?$query',
    method: 'POST',
  );
  return DioException(
    requestOptions: o,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: o,
      statusCode: 400,
      data: <String, dynamic>{'email': _email, 'phone': _phone},
    ),
  );
}

void main() {
  group('redactText', () {
    test('email / phone / JWT / OTP / Bearer canaries are removed', () {
      final String out = redactText(
        'user $_email phone $_phone alt 0501112233 token $_jwt '
        'code 482913 header Bearer x',
      );
      _expectClean(out);
      expect(out, contains('[email]'));
      expect(out, contains('[phone]'));
      expect(out, contains('[jwt]'));
      expect(out, contains('[otp]'));
      expect(out, contains('Bearer [redacted]'));
    });

    test('spaced UA phone and Cyrillic OTP keyword', () {
      final String out = redactText('тел. +380 50 111 22 33, код: 4829');
      expect(out, isNot(contains('111 22 33')));
      expect(out, isNot(contains('4829')));
    });

    test('ordinary text is left alone', () {
      expect(redactText('Bad state: no element'), 'Bad state: no element');
    });

    // Security audit 2026-11-05 (MEDIUM): separator-formatted local numbers.
    for (final String phone in const <String>[
      '050 111 22 33',
      '(050) 111-22-33',
      '050-111-22-33',
      '+38 050 111 22 33',
      '38(050)1112233',
    ]) {
      test('separator-formatted UA phone "$phone" is redacted', () {
        final String out = redactText('дзвоніть $phone після обіду');
        expect(out, 'дзвоніть [phone] після обіду');
      });
    }

    test('32-hex request ids are not split by the separator phone rule', () {
      // No run of >= 9 digits, but 0XX-XXX-XX-XX shaped digit groups inside.
      const String id = 'ab050c111d22e33f0501a1112b22c33d';
      expect(redactText('request $id failed'), 'request $id failed');
    });

    test('password / pin / token / refresh / secret values are dropped', () {
      final String out = redactText(
        'password: hunter2 PIN: 482913 refresh=opaqueR3fr3sh '
        'access_token=abc.def secret = s3cr3t',
      );
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('482913')));
      expect(out, isNot(contains('opaqueR3fr3sh')));
      expect(out, isNot(contains('abc.def')));
      expect(out, isNot(contains('s3cr3t')));
      expect(out, contains('password=[redacted]'));
      expect(out, contains('PIN=[redacted]'));
      expect(out, contains('refresh=[redacted]'));
    });

    // Security audit 2026-11-05 (LOW): a quoted value is dropped whole.
    test('quoted secret values with spaces are dropped whole', () {
      final String json = redactText('{"password":"a b c","x":1}');
      expect(json, isNot(contains('b c')));
      expect(json, contains('password=[redacted]'));
      final String kv = redactText('Password = "x y" done');
      expect(kv, isNot(contains('y"')));
      expect(kv, 'Password=[redacted] done');
      final String single = redactText("secret: 'p q r' end");
      expect(single, "secret=[redacted] end");
    });

    // Security audit 2026-11-05 (INFO): an unterminated quote drops the rest.
    test('unterminated quoted secret value is dropped to the end', () {
      expect(redactText('password: "unterminated a b'), 'password=[redacted]');
      expect(redactText("pin: 'open 4829 x"), 'pin=[redacted]');
    });

    // Security audit 2026-11-05 (INFO): dot-separated phone, spaced PIN.
    test('dot-separated phone and "PIN 482913" are redacted', () {
      expect(redactText('тел 050.111.22.33 ok'), 'тел [phone] ok');
      final String pin = redactText('PIN 482913 entered');
      expect(pin, isNot(contains('482913')));
      expect(pin, 'PIN [redacted] entered');
    });

    test('versions and 32-hex ids are not redacted by the new rules', () {
      const String id = '0123abcd0123abcd0123abcd0123abcd';
      const String text = 'sentry 9.30.1 dart 1.5.0 id $id spinner 1234';
      expect(redactText(text), text);
    });

    // QA audit 2026-11-05 (LOW): exercises the "not preceded by a letter"
    // guard of both the key-value and the spaced-PIN rules.
    for (final String text in const <String>['spin 1234', 'spinner: 1234']) {
      test('"$text" is left alone (pin inside a word)', () {
        expect(redactText(text), text);
      });
    }

    // Perf audit 2026-11-05 (P2): no quadratic scan on a long run without @.
    test('a 20 KB run without @ scrubs fast; emails still redact', () {
      final String run = 'a.b_c%d+e-f' * 1900;
      final String input = '$run x $_email y $run';
      final Stopwatch sw = Stopwatch()..start();
      final String out = redactText(input);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(out, isNot(contains(_email)));
      expect(out, contains('[email]'));
    });

    // Perf audit 2026-11-05 (P2 + INFO): bounded key suffix / JWT segments.
    // Sized so the old unbounded patterns take > 3 s here (measured
    // 2026-11-05; at 1/8 of these sizes they ran in 74-126 ms and the test
    // could not fail) while the bounded ones stay well under 1 s.
    for (final String run in <String>[
      '_pin' * 40000,
      '0token' * 24000,
      'eyJ' * 56000,
    ]) {
      test(
        'a ${run.length}-char "${run.substring(0, 6)}…" run scrubs fast',
        () {
          final Stopwatch sw = Stopwatch()..start();
          final String out = redactText('$run x $_jwt y');
          sw.stop();
          expect(sw.elapsedMilliseconds, lessThan(1000));
          expect(out, isNot(contains(_jwt)));
        },
      );
    }

    test('two emails glued by "+" are both redacted', () {
      expect(redactText('to a@b.com+x@y.z'), 'to [email][email]');
    });

    test('URL-encoded email (%40) is redacted', () {
      final String out = redactText('GET /x?e=user%40mail.com');
      expect(out, isNot(contains('user%40mail.com')));
      expect(out, contains('[email]'));
    });
  });

  group('exception value hardening', () {
    test('FormatException source text is dropped, message kept', () {
      const FormatException fe = FormatException(
        'Unexpected character',
        '{"name":"Олена","note":"secret allergy"}',
        1,
      );
      final SentryEvent out = scrubEvent(
        SentryEvent(
          exceptions: <SentryException>[
            SentryException(
              type: 'FormatException',
              value: fe.toString(),
              throwable: fe,
            ),
          ],
        ),
      );
      final String value = out.exceptions!.single.value!;
      expect(value, 'Unexpected character');
      expect(value, isNot(contains('Олена')));
    });

    test('FormatException by type only keeps the first line', () {
      final SentryEvent out = scrubEvent(
        SentryEvent(
          exceptions: <SentryException>[
            SentryException(
              type: 'FormatException',
              value: 'Bad json\n{"name":"Олена"}\n^',
            ),
          ],
        ),
      );
      expect(out.exceptions!.single.value, 'Bad json');
    });

    test('long exception values are capped', () {
      final SentryEvent out = scrubEvent(
        SentryEvent(
          exceptions: <SentryException>[
            SentryException(type: 'StateError', value: 'x' * 1000),
          ],
        ),
      );
      final String value = out.exceptions!.single.value!;
      expect(value.length, kMaxExceptionValueLength + 1);
      expect(value, endsWith('…'));
    });
  });

  test('DioException with ?phone= query and response.data -> rewritten', () {
    final DioException e = _dio(query: 'phone=%2B380501112233&q=$_email');
    final SentryEvent event = SentryEvent(
      exceptions: <SentryException>[
        SentryException(
          type: 'DioException',
          value: e.toString(),
          throwable: e,
        ),
      ],
    );
    final SentryEvent out = scrubEvent(event, installId: 'a' * 32);
    final String value = out.exceptions!.single.value!;
    expect(value, 'DioException[badResponse] POST /api/v1/users/me status=400');
    expect(value, isNot(contains('phone=')));
    expect(value, isNot(contains('?')));
    _expectClean(value);
  });

  test('normalised path drops invite tokens and ids', () {
    final DioException e = _dio(
      path: '/api/v1/invite/accept/Zx9vQ2kLm8Np4Rt6Yw1Bc3Df5Gh7Jk0',
    );
    expect(
      describeDioException(e),
      'DioException[badResponse] POST /api/v1/invite/accept/{id} status=400',
    );
  });

  test('message, extra (note in clientComment), tags and contexts', () {
    final SentryEvent event = SentryEvent(
      message: SentryMessage('failed for $_email', template: 'failed for %s'),
      tags: <String, String>{
        'screen': 'booking $_phone',
        'phone': _phone,
        'request_id': '0123456789abcdef0123456789abcdef',
      },
      user: SentryUser(
        id: 'backend-user-uuid',
        email: _email,
        username: 'Олена',
        ipAddress: '1.2.3.4',
      ),
      request: SentryRequest(url: 'https://api.beautica.app/x?phone=$_phone'),
    );
    // ignore: deprecated_member_use — `extra` must still be scrubbed.
    event.extra = <String, dynamic>{
      'clientComment': _note,
      'nested': <String, dynamic>{'text': 'call $_phone', 'token': _jwt},
    };
    event.contexts['flutter_error_details'] = <String, String>{
      'information': 'Text("$_email")',
    };
    event.contexts['patient_health'] = <String, String>{'x': 'y'};

    final SentryEvent out = scrubEvent(event, installId: 'f' * 32);

    expect(out.request, isNull);
    expect(out.user?.id, 'f' * 32);
    expect(out.user?.email, isNull);
    expect(out.user?.username, isNull);
    expect(out.user?.ipAddress, isNull);
    _expectClean(out.message!.formatted);
    // ignore: deprecated_member_use — reading the scrubbed `extra`.
    final Map<String, dynamic> extra = out.extra!;
    expect(extra.containsKey('clientComment'), isFalse);
    _expectClean('$extra');
    expect(out.tags!.containsKey('phone'), isFalse);
    _expectClean('${out.tags}');
    expect(
      out.tags!['request_id'],
      '0123456789abcdef0123456789abcdef',
      reason: 'our own request id must survive verbatim',
    );
    expect(out.contexts.containsKey('patient_health'), isFalse);
    _expectClean('${out.contexts['flutter_error_details']}');
  });

  test('no install id -> no user at all', () {
    final SentryEvent out = scrubEvent(
      SentryEvent(
        user: SentryUser(id: 'x', email: _email),
      ),
    );
    expect(out.user, isNull);
  });

  group('breadcrumbs', () {
    test('ui.click / ui.* / print / console are dropped', () {
      for (final String c in <String>[
        'ui.click',
        'ui.lifecycle',
        'print',
        'console',
      ]) {
        expect(scrubBreadcrumb(Breadcrumb(category: c, message: 'x')), isNull);
      }
    });

    test('navigation keeps normalised from/to/state only', () {
      final Breadcrumb out = scrubBreadcrumb(
        Breadcrumb(
          category: 'navigation',
          type: 'navigation',
          data: <String, dynamic>{
            'state': 'didPush',
            'from': '/home',
            'to': '/invite/accept/Zx9vQ2kLm8Np4Rt6Yw1Bc3Df5Gh7Jk0',
            'to_arguments': <String, String>{'phone': _phone},
          },
        ),
      )!;
      expect(out.data, <String, dynamic>{
        'state': 'didPush',
        'from': '/home',
        'to': '/invite/accept/{id}',
      });
    });

    test('http keeps request_id verbatim, drops url/query, redacts rest', () {
      final Breadcrumb out = scrubBreadcrumb(
        Breadcrumb(
          category: 'http',
          message: 'GET for $_email',
          data: <String, dynamic>{
            'method': 'GET',
            'url': 'https://api.beautica.app/a?phone=$_phone',
            'path': '/api/v1/masters/3f2b8c1e-1111-4222-8333-944445555666',
            'status': 200,
            'request_id': '1234567890123456789012345678abcd',
          },
        ),
      )!;
      expect(out.data!['url'], isNull);
      expect(out.data!['path'], '/api/v1/masters/{id}');
      expect(out.data!['request_id'], '1234567890123456789012345678abcd');
      _expectClean('${out.data} ${out.message}');
    });
  });
}
