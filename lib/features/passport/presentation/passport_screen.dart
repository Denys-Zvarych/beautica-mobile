// Phase 13.8 — CLIENT BEAUTY PASSPORT page.
//
// Ported 1:1 from the approved preview app
// `docs/signup-designs/BeautyPassport/`. The approved final layout (the user
// REMOVED the quick-links / next-appointment / favourite-masters cards the
// phase-doc prose mentioned) is exactly:
//   1. Top bar      — beautica wordmark · notification bell · burger
//   2. Profile block — avatar + name + location line (pin + city, NO chevron)
//                      + phone line
//   3. BEAUTY PASSPORT card (the hero) — blush document card; empty variant
//      when bookingsConsidered == 0
//   4. Bottom nav    — hosted by ClientShell (index 4); NOT re-added here.
//
// Single-screen, no scrolling: the card is the Expanded hero, vertically
// centred in the freed space (a SingleChildScrollView is the overflow safety
// valve only — on normal phone viewports nothing scrolls).
//
// PII: the profile block renders real client name / phone / city, so this
// screen acquires the app-wide [ScreenProtectionManager] (FLAG_SECURE / iOS
// app-switcher blur) on mount and releases it on unmount — same pattern as
// HomeHubScreen (§ CRITICAL-4). Hence ConsumerStatefulWidget.
//
// Top bar wordmark + bell + burger reuse the real Home Hub affordances
// (`BellButton`, `NeumorphicIconButton(BeauticaIcons.menuBurger)`) so the bar is
// identical to Головна. Data: `clientProfileProvider` (real, from auth session)
// for the profile; `passportProvider` (placeholder until backend 19.5) for the
// derived card.
//
// l10n gate: every Ukrainian string goes through AppLocalizations EXCEPT the
// locked brand literals "BEAUTY PASSPORT" / «Твій б'юті-паспорт у Beautica»
// (in passport_table.dart) and the lowercase "beautica" wordmark.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icon.dart';
import '../../../core/icons/beautica_asset_icons.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/beautica_icons.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../home/application/home_hub_notifier.dart';
import '../../home/domain/home_hub_models.dart';
import '../../home/presentation/widgets/hub_widgets.dart';
import '../application/passport_notifier.dart';
import '../domain/passport.dart';
import 'widgets/passport_table.dart';

/// The CLIENT BEAUTY PASSPORT page — bottom-nav tab index 4.
class PassportScreen extends ConsumerStatefulWidget {
  const PassportScreen({super.key});

