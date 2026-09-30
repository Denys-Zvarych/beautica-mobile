// Phase 361 — PLACEHOLDER for the notification feed («Сповіщення»).
//
// Exists only so the shared bell on every role's header has a real route to
// push. Phase 363 replaces this body with the approved feed screen (design
// gate: phase 362); the route name and the screen class stay.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  void _onBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return SectionScaffold(
      title: l10n.notificationsScreenTitle,
      backKey: const Key('notifications-back'),
      backSemanticLabel: l10n.salonProfileBackLabel,
      onBack: () => _onBack(context),
      body: const SizedBox.shrink(),
    );
  }
}
