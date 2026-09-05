// Widget tests for [SalonInviteRow] — the shared invite-history row rendered
// by BOTH `SalonPendingInvitesScreen` (full history) and `InviteStaffScreen`
// (pending-only block).
//
// WHY THIS FILE EXISTS
// --------------------
// Two gaps, both raised as findings and both invisible to every other test in
// the suite:
//
//   1. mobile-security MEDIUM (2026-09-02) — the HOSTILE-STATUS defence had
//      ZERO coverage. `grep -a -rn "InviteStatus.accepted\|InviteStatus
//      .expired\|InviteStatus.unknown" test/ integration_test/` returned 0
//      hits: every screen fixture in the suite was `status: pending`. The
//      contract that a NON-PENDING row renders no cancel affordance — and that
//      an UNRECOGNISED status renders no status chip at all rather than
//      mislabelling itself — was correct in `salon_invite_row.dart` and
//      guarded by nothing. `DELETE .../invites/{inviteId}` 404s for every
//      non-pending invite, so a regression that re-exposed the action would
//      hand the owner a button that can only fail.
//
//   2. The TRUNCATION FIX. `salon_invite_row.dart`'s own header documents the
//      reported "text is cut" defect and the three-part layout fix (email may
//      wrap to 2 lines; the chips sit in a `Wrap`; the caption gets its OWN
//      full-width line instead of being the sole shock absorber under a role
//      chip). `salon_pending_invites_screen_test.dart:63-64` names THIS FILE
//      as the home for that coverage — and this file did not exist.
//
// HOW THE TRUNCATION GUARD AVOIDS BEING VACUOUS
// ---------------------------------------------
// It asserts `RenderParagraph.didExceedMaxLines == false` — the render-layer
// ground truth, read AFTER layout at a pinned 320dp surface. It deliberately
// does NOT assert `maxLines == 2` on the widget: reading a constructor field
// proves the field's value and never exercises layout, so it would stay green
// against every layout that squeezes the text (recorded rule in this repo:
// "widget-field assertions are vacuous").
//
// MUTATION-PROBED 2026-09-02, both halves independently:
//   * email:   `maxLines: 2` -> `maxLines: 1` in `salon_invite_row.dart:215`
//              turns `email fits without truncation` RED
//              (`didExceedMaxLines: true`).
//   * caption: restoring the PRE-FIX layout — role chip + `_SentAgoCaption`
//              back on ONE `Row` with the caption the only `Flexible`, the
//              exact shape the header describes — turns `caption fits without
//              truncation` RED (`didExceedMaxLines: true`) at the same 320dp
//              width with the longest role label.
// Both were restored immediately after; the exact observed failures are in
// the QA report.
//
// CLOCK COHERENCE (recorded invariant M15): the row's «надіслано …» caption
// runs through `formatRelativeDate`, whose `now` defaults to the HOST clock
// and which this widget deliberately does not inject a `clockProvider` into
// (see `_SentAgoCaption`'s doc / phase-284 D2). So the fixture's `createdAt`
// is built from `DateTime.now()` — BOTH sides live, never mixed — and the
// expected caption is computed with the SAME function the widget calls.
//
// Finders are Keys, semantics labels, and l10n-resolved strings — never
// Cyrillic literals (`forbid_cyrillic_finder.sh`). Layer: Widget.

import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/salon/domain/invite_status.dart';
import 'package:beautica_mobile/features/salon/domain/salon_invite.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_invite_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/relative_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

const String _kInviteId = 'inv-row-1';

/// A 42-character address — long enough that the pre-fix single-line email
/// could not fit beside the «Скасувати» action at 320dp.
const String _kLongEmail = 'nadiya.oleksandrivna.kovalenko@beautica.ua';

const String _kShortEmail = 'anna@beautica.ua';

/// Host-clock fixture — see the header on clock coherence. Three days back
/// keeps `formatRelativeDate` in a stable bucket for the whole test run.
final DateTime _kSentAt = DateTime.now().subtract(const Duration(days: 3));
final DateTime _kExpiresAt = _kSentAt.add(const Duration(hours: 48));

SalonInvite _invite({
  required InviteStatus status,
  String email = _kShortEmail,
  SalonStaffRole role = SalonStaffRole.master,
}) => SalonInvite(
  inviteId: _kInviteId,
  recipientEmail: email,
  role: role,
  status: status,
  createdAt: _kSentAt,
  expiresAt: _kExpiresAt,
);

