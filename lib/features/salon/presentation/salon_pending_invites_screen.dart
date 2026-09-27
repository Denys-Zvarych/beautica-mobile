// «Надіслані запрошення»: the salon's outbound staff-invitation HISTORY —
// every invitation the owner/admin has ever sent, newest first, each carrying
// the status it ended up in (очікує / прийнято / термін минув / скасовано).
//
// This screen started as a PENDING-ONLY list. It was widened to full history
// because a pending-only list answered the wrong question: an invitation that
// was accepted, expired or revoked simply vanished, so «я вже запрошував цю
// людину?» had no answer anywhere in the app and a re-invite was the only way
// to find out. Both SALON_OWNER and SALON_ADMIN see the full list (a locked
// product decision — there is no role-based filtering here).
//
// Reached from the Phase 21.9 salon settings hub's «Надіслані запрошення»
// row (owner AND admin — the row sits outside that hub's owner-only block),
// which shipped as a deliberate no-op placeholder until this phase.
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// salon_pending_invites_screen.dart` — ported literally: a section header
// carrying the count, a column of [SalonInviteRow]s,
// and a «Запросити в команду» CTA. Two substitutions, both the house pattern
// every sibling salon screen already made for its own preview source:
//
//   * the preview's bespoke `_TopBar` → the shared [SectionScaffold] (same
//     substitution `RegisterSalonScreen` / `SalonProfileEditScreen` /
//     `InviteStaffScreen` made);
//   * the preview's decorative salon logo + name subheading is NOT ported —
//     this screen receives only a `salonId`, and fetching a whole [Salon]
//     to render one caption is the same call-out `SalonSettingsScreen`
//     already documents for its own copy of that row.
//
// The preview keeps its CTA at the BOTTOM OF THE SCROLLING COLUMN in the
// populated branch. Production pins it in [SectionScaffold.footer] instead,
// so it stays reachable with a long invite list — the same treatment every
// other production form gives its primary action, and the reason
// [SectionScaffold] has a footer slot at all.
//
// GAPS THE PREVIEW DID NOT COVER (it is a static, always-loaded mock):
//   * loading → three shimmer rows built from the SHARED
//     [SkeletonShimmerScope] / [SkeletonBlock], laid out on the invite row's
//     own silhouette (glyph circle + two text bars + action bar) inside the
//     same [NeumorphicInset] geometry, so resolving the list causes no
//     layout jump;
//   * error → the shared [ErrorState] + retry, the single error voice every
//     other `AsyncValue` branch in the app uses;
//   * the in-flight and failed cancel states, which live on
//     [SalonInviteRow] itself (spinner / error chip) rather than on this
//     screen — see `salon_invites_notifier.dart` for why a per-row cancel
//     must never become a top-level `AsyncLoading`/`AsyncError`;
//   * the truncation note, which the preview had no concept of: the server
//     caps the history at its 200 most recent rows, and a silently short list
//     would read as "this is everything".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/section_header.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../master/presentation/widgets/section_scaffold.dart';
import '../application/salon_invites_notifier.dart';
import '../domain/salon_invite.dart';
import 'widgets/salon_invite_row.dart';

/// The owner/admin's history of sent staff invitations for [salonId].
class SalonPendingInvitesScreen extends ConsumerWidget {
  const SalonPendingInvitesScreen({super.key, required this.salonId});

  /// Backend Salon-row UUID whose invitations are listed.
  final String salonId;

  void _openInvite(BuildContext context) {
    context.push(RouteNames.salonInviteStaff(salonId));
  }

