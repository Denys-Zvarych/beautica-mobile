// Phase 2.16 — Shared chrome for the multi-step registration wizard.
//
// SOURCE OF TRUTH: docs/signup-designs/sign-up-page.html (and the 2.17 /
// 2.19 sibling pages, which share the IDENTICAL screen-header block).
//
// Wraps each step screen with:
//   • AuthScaffold (espresso bg + gradient painter + safe area + scroll).
//   • Brand row (monogram B + BEAUTICA wordmark).
//   • Role chip — reads role from `registerDraftProvider`. If the draft is
//     null (e.g. deep-link to /register without picking a role first),
//     redirects to /register/role.
//   • Two-line headline with Cormorant Garamond italic accent on the second
//     line — varies per step.
//   • `RegistrationProgress(currentStep: …)` derived from the current route.
//   • Glassmorphism card hosting the step's child widget.
//   • "← Назад" back link — hidden on Step 1; on Step 2/3 returns to the
//     previous step. The back link preserves the [RegisterDraft] state (no
//     `reset` is called — controllers re-hydrate from the draft on rebuild).

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../../../shared/widgets/auth_scaffold.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'user_role_l10n.dart';
import 'widgets/registration_progress.dart';

// ---------------------------------------------------------------------------
// Static style constants — literal CSS values, allocated once.
// ---------------------------------------------------------------------------

const _kGlassRadius = BorderRadius.all(Radius.circular(22));

const _kGlassDecoration = BoxDecoration(
  color: Color(0x11FFFFFF), // rgba(255,255,255,0.065)
  borderRadius: _kGlassRadius,
  border: Border.fromBorderSide(BorderSide(color: Color(0x1AFFFFFF), width: 1)),
);

const _kMonogramDecoration = BoxDecoration(
  color: Color(0x1AFFFFFF),
  borderRadius: BorderRadius.all(Radius.circular(10)),
  border: Border.fromBorderSide(BorderSide(color: Color(0x33FFFFFF), width: 1)),
);

const _kRoleChipDecoration = BoxDecoration(
  color: Color(0x1AB89A7A), // rgba(184,154,122,0.1)
  borderRadius: BorderRadius.all(Radius.circular(20)),
  border: Border.fromBorderSide(
    BorderSide(color: Color(0x47B89A7A), width: 1), // 0.28 alpha
  ),
);

const _kRoleChipTextStyle = TextStyle(
  color: BrandColors.camel,
  fontSize: 11,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.44,
);

