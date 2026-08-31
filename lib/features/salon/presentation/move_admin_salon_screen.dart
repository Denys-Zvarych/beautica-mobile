// Phase 21.6 — «Інший салон»: the rotate-admin destination picker.
//
// Pushed from [AdminSettingsScreen]'s «Перемістити до іншого салону» row.
// Lists the ACTIVE salons sharing this salon's owner, minus this salon;
// tapping one raises the confirmation and, on confirm, issues
// `PATCH /salons/{salonId}/admins/{userId}/salon`.
//
// WHERE THE LIST COMES FROM — `GET /salons/{salonId}/sibling-salons`
// ([siblingSalonsProvider]), NOT `GET /salons/mine`. The preview's own note
// says the production port would "hydrate from the same owner-scoped
// `GET /salons`the hub uses, filtered by `salon.id != currentSalonId`"; that
// is wrong for this screen and the backend closed the gap. `/salons/mine` is
// owner-only and 403s for the assigned `SALON_ADMIN` who may equally be
// doing the rotating, and the client-side "filter out the current salon"
// step is the server's job (it also has to filter INACTIVE salons, which the
// client cannot see). Backend Phase 21.3b added the owner+admin endpoint for
// exactly this list. See [SalonRepository.getSiblingSalons].
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// move_admin_salon_screen.dart` — ported literally onto the production
// shell. REUSE-FIRST substitutions:
//
//   * the preview's bespoke `_PickerTopBar` → the shared [SectionScaffold]
//     (back chevron + centred title), the same swap every sibling salon
//     screen made;
//   * the preview's bespoke `_SalonTargetCard` → [SalonHubCard], PROMOTED
//     this phase out of `my_salons_screen.dart` — the preview's own doc says
//     that card "mirrors the 'Мої салони' hub card", so the hub card IS the
//     widget, and copying it privately here is the fork the rule forbids;
//   * the preview's bespoke `_MoveDialogButton` pair → the shipped
//     confirmation chrome ([MoveAdminDialog]);
//   * the preview's imperative `Navigator.push`/`maybePop` → go_router.
//
// GAPS THE PREVIEW DID NOT COVER (it is a static, always-loaded mock):
//   * loading → shimmer cards on the real card's silhouette, from the SHARED
//     [SkeletonShimmerScope]/[SkeletonBlock];
//   * error → the shared [ErrorState] + retry, the one error voice every
//     other `AsyncValue` branch in the app uses.
//
// WHAT THE BACKEND CANNOT GIVE THIS SCREEN — the preview's card shows a
// two-line `locality\naddress` block. `SiblingSalonOption` carries NO
// locality at all (deliberately: see that model's own header for the
// disclosure rationale), only `street`/`buildingNo`. So the card renders the
// street line alone. This is a data limit, not a design change — the same
// [SalonHubCard] renders both lines wherever a full [Salon] is available.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart'
    show kSalonTeamNavTab;
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:dio/dio.dart';

import '../../master/presentation/widgets/section_scaffold.dart';
import '../application/admin_settings_notifier.dart';
import '../application/salon_management_profile_notifier.dart';
import '../application/salon_shell_provider.dart';
import '../application/salon_staff_member_notifier.dart';
import '../domain/salon.dart';
import '../domain/salon_staff_member.dart';
import 'salon_management_profile_screen.dart' show kSalonStaffSubTab;
import 'widgets/admin_action_dialogs.dart';
import 'widgets/salon_hub_card.dart';
import 'widgets/salon_notice_card.dart';

/// The destination picker for moving administrator [memberId] out of salon
/// [salonId].
class MoveAdminSalonScreen extends ConsumerStatefulWidget {
  const MoveAdminSalonScreen({
    super.key,
    required this.salonId,
    required this.memberId,
  });

  /// The SOURCE salon — the one the administrator is currently assigned to,
  /// and the `{salonId}` of both the sibling-salons read and the rotate
  /// write.
  final String salonId;

  /// The roster entry's `userId`.
  final String memberId;

  @override
  ConsumerState<MoveAdminSalonScreen> createState() =>
      _MoveAdminSalonScreenState();
}