  void _onBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.salonManageSettings(salonId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // NARROWED, never a bare whole-state watch (mobile-perf MEDIUM; the
    // guidance backlog row 335 records for the schedule hub applies verbatim
    // here). A cancel emits TWICE — once entering `cancelling`, once from
    // `_settle` — and each emission changes only two id sets. Watching the
    // whole state rebuilt this screen both times, which rebuilt the
    // `SliverList` delegate, which rebuilt every visible row: 2xN row builds
    // for a one-row operation. [_viewOf] projects the emission down to the
    // pieces THIS widget draws (the branch, the row list, the truncation
    // flag); the per-row flags are watched one level down by [_InviteRowSlot].
    // The notifier deliberately carries the SAME `invites` instance through
    // every emission that does not change the rows, so the record below
    // compares equal and Riverpod skips the rebuild entirely.
    final _InvitesView view = ref.watch(
      salonInvitesProvider(salonId).select(_viewOf),
    );
    final List<SalonInvite>? invites = view.invites;
    final Object? error = view.error;

    return SectionScaffold(
      // Reuses the settings-hub row's own label rather than adding a second
      // ARB key holding the identical string — the row and the page it opens
      // are the same noun by design.
      title: l10n.salonSettingsSentInvites,
      backSemanticLabel: l10n.salonPendingInvitesBackSemanticLabel,
      backKey: const Key('btn-back-pending-invites'),
      onBack: () => _onBack(context),
      footer: NeumorphicButton(
        key: const Key('pending-invites-invite-cta'),
        label: l10n.salonPendingInvitesInviteCta,
        icon: Icons.group_add_rounded,
        onPressed: () => _openInvite(context),
      ),
      // SLIVERS, not `body` — this is the surface that made
      // `SectionScaffold.slivers` exist (mobile-perf HIGH, backlog row 739).
      // The list is capped at 200 SERVER-side, not by a 48h pending window
      // any more, and an eager `Column` of 200 rows built ~15k elements, ~600
      // `RepaintBoundary`s and ~600 `AnimationController`s in the entry frame.
      // Only the visible rows are built now.
      //
      // The branch itself is still decided by `AsyncValue.when` — inside
      // [_viewOf], with the identical arguments this call site used, so the
      // narrowing above changed WHERE the branch is chosen and nothing about
      // HOW. In particular `.when`'s `skipLoadingOnRefresh` default still
      // keeps the resolved list on screen through a refetch instead of
      // flashing the skeleton, and the error branch is still the concrete
      // `error:` case rather than a `hasError` test (which
      // `AsyncLoading(retrying: true)` also satisfies mid-refetch).
      slivers: invites != null
          ? _inviteSlivers(
              l10n: l10n,
              salonId: salonId,
              invites: invites,
              truncated: view.truncated,
            )
          : error != null
          ? <Widget>[
              SliverToBoxAdapter(
                child: ErrorState(
                  failure: error is Failure
                      ? error
                      : UnknownFailure(cause: error),
                  onRetry: () => ref.invalidate(salonInvitesProvider(salonId)),
                ),
              ),
            ]
          : const <Widget>[
              SliverToBoxAdapter(child: _PendingInvitesSkeleton()),
            ],
    );
  }
}

/// What [SalonPendingInvitesScreen.build] actually draws, projected out of the
/// provider's full [SalonInvitesState] so the per-row cancel bookkeeping —
/// the only part of that state a cancel touches — is NOT in this widget's
/// rebuild condition.
///
/// Exactly one of [invites] / [error] is non-null on a resolved emission;
/// both are null while the first load is in flight. [truncated] is only
/// meaningful alongside a non-null [invites].
typedef _InvitesView = ({
  List<SalonInvite>? invites,
  bool truncated,
  Object? error,
});

/// The projection [SalonPendingInvitesScreen] selects on.
///
/// Deliberately implemented ON TOP OF `AsyncValue.when` with the screen's own
/// arguments rather than a hand-rolled `hasValue`/`hasError` ladder: the
/// branch semantics (`skipLoadingOnRefresh`, error-over-stale-value) then
/// cannot drift from what the screen rendered before the narrowing, because
/// they are literally the same call.
///
/// The returned record compares by value, and its [invites] field compares by
/// LIST IDENTITY — which is exactly the contract
/// `salon_invites_notifier.dart` documents and upholds: a cancel starting, a
/// cancel failing, and a cancel succeeding-without-changing-the-rows all
/// carry the previous `invites` instance through, so this projection is
/// unchanged and the screen does not rebuild.
_InvitesView _viewOf(AsyncValue<SalonInvitesState> async) => async.when(
  loading: () => const (invites: null, truncated: false, error: null),
  error: (Object e, _) => (invites: null, truncated: false, error: e),
  data: (SalonInvitesState s) =>
      (invites: s.invites, truncated: s.truncated, error: null),
);

