// Unit tests for [SalonInvites] — the invite-history notifier's cancel guard
// and its IN-PLACE status transition.
//
// WHY THIS FILE EXISTS
// --------------------
// `salon_pending_invites_screen_test.dart` drives this notifier through the
// WIDGET, so it can only reach `cancelInvite` for ids whose row currently
// renders «Скасувати» — i.e. pending ones. The notifier's own doc calls its
// `isCancellable` check "the AUTHORITATIVE guard", explicitly for callers
// reaching PAST the widget: a stale closure held across a status flip, a
// future surface, a test. That path had no coverage at all, so the guard the
// doc leans on was unexercised.
//
// The transition contract is equally load-bearing and equally unpinned at
// this layer: a successful cancel must REPLACE the row in place with
// [InviteStatus.cancelled], never remove it. This is a HISTORY list — a local
// removal would contradict the very list the next refetch returns (proved
// end-to-end in `integration_test/salon_pending_invites_flow_test.dart`;
// proved here as a pure state transition, with no tree in the way).
//
// Riverpod hygiene: a FRESH [ProviderContainer] per test, disposed through
// `addTearDown`, and the repository always overridden with the shared
// [FakeSalonRepository] — no real network, no real storage.
//
// Pure Dart / provider-level: no widget tree.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/application/salon_invites_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/invite_status.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_invite.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';

const String _kSalonId = 'salon-1';
const Salon _kSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

final DateTime _kSentAt = DateTime.utc(2026, 6, 20, 9);
final DateTime _kExpiresAt = DateTime.utc(2026, 6, 22, 9);

SalonInvite _invite(String id, InviteStatus status) => SalonInvite(
  inviteId: id,
  recipientEmail: '$id@beautica.ua',
  role: SalonStaffRole.master,
  status: status,
  createdAt: _kSentAt,
  expiresAt: _kExpiresAt,
);

/// A MIXED history — one row per status, newest-first exactly as the server
/// sends it. Deliberately NOT all-pending: an all-pending fixture cannot tell
/// a working guard from an absent one.
List<SalonInvite> _history() => <SalonInvite>[
  _invite('inv-pending', InviteStatus.pending),
  _invite('inv-cancelled', InviteStatus.cancelled),
  _invite('inv-expired', InviteStatus.expired),
  _invite('inv-accepted', InviteStatus.accepted),
  _invite('inv-unknown', InviteStatus.unknown),
];

/// Builds a container with [salonRepositoryProvider] faked, disposed on
/// teardown (no state leaks between tests).
ProviderContainer _container(FakeSalonRepository repo) {
  final ProviderContainer container = ProviderContainer(
    // No retry: these tests assert EXACT DELETE call counts, and the
    // production policy would re-issue a failed one on a timer.
    retry: (_, _) => null,
    overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)].cast(),
  );
  addTearDown(container.dispose);
  return container;
}

Future<SalonInvitesState> _resolved(ProviderContainer container) =>
    container.read(salonInvitesProvider(_kSalonId).future);

SalonInvitesState _state(ProviderContainer container) =>
    container.read(salonInvitesProvider(_kSalonId)).requireValue;

SalonInvites _notifier(ProviderContainer container) =>
    container.read(salonInvitesProvider(_kSalonId).notifier);

