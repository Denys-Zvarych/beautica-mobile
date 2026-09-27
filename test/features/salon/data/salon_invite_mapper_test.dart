// Unit tests for [SalonInviteMapper] — the `GET /salons/{salonId}/invites`
// DTO -> [SalonInvite] boundary.
//
// WHY THIS FILE EXISTS
// --------------------
// Three separate gaps, all at the same boundary and none previously covered:
//
//   1. `_statusFromWire` is the ONLY place a wire string becomes an
//      [InviteStatus], and every screen fixture in the suite constructed
//      [SalonInvite] directly in Dart — so nothing proved a `'CANCELLED'` on
//      the wire ever reaches the domain as [InviteStatus.cancelled], nor that
//      an UNRECOGNISED value degrades to [InviteStatus.unknown] instead of
//      being guessed at. `unknown` is a security-relevant fallback, not a
//      cosmetic one: it is what stops a fifth backend state from rendering a
//      cancel action the server would 404.
//
//   2. mobile-security MEDIUM — `recipientEmail` is ATTACKER-INFLUENCED (a
//      SALON_ADMIN types it into the invite form; the OWNER reads it back in
//      the history). `validateEmail`'s `[^@\s]+` local part accepts U+202E,
//      U+200B, U+2066 and U+200E, and the backend applies no character-class
//      check either. `salon_mapper.dart:313` runs the address through
//      `sanitizeDisplayText` at the boundary so ONE call covers both the
//      visible `Text` and the «Скасувати» semantic label built from the same
//      string. Nothing asserted that call existed.
//
//   3. The per-row degradation contract: a row with no `inviteId` is DROPPED
//      (it could be neither keyed nor cancelled) while its siblings survive,
//      and a missing timestamp falls back to the epoch rather than hiding an
//      invitation the viewer needs to see.
//
// MUTATION-PROBED 2026-09-02: deleting the `sanitizeDisplayText(...)` wrapper
// at `salon_mapper.dart:313` (leaving `dto.recipientEmail ?? ''`) turns the
// sanitization group RED. Restored immediately; the observed failure is in
// the QA report.
//
// Pure Dart unit test: no widget tree, no network, no clock.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/salon/data/salon_mapper.dart';
import 'package:beautica_mobile/features/salon/domain/invite_status.dart';
import 'package:beautica_mobile/features/salon/domain/salon_invite.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Unix epoch in UTC — the mapper's fallback for a missing timestamp.
final DateTime _kEpoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

final DateTime _kCreatedAt = DateTime.utc(2026, 6, 20, 9);
final DateTime _kExpiresAt = DateTime.utc(2026, 6, 22, 9);

SalonInviteResponse _dto({
  String? inviteId = 'inv-1',
  String? recipientEmail = 'anna@beautica.ua',
  String? role = 'SALON_MASTER',
  String? status = 'PENDING',
  DateTime? createdAt,
  DateTime? expiresAt,
  bool omitCreatedAt = false,
  bool omitExpiresAt = false,
}) => SalonInviteResponse(
  (SalonInviteResponseBuilder b) => b
    ..inviteId = inviteId
    ..recipientEmail = recipientEmail
    ..role = role
    ..status = status
    ..createdAt = omitCreatedAt ? null : (createdAt ?? _kCreatedAt)
    ..expiresAt = omitExpiresAt ? null : (expiresAt ?? _kExpiresAt),
);

SalonInvite _mapOne(SalonInviteResponse dto) =>
    SalonInviteMapper.fromDtoList(<SalonInviteResponse>[dto]).single;