/// One row, subscribed to ITS OWN cancel bookkeeping and nothing else.
///
/// The row's `invite` arrives from the parent (a status flip DOES change the
/// list instance, so the parent rebuilds and hands the new value down), while
/// [SalonInvitesState.cancelling] / [SalonInvitesState.failed] are watched
/// here through a `select` scoped to this invite's id. A cancel therefore
/// rebuilds one row instead of every visible one.
///
/// The `select` reads `state.value` WITHOUT treating null as "no row": an
/// `invalidate` retains `.value` (recorded gotcha in this repo), so the flags
/// carry across a refetch exactly as the rows they annotate do. Null here
/// means "nothing has loaded yet", in which case no row is on screen anyway.
///
/// Keyed with a plain [ValueKey] on the invite id, NOT [salonInviteRowKey] —
/// that key stays on [SalonInviteRow] itself (its own `assert` requires it,
/// and the widget tests match it exactly once). This wrapper still needs a
/// key of its own so a list edit matches slots by invite rather than by
/// index, which is the same reasoning `salonInviteRowKey`'s doc gives.
class _InviteRowSlot extends ConsumerWidget {
  const _InviteRowSlot({
    super.key,
    required this.salonId,
    required this.invite,
  });

  final String salonId;
  final SalonInvite invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String inviteId = invite.inviteId;
    final ({bool cancelling, bool failed}) row = ref.watch(
      salonInvitesProvider(salonId).select((AsyncValue<SalonInvitesState> v) {
        final SalonInvitesState? s = v.value;
        return (
          cancelling: s?.cancelling.contains(inviteId) ?? false,
          failed: s?.failed.contains(inviteId) ?? false,
        );
      }),
    );
    return SalonInviteRow(
      // Keyed at the CALL SITE, not inside the row — a keyless child is
      // matched by index, so a mid-list cancel would deactivate and
      // re-inflate every trailing row instead of updating it. See
      // `salonInviteRowKey`'s own doc.
      key: salonInviteRowKey(inviteId),
      invite: invite,
      cancelling: row.cancelling,
      failed: row.failed,
      onCancel: () => ref
          .read(salonInvitesProvider(salonId).notifier)
          .cancelInvite(inviteId),
    );
  }
}