void main() {
  group('build', () {
    test('carries the server list, its ORDER, and the truncated flag; derives '
        'the pending subset', () async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _history(),
        salonInvitesTruncated: true,
      );
      final ProviderContainer container = _container(repo);

      final SalonInvitesState state = await _resolved(container);

      expect(state.invites.map((SalonInvite i) => i.inviteId), <String>[
        'inv-pending',
        'inv-cancelled',
        'inv-expired',
        'inv-accepted',
        'inv-unknown',
      ]);
      expect(state.truncated, isTrue);
      expect(state.pending.map((SalonInvite i) => i.inviteId), <String>[
        'inv-pending',
      ]);
      expect(state.cancelling, isEmpty);
      expect(state.failed, isEmpty);
    });
  });

  group('cancelInvite is a NO-OP for anything not pending', () {
    // The authoritative guard. `DELETE .../invites/{inviteId}` 404s for every
    // used, revoked or expired invitation, so a caller reaching past the
    // widget must not be able to fire a request the server will reject.
    for (final String id in <String>[
      'inv-cancelled',
      'inv-expired',
      'inv-accepted',
      'inv-unknown',
    ]) {
      test('$id: no DELETE is issued and the state is untouched', () async {
        final repo = FakeSalonRepository(
          salon: _kSalon,
          salonInvites: _history(),
        );
        final ProviderContainer container = _container(repo);
        final SalonInvitesState before = await _resolved(container);

        await _notifier(container).cancelInvite(id);

        expect(
          repo.cancelInviteRequests,
          isEmpty,
          reason:
              'the notifier guard, not the widget, is what stops a request '
              'the backend would 404',
        );
        final SalonInvitesState after = _state(container);
        expect(after.invites, same(before.invites));
        expect(after.pending, same(before.pending));
        expect(after.cancelling, isEmpty);
        expect(after.failed, isEmpty);
      });
    }

    test('an id absent from the list is handled without a request or a '
        'throw', () async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _history(),
      );
      final ProviderContainer container = _container(repo);
      final SalonInvitesState before = await _resolved(container);

      await _notifier(container).cancelInvite('inv-does-not-exist');

      expect(repo.cancelInviteRequests, isEmpty);
      expect(_state(container).invites, same(before.invites));
    });

    test('cancelInvite before the list resolves issues nothing', () async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _history(),
      );
      final ProviderContainer container = _container(repo);
      // Read the notifier WITHOUT awaiting `.future` — the state is
      // AsyncLoading, so the `state is! AsyncData` guard must fire.
      await _notifier(container).cancelInvite('inv-pending');

      expect(repo.cancelInviteRequests, isEmpty);
    });
  });

  group('a successful cancel REPLACES the row in place', () {
    test('same length, same index, same order — status flips to cancelled and '
        'the pending subset loses it', () async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _history(),
      );
      final ProviderContainer container = _container(repo);
      final SalonInvitesState before = await _resolved(container);
      expect(before.invites, hasLength(5));

      await _notifier(container).cancelInvite('inv-pending');

      expect(repo.cancelInviteRequests, hasLength(1));
      expect(repo.cancelInviteRequests.single.salonId, _kSalonId);
      expect(repo.cancelInviteRequests.single.inviteId, 'inv-pending');

      final SalonInvitesState after = _state(container);
      // HISTORY must not lose the row.
      expect(after.invites, hasLength(5));
      expect(after.invites.map((SalonInvite i) => i.inviteId), <String>[
        'inv-pending',
        'inv-cancelled',
        'inv-expired',
        'inv-accepted',
        'inv-unknown',
      ]);
      expect(after.invites.first.status, InviteStatus.cancelled);
      expect(after.invites.first.isCancellable, isFalse);
      // Every OTHER row is byte-identical — a cancel touches exactly one.
      for (int i = 1; i < after.invites.length; i++) {
        expect(after.invites[i], before.invites[i]);
      }
      // The derived subset is recomputed — this is the one transition that
      // genuinely leaves it.
      expect(after.pending, isEmpty);
      expect(after.cancelling, isEmpty);
      expect(after.failed, isEmpty);
      expect(after.truncated, before.truncated);
    });

    test('a second cancel of the SAME row is now refused by the guard — the '
        'row is no longer pending', () async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _history(),
      );
      final ProviderContainer container = _container(repo);
      await _resolved(container);

      await _notifier(container).cancelInvite('inv-pending');
      await _notifier(container).cancelInvite('inv-pending');

      expect(
        repo.cancelInviteRequests,
        hasLength(1),
        reason:
            'the flip to CANCELLED must close the guard — a stale closure '
            'firing again would hit a 404',
      );
    });
  });

  group('a failed cancel', () {
    test('leaves the row pending and in place, and records the id in '
        'failed', () async {
      final repo = FakeSalonRepository(salon: _kSalon, salonInvites: _history())
        ..cancelInviteError = const ServerFailure(statusCode: 500);
      final ProviderContainer container = _container(repo);
      final SalonInvitesState before = await _resolved(container);

      await _notifier(container).cancelInvite('inv-pending');

      final SalonInvitesState after = _state(container);
      expect(after.invites, hasLength(5));
      expect(after.invites.first, before.invites.first);
      expect(after.invites.first.status, InviteStatus.pending);
      expect(after.failed, <String>{'inv-pending'});
      expect(after.cancelling, isEmpty);
      expect(
        after.pending,
        same(before.pending),
        reason:
            'the row is untouched, so the derived subset must carry over by '
            'IDENTITY — a fresh list would rebuild every consuming row',
      );
    });

    test('retrying clears the failure flag and flips the row', () async {
      final repo = FakeSalonRepository(salon: _kSalon, salonInvites: _history())
        ..cancelInviteError = const ServerFailure(statusCode: 500);
      final ProviderContainer container = _container(repo);
      await _resolved(container);

      await _notifier(container).cancelInvite('inv-pending');
      expect(_state(container).failed, <String>{'inv-pending'});

      repo.cancelInviteError = null;
      await _notifier(container).cancelInvite('inv-pending');

      expect(repo.cancelInviteRequests, hasLength(2));
      final SalonInvitesState after = _state(container);
      expect(after.failed, isEmpty);
      expect(after.invites.first.status, InviteStatus.cancelled);
      expect(after.invites, hasLength(5));
    });
  });
}
