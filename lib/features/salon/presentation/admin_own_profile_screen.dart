// Phase 21.16 — Admin Own Profile Screen.
//
// The `SALON_ADMIN`'s own FIRST-PERSON profile — "me", as distinct from
// `SalonStaffProfileScreen` (Phase 21.5, which views SOMEONE ELSE, including
// an admin, as MANAGED by an owner) and from every salon-management surface
// (which manages a salon). It is the «Профіль» tab of `SalonShellScreen`'s
// admin branch — the branch that until this phase fell through to
// `SalonShellTabPlaceholder` — and is also reachable stand-alone at
// [RouteNames.adminOwnProfile].
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// admin_own_profile_screen.dart` — the approved preview, transcribed onto the
// shipped widgets rather than onto the preview's own `staff_profile_widgets
// .dart` (which exists only in the preview app). See REUSE below.
//
// ── BODY ──────────────────────────────────────────────────────────────────
//   1 identity — avatar, name, «Адмін» [RoleChip], optional
//     `professionalTitle` sub-line (an admin can set one via `PATCH
//     /users/me`, same as a master — backend `ccf2a41` covers all non-CLIENT
//     roles).
//   2 «Салон» — the ONE salon this admin belongs to, as a read-only
//     affiliation card. Absent entirely when it cannot be resolved (see THE
//     SALON SECTION below).
//   3 «Контакти» — phone ONLY, and only when one is on file. There is
//     deliberately no Instagram tile: an Instagram handle is a public
//     marketing surface, not something a staff member's internal profile
//     shows — the same rule `salon_staff_profile_screen.dart` already applies
//     to a colleague's card, and the preview draws it that way here too.
//
// Deliberately ABSENT, all three matching how the preview and Phase 21.5 draw
// an admin: no stats row, no bio, no service categories. Admins are
// administrative staff, not service providers, so every one of those would
// print a permanent em-dash.
//
// ── REUSE ─────────────────────────────────────────────────────────────────
// Nothing here is new chrome. [ProfileScaffold] supplies the top bar/back/
// trailing/scroll body (so this screen's header sits at the identical
// position to the owner's), [NeumorphicIconButton] the tune action,
// [StaffIdentityCard] the identity card PROMOTED in this phase out of the
// owner and staff screens, [SalonAffiliationCard] the salon card, [ContactTile]
// the phone row, and [SkeletonShimmerScope]/[SkeletonBlock] the loading state.
// The one genuinely new widget is [SalonAffiliationCard]; its own header
// records why [SalonHubCard] could not be widened into it.
//
// ── THE DATA, AND WHY THERE IS NO NEW PROVIDER ────────────────────────────
// The phase doc proposes two new providers. Both already exist under other
// names, and this screen reuses them verbatim rather than adding a third and
// fourth read of the same two endpoints:
//
//   • IDENTITY — `clientEditProfileProvider`, the keepAlive `GET /users/me` →
//     [User] read. Its name says CLIENT (it was introduced for the client edit
//     screens) but its `build()` requires only an `Authenticated` session and
//     the endpoint is `isAuthenticated()`-gated backend-side, so it is
//     role-agnostic in fact. `owner_own_profile_notifier.dart` composes the
//     SAME provider for the same reason; the phase doc's own Step 1 says to
//     alias it if it exists, and it does.
//   • SALON — TWO paths, one per host, because the right read differs (see
//     [AdminOwnProfileScreen.hostSalonId] and `_AdminSalonSection`):
//     – INSIDE `SalonShellScreen`, `salonManagementProfileProvider(salonId)`
//       keyed on the SHELL'S OWN `salonId` (handed down as `hostSalonId`, not
//       re-derived from `User.salonId`). Slot 0 hosts
//       `SalonManagementProfileScreen` for that exact key and is built on the
//       shell's first frame, so this watch resolves against an already-warm
//       family member and issues NO request at all — and an admin editing the
//       salon name updates both surfaces at once instead of leaving this tab
//       stale.
//     – ON THE STAND-ALONE route there is no host and nothing warm, so the
//       management family would cold-start and fire `GET /salons/{id}/staff`
//       — the unmasked staff-contacts roster — alongside the salon read, for
//       a value this screen destructures away unread. That path takes
//       `salonDetailProvider(salonId)`, the single `GET /salons/{id}`
//       instead (mobile-perf + mobile-security LOW, 2026-09-05).
//     The admin is authorized for both endpoints on their own salon (`GET
//     /salons/{id}/staff` is owner+admin scoped, and `salonManageGuard` binds
//     an admin to `User.salonId` exactly).
//
// ── THE SALON SECTION DEGRADES, IT DOES NOT ERROR ─────────────────────────
// Only the identity read can put this screen into an error state — without a
// name and contacts there is no profile to render. The salon card is
// OPTIONAL: a missing `User.salonId`, an unresolved read, or a failed one all
// render the section ABSENT rather than erroring the whole tab. Erroring an
// entire profile because a context card raced is a strictly worse failure than
// omitting it — the same rule `owner_own_profile_notifier.dart` states for the
// owner-as-master section.
//
// ── THE TRAILING TUNE ─────────────────────────────────────────────────────
// Rendered VISIBLE BUT INERT (`enabled: false`): its destination, the Phase
// 21.17 Admin Personal Settings screen, is unbuilt. The phase doc's
// `context.push(RouteNames.adminSettings)` cannot be honoured yet — that
// constant does not exist. This is deliberately NOT a route stub (dead weight
// the router-shadowing tests would then have to police) and NOT a snackbar (a
// fake acknowledgement); it is the identical treatment
// `owner_own_profile_screen.dart` gives its own unbuilt Phase 21.15 target.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/reveal_transition.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:beautica_mobile/shared/widgets/staff_identity_card.dart';