/// The resolved list as slivers — the count header, one lazily built
/// [SalonInviteRow] per invitation (server order, newest first, never
/// re-sorted here), and the truncation footnote — or the empty state when the
/// salon has never invited anyone.
///
/// A top-level function rather than a widget: the pieces must be SIBLING
/// slivers of the scaffold's own viewport, and a widget returning them would
/// have to be a sliver itself (i.e. a group), which is the nesting this
/// replaced.
///
/// The separator between rows lives INSIDE each row's own padding (top gap on
/// every row but the first) rather than as interleaved `SizedBox` children:
/// [SliverList.separated] would build a separator element per gap, and the gap
/// is a fixed inset, not content.
List<Widget> _inviteSlivers({
  required AppLocalizations l10n,
  required String salonId,
  required List<SalonInvite> invites,
  required bool truncated,
}) {
  if (invites.isEmpty) {
    return const <Widget>[
      SliverToBoxAdapter(child: _PendingInvitesEmptyState()),
    ];
  }

  return <Widget>[
    SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            key: const Key('pending-invites-header'),
            title: l10n.salonPendingInvitesSectionLabel,
            titleStyle: VelvetText.sectionLabel(),
            trailing: Text(
              '${invites.length}',
              // raw-ui-string-ok: an interpolated count, not translatable copy.
              style: VelvetText.feedbackMutedSm,
            ),
          ),
          const SizedBox(height: VelvetSpacing.sm + 2),
        ],
      ),
    ),
    SliverList.builder(
      itemCount: invites.length,
      itemBuilder: (BuildContext context, int i) {
        final SalonInvite invite = invites[i];
        return Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : VelvetSpacing.sm + 2),
          child: _InviteRowSlot(
            key: ValueKey<String>(invite.inviteId),
            salonId: salonId,
            invite: invite,
          ),
        );
      },
    ),
    // The server cut older rows to stay under its cap. Said quietly and
    // AFTER the list, where it reads as a footnote about what is below
    // rather than a warning about what is above — the 200 rows on screen
    // are all real and all current.
    if (truncated)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: VelvetSpacing.md),
          child: Text(
            key: const Key('pending-invites-truncated-note'),
            l10n.salonInvitesTruncatedNote,
            style: VelvetText.feedbackMutedSm,
            textAlign: TextAlign.center,
          ),
        ),
      ),
  ];
}

/// Nothing outstanding — a quiet inset card explaining when a row will
/// appear here. Ported from the preview's own `_PendingEmptyState`, minus its
/// inline CTA: the CTA is pinned in the scaffold footer on this screen and is
/// therefore already on screen.
class _PendingInvitesEmptyState extends StatelessWidget {
  const _PendingInvitesEmptyState();

  static const double _glyphExtent = 52;

  // Hoisted — `withValues` allocates a Color, so never call it in build().
  static final BoxDecoration _glyphDecoration = BoxDecoration(
    shape: BoxShape.circle,
    color: BrandColors.accent.withValues(alpha: 0.14),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return NeumorphicInset(
      key: const Key('pending-invites-empty'),
      radius: VelvetRadii.card,
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.lg),
        child: Column(
          children: <Widget>[
            Container(
              height: _glyphExtent,
              width: _glyphExtent,
              decoration: _glyphDecoration,
              child: const Icon(
                Icons.mark_email_read_outlined,
                size: 24,
                color: BrandColors.accentDeep,
              ),
            ),
            const SizedBox(height: VelvetSpacing.md),
            Text(
              l10n.salonPendingInvitesEmptyTitle,
              style: VelvetText.subheadingWizard15,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.xs),
            Text(
              l10n.salonPendingInvitesEmptyBody,
              style: VelvetText.feedbackMutedSm,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Three placeholder rows on the real row's silhouette — same well geometry,
/// same glyph circle, same two-line text stack, so the list resolves without
/// a layout jump.
class _PendingInvitesSkeleton extends StatelessWidget {
  const _PendingInvitesSkeleton();

  static const int _rowCount = 3;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBlock(width: 150, height: 12),
          ),
          const SizedBox(height: VelvetSpacing.sm + 2),
          for (int i = 0; i < _rowCount; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: VelvetSpacing.sm + 2),
            const _SkeletonInviteRow(),
          ],
        ],
      ),
    );
  }
}

class _SkeletonInviteRow extends StatelessWidget {
  const _SkeletonInviteRow();

  @override
  Widget build(BuildContext context) {
    return const NeumorphicInset(
      radius: VelvetRadii.card,
      child: Padding(
        padding: EdgeInsets.all(VelvetSpacing.md - 2),
        child: Row(
          children: <Widget>[
            SkeletonBlock(width: 40, height: 40, circle: true),
            SizedBox(width: VelvetSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SkeletonBlock(width: 160, height: 13),
                  SizedBox(height: VelvetSpacing.xs + 1),
                  SkeletonBlock(width: 110, height: 11),
                ],
              ),
            ),
            SizedBox(width: VelvetSpacing.xs),
            SkeletonBlock(width: 58, height: 12),
          ],
        ),
      ),
    );
  }
}