/// Runs [body] with the semantics tree COMPILED, disposing the handle even
/// when an assertion inside [body] throws.
///
/// LOAD-BEARING, not boilerplate: `find.bySemanticsLabel` matches against the
/// compiled semantics tree, which `flutter_test` does not build unless a
/// handle is held. Without it, EVERY `bySemanticsLabel` assertion in this
/// file — including the `findsNothing` ones that are the whole point of the
/// hostile-status group — passes VACUOUSLY, because nothing is ever found.
/// Caught exactly that way on the first run of this file: the single
/// `findsOneWidget` semantics assertion went red while its `findsNothing`
/// siblings stayed green. That asymmetry is the proof the negative
/// assertions below are now load-bearing rather than decorative.
///
/// `addTearDown` cannot be used for the dispose: `flutter_test` runs its
/// end-of-test semantics-handle verification BEFORE the registered teardowns,
/// so the handle must be released inside the test body.
void semanticsWidgetTest(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  });
}

/// Pumps ONE row at [width] logical px.
///
/// 320 is the narrowest phone the app targets and the width at which the
/// reported truncation defect reproduced.
Future<void> _pumpRow(
  WidgetTester tester,
  SalonInvite invite, {
  double width = 320,
  VoidCallback? onCancel,
}) async {
  await tester.pumpApp(
    Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SalonInviteRow(
          key: salonInviteRowKey(invite.inviteId),
          invite: invite,
          onCancel: onCancel ?? () {},
        ),
      ),
    ),
    width: width,
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(SalonInviteRow)));

Finder get _cancel => find.byKey(salonInviteCancelKey(_kInviteId));

/// Finds the CANCEL action's semantics node by its accessibility label.
///
/// A `RegExp`, not an exact string, because `_CancelAction`'s
/// `Semantics(label: …)` node MERGES its child «Скасувати» `Text` label into
/// its own — the compiled node reads
/// `"Скасувати запрошення для <email>\nСкасувати"`. Verified by dumping the
/// live semantics tree (2026-09-02); an exact-string finder silently matched
/// nothing, which would have made every `findsNothing` below vacuous.
Finder _cancelSemantics(AppLocalizations l10n, String email) =>
    find.bySemanticsLabel(
      RegExp(RegExp.escape(l10n.salonPendingInvitesCancelSemanticLabel(email))),
    );

/// The render-layer truth about whether [finder]'s paragraph was clipped.
bool _overflowed(WidgetTester tester, Finder finder) =>
    tester.renderObject<RenderParagraph>(finder).didExceedMaxLines;

/// Every status label the row can render, so an "absent chip" assertion cannot
/// be satisfied by the label simply having changed.
List<String> _allStatusLabels(AppLocalizations l10n) => <String>[
  l10n.salonInvitesStatusPending,
  l10n.salonInvitesStatusAccepted,
  l10n.salonInvitesStatusExpired,
  l10n.salonInvitesStatusCancelled,
];

