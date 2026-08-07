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
// Both async surfaces on this page are rendered with an EXPLICIT branch
// order (`isLoading` → `hasError` → value), never `.when()`: Riverpod
// carries the previous error forward through an in-flight retry, so
// `hasError` alone cannot separate loading from failed. Each surface has
// three states — loading, ERROR and data — the error being a real affordance
// (`_ProfileError` for the profile block, `_PassportError` for the hero),
// never a silent degrade to a blank-field profile or to the empty-passport
// variant. Collapsing a failure into "no data yet" is what let the
// always-empty passport bug hide; the two are separately test-pinned.
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
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/formatters/booking_price_labels.dart';
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
      // Top bar (wordmark · bell · burger) AND bottom nav are hosted by
      // ClientShell — this screen is just the body. The shell owns the single
      // SafeArea(top), so the body must NOT re-wrap one.
      body: RepaintBoundary(
        child: _PassportBody(
          onCamera: _onCameraTap,
          onFindMaster: _onFindMaster,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — ConsumerWidget so it can watch the profile + passport providers.
// ---------------------------------------------------------------------------

class _PassportBody extends ConsumerWidget {
  const _PassportBody({required this.onCamera, required this.onFindMaster});

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
      // Top inset matches Home's body: the shell-owned ClientTopBar sits
      // directly above, so the profile block needs a `lg` breathing gap (the
      // old in-body bar + its trailing `lg` SizedBox collapsed to this top
      // pad). This keeps the identity card at the SAME vertical position as
      // Home — no jump on nav.
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.lg,
        VelvetSpacing.lg,
        VelvetSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // (Top bar removed — now persistent chrome owned by ClientShell.)
          // Profile block — name / location (pin + city, no chevron) / phone.
          // Scoped Consumer: only this subtree rebuilds on a profile refresh.
          Consumer(
            builder: (BuildContext context, WidgetRef ref, _) {
              final AsyncValue<ClientProfileSummary> profileAsync = ref.watch(
                clientProfileProvider,
              );

              // Same explicit branch order as the hero below — deliberately NOT
              // `.when()`.
              //
              // A retry re-enters `AsyncLoading` while STILL carrying the
              // previous error, so `hasError` stays true for the whole in-flight
              // retry. Matching `isLoading` FIRST is what stops the error
              // affordance flashing straight back the instant the client taps
              // «Спробувати знову».
              //
              // A failure must NEVER fall through to a blank-field profile: a
              // synthesised all-empty [ClientProfileSummary] renders as the
              // placeholder city/phone lines and an initial-less avatar, which
              // is visually indistinguishable from "this client has no details
              // yet". That collapse is the same defect class that let the
              // always-empty passport bug hide for a whole phase.
              if (profileAsync.isLoading) {
                // Seamless reload: `ref.invalidate` RETAINS the previous value,
                // so keep a good profile on screen rather than collapsing to the
                // skeleton. Only a genuine first load re-skeletons.
                final ClientProfileSummary? retained = profileAsync.value;
                return retained == null
                    ? const _ProfileSkeleton()
                    : _ProfileBlock(profile: retained, onCamera: onCamera);
              }
              if (profileAsync.hasError) {
                return _ProfileError(
                  // The retry listener is on-screen and visible here, so the
                  // offstage-pause caveat (an invalidate whose only listeners
                  // are paused defers its refetch to resume) cannot bite.
                  onRetry: () => ref.invalidate(clientProfileProvider),
                );
              }
              final ClientProfileSummary? profile = profileAsync.value;
              return profile == null
                  ? const _ProfileSkeleton()
                  : _ProfileBlock(profile: profile, onCamera: onCamera);
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
                final AsyncValue<Passport> passportAsync = ref.watch(
                  passportProvider,
                );

                // Explicit branch order — deliberately NOT `.when()`.
                //
                // A retry puts the provider back into `AsyncLoading` while it
                // STILL CARRIES the previous error, so `hasError` stays true for
                // the whole in-flight retry. Matching `isLoading` FIRST is what
                // keeps the error card from flashing straight back the instant
                // the client taps «Спробувати знову».
                //
                // An error must NEVER fall through to the empty-passport
                // variant: that collapse is exactly what let the "always empty"
                // bug hide — a 401/500 looked identical to "no history yet".
                if (passportAsync.isLoading) {
                  // Seamless reload: `ref.invalidate` RETAINS the previous
                  // value, so if a good passport is already on screen keep it
                  // rendered rather than collapsing to the skeleton. Only a
                  // genuine first load (no retained value) shows the skeleton.
                  final Passport? retained = passportAsync.value;
                  return retained == null
                      ? const _PassportCardSkeleton()
                      : _PassportHero(
                          passport: retained,
                          onFindMaster: onFindMaster,
                        );
                }
                if (passportAsync.hasError) {
                  return _PassportError(
                    // The retry listener is on-screen and visible here, so the
                    // offstage-pause caveat (an invalidate whose only listeners
                    // are paused defers its refetch to resume) cannot bite.
                    onRetry: () => ref.invalidate(passportProvider),
                  );
                }
                final Passport? passport = passportAsync.value;
                return passport == null
                    ? const _PassportCardSkeleton()
                    : _PassportHero(
                        passport: passport,
                        onFindMaster: onFindMaster,
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
    // `BudgetBand.max` is a backend-derived double and `passportBudgetCeiling`
    // takes an `"type": "int"` placeholder, so it goes through the same
    // [renderableWholePrice] gate as the discovery search cards rather than a
    // bare `.round()`: that call THROWS `UnsupportedError` on `Infinity`/`NaN`
    // — inside `build()`, so a malformed payload would replace the passport
    // hero with an error widget — and silently SATURATES to
    // «9223372036854775807 ₴» above 2^63. Dormant today (the repository still
    // returns `PassportMapper.placeholder()` with a null budget); it arms when
    // backend 19.5 replaces that placeholder, which the mapper's `TODO(19.5)`
    // would not prompt anyone to harden. Unstatable ⇒ the existing
    // "budget not known" label, never a fabricated figure.
    final int? budgetCeiling = renderableWholePrice(budget?.max);
    final String budgetValue = budgetCeiling == null
        ? l10n.passportBudgetUnknown
        : l10n.passportBudgetCeiling(budgetCeiling);
    // Placeholder fallback for an absent memberSinceYear, mirrors
    // `home_hub_notifier.dart`'s identical fallback; a year-level display
    // value, not a calendar-day derivation.
    final String memberSince =
        passport.memberSinceYear?.toString() ??
        DateTime.now().year.toString(); // instant-ok: year-level value fallback
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

  static final TextStyle _bodyStyle = VelvetText.body14;

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

/// The passport FAILED TO LOAD. A DISTINCT state, never the empty variant.
///
/// The empty passport is an invitation ("book your first service and Beautica
/// starts collecting"); a failed fetch is a fault the client can act on by
/// retrying. Rendering the former for the latter is what let the always-empty
/// data layer hide for a whole phase — a 401/500 was pixel-identical to "no
/// history yet", so nobody could see the difference from the outside.
///
/// Deliberately built on [_EmptyPassport]'s geometry — the same extruded card,
/// the same 92 dp neumorphic well, the same title/body/CTA rhythm — so the
/// failure reads as the same surface in a different state rather than as a
/// foreign widget in the hero slot. Only the glyph, copy and CTA differ.
///
/// The retry is `ref.invalidate(passportProvider)`. Because the caller matches
/// `isLoading` BEFORE `hasError`, this card is unmounted for the whole
/// in-flight retry and the skeleton (or the retained passport) shows instead —
/// `AsyncLoading(retrying: true)` still reports `hasError`, so a `.when()` or a
/// `hasError`-first order would paint this card straight back under the
/// client's finger. That ordering is pinned by
/// `test/features/passport/presentation/passport_screen_test.dart`.
class _PassportError extends StatelessWidget {
  const _PassportError({required this.onRetry});

  final VoidCallback onRetry;

  static final BoxDecoration _cardDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    boxShadow: VelvetShadows.extrudedCard,
  );

  static const BoxDecoration _glyphWellDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  static final TextStyle _bodyStyle = VelvetText.body14;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('passport_error_state'),
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
            decoration: _glyphWellDecoration,
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 38,
              color: BrandColors.accent,
            ),
          ),
          const SizedBox(height: VelvetSpacing.lg),
          Text(
            l10n.passportErrorTitle,
            textAlign: TextAlign.center,
            style: VelvetText.subheading(),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Text(
            l10n.passportErrorBody,
            textAlign: TextAlign.center,
            style: _bodyStyle,
          ),
          const SizedBox(height: VelvetSpacing.lg),
          HubFilledButton(
            key: const Key('passport_retry_button'),
            label: l10n.retryLabel,
            onTap: onRetry,
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

  static final TextStyle _nameStyle = VelvetText.displayName21;
  static final TextStyle _lineStyle = VelvetText.body14Text;

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
              HubAvatar(initials: profile.initials, size: 96, fontSize: 27),
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
              _line(
                Icons.location_on_rounded,
                city,
                iconWidget: const AppIcon(
                  BeauticaAssetIcons.locationMarker,
                  size: 16,
                  color: BrandColors.accent,
                ),
              ),
              const SizedBox(height: VelvetSpacing.sm),
              _line(Icons.call_rounded, phone),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(IconData icon, String text, {Widget? iconWidget}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        iconWidget ?? Icon(icon, size: 16, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.sm),
        Flexible(
          child: Text(text, style: _lineStyle, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// The PROFILE FAILED TO LOAD. The sub-block counterpart of [_PassportError]:
/// same glyph (`cloud_off_rounded`), same accent tint, same neumorphic well,
/// same `retryLabel` CTA — nothing new enters the visual language. It is laid
/// out as a ROW on [_ProfileBlock]'s own geometry (a 96 dp well exactly where
/// the avatar sits, copy + retry exactly where the name/location/phone lines
/// sit) rather than as the hero's full extruded card: this is a sub-block, so
/// it gets the block's footprint and no more. Occupying that footprint also
/// keeps the passport hero at an unchanged vertical position — the failure
/// costs no layout jump.
///
/// The copy reuses `homeHubProfileLoadError` — the identical failure of the
/// identical `clientProfileProvider` already worded for the Home Hub's profile
/// section, so the two screens report one fault in one voice.
///
/// Like the hero, the caller matches `isLoading` BEFORE `hasError`, so this row
/// is unmounted for the whole in-flight retry — `AsyncLoading(retrying: true)`
/// still reports `hasError`, and a `.when()` or a `hasError`-first order would
/// paint the failure straight back under the client's finger. That ordering is
/// pinned by `test/features/passport/presentation/passport_profile_error_test.dart`.
class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.onRetry});

  final VoidCallback onRetry;

  static const BoxDecoration _glyphWellDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  static final TextStyle _messageStyle = VelvetText.body14Text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('passport_profile_error_state'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // Matches the avatar's 100 dp slot / 96 dp disc so the row keeps
        // _ProfileBlock's exact height and the hero below never shifts.
        SizedBox(
          height: 100,
          width: 100,
          child: Center(
            child: Container(
              height: 96,
              width: 96,
              decoration: _glyphWellDecoration,
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 38,
                color: BrandColors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: VelvetSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(l10n.homeHubProfileLoadError, style: _messageStyle),
              const SizedBox(height: VelvetSpacing.sm + 2),
              HubFilledButton(
                key: const Key('passport_profile_retry_button'),
                label: l10n.retryLabel,
                onTap: onRetry,
              ),
            ],
          ),
        ),
      ],
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
