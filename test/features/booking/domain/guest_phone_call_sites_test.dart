// Phase 417 (mobile-qa) — STRUCTURAL GATE: `guestPhone` / `clientPhone` on the
// booking side. M519 — extended to `Booking.clientPhone`.
//
// 2026-11-21 (user): «Деталі запису» shows NO client phone for any role; the
// phone lives only on the client card (its own `ClientCard.phone`, gated by
// `canSeeClientPhone`). Client-profile audit (2026-11-22, CLI-D08 / GST-D14):
// the domain `Booking` no longer holds either phone and the mapper no longer
// copies the wire fields, so NO non-comment reference may exist in `lib/`.
// Comments and generated code (`lib/api/` keeps the wire fields) are ignored.
//
// ADDING A READER is a deliberate act: it must gate on `canSeeClientPhone`
// (never a salon master or client), and this gate is changed in a reviewed
// diff.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The word-boundary match leaves the unrelated l10n getters
/// (`clientPhoneCopied`, `clientPhoneSemantics`, …) out of the scan, and also
/// catches the removed `clientPhoneFor` gate so it cannot quietly return.
final RegExp _clientPhoneRef = RegExp(r'\bclientPhone(For)?\b');
final RegExp _guestPhoneRef = RegExp(r'\bguestPhone\b');

bool _generated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.startsWith('lib/l10n/') ||
    path.startsWith('lib/api/');

/// Whether [path] matches [pattern] on a line outside a `//` comment.
bool _codeHit(String path, RegExp pattern) => File(path).readAsLinesSync().any(
  (String l) => pattern.hasMatch(l) && !l.trimLeft().startsWith('//'),
);

/// Non-generated `.dart` files under `lib/`, slash-normalised.
List<String> _libSources() => <String>[
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart'))
      if (!_generated(e.path.replaceAll(r'\', '/')))
        e.path.replaceAll(r'\', '/'),
];

void main() {
  test('guestPhone is referenced nowhere in lib/ (CLI-D08)', () {
    final List<String> sources = _libSources();
    expect(sources.length, greaterThan(100), reason: 'the scan must see lib/');
    final List<String> offenders = <String>[
      for (final String path in sources)
        if (_codeHit(path, _guestPhoneRef)) path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'USER RULE (2026-11-21): «Деталі запису» shows no client phone and '
          'Booking holds none. The phone lives on the client card. Remove the '
          '`guestPhone` reference from: $offenders',
    );
  });

  test('clientPhone / clientPhoneFor is referenced nowhere in lib/', () {
    final List<String> sources = _libSources();
    expect(sources.length, greaterThan(100), reason: 'the scan must see lib/');
    final List<String> offenders = <String>[
      for (final String path in sources)
        if (_codeHit(path, _clientPhoneRef)) path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'USER RULE (2026-11-21): «Деталі запису» shows no client phone and '
          'Booking holds none. The phone lives on the client card. Remove the '
          '`clientPhone` reference from: $offenders',
    );
  });
}
