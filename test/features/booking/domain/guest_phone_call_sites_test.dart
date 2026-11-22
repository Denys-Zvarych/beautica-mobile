// Phase 417 (mobile-qa) — STRUCTURAL GATE: where `guestPhone` may be read.
// M519 — extended to `Booking.clientPhone`.
//
// 2026-11-21 (user): «Деталі запису» shows NO client phone for any role; the
// phone lives only on the client card (its own `ClientCard.phone`, gated by
// `canSeeClientPhone`). The booking fields are now mapped and never read, so
// this test pins every non-comment reference in `lib/` to the two files that
// own them:
//   • booking.dart          — the model fields;
//   • booking_mapper.dart   — DTO → model mapping.
// Comments and generated code are ignored.
//
// ADDING A READER is a deliberate act: it must gate on `canSeeClientPhone`
// (never a salon master or client), and the allow-list below is updated in a
// reviewed diff.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const Set<String> _allowed = <String>{
  'lib/features/booking/domain/booking.dart',
  'lib/features/booking/data/booking_mapper.dart',
};

/// M519 — owners of `clientPhone` (the booking field), plus the removed
/// `clientPhoneFor` gate so it cannot quietly return. The word-boundary match
/// leaves the unrelated l10n getters (`clientPhoneCopied`,
/// `clientPhoneSemantics`, …) out of the scan.
const Set<String> _clientPhoneAllowed = <String>{
  'lib/features/booking/domain/booking.dart',
  'lib/features/booking/data/booking_mapper.dart',
};

final RegExp _clientPhoneRef = RegExp(r'\bclientPhone(For)?\b');

bool _generated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.freezed.dart') ||
    path.startsWith('lib/l10n/') ||
    path.startsWith('lib/api/');

/// Source lines of [path] that mention `guestPhone` outside a `//` comment.
List<String> _codeHits(String path) => <String>[
  for (final String line in File(path).readAsLinesSync())
    if (line.contains('guestPhone') && !line.trimLeft().startsWith('//'))
      line.trim(),
];

/// Source lines of [path] that reference `clientPhone` / `clientPhoneFor`
/// outside a `//` comment.
List<String> _clientPhoneHits(String path) => <String>[
  for (final String line in File(path).readAsLinesSync())
    if (_clientPhoneRef.hasMatch(line) && !line.trimLeft().startsWith('//'))
      line.trim(),
];

/// Non-generated `.dart` files under `lib/`, slash-normalised.
List<String> _libSources() => <String>[
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart'))
      if (!_generated(e.path.replaceAll(r'\', '/')))
        e.path.replaceAll(r'\', '/'),
];

void main() {
  test('guestPhone is read in lib/ only by the model and the mapper', () {
    final List<String> offenders = <String>[];
    int scanned = 0;
    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String path = e.path.replaceAll(r'\', '/');
      if (_generated(path)) continue;
      scanned++;
      if (_allowed.contains(path)) continue;
      if (_codeHits(path).isNotEmpty) offenders.add(path);
    }

    expect(scanned, greaterThan(100), reason: 'the scan must see lib/');
    expect(
      offenders,
      isEmpty,
      reason:
          'USER RULE (2026-11-21): «Деталі запису» shows no client phone; the '
          'guest phone is only mapped (model + mapper). The phone lives on the '
          'client card. Remove the `guestPhone` read from: $offenders',
    );
  });

  test('every allow-listed file still exists and really references it', () {
    for (final String path in _allowed) {
      expect(
        File(path).existsSync() && _codeHits(path).isNotEmpty,
        isTrue,
        reason: '$path no longer references guestPhone — update the list',
      );
    }
  });

  test('Booking.clientPhone is read in lib/ only by its owning files', () {
    final List<String> sources = _libSources();
    expect(sources.length, greaterThan(100), reason: 'the scan must see lib/');
    final List<String> offenders = <String>[
      for (final String path in sources)
        if (!_clientPhoneAllowed.contains(path) &&
            _clientPhoneHits(path).isNotEmpty)
          path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'USER RULE (2026-11-21): «Деталі запису» shows no client phone; '
          'Booking.clientPhone is only mapped (model + mapper). The phone '
          'lives on the client card. Remove the `clientPhone` read from: '
          '$offenders',
    );
  });

  test('every clientPhone owner still exists and really references it', () {
    for (final String path in _clientPhoneAllowed) {
      expect(
        File(path).existsSync() && _clientPhoneHits(path).isNotEmpty,
        isTrue,
        reason: '$path no longer references clientPhone — update the list',
      );
    }
  });
}
