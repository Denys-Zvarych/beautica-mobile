// Phase 410 (R.3 D6) — PII scrubber for every Sentry event and breadcrumb.
//
// Pure functions; wired as `beforeSend` / `beforeBreadcrumb` by
// `crash_reporting.dart`. Patterns mirror backend 371 D4
// (`SentryPiiScrubber`) so both sides redact the same shapes:
//   [email] (`@` or URL-encoded `%40`), [phone] (`+380…`, `0XXXXXXXXX`,
//   separator-formatted `050 111 22 33` / `(050) 111-22-33` / `050.111.22.33` /
//   `+38 050 111 22 33`, any run of ≥ 9 digits), [jwt], [otp] (4–6 digits
//   within 20 chars of `otp|code|код`), `Bearer [redacted]`,
//   `<password|pin|token|refresh|secret>=[redacted]` (key: value pairs,
//   quoted values whole), `PIN [redacted]` (`PIN 482913`).
// On top of the regexes:
//   - `event.request` dropped; `event.user` reduced to the anonymous install
//     ID only (never email / username / IP);
//   - a `DioException` value is REWRITTEN to
//     `DioException[<type>] <METHOD> <normalised path> status=<n>` — its
//     default `toString` carries the full URL (query included) and can carry
//     `response.data`;
//   - navigation breadcrumbs keep only normalised `from`/`to`/`state`
//     (route arguments — path + query params under go_router — dropped);
//   - breadcrumbs of category `ui.*`, `console`, `print` are dropped;
//   - `extra` / `contexts` / `tags` keys matching the backend key regex are
//     dropped, and every remaining string value is redacted.

import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../network/request_id_interceptor.dart' show normalisePath;

// Local part capped at 64 chars (RFC 5321 max): an unbounded `+` re-scans a
// long `[A-Za-z0-9._%+-]` run from every start position — quadratic on a
// 20 KB run without `@` (perf audit 2026-11-05). A `(?<!…)` start anchor was
// rejected: it leaks the second of two emails glued by `+`/`_`/`%`
// (`a@b.com+x@y.z`), which this form still redacts.
final RegExp _email = RegExp(
  r'[A-Za-z0-9._%+\-]{1,64}(@|%40)[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)+',
);
// `password: x`, `PIN: 482913`, `refresh=<opaque>`, `access_token=…`: the
// key (plus any word suffix) is kept, the value dropped. Not preceded by a
// letter, so `spinner:` / `mytoken=` style words inside text are left alone.
// A quoted value is dropped whole, spaces included (`"password":"a b c"`);
// an unterminated quote drops everything to the end of the text. The key
// suffix is bounded (`\w{0,32}`): an unbounded `\w*` re-scans a run like
// `_pin_pin_pin…` from every keyword — quadratic (perf audit 2026-11-05).
final RegExp _secretKv = RegExp(
  r'''(?<![A-Za-z])((?:password|pin|token|refresh|secret)\w{0,32})["']?\s*[:=]\s*(?:"[^"]*"?|'[^']*'?|\S+)''',
  caseSensitive: false,
);
// `PIN 482913`: a bare pin keyword, whitespace, then 4+ digits.
final RegExp _pinSpaced = RegExp(
  r'(?<![A-Za-z])(pin)\s+\d{4,}',
  caseSensitive: false,
);
// Segments bounded: unbounded `+` is quadratic on `eyJeyJ…`. The header
// (`{"alg":…}`, tens of chars) is capped at 512 — a 4096 cap there still
// costs ~0.5 s on an 84 KB `eyJ` run; payload/signature at 4096.
final RegExp _jwt = RegExp(r'eyJ[\w-]{1,512}\.[\w-]{1,4096}\.[\w-]{1,4096}');
final RegExp _bearer = RegExp(r'Bearer\s+\S+', caseSensitive: false);
// UA phone, compact or spaced/dashed (`+380 50 111 22 33`).
final RegExp _uaPhone = RegExp(
  r'\+?380[\s\-()]*\d{2}[\s\-()]*\d{3}[\s\-]*\d{2}[\s\-]*\d{2}',
);
// Local UA phone with optional `+38`/`38` and separators: `050 111 22 33`,
// `(050) 111-22-33`, `050-111-22-33`, `050.111.22.33`, `+38 050 111 22 33`.
// Needs 10 digits in 0XX-XXX-XX-XX groups, so versions (`9.30.1`) never
// match. Not glued to a
// preceding/following alphanumeric, so a 32-hex request id is never split.
final RegExp _uaPhoneSeparated = RegExp(
  r'(?<![0-9A-Za-z+])(?:\+?38[\s\-]*)?\(?0\d{2}\)?[\s\-.]*\d{3}[\s\-.]*\d{2}[\s\-.]*\d{2}(?![0-9A-Za-z])',
);
final RegExp _localPhone = RegExp(r'\b0\d{9}\b');
final RegExp _longDigits = RegExp(r'\d{9,}');
// 4–6 digits within 20 chars after `otp|code|код` (case-insensitive).
final RegExp _otp = RegExp(
  r'(otp|code|код)([^\d]{0,20}?)\d{4,6}(?!\d)',
  caseSensitive: false,
  unicode: true,
);

