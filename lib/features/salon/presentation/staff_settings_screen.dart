// Phase 21.6, generalized Phase 305, MASTER branch wired Phase 307 —
// «Налаштування» for ONE staff member.
//
// The full settings PAGE (never a bottom sheet) reached from the trailing
// `Icons.tune_rounded` control on a staff member's management profile
// (`salon_staff_profile_screen.dart`, Phase 21.5). Its body is chosen by
// `SalonStaffMember.role`. Admins are administrative staff, not
// service-providing masters, so the master branch's own actions have no
// meaning on the admin branch — only the three admin-specific rows do:
//
//   1. «Перемістити до іншого салону» → pushes [MoveAdminSalonScreen]
//      (`PATCH /salons/{salonId}/admins/{userId}/salon`).
//   2. «Перевести в майстри» → PRESENT BUT DISABLED. There is NO backend
//      endpoint for role conversion (it would have to create a `Master` row,
//      migrate the user's identity and decide what happens to their admin
//      history — none of it scoped). The design places the row, so the row
//      is placed; wiring it to anything would be faking a success. It ships
//      `enabled: false` + «незабаром».
//   3. hairline, then the terminal «Видалити адміністратора», OWNER-ONLY as
//      of Phase 308 (`DELETE /salons/{salonId}/admins/{userId}`).
//
// COPY — «Видалити адміністратора» is the design's own label and stays.
// Backend Phase 299 turned the endpoint into a HARD DELETE of the admin's
// user account (it used to null `salon_id` and leave the row alive) and
// narrowed the caller to `SALON_OWNER`. Both staff-removal endpoints — this
// one and `DELETE /salons/{salonId}/masters/{masterId}` — hard-delete now;
// there is no surviving distinction between them. Phase 308 corrected the
// confirmation body accordingly (it used to promise only a loss of salon
// access) and added the `canManageStaff` owner gate below so a non-owner
// admin never sees a row that 403s on tap.
//
// THE MASTER BRANCH (Phase 307) — a single terminal row, «Видалити
// майстра» (`DELETE /salons/{salonId}/masters/{masterId}`, backend Phase
// 297 + 298). A categorically LARGER act than the admin branch's: the
// endpoint hard-deletes the master's account and cancels+notifies their
// future bookings, and it is SALON_OWNER-only (unlike remove-admin, which an
// admin may also perform). Two gates stand in front of it, both UI-
// correctness (the server remains the real gate — see D3's own doc):
//
//   * not the owner              → [SalonNoticeCard] (`staffSettingsMasterOwnerOnlyTitle`/`Body`), no row at all;
//   * the owner's OWN master row → the SAME card (same key), but DISTINCT
//     copy (`staffSettingsMasterSelfTitle`/`Body`, mobile-security LOW fix,
//     2026-09-05) — the "ask the owner" phrasing on the not-owner branch is
//     factually wrong when the viewer IS the owner: there is nobody else to
//     ask. Backend 297 409s/403s a self-target regardless; this card's copy
//     honestly points the owner at the separate `DELETE
//     /salons/{salonId}/master` owner-toggle instead of just saying "no".
//     `isOwnRow` in `build()` is the switch between the two bodies.
//
// D2 — THE ID TRAP: the row acts on `member.masterId`, NEVER
// `widget.memberId`/`member.userId`. See [SalonRepository.removeMaster]'s
// own doc for why a swapped id 404s in a way indistinguishable from
// "already removed". While the resolved entry's `masterId` is null (a data
// anomaly — every real master row carries one) the row renders
// `enabled: false`, the same present-but-disabled idiom
// `adminSettingsConvertToMaster` already established on this screen.
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
import 'package:beautica_mobile/shared/widgets/salon_notice_card.dart';
import 'package:dio/dio.dart';

