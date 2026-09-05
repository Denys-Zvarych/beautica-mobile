// Phase 21.14 — Owner Own Profile Screen.
//
// The `SALON_OWNER`'s own FIRST-PERSON profile — "me", as distinct from every
// salon-management surface (which manages a salon or another staff member) and
// from `SalonStaffProfileScreen` (Phase 21.5, which views SOMEONE ELSE). It is
// the «Профіль» tab of `SalonShellScreen`'s owner branch, and is also reachable
// stand-alone at [RouteNames.ownerOwnProfile].
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// owner_own_profile_screen.dart` — the approved preview, transcribed onto the
// shipped widgets rather than onto the preview's own `staff_profile_widgets
// .dart` (which exists only in the preview app). See REUSE below.
//
// ── BODY ──────────────────────────────────────────────────────────────────
//   1 identity — avatar, name, «Власник салону» [RoleChip], optional
//     `professionalTitle` sub-line. NO rating row: an owner's identity card
//     stays the owner's own even when they also work as a master; the rating
//     surfaces in the stats row below instead (the preview passes
//     `hasReviews: false` here for exactly this reason).
//   2 stats  ┐
//   3 bio    ├─ MASTER ONLY — rendered only when the owner also performs
//   4 categories ┘ services. See THE MASTER GATE.
//   5 contacts — phone always, Instagram only when set. There is deliberately
//     NO salon-affiliation card: an owner can own several salons, so no single
//     salon represents them; those live in the «Мої салони» hub instead.
//
// ── REUSE ─────────────────────────────────────────────────────────────────
// Every leaf here is an already-shipped widget, used verbatim, exactly as
// `salon_staff_profile_screen.dart` (Phase 21.5) established for this screen
// family: [ProfileScaffold] chrome, [ProfileAvatar], [RoleChip], [StatTile],
// [ServicesStatTile], [RatingStar], [NeumorphicInset], [ContactTile],
// [ServiceCategoryCardList], [SkeletonShimmerScope]/[SkeletonBlock]. Nothing
// was forked, copied, or promoted for this screen — the shared set already
// covered it.
//
// ── THREE STAT TILES, NOT FOUR ────────────────────────────────────────────
// The preview's stats row has a fourth «Досвід» tile. There is no tenure /
// experience field on [Master], on `MasterDetailResponse`, or on any other
// DTO, so a fourth tile could only ever print a permanent em-dash or a
// fabricated number. It is dropped. The three surviving captions are the
// SHIPPED ones, already proven to fit at the NARROWER 4-up tile width on
// `master_profile_screen.dart`, so a 3-up row cannot regress them;
// `IntrinsicHeight` + `CrossAxisAlignment.stretch` and the
// `VelvetSpacing.sm` gutter are kept unchanged so this row keeps the same
// rhythm as every other stats row in the app — the width freed by the dropped
// tile goes into the TILES, not into the gutters.
//
// ── NO «УСІ ПОСЛУГИ» LINK, NO INTERACTIVE CATEGORY CARDS ──────────────────
// The preview's category section carries an «Усі послуги» link, and the
// master's own profile passes `interactive: true` so a card deep-links to
// `/services`. Both are omitted here because both resolve to the
// INDEPENDENT_MASTER's own service-management screen, which reads
// `GET /independent-masters/me/services` —
// `@PreAuthorize("hasRole('INDEPENDENT_MASTER')")`, i.e. a guaranteed 403 for
// a `SALON_OWNER`. A dead affordance is worse than an absent one, so the
// section renders as a read-only summary (`interactive: false`), matching
// `salon_staff_profile_screen.dart`'s own reasoning for the same call.
//
// ── THE MASTER GATE ───────────────────────────────────────────────────────
// Owned entirely by [ownerOwnProfileProvider] — see that file for the
// `hasMasterProfile` tri-state and for why a `/masters/me` 404 degrades the
// section to ABSENT instead of erroring the whole tab.
//
// ── THE TRAILING TUNE ─────────────────────────────────────────────────────
// Rendered VISIBLE BUT INERT (`enabled: false`): its destination, the Phase
// 21.15 Owner Settings Hub, is unbuilt. It is deliberately NOT a route stub
// (dead weight the router-shadowing tests would then have to police) and NOT a
// snackbar (a fake acknowledgement). The dim/absorb/semantics treatment is
// [NeumorphicIconButton]'s `enabled` parameter, which mirrors [SettingsRow]'s
// identical, already-shipped convention.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../master/presentation/widgets/profile_avatar.dart';
import '../../master/presentation/widgets/profile_scaffold.dart';
import '../../master/presentation/widgets/service_category_cards.dart';
import '../../master/presentation/widgets/services_stat_tile.dart';
import '../application/owner_own_profile_notifier.dart';

