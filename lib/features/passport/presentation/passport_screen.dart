// Phase 238 — the CLIENT BEAUTY PASSPORT page, rebuilt from the approved
// preview `docs/signup-designs/BeautyPassport/`.
//
// Four stacked blocks, read top to bottom as *who you are · what you want next*:
//
//   1. Profile block   — avatar + name + location + phone. UNCHANGED.
//   2. Identity strip  — a compact 2x2 counter-column card carrying the locked
//                        «BEAUTY PASSPORT» literal and the client's derived
//                        standing. Read-only.
//   3. Derived block   — «Улюблені райони та міста» + «Середній чек» (the
//                        AVERAGE, not a ceiling). Omitted entirely when there
//                        is nothing to report.
//   4. BEAUTY WISH LIST — a non-scrolling line of exactly two compact cards
//                        plus «Показати всі (N)».
//
// The top bar and the bottom nav are persistent chrome owned by `ClientShell`;
// this screen is only the body.
//
// ## WHAT THIS PHASE DELETED
//
// The full-page "document" card (`passport_table.dart`) is GONE, not unrouted:
// the ruled «Улюблені процедури» / «Улюблені райони» / «Бюджет» fields, the
// tally-dot rank affordance and the embossed «B» watermark, together with their
// ARB keys and the `passportBudgetCeiling` string Phase 235 left behind.
//
// The `_EmptyPassport` invitation hero went with it. That is a DIVERGENCE from
// the phase doc's deletion table, which does not name it, and it follows the
// approved preview: the preview's «Паспорт — без історії» variant renders
// profile + identity strip + wish list and NO empty hero. It is also the right
// shape — the identity strip is meaningful for a brand-new client («Жодного
// відгуку залишено» / «Користувач з 2026») and the wish list's own empty state
// already carries the «Знайти майстра» invitation, so an empty hero would be a
// second, competing call to the same action.
//
// ## THE PAGE NOW SCROLLS — AND THE CTAs DO NOT CLEAR THE FOLD
//
// Measured at 360x800 with the approved fixtures (identity strip 86 dp,
// derived block 142 dp, wish-list section 339 dp): body content is 779 dp, the
// two «Записатись» CTAs end at 709 dp and «Показати всі (N)» at 755 dp.
//
// The BODY's viewport is not 800. `ClientShell` mounts the top bar as FIXED
// chrome ABOVE this scroll view (`VelvetSpacing.sm` 8 + `ClientTopBar` 48 = 56)
// and the bottom nav BELOW it (`_barHeight` 64 + `_centerSize`/2 26 = 90), so
// the body gets 800 - 56 - 90 = 654 dp. The CTAs therefore sit ~55 dp BELOW the
// fold and the page scrolls ~125 dp.
//
// This DIVERGES from the approved preview's budget, which put the CTAs ~4 dp
// INSIDE a 710 dp fold — and the difference is structural, not a regression in
// this port: the preview scrolls its own top bar (8 + 48 + 16 = 72 dp) as part
// of the ListView's content, whereas the shipped shell pins it outside. Those
// 56 dp come straight off the visible area. Recorded rather than silently
// absorbed; the preview's README is explicit that this budget is "to spend
// deliberately, not to discover".
//
// Rhythm is a flat `VelvetSpacing.lg` between blocks with ONE deliberate
// exception: the `md` gap binding the derived block to the identity strip,
// because the derived block is the strip's data page and the pair is one unit.
//
// ## PII
//
// The profile block renders real client name / phone / city, so this screen
// acquires the app-wide [ScreenProtectionManager] (FLAG_SECURE / iOS
// app-switcher blur) on mount and releases it on unmount — same pattern as
// HomeHubScreen (§ CRITICAL-4). Hence ConsumerStatefulWidget.
//
// ## THE ASYNC BRANCH ORDER IS EXPLICIT AND LOAD-BEARING
//
// Every async surface here branches `isLoading` → `hasError` → value, NEVER
// `.when()`. Riverpod carries the previous error forward through an in-flight
// retry (`AsyncLoading(retrying: true)` still reports `hasError`), so a
// `hasError`-first order would paint the failure straight back under the
// client's finger. And an error must NEVER degrade into an empty / no-data
// rendering: that collapse is exactly what let the always-empty passport bug
// hide for a whole phase, and the two are separately test-pinned.
//
// The profile, the passport and the wish list each watch their provider in
// their OWN [Consumer] subtree, so a refresh of one does not rebuild the others.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icon.dart';
import '../../../core/icons/beautica_asset_icons.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/staggered_reveal.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/formatters/booking_price_labels.dart';
import '../../home/application/home_hub_notifier.dart';
import '../../home/domain/home_hub_models.dart';
import '../../home/presentation/widgets/hub_widgets.dart';
import '../../wishlist/presentation/widgets/wishlist_rebook.dart';
import '../../wishlist/presentation/widgets/wishlist_section.dart';
import '../application/passport_notifier.dart';
import '../domain/passport.dart';
import 'widgets/passport_derived_block.dart';
import 'widgets/passport_identity_strip.dart';

