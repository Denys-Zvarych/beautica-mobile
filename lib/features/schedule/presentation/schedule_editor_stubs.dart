// Phase 15.2 — Routed editor stubs for phases 15.3–15.5.
//
// The schedule screen (Phase 15.2) wires the READ path and the navigation
// entry points to the per-day / weekly-template / propagate editors. Those
// editor surfaces themselves land in 15.3–15.5. Until then each entry point
// pushes a REAL routed placeholder screen (never a SnackBar-only dead end, per
// the phase doc Step 4) so navigation is honest: the user lands on a titled
// screen that names the coming feature and can back out cleanly.
//
// Each stub is intentionally minimal but real — registered in the router,
// auth-guarded by the global redirect, themed with the production neumorphic
// chrome. When the corresponding phase ships it REPLACES the stub at the same
// route (mirroring how /done graduated from placeholder to DoneScreen).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// Shared scaffold for the three editor stubs: a neumorphic back bar, a centred
/// icon + title + "coming soon" body.
class _EditorStubScaffold extends StatelessWidget {
  const _EditorStubScaffold({
    required this.title,
    required this.body,
    required this.icon,
    required this.markerKey,
  });

  final String title;
  final String body;
  final IconData icon;
  final Key markerKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      key: markerKey,
      backgroundColor: BrandColors.base,
      appBar: AppBar(
        backgroundColor: BrandColors.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(title, style: VelvetText.subheading()),
        leading: NeumorphicIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          semanticLabel: l10n.registerBackStep,
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.masterSchedule);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(VelvetSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  height: 64,
                  width: 64,
                  decoration: const BoxDecoration(
                    color: BrandColors.base,
                    shape: BoxShape.circle,
                    boxShadow: VelvetShadows.extrudedSmall,
                  ),
                  child: Icon(icon, size: 28, color: BrandColors.accentDeep),
                ),
                const SizedBox(height: VelvetSpacing.lg),
                Text(
                  title,
                  style: VelvetText.heading(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: VelvetSpacing.sm),
                Text(
                  body,
                  style: VelvetText.body(),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Phase 15.5 — the weekly-template editor stub was REMOVED: the real editor
// (`WeeklyTemplateEditorScreen`) now occupies `RouteNames.scheduleWeeklyEditor`.

/// Phase 15.4 stub — the per-date override sheet. Reached from the day pencil
/// and "+ Додати час". The day-off entry ("+ Time Off") routes here too with
/// the same stub copy until 15.4 distinguishes the modes.
class PerDateOverrideStubScreen extends StatelessWidget {
  const PerDateOverrideStubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _EditorStubScaffold(
      markerKey: const Key('stub-per-date-override'),
      icon: Icons.edit_calendar_rounded,
      title: l10n.scheduleOverrideEditorTitle,
      body: l10n.scheduleEditorComingSoon,
    );
  }
}

// Phase 15.5 — the copy/propagate stub (`SchedulePropagateStubScreen`) was
// REMOVED. The copy/propagate range surface graduated to the modal
// `ApplyScheduleSheet` («Період дії графіка»), opened from the weekly editor's
// tappable active-window card, so `RouteNames.schedulePropagate` now lands on
// `WeeklyTemplateEditorScreen` — there is no remaining consumer of the stub
// (mirrors the earlier `WeeklyTemplateEditorStubScreen` retirement).