/// The signed-in `SALON_OWNER`'s own profile.
class OwnerOwnProfileScreen extends ConsumerStatefulWidget {
  const OwnerOwnProfileScreen({
    super.key,
    this.embedded = false,
    this.visible = true,
  });

  /// `true` when hosted as the owner shell's «Профіль» tab root, where there
  /// is nothing to pop — the back chevron is dropped and the shell supplies
  /// its own `SalonBottomNav`. `false` for the stand-alone
  /// [RouteNames.ownerOwnProfile] push, which keeps a working back button.
  final bool embedded;

  /// Whether this instance is the one the user is actually looking at.
  ///
  /// Defaults to `true`, so the stand-alone route and every test that pumps
  /// this screen directly behave exactly as before. `SalonShellScreen` passes
  /// `stackSlot == 2` (mobile-perf MEDIUM + LOW, 2026-08-31) because a raw
  /// `IndexedStack` gives its off-screen children NO signal of their own:
  /// Flutter wraps them in `Visibility(maintainState/Animation/Size/
  /// Interactivity: true)` (`basic.dart`), which — unlike a covered go_router
  /// route — sets neither `Offstage` nor `TickerMode`, so an off-screen child
  /// still builds, still lays out, and still TICKS. `master_profile_screen
  /// .dart` never needed this flag only because it is always a routed page.
  ///
  /// Two concrete defects this closes, both of them for the shell's slot 2:
  ///
  ///  • THE ENTRANCE. Tap «Профіль», then tap away before the loader resolves.
  ///    The screen stays mounted, so the `data:` branch still runs off-screen,
  ///    `_startReveal()` played the whole 950 ms staggered entrance on an
  ///    unpainted subtree AND burned its one-shot `_controller.value == 0`
  ///    guard — so the user's FIRST REAL VIEW of the tab had no entrance at
  ///    all. The reveal is now gated on this flag and fires on the first
  ///    VISIBLE build instead.
  ///  • THE PII GUARD. `IndexedStack` never disposes a visited child, so an
  ///    `initState`-acquire / `dispose`-release pair meant one visit to
  ///    «Профіль» latched the iOS app-switcher blur across every other salon
  ///    tab for the rest of the shell visit (the refcount only cleared on
  ///    logout's `reset()`). Protection now tracks visibility, so it is held
  ///    exactly while this screen's PII is on screen.
  final bool visible;

  @override
  ConsumerState<OwnerOwnProfileScreen> createState() =>
      _OwnerOwnProfileScreenState();
}

