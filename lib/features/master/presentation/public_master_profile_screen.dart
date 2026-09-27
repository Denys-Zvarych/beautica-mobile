// Phase 13.5 — Public master profile (CLIENT-facing, read-only).
//
// The client's view of a master, reached by tapping a search / favourites /
// salon-roster result card. Same depth language as the master's own profile
// (`MasterProfileScreen`) but:
//   • NO edit button — the top-right action is a favourite (heart) toggle;
//   • contacts = Instagram only (no phone/dialer tile);
//   • a pinned camel-wash booking shelf holding a single «Записатись до
//     майстра» CTA (no section label) — shown for EVERY resolved master,
//     independent or salon-affiliated (Phase 358 restored this; see below).
//
// Phase 351 (Qase defect #21, "option D") — this screen now applies to BOTH
// independent and salon masters (one screen, `master.type` still gates every
// independent-only affordance) and is restructured around three tabs —
// «Про майстра» / «Послуги» / «Відгуки» — mirroring the public SALON
// profile's tab language exactly (U1/U3: design gate waived, build only from
// already-existing widgets). The stat cards STAY (U5) — «Рейтинг» / «Послуги»
// / «Відгуки», minus «Досвід» (D9, always «—», no backing field) — but each
// card now SWITCHES to the matching tab in place instead of pushing a route
// (U6/U7, D15's shared `ProfileTabSelection` mixin) — no
// `IndexedStack`/`TabController`. `ServiceCategoryCardList` and
// `MasterReviewsBody` — already shared widgets — now live under their own
// tabs instead of stacked on the page; `masterPublicReviews` stays a real
// ROUTE (unrelated consumers: `booking_counterparty_header.dart`,
// `leave_review_screen.dart`, `booking_confirm_screen.dart`) but this screen
// no longer pushes it itself.
//
// Data comes from [publicMasterProfileProvider] (a family keyed on masterId)
// which loads the master + active services in parallel. All three AsyncValue
// states are handled explicitly (loading skeleton / error / data).
//
// Design source: `docs/signup-designs/PublicMasterProfile/` — ported within the
// locked Warm Mocha (VelvetTouch) palette, reusing the production
// ProfileScaffold / ProfileAvatar / RoleChip / ContactTile widgets, plus (Phase
// 351) the salon profile's [ProfileTabBar] and the shared
// [ProfileTabSelection] card-to-tab mixin.
//
// Phase 358 (user report, verbatim: "why u remove the button to book directly
// from salon master profile? add it pls") — Phase 351's scope table narrowed
// `_BookingShelf` to INDEPENDENT_MASTER only, without being asked to; that was
// a regression against the pre-351 screen, which showed the shelf for EVERY
// resolved master (`data: (_) => _BookingShelf(...)`). Restored: the shelf now
// renders for a salon-affiliated master too. The CTA already worked end to
// end for a salon master before this fix — `RouteNames.bookingNew` /
// `ServiceSelectorSheet` never branch on `MasterType` (Phase 350 D4 proved
// this for the rebook CTA: services load via the public, type-agnostic
// `GET /masters/{id}/services`, and `CreateAppointmentRequest` needs only
// `masterId` + `masterServiceIds`) — only the visibility gate on THIS screen
// was wrong. Instagram/portfolio stay independent-only — unchanged, see
// `_AboutTab`.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/reveal_transition.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/location/presentation/saved_settlement_label.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/expandable_note.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:beautica_mobile/shared/widgets/profile_tab_bar.dart';
import 'package:beautica_mobile/shared/widgets/profile_tab_selection.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'widgets/master_address_block.dart';
import 'widgets/master_profile_tabs.dart';
import 'widgets/master_reviews_body.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_scaffold.dart';
import 'widgets/service_category_cards.dart';
import 'widgets/services_stat_tile.dart';

/// CLIENT-facing read-only profile of the master identified by [masterId].
class PublicMasterProfileScreen extends ConsumerStatefulWidget {
  const PublicMasterProfileScreen({super.key, required this.masterId});

  /// Backend Master-row UUID of the profile being viewed.
  final String masterId;

  @override
  ConsumerState<PublicMasterProfileScreen> createState() =>
      _PublicMasterProfileScreenState();
}

