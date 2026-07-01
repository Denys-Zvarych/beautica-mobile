// The terminal confirmation state, shown after a successful send. A success
// medallion + "Дякуємо!" headline + the email the reply will arrive at, plus a
// single "Готово" CTA.
//
// Design source: `docs/signup-designs/ContactSupport/lib/widgets/
// success_card.dart` — ported 1:1, swapping VelvetColors → BrandColors and the
// copy to l10n. When [email] is null (the rare case where the session user has
// no email handy) the email line is omitted.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Success card shown after a support message is accepted.
class SupportSuccessCard extends StatelessWidget {
  const SupportSuccessCard({
    super.key,
    required this.email,
    required this.onDone,
  });

  /// The address the team replies to — shown so the user knows where to expect
  /// the answer. Omitted when null.
  final String? email;
  final VoidCallback onDone;

  static const BoxDecoration _medallionDecoration = BoxDecoration(
    color: BrandColors.base,
    shape: BoxShape.circle,
    boxShadow: VelvetShadows.extrudedSmall,
  );

  static final TextStyle _emailStyle = VelvetText.bodyStrong().copyWith(
    color: BrandColors.accentDeep,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? email = this.email;
    return Center(
      key: const Key('support-success-card'),
      child: NeumorphicCard(
        padding: const EdgeInsets.all(VelvetSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 84,
              width: 84,
              decoration: _medallionDecoration,
              child: const Icon(
                Icons.mark_email_read_rounded,
                size: 38,
                color: BrandColors.success,
              ),
            ),
            const SizedBox(height: VelvetSpacing.lg),
            Text(
              l10n.contactSupportSuccessTitle,
              style: VelvetText.heading(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              email == null
                  ? l10n.contactSupportSuccessBodyNoEmail
                  : l10n.contactSupportSuccessBody,
              style: VelvetText.body(),
              textAlign: TextAlign.center,
            ),
            if (email != null) ...<Widget>[
              const SizedBox(height: VelvetSpacing.xs),
              Text(email, style: _emailStyle, textAlign: TextAlign.center),
            ],
            const SizedBox(height: VelvetSpacing.xl),
            NeumorphicButton(
              key: const Key('support-success-done'),
              label: l10n.contactSupportDone,
              icon: Icons.check_rounded,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    );
  }
}