class _MoveAdminSalonScreenState extends ConsumerState<MoveAdminSalonScreen> {
  /// Double-tap guard for the whole list: while a rotate is in flight no
  /// second destination may be submitted.
  bool _moving = false;

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        RouteNames.salonManageAdminSettings(widget.salonId, widget.memberId),
      );
    }
  }

  /// Maps a rotate [Failure] to this screen's own copy — see
  /// `AdminSettingsScreen._removeErrorMessage`'s doc for why the status is
  /// read off [Failure.cause] rather than assumed to be a [ServerFailure],
  /// and why a 403 gets its own sentence.
  String _errorMessage(Failure failure, AppLocalizations l10n) {
    final int? statusCode = switch (failure) {
      ServerFailure(:final statusCode) => statusCode,
      _ => switch (failure.cause) {
        DioException(:final response) => response?.statusCode,
        _ => null,
      },
    };
    return statusCode == 403
        ? l10n.moveAdminSalonErrorForbidden
        : l10n.moveAdminSalonErrorGeneric;
  }

  Future<void> _confirmMove(SiblingSalonOption target, String adminName) async {
    if (_moving) return;
    final AppLocalizations l10n = AppLocalizations.of(context);

    final bool? confirmed = await showMoveAdminDialog(
      context,
      adminName: adminName,
      destinationSalonName: target.name,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _moving = true);
    final Failure? failure = await ref
        .read(adminSettingsProvider.notifier)
        .rotate(
          salonId: widget.salonId,
          userId: widget.memberId,
          destinationSalonId: target.id,
        );
    if (!mounted) return;

    if (failure != null) {
      setState(() => _moving = false);
      showErrorSnack(context, _errorMessage(failure, l10n));
      return;
    }

    showSuccessSnack(context, l10n.moveAdminSalonSuccess);
    _returnToStaffTab();
  }

  /// Leaves for the SOURCE salon profile's «Персонал» tab after a successful
  /// move, refreshing its roster on the way — the administrator is no longer
  /// on it.
  ///
  /// Same ordering and same reasoning as
  /// `AdminSettingsScreen._returnToStaffTab` (invalidate while mounted, then
  /// reconcile BOTH shell indices, then unwind), with one extra pop: this
  /// screen sits above the admin settings page, which sits above the staff
  /// profile. Each pop re-checks `canPop`, so a cold deep link straight here
  /// falls back to `context.go` on the management profile.
  void _returnToStaffTab() {
    ref.invalidate(salonManagementProfileProvider(widget.salonId));
    ref
        .read(salonManageTabProvider(widget.salonId).notifier)
        .select(kSalonStaffSubTab);
    ref
        .read(salonShellProvider(widget.salonId).notifier)
        .select(kSalonTeamNavTab);

    for (int i = 0; i < 3; i++) {
      if (!context.mounted) return;
      if (!context.canPop()) {
        context.go(RouteNames.salonManage(widget.salonId));
        return;
      }
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<List<SiblingSalonOption>> async = ref.watch(
      siblingSalonsProvider(widget.salonId),
    );
    // The administrator's display name — off the already-cached roster, the
    // same nullable-`value` read (and the same degradation rule) as
    // `AdminSettingsScreen.build`.
    final SalonStaffMember? member = ref
        .watch(
          salonStaffMemberProfileProvider(
            widget.salonId,
            widget.memberId,
          ).select((AsyncValue<SalonStaffMemberProfileData> s) => s.value),
        )
        ?.$1;
    final String adminName = member == null
        ? ''
        : '${member.firstName} ${member.lastName}'.trim();

    return SectionScaffold(
      title: l10n.moveAdminSalonTitle,
      backSemanticLabel: l10n.moveAdminSalonBackSemanticLabel,
      backKey: const Key('btn-back-move-admin'),
      onBack: _onBack,
      // Deliberately `.when` on the CONCRETE branch shape rather than a
      // `hasError` test: `AsyncLoading(retrying: true)` satisfies `hasError`
      // while the list refetches, and gating the error branch on it would
      // flash the error screen over a healthy retry.
      body: async.when(
        loading: () => const _MoveTargetsSkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () => ref.invalidate(siblingSalonsProvider(widget.salonId)),
        ),
        data: (List<SiblingSalonOption> targets) => _MoveTargetsBody(
          targets: targets,
          adminName: adminName,
          onSelect: (SiblingSalonOption target) =>
              _confirmMove(target, adminName),
        ),
      ),
    );
  }
}

/// The resolved destination list — the prompt line plus one [SalonHubCard]
/// per sibling salon, or the empty state when the owner has only this one.
class _MoveTargetsBody extends StatelessWidget {
  const _MoveTargetsBody({
    required this.targets,
    required this.adminName,
    required this.onSelect,
  });

  final List<SiblingSalonOption> targets;

  /// Empty while the roster is still resolving — the prompt line is then
  /// omitted rather than rendered with a hole in the sentence.
  final String adminName;

  final ValueChanged<SiblingSalonOption> onSelect;