void main() {
  group('_statusFromWire — the four recognised wire values', () {
    // The table is exhaustive over the backend's derived status vocabulary
    // (see `invite_status.dart`'s header: PENDING/EXPIRED derive from
    // `expires_at`, ACCEPTED from `is_used`, CANCELLED from the revocation
    // marker). A renamed wire value silently becomes `unknown` — a row that
    // renders no chip and no action — so each one is pinned by name.
    const Map<String, InviteStatus> cases = <String, InviteStatus>{
      'PENDING': InviteStatus.pending,
      'ACCEPTED': InviteStatus.accepted,
      'EXPIRED': InviteStatus.expired,
      'CANCELLED': InviteStatus.cancelled,
    };
    cases.forEach((String wire, InviteStatus expected) {
      test('$wire maps to $expected', () {
        expect(_mapOne(_dto(status: wire)).status, expected);
      });
    });

    test('ONLY pending is cancellable — the widget affordance and the '
        'notifier guard both read this one getter', () {
      expect(_mapOne(_dto(status: 'PENDING')).isCancellable, isTrue);
      for (final String wire in <String>[
        'ACCEPTED',
        'EXPIRED',
        'CANCELLED',
        'SUPERSEDED',
      ]) {
        expect(
          _mapOne(_dto(status: wire)).isCancellable,
          isFalse,
          reason:
              'DELETE .../invites/{inviteId} 404s for every non-pending '
              'invite — offering the action anywhere else is a guaranteed '
              'error',
        );
      }
    });
  });

  group('_statusFromWire — everything unrecognised degrades to unknown', () {
    // `unknown` is the FORWARD-COMPATIBILITY fallback. It renders no status
    // chip and no cancel action, so an unrecognised state can never be
    // mislabelled and can never offer an action the server would reject.
    const Map<String, String?> cases = <String, String?>{
      'a null status (field absent from the payload)': null,
      'an empty string': '',
      'the correct value in the WRONG CASE (matching is literal, not '
              'case-insensitive)':
          'pending',
      'a fifth state a newer backend introduces': 'SUPERSEDED',
      'a whitespace-padded value': ' PENDING ',
    };
    cases.forEach((String name, String? wire) {
      test('$name maps to InviteStatus.unknown', () {
        expect(_mapOne(_dto(status: wire)).status, InviteStatus.unknown);
      });
    });
  });

  group('role mapping', () {
    test('SALON_ADMIN maps to admin', () {
      expect(_mapOne(_dto(role: 'SALON_ADMIN')).role, SalonStaffRole.admin);
    });

    test('SALON_MASTER maps to master', () {
      expect(_mapOne(_dto(role: 'SALON_MASTER')).role, SalonStaffRole.master);
    });

    test('a null or unrecognised role falls back to master (the fail-safe '
        'direction — the LESS privileged of the two)', () {
      expect(_mapOne(_dto(role: null)).role, SalonStaffRole.master);
      expect(_mapOne(_dto(role: 'SALON_OWNER')).role, SalonStaffRole.master);
      expect(_mapOne(_dto(role: 'salon_admin')).role, SalonStaffRole.master);
    });
  });

  group('recipientEmail is SANITISED at the boundary (mobile-security)', () {
    // Written as \uXXXX escapes, never literal characters, so this file does
    // not itself embed the control characters it is asserting are stripped
    // (same convention `sanitize_display_text.dart` follows).
    //
    // All four of these PASS `validateEmail` — empirically confirmed by the
    // security audit — so the invite form will happily send them and the
    // backend will happily store them. The mapper is the only thing between
    // a hostile address and a `Text` widget that (since the history rework
    // moved the address to `maxLines: 2` + soft wrap) no longer clips the
    // payload to one line.
    const Map<String, String> hostile = <String, String>{
      'U+202E RIGHT-TO-LEFT OVERRIDE': '\u202E',
      'U+200B ZERO WIDTH SPACE': '\u200B',
      'U+2066 LEFT-TO-RIGHT ISOLATE': '\u2066',
      'U+200E LEFT-TO-RIGHT MARK': '\u200E',
    };
    hostile.forEach((String name, String payload) {
      test('$name does not survive into the domain object', () {
        final SalonInvite invite = _mapOne(
          _dto(recipientEmail: 'anna${payload}evil@beautica.ua'),
        );

        expect(
          invite.recipientEmail,
          'annaevil@beautica.ua',
          reason:
              'the control character must be STRIPPED at the mapper, not '
              'passed through to the row Text and the «Скасувати» semantic '
              'label built from the same string',
        );
        expect(invite.recipientEmail.contains(payload), isFalse);
      });
    });

    test('a payload combining all four is stripped in one pass', () {
      expect(
        _mapOne(
          _dto(recipientEmail: 'a\u202En\u200Bn\u2066a\u200E@beautica.ua'),
        ).recipientEmail,
        'anna@beautica.ua',
      );
    });

    test('a null recipientEmail becomes an empty string, never a crash', () {
      expect(_mapOne(_dto(recipientEmail: null)).recipientEmail, '');
    });

    test('an ordinary address is passed through byte-for-byte — sanitization '
        'must not mangle legitimate input', () {
      expect(
        _mapOne(
          _dto(recipientEmail: "o'brien.mc-tavish+staff@beautica.ua"),
        ).recipientEmail,
        "o'brien.mc-tavish+staff@beautica.ua",
      );
    });
  });

  group('timestamps', () {
    test('createdAt and expiresAt are carried through verbatim', () {
      final SalonInvite invite = _mapOne(_dto());
      expect(invite.createdAt, _kCreatedAt);
      expect(invite.expiresAt, _kExpiresAt);
    });

    test('a null expiresAt falls back to the Unix epoch (UTC) rather than '
        'dropping the row — the field drives no visible surface', () {
      final SalonInvite invite = _mapOne(_dto(omitExpiresAt: true));
      expect(invite.expiresAt, _kEpoch);
      expect(invite.expiresAt.isUtc, isTrue);
      // The row still exists and still carries everything else.
      expect(invite.inviteId, 'inv-1');
      expect(invite.status, InviteStatus.pending);
    });

    test('a null createdAt falls back to the Unix epoch (UTC) — a missing '
        'timestamp must not hide an invitation', () {
      final SalonInvite invite = _mapOne(_dto(omitCreatedAt: true));
      expect(invite.createdAt, _kEpoch);
      expect(invite.createdAt.isUtc, isTrue);
    });
  });

  group('per-row degradation and ordering', () {
    test('a row with a NULL inviteId is dropped; its siblings survive', () {
      final List<SalonInvite> out =
          SalonInviteMapper.fromDtoList(<SalonInviteResponse>[
            _dto(inviteId: 'keep-1'),
            _dto(inviteId: null, recipientEmail: 'broken@beautica.ua'),
            _dto(inviteId: 'keep-2'),
          ]);

      expect(out.map((SalonInvite i) => i.inviteId), <String>[
        'keep-1',
        'keep-2',
      ]);
      expect(
        out.map((SalonInvite i) => i.recipientEmail),
        isNot(contains('broken@beautica.ua')),
        reason: 'one broken row must cost its own row, never the whole list',
      );
    });

    test('a row with an EMPTY inviteId is dropped too — "" could be neither '
        'keyed nor cancelled', () {
      final List<SalonInvite> out = SalonInviteMapper.fromDtoList(
        <SalonInviteResponse>[_dto(inviteId: ''), _dto(inviteId: 'keep')],
      );

      expect(out.map((SalonInvite i) => i.inviteId), <String>['keep']);
    });

    test('WIRE ORDER is preserved — the server sorts createdAt DESC and the '
        'mapper must not re-sort', () {
      // Ids ASCEND while createdAt DESCENDS, so a mapper that sorted by
      // either field would produce a visibly different sequence rather than
      // landing on the same order by luck.
      final List<SalonInvite> out =
          SalonInviteMapper.fromDtoList(<SalonInviteResponse>[
            _dto(inviteId: 'a', createdAt: DateTime.utc(2026, 6, 20)),
            _dto(inviteId: 'b', createdAt: DateTime.utc(2026, 6, 18)),
            _dto(inviteId: 'c', createdAt: DateTime.utc(2026, 6, 14)),
          ]);

      expect(out.map((SalonInvite i) => i.inviteId), <String>['a', 'b', 'c']);
    });

    test('an empty wire list maps to an empty list, never null', () {
      expect(
        SalonInviteMapper.fromDtoList(const <SalonInviteResponse>[]),
        isEmpty,
      );
    });

    test('a MIXED-status page maps every row independently — the exact shape '
        'the history screen renders', () {
      final List<SalonInvite> out =
          SalonInviteMapper.fromDtoList(<SalonInviteResponse>[
            _dto(inviteId: 'h-1', status: 'PENDING', role: 'SALON_MASTER'),
            _dto(inviteId: 'h-2', status: 'CANCELLED', role: 'SALON_ADMIN'),
            _dto(inviteId: 'h-3', status: 'EXPIRED', role: 'SALON_MASTER'),
            _dto(inviteId: 'h-4', status: 'ACCEPTED', role: 'SALON_ADMIN'),
            _dto(inviteId: 'h-5', status: 'SUPERSEDED', role: 'SALON_ADMIN'),
          ]);

      expect(out.map((SalonInvite i) => i.status), <InviteStatus>[
        InviteStatus.pending,
        InviteStatus.cancelled,
        InviteStatus.expired,
        InviteStatus.accepted,
        InviteStatus.unknown,
      ]);
      expect(
        out
            .where((SalonInvite i) => i.isCancellable)
            .map((SalonInvite i) => i.inviteId),
        <String>['h-1'],
      );
    });
  });
}
