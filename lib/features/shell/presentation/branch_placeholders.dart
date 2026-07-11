// Phase 13.1 — CLIENT shell branch placeholder screens.
//
// Minimal neumorphic "Скоро…" panels so the reviewer can tap every tab and
// watch selection + the elevated-center behaviour while the real screens are
// built in later phases (Головна → 13.7, Улюблені → 13.11, Пошук → 13.3,
// Записи → 14.3, BEAUTY PASSPORT → 13.8). Each is removed as its real screen
// ships.
//
// Ported from the approved preview app
// `docs/signup-designs/ClientShell/lib/screens/client_shell_screen.dart`
// (the `_BranchBody` + `_ComingSoonChip` + `StaggeredReveal`). Hard-coded
// Ukrainian copy → l10n; `VelvetColors.*` → `BrandColors.*`. The staggered
// entrance subtree is wrapped in a RepaintBoundary so the one animated moment
// never repaints the rest of the shell.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';

import 'widgets/client_bottom_nav.dart';

/// A single client-shell branch placeholder: a calm centered "Скоро…" panel.
///
/// [title] and [blurb] are supplied already-localised by the branch screens
/// below; [icon] is the branch glyph.
///
/// For tabs whose icon is now an SVG asset (e.g. Головна), supply
/// [iconWidget] instead of [icon]. When [iconWidget] is non-null it is
/// rendered inside the pillow in place of the [Icon] widget and [icon] is
/// ignored.
class ClientBranchPlaceholder extends StatelessWidget {
  const ClientBranchPlaceholder({
    super.key,
    required this.title,
    required this.blurb,
    this.icon,
    this.iconWidget,
  });

  final String title;
  final String blurb;

  /// Material glyph for the branch. Ignored when [iconWidget] is non-null.
  /// Either [icon] or [iconWidget] must be provided.
  final IconData? icon;

  /// Optional widget rendered inside the pillow instead of [icon].
  /// Use this for tabs whose icon comes from [BeauticaAssetIcons].
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The whole staggered entrance subtree is isolated so its 1s reveal repaint
    // is bounded and never bleeds into the surrounding shell.
    return RepaintBoundary(
      child: _StaggeredReveal(
        builder: (BuildContext context, _RevealFn reveal) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              VelvetSpacing.lg,
              VelvetSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                reveal(
                  start: 0.0,
                  end: 0.5,
                  child: Text(l10n.appTitle, style: VelvetText.wordmark()),
                ),
                const Spacer(),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      reveal(
                        start: 0.1,
                        end: 0.6,
                        child: _IconPillow(icon: icon, iconWidget: iconWidget),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),
                      reveal(
                        start: 0.25,
                        end: 0.75,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: VelvetText.heading(),
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.sm),
                      reveal(
                        start: 0.35,
                        end: 0.85,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 300),
                          child: Text(
                            blurb,
                            textAlign: TextAlign.center,
                            style: VelvetText.body(),
                          ),
                        ),
                      ),
                      const SizedBox(height: VelvetSpacing.lg),
                      reveal(
                        start: 0.45,
                        end: 0.95,
                        child: _ComingSoonChip(label: l10n.clientComingSoon),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A 96dp extruded neumorphic pillow cradling the branch glyph.
///
/// When [iconWidget] is non-null it is rendered in the centre instead of
/// `Icon([icon], ...)`. Size and tint are equivalent: [iconWidget] is expected
/// to be 40×40 dp tinted to [BrandColors.accentDeep] (callers should use
/// `AppIcon(..., size: 40, color: BrandColors.accentDeep)`).
class _IconPillow extends StatelessWidget {
  const _IconPillow({this.icon, this.iconWidget});

  final IconData? icon;
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      width: 96,
      decoration: const BoxDecoration(
        color: BrandColors.base,
        shape: BoxShape.circle,
        boxShadow: VelvetShadows.extrudedCard,
      ),
      child: Center(
        child:
            iconWidget ??
            Icon(icon ?? Icons.circle, size: 40, color: BrandColors.accentDeep),
      ),
    );
  }
}

/// A small raised "Скоро…" chip — the placeholder marker for branches whose
/// real screen ships in a later phase.
class _ComingSoonChip extends StatelessWidget {
  const _ComingSoonChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      radius: 22,
      shadows: VelvetShadows.extrudedSmall,
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.md,
        vertical: VelvetSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.auto_awesome_rounded,
            size: 14,
            color: BrandColors.accent,
          ),
          const SizedBox(width: VelvetSpacing.sm - 2),
          Text(label, style: VelvetText.shellComingSoonLabel),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Головна — Phase 13.7. CLIENT post-login landing + branch index 0.
