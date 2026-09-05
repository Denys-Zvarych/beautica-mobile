// Widget tests for [SalonPendingInvitesScreen] and the [SalonInvites]
// notifier's per-row cancel machine.
//
// Covers:
//   1. The resolved list renders one [SalonInviteRow] per invitation, in
//      backend order, with the header count matching — and each row carries
//      its OWN invite's email, so a mis-keyed row (all three rendering the
//      same invite) cannot pass.
//   2. Cancel: the tapped row's `DELETE` receives THAT row's `(salonId,
//      inviteId)`, that row FLIPS to «Скасовано» IN PLACE, and the siblings
//      stay pending (the headline case — a cancel that hit the wrong row, or
//      all of them, would still "change a row"). The screen is a HISTORY
//      list, so a cancelled invitation must never disappear from it.
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
import 'package:beautica_mobile/features/salon/domain/invite_status.dart';
import 'package:beautica_mobile/features/salon/domain/salon_invite.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_pending_invites_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_invite_row.dart';
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

/// Nothing on this screen renders `expiresAt` — the server owns the status
/// derivation — so the fixture only needs a coherent value, not a meaningful
/// one.
final DateTime _kExpiresAt = _kSentAt.add(const Duration(hours: 48));

/// Three PENDING invitations — the fixture the cancel cases need, since only
/// a pending row renders «Скасувати» at all.
///
/// Per-ROW mixed-status rendering (which chip, which tint, which affordance)
/// is `presentation/widgets/salon_invite_row_test.dart`'s job. What the
/// `mixed-status history` group below adds is the SCREEN-level half that file
/// structurally cannot see: four different statuses side by side in one list,
/// server order preserved across the `SliverList.builder`, and exactly one
/// cancel affordance across the whole screen.
List<SalonInvite> _invites() => <SalonInvite>[
  SalonInvite(
    inviteId: 'inv-a',
    recipientEmail: 'anna@example.com',
    role: SalonStaffRole.master,
    status: InviteStatus.pending,
    createdAt: _kSentAt,
    expiresAt: _kExpiresAt,
  ),
  SalonInvite(
    inviteId: 'inv-b',
    recipientEmail: 'borys@example.com',
    role: SalonStaffRole.admin,
    status: InviteStatus.pending,
    createdAt: _kSentAt,
    expiresAt: _kExpiresAt,
  ),
  SalonInvite(
    inviteId: 'inv-c',
    recipientEmail: 'chrystyna@example.com',
    role: SalonStaffRole.master,
    status: InviteStatus.pending,
    createdAt: _kSentAt,
    expiresAt: _kExpiresAt,
  ),
];

/// FOUR invitations, one per wire status, in the order the server sends them
/// (`createdAt DESC`) — the shape of a real history page.
///
/// The ids ASCEND while the intended display order is exactly this sequence,
/// so a client-side re-sort by id, email or status would produce a visibly
/// different order rather than landing on the same one by luck.
List<SalonInvite> _mixedInvites() => <SalonInvite>[
  SalonInvite(
    inviteId: 'inv-1-pending',
    recipientEmail: 'pending@beautica.ua',
    role: SalonStaffRole.master,
    status: InviteStatus.pending,
    createdAt: _kSentAt,
    expiresAt: _kExpiresAt,
  ),
  SalonInvite(
    inviteId: 'inv-2-cancelled',
    recipientEmail: 'cancelled@beautica.ua',
    role: SalonStaffRole.admin,
    status: InviteStatus.cancelled,
    createdAt: _kSentAt.subtract(const Duration(days: 1)),
    expiresAt: _kExpiresAt,
  ),
  SalonInvite(
    inviteId: 'inv-3-expired',
    recipientEmail: 'expired@beautica.ua',
    role: SalonStaffRole.master,
    status: InviteStatus.expired,
    createdAt: _kSentAt.subtract(const Duration(days: 2)),
    expiresAt: _kExpiresAt,
  ),
  SalonInvite(
    inviteId: 'inv-4-accepted',
    recipientEmail: 'accepted@beautica.ua',
    role: SalonStaffRole.admin,
    status: InviteStatus.accepted,
    createdAt: _kSentAt.subtract(const Duration(days: 3)),
    expiresAt: _kExpiresAt,
  ),
];

