// Phase 21.6, generalized Phase 305 — «Налаштування» for ONE staff member.
//
// The full settings PAGE (never a bottom sheet) reached from the trailing
// `Icons.tune_rounded` control on a staff member's management profile
// (`salon_staff_profile_screen.dart`, Phase 21.5). Its body is chosen by
// `SalonStaffMember.role`. As of THIS phase only the ADMIN branch exists —
// phase 307 adds the MASTER branch alongside it, which is the reason this
// screen was widened (Phase 305) rather than forked into a
// `master_settings_screen.dart` when that need arrived. Admins are
// administrative staff, not service-providing masters, so the master sheet's
// service / activate / make-admin toggles have no meaning on the admin
// branch — only the two admin-specific actions do:
//
//   1. «Перемістити до іншого салону» → pushes [MoveAdminSalonScreen]
//      (`PATCH /salons/{salonId}/admins/{userId}/salon`).
//   2. «Перевести в майстри» → PRESENT BUT DISABLED. There is NO backend
//      endpoint for role conversion (it would have to create a `Master` row,
//      migrate the user's identity and decide what happens to their admin
//      history — none of it scoped). The design places the row, so the row
//      is placed; wiring it to anything would be faking a success. It ships
//      `enabled: false` + «незабаром».
//   3. hairline, then the terminal «Видалити адміністратора»
//      (`DELETE /salons/{salonId}/admins/{userId}`).
//
// COPY — «Видалити адміністратора» is the design's own label and stays. The
// endpoint UNASSIGNS the admin (`salon_id` → null); it does not delete their
// account. The confirmation body is where that is made honest
// («…втратить доступ до керування салоном»), which is exactly what the
// preview's own dialog already said.
//
// This is a manage-THIS-staff-member screen opened by the owner or a fellow
// admin — NOT the viewer's own settings — so it carries no self-service rows
// (no «Акаунт», no «Вийти»). Those act on the CURRENT viewer, which would be
// nonsensical here; they live on the viewer's own `salon_settings_screen`.
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// admin_settings_screen.dart` — ported literally onto the production shell.
// REUSE-FIRST substitutions, all of them the house pattern every sibling
// salon screen already made for its own preview source:
//
//   * the preview's bespoke `_SettingsTopBar` → the shared [SectionScaffold]
//     (`backIcon: Icons.close_rounded`, no back chevron — identical to
//     `settings_hub_screen.dart` / `salon_settings_screen.dart`);
//   * the preview's bespoke `_SettingsRow` → the shared [SettingsRow], with
//     the ONE additive parameter this screen needed (`enabled`) added to it
//     rather than forked;
//   * the preview's bespoke `_DialogButton` pair → the shipped confirmation
//     chrome ([RemoveAdminDialog], see `widgets/admin_action_dialogs.dart`'s
//     own header for that one deliberate layout deviation);
//   * the preview's imperative `Navigator.push` → `context.push` on named
//     [RouteNames] routes.
//
// The staggered reveal is the preview's verbatim: ONE 1000 ms controller,
// per-row `Interval`s, `Tween<Offset>(begin: Offset(0, 0.035))`,
// `Curves.easeOutCubic`, animations pre-built in `initState` so `build()`
// allocates nothing (the `settings_hub_screen.dart` mobile-perf pattern).
// "Allocates nothing" is now literally true for BOTH halves — the slide
// half used to be derived per build; see `_curve` and `_RevealAnim`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart'
    show kSalonTeamNavTab;
import 'package:dio/dio.dart';

import '../../master/presentation/widgets/profile_avatar.dart';
import '../../master/presentation/widgets/section_scaffold.dart';
import '../../master/presentation/widgets/settings_row.dart';
import '../application/admin_settings_notifier.dart';
import '../application/salon_management_profile_notifier.dart';
import '../application/salon_shell_provider.dart';
import '../application/salon_staff_member_notifier.dart';
import '../domain/salon_staff_member.dart';
import 'salon_management_profile_screen.dart' show kSalonStaffSubTab;
import 'widgets/admin_action_dialogs.dart';
import 'widgets/salon_notice_card.dart';

/// The two halves of one row's staggered entrance, built once in
/// `initState` and only READ in `build` — see
/// `_StaffSettingsScreenState._curve` for why the slide half is no longer
/// derived per build.
class _RevealAnim {
  const _RevealAnim({required this.fade, required this.slide});

  /// Drives `FadeTransition.opacity`. Owned here: it is the only half that
  /// needs disposing (it attaches a status listener to the controller).
  final CurvedAnimation fade;