class _PublicMasterProfileScreenState
    extends ConsumerState<PublicMasterProfileScreen>
    with
        SingleTickerProviderStateMixin,
        ProfileTabSelection<PublicMasterProfileScreen> {
  late final AnimationController _controller;

  // Pre-built staggered-entrance animations (one per reveal section) so build()
  // never allocates a CurvedAnimation/Tween per frame (mobile-perf pattern,
  // mirrors MasterProfileScreen / PublicSalonProfileScreen). Phase 351 — FOUR
  // sections now (identity card / rating line / tab bar / tab body), down
  // from six (the old stats/bio/portfolio/categories/contacts stack).
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final CurvedAnimation _anim3;
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;
  late final Animation<Offset> _slide3;

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x throws
  // when `ref` is used after the widget is unmounted).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders another master's address (PII) — guard against
    // app-switcher snapshots while it is mounted. The manager is ref-counted
    // and !kDebugMode-guarded internally. It does NOT block screenshots:
    // capture is allowed app-wide by product decision 2026-08-20, see the
    // header of `lib/core/security/screen_protection.dart`.
    //
    // INTENTIONAL PRODUCT DECISION (keep): retaining the acquire on the public
    // profile is deliberate — do NOT remove it in a future audit pass. The
    // owner reviewed it and chose to keep this screen inside the guard. (The
    // review predates the 2026-08-20 reversal, which narrowed WHAT the guard
    // does but did not touch any acquire/release call site.)
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _anim0 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.55, curve: Curves.easeOutCubic),
    );
    _anim1 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.65, curve: Curves.easeOutCubic),
    );
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.80, curve: Curves.easeOutCubic),
    );
    _anim3 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.00, curve: Curves.easeOutCubic),
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
  }

  @override
  void dispose() {
    _screenProtection.release();
    disposeProfileTabSelection();
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startReveal() {
    if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<PublicMasterProfileData> async = ref.watch(
      publicMasterProfileProvider(widget.masterId),
    );

    return ProfileScaffold(
      title: l10n.publicMasterProfileTitle,
      trailing: _FavoriteToggleButton(masterId: widget.masterId),
      // The booking shelf is only meaningful once the master has resolved —
      // shown for EVERY resolved master, independent or salon-affiliated
      // (Phase 358 — restores the pre-351 behaviour; `RouteNames.bookingNew`
      // works end to end for a salon master, see the file header's Phase 358
      // note).
      bottomNavBar: async.maybeWhen(
        data: (_) => _BookingShelf(masterId: widget.masterId),
        orElse: () => null,
      ),
      child: async.when(
        loading: () => const _PublicProfileSkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () =>
              ref.invalidate(publicMasterProfileProvider(widget.masterId)),
        ),
        data: (PublicMasterProfileData data) {
          _startReveal();
          return _PublicProfileBody(
            masterId: widget.masterId,
            master: data.$1,
            services: data.$2,
            tabNotifier: profileTabNotifier,
            onSelectTab: selectProfileTab,
            anim0: _anim0,
            anim1: _anim1,
            anim2: _anim2,
            anim3: _anim3,
            slide0: _slide0,
            slide1: _slide1,
            slide2: _slide2,
            slide3: _slide3,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PublicProfileBody — loaded state: identity card + stat cards + tabs
// ---------------------------------------------------------------------------

class _PublicProfileBody extends StatelessWidget {
  const _PublicProfileBody({
    required this.masterId,
    required this.master,
    required this.services,
    required this.tabNotifier,
    required this.onSelectTab,
    required this.anim0,
    required this.anim1,
    required this.anim2,
    required this.anim3,
    required this.slide0,
    required this.slide1,
    required this.slide2,
    required this.slide3,
  });

  /// Trusted route param (`widget.masterId`) — used for the reviews tab's
  /// `MasterReviewsBody(masterId:)`, never [master].id, which is a value
  /// round-tripped through the profile response and mapped by
  /// `MasterMapper`.
  final String masterId;
  final Master master;

  /// The master's active services, loaded in parallel with [master] by
  /// [publicMasterProfileProvider]. Drives the «Послуги» tab.
  final List<MasterService> services;

  /// [ProfileTabSelection.profileTabNotifier] — the active tab index (0 =
  /// Про майстра, 1 = Послуги, 2 = Відгуки), as a [ValueNotifier] so only the
  /// [ProfileTabSection] below rebuilds on a tab switch (mobile-perf LOW,
  /// Phase 351 audit-fix cycle 1) — this identity card / stat-card row above
  /// it never watches it.
  final ValueNotifier<int> tabNotifier;

  /// [ProfileTabSelection.selectProfileTab] — passed to [ProfileTabBar]'s
  /// `onSelect`, the only way to switch tabs (the stat cards are
  /// display-only, user decision 2026-09-26).
  final ValueChanged<int> onSelectTab;

  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<double> anim3;
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;
  final Animation<Offset> slide3;

  static const List<String> _tabKeys = <String>['about', 'services', 'reviews'];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String displayName = '${master.firstName} ${master.lastName}'.trim();
    final String roleLabel = _roleLabel(master.type, l10n);
    // «м. Львів, Львівська обл.» — the picker's label, not the bare name;
    // the bare name when the read carries no settlement type.
    final String? settlementLabel =
        savedSettlementLabel(l10n, master.savedSettlement) ?? master.city;
    final String? localityLine = buildLocalityLine(settlementLabel);
    final String? streetLine = buildStreetLine(
      master.street,
      master.buildingNo,
    );
    // Phase 224 — the COLLAPSED one-line form of the same address. Which of
    // the two renderings ships is `MasterAddressBlock`'s measured decision.
    final String? combinedAddressLine = buildCombinedAddressLine(
      settlementLabel,
      master.street,
      master.buildingNo,
    );
    // Phase 222 — sanitization now happens INSIDE `ExpandableNote` (it
    // must run on the exact same string the widget measures for overflow AND
    // renders — see that widget's class doc). Pre-sanitizing here too would
    // be a redundant no-op pass (sanitize is idempotent) that only obscures
    // which layer owns the invariant; kept single-sourced in the widget.
    final String? noteText = (master.locationNote?.isNotEmpty ?? false)
        ? master.locationNote
        : null;
    // Instagram + portfolio are an INDEPENDENT_MASTER-only affordance — a
    // salon-affiliated master's public profile hides both. This is a
    // client-side-only decision for THIS pair specifically: the backend's
    // `MasterDetailResponse.fromPublic` never masks `instagram` (it — like
    // `bio` — is returned unmasked for every `MasterType`). The backend DOES
    // null out `street` / `buildingNo` / `locationNote` / `cityId` /
    // `oblastId` / `districtId` for `SALON_MASTER` / `SALON_OWNER` — only
    // `INDEPENDENT_MASTER` receives those on this public path — so for the
    // ADDRESS fields (not instagram/bio) this screen's `isIndependent` gate
    // is redundant with, not a substitute for, an already-enforced backend
    // rule.
    final bool isIndependent = master.type == MasterType.independentMaster;
    final String? instagram =
        (isIndependent && (master.instagram?.isNotEmpty ?? false))
        ? master.instagram
        : null;
    final bool hasReviews = master.reviewCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1 — Identity card.
        RevealTransition(
          key: const Key('public-master-profile-reveal-0'),
          fade: anim0,
          slide: slide0,
          child: NeumorphicCard(
            color: const Color(0xFFEDE4D5),
            padding: const EdgeInsets.all(VelvetSpacing.md),
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
                        key: const Key('public-master-profile-name'),
                        style: VelvetText.displayName(),
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: VelvetSpacing.xs + 2),
                      RoleChip(
                        key: (master.professionalTitle?.isNotEmpty == true)
                            ? const Key(
                                'public-master-profile-professional-title',
                              )
                            : null,
                        label: (master.professionalTitle?.isNotEmpty == true)
                            ? master.professionalTitle!
                            : roleLabel,
                        icon: Icons.auto_awesome_rounded,
                      ),
                      // Equivalent to the old `localityLine != null ||
                      // streetLine != null` gate (see the own-profile screen
                      // for why), and it promotes the local to non-nullable.
                      if (combinedAddressLine != null) ...<Widget>[
                        const SizedBox(height: VelvetSpacing.xs),
                        // Phase 220 (C) + Phase 224 — same address block as
                        // the own-profile screen: locality (city) first, then
                        // street + building, collapsed onto ONE row when the
                        // whole string fits, then the note. Composition lives
                        // in `shared/formatters/address_lines.dart`, the
                        // measure-and-choose in
                        // `widgets/master_address_block.dart`.
                        MasterAddressBlock(
                          keyPrefix: 'public-master-profile',
                          icon: const Icon(
                            Icons.location_on_outlined,
                            size: MasterAddressBlock.iconSize,
                            color: BrandColors.muted,
                          ),
                          localityLine: localityLine,
                          streetLine: streetLine,
                          combinedLine: combinedAddressLine,
                        ),
                        if (noteText != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: ExpandableNote(
                              key: const Key(
                                'public-master-profile-location-note',
                              ),
                              text: noteText,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // 2 — Stat cards: «Рейтинг» / «Послуги» / «Відгуки» (D9 — «Досвід»
        // removed, it always showed «—» with no backing field). Display-only
        // (user decision 2026-09-26) — no tap, no ripple, no button
        // semantics. The «Про майстра» / «Послуги» / «Відгуки» tabs below are
        // the only way to switch tabs.
        RevealTransition(
          key: const Key('public-master-profile-reveal-1'),
          fade: anim1,
          slide: slide1,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    key: const Key('public-master-profile-rating-tile'),
                    icon: Icons.star_rounded,
                    // `displayRating` folds all three "no rating yet" shapes
                    // (null average, a stale 0.0, zero reviews) onto null, so
                    // the star and the readout cannot disagree.
                    iconWidget: RatingStar(
                      rating: master.displayRating,
                      size: 18,
                      showLabel: false,
                    ),
                    value: master.displayRating?.toStringAsFixed(1) ?? '—',
                    caption: l10n.masterRatingLabel,
                    valueKey: const Key('public-master-profile-rating-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: ServicesStatTile(
                    key: const Key('public-master-profile-services-tile'),
                    count: services.length,
                    valueKey: const Key('public-master-profile-services-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    key: const Key('public-master-profile-reviews-tile'),
                    icon: Icons.reviews_outlined,
                    value: hasReviews ? master.reviewCount.toString() : '—',
                    caption: l10n.masterStatsReviewsLabel,
                    valueKey: const Key('public-master-profile-reviews-value'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.lg),

        // 3+4 — Tab bar + tab body, isolated behind ONE `ProfileTabSection`
        // (mobile-perf LOW, Phase 351 audit-fix cycle 1) — a tab switch now
        // only rebuilds this region, never sections 1-2 above.
        ProfileTabSection(
          notifier: tabNotifier,
          builder: (BuildContext context, int tab) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 3 — Tab bar. Promoted `ProfileTabBar` (Phase 351) — same
              // widget the public salon profile uses, own `keyPrefix` so its
              // finders read as this screen's own
              // (`public-master-profile-tab-0` etc.), not borrowed from the
              // salon's `salon-tab-*`. The only way to switch tabs — the stat
              // cards above are display-only (user decision 2026-09-26).
              RevealTransition(
                key: const Key('public-master-profile-reveal-2'),
                fade: anim2,
                slide: slide2,
                child: ProfileTabBar(
                  tabs: masterProfileTabLabels(l10n),
                  selected: tab,
                  onSelect: onSelectTab,
                  keyPrefix: 'public-master-profile',
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),

              // 4 — Tab body. Mirrors the salon profile's `switch (tab)` +
              // `KeyedSubtree` exactly (D2) — no `IndexedStack`/
              // `TabController`, one tab mechanism only. Every arm is a
              // non-scrolling `Column` (already true for `_AboutTab`,
              // `ServiceCategoryCardList` and `MasterReviewsBody`), sitting
              // inside `ProfileScaffold`'s own `SingleChildScrollView`
              // (which also supplies the `VelvetSpacing.lg` horizontal
              // gutter every tab gets for free — unlike the salon's bespoke
              // scroll view, no per-tab `Padding` is needed here).
              RevealTransition(
                key: const Key('public-master-profile-reveal-3'),
                fade: anim3,
                slide: slide3,
                child: KeyedSubtree(
                  key: ValueKey<String>(
                    'public-master-profile-tab-body-${_tabKeys[tab]}',
                  ),
                  child: switch (tab) {
                    0 => _AboutTab(
                      master: master,
                      isIndependent: isIndependent,
                      instagram: instagram,
                    ),
                    1 => ServiceCategoryCardList(
                      services: services,
                      keyPrefix: 'public-master-profile-category',
                      interactive: false,
                    ),
                    _ => MasterReviewsBody(masterId: masterId),
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _roleLabel(MasterType type, AppLocalizations l10n) {
    switch (type) {
      case MasterType.independentMaster:
        return l10n.masterRoleIndependent;
      case MasterType.salonMaster:
        return l10n.masterRoleSalonMaster;
      case MasterType.salonOwner:
        return l10n.masterRoleSalonOwner;
    }
  }
}

// ---------------------------------------------------------------------------
// _AboutTab — "Про майстра": bio (or the empty-state text) + portfolio +
// Instagram contact, the last two INDEPENDENT_MASTER-only.
// ---------------------------------------------------------------------------

class _AboutTab extends StatelessWidget {
  const _AboutTab({
    required this.master,
    required this.isIndependent,
    required this.instagram,
  });

  final Master master;
  final bool isIndependent;

  /// Already gated on [isIndependent] by the caller — non-null only for an
  /// independent master with a non-empty Instagram handle.
  final String? instagram;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool hasBio = master.bio != null && master.bio!.isNotEmpty;

    return Column(
      key: const Key('public-master-profile-about-tab'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Bio — always renders ONE of two variants now (Phase 351 D9/empty-
        // state decision), unlike the pre-351 screen, which omitted the
        // whole section when empty. "Both rows" locked decision: THIS screen
        // is always read-only (a client viewing another master), so it only
        // ever shows the muted placeholder — never the master's own
        // `AddLink` «Додати опис» affordance (that lives on the master's OWN
        // profile screens: `MasterProfileScreen` / `SalonMasterProfileScreen`).
        if (hasBio) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: Text(
              l10n.publicMasterBioLabel,
              style: VelvetText.sectionLabel(),
            ),
          ),
          NeumorphicInset(
            radius: VelvetRadii.card,
            child: Padding(
              padding: const EdgeInsets.all(VelvetSpacing.md + 2),
              child: Text(master.bio!, style: VelvetText.bodyStrong()),
            ),
          ),
        ] else
          Text(
            l10n.publicMasterAboutEmpty,
            key: const Key('public-master-profile-about-empty'),
            style: VelvetText.feedback(BrandColors.muted),
          ),

        // Portfolio rail (placeholder tiles until the gallery phase).
        // INDEPENDENT_MASTER only — hidden entirely for salon-affiliated
        // masters. REUSE-FIRST — [PortfolioRail] promoted to
        // shared/widgets/portfolio_rail.dart; no `onSeeAll` here (this
        // read-only view has no gallery route), matching prior behaviour.
        if (isIndependent) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xl),
          const PortfolioRail(railKey: Key('public-master-profile-portfolio')),
        ],

        // Contacts (Instagram only; omitted when not set).
        if (instagram != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xl),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: Text(
              l10n.masterContactsLabel,
              style: VelvetText.sectionLabel(),
            ),
          ),
          ContactTile(
            key: const Key('public-master-contact-instagram'),
            icon: Icons.alternate_email,
            label: l10n.masterInstagramLabel,
            value: instagram!,
            semanticLabel: l10n.masterInstagramLabel,
            onTap: () => _openInstagram(context, instagram),
          ),
        ],
      ],
    );
  }

  /// Opens the master's Instagram in the Instagram app or a browser, sanitising
  /// [rawValue] through [canonicalInstagramUri] (STRICT https + host/charset
  /// allow-list) before launch — an unvalidated string is never handed to
  /// [launchUrl]. On a null result / launch failure a localized VelvetSnack shows.
  static Future<void> _openInstagram(
    BuildContext context,
    String? rawValue,
  ) async {
    final Uri? uri = canonicalInstagramUri(rawValue);
    if (uri == null) {
      _showInstagramError(context);
      return;
    }
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (error) {
      if (kDebugMode) {
        log(
          'Instagram launch threw',
          name: 'feature.master.public',
          level: 900,
          error: error,
        );
      }
    }
    if (!context.mounted) return;
    if (!launched) _showInstagramError(context);
  }

  /// This route is registered TOP-LEVEL, outside the CLIENT `StatefulShellRoute`
  /// (app_router.dart) — pushed full-screen OVER `ClientShell`, which replaces
  /// it entirely (the shared `ClientBottomNav` is not part of this route's
  /// tree at all). The screen's own bottom slot is `_BookingShelf`, a local
  /// per-screen CTA, not the shared nav bar the `bottomNavClearance*` constants
  /// exist to clear — so no `bottomInset` is needed here.
  static void _showInstagramError(BuildContext context) {
    showErrorSnack(
      context,
      AppLocalizations.of(context).masterInstagramOpenError,
    );
  }
}

// ---------------------------------------------------------------------------
// _FavoriteToggleButton — top-right heart bound to the favorite toggle notifier
// ---------------------------------------------------------------------------

/// A 48×48 raised neumorphic heart that flips the favourite flag for this
/// master via [favoriteToggleProvider] (targetType = MASTER). The icon pops on
/// toggle; the button depresses on press. On a failed toggle the notifier
/// reverts the optimistic flag and a localized VelvetSnack is shown.
class _FavoriteToggleButton extends ConsumerStatefulWidget {
  const _FavoriteToggleButton({required this.masterId});

  final String masterId;

  @override
  ConsumerState<_FavoriteToggleButton> createState() =>
      _FavoriteToggleButtonState();
}

class _FavoriteToggleButtonState extends ConsumerState<_FavoriteToggleButton> {
  bool _pressed = false;

  FavoriteTarget get _target =>
      FavoriteTarget(type: FavoriteTargetType.master, id: widget.masterId);

  Future<void> _onTap() async {
    setState(() => _pressed = false);
    final Failure? failure = await ref
        .read(favoriteToggleProvider.notifier)
        .toggle(_target);
    // See `_showInstagramError`'s doc above — this top-level route sits over
    // `ClientShell`, not inside it, so no `bottomInset` is needed here either.
    if (failure != null && mounted) {
      showErrorSnack(context, failure.userMessage(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FavoriteTarget target = _target;
    final bool isFavorite = ref.watch(
      favoriteToggleProvider.select(
        (Map<FavoriteTarget, FavoriteEntry> m) =>
            m[target]?.isFavorite ?? false,
      ),
    );

    return Semantics(
      button: true,
      toggled: isFavorite,
      label: isFavorite ? l10n.favoriteRemoveLabel : l10n.favoriteAddLabel,
      child: GestureDetector(
        key: const Key('public-master-favorite-toggle'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => _onTap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: _heartRadius,
            boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
          ),
          child: Center(
            child: AnimatedScale(
              scale: isFavorite ? 1.12 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.elasticOut,
              child: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 22,
                color: isFavorite ? BrandColors.accent : BrandColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const BorderRadius _heartRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );
}

// ---------------------------------------------------------------------------
// _BookingShelf — pinned camel-wash booking shelf (CTA only)
// ---------------------------------------------------------------------------

/// The pinned bottom booking shelf. On the profile it holds a single child: the
/// camel «Записатись до майстра» CTA — no section label. Tapping the CTA
/// opens the Phase 14.1 booking flow ([RouteNames.bookingNew]) carrying the
/// target master id in `extra`. Actual service selection lives in 14.1.
///
/// Phase 351 — this is `_LOAD-BEARING` `_BookingShelf`, DELIBERATELY holding a
/// single-child `Column` (mobile-backlog :622) — do not "simplify" it away.
/// It is hosted via `ProfileScaffold.bottomNavBar`, pinned above every tab.
class _BookingShelf extends StatelessWidget {
  const _BookingShelf({required this.masterId});

  final String masterId;

  /// Camel-wash surface (a few steps off the page base) so the shelf reads as
  /// its own elevated sheet rising from the bottom.
  static const Color _shelfSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _shelfSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.shadowDarkCard,
            offset: Offset(0, -9),
            blurRadius: 24,
          ),
          BoxShadow(
            color: BrandColors.shadowLightStrong,
            offset: Offset(0, -1),
            blurRadius: 3,
            spreadRadius: -1,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NeumorphicButton(
                key: const Key('public-master-book-cta'),
                label: l10n.publicMasterBookingCta,
                icon: Icons.add_rounded,
                onPressed: () =>
                    context.push(RouteNames.bookingNew, extra: masterId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PublicProfileSkeleton — loading state
// ---------------------------------------------------------------------------

class _PublicProfileSkeleton extends StatelessWidget {
  const _PublicProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Identity card.
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
                      SkeletonBlock(width: 100, height: 24, radius: 999),
                      SizedBox(height: VelvetSpacing.xs),
                      SkeletonBlock(width: 160, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: VelvetSpacing.xl),
          // Stat cards placeholder — 3 equal tiles (rating / services / reviews).
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
          SizedBox(height: VelvetSpacing.lg),
          // Tab bar placeholder.
          SkeletonBlock(width: double.infinity, height: 44),
          SizedBox(height: VelvetSpacing.lg),
          // Tab body placeholder.
          SkeletonBlock(
            width: double.infinity,
            height: 160,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}