/// Backend 371 D4 key regex: a matching `extra`/`contexts`/`tags` key is
/// dropped whole, whatever its value.
final RegExp sensitiveKey = RegExp(
  r'note|comment|passport|allerg|health|password|token|otp|phone|email|secret|key',
  caseSensitive: false,
);

/// Redacts every PII shape in [input]. Order matters: JWT and Bearer before
/// the digit rules (a JWT can contain digit runs), secret key-values before
/// email (`password: a@b.c`), email before phones.
String redactText(String input) {
  String s = input;
  s = s.replaceAll(_jwt, '[jwt]');
  s = s.replaceAll(_bearer, 'Bearer [redacted]');
  s = s.replaceAllMapped(_secretKv, (Match m) => '${m[1]}=[redacted]');
  s = s.replaceAllMapped(_pinSpaced, (Match m) => '${m[1]} [redacted]');
  s = s.replaceAll(_email, '[email]');
  s = s.replaceAllMapped(_otp, (Match m) => '${m[1]}${m[2]}[otp]');
  s = s.replaceAll(_uaPhone, '[phone]');
  s = s.replaceAll(_uaPhoneSeparated, '[phone]');
  s = s.replaceAll(_localPhone, '[phone]');
  s = s.replaceAll(_longDigits, '[phone]');
  return s;
}

/// Longest exception `value` sent; longer values are truncated with `…`.
const int kMaxExceptionValueLength = 200;

String _cap(String v) => v.length <= kMaxExceptionValueLength
    ? v
    : '${v.substring(0, kMaxExceptionValueLength)}…';

/// The PII-free one-line description of a [DioException].
String describeDioException(DioException e) {
  final RequestOptions o = e.requestOptions;
  return 'DioException[${e.type.name}] ${o.method} '
      '${normalisePath(o.uri.path)} status=${e.response?.statusCode}';
}

/// Recursively redacts strings and drops [sensitiveKey] keys of a JSON-ish
/// value. Non-JSON objects are replaced by their runtime type.
Object? scrubValue(Object? value) {
  if (value == null || value is num || value is bool) return value;
  if (value is String) return redactText(value);
  if (value is Map) {
    return <String, dynamic>{
      for (final MapEntry<dynamic, dynamic> e in value.entries)
        if (!sensitiveKey.hasMatch('${e.key}'))
          '${e.key}': _isOwnRequestId(e.key, e.value)
              ? e.value
              : scrubValue(e.value),
    };
  }
  if (value is Iterable) return value.map(scrubValue).toList();
  return '${value.runtimeType}';
}

final RegExp _hex32 = RegExp(r'^[0-9a-f]{32}$');

/// Our own `X-Request-Id` (32 hex, `randomHex128`) is kept verbatim — a hex
/// string can hold a ≥ 9-digit run the phone rule would otherwise mangle,
/// breaking the phone-crash → server-log join.
bool _isOwnRequestId(Object? key, Object? value) =>
    key == 'request_id' && value is String && _hex32.hasMatch(value);

bool _isJsonish(Object? v) =>
    v == null ||
    v is String ||
    v is num ||
    v is bool ||
    (v is Map && v.values.every(_isJsonish)) ||
    (v is Iterable && v.every(_isJsonish));

const Set<String> _droppedCategories = <String>{'console', 'print'};