  /// Drives `SlideTransition.position`. A lazy view over [fade] — it holds no
  /// listener of its own, so it is not disposed.
  final Animation<Offset> slide;
}

/// «Налаштування» for the administrator [memberId] of salon [salonId].
class StaffSettingsScreen extends ConsumerStatefulWidget {
  const StaffSettingsScreen({
    super.key,
    required this.salonId,
    required this.memberId,
  });

  /// Backend Salon-row UUID this administrator is assigned to.
  final String salonId;

  /// The roster entry's `userId` — also the `{userId}` path variable of both
  /// admin endpoints this screen calls.
  final String memberId;

  @override
  ConsumerState<StaffSettingsScreen> createState() =>
      _StaffSettingsScreenState();
}

class _StaffSettingsScreenState extends ConsumerState<StaffSettingsScreen>
    with SingleTickerProviderStateMixin {
  /// Double-tap guard for the destructive row, mirroring
  /// `SettingsScreen`'s own delete-salon flag: it also drives
  /// `SettingsRow(loading: ...)` so a slow network shows a spinner instead of
  /// swallowing the second tap.
  bool _removing = false;

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final _RevealAnim _anim0; // context subheading
  late final _RevealAnim _anim1; // move to another salon
  late final _RevealAnim _anim2; // convert to master (disabled)
  late final _RevealAnim _anim3; // hairline
  late final _RevealAnim _anim4; // remove (destructive)

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    // The preview's own intervals, verbatim (`admin_settings_screen.dart:73-77`).
    _anim0 = _curve(0.00, 0.42);
    _anim1 = _curve(0.10, 0.54);
    _anim2 = _curve(0.20, 0.66);
    _anim3 = _curve(0.32, 0.78);
    _anim4 = _curve(0.42, 0.92);
    _controller.forward();
  }

  /// Builds BOTH halves of one row's entrance up front.
  ///
  /// mobile-perf LOW (2026-08-31) — the slide half used to be
  /// `_slideTween.animate(anim)` inside `_reveal`, i.e. a fresh
  /// `Animation<Offset>` per row PER BUILD. That contradicted the file
  /// header's "build() allocates nothing" claim and, worse, handed
  /// `SlideTransition` a new `position` object on every rebuild, so
  /// `didUpdateWidget` detached its listener from the old animation and
  /// reattached to the new one each time. Both halves are now built once,
  /// here, and `build()` only reads them.
  _RevealAnim _curve(double start, double end) {
    final CurvedAnimation fade = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return _RevealAnim(fade: fade, slide: _slideTween.animate(fade));
  }

  @override
  void dispose() {
    _anim0.fade.dispose();
    _anim1.fade.dispose();
    _anim2.fade.dispose();
    _anim3.fade.dispose();
    _anim4.fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// One row's staggered entrance.
  ///
  /// mobile-perf MEDIUM (2026-08-31) — [RepaintBoundary] sits INSIDE the
  /// transitions, wrapping the row itself. Without it `SlideTransition`'s
  /// `FractionalTranslation` repaints the row's full subtree (a
  /// [NeumorphicInset] well plus two blurred [VelvetShadow]s) on every frame
  /// of the 1000 ms entrance; with it the row rasterises once and each frame
  /// only re-offsets a retained layer. `my_salons_screen.dart`'s own
  /// `_reveal` carries the same boundary for the same reason.
  Widget _reveal(_RevealAnim anim, Widget child) {
    return FadeTransition(
      opacity: anim.fade,
      child: SlideTransition(
        position: anim.slide,
        child: RepaintBoundary(child: child),
      ),
    );
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        RouteNames.salonManageStaffMember(widget.salonId, widget.memberId),
      );
    }
  }

  void _openMove() {
    context.push(
      RouteNames.salonManageAdminMove(widget.salonId, widget.memberId),
    );
  }

  /// Maps a remove [Failure] to this screen's own copy.
  ///
  /// Deliberately NOT `failure.userMessage(context)`: [ServerFailure]'s is a
  /// single generic "server error" for every status, and a 403 here means
  /// something the viewer can act on (you cannot remove yourself; you need
  /// management access). Reads the status off [Failure.cause] rather than
  /// assuming a [ServerFailure] subtype — [ErrorMapperInterceptor] maps only
  /// an explicit list of codes, and a bare 403 arrives as [UnknownFailure];
  /// see `InviteStaffScreen._errorMessage`'s own doc for that trap.
  String _removeErrorMessage(Failure failure, AppLocalizations l10n) {
    final int? statusCode = switch (failure) {
      ServerFailure(:final statusCode) => statusCode,
      _ => switch (failure.cause) {
        DioException(:final response) => response?.statusCode,
        _ => null,
      },
    };
    return statusCode == 403
        ? l10n.adminSettingsRemoveErrorForbidden
        : l10n.adminSettingsRemoveErrorGeneric;
  }

  Future<void> _confirmRemove(String adminName) async {
    if (_removing) return;
    final AppLocalizations l10n = AppLocalizations.of(context);

    final bool? confirmed = await showRemoveAdminDialog(context, adminName);
    if (confirmed != true || !mounted) return;

    setState(() => _removing = true);
    final Failure? failure = await ref
        .read(staffSettingsProvider.notifier)
        .removeAdmin(salonId: widget.salonId, userId: widget.memberId);
    if (!mounted) return;

    if (failure != null) {
      setState(() => _removing = false);
      showErrorSnack(context, _removeErrorMessage(failure, l10n));
      return;
    }

    showSuccessSnack(context, l10n.adminSettingsRemoveSuccess);
    _returnToStaffTab();
  }

  /// Leaves for the salon profile's «Персонал» tab after a successful
  /// removal, refreshing the roster on the way.
  ///
  /// Order matters. The roster is invalidated FIRST, while this element is
  /// still mounted and `ref` is guaranteed usable (the
  /// `InviteStaffScreen._submit` precedent) — `salonManagementProfileProvider`
  /// is the family the «Персонал» grid AND the staff profile we are popping
  /// through both read, so without this the admin the viewer just watched
  /// disappear is still in the list they land on.
  ///
  /// WHAT THAT INVALIDATE ACTUALLY DOES — it is NOT a seamless in-place
  /// refetch, and nothing here should be written as if it were. At this
  /// moment the salon profile below is obscured by this pushed route, so
  /// every remaining listener of the family is offstage-PAUSED; per the
  /// documented Riverpod trap, invalidating an `autoDispose` provider whose
  /// only listeners are paused DISPOSES it rather than refetching it (and
  /// `SalonManagementProfile` is a plain `@riverpod` family — see its own
  /// header for why it deliberately carries no `keepAlive`). So the grid the
  /// viewer lands on re-builds from scratch and shows its skeleton for one
  /// fetch before the corrected roster paints.
  ///
  /// That beat of loading is the intended trade, not a defect: the
  /// alternative is landing on a stale list that still names the
  /// administrator the viewer just watched disappear. Promoting the family
  /// to `keepAlive` to get a seamless swap would keep every visited salon's
  /// roster resident for the session and is a separate decision, not a
  /// silent side effect of this screen's unwind.
  ///
  /// Then the two shell indices are reconciled, exactly as
  /// `SalonShellScreen._onSubTabSelected` does: the sub-tab moves to
  /// «Персонал» and the bottom-nav highlight follows it to «Команда».
  /// Setting only one of the two is what makes the nav and the in-screen row
  /// disagree. When the profile is routed standalone (not hosted by the
  /// shell) these writes are simply unobserved — harmless.
  ///
  /// Finally we pop TWICE: this settings page, then the staff profile
  /// underneath it, which is now a page about a member who is no longer on
  /// the roster (it would render `NotFoundFailure`). `context.canPop()` is
  /// re-checked before each pop, so a cold deep link straight to this route
  /// falls back to `context.go` on the management profile instead.
  void _returnToStaffTab() {
    ref.invalidate(salonManagementProfileProvider(widget.salonId));
    ref
        .read(salonManageTabProvider(widget.salonId).notifier)
        .select(kSalonStaffSubTab);
    ref
        .read(salonShellProvider(widget.salonId).notifier)
        .select(kSalonTeamNavTab);

    if (!context.canPop()) {
      context.go(RouteNames.salonManage(widget.salonId));
      return;
    }
    context.pop();
    if (!context.mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.salonManage(widget.salonId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // The administrator's display name, read off the ALREADY-CACHED roster
    // (`salonStaffMemberProfileProvider` selects the entry out of
    // `salonManagementProfileProvider`, which is warm on every real entry
    // path — this screen is reached from that member's own profile). It
    // drives the context subheading and both dialog bodies.
    //
    // Read through `AsyncValue.value` (nullable in Riverpod 3.x), never
    // `hasValue`/`hasError`: it keeps the PREVIOUS name visible while the
    // entry re-resolves, and it sidesteps `AsyncValue.hasError` being
    // satisfied by `AsyncLoading(retrying: true)`. A name that is not there
    // yet renders no subheading rather than a spinner — see
    // `_ContextSubheading` in `salon_settings_screen.dart` for the same
    // degradation rule.
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

    // ROLE GUARD (mobile-perf/QA LOW, 2026-08-31) — every row below acts on
    // `/salons/{salonId}/admins/{userId}`, which only exists for an ADMIN
    // entry. `SalonStaffProfileScreen` only offers the entry point for an
    // admin, but the ROUTE is reachable without it: the browser/system back
    // stack, an in-app `context.go`, or a cold deep link all land here with
    // whatever `memberId` the URL carries. Rendering «Видалити
    // адміністратора» against a MASTER's userId is a dead affordance — the
    // server refuses it (that is and stays the gate; this is a UI-correctness
    // fix, not a client-side authorization decision) — but a destructive row
    // that cannot work must not be drawn at all.
    //
    // Gated on a RESOLVED non-admin only. While the role is unknown (loading,
    // or a failed roster read) `member` is null and the rows render as
    // before, exactly like `SalonStaffProfileScreen`'s own `maybeWhen`
    // default — the guard never flashes over a healthy load.
    final bool isNotAdmin =
        member != null && member.role != SalonStaffRole.admin;

    return SectionScaffold(
      title: l10n.settingsTitle,
      backIcon: Icons.close_rounded,
      backSemanticLabel: l10n.settingsHubClose,
      backKey: const Key('btn-close-admin-settings'),
      onBack: _close,
      body: isNotAdmin
          ? SalonNoticeCard(
              key: const Key('admin-settings-not-an-admin'),
              icon: Icons.badge_outlined,
              title: l10n.adminSettingsNotAnAdminTitle,
              body: l10n.adminSettingsNotAnAdminBody,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Context subheading — WHO is being managed. Absent (never a
                // placeholder) until the roster resolves.
                _reveal(_anim0, _AdminContextRow(name: adminName)),

                // Navigational group.
                _reveal(
                  _anim1,
                  SettingsRow(
                    key: const Key('row-admin-move-salon'),
                    icon: Icons.swap_horiz_rounded,
                    label: l10n.adminSettingsMoveSalon,
                    onTap: _openMove,
                  ),
                ),
                const SizedBox(height: VelvetSpacing.md),
                _reveal(
                  _anim2,
                  SettingsRow(
                    key: const Key('row-admin-convert-to-master'),
                    icon: Icons.badge_outlined,
                    label: l10n.adminSettingsConvertToMaster,
                    // No backend endpoint exists for role conversion — the row is
                    // visibly present and inert, and says so. `onTap` is a no-op
                    // that `enabled: false` never lets fire (taps are absorbed);
                    // it is not a "silently does nothing" handler.
                    enabled: false,
                    showChevron: false,
                    value: l10n.adminSettingsConvertToMasterSoon,
                    onTap: () {},
                  ),
                ),

                // Separation before the terminal action.
                _reveal(
                  _anim3,
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
                    child: Divider(
                      key: Key('admin-settings-divider'),
                      thickness: 0.6,
                      color: Color(0x38B89A7A), // accent @ ~22%
                    ),
                  ),
                ),

                // Terminal / destructive action — set apart.
                _reveal(
                  _anim4,
                  SettingsRow(
                    key: const Key('row-admin-remove'),
                    icon: Icons.person_remove_outlined,
                    label: l10n.adminSettingsRemove,
                    destructive: true,
                    showChevron: false,
                    loading: _removing,
                    onTap: () => _confirmRemove(adminName),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The design's context subheading (`docs/signup-designs/SalonManagementDesign
/// /lib/screens/admin_settings_screen.dart:228-250`) — a [RoleChip] beside
/// the administrator's name, so a page whose every row says "адміністратор"
/// still says WHICH one.
///
/// DEGRADATION — this row is orientation, not chrome: with no name to show
/// (roster still loading, or a failed read) it renders `SizedBox.shrink()`,
/// never a spinner, a skeleton or an orphaned chip. It can therefore never
/// block or displace the rows below. Same rule `_ContextSubheading` states
/// on `salon_settings_screen.dart`.
class _AdminContextRow extends StatelessWidget {
  const _AdminContextRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) {
      return const SizedBox.shrink(key: Key('admin-settings-context-absent'));
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('admin-settings-context'),
      padding: const EdgeInsets.only(
        left: VelvetSpacing.xs,
        bottom: VelvetSpacing.lg,
      ),
      child: Row(
        children: <Widget>[
          RoleChip(
            label: l10n.adminSettingsContextRoleLabel,
            icon: Icons.shield_outlined,
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Flexible(
            child: Text(
              name,
              key: const Key('admin-settings-context-name'),
              style: VelvetText.body(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
