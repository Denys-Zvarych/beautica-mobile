// Phase 21.11 — «Надіслані запрошення»: the outbound staff invitations the
// owner/admin has sent and that are still awaiting acceptance.
//
// Reached from the Phase 21.9 salon settings hub's «Надіслані запрошення»
// row (owner AND admin — the row sits outside that hub's owner-only block),
// which shipped as a deliberate no-op placeholder until this phase.
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// salon_pending_invites_screen.dart` — ported literally: a «Очікують
// підтвердження» header carrying the count, a column of [PendingInviteRow]s,
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
//     [PendingInviteRow] itself (spinner / error chip) rather than on this
//     screen — see `pending_invites_notifier.dart` for why a per-row cancel
//     must never become a top-level `AsyncLoading`/`AsyncError`.

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
import '../application/pending_invites_notifier.dart';
import '../domain/pending_invite.dart';
import 'widgets/pending_invite_row.dart';

/// The owner/admin's list of sent-but-unaccepted staff invitations for
/// [salonId].
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
    final AsyncValue<PendingInvitesState> async = ref.watch(
      pendingInvitesProvider(salonId),
    );

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
      // Deliberately `.when` on the CONCRETE branch shape rather than a
      // `hasError` test: `AsyncLoading(retrying: true)` satisfies `hasError`
      // while the list is being refetched, and gating the error branch on it
      // would flash the error screen over a perfectly healthy retry.
      body: async.when(
        loading: () => const _PendingInvitesSkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () => ref.invalidate(pendingInvitesProvider(salonId)),
        ),
        data: (PendingInvitesState data) => _PendingInvitesBody(
          state: data,
          onCancel: (String inviteId) => ref
              .read(pendingInvitesProvider(salonId).notifier)
              .cancelInvite(inviteId),
        ),
      ),
    );
  }
}

/// The resolved list — the count header plus one [PendingInviteRow] per
/// invitation, or the empty state when nothing is outstanding.
class _PendingInvitesBody extends StatelessWidget {
  const _PendingInvitesBody({required this.state, required this.onCancel});

  final PendingInvitesState state;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<PendingInvite> invites = state.invites;
    if (invites.isEmpty) return const _PendingInvitesEmptyState();

    return Column(
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
        // EAGER ON PURPOSE — do not "fix" this into a builder (mobile-perf
        // LOW, reviewed and declined 2026-08-30). `SectionScaffold` renders
        // [body] inside a `SingleChildScrollView`, so a nested `ListView`
        // here needs `shrinkWrap: true` + `NeverScrollableScrollPhysics` —
        // and a shrink-wrapped list lays out EVERY child to measure itself,
        // so it builds exactly as many rows as this `Column` while adding a
        // second scrollable, a viewport and an extra layout pass. The
        // laziness is forfeited; only the ceremony survives. Going genuinely
        // lazy would mean re-shaping `SectionScaffold` itself onto slivers,
        // which is a shared-chrome change across its 23 consumers, not this
        // list's call. N is bounded server-side anyway: `GET
        // /salons/{id}/invites/pending` returns only unused, unexpired
        // invitations inside a 48h window.
        for (int i = 0; i < invites.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: VelvetSpacing.sm + 2),
          PendingInviteRow(
            // Keyed at the CALL SITE, not inside the row — a keyless child is
            // matched by index, so a mid-list cancel would deactivate and
            // re-inflate every trailing row instead of updating it. See
            // `pendingInviteRowKey`'s own doc.
            key: pendingInviteRowKey(invites[i].inviteId),
            invite: invites[i],
            cancelling: state.cancelling.contains(invites[i].inviteId),
            failed: state.failed.contains(invites[i].inviteId),
            onCancel: () => onCancel(invites[i].inviteId),
          ),
        ],
      ],
    );
  }
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