import '../../master/presentation/widgets/profile_avatar.dart';
import '../../master/presentation/widgets/profile_scaffold.dart';
import '../application/salon_detail_notifier.dart';
import '../application/salon_management_profile_notifier.dart';
import '../domain/salon.dart';
import 'widgets/salon_affiliation_card.dart';

/// The signed-in `SALON_ADMIN`'s own profile.
class AdminOwnProfileScreen extends ConsumerStatefulWidget {
  const AdminOwnProfileScreen({
    super.key,
    this.embedded = false,
    this.visible = true,
    this.hostSalonId,
    this.onSalonTap,
  });

  /// `true` when hosted as the admin shell's «Профіль» tab root, where there
  /// is nothing to pop — the back chevron is dropped and the shell supplies
  /// its own `SalonBottomNav`. `false` for the stand-alone
  /// [RouteNames.adminOwnProfile] push, which keeps a working back button.
  final bool embedded;

  /// Whether this instance is the one the user is actually looking at.
  ///
  /// Defaults to `true`, so the stand-alone route and every test that pumps
  /// this screen directly behave exactly as before. `SalonShellScreen` passes
  /// `stackSlot == 2` — the SAME hand-off it makes to
  /// [OwnerOwnProfileScreen.visible], for the same two defects, because a raw
  /// `IndexedStack` sets neither `Offstage` nor `TickerMode` on its non-current
  /// children: an off-screen slot still builds, still lays out, and still
  /// TICKS. See that field's doc for the full statement; in short this flag
  /// gates
  ///
  ///  • THE ENTRANCE — the one-shot staggered reveal must be spent on a
  ///    VISIBLE frame, not burned off-screen while the user is on another tab;
  ///  • THE PII GUARD — this screen renders the admin's own phone, and
  ///    `IndexedStack` never disposes a visited child, so an
  ///    `initState`-acquire / `dispose`-release pair would latch the iOS
  ///    app-switcher blur across every other salon tab for the rest of the
  ///    shell visit.
  final bool visible;

  /// The salon id the HOST has already warmed, when there is a host.
  ///
  /// `SalonShellScreen` passes its own `widget.salonId` — the go_router PATH
  /// PARAM — which is the SAME string slot 0 keys
  /// `salonManagementProfileProvider` on. That identity is the whole point
  /// (mobile-perf LOW, 2026-09-05): deriving the key independently from
  /// `User.salonId` (the `GET /users/me` field) instead meant any casing or
  /// formatting divergence between the two UUID strings resolved a DIFFERENT
  /// family element, cold-starting a second copy of the salon + roster reads
  /// inside the shell where the correct cost is zero.
  ///
  /// `null` — the default, and what the stand-alone [RouteNames.adminOwnProfile]
  /// route passes — means "no warm host". The section then falls back to
  /// `User.salonId` for the key AND reads through [salonDetailProvider], the
  /// single-endpoint `GET /salons/{id}`, instead of the management family: with
  /// nothing warm to reuse there is no benefit left to pay the paired roster
  /// read for, and that roster is the unmasked staff-contacts list this screen
  /// never renders.
  final String? hostSalonId;

