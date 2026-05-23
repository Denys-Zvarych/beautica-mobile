// Phase 2.16 — Shared chrome for the multi-step registration wizard.
// VelvetTouch redesign.
//
// Wraps each step screen with:
//   • AuthScaffold (warm-taupe bg + safe area + scroll).
//   • VelvetHeader (compact logo + wordmark).
//   • Role chip — neumorphic extruded pill showing the chosen role. Reads role
//     from `registerDraftProvider`. If the draft is null (e.g. deep-link to
//     /register without picking a role first), redirects to /register/role.
//   • Headline (VelvetText.heading()).
//   • Two-dot step progress indicator (_StepProgress).
//   • Step content from the ShellRoute child.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../core/widgets/neumorphic.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';
import '../domain/user_role.dart';
import '../state/register_draft_notifier.dart';
import 'user_role_l10n.dart';
import 'widgets/auth_scaffold.dart';

/// Shared wizard chrome — wraps each step screen with the brand header, role
/// chip, hero headline, and two-dot step progress.
///
/// Phase 2.16 — Stateful so the shell owns screenshot/recents suppression for
/// ALL wizard steps. Step 1 (and future steps) no longer need to call
/// `ScreenProtector` individually — the shell switches it on in [initState]
/// and off in [dispose] for the entire wizard lifetime.
class RegisterFlowShell extends ConsumerStatefulWidget {
  const RegisterFlowShell({super.key, required this.child});

  /// The step screen rendered inside the wizard chrome.
  final Widget child;

  @override
  ConsumerState<RegisterFlowShell> createState() => _RegisterFlowShellState();
}

class _RegisterFlowShellState extends ConsumerState<RegisterFlowShell> {
  /// Guards against the missing-role redirect being scheduled more than once
  /// per shell lifetime. Without it, every rebuild during a transition would
  /// queue a redundant `context.go(...)`.
  bool _redirectScheduled = false;

  @override
  void initState() {
    super.initState();
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
    // Run the null-role guard here (not in build) so the redirect is scheduled
    // exactly once even if the shell rebuilds during a transition. The
    // [_redirectScheduled] flag is the single source of truth for "have we
    // already queued the bounce-back".
    //
    // Navigation-race guard: only bounce to role-selection when the user has
    // no role AND is still on a wizard route. We use
    // `GoRouter.of(context).routerDelegate.currentConfiguration.fullPath`
    // (evaluated at post-frame time) so the check is timing-independent:
    //   • deep-link to /register with no role → fullPath == '/register' at
    //     post-frame → stillInWizard → bounce fires correctly.
    //   • intentional exit via "log in" → fullPath == '/login' at post-frame
    //     → !stillInWizard → bounce is suppressed.
    final role = ref.read(registerDraftProvider.select((d) => d?.role));
    if (role == null && !_redirectScheduled) {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
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
    // render a placeholder while the post-frame callback resolves.
    if (role == null) {
      return const AuthScaffold(child: SizedBox.shrink());
    }

    final location = GoRouterState.of(context).matchedLocation;
    final currentStep = _stepIndex(location);

    return AuthScaffold(
      showBack: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const VelvetHeader(),
          // Role chip — neumorphic inset pill.
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: BrandColors.base,
                borderRadius: BorderRadius.circular(VelvetRadii.field),
                boxShadow: VelvetShadows.extrudedSmall,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(role.icon, size: 16, color: BrandColors.accent),
                  const SizedBox(width: VelvetSpacing.xs),
                  Text(
                    role.label(l10n),
                    key: const Key('role-chip-label'),
                    style: VelvetText.label(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          Text(
            _shellHeadline(location, role, l10n),
            key: const Key('shell-headline'),
            style: VelvetText.heading(),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          // Two-dot step progress indicator.
          _StepProgress(currentStep: currentStep, totalSteps: 2),
          const SizedBox(height: VelvetSpacing.lg),
          // Step content from ShellRoute child.
          widget.child,
        ],
      ),
    );
  }

  static int _stepIndex(String location) {
    if (location == RouteNames.registerStep2) return 2;
    if (location == RouteNames.registerStep3) return 2;
    return 1;
  }

  static String _shellHeadline(
    String location,
    UserRole role,
    AppLocalizations l10n,
  ) {
    if (location == RouteNames.registerStep2) {
      return l10n.registerStep2ShellHeadline;
    }
    if (location == RouteNames.registerStep3) {
      return switch (role) {
        UserRole.client => l10n.registerStep3ShellHeadlineClient,
        UserRole.salonOwner => l10n.registerStep3ShellHeadlineOwner,
        _ => l10n.registerStep3ShellHeadlineMaster,
      };
    }
    return l10n.registerHeadline; // /register (step 1): 'Створення акаунту'
  }
}

// ---------------------------------------------------------------------------
// _StepProgress — two-dot animated progress bar
// ---------------------------------------------------------------------------

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.currentStep, required this.totalSteps});

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 1; i <= totalSteps; i++) ...<Widget>[
          _StepDot(active: i == currentStep),
          if (i < totalSteps) const SizedBox(width: VelvetSpacing.sm),
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: active ? 24 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: active ? BrandColors.accent : BrandColors.faint,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
