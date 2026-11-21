// M509 — PLACEHOLDER for the client card (M510), so a list row has a real
// destination before M510 lands.
//
// M510 REPLACES this screen at the same routes (`<list>/user/:userId`,
// `<list>/guest/:bookingId`, see [clientCardRoute]) with the approved card from
// `docs/signup-designs/ClientCardVariants/`. Deliberately minimal: a top bar
// with back and an empty body — it shows no client data, so there is nothing to
// protect and nothing for M510 to unlearn.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';

/// The temporary card route target. See the file header.
class ClientCardPlaceholderScreen extends StatelessWidget {
  const ClientCardPlaceholderScreen({super.key});

  static const Key screenKey = Key('client-card-placeholder');
  static const Key backKey = Key('btn-back-client-card');

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      key: screenKey,
      backgroundColor: BrandColors.base,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            VelvetTopBar(
              title: l10n.clientCardTitle,
              backKey: backKey,
              backSemanticLabel: l10n.registerBackStep,
              onBack: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}