/// The CLIENT BEAUTY PASSPORT page — bottom-nav tab index 4.
class PassportScreen extends ConsumerStatefulWidget {
  const PassportScreen({super.key});

  @override
  ConsumerState<PassportScreen> createState() => _PassportScreenState();
}

class _PassportScreenState extends ConsumerState<PassportScreen>
    with WishlistRebookHost {
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
    // The wish list's empty-state CTA sends the client to discovery (Пошук).
    context.go(RouteNames.clientSearch);
  }

  void _onShowAllFavourites() {
    // `push`, not `go`: this is a pushed leaf on the passport branch's own
    // navigator, so swipe-back returns to the still-scrolled passport page.
    context.push(RouteNames.clientWishlist);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Stable branch key: the client-shell E2E flow's branch-4 assertion (and
      // the passport flow) target this locale-independent key.
      key: const Key('client-branch-passport'),
      backgroundColor: BrandColors.base,
      // Top bar AND bottom nav are hosted by ClientShell — this screen is just
      // the body. The shell owns the single SafeArea(top), so the body must NOT
      // re-wrap one.
      body: RepaintBoundary(
        child: StaggeredReveal(
          builder: (BuildContext context, RevealFn reveal) {
            return ListView(
              // Top inset matches Home's body exactly: the shell-owned
              // ClientTopBar sits directly above, so the profile block needs the
              // same `lg` breathing gap. Keeping the two equal is what stops the
              // identity card jumping vertically on every Home↔Passport switch
              // (pinned by passport_home_card_alignment_regression_test).
              padding: const EdgeInsets.fromLTRB(
                VelvetSpacing.lg,
                VelvetSpacing.lg,
                VelvetSpacing.lg,
                VelvetSpacing.lg,
              ),
              children: <Widget>[
                // 1. Profile block — its own Consumer, so a profile refresh
                //    does not rebuild the strip or the wish list.
                reveal(
                  start: 0.06,
                  end: 0.46,
                  child: _ProfileSection(onCamera: _onCameraTap),
                ),
                const SizedBox(height: VelvetSpacing.lg),
                // 2 + 3. Identity strip and its data page. One Consumer: both
                //    read the SAME passport payload, so splitting them would
                //    double the watch for no rebuild saving.
                _PassportSection(reveal: reveal),
                const SizedBox(height: VelvetSpacing.lg),
                // 4. BEAUTY WISH LIST — watches `wishlistProvider` internally.
                reveal(
                  start: 0.28,
                  end: 0.68,
                  child: WishlistSection(
                    // Phase 241 — WishlistRebookHost, shared verbatim with
                    // WishlistScreen so the two «Записатись» CTAs can never
                    // diverge (see wishlist_rebook.dart).
                    onBook: rebook,
                    onFindMaster: _onFindMaster,
                    onShowAll: _onShowAllFavourites,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Identity strip + derived block
// ---------------------------------------------------------------------------

/// Watches `passportProvider` and renders the strip and, when there is anything
/// to report, the derived block beneath it.
class _PassportSection extends ConsumerWidget {
  const _PassportSection({required this.reveal});

  final RevealFn reveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Passport> async = ref.watch(passportProvider);

    // Explicit branch order — see the file header.
    if (async.isLoading) {
      // Seamless reload: `ref.invalidate` RETAINS the previous value, so keep a
      // good passport on screen rather than collapsing to the skeleton. Only a
      // genuine FIRST load re-skeletons.
      final Passport? retained = async.value;
      return retained == null
          ? reveal(start: 0.14, end: 0.54, child: const _PassportSkeleton())
          : _content(context, retained);
    }
    if (async.hasError) {
      return reveal(
        start: 0.14,
        end: 0.54,
        child: _PassportError(
          // The retry listener is on-screen and visible here, so the
          // offstage-pause caveat (an invalidate whose only listeners are
          // paused defers its refetch to resume) cannot bite.
          onRetry: () => ref.invalidate(passportProvider),
        ),
      );
    }
    final Passport? passport = async.value;
    return passport == null
        ? reveal(start: 0.14, end: 0.54, child: const _PassportSkeleton())
        : _content(context, passport);
  }

  Widget _content(BuildContext context, Passport passport) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    // Phase 235: the page shows the AVERAGE («750 ₴»), not the ceiling
    // («до 800 ₴»). `BudgetBand.avg` is a backend-derived double and
    // `passportBudgetAverage` takes an `"type": "int"` placeholder, so it goes
    // through the same [renderableWholePrice] gate as the discovery search
    // cards rather than a bare `.round()`: that call THROWS `UnsupportedError`
    // on Infinity/NaN — and `jsonDecode('1e400')` yields `double.infinity`
    // without throwing — and silently SATURATES to «9223372036854775807 ₴»
    // above 2^63. Unstatable ⇒ NO figure at all, so the block renders its bare
    // «—» rather than a fabricated number.
    final int? average = renderableWholePrice(passport.budget?.avg);
    final PassportDerivedBlock derived = PassportDerivedBlock(
      districts: passport.favoriteDistricts,
      cities: passport.favoriteCities,
      averageSpend: average == null
          ? null
          : l10n.passportBudgetAverage(average),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        reveal(
          start: 0.14,
          end: 0.54,
          // No fallback for the year: [Passport.memberSinceYear] is a required
          // non-null int and the mapper throws rather than inventing one. The
          // `DateTime.now().year` default that used to live here fabricated the
          // current year for every client whose payload lacked the field.
          child: PassportIdentityStrip(
            reviewsWritten: passport.reviewsWritten,
            memberSinceYear: passport.memberSinceYear,
          ),
        ),
        // `md`, not `lg`: the derived block is the identity strip's data page,
        // so the pair is bound tighter than the page's blocks are to each other.
        if (derived.hasContent) ...<Widget>[
          const SizedBox(height: VelvetSpacing.md),
          reveal(start: 0.20, end: 0.60, child: derived),
        ],
      ],
    );
  }
}

/// The passport FAILED TO LOAD. A DISTINCT state, never a silent degrade.
///
/// A failed fetch is a fault the client can act on by retrying; rendering it as
/// "nothing derived yet" is what let the always-empty data layer hide for a
/// whole phase, because a 401/500 was pixel-identical to a new account.
///
/// Deliberately built on the identity strip's own silhouette — same extruded
/// card, same radius — so the failure reads as the same surface in a different
/// state rather than as a foreign widget in the strip's slot.
///
/// Because the caller matches `isLoading` BEFORE `hasError`, this card is
/// unmounted for the whole in-flight retry and the skeleton (or the retained
/// passport) shows instead.
class _PassportError extends StatelessWidget {
  const _PassportError({required this.onRetry});

  final VoidCallback onRetry;

  static const double _kWell = 64;
  static const double _kWellGlyph = 28;

  static final BoxDecoration _cardDecoration = BoxDecoration(
    color: BrandColors.base,
    borderRadius: BorderRadius.circular(VelvetRadii.card),
    boxShadow: VelvetShadows.extrudedCard,
  );

  static const BoxDecoration _wellDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
            height: _kWell,
            width: _kWell,
            decoration: _wellDecoration,
            child: const Icon(
              Icons.cloud_off_rounded,
              size: _kWellGlyph,
              color: BrandColors.accent,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          Text(
            l10n.passportErrorTitle,
            textAlign: TextAlign.center,
            style: VelvetText.subheading(),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Text(
            l10n.passportErrorBody,
            textAlign: TextAlign.center,
            style: VelvetText.body14,
          ),
          const SizedBox(height: VelvetSpacing.md),
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

/// The identity strip's first-load placeholder. Sized to the strip's own
/// resting height so nothing below it jumps when the payload lands.
class _PassportSkeleton extends StatelessWidget {
  const _PassportSkeleton();

  static const double _kHeight = 66;

  static final BoxDecoration _decoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.22),
    borderRadius: BorderRadius.circular(VelvetRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('passport_skeleton'),
      height: _kHeight,
      decoration: _decoration,
    );
  }
}

// ---------------------------------------------------------------------------
// Profile block — mirrors the Головна profile block; NO location chevron/tap.
// ---------------------------------------------------------------------------

/// Watches `clientProfileProvider` in its own subtree.
class _ProfileSection extends ConsumerWidget {
  const _ProfileSection({required this.onCamera});

  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ClientProfileSummary> async = ref.watch(
      clientProfileProvider,
    );

    // Same explicit branch order as the passport section above.
    //
    // A failure must NEVER fall through to a blank-field profile: a synthesised
    // all-empty [ClientProfileSummary] renders as the placeholder city/phone
    // lines and an initial-less avatar, which is visually indistinguishable
    // from "this client has no details yet".
    if (async.isLoading) {
      final ClientProfileSummary? retained = async.value;
      return retained == null
          ? const _ProfileSkeleton()
          : _ProfileBlock(profile: retained, onCamera: onCamera);
    }
    if (async.hasError) {
      return _ProfileError(
        onRetry: () => ref.invalidate(clientProfileProvider),
      );
    }
    final ClientProfileSummary? profile = async.value;
    return profile == null
        ? const _ProfileSkeleton()
        : _ProfileBlock(profile: profile, onCamera: onCamera);
  }
}

class _ProfileBlock extends StatelessWidget {
  const _ProfileBlock({required this.profile, required this.onCamera});

  final ClientProfileSummary profile;
  final VoidCallback onCamera;

  static const double _kSlot = 100;
  static const double _kAvatar = 96;
  static const double _kBadge = 30;
  static const double _kBadgeGlyph = 15;
  static const double _kMetaGlyph = 16;

  static final TextStyle _nameStyle = VelvetText.displayName21;
  static final TextStyle _lineStyle = VelvetText.body14Text;

  static final BoxDecoration _cameraBadgeDecoration = BoxDecoration(
    color: BrandColors.white,
    shape: BoxShape.circle,
    border: Border.all(color: BrandColors.base, width: 2),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
          height: _kSlot,
          width: _kSlot,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              HubAvatar(
                initials: profile.initials,
                size: _kAvatar,
                fontSize: 27,
              ),
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
                      height: _kBadge,
                      width: _kBadge,
                      decoration: _cameraBadgeDecoration,
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        size: _kBadgeGlyph,
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
              const SizedBox(height: AppSpacing.xxs),
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
                  size: _kMetaGlyph,
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
        iconWidget ?? Icon(icon, size: _kMetaGlyph, color: BrandColors.accent),
        const SizedBox(width: VelvetSpacing.sm),
        Flexible(
          child: Text(text, style: _lineStyle, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// The PROFILE FAILED TO LOAD. The sub-block counterpart of [_PassportError]:
/// same glyph, same accent tint, same neumorphic well, same `retryLabel` CTA —
/// nothing new enters the visual language. Laid out as a ROW on
/// [_ProfileBlock]'s own geometry so the failure costs no layout jump.
///
/// The copy reuses `homeHubProfileLoadError` — the identical failure of the
/// identical `clientProfileProvider`, already worded for the Home Hub's profile
/// section, so the two screens report one fault in one voice.
class _ProfileError extends StatelessWidget {
  const _ProfileError({required this.onRetry});

  final VoidCallback onRetry;

  static const double _kSlot = 100;
  static const double _kWell = 96;
  static const double _kGlyph = 38;

  static const BoxDecoration _glyphWellDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  static final TextStyle _messageStyle = VelvetText.body14Text;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Row(
      key: const Key('passport_profile_error_state'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // Matches the avatar's 100 dp slot / 96 dp disc so the row keeps
        // _ProfileBlock's exact height and the strip below never shifts.
        SizedBox(
          height: _kSlot,
          width: _kSlot,
          child: Center(
            child: Container(
              height: _kWell,
              width: _kWell,
              decoration: _glyphWellDecoration,
              child: const Icon(
                Icons.cloud_off_rounded,
                size: _kGlyph,
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

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  static const double _kAvatar = 96;

  static final BoxDecoration _avatarDecoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    shape: BoxShape.circle,
  );
  static final BoxDecoration _barDecoration = BoxDecoration(
    color: BrandColors.faint.withValues(alpha: 0.3),
    borderRadius: BorderRadius.circular(AppSpacing.xs),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          height: _kAvatar,
          width: _kAvatar,
          decoration: _avatarDecoration,
        ),
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