  /// Adapts one narrow [SiblingSalonOption] into the display-only [Salon]
  /// [SalonHubCard] renders.
  ///
  /// Explicit and local ON PURPOSE: the repository returns the narrow model
  /// the endpoint actually sends (see `SiblingSalonOptionMapper`'s doc), so this
  /// is the ONE place the widening happens and the one place a reader has to
  /// look to know which fields are genuinely absent. Everything left unset
  /// degrades correctly in the card: a blank `cityId`/`oblastId` short-
  /// circuits `resolvedLocalityProvider` with NO network read at all (see
  /// that provider's own guard), so no locality line is drawn, and a null
  /// `isPrimary` renders no «Основний» badge — neither of which this
  /// endpoint could ever have populated.
  static Salon _displaySalon(SiblingSalonOption option) => Salon(
    id: option.id,
    name: option.name,
    street: option.street,
    buildingNo: option.buildingNo,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (targets.isEmpty) return const _MoveTargetsEmptyState();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (adminName.isNotEmpty)
          Padding(
            key: const Key('move-admin-prompt'),
            padding: const EdgeInsets.only(
              left: VelvetSpacing.xs,
              bottom: VelvetSpacing.lg,
            ),
            child: Text(
              l10n.moveAdminSalonPrompt(adminName),
              style: VelvetText.body(),
            ),
          ),
        // EAGER ON PURPOSE — do not "fix" this into a builder.
        // [SectionScaffold] renders [body] inside a `SingleChildScrollView`,
        // so a nested `ListView` here would need `shrinkWrap: true`, and a
        // shrink-wrapped list lays out EVERY child to measure itself: the
        // laziness is forfeited and only the extra viewport survives. Same
        // reasoning `salon_pending_invites_screen.dart` records for its own
        // list.
        //
        // WHY NOT `CustomScrollView` + `SliverList` (mobile-perf LOW,
        // 2026-08-31) — that IS the repo's answer for a >10-child
        // `SingleChildScrollView`, and it was assessed rather than waved off.
        // It is declined here because the scroll view is NOT this screen's:
        // it belongs to [SectionScaffold], which hard-codes
        // `Expanded(child: SingleChildScrollView(child: body))` around a
        // plain `Widget body` for ~10 pushed pages (the master settings hub
        // and every section edit page). Taking a sliver would mean adding a
        // second `sliverBody` branch to that shared chrome and proving all
        // ~10 existing consumers still render pixel-identically — a
        // structural fork of shared chrome, bought for ONE screen.
        //
        // What it would buy is small. N is the number of ACTIVE salons
        // sharing this salon's owner minus one; the endpoint is unpaginated
        // and the realistic figure is 1–5, with the 50 in the finding a
        // hypothetical cap, not a product bound. Each card is cheap to build:
        // [SiblingSalonOption] carries no `cityId`, so `_displaySalon` leaves
        // it blank and every card's `resolvedLocalityProvider` watch
        // short-circuits with NO network read (see [_displaySalon]'s doc), so
        // eager N does not mean N requests. The per-press repaint cost — the
        // one thing that genuinely scaled with N — is fixed below by the
        // [RepaintBoundary], not by laziness. If the sibling endpoint ever
        // grows pagination, revisit `SectionScaffold` first.
        for (int i = 0; i < targets.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: VelvetSpacing.md),
          // [SalonHubCard] depresses on press (`AnimatedScale` +
          // `AnimatedContainer` swapping its extruded shadow). Without this
          // boundary that press marks the whole eager column dirty and every
          // sibling neumorphic card repaints with it. `my_salons_screen.dart`
          // wraps the same card for the same reason (its `_reveal` helper);
          // this column has no `_reveal` to hang it off, so it is explicit.
          RepaintBoundary(
            child: SalonHubCard(
              // Keyed at the CALL SITE so a list that changes between builds
              // matches cards by identity, not by index.
              key: ValueKey<String>('move-admin-target-${targets[i].id}'),
              salon: _displaySalon(targets[i]),
              onTap: () => onSelect(targets[i]),
            ),
          ),
        ],
      ],
    );
  }
}

/// Nothing to move to — the owner has exactly one active salon. Ported from
/// the preview's own `_EmptyState`, rebuilt on the shared [NeumorphicInset]
/// the sibling empty states use.
///
/// Phase 21.6 audit follow-up — the card body itself was PROMOTED to
/// [SalonNoticeCard] so [AdminSettingsScreen]'s non-admin guard renders the
/// same shape instead of a fork. The geometry is unchanged; this widget is
/// now just this screen's copy + key bound onto it.
class _MoveTargetsEmptyState extends StatelessWidget {
  const _MoveTargetsEmptyState();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SalonNoticeCard(
      key: const Key('move-admin-empty'),
      icon: Icons.storefront_outlined,
      title: l10n.moveAdminSalonEmptyTitle,
      body: l10n.moveAdminSalonEmptyBody,
    );
  }
}

/// Placeholder cards on the real card's silhouette — same logo circle, same
/// two-line text stack — so the list resolves without a layout jump.
class _MoveTargetsSkeleton extends StatelessWidget {
  const _MoveTargetsSkeleton();

  static const int _rowCount = 2;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Align(
            alignment: Alignment.centerLeft,
            child: SkeletonBlock(width: 210, height: 13),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          for (int i = 0; i < _rowCount; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: VelvetSpacing.md),
            const _SkeletonTargetCard(),
          ],
        ],
      ),
    );
  }
}

class _SkeletonTargetCard extends StatelessWidget {
  const _SkeletonTargetCard();

  @override
  Widget build(BuildContext context) {
    return const NeumorphicCard(
      padding: EdgeInsets.all(VelvetSpacing.md + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SkeletonBlock(width: 58, height: 58, circle: true),
          SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SkeletonBlock(width: 150, height: 17),
                SizedBox(height: VelvetSpacing.xs + 1),
                SkeletonBlock(width: 110, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