void main() {
  group('truncation guard (the reported «text is cut» fix)', () {
    semanticsWidgetTest(
      'a 42-char address wraps instead of being clipped, and the '
      '«надіслано …» caption is NOT truncated — narrowest phone, longest '
      'role label, cancel action present',
      (tester) async {
        // The worst case for the EMAIL line: pending (so «Скасувати» occupies
        // the same row) + the longest role label + a status chip beside it.
        await _pumpRow(
          tester,
          _invite(
            status: InviteStatus.pending,
            email: _kLongEmail,
            role: SalonStaffRole.admin,
          ),
        );
        final AppLocalizations l10n = _l10n(tester);

        // The cancel action really IS on screen — without this the email would
        // have the full width and the assertion below would be trivially true.
        expect(_cancel, findsOneWidget);

        expect(
          _overflowed(tester, find.text(_kLongEmail)),
          isFalse,
          reason:
              'the address must wrap to a second line, not ellipsise — '
              'maxLines: 1 on this Text is the pre-fix defect',
        );

        final String caption = l10n.salonPendingInvitesSentAgo(
          formatRelativeDate(l10n, _kSentAt),
        );
        expect(
          _overflowed(tester, find.text(caption)),
          isFalse,
          reason:
              'the caption owns its own full-width line — putting it back on '
              'the role-chip Row (the pre-fix layout) squeezes it into an '
              'ellipsis',
        );
      },
    );

    semanticsWidgetTest(
      'the longest role + status label pair still renders both '
      'chips un-truncated at 320dp',
      (tester) async {
        // The worst case for the CHIP RUN: «Адміністратор» + «Термін минув».
        // A terminal status, so no cancel action competes for width — this
        // probes the `Wrap`, not the email line.
        await _pumpRow(
          tester,
          _invite(
            status: InviteStatus.expired,
            email: _kLongEmail,
            role: SalonStaffRole.admin,
          ),
        );
        final AppLocalizations l10n = _l10n(tester);

        expect(
          _overflowed(tester, find.text(l10n.inviteStaffRoleAdmin)),
          isFalse,
          reason:
              'the role chip flows onto a second Wrap run, never compresses',
        );
        expect(
          _overflowed(tester, find.text(l10n.salonInvitesStatusExpired)),
          isFalse,
        );
        expect(_overflowed(tester, find.text(_kLongEmail)), isFalse);
        final String caption = l10n.salonPendingInvitesSentAgo(
          formatRelativeDate(l10n, _kSentAt),
        );
        expect(_overflowed(tester, find.text(caption)), isFalse);
      },
    );
  });

  group('hostile / terminal statuses render no cancel affordance', () {
    // One test per terminal status. The action must be ABSENT from the tree —
    // not rendered-and-disabled — because `_CancelAction` is a
    // `Semantics(button:)` node: a disabled one is still announced and
    // focusable for a request the backend 404s.
    for (final (InviteStatus status, String name) in <(InviteStatus, String)>[
      (InviteStatus.accepted, 'accepted'),
      (InviteStatus.expired, 'expired'),
      (InviteStatus.cancelled, 'cancelled'),
    ]) {
      semanticsWidgetTest(
        '$name renders its status chip and NO cancel — neither the '
        'key nor the semantics node exists',
        (tester) async {
          bool cancelled = false;
          await _pumpRow(
            tester,
            _invite(status: status),
            onCancel: () => cancelled = true,
          );
          final AppLocalizations l10n = _l10n(tester);

          final String label = switch (status) {
            InviteStatus.accepted => l10n.salonInvitesStatusAccepted,
            InviteStatus.expired => l10n.salonInvitesStatusExpired,
            InviteStatus.cancelled => l10n.salonInvitesStatusCancelled,
            _ => throw StateError('unreachable'),
          };

          // The chip IS there, correctly labelled and announced as a status.
          expect(find.text(label), findsOneWidget);
          expect(
            find.bySemanticsLabel(l10n.salonInvitesStatusSemanticLabel(label)),
            findsOneWidget,
          );
          // Role chip + status chip — the status pill is a tinted `RoleChip`,
          // never a private fork.
          expect(find.byType(RoleChip), findsNWidgets(2));

          // The cancel affordance is GONE from both the widget tree and the
          // semantics tree.
          expect(_cancel, findsNothing);
          expect(
            _cancelSemantics(l10n, _kShortEmail),
            findsNothing,
            reason:
                'a disabled-but-present Semantics(button:) node would still be '
                'announced and focusable — the action must not exist at all',
          );
          expect(find.text(l10n.salonPendingInvitesCancelCta), findsNothing);
          expect(find.byType(GestureDetector), findsNothing);
          expect(cancelled, isFalse);
        },
      );
    }

    semanticsWidgetTest('unknown renders NO status chip and NO cancel — an '
        'unrecognised state is never labelled or actioned', (tester) async {
      await _pumpRow(tester, _invite(status: InviteStatus.unknown));
      final AppLocalizations l10n = _l10n(tester);

      // Exactly one chip: the ROLE. No status pill at all.
      expect(find.byType(RoleChip), findsOneWidget);
      expect(find.text(l10n.inviteStaffRoleMaster), findsOneWidget);
      for (final String label in _allStatusLabels(l10n)) {
        expect(
          find.text(label),
          findsNothing,
          reason: 'unknown must not borrow any recognised status label',
        );
        expect(
          find.bySemanticsLabel(l10n.salonInvitesStatusSemanticLabel(label)),
          findsNothing,
        );
      }
      // …and an empty-labelled placeholder pill is equally forbidden.
      expect(
        find.bySemanticsLabel(l10n.salonInvitesStatusSemanticLabel('')),
        findsNothing,
      );

      expect(_cancel, findsNothing);
      expect(_cancelSemantics(l10n, _kShortEmail), findsNothing);
    });
  });

  group('pending is the ONLY cancellable state', () {
    semanticsWidgetTest(
      'renders the «Скасувати» affordance, its semantics node, and '
      'the «Очікує» chip — and the tap reaches onCancel',
      (tester) async {
        int taps = 0;
        await _pumpRow(
          tester,
          _invite(status: InviteStatus.pending),
          onCancel: () => taps++,
        );
        final AppLocalizations l10n = _l10n(tester);

        expect(_cancel, findsOneWidget);
        expect(_cancelSemantics(l10n, _kShortEmail), findsOneWidget);
        expect(find.text(l10n.salonInvitesStatusPending), findsOneWidget);
        expect(find.byType(RoleChip), findsNWidgets(2));

        await tester.tap(_cancel);
        await tester.pump();
        expect(taps, 1);
      },
    );

    semanticsWidgetTest(
      'while cancelling, the row swaps the label for a spinner and '
      'ignores taps',
      (tester) async {
        int taps = 0;
        await tester.pumpApp(
          Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SalonInviteRow(
                key: salonInviteRowKey(_kInviteId),
                invite: _invite(status: InviteStatus.pending),
                cancelling: true,
                onCancel: () => taps++,
              ),
            ),
          ),
          width: 320,
        );
        await tester.pump();
        final AppLocalizations l10n = _l10n(tester);

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text(l10n.salonPendingInvitesCancelCta), findsNothing);

        await tester.tap(_cancel, warnIfMissed: false);
        await tester.pump();
        expect(taps, 0);
      },
    );
  });
}