  @override
  ConsumerState<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends ConsumerState<PassportScreen> {
  // Riverpod 3.x rule: never call ref inside dispose(). The manager reference is
  // cached via a late-final ref.read run eagerly in initState (while ref is
  // valid); dispose() then only touches the cached field.
  late final ScreenProtectionManager _protection = ref.read(
    screenProtectionProvider,
  );

  @override
  void initState() {
    super.initState();
    // PII: the profile block shows name / phone / city — acquire screen
    // protection so FLAG_SECURE / iOS app-switcher blur is active while mounted.
    _protection.acquire();
    if (kDebugMode) {
      log(
        'PassportScreen mounted — screen protection acquired',
        name: 'feature.passport',
        level: 800,
      );
    }
  }

  @override
  void dispose() {
    _protection.release();
    if (kDebugMode) {
      log(
        'PassportScreen disposed — screen protection released',
        name: 'feature.passport',
        level: 800,
      );
    }
    super.dispose();
  }

  void _onBellTap() {
    // TODO(14.9): route to RouteNames.notifications when that screen ships.
    if (kDebugMode) {
      log(
        'notifications tapped — placeholder',
        name: 'feature.passport',
        level: 700,
      );
    }
  }

  void _onBurgerTap() => context.push(RouteNames.clientMenu);

  void _onCameraTap() {
    // TODO(13.7.1): wire image upload. Placeholder for now.
    if (kDebugMode) {
      log(
        'change photo tapped — placeholder',
        name: 'feature.passport',
        level: 700,
      );
    }
  }

  void _onFindMaster() {
    // The empty-passport CTA sends the client to discovery (Пошук, tab 2).
    context.go(RouteNames.clientSearch);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Stable branch key: the real PassportScreen replaced the placeholder for
      // the index-4 client-shell branch (Phase 13.8). Carry the same
      // `client-branch-passport` key the placeholder exposed so the client-shell
      // E2E flow's branch-4 assertion (and the passport flow) keep a stable,
      // locale-independent target.
      key: const Key('client-branch-passport'),
      backgroundColor: BrandColors.base,
      // Bottom nav is hosted by ClientShell — this screen is just the body.
      body: SafeArea(
        bottom: false,
        child: RepaintBoundary(
          child: _PassportBody(
            onBell: _onBellTap,
            onBurger: _onBurgerTap,
            onCamera: _onCameraTap,
            onFindMaster: _onFindMaster,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — ConsumerWidget so it can watch the profile + passport providers.
// ---------------------------------------------------------------------------

class _PassportBody extends ConsumerWidget {
  const _PassportBody({
    required this.onBell,
    required this.onBurger,
    required this.onCamera,
    required this.onFindMaster,
  });

  final VoidCallback onBell;
  final VoidCallback onBurger;
  final VoidCallback onCamera;
  final VoidCallback onFindMaster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // L2 (perf): the profile and passport providers are watched in SEPARATE
    // [Consumer] subtrees — NOT both at this level — so a profile refresh only
    // rebuilds the profile block and a passport refresh only rebuilds the hero
    // card. Watching both here would couple the two: either provider's change
    // would rebuild the whole body (incl. the expensive hero).

    // Single-screen layout: a non-scrolling Column. The passport document is
    // the hero and absorbs the slack via Expanded; the chrome + profile take
    // only what they need, so the whole page fits one phone viewport.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.sm,
        VelvetSpacing.lg,
        VelvetSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TopBar(onBell: onBell, onBurger: onBurger),
          const SizedBox(height: VelvetSpacing.sm + 2),
          // Profile block — name / location (pin + city, no chevron) / phone.
          // Scoped Consumer: only this subtree rebuilds on a profile refresh.
          Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              final profileAsync = ref.watch(clientProfileProvider);
              return profileAsync.when(
                data: (ClientProfileSummary p) =>
                    _ProfileBlock(profile: p, onCamera: onCamera),
                loading: () => const _ProfileSkeleton(),
                error: (Object e, _) => _ProfileBlock(
                  profile: const ClientProfileSummary(
                    firstName: '',
                    lastName: '',
                    city: '',
                    phone: '',
                    clientRating: null,
                    memberSinceYear: 0,
                  ),
                  onCamera: onCamera,
                ),
              );
            },
          ),
          const SizedBox(height: VelvetSpacing.sm + 2),
          // The passport document — the page's only hero — absorbs the freed
          // space and is centred within the slack so it never stretches
          // edge-to-edge. The scroll view is the overflow safety valve only.
          // Scoped Consumer: only the hero rebuilds on a passport refresh.
          Expanded(
            child: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                final passportAsync = ref.watch(passportProvider);
                return passportAsync.when(
                  data: (Passport passport) => _PassportHero(
                    passport: passport,
                    onFindMaster: onFindMaster,
                  ),
                  loading: () => const _PassportCardSkeleton(),
                  error: (Object e, _) =>
                      _PassportHero.empty(onFindMaster: onFindMaster),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passport hero — populated card OR empty-passport variant, centred in slack.
// ---------------------------------------------------------------------------

class _PassportHero extends StatelessWidget {
  const _PassportHero({required this.passport, required this.onFindMaster});

  const _PassportHero.empty({required this.onFindMaster}) : passport = null;

  final Passport? passport;
  final VoidCallback onFindMaster;

  @override
  Widget build(BuildContext context) {
    final Passport? p = passport;
    final bool empty = p == null || p.isEmpty;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            // Vertical centring in the freed space is done by [ConstrainedBox]
            // minHeight + [Center] alone — the card is a mainAxisSize.min Column,
            // not a Row of Expanded children, so no outer IntrinsicHeight is
            // needed here. (The card's own inner IntrinsicHeight in
            // passport_table.dart still equalises the three columns.)
            child: Center(
              child: empty
                  ? _EmptyPassport(onFindMaster: onFindMaster)
                  : _PopulatedPassport(passport: p),
            ),
          ),
        );
      },
    );
  }
}

/// Maps the derived [Passport] onto the [PassportCard], building the localised
/// budget chip and member-since strings.
class _PopulatedPassport extends StatelessWidget {
  const _PopulatedPassport({required this.passport});

  final Passport passport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final BudgetBand? budget = passport.budget;
    final String budgetValue = budget == null
        ? l10n.passportBudgetUnknown
        : l10n.passportBudgetCeiling(budget.max.round());
    final String memberSince =
        passport.memberSinceYear?.toString() ?? DateTime.now().year.toString();
    return PassportCard(
      procedures: passport.favoriteProcedures,
      districts: passport.favoriteDistricts,
      budgetValue: budgetValue,
      reviewsLeft: passport.reviewsLeft,
      memberSince: memberSince,
    );
  }
}

/// The empty passport: shown when no completed bookings have been considered.
/// A friendly stamp glyph + encouraging copy inviting the client to book their
/// first service — an invitation to act, not an apology.
class _EmptyPassport extends StatelessWidget {
  const _EmptyPassport({required this.onFindMaster});

  final VoidCallback onFindMaster;

  static final BoxDecoration _cardDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    boxShadow: VelvetShadows.extrudedCard,
  );

  static const BoxDecoration _stampWellDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  static final TextStyle _bodyStyle = VelvetText.body().copyWith(fontSize: 14);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      decoration: _cardDecoration,
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            height: 92,
            width: 92,
            decoration: _stampWellDecoration,
            child: const Icon(
              Icons.auto_stories_rounded,
              size: 38,
              color: BrandColors.accent,
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          Text(
            l10n.passportEmptyTitle,
            textAlign: TextAlign.center,
            style: VelvetText.subheading(),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Text(
            l10n.passportEmptyBody,
            textAlign: TextAlign.center,
            style: _bodyStyle,
          ),
          const SizedBox(height: VelvetSpacing.lg),
          HubFilledButton(
            key: const Key('passport_find_master_button'),
            label: l10n.passportEmptyCta,
            onTap: onFindMaster,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile block — mirrors the Головна profile block; NO location chevron/tap.
// ---------------------------------------------------------------------------

class _ProfileBlock extends StatelessWidget {
  const _ProfileBlock({required this.profile, required this.onCamera});

  final ClientProfileSummary profile;
  final VoidCallback onCamera;

  static final TextStyle _nameStyle = VelvetText.displayName().copyWith(
    fontSize: 21,
  );
  static final TextStyle _lineStyle = VelvetText.body().copyWith(
    fontSize: 14,
    color: BrandColors.text,
  );

  static final BoxDecoration _cameraBadgeDecoration = BoxDecoration(
    color: BrandColors.white,
    shape: BoxShape.circle,
    border: Border.all(color: BrandColors.base, width: 2),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String city = profile.city.isNotEmpty
        ? profile.city
        : l10n.homeHubLocationPlaceholder;
    final String phone = profile.phone.isNotEmpty
        ? profile.phone
        : l10n.homeHubPhonePlaceholder;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 100,
          width: 100,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              HubAvatar(initials: profile.initials, size: 96, fontSize: 30),
              Positioned(
                right: 0,
                bottom: 0,
                child: Semantics(
                  button: true,
                  label: l10n.homeHubChangePhotoLabel,
                  child: GestureDetector(
                    key: const Key('passport_change_photo_button'),
                    onTap: onCamera,
                    child: Container(
                      height: 30,
                      width: 30,
                      decoration: _cameraBadgeDecoration,
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        size: 15,
                        color: BrandColors.accentDeep,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: VelvetSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 4),
              Text(
                profile.fullName,
                style: _nameStyle,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: VelvetSpacing.sm + 2),
              // Location line — pin + city, NO chevron and NO tap (approved
              // design dropped the chevron the Головна card has).
              _line(Icons.location_on_rounded, city),
              const SizedBox(height: VelvetSpacing.sm),
              _line(Icons.call_rounded, phone),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.sm),
        Flexible(
          child: Text(text, style: _lineStyle, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar — beautica wordmark · bell · burger (identical to Головна).
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBell, required this.onBurger});

  final VoidCallback onBell;
  final VoidCallback onBurger;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Text(
          // ignore: avoid_hardcoded_strings — brand wordmark, NOT translated.
          'beautica',
          style: VelvetText.wordmark(),
        ),
        const Spacer(),
        _BellButton(
          onTap: onBell,
          semanticLabel: l10n.homeHubNotificationsLabel,
        ),
        const SizedBox(width: VelvetSpacing.sm + 4),
        NeumorphicIconButton(
          key: const Key('btn-menu-passport'),
          icon: BeauticaIcons.menuBurger,
          semanticLabel: l10n.settingsHubMenuButton,
          onTap: onBurger,
        ),
      ],
    );
  }
}

/// Notification bell — identical idle-state recipe to the real Home Hub
/// `BellButton` (which is `@visibleForTesting`, so it can't be reused across
/// features): the in-repo [BeauticaAssetIcons.notificationPlain] rendered FLAT
/// at 24×24, tinted [BrandColors.textSecondary]. The production call site is
/// pinned to the dotless (no-unread) state, matching Головна.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.onTap, required this.semanticLabel});

  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        key: const Key('passport_bell_button'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.all(VelvetSpacing.xs),
          child: AppIcon(
            BeauticaAssetIcons.notificationPlain,
            size: 24,
            color: BrandColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading skeletons
// ---------------------------------------------------------------------------

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  static final BoxDecoration _avatarDecoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    shape: BoxShape.circle,
  );
  static final BoxDecoration _barDecoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    borderRadius: BorderRadius.circular(8),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(height: 96, width: 96, decoration: _avatarDecoration),
        const SizedBox(width: VelvetSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(height: 20, width: 140, decoration: _barDecoration),
              const SizedBox(height: VelvetSpacing.sm),
              Container(height: 14, width: 100, decoration: _barDecoration),
              const SizedBox(height: VelvetSpacing.sm - 2),
              Container(height: 14, width: 120, decoration: _barDecoration),
            ],
          ),
        ),
      ],
    );
  }
}

class _PassportCardSkeleton extends StatelessWidget {
  const _PassportCardSkeleton();

  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.22),
    borderRadius: BorderRadius.circular(VelvetRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    return Center(child: Container(height: 280, decoration: _decoration));
  }
}