// ---------------------------------------------------------------------------
class ClientHomePlaceholderScreen extends StatelessWidget {
  const ClientHomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClientBranchPlaceholder(
      key: const Key('client-branch-home'),
      title: l10n.clientPlaceholderHomeTitle,
      blurb: l10n.clientPlaceholderHomeBlurb,
      iconWidget: const AppIcon(
        BeauticaAssetIcons.homeFilled,
        size: 40,
        color: BrandColors.accentDeep,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Улюблені — Phase 13.11.
// ---------------------------------------------------------------------------
class ClientFavoritesPlaceholderScreen extends StatelessWidget {
  const ClientFavoritesPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClientBranchPlaceholder(
      key: const Key('client-branch-favorites'),
      title: l10n.clientPlaceholderFavoritesTitle,
      blurb: l10n.clientPlaceholderFavoritesBlurb,
      iconWidget: const AppIcon(
        BeauticaAssetIcons.heartFilled,
        size: 40,
        color: BrandColors.accentDeep,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Пошук — Phase 13.3.
// ---------------------------------------------------------------------------
class ClientSearchPlaceholderScreen extends StatelessWidget {
  const ClientSearchPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClientBranchPlaceholder(
      key: const Key('client-branch-search'),
      title: l10n.clientPlaceholderSearchTitle,
      blurb: l10n.clientPlaceholderSearchBlurb,
      iconWidget: const AppIcon(
        BeauticaAssetIcons.searchFilled,
        size: 40,
        color: BrandColors.accentDeep,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Записи — Phase 14.3.
// ---------------------------------------------------------------------------
class ClientBookingsPlaceholderScreen extends StatelessWidget {
  const ClientBookingsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClientBranchPlaceholder(
      key: const Key('client-branch-bookings'),
      title: l10n.clientPlaceholderBookingsTitle,
      blurb: l10n.clientPlaceholderBookingsBlurb,
      iconWidget: const AppIcon(
        BeauticaAssetIcons.noteFilled,
        size: 40,
        color: BrandColors.accentDeep,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// BEAUTY PASSPORT — Phase 13.8. Title is the untranslated brand constant
// [kBeautyPassportLabel]; only the blurb is localised.
// ---------------------------------------------------------------------------
class ClientPassportPlaceholderScreen extends StatelessWidget {
  const ClientPassportPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ClientBranchPlaceholder(
      key: const Key('client-branch-passport'),
      title: kBeautyPassportLabel,
      blurb: l10n.clientPlaceholderPassportBlurb,
      iconWidget: const AppIcon(
        BeauticaAssetIcons.passportFilled,
        size: 40,
        color: BrandColors.accentDeep,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Staggered fade-up entrance (ported verbatim from the preview's
// `staggered_reveal.dart`). Kept local to this file — it is only used by the
// placeholder bodies and will retire alongside them as real screens ship.
// ---------------------------------------------------------------------------

typedef _RevealFn =
    Widget Function({
      required double start,
      required double end,
      required Widget child,
    });

class _StaggeredReveal extends StatefulWidget {
  const _StaggeredReveal({required this.builder});

  final Widget Function(BuildContext context, _RevealFn reveal) builder;

  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<_StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // PERF (MEDIUM): the CLIENT shell is a StatefulShellRoute.indexedStack, so all
  // five branches build and keep-alive at mount. Without this gate, the four
  // off-screen 1s reveal controllers would all fire during the post-login frame
  // budget. IndexedStack sets TickerMode=false for its off-screen children, so
  // we only start the reveal once ticking is enabled (the visible branch) and
  // react to it flipping true the first time a branch becomes visible on a tab
  // switch — see didChangeDependencies.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start the one-shot reveal only when this branch is actually ticking
    // (i.e. it is the visible IndexedStack child). Off-screen branches have
    // TickerMode=false at mount and flip to true the first time their tab is
    // selected, at which point this fires and the reveal plays once.
    if (!_started && TickerMode.valuesOf(context).enabled) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    // PERF (LOW): drive fade + upward slide via FadeTransition + SlideTransition
    // (layer-level — no per-frame widget rebuild) instead of an AnimatedBuilder
    // rebuilding Opacity + Transform.translate every tick. The slide starts
    // ~18 logical px below (0.18 of the ~100px subtree band ≈ the previous fixed
    // 18px offset feel) and settles to zero as the interval completes.
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reveal);
}

// ---------------------------------------------------------------------------
// Бронювання (підтвердження) — Phase 14.1 stub for `/booking/confirm`. A
// standalone (pushed, full-screen) «Скоро…» panel reached from the Step 2
// time screen's «Підтвердити» CTA, so the booking flow's route/args contract
// is exercised end-to-end even though the real confirmation/create-booking
// screen ships in Phase 14.2. `BookingNewPlaceholderScreen` (the OLDER
// placeholder this one supersedes at a different route) is retired — Phase
// 14.1 replaces `/booking/new` with the real `ServiceSelectorSheet`. Unlike
// the branch placeholders above, this screen carries its own top bar (with a
// back arrow) because it is pushed onto the navigator, not hosted by the
// client shell.
// ---------------------------------------------------------------------------
class BookingConfirmPlaceholderScreen extends StatelessWidget {
  const BookingConfirmPlaceholderScreen({super.key, this.args});

  /// The [BookingConfirmArgs] handed off by `SlotTimeScreen`. Nullable so a
  /// stray direct navigation (missing/invalid `extra`) still renders this
  /// placeholder instead of crashing; the app_router redirect guard normally
  /// prevents that case from ever reaching here. Not yet rendered — Phase
  /// 14.2 replaces this whole screen with the real confirmation flow.
  final Object? args;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            VelvetTopBar(
              title: l10n.bookingNewPlaceholderTitle,
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ClientBranchPlaceholder(
                key: const Key('booking-confirm-placeholder'),
                title: l10n.bookingNewPlaceholderTitle,
                blurb: l10n.bookingNewPlaceholderBlurb,
                icon: Icons.event_available_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
