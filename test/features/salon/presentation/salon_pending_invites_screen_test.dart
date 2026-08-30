// Phase 21.11 — Widget tests for [SalonPendingInvitesScreen] and the
// [PendingInvites] notifier's per-row cancel machine.
//
// Covers:
//   1. The resolved list renders one [PendingInviteRow] per invitation, in
//      backend order, with the header count matching — and each row carries
//      its OWN invite's email, so a mis-keyed row (all three rendering the
//      same invite) cannot pass.
//   2. Cancel: the tapped row's `DELETE` receives THAT row's `(salonId,
//      inviteId)`, the row disappears on success, and the siblings stay put
//      (the headline case — a cancel that removed the wrong row, or all of
//      them, would still "make a row disappear").
//   3. While the `DELETE` is in flight the tapped row swaps «Скасувати» for
//      an in-row spinner, the OTHER rows keep their labels, and a second tap
//      on the busy row issues no second call.
//   4. A failed cancel leaves the row in the list and raises its in-row error
//      chip — scoped to that row, with the list itself still rendered (NOT a
//      full-screen error). Tapping again clears the chip and retries.
//   5. Empty list → the empty state, no rows, no section header.
//   6. Error → the shared [ErrorState]; its retry re-fetches and the list
//      renders.
//   7. The pinned CTA pushes `RouteNames.salonInviteStaff` with THIS salonId.
//
// Finders use widget Keys and l10n-resolved strings — never Cyrillic literals
// (`forbid_cyrillic_finder.sh`). Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/pending_invite.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_pending_invites_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/pending_invite_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/pump_app.dart';

const String _kSalonId = 'salon-1';
const Salon _kSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

/// A fixed instant for `createdAt` — the row's "надіслано …" caption is
/// rendered through `formatRelativeDate`, which reads the HOST clock for
/// "now". Anchoring the fixture far enough in the past keeps the caption in a
/// stable bucket without pinning a clock the screen does not inject (test
/// clock coherence: both sides live, never mixed).
final DateTime _kSentAt = DateTime.now().subtract(const Duration(days: 3));

List<PendingInvite> _invites() => <PendingInvite>[
  PendingInvite(
    inviteId: 'inv-a',
    recipientEmail: 'anna@example.com',
    role: SalonStaffRole.master,
    createdAt: _kSentAt,
  ),
  PendingInvite(
    inviteId: 'inv-b',
    recipientEmail: 'borys@example.com',
    role: SalonStaffRole.admin,
    createdAt: _kSentAt,
  ),
  PendingInvite(
    inviteId: 'inv-c',
    recipientEmail: 'chrystyna@example.com',
    role: SalonStaffRole.master,
    createdAt: _kSentAt,
  ),
];

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.salonPendingInvites(_kSalonId),
  routes: <RouteBase>[
    GoRoute(
      path: '/salons/:salonId/pending-invites',
      builder: (context, state) =>
          SalonPendingInvitesScreen(salonId: state.pathParameters['salonId']!),
    ),
    GoRoute(
      path: '/salons/:salonId/manage/invite',
      builder: (context, state) => Scaffold(
        body: SizedBox(
          key: Key('stub-invite-${state.pathParameters['salonId']}'),
        ),
      ),
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeSalonRepository repo, {
  Duration? Function(int retryCount, Object error)? retry,
}) async {
  final GoRouter router = _router();
  addTearDown(router.dispose);
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
    retry: retry,
  );
  await tester.pumpAndSettle();
  return router;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SalonPendingInvitesScreen)));

Finder _cancelOf(String inviteId) =>
    find.byKey(pendingInviteCancelKey(inviteId));