/// The mixed fixture's ids, in the order the server sent them.
const List<String> _kMixedOrder = <String>[
  'inv-1-pending',
  'inv-2-cancelled',
  'inv-3-expired',
  'inv-4-accepted',
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

Finder _cancelOf(String inviteId) => find.byKey(salonInviteCancelKey(inviteId));

void main() {
  group('list rendering', () {
    testWidgets('renders one row per invitation, each with its own email', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _invites(),
      );
      await _pump(tester, repo);

      expect(find.byType(SalonInviteRow), findsNWidgets(3));
      // Per-row identity: a row keyed to the wrong invite, or three copies of
      // one invite, fails here even though the count above would pass.
      for (final SalonInvite invite in _invites()) {
        expect(
          find.descendant(
            of: find.byKey(salonInviteRowKey(invite.inviteId)),
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
        salonInvites: _invites(),
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      expect(
        find.descendant(
          of: find.byKey(salonInviteRowKey('inv-b')),
          matching: find.text(l10n.inviteStaffRoleAdmin),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(salonInviteRowKey('inv-a')),
          matching: find.text(l10n.inviteStaffRoleMaster),
        ),
        findsOneWidget,
      );
    });
  });

  group('cancel', () {
    testWidgets('flips ONLY the tapped row to «Скасовано» and sends its own '
        'inviteId — the row STAYS in the history', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _invites(),
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(_cancelOf('inv-b'));
      await tester.pumpAndSettle();

      expect(repo.cancelInviteRequests, hasLength(1));
      expect(repo.cancelInviteRequests.single.salonId, _kSalonId);
      expect(repo.cancelInviteRequests.single.inviteId, 'inv-b');

      // This list is HISTORY: a cancelled invitation is a row that changed
      // state, never a row that disappeared. All three rows survive and the
      // header count is unchanged.
      expect(find.byKey(salonInviteRowKey('inv-b')), findsOneWidget);
      expect(find.byKey(salonInviteRowKey('inv-a')), findsOneWidget);
      expect(find.byKey(salonInviteRowKey('inv-c')), findsOneWidget);
      expect(find.byType(SalonInviteRow), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byKey(const Key('pending-invites-header')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );

      // The tapped row now reads «Скасовано» and offers no cancel; the
      // siblings are untouched and still cancellable.
      expect(
        find.descendant(
          of: find.byKey(salonInviteRowKey('inv-b')),
          matching: find.text(l10n.salonInvitesStatusCancelled),
        ),
        findsOneWidget,
      );
      expect(_cancelOf('inv-b'), findsNothing);
      expect(_cancelOf('inv-a'), findsOneWidget);
      expect(_cancelOf('inv-c'), findsOneWidget);
      expect(find.text(l10n.salonInvitesStatusCancelled), findsOneWidget);
    });

    testWidgets('cancelling the ONLY invitation leaves it on screen — the '
        'empty state is for a salon that never invited anyone', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: <SalonInvite>[_invites().first],
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(_cancelOf('inv-a'));
      await tester.pumpAndSettle();

      expect(find.byType(SalonInviteRow), findsOneWidget);
      expect(find.byKey(const Key('pending-invites-empty')), findsNothing);
      expect(find.text(l10n.salonInvitesStatusCancelled), findsOneWidget);
    });

    testWidgets('while in flight the tapped row spins, the siblings do not, '
        'and a second tap issues no second call', (tester) async {
      final gate = Completer<void>();
      final repo = FakeSalonRepository(salon: _kSalon, salonInvites: _invites())
        ..cancelInviteGate = gate;
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(_cancelOf('inv-b'));
      // One frame — enough for the notifier's optimistic `cancelling` write to
      // reach the tree, not enough for the (gated) request to resolve.
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(salonInviteRowKey('inv-b')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason: 'the busy row swaps its label for an in-row spinner',
      );
      expect(
        find.descendant(
          of: find.byKey(salonInviteRowKey('inv-b')),
          matching: find.text(l10n.salonPendingInvitesCancelCta),
        ),
        findsNothing,
      );
      // Siblings are untouched — the busy state is per row, not per screen.
      expect(
        find.descendant(
          of: find.byKey(salonInviteRowKey('inv-a')),
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
      // The row settles into its cancelled state rather than vanishing, and
      // the spinner goes with the cancel action that hosted it.
      expect(find.byKey(salonInviteRowKey('inv-b')), findsOneWidget);
      expect(_cancelOf('inv-b'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a FAILED cancel restores nothing — the row stays, its error '
        'chip appears, and the list is still rendered', (tester) async {
      final repo = FakeSalonRepository(salon: _kSalon, salonInvites: _invites())
        ..cancelInviteError = const ServerFailure(statusCode: 500);
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(_cancelOf('inv-b'));
      await tester.pumpAndSettle();

      expect(find.byKey(salonInviteRowKey('inv-b')), findsOneWidget);
      expect(find.byType(SalonInviteRow), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byKey(salonInviteRowKey('inv-b')),
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

    testWidgets('retrying after a failure clears the chip and flips the row', (
      tester,
    ) async {
      final repo = FakeSalonRepository(salon: _kSalon, salonInvites: _invites())
        ..cancelInviteError = const ServerFailure(statusCode: 500);
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(_cancelOf('inv-b'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.salonPendingInvitesCancelError), findsOneWidget);

      repo.cancelInviteError = null;
      await tester.tap(_cancelOf('inv-b'));
      await tester.pumpAndSettle();

      expect(repo.cancelInviteRequests, hasLength(2));
      expect(find.byKey(salonInviteRowKey('inv-b')), findsOneWidget);
      expect(_cancelOf('inv-b'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(salonInviteRowKey('inv-b')),
          matching: find.text(l10n.salonInvitesStatusCancelled),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.salonPendingInvitesCancelError), findsNothing);
    });
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
      expect(find.byType(SalonInviteRow), findsNothing);
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
      final repo = FakeSalonRepository(salon: _kSalon, salonInvites: _invites())
        ..listSalonInvitesError = const ServerFailure(statusCode: 500);
      // `retry: null` — the production retry policy would re-issue the failed
      // fetch on a timer and make `listSalonInvitesCalls` non-deterministic.
      await _pump(tester, repo, retry: (_, _) => null);

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.byType(SalonInviteRow), findsNothing);
      expect(repo.listSalonInvitesCalls, 1);

      repo.listSalonInvitesError = null;
      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(repo.listSalonInvitesCalls, 2);
      expect(find.byType(ErrorState), findsNothing);
      expect(find.byType(SalonInviteRow), findsNWidgets(3));
    });
  });

  group('invite CTA', () {
    testWidgets('pushes the invite-staff route with THIS salonId', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _invites(),
      );
      await _pump(tester, repo);

      await tester.tap(find.byKey(const Key('pending-invites-invite-cta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stub-invite-$_kSalonId')), findsOneWidget);
    });
  });

  // ── Mixed-status history (mobile-security MEDIUM, 2026-09-02) ────────────
  //
  // Every fixture in this file was `status: pending` until now, so the screen
  // had NEVER been rendered with a terminal row in it. These four tests are
  // the screen-level half of that gap; the per-row rendering contract lives
  // in `presentation/widgets/salon_invite_row_test.dart`.
  group('mixed-status history', () {
    testWidgets('four rows, one per status, render four DISTINCT status '
        'labels', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _mixedInvites(),
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      expect(find.byType(SalonInviteRow), findsNWidgets(4));

      // Each label appears EXACTLY once, and on ITS OWN row — a screen that
      // rendered one status four times would still show four chips.
      final Map<String, String> expected = <String, String>{
        'inv-1-pending': l10n.salonInvitesStatusPending,
        'inv-2-cancelled': l10n.salonInvitesStatusCancelled,
        'inv-3-expired': l10n.salonInvitesStatusExpired,
        'inv-4-accepted': l10n.salonInvitesStatusAccepted,
      };
      expected.forEach((String id, String label) {
        expect(
          find.descendant(
            of: find.byKey(salonInviteRowKey(id)),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: 'row $id must carry its own status label',
        );
        expect(find.text(label), findsOneWidget);
      });
      // The four labels really are four different strings — if the ARB ever
      // collapsed two of them the assertions above would still pass.
      expect(expected.values.toSet(), hasLength(4));
    });

    testWidgets('rows appear in FIXTURE order — no client-side re-sort', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _mixedInvites(),
      );
      await _pump(tester, repo);

      // Vertical position, read off the laid-out tree rather than the
      // element order, so a reordering that a `findsNWidgets` count would
      // miss is caught.
      final List<String> onScreen = <String>[..._kMixedOrder]
        ..sort(
          (String a, String b) => tester
              .getTopLeft(find.byKey(salonInviteRowKey(a)))
              .dy
              .compareTo(
                tester.getTopLeft(find.byKey(salonInviteRowKey(b))).dy,
              ),
        );

      expect(
        onScreen,
        _kMixedOrder,
        reason:
            'the server sorts createdAt DESC; a defensive client re-sort '
            'would hide an ordering regression behind a green screen',
      );
    });

    testWidgets('exactly ONE cancel affordance across the whole screen when '
        'only one row is pending', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _mixedInvites(),
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      expect(_cancelOf('inv-1-pending'), findsOneWidget);
      for (final String id in <String>[
        'inv-2-cancelled',
        'inv-3-expired',
        'inv-4-accepted',
      ]) {
        expect(
          _cancelOf(id),
          findsNothing,
          reason: 'DELETE .../invites/$id would 404 — never offer it',
        );
      }
      // Screen-wide, not just per row: exactly one «Скасувати» is rendered.
      expect(
        find.text(l10n.salonPendingInvitesCancelCta),
        findsOneWidget,
        reason:
            'three of the four rows are terminal — one cancel label is the '
            'whole screen\'s budget',
      );
    });
  });

  group('truncation note', () {
    testWidgets('truncated == true renders the «Показано 200 останніх '
        'запрошень» note AFTER the list', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _mixedInvites(),
        salonInvitesTruncated: true,
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      final Finder note = find.byKey(
        const Key('pending-invites-truncated-note'),
      );
      expect(note, findsOneWidget);
      expect(find.text(l10n.salonInvitesTruncatedNote), findsOneWidget);
      // A FOOTNOTE about what is below, not a warning above the list.
      expect(
        tester.getTopLeft(note).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(salonInviteRowKey('inv-4-accepted'))).dy,
        ),
      );
    });

    testWidgets('truncated == false renders NO note — a complete list must '
        'not claim to be capped', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _mixedInvites(),
      );
      await _pump(tester, repo);
      final AppLocalizations l10n = _l10n(tester);

      expect(
        find.byKey(const Key('pending-invites-truncated-note')),
        findsNothing,
      );
      expect(find.text(l10n.salonInvitesTruncatedNote), findsNothing);
      // The list itself is unaffected.
      expect(find.byType(SalonInviteRow), findsNWidgets(4));
    });
  });
}