  /// Optional "take me to this salon" handler for the affiliation card.
  ///
  /// The shell passes its own «Салон» nav selection here (phase doc Step 3),
  /// which is the only context in which a destination exists — the stand-alone
  /// route has no shell tab to move. Null (the default) renders the card
  /// INERT, which is also exactly what the approved preview draws.
  final VoidCallback? onSalonTap;

  @override
  ConsumerState<AdminOwnProfileScreen> createState() =>
      _AdminOwnProfileScreenState();
}

class _AdminOwnProfileScreenState extends ConsumerState<AdminOwnProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Pre-built staggered-entrance animations (the shipped mobile-perf pattern —
  // see `master_profile_screen.dart`'s own note) so build() never allocates a
  // CurvedAnimation/Tween per frame. Three sections: identity / salon /
  // contacts. The intervals are the approved preview's own
  // (`admin_own_profile_screen.dart:120,154,176`), not the owner screen's
  // five-section split.
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;

  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws.
  late final ScreenProtectionManager _screenProtection;

  /// Whether THIS instance currently holds a [ScreenProtectionManager]
  /// reference. Tracked explicitly so acquire/release stay strictly paired
  /// across any number of visibility flips and one final [dispose].
  bool _protectionHeld = false;

  @override
  void initState() {
    super.initState();
    // This screen renders the admin's own phone — the same PII class every
    // other profile screen guards. Held for as long as this screen is VISIBLE
    // rather than as long as it is MOUNTED — see
    // [AdminOwnProfileScreen.visible] for why the two differ inside an
    // `IndexedStack`.
    _screenProtection = ref.read(screenProtectionProvider);
    _syncScreenProtection();
    _controller = AnimationController(
      vsync: this,
      // The preview's own 1000 ms run. Its three intervals below are stated as
      // fractions OF this duration, so the two travel together.
      duration: const Duration(milliseconds: 1000),
    );
    _anim0 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.06, 0.60, curve: Curves.easeOutCubic),
    );
    _anim1 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.20, 0.78, curve: Curves.easeOutCubic),
    );
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.34, 1.0, curve: Curves.easeOutCubic),
    );
    const Offset slideBegin = Offset(0, 0.04);
    _slide0 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim0);
    _slide1 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim1);
    _slide2 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim2);
  }

  @override
  void didUpdateWidget(covariant AdminOwnProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    _syncScreenProtection();
    // Becoming visible is the moment the entrance is ALLOWED to run, but it is
    // started from `build()` (which runs again on this same frame, since the
    // shell rebuilt to change `visible`) rather than here, where `_controller`
    // may not have a frame to animate into yet.
    //
    // Going off-screen mid-reveal has to be handled HERE, though: `stop()`
    // freezes a running entrance instead of leaving a `Ticker` scheduling a
    // frame every vsync for up to a second, driving three transition pairs on
    // a subtree the `IndexedStack` is not painting. It does NOT reset `value`,
    // so [_startReveal] resumes from where it stopped when the tab comes back
    // — see that method for the guard that makes resuming possible.
    if (!widget.visible) _controller.stop();
  }

  /// Brings the [ScreenProtectionManager] refcount in line with
  /// [AdminOwnProfileScreen.visible]. Idempotent: a repeated call in the same
  /// visibility state is a no-op, so the acquire/release pair can never drift.
  void _syncScreenProtection() {
    if (widget.visible == _protectionHeld) return;
    if (widget.visible) {
      _screenProtection.acquire();
    } else {
      _screenProtection.release();
    }
    _protectionHeld = widget.visible;
  }

  @override
  void dispose() {
    // Only if still held — an instance disposed while off-screen released its
    // reference at the visibility flip and must not double-release.
    if (_protectionHeld) _screenProtection.release();
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startReveal() {
    // The one-shot entrance must be spent on a VISIBLE frame. Off-screen this
    // is a no-op, so the entrance survives until the tab is actually shown.
    //
    // `isCompleted` rather than `value == 0`: [didUpdateWidget] parks a
    // running reveal at a FRACTIONAL value when the tab goes off-screen, and a
    // `value == 0` guard could never leave that state — the entrance would
    // freeze half-faded for the rest of the shell visit. This form keeps both
    // properties that matter: a finished entrance never replays, and an
    // untouched one still animates from 0 rather than jumping to 1.
    if (!widget.visible) return;
    if (!_controller.isAnimating && !_controller.isCompleted) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<User> async = ref.watch(clientEditProfileProvider);

    return ProfileScaffold(
      title: l10n.adminOwnProfileTitle,
      showBack: !widget.embedded,
      trailing: NeumorphicIconButton(
        key: const Key('btn-admin-own-profile-settings'),
        icon: Icons.tune_rounded,
        semanticLabel: l10n.adminOwnProfileSettingsSemanticLabel,
        // Phase 21.17 is unbuilt — the control is present but inert. See the
        // file header's THE TRAILING TUNE note for why this is neither a
        // route stub nor a snackbar.
        enabled: false,
        onTap: () {},
      ),
      // Pull-to-refresh. `clientEditProfileProvider` is a keepAlive singleton,
      // so it is the invalidation target itself; the salon card follows from
      // its own `ref.watch` edge and is refreshed by whoever owns that family
      // (the shell's slot 0), never from here — invalidating another surface's
      // loader out from under it is not this tab's business.
      //
      // Riverpod 3.x: `invalidate` retains `.value`, so the previous profile
      // stays on screen through the refetch — never gate this UI on
      // `value == null`.
      onRefresh: () async {
        ref.invalidate(clientEditProfileProvider);
        await ref.read(clientEditProfileProvider.future);
      },
      // mobile-perf LOW (2026-09-05) — [AdminOwnProfileScreen.visible] gated the
      // ENTRANCE controller only, which this State owns and stops itself. It
      // did NOT reach the LOADING state: [SkeletonShimmerScope] owns its own
      // `..repeat(reverse: true)` controller, and a raw `IndexedStack` inserts
      // neither `Offstage` nor `TickerMode`, so tapping «Профіль» and away
      // again before `GET /users/me` returns left a shimmer scheduling a vsync
      // frame every ~16 ms on a subtree the stack never paints. `TickerMode`
      // mutes every ticker BELOW it — the skeleton's shimmer today, and any
      // future implicit animation in the loaded body — without touching
      // `_controller`, whose ticker is created by this State ABOVE this point
      // and stays under [didUpdateWidget]'s explicit `stop()`/resume control.
      child: TickerMode(
        enabled: widget.visible,
        child: async.when(
          loading: () => const _AdminProfileSkeleton(),
          error: (Object e, _) => ErrorState(
            failure: e is Failure ? e : UnknownFailure(cause: e),
            onRetry: () => ref.invalidate(clientEditProfileProvider),
          ),
          data: (User admin) {
            _startReveal();
            return _AdminProfileBody(
              admin: admin,
              hostSalonId: widget.hostSalonId,
              onSalonTap: widget.onSalonTap,
              anim0: _anim0,
              anim1: _anim1,
              anim2: _anim2,
              slide0: _slide0,
              slide1: _slide1,
              slide2: _slide2,
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _AdminProfileBody — loaded state
// ---------------------------------------------------------------------------

class _AdminProfileBody extends StatelessWidget {
  const _AdminProfileBody({
    required this.admin,
    required this.hostSalonId,
    required this.onSalonTap,
    required this.anim0,
    required this.anim1,
    required this.anim2,
    required this.slide0,
    required this.slide1,
    required this.slide2,
  });

  final User admin;

  /// See [AdminOwnProfileScreen.hostSalonId] — non-null selects BOTH the
  /// family key and the warm management read; null selects the stand-alone
  /// single-salon read keyed on `User.salonId`.
  final String? hostSalonId;

  final VoidCallback? onSalonTap;

  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final String displayName = <String?>[admin.firstName, admin.lastName]
        .whereType<String>()
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .join(' ');
    final String? title = admin.professionalTitle?.trim();
    final String? professionalTitle = (title != null && title.isNotEmpty)
        ? title
        : null;

    // The host's key WINS when there is a host — see
    // [AdminOwnProfileScreen.hostSalonId]. `User.salonId` is only the
    // stand-alone fallback, where nothing else knows which salon this is.
    //
    // mobile-security LOW (2026-09-05) — but the host key only gets to win
    // when it AGREES with the viewer's own binding. Until now the whole
    // ownership guarantee lived in `salonManageGuard` (`app_router.dart`), a
    // different file: this widget took `hostSalonId` on trust, so mounting
    // `AdminOwnProfileScreen(hostSalonId: …)` off any route that is not bound
    // to the viewer's own salon would render ANOTHER salon's name, logo and
    // address on the viewer's own profile page, silently and with no error.
    // A widget that can leak an identity has to defend itself rather than
    // depend on a guard three layers up, so a disagreement now:
    //   * trips an [assert] in debug/test — the developer who wired the new
    //     route sees it on the first pump, not in production; and
    //   * falls back to `selfKey` in release, so the WORST case is a screen
    //     showing the viewer's real salon (the stand-alone behaviour) instead
    //     of a foreign one.
    // `warmedByHost` follows the key that actually won: on a mismatch the
    // management family is warm for the HOST's id, not the one being
    // rendered, so claiming warmth there would just mislabel a cold read.
    final String? hostKey = hostSalonId?.trim();
    final String? selfKey = admin.salonId?.trim();
    final bool hasHostKey = hostKey != null && hostKey.isNotEmpty;
    final bool hasSelfKey = selfKey != null && selfKey.isNotEmpty;
    // CASE-INSENSITIVE, deliberately. Salon ids are UUIDs, so `a-1` and `A-1`
    // are the SAME salon rendered differently — and the sibling mobile-perf
    // fix in this very screen exists precisely because that divergence used to
    // split `salonManagementProfileProvider` into two family elements (see
    // `admin_own_profile_screen_test.dart`'s «Салон» read group, whose fixture
    // is case-divergent on purpose). Comparing raw would turn that documented
    // benign divergence into an ownership violation and undo the perf fix.
    // What this is looking for is a host pointing at a DIFFERENT salon.
    final bool hostDisagrees =
        hasHostKey &&
        hasSelfKey &&
        hostKey.toLowerCase() != selfKey.toLowerCase();
    assert(
      !hostDisagrees,
      'AdminOwnProfileScreen was given hostSalonId "$hostKey" but the signed-in '
      'admin is bound to salon "$selfKey". This screen renders the viewer\'s OWN '
      'profile, so the two must be the same salon; a mismatch means it was '
      'mounted off a route that is not ownership-bound to the viewer (the '
      'binding otherwise lives only in salonManageGuard, app_router.dart). '
      'Falling back to the admin\'s own salonId. Bind the route, or mount the '
      'stand-alone form with hostSalonId: null.',
    );
    final bool hostWins = hasHostKey && !hostDisagrees;
    final String? affiliatedSalonId = hostWins
        ? hostKey
        : hasSelfKey
        ? selfKey
        : hasHostKey
        ? hostKey
        : null;
    final bool warmedByHost = hostWins;

    final String? phone = admin.phoneNumber?.trim();
    // Phone-only contacts, and the SECTION is omitted when there is no number
    // — the preview's own rule (`admin_own_profile_screen.dart:174`) and
    // `salon_staff_profile_screen.dart`'s. This deliberately differs from
    // `owner_own_profile_screen.dart`, which renders a permanent em-dash tile:
    // that screen always has a contacts block because it may also carry
    // Instagram, whereas here an em-dash would be the section's only content.
    final String? phoneValue = (phone != null && phone.isNotEmpty)
        ? phone
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1 — identity.
        RevealTransition(
          key: const Key('admin-own-profile-reveal-0'),
          fade: anim0,
          slide: slide0,
          child: StaffIdentityCard(
            displayName: displayName,
            roleLabel: l10n.adminOwnProfileRoleLabel,
            professionalTitle: professionalTitle,
            nameKey: const Key('admin-own-profile-name'),
            roleChipKey: const Key('admin-own-profile-role-chip'),
            professionalTitleKey: const Key(
              'admin-own-profile-professional-title',
            ),
          ),
        ),

        // 2 — «Салон». Absent when the admin carries no salon id at all; the
        // section widget itself renders nothing while its read is unresolved
        // or failed (see the file header).
        if (affiliatedSalonId != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xl),
          RevealTransition(
            key: const Key('admin-own-profile-reveal-1'),
            fade: anim1,
            slide: slide1,
            child: _AdminSalonSection(
              salonId: affiliatedSalonId,
              warmedByHost: warmedByHost,
              onSalonTap: onSalonTap,
            ),
          ),
        ],

        // 3 — «Контакти». Phone only, and only when set.
        if (phoneValue != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xl),
          RevealTransition(
            key: const Key('admin-own-profile-reveal-2'),
            fade: anim2,
            slide: slide2,
            child: Column(
              key: const Key('admin-own-profile-contacts'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    bottom: VelvetSpacing.xs,
                  ),
                  child: Text(
                    l10n.masterContactsLabel,
                    style: VelvetText.sectionLabel(),
                  ),
                ),
                ContactTile(
                  key: const Key('admin-own-profile-contact-phone'),
                  icon: Icons.phone_outlined,
                  value: phoneValue,
                  semanticLabel: l10n.masterPhoneSemantics,
                  // Dialling out is not in this phase's scope — mirrors the
                  // identical phone tile on `owner_own_profile_screen.dart`
                  // and `salon_staff_profile_screen.dart`.
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _AdminSalonSection
// ---------------------------------------------------------------------------

/// «Салон» — the label plus the [SalonAffiliationCard] for the one salon this
/// admin belongs to.
///
/// Renders NOTHING (label included) while the salon read is unresolved or has
/// failed: this is an optional context section, so an absent card is the
/// correct degradation and a header sitting above nothing would be worse than
/// no header.
///
/// WHICH read depends on [warmedByHost] — see
/// [AdminOwnProfileScreen.hostSalonId]:
///
///  • `true` (inside `SalonShellScreen`) — `salonManagementProfileProvider
///    (salonId)`, on the SAME key slot 0 already warmed. Zero requests, and an
///    in-shell salon edit updates this card and the management screen together
///    instead of leaving one stale.
///  • `false` (the stand-alone `/profile/admin` route) — [salonDetailProvider],
///    the single `GET /salons/{id}`. There is nothing warm to reuse there, so
///    the management family would cold-start and pay for a staff roster this
///    screen never renders (mobile-perf + mobile-security LOW, 2026-09-05).
class _AdminSalonSection extends ConsumerWidget {
  const _AdminSalonSection({
    required this.salonId,
    required this.warmedByHost,
    required this.onSalonTap,
  });

  final String salonId;

  /// Whether a host (the salon shell) has already warmed
  /// `salonManagementProfileProvider(salonId)` on THIS key.
  final bool warmedByHost;

  final VoidCallback? onSalonTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // `.value`, not a `when`, on either branch: it collapses "still loading"
    // and "failed" to the same `null`, which is exactly the two-into-one
    // degradation this section wants — no spinner, no error box, no layout
    // jump.
    //
    // The branch is on a `final` field of this widget, so it is stable for the
    // life of the element and never flip-flops a subscription mid-flight.
    final Salon? salon = warmedByHost
        ? ref.watch(salonManagementProfileProvider(salonId)).value?.$1
        : ref.watch(salonDetailProvider(salonId)).value;
    if (salon == null) return const SizedBox.shrink();

    return Column(
      key: const Key('admin-own-profile-salon'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
          child: Text(
            l10n.adminOwnProfileSalonSectionLabel,
            style: VelvetText.sectionLabel(),
          ),
        ),
        SalonAffiliationCard(
          key: const Key('admin-own-profile-salon-card'),
          salon: salon,
          onTap: onSalonTap,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _AdminProfileSkeleton — loading state
// ---------------------------------------------------------------------------

/// Neumorphic shimmer skeleton matching [_AdminProfileBody]'s layout.
///
/// It renders all THREE sections because that is the common case for a real
/// admin — they always belong to a salon, and an invite carries a phone — so
/// the skeleton settles into the real layout instead of collapsing upward on
/// arrival.
class _AdminProfileSkeleton extends StatelessWidget {
  const _AdminProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 1 — identity card.
          NeumorphicCard(
            color: Color(0xFFEDE4D5),
            padding: EdgeInsets.all(VelvetSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SkeletonBlock(width: 80, height: 80, circle: true),
                SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SkeletonBlock(width: 140, height: 16),
                      SizedBox(height: VelvetSpacing.xs + 2),
                      SkeletonBlock(width: 120, height: 24, radius: 999),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 2 — «Салон» label + affiliation card.
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: SkeletonBlock(width: 60, height: 13),
          ),
          SkeletonBlock(
            width: double.infinity,
            height: 76,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 3 — «Контакти» label + 1 tile.
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: SkeletonBlock(width: 90, height: 13),
          ),
          SkeletonBlock(
            width: double.infinity,
            height: 60,
            radius: VelvetRadii.field,
          ),
        ],
      ),
    );
  }
}