class _OwnerOwnProfileScreenState extends ConsumerState<OwnerOwnProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Pre-built staggered-entrance animations (the shipped mobile-perf pattern —
  // see `master_profile_screen.dart`'s own note) so build() never allocates a
  // CurvedAnimation/Tween per frame. Five sections: identity / stats / bio /
  // categories / contacts.
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final CurvedAnimation _anim3;
  late final CurvedAnimation _anim4;
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;
  late final Animation<Offset> _slide3;
  late final Animation<Offset> _slide4;

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
    // This screen renders the owner's own phone / Instagram — the same PII
    // class every other profile screen guards. Held for as long as this
    // screen is VISIBLE rather than as long as it is MOUNTED — see
    // [OwnerOwnProfileScreen.visible] for why the two differ inside an
    // `IndexedStack`.
    _screenProtection = ref.read(screenProtectionProvider);
    _syncScreenProtection();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _anim0 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.55, curve: Curves.easeOutCubic),
    );
    _anim1 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.68, curve: Curves.easeOutCubic),
    );
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.80, curve: Curves.easeOutCubic),
    );
    _anim3 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.40, 0.90, curve: Curves.easeOutCubic),
    );
    _anim4 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.50, 1.0, curve: Curves.easeOutCubic),
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
    _slide3 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim3);
    _slide4 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim4);
  }

  @override
  void didUpdateWidget(covariant OwnerOwnProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    _syncScreenProtection();
    // Becoming visible is also the moment the entrance is allowed to run: the
    // loader may well have resolved while this tab was off-screen, in which
    // case `build()`'s `data:` branch already ran (and was refused) at least
    // once. `build()` runs again on this same frame — the shell rebuilt to
    // change `visible` — so the reveal is started from there, not here, where
    // `_controller` may not have a frame to animate into yet.
  }

  /// Brings the [ScreenProtectionManager] refcount in line with
  /// [OwnerOwnProfileScreen.visible]. Idempotent: a repeated call in the same
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
    // reference at the visibility flip and must not double-release. (The
    // manager itself floors at zero, but relying on that would let a real
    // imbalance hide.)
    if (_protectionHeld) _screenProtection.release();
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startReveal() {
    // The one-shot entrance must be spent on a VISIBLE frame. Off-screen this
    // is a no-op, so the `_controller.value == 0` guard survives until the tab
    // is actually shown — see [OwnerOwnProfileScreen.visible].
    if (!widget.visible) return;
    if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<OwnerOwnProfileData> async = ref.watch(
      ownerOwnProfileProvider,
    );

    return ProfileScaffold(
      title: l10n.ownerOwnProfileTitle,
      showBack: !widget.embedded,
      trailing: NeumorphicIconButton(
        key: const Key('btn-owner-own-profile-settings'),
        icon: Icons.tune_rounded,
        semanticLabel: l10n.ownerOwnProfileSettingsSemanticLabel,
        // Phase 21.15 is unbuilt — the control is present but inert. See the
        // file header's THE TRAILING TUNE note for why this is neither a
        // route stub nor a snackbar.
        enabled: false,
        onTap: () {},
      ),
      // Pull-to-refresh. Invalidating [ownerOwnProfileProvider] alone would
      // NOT refetch anything: both reads it composes are `keepAlive`
      // singletons, so a rebuilt body would simply re-await their retained
      // values. The two upstreams are therefore the invalidation targets, and
      // the downstream rebuild follows from the `ref.watch` edges.
      //
      // Riverpod 3.x: `invalidate` retains `.value`, so the previous profile
      // stays on screen through the refetch — never gate this UI on
      // `value == null`.
      onRefresh: () async {
        ref.invalidate(clientEditProfileProvider);
        ref.invalidate(masterProfileProvider);
        await ref.read(ownerOwnProfileProvider.future);
      },
      child: async.when(
        loading: () => const _OwnerProfileSkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          // Only the `/users/me` read can land here (see the provider), so
          // that is the one upstream retry has to clear.
          onRetry: () => ref.invalidate(clientEditProfileProvider),
        ),
        data: (OwnerOwnProfileData data) {
          _startReveal();
          return _OwnerProfileBody(
            owner: data.owner,
            master: data.master,
            anim0: _anim0,
            anim1: _anim1,
            anim2: _anim2,
            anim3: _anim3,
            anim4: _anim4,
            slide0: _slide0,
            slide1: _slide1,
            slide2: _slide2,
            slide3: _slide3,
            slide4: _slide4,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _OwnerProfileBody — loaded state
// ---------------------------------------------------------------------------

class _OwnerProfileBody extends StatelessWidget {
  const _OwnerProfileBody({
    required this.owner,
    required this.master,
    required this.anim0,
    required this.anim1,
    required this.anim2,
    required this.anim3,
    required this.anim4,
    required this.slide0,
    required this.slide1,
    required this.slide2,
    required this.slide3,
    required this.slide4,
  });

  final User owner;

  /// The owner-as-master section, or `null` when the owner does not perform
  /// services (or their master row could not be resolved — see
  /// `owner_own_profile_notifier.dart`).
  final OwnerMasterSection? master;

  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<double> anim3;
  final Animation<double> anim4;
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;
  final Animation<Offset> slide3;
  final Animation<Offset> slide4;

  static Widget _reveal(
    Animation<double> fade,
    Animation<Offset> slide,
    Widget child,
  ) => RepaintBoundary(
    child: FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final String displayName = <String?>[owner.firstName, owner.lastName]
        .whereType<String>()
        .map((String part) => part.trim())
        .where((String part) => part.isNotEmpty)
        .join(' ');
    final String? title = owner.professionalTitle?.trim();
    final String? professionalTitle = (title != null && title.isNotEmpty)
        ? title
        : null;

    final String? instagram = owner.instagram?.trim();
    final String? instagramValue = (instagram != null && instagram.isNotEmpty)
        ? instagram
        : null;

    final OwnerMasterSection? section = master;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1 — identity. No rating row here even when the owner works as a
        // master (see the file header) — the chip stays «Власник салону».
        _reveal(
          anim0,
          slide0,
          NeumorphicCard(
            color: const Color(0xFFEDE4D5),
            padding: const EdgeInsets.all(VelvetSpacing.md),
            // [RoleChip] uses [NeumorphicInset], whose RepaintBoundary can
            // paint near the card's rounded corners — same reason
            // `master_profile_screen.dart` opts its identity card into
            // ClipRRect and leaves every other card at the default.
            clipContent: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const ProfileAvatar(),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        displayName,
                        key: const Key('owner-own-profile-name'),
                        style: VelvetText.displayName(),
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: VelvetSpacing.xs + 2),
                      RoleChip(
                        key: const Key('owner-own-profile-role-chip'),
                        label: l10n.masterRoleSalonOwner,
                        icon: Icons.auto_awesome_rounded,
                      ),
                      // The self-declared title sits UNDER the role chip
                      // rather than replacing its label (which is what
                      // `master_profile_screen.dart` does): «Власник салону»
                      // is the fact this card exists to state, so the title
                      // supplements it instead of displacing it.
                      if (professionalTitle != null) ...<Widget>[
                        const SizedBox(height: VelvetSpacing.xs),
                        Text(
                          professionalTitle,
                          key: const Key(
                            'owner-own-profile-professional-title',
                          ),
                          style: VelvetText.feedbackMutedXs,
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // 2/3/4 — the owner-as-master sections. Absent entirely when the owner
        // performs no services.
        if (section != null) ...<Widget>[
          _reveal(
            anim1,
            slide1,
            _OwnerStatsRow(master: section.$1, services: section.$2),
          ),
          const SizedBox(height: VelvetSpacing.xl),
          ..._buildBio(context, l10n, section.$1),
          _reveal(anim3, slide3, _OwnerCategoriesSection(services: section.$2)),
          const SizedBox(height: VelvetSpacing.xl),
        ],

        // 5 — contacts. Phone always (em-dash when unset, matching every other
        // profile screen); Instagram only when the owner set one.
        _reveal(
          anim4,
          slide4,
          Column(
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
                key: const Key('owner-own-profile-contact-phone'),
                icon: Icons.phone_outlined,
                value: owner.phoneNumber ?? StatTile.noDataGlyph,
                semanticLabel: l10n.masterPhoneSemantics,
                // Dialling out is not in this phase's scope — mirrors the
                // identical phone tile on `salon_staff_profile_screen.dart`.
                onTap: () {},
              ),
              if (instagramValue != null) ...<Widget>[
                const SizedBox(height: VelvetSpacing.sm),
                ContactTile(
                  key: const Key('owner-own-profile-contact-instagram'),
                  icon: Icons.alternate_email,
                  label: l10n.masterInstagramLabel,
                  value: instagramValue,
                  semanticLabel: l10n.masterInstagramLabel,
                  onTap: () {},
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// The «Про мене» block, or nothing when the owner wrote no bio.
  ///
  /// Returned as a list so the caller can splat it and keep the trailing
  /// spacer inside the same conditional — an empty bio must not leave a gap.
  List<Widget> _buildBio(
    BuildContext context,
    AppLocalizations l10n,
    Master master,
  ) {
    final String? raw = master.bio?.trim();
    if (raw == null || raw.isEmpty) return const <Widget>[];
    return <Widget>[
      _reveal(
        anim2,
        slide2,
        Column(
          key: const Key('owner-own-profile-bio'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
              child: Text(
                l10n.ownerOwnProfileBioLabel,
                style: VelvetText.sectionLabel(),
              ),
            ),
            NeumorphicInset(
              radius: VelvetRadii.card,
              child: Padding(
                padding: const EdgeInsets.all(VelvetSpacing.md + 2),
                child: Text(raw, style: VelvetText.bodyStrong()),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: VelvetSpacing.xl),
    ];
  }
}

// ---------------------------------------------------------------------------
// _OwnerStatsRow
// ---------------------------------------------------------------------------

/// Rating / reviews / services — THREE tiles, not the preview's four. See the
/// file header for why «Досвід» is dropped.
///
/// All three tiles are non-interactive here, unlike the master's own profile
/// where the rating and reviews tiles push «Мої відгуки»: that screen is the
/// INDEPENDENT_MASTER's, and this phase ships no owner-scoped reviews
/// destination, so a tappable tile would be a dead affordance.
class _OwnerStatsRow extends StatelessWidget {
  const _OwnerStatsRow({required this.master, required this.services});

  final Master master;
  final List<MasterService> services;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // `displayRating` folds all three "no rating yet" shapes (null average, a
    // stale 0.0, zero reviews) onto null, so the star and the readout cannot
    // disagree. See its own doc on [Master].
    final double? rating = master.displayRating;

    return IntrinsicHeight(
      // Kept from the 4-up rows: a caption that wraps on a narrow device or at
      // a large text scale must not leave the row ragged.
      child: Row(
        key: const Key('owner-own-profile-stats'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: StatTile(
              icon: Icons.star_rounded,
              iconWidget: RatingStar(
                rating: rating,
                size: 18,
                showLabel: false,
              ),
              value: rating?.toStringAsFixed(1) ?? StatTile.noDataGlyph,
              caption: l10n.masterRatingLabel,
              valueKey: const Key('owner-own-profile-rating-value'),
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: StatTile(
              icon: Icons.reviews_outlined,
              value: master.reviewCount == 0
                  ? StatTile.noDataGlyph
                  : master.reviewCount.toString(),
              caption: l10n.masterStatsReviewsLabel,
              valueKey: const Key('owner-own-profile-reviews-value'),
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: ServicesStatTile(
              // Already resolved by the time this row builds — the provider
              // awaited the catalogue before emitting, so there is no
              // unresolved (`null`) or failed (`hasError`) state to model here.
              count: services.length,
              valueKey: const Key('owner-own-profile-services-value'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _OwnerCategoriesSection
// ---------------------------------------------------------------------------

/// «Мої категорії» — the owner's services grouped by category, read-only.
///
/// The empty state is rendered HERE rather than delegated: [ServiceCategoryCardList]
/// short-circuits to `SizedBox.shrink()` on an empty list, so a section that
/// leaned on it would silently lose its own header too.
class _OwnerCategoriesSection extends StatelessWidget {
  const _OwnerCategoriesSection({required this.services});

  final List<MasterService> services;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Column(
      key: const Key('owner-own-profile-categories'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
          child: Text(
            l10n.ownerOwnProfileCategoriesLabel,
            style: VelvetText.sectionLabel(),
          ),
        ),
        if (services.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs, left: 4),
            child: Text(
              l10n.ownerOwnProfileNoServices,
              key: const Key('owner-own-profile-categories-empty'),
              style: VelvetText.feedbackMutedXs,
            ),
          )
        else
          // `interactive: false` — see the file header: the interactive
          // destination is INDEPENDENT_MASTER-only and 403s for an owner.
          ServiceCategoryCardList(
            services: services,
            keyPrefix: 'owner-profile-category',
            interactive: false,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _OwnerProfileSkeleton — loading state
// ---------------------------------------------------------------------------

/// Neumorphic shimmer skeleton matching [_OwnerProfileBody]'s layout.
///
/// It renders the MASTER-SECTION shape (stats + bio + categories) because that
/// is the common case for an existing owner — the backend auto-creates the
/// owner's master row on first-salon registration — so the skeleton settles
/// into the real layout instead of collapsing upward on arrival.
class _OwnerProfileSkeleton extends StatelessWidget {
  const _OwnerProfileSkeleton();

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

          // 2 — stats row: THREE equal tiles.
          Row(
            children: <Widget>[
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
              SizedBox(width: VelvetSpacing.sm),
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
              SizedBox(width: VelvetSpacing.sm),
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
            ],
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 3 — bio label + block.
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: SkeletonBlock(width: 90, height: 13),
          ),
          SkeletonBlock(
            width: double.infinity,
            height: 92,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 4 — categories label + 2 cards.
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: SkeletonBlock(width: 110, height: 13),
          ),
          SkeletonBlock(
            width: double.infinity,
            height: 60,
            radius: VelvetRadii.field,
          ),
          SizedBox(height: VelvetSpacing.xs + 4),
          SkeletonBlock(
            width: double.infinity,
            height: 60,
            radius: VelvetRadii.field,
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 5 — contacts label + 1 tile.
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