import '../../auth/presentation/auth_selectors.dart';
import '../../master/presentation/widgets/profile_avatar.dart';
import '../../master/presentation/widgets/section_scaffold.dart';
import '../../master/presentation/widgets/settings_row.dart';
import '../application/admin_settings_notifier.dart';
import '../application/public_salon_profile_notifier.dart';
import '../application/salon_management_profile_notifier.dart';
import '../application/salon_shell_provider.dart';
import '../application/salon_staff_member_notifier.dart';
import '../domain/salon_staff_member.dart';
import 'salon_management_profile_screen.dart' show kSalonStaffSubTab;
import 'widgets/admin_action_dialogs.dart';

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
  /// Double-tap guard for the destructive row's NETWORK call, mirroring
  /// `SettingsScreen`'s own delete-salon flag: it drives
  /// `SettingsRow(loading: ...)`, so a slow network shows a spinner instead
  /// of swallowing the second tap. Flips to `true` only once the DELETE is
  /// actually dispatched, never merely while the confirmation dialog is up
  /// — see [_confirmOpen] for that earlier window, and why it is a SEPARATE
  /// flag rather than this one doing double duty.
  bool _removing = false;

  /// Double-tap guard for the CONFIRMATION-DIALOG window, ahead of
  /// [_removing] (mobile-perf LOW fix, 2026-09-05).
  ///
  /// `_removing` used to be the only guard, and it flipped to `true` only
  /// AFTER `showRemoveAdminDialog`/`showRemoveMasterDialog` resolved. That
  /// left a window between "row tapped" and "dialog's modal barrier is up"
  /// where a fast double-tap could open two stacked confirmation dialogs;
  /// confirming both then fired TWO delete calls — and on the master path
  /// the second one hard-deletes an account that is already gone, a 404 the
  /// UI cannot distinguish from "already removed".
  ///
  /// A SEPARATE flag, not `_removing` set early, because `_removing` also
  /// drives `SettingsRow(loading: true)`, which swaps in an indeterminate
  /// spinner — an animation that never settles on its own. Flipping THAT on
  /// for the entire time the confirmation dialog sits open (an
  /// indefinite, user-paced wait, not a network round-trip) would leave the
  /// row "spinning" behind the modal barrier for as long as the viewer takes
  /// to decide, and makes `tester.pumpAndSettle()` hang for that whole
  /// window in every test that opens this dialog — measured directly: this
  /// is exactly what reusing `_removing` for both windows did. `_confirmOpen`
  /// carries none of that chrome; it is a plain re-entrancy guard, checked
  /// (like `_removing`) as a raw field read before any `setState`, so a
  /// second synchronous tap during the SAME event dispatch is blocked
  /// regardless of whether a frame has rendered yet. Reset to `false` right
  /// after the dialog resolves, confirmed or not.
  bool _confirmOpen = false;

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

  /// Reads the HTTP status code off a remove [Failure].
  ///
  /// Prefers [ServerFailure]'s own field, falling back to unwrapping
  /// [Failure.cause] — the shape a bare 403 arrives in, since
  /// [ErrorMapperInterceptor] maps only an explicit list of codes to
  /// [ServerFailure] and 403 is not on it (see
  /// `InviteStaffScreen._errorMessage`'s own doc for that trap).
  ///
  /// PROMOTED (Phase 307, D5) out of [_removeErrorMessage] (admin) so
  /// [_removeMasterErrorMessage] (master) reads a status the same way — one
  /// extraction, shared, so the two role branches cannot drift in how they
  /// interpret a code.
  int? _failureStatusCode(Failure failure) => switch (failure) {
    ServerFailure(:final statusCode) => statusCode,
    _ => switch (failure.cause) {
      DioException(:final response) => response?.statusCode,
      _ => null,
    },
  };

  /// Maps a remove-admin [Failure] to this screen's own copy.
  ///
  /// Deliberately NOT `failure.userMessage(context)`: [ServerFailure]'s is a
  /// single generic "server error" for every status, and each status here
  /// means something distinct the viewer can act on or at least understand.
  ///
  /// Phase 308 (D6/D7) widened this from a two-way (403-vs-generic) switch
  /// to four-way, mirroring [_removeMasterErrorMessage]'s shape now that
  /// backend Phase 299 gave this endpoint the same 409/404 failure modes:
  ///   * 403 — owner-only as of 299; `canManageStaff` (D3) should make this
  ///     unreachable in practice, but the role can go stale between a
  ///     cached staff read and the tap, so the backstop stays.
  ///   * 409 — the admin's user row is also referenced as a client. Unlike
  ///     [_removeMasterErrorMessage]'s 409 (three collapsed causes, hedged
  ///     copy), this status has exactly ONE cause server-side, so the copy
  ///     names it directly instead of hedging.
  ///   * 404 — idempotent-by-absence: a second DELETE lands here.
  String _removeErrorMessage(Failure failure, AppLocalizations l10n) {
    return switch (_failureStatusCode(failure)) {
      403 => l10n.adminSettingsRemoveErrorForbidden,
      409 => l10n.adminSettingsRemoveErrorConflict,
      404 => l10n.adminSettingsRemoveErrorNotFound,
      _ => l10n.adminSettingsRemoveErrorGeneric,
    };
  }

  /// Maps a remove-master [Failure] to this screen's own copy (Phase 307,
  /// D5) — a four-way switch, unlike the admin branch's two-way one, because
  /// the master endpoint distinguishes 409 (stale roster picture) from 404
  /// (the member is already gone) where the admin endpoint's callers only
  /// ever needed 403-vs-generic.
  String _removeMasterErrorMessage(int? statusCode, AppLocalizations l10n) {
    return switch (statusCode) {
      403 => l10n.removeMasterErrorForbidden,
      409 => l10n.removeMasterErrorConflict,
      404 => l10n.removeMasterErrorNotFound,
      _ => l10n.removeMasterErrorGeneric,
    };
  }

  Future<void> _confirmRemove(String adminName) async {
    if (_removing || _confirmOpen) return;
    final AppLocalizations l10n = AppLocalizations.of(context);

    // Set BEFORE the dialog is awaited (mobile-perf LOW fix, 2026-09-05) —
    // see `_confirmOpen`'s own doc for why this is a plain field write, not
    // `setState`, and why it is a SEPARATE flag from `_removing`. A second
    // tap landing anywhere between now and the dialog resolving reads this
    // flag straight off the field and returns before a second dialog is
    // ever raised.
    _confirmOpen = true;
    final bool? confirmed = await showRemoveAdminDialog(context, adminName);
    _confirmOpen = false;
    if (!mounted) return;
    if (confirmed != true) return;

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

  /// Confirms and issues the master removal (Phase 307).
  ///
  /// D2 — acts ONLY on [member]'s `masterId`, never `widget.memberId`. The
  /// row that calls this is `enabled: member.masterId != null`, so a null
  /// id should never reach here in practice; the guard below is defensive,
  /// not load-bearing.
  ///
  /// D5 — four-way status handling, distinct from [_confirmRemove]'s
  /// two-way one:
  ///   * 404 — the member is already gone. Unwinds via [_returnToStaffTab]
  ///     exactly like a success, with the not-found copy instead of the
  ///     success snack.
  ///   * 409 — every cause means this page's picture of the roster is
  ///     stale. Stays on the page, re-enables the row, and invalidates
  ///     [salonManagementProfileProvider] so the NEXT visit to «Персонал»
  ///     is not stale too.
  ///   * 403 / other — stays on the page, re-enables the row. No
  ///     invalidation: nothing about the roster is known to be wrong.
  Future<void> _confirmRemoveMaster(SalonStaffMember member) async {
    if (_removing || _confirmOpen) return;
    final String? masterId = member.masterId;
    if (masterId == null) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String masterName = '${member.firstName} ${member.lastName}'.trim();

    // Set BEFORE the dialog is awaited (mobile-perf LOW fix, 2026-09-05) —
    // see `_confirmOpen`'s own doc. Without this, no guard covered the
    // entire pre-confirmation window and a fast double-tap could open two
    // stacked confirmation dialogs; confirming both would fire TWO
    // hard-delete calls against a master's account.
    _confirmOpen = true;
    final bool? confirmed = await showRemoveMasterDialog(context, masterName);
    _confirmOpen = false;
    if (!mounted) return;
    if (confirmed != true) return;

    setState(() => _removing = true);
    final Failure? failure = await ref
        .read(staffSettingsProvider.notifier)
        .removeMaster(salonId: widget.salonId, masterId: masterId);
    if (!mounted) return;

    if (failure != null) {
      final int? statusCode = _failureStatusCode(failure);
      final String message = _removeMasterErrorMessage(statusCode, l10n);
      if (statusCode == 404) {
        showErrorSnack(context, message);
        _returnToStaffTab();
        return;
      }
      setState(() => _removing = false);
      showErrorSnack(context, message);
      if (statusCode == 409) {
        ref.invalidate(salonManagementProfileProvider(widget.salonId));
      }
      return;
    }

    showSuccessSnack(context, l10n.removeMasterSuccess);
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
  ///
  /// EXTENDED (Phase 307, D6) with two more invalidations, ahead of the
  /// roster one, harmless for the admin flow that already called this
  /// method unmodified:
  ///
  ///   * `salonStaffMemberProfileProvider(salonId, memberId)` — the SAME
  ///     family this screen's own `build()` reads for the display name.
  ///     Invalidating it FIRST means the staff profile underneath, on its
  ///     way past during the pops below, cannot repaint a `NotFoundFailure`
  ///     mid-transition.
  ///   * `publicSalonProfileProvider(salonId)` — a **keepAlive** family
  ///     holding the public masters rail. Being keepAlive, invalidating it
  ///     is a seamless refetch, not a dispose; left alone it would keep
  ///     serving a removed master to the owner's own public-profile view for
  ///     the rest of the session.
  void _returnToStaffTab() {
    ref.invalidate(
      salonStaffMemberProfileProvider(widget.salonId, widget.memberId),
    );
    ref.invalidate(salonManagementProfileProvider(widget.salonId));
    ref.invalidate(publicSalonProfileProvider(widget.salonId));
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

    // ROLE GUARD (mobile-perf/QA LOW, 2026-08-31; MASTER branch Phase 307) —
    // every row on the ADMIN branch acts on
    // `/salons/{salonId}/admins/{userId}`, which only exists for an ADMIN
    // entry. `SalonStaffProfileScreen` only offers the entry point for an
    // admin/eligible-master, but the ROUTE is reachable without it: the
    // browser/system back stack, an in-app `context.go`, or a cold deep link
    // all land here with whatever `memberId` the URL carries. Rendering
    // «Видалити адміністратора» against a MASTER's userId is a dead
    // affordance — the server refuses it (that is and stays the gate; this
    // is a UI-correctness fix, not a client-side authorization decision) —
    // but a destructive row that cannot work must not be drawn at all.
    //
    // Gated on a RESOLVED non-admin only. While the role is unknown (loading,
    // or a failed roster read) `member` is null and the ADMIN rows render as
    // before, exactly like `SalonStaffProfileScreen`'s own `maybeWhen`
    // default — the guard never flashes over a healthy load. Since
    // [SalonStaffRole] only has two values, a resolved non-admin IS a master.
    final bool isNotAdmin =
        member != null && member.role != SalonStaffRole.admin;

    final bool isOwner = ref.watch(isSalonOwnerProvider);
    final String? currentUserId = ref.watch(currentUserProvider)?.id;

    // D3 (Phase 308) — the owner-and-not-self predicate, computed ONCE and
    // shared by both the admin remove row (this file, below) and the master
    // remove row (`canManageMaster`, immediately after) — REUSE-FIRST inside
    // a single file, not only across files. `member?.userId` (safe
    // navigation, not the `isNotAdmin`-promoted form) because this is read
    // on the ADMIN branch too, where `member` is legitimately null while the
    // roster is still loading — exactly the case the ROLE GUARD comment
    // above already carves out, so a null `member` must not gate the row
    // off. `null != currentUserId` is `true` for any signed-in viewer, so
    // the loading window renders the row exactly as it did before this
    // gate existed.
    final bool canManageStaff = isOwner && member?.userId != currentUserId;

    // D3/D4 (Phase 307) — the master branch's OWN gate, evaluated only when
    // it is reachable at all (`isNotAdmin`). Owner-only, and never against
    // the owner's own master row.
    //
    // CAREFUL — `isNotAdmin` must stay the LEFTMOST conjunct here: it is
    // what promotes the nullable `member` (via its own `member != null &&
    // …` definition above) so every bare `member` use later in `build()`
    // (`member.userId` below, `_confirmRemoveMaster(member)`, …) compiles
    // without a null check at each call site. `canManageStaff` itself reads
    // `member` through `?.` and needs no such promotion — it does not carry
    // it either. An NPE was already introduced and fixed on this exact
    // expression earlier today; do not drop `isNotAdmin` or reorder it
    // after `canManageStaff`.
    final bool canManageMaster = isNotAdmin && canManageStaff;

    // mobile-security LOW fix (2026-09-05) — the two denial CAUSES need
    // different copy. `staffSettingsMasterOwnerOnlyBody`'s "ask the owner"
    // phrasing is correct for a non-owner viewer, but is factually wrong
    // when the viewer IS the owner looking at their own master row — there
    // is nobody else for them to ask. `isOwnRow` is `true` only in that
    // second case; a non-owner viewing someone else's row, or a non-owner
    // who happens to share an id with the row (cannot occur for a real
    // master self-view, since that master would need `isOwner == true` to
    // reach here), both fall through to the existing "owner only" copy.
    final bool isOwnRow =
        isNotAdmin && isOwner && member.userId == currentUserId;

    final Widget body;
    if (member == null || member.role == SalonStaffRole.admin) {
      body = Column(
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

          // D3/D4 (Phase 308) — the hairline and the terminal row are a
          // PAIR: a divider terminating nothing is a visual bug, so both are
          // omitted together for a non-owner (or the owner's own row —
          // self-removal is a 403 on the backend and always was, but the
          // object it now destroys is an account). No denial copy here,
          // unlike the master branch's `SalonNoticeCard`: the admin branch
          // still has the move/convert rows above, so the screen is never
          // left empty and needs no explanation (D4).
          if (canManageStaff) ...<Widget>[
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
        ],
      );
    } else if (!canManageMaster) {
      // D3/D4 — not the owner, or the owner's own master row. `member` is
      // promoted non-null here (the `if` above ruled out both `null` and
      // `admin`). The outer key stays the same for both sub-cases (only the
      // copy differs) — every existing "the notice renders" assertion keys
      // off `staff-settings-master-owner-only` regardless of which sentence
      // is showing.
      body = SalonNoticeCard(
        key: const Key('staff-settings-master-owner-only'),
        icon: Icons.lock_outline,
        title: isOwnRow
            ? l10n.staffSettingsMasterSelfTitle
            : l10n.staffSettingsMasterOwnerOnlyTitle,
        body: isOwnRow
            ? l10n.staffSettingsMasterSelfBody
            : l10n.staffSettingsMasterOwnerOnlyBody,
      );
    } else {
      // The one master action this screen has today (D1) — single row, no
      // context subheading, no hairline; see this file's header for why the
      // master branch is deliberately this minimal.
      body = _reveal(
        _anim0,
        SettingsRow(
          key: const Key('row-master-remove'),
          icon: Icons.person_remove_outlined,
          label: l10n.staffSettingsRemoveMaster,
          destructive: true,
          showChevron: false,
          // D2 — a resolved master entry with no `masterId` is a data
          // anomaly; the row stays disabled rather than ever sending a
          // guessed id.
          enabled: member.masterId != null,
          loading: _removing,
          onTap: () => _confirmRemoveMaster(member),
        ),
      );
    }

    return SectionScaffold(
      title: l10n.settingsTitle,
      backIcon: Icons.close_rounded,
      backSemanticLabel: l10n.settingsHubClose,
      backKey: const Key('btn-close-admin-settings'),
      onBack: _close,
      body: body,
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