const _kBackLinkStyle = TextStyle(
  color: BrandColors.camel,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

const _kBrandNameStyle = TextStyle(
  color: Color(0xEBFFFFFF),
  fontSize: 18,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.6,
);

const _kMonogramTextStyle = TextStyle(
  color: Color(0xF2FFFFFF),
  fontSize: 20,
  fontWeight: FontWeight.w700,
  height: 1,
);

final _kBlur = ImageFilter.blur(sigmaX: 20, sigmaY: 20);

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shared wizard chrome — wraps each step screen with the brand row, role
/// chip, hero headline, 4-pill progress, glass card, and back link.
///
/// Phase 2.16 HIGH-2 — Stateful so the shell owns the screenshot/recents
/// suppression for ALL wizard steps. Step 1 (and any future Step 2/3) no
/// longer need to call `ScreenProtector` individually — the shell switches
/// it on in [initState] and off in [dispose] for the entire wizard lifetime.
class RegisterFlowShell extends ConsumerStatefulWidget {
  const RegisterFlowShell({super.key, required this.child});

  /// The step screen rendered inside the glassmorphism card.
  final Widget child;

  @override
  ConsumerState<RegisterFlowShell> createState() => _RegisterFlowShellState();
}

class _RegisterFlowShellState extends ConsumerState<RegisterFlowShell> {
  /// Phase 2.16 MEDIUM-perf-1 — guards against the missing-role redirect
  /// being scheduled more than once per shell lifetime. Without it, every
  /// rebuild during a transition would queue a redundant `context.go(...)`.
  bool _redirectScheduled = false;

  @override
  void initState() {
    super.initState();
    // HIGH-2 — Apply screen capture suppression for the WHOLE wizard. Sibling
    // screens (login, verification, role-selection) do this individually; the
    // shell handles it centrally for Step 1 / Step 2 / Step 3.
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOn();
    }
  }

  @override
  void dispose() {
    if (!kDebugMode) {
      ScreenProtector.preventScreenshotOff();
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MEDIUM-perf-1 — Run the null-role guard here (not in build) so the
    // redirect is scheduled exactly once even if the shell rebuilds during
    // a transition. The [_redirectScheduled] flag is the single source of
    // truth for "have we already queued the bounce-back".
    //
    // Navigation-race guard (Phase 2.16 bug-fix): only bounce to
    // role-selection when the user has no role AND is still on a wizard
    // route. Inside a ShellRoute, `GoRouterState.of(context).matchedLocation`
    // only reflects the current CHILD route of the shell (e.g. '/register')
    // — it does NOT update to '/login' when the user navigates OUTSIDE the
    // shell, because the shell's InheritedGoRouter is scoped to its own
    // sub-tree. To get the authoritative full-app location we use
    // `GoRouter.of(context).routerDelegate.currentConfiguration.fullPath`,
    // which is always up-to-date at post-frame time (after go_router has
    // committed the route change). This makes the check timing-independent:
    //   • deep-link to /register with no role → fullPath == '/register' at
    //     post-frame → stillInWizard → bounce fires correctly.
    //   • intentional exit via "log in" → fullPath == '/login' at post-frame
    //     → !stillInWizard → bounce is suppressed.
    final role = ref.read(registerDraftProvider.select((d) => d?.role));
    if (role == null && !_redirectScheduled) {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Re-read the authoritative app-level route at fire time. By the
        // time this post-frame callback runs, go_router has always committed
        // its full route update (including navigations that exit the shell),
        // so fullPath is authoritative and timing-race-free.
        final fullPath = GoRouter.of(
          context,
        ).routerDelegate.currentConfiguration.fullPath;
        final stillInWizard =
            fullPath == RouteNames.register ||
            fullPath == RouteNames.registerStep2 ||
            fullPath == RouteNames.registerStep3;
        if (!stillInWizard) return;
        context.go(RouteNames.registerRole);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // PERF rule M8: only watch the role slice — the rest of the draft
    // changes on every keystroke and would cause the whole shell to rebuild.
    final role = ref.watch(registerDraftProvider.select((d) => d?.role));

    // Defensive: if no role is set (deep-link to /register without picking a
    // role first, OR the wizard is being exited via the "log in instead" link),
    // render a placeholder while the post-frame callback resolves. The post-
    // frame callback in didChangeDependencies will bounce to /register/role only
    // if the live matchedLocation is still a wizard path when it fires — so
    // this placeholder renders safely for one frame in both the deep-link and
    // the intentional-exit cases.
    if (role == null) {
      return const AuthScaffold(child: SizedBox.shrink());
    }

    final location = GoRouterState.of(context).matchedLocation;
    final step = _stepForLocation(location);
    final headline = _headlineFor(step, location, role, l10n);
    final activeLabel = _labelForLocation(location, l10n);

    return AuthScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const _ShellBrandRow(key: Key('brand-row')),
          const SizedBox(height: 24),
          _RoleChip(role: role, l10n: l10n),
          const SizedBox(height: 14),
          _HeadlineBlock(
            line1: headline.$1,
            line2: headline.$2,
            key: const Key('shell-headline'),
          ),
          const SizedBox(height: 28),
          RegistrationProgress(
            key: const Key('registration-progress'),
            currentStep: step,
            activeStepLabel: activeLabel,
          ),
          const SizedBox(height: 20),
          _GlassCard(child: widget.child),
          const SizedBox(height: AppSpacing.xs),
          if (step != RegistrationStep.account)
            _BackLink(
              step: step,
              location: location,
              label: l10n.registerBackStep,
              key: const Key('btn-back-step'),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }

  /// Maps a `go_router` matched-location string to the [RegistrationStep]
  /// the progress widget should render. The verification + done screens
  /// are NOT inside this shell (they have their own AuthScaffold), so
  /// they never resolve here — the default branch keeps Step 1 active.
  static RegistrationStep _stepForLocation(String location) {
    if (location == RouteNames.registerStep2) return RegistrationStep.details;
    if (location == RouteNames.registerStep3) {
      // Step 3 also lands on the "details" pill — there is no 3rd
      // pre-verification pill. The spec is explicit: 4 pills are
      // account / details / verification / done. Step 3 is still part of
      // the "details" collection grouping alongside Step 2 per the design
      // (sign-up-step-3-address.html shows the SAME 4-pill row with
      // `details` active). Keep `details` active for both Step 2 and Step 3.
      return RegistrationStep.details;
    }
    return RegistrationStep.account;
  }

  /// Per-route active-label copy for the 4-dot progress widget.
  ///
  /// Step 2 and Step 3 both collapse to [RegistrationStep.details] (dot 2 is
  /// active for both routes) — the only thing that differs is the label
  /// rendered under dot 2: "Профіль" on /register/step-2 and "Локація" on
  /// /register/step-3. This helper returns the correct localised label per
  /// route. The verification + done screens render their own progress widget
  /// outside the shell and pass their own labels.
  static String _labelForLocation(String location, AppLocalizations l10n) {
    if (location == RouteNames.register) return l10n.registerProgressAccount;
    if (location == RouteNames.registerStep2) {
      return l10n.registerProgressProfile;
    }
    if (location == RouteNames.registerStep3) {
      return l10n.registerProgressLocation;
    }
    // Defensive fallback — should never happen since the shell only mounts on
    // /register*; keep the Account label to avoid a blank progress row.
    return l10n.registerProgressAccount;
  }

  /// Per-step headline copy (line 1 in Manrope 700, line 2 in Cormorant
  /// Garamond italic camel accent). Reads from l10n so UA / EN switch
  /// correctly.
  ///
  /// Both Step 2 and Step 3 map to [RegistrationStep.details], so the headline
  /// is disambiguated by [location]:
  ///   • /register/step-2 → "Особисті / дані" (role-agnostic, Phase 2.17).
  ///   • /register/step-3 → per-role address headline (Phase 2.19):
  ///       CLIENT → "Ваше / місто", MASTER → "Де ви / працюєте",
  ///       OWNER  → "Адреса / салону".
  static (String, String) _headlineFor(
    RegistrationStep step,
    String location,
    UserRole role,
    AppLocalizations l10n,
  ) {
    switch (step) {
      case RegistrationStep.account:
        return (l10n.registerStep1Headline, l10n.registerStep1HeadlineAccent);
      case RegistrationStep.details:
        if (location == RouteNames.registerStep3) {
          return switch (role) {
            UserRole.client => (
              l10n.step3HeadlineClientLine1,
              l10n.step3HeadlineClientLine2,
            ),
            UserRole.salonOwner => (
              l10n.step3HeadlineOwnerLine1,
              l10n.step3HeadlineOwnerLine2,
            ),
            // INDEPENDENT_MASTER (and any salon staff roles that ever reach the
            // wizard) use the "Де ви / працюєте" provider headline.
            _ => (l10n.step3HeadlineMasterLine1, l10n.step3HeadlineMasterLine2),
          };
        }
        // Step 2 — role-agnostic "Особисті / дані" headline (Phase 2.17).
        return (l10n.step2HeadlineLine1, l10n.step2HeadlineLine2);
      case RegistrationStep.verification:
        return (l10n.verificationHeadline, l10n.verificationHeadlineAccent);
      case RegistrationStep.done:
        return (l10n.registerStep1Headline, l10n.registerStep1HeadlineAccent);
    }
  }
}

// ---------------------------------------------------------------------------
// _ShellBrandRow — monogram B + BEAUTICA
// ---------------------------------------------------------------------------

class _ShellBrandRow extends StatelessWidget {
  const _ShellBrandRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            child: DecoratedBox(
              decoration: _kMonogramDecoration,
              child: Center(
                child: Text(
                  // ignore: no_raw_ui_strings
                  // Single-letter brand monogram — exempt from l10n per
                  // mobile-backlog known-issue pattern §5.
                  'B',
                  style: _kMonogramTextStyle,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: AppSpacing.xs),
        Text(
          // ignore: no_raw_ui_strings
          // Brand wordmark — exempt from l10n per mobile-backlog §5.
          'BEAUTICA',
          style: _kBrandNameStyle,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _RoleChip — shows which role the user picked on the role-selection screen
// ---------------------------------------------------------------------------

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, required this.l10n});

  final UserRole role;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: _kRoleChipDecoration,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_outline,
                size: 12,
                color: BrandColors.camel,
                semanticLabel: null,
              ),
              const SizedBox(width: 6),
              Text(
                role.label(l10n),
                key: const Key('role-chip-label'),
                style: _kRoleChipTextStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HeadlineBlock — two-line headline (Manrope 700 + Cormorant Garamond italic)
// ---------------------------------------------------------------------------

class _HeadlineBlock extends StatelessWidget {
  const _HeadlineBlock({super.key, required this.line1, required this.line2});

  final String line1;
  final String line2;

  static final _kLine1Style = GoogleFonts.manrope(
    textStyle: const TextStyle(
      color: Colors.white,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      height: 1.22,
    ),
  );

  static final _kLine2Style = GoogleFonts.cormorantGaramond(
    textStyle: const TextStyle(
      color: BrandColors.camel,
      fontSize: 34,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w400,
      height: 1.22,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$line1\n',
        style: _kLine1Style,
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text(line2, style: _kLine2Style),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _GlassCard — glassmorphism card hosting the step screen
// ---------------------------------------------------------------------------

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: _kGlassRadius,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: BackdropFilter(
                filter: _kBlur,
                child: const DecoratedBox(decoration: _kGlassDecoration),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _BackLink — "← Назад" link below the glass card
// ---------------------------------------------------------------------------

class _BackLink extends StatelessWidget {
  const _BackLink({
    super.key,
    required this.step,
    required this.location,
    required this.label,
  });

  final RegistrationStep step;

  /// The current matched route location. Needed because Step 2 and Step 3 both
  /// collapse to [RegistrationStep.details], so the back target must be
  /// disambiguated by route: Step 3 (/register/step-3) goes back to Step 2
  /// (/register/step-2 — name/surname/phone); Step 2 goes back to Step 1.
  final String location;

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () {
          final target = switch (step) {
            // Step 3 → previous step is Step 2 (profile); Step 2 → Step 1.
            RegistrationStep.details =>
              location == RouteNames.registerStep3
                  ? RouteNames.registerStep2
                  : RouteNames.register,
            RegistrationStep.verification => RouteNames.registerStep3,
            RegistrationStep.done => RouteNames.verification,
            RegistrationStep.account => RouteNames.registerRole,
          };
          context.go(target);
        },
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.camel,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          // Trim visual dead space (vertical 6) while keeping the effective
          // tap target at the a11y minimum 44px high via minimumSize. We do
          // NOT use tapTargetSize.shrinkWrap here — with 13px text + 6px
          // padding it would collapse the hit area to ~28px, below 44px.
          minimumSize: const Size(88, 44),
        ),
        // Icons.west is a Material icon (always paints). The Manrope UI font
        // has no glyph for U+2190 (←), so the old Text('← $label') rendered
        // a blank square. This mirrors the already-correct _BackToRoleLink
        // pattern in register_step_1_screen.dart.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.west,
              size: 15,
              color: BrandColors.camel.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 6),
            Text(label, style: _kBackLinkStyle),
          ],
        ),
      ),
    );
  }
}