void main() {
  group('list rendering', () {
    testWidgets('renders one row per invitation, each with its own email', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        pendingInvites: _invites(),
      );
      await _pump(tester, repo);

      expect(find.byType(PendingInviteRow), findsNWidgets(3));
      // Per-row identity: a row keyed to the wrong invite, or three copies of
      // one invite, fails here even though the count above would pass.
      for (final PendingInvite invite in _invites()) {
        expect(
          find.descendant(
            of: find.byKey(pendingInviteRowKey(invite.inviteId)),
            matching: find.text(invite.recipientEmail),
          ),
          findsOneWidget,
          reason: 'row ${invite.inviteId} must show its own recipient',
        );
      }
      // The header carries the count.
      expect(
        find.descendant(
          of: find.byKey(const Key('pending-invites-header')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pending-invites-empty')), findsNothing);
    });

    testWidgets('an admin invite and a master invite carry DIFFERENT role '
        'chips', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        pendingInvites: _invites(),
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      expect(
        find.descendant(
          of: find.byKey(pendingInviteRowKey('inv-b')),
          matching: find.text(l10n.inviteStaffRoleAdmin),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(pendingInviteRowKey('inv-a')),
          matching: find.text(l10n.inviteStaffRoleMaster),
        ),
        findsOneWidget,
      );
    });
  });

  group('cancel', () {
    testWidgets('removes ONLY the tapped row and sends its own inviteId', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        pendingInvites: _invites(),
      );
      await _pump(tester, repo);

      await tester.tap(_cancelOf('inv-b'));
      await tester.pumpAndSettle();

      expect(repo.cancelInviteRequests, hasLength(1));
      expect(repo.cancelInviteRequests.single.salonId, _kSalonId);
      expect(repo.cancelInviteRequests.single.inviteId, 'inv-b');

      expect(find.byKey(pendingInviteRowKey('inv-b')), findsNothing);
      expect(find.byKey(pendingInviteRowKey('inv-a')), findsOneWidget);
      expect(find.byKey(pendingInviteRowKey('inv-c')), findsOneWidget);
      expect(find.byType(PendingInviteRow), findsNWidgets(2));
      // The header count follows the removal.
      expect(
        find.descendant(
          of: find.byKey(const Key('pending-invites-header')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the LAST invitation reveals the empty state', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        pendingInvites: <PendingInvite>[_invites().first],
      );
      await _pump(tester, repo);

      await tester.tap(_cancelOf('inv-a'));
      await tester.pumpAndSettle();

      expect(find.byType(PendingInviteRow), findsNothing);
      expect(find.byKey(const Key('pending-invites-empty')), findsOneWidget);
    });

    testWidgets('while in flight the tapped row spins, the siblings do not, '
        'and a second tap issues no second call', (tester) async {
      final gate = Completer<void>();
      final repo = FakeSalonRepository(
        salon: _kSalon,
        pendingInvites: _invites(),
      )..cancelInviteGate = gate;
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(_cancelOf('inv-b'));
      // One frame — enough for the notifier's optimistic `cancelling` write to
      // reach the tree, not enough for the (gated) request to resolve.
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(pendingInviteRowKey('inv-b')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason: 'the busy row swaps its label for an in-row spinner',
      );
      expect(
        find.descendant(
          of: find.byKey(pendingInviteRowKey('inv-b')),
          matching: find.text(l10n.salonPendingInvitesCancelCta),
        ),
        findsNothing,
      );
      // Siblings are untouched — the busy state is per row, not per screen.
      expect(
        find.descendant(
          of: find.byKey(pendingInviteRowKey('inv-a')),
          matching: find.text(l10n.salonPendingInvitesCancelCta),
        ),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Re-entry guard: tapping the busy row again must not queue a second
      // DELETE.
      await tester.tap(_cancelOf('inv-b'), warnIfMissed: false);
      await tester.pump();
      expect(repo.cancelInviteRequests, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(pendingInviteRowKey('inv-b')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a FAILED cancel restores nothing — the row stays, its error '
        'chip appears, and the list is still rendered', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        pendingInvites: _invites(),
      )..cancelInviteError = const ServerFailure(statusCode: 500);
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(_cancelOf('inv-b'));
      await tester.pumpAndSettle();

      expect(find.byKey(pendingInviteRowKey('inv-b')), findsOneWidget);
      expect(find.byType(PendingInviteRow), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byKey(pendingInviteRowKey('inv-b')),
          matching: find.text(l10n.salonPendingInvitesCancelError),
        ),
        findsOneWidget,
      );
      // Scoped to the failed row — the siblings carry no chip, and the screen
      // did NOT fall back to the full-screen error state.
      expect(find.text(l10n.salonPendingInvitesCancelError), findsOneWidget);
      expect(find.byType(ErrorState), findsNothing);
      // The spinner cleared.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'retrying after a failure clears the chip and removes the row',
      (tester) async {
        final repo = FakeSalonRepository(
          salon: _kSalon,
          pendingInvites: _invites(),
        )..cancelInviteError = const ServerFailure(statusCode: 500);
        await _pump(tester, repo);
        final AppLocalizations l10n = _l10n(tester);

        await tester.tap(_cancelOf('inv-b'));
        await tester.pumpAndSettle();
        expect(find.text(l10n.salonPendingInvitesCancelError), findsOneWidget);

        repo.cancelInviteError = null;
        await tester.tap(_cancelOf('inv-b'));
        await tester.pumpAndSettle();

        expect(repo.cancelInviteRequests, hasLength(2));
        expect(find.byKey(pendingInviteRowKey('inv-b')), findsNothing);
        expect(find.text(l10n.salonPendingInvitesCancelError), findsNothing);
      },
    );
  });

  group('empty / error branches', () {
    testWidgets('no invitations → the empty state, no rows, no header', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _kSalon);
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      expect(find.byKey(const Key('pending-invites-empty')), findsOneWidget);
      expect(find.text(l10n.salonPendingInvitesEmptyTitle), findsOneWidget);
      expect(find.byType(PendingInviteRow), findsNothing);
      expect(find.byKey(const Key('pending-invites-header')), findsNothing);
      // The CTA is pinned in the footer, so it is on screen in the empty
      // branch too — the empty state is an invitation to act, not a dead end.
      expect(
        find.byKey(const Key('pending-invites-invite-cta')),
        findsOneWidget,
      );
    });

    testWidgets('a failed fetch shows ErrorState; retry re-fetches and the '
        'list renders', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        pendingInvites: _invites(),
      )..listPendingInvitesError = const ServerFailure(statusCode: 500);
      // `retry: null` — the production retry policy would re-issue the failed
      // fetch on a timer and make `listPendingInvitesCalls` non-deterministic.
      await _pump(tester, repo, retry: (_, _) => null);

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byType(PendingInviteRow), findsNothing);
      expect(repo.listPendingInvitesCalls, 1);

      repo.listPendingInvitesError = null;
      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(repo.listPendingInvitesCalls, 2);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byType(PendingInviteRow), findsNWidgets(3));
    });
  });

  group('invite CTA', () {
    testWidgets('pushes the invite-staff route with THIS salonId', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        pendingInvites: _invites(),
      );
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('pending-invites-invite-cta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-invite-$_kSalonId')), findsOneWidget);
    });
  });
}
