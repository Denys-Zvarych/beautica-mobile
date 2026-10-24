// Phase 417 (mobile-qa) — STRUCTURAL GATE: where `guestPhone` may be read.
//
// USER RULE (2026-10-22): the GUEST's phone is shown only on «Деталі запису»,
// only for a guest booking, only to an independent master / salon owner /
// salon admin. A SALON_MASTER (even the performing one) and a CLIENT never see
// it, and a REGISTERED client's phone is shown nowhere.
//
// Nothing at runtime notices a new screen that renders the field, so this test
// pins every non-comment reference in `lib/` to the four files that own it:
//   • booking.dart                 — the model field;
//   • booking_mapper.dart          — DTO → model mapping;
//   • booking_display_x.dart       — `guestPhoneFor`, the role + guest gate;
//   • booking_detail_screen.dart   — the only renderer (reads the GATED value).
// Comments and generated code are ignored.
//
// ADDING A SITE is a deliberate act: it must go through `guestPhoneFor`, and
// the allow-list below is updated in a reviewed diff.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const Set<String> _allowed = <String>{
  'lib/features/booking/domain/booking.dart',
  'lib/features/booking/data/booking_mapper.dart',
  'lib/features/booking/domain/booking_display_x.dart',
  'lib/features/booking/presentation/booking_detail_screen.dart',
};

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

void main() {
  test('guestPhone is read in lib/ only by the four owning files', () {
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
          'USER RULE (2026-10-22): the guest phone is shown only on «Деталі '
          'запису» via BookingDisplayX.guestPhoneFor — never to a salon master '
          'or client, and a registered client\'s phone nowhere. Remove the '
          '`guestPhone` read from: $offenders',
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
}