/// `beforeBreadcrumb`: `null` drops the breadcrumb.
Breadcrumb? scrubBreadcrumb(Breadcrumb? crumb) {
  if (crumb == null) return null;
  final String category = crumb.category ?? '';
  if (category.startsWith('ui.') ||
      category == 'ui' ||
      _droppedCategories.contains(category)) {
    return null;
  }
  final String? message = crumb.message;
  if (message != null) crumb.message = redactText(message);

  final Map<String, dynamic>? data = crumb.data;
  if (data != null) {
    if (category == 'navigation') {
      crumb.data = <String, dynamic>{
        for (final String k in const <String>['state', 'from', 'to'])
          if (data[k] is String)
            k: redactText(normalisePath(data[k] as String)),
      };
    } else if (category == 'http') {
      final Object? path = data['path'];
      final Object? url = data['url'];
      final Map<String, dynamic> scrubbed =
          scrubValue(data) as Map<String, dynamic>
            ..remove('url')
            ..remove('http.query')
            ..remove('http.fragment');
      if (path is String) scrubbed['path'] = normalisePath(path);
      if (url is String) {
        scrubbed['path'] ??= normalisePath(Uri.tryParse(url)?.path ?? '');
      }
      crumb.data = scrubbed;
    } else {
      crumb.data = scrubValue(data) as Map<String, dynamic>;
    }
  }
  return crumb;
}

/// `beforeSend` body (opt-out is checked by the caller). [installId] becomes
/// the ONLY user field; `null` leaves no user at all.
SentryEvent scrubEvent(SentryEvent event, {String? installId}) {
  event.request = null;
  event.user = installId == null ? null : SentryUser(id: installId);
  event.serverName = null;

  final Object? throwable = event.throwable;
  final List<SentryException>? exceptions = event.exceptions;
  if (exceptions != null) {
    for (final SentryException ex in exceptions) {
      final Object? thrown = ex.throwable;
      if (thrown is DioException) {
        ex.value = describeDioException(thrown);
      } else if (ex.type == 'DioException' && throwable is DioException) {
        ex.value = describeDioException(throwable);
      } else if (thrown is FormatException || ex.type == 'FormatException') {
        // `FormatException.toString` quotes the offending SOURCE text (a
        // server body, user input) on the following lines: keep the message.
        final String? v = thrown is FormatException
            ? thrown.message
            : ex.value?.split('\n').first;
        if (v != null) ex.value = _cap(redactText(v));
      } else {
        final String? v = ex.value;
        if (v != null) ex.value = _cap(redactText(v));
      }
    }
  }

  final SentryMessage? msg = event.message;
  if (msg != null) {
    final String? template = msg.template;
    // `params` dropped: they are exactly the values a template interpolates.
    event.message = SentryMessage(
      redactText(msg.formatted),
      template: template == null ? null : redactText(template),
    );
  }

  final List<Breadcrumb>? crumbs = event.breadcrumbs;
  if (crumbs != null) {
    event.breadcrumbs = <Breadcrumb>[
      for (final Breadcrumb c in crumbs) ?scrubBreadcrumb(c),
    ];
  }

  // Deprecated in the SDK but still SENT when a caller sets it — so still
  // scrubbed.
  // ignore: deprecated_member_use — scrubbing, not authoring, `extra`.
  final Map<String, dynamic>? extra = event.extra;
  if (extra != null) {
    // ignore: deprecated_member_use — see above.
    event.extra = scrubValue(extra) as Map<String, dynamic>;
  }

  final Map<String, String>? tags = event.tags;
  if (tags != null) {
    event.tags = <String, String>{
      for (final MapEntry<String, String> e in tags.entries)
        if (!sensitiveKey.hasMatch(e.key))
          e.key: _isOwnRequestId(e.key, e.value)
              ? e.value
              : redactText(e.value),
    };
  }

  // Contexts: typed SDK contexts (device, os, app, …) are left alone apart
  // from the device name (user-chosen, e.g. «Pixel Олени»); every custom map
  // context (e.g. `flutter_error_details`, whose `information` can quote
  // widget text) is redacted, and sensitive keys dropped.
  final Contexts contexts = event.contexts;
  contexts.device?.name = null;
  for (final String key in contexts.keys.toList()) {
    if (sensitiveKey.hasMatch(key)) {
      contexts.remove(key);
      continue;
    }
    final Object? v = contexts[key];
    // Only plain JSON values: typed SDK contexts (SentryDevice, the
    // `runtimes` List<SentryRuntime>, …) must keep their types or the
    // envelope fails to serialise.
    if (v is String || (v is Map && v.values.every(_isJsonish))) {
      contexts[key] = scrubValue(v);
    }
  }
  return event;
}
