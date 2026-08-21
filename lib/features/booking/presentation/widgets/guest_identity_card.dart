// Shared walk-in GUEST identity card.
//
// A bordered neumorphic card wrapping a single [LabelledRow] (name + phone),
// shown on the master's own walk-in («Новий запис») entry point wherever the
// MASTER identity card would otherwise sit — the confirm screen (this visit
// is about to be submitted) and the terminal success screen (it just was) —
// so the master reviewing/celebrating a walk-in visit always sees WHO it is
// for, not just their own strip staring back at them.
//
// PROMOTED (audit-fix cycle 3, FIX 1) from the inline `NeumorphicCard` +
// `LabelledRow` block `BookingSuccessScreen` built directly inline in its
// `recapCards` list (audit-fix cycle 2, FIX 1, 2026-08-21). `BookingConfirmScreen`
// needed the IDENTICAL card and REUSE-FIRST forbids a second hand-copied
// implementation — see `booking_success_walkin_test.dart` /
// `booking_confirm_test.dart` for the tests pinning both screens render this
// card identically (present when a guest is carried, absent otherwise).
//
// REUSE, not a NEW atom: this is a thin composition of two already-shared
// primitives ([NeumorphicCard], [LabelledRow]) — no bespoke layout of its own.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/create_master_booking_request.dart' show WalkInGuest;
import 'labelled_row.dart';

/// The walk-in guest's identity — name + phone — in a bordered neumorphic
/// card, occupying the visual slot the master's own [MasterStrip] identity
/// card would otherwise take on this screen.
class GuestIdentityCard extends StatelessWidget {
  const GuestIdentityCard({super.key, required this.guest});

  /// The walk-in guest carried on this flow's args. [WalkInGuest.name] /
  /// [WalkInGuest.surname] are two separate required fields on the domain
  /// model (never a single combined name) — joined here exactly as the
  /// retired wizard's own guest card did.
  final WalkInGuest guest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NeumorphicCard(
      showBorder: true,
      padding: const EdgeInsets.all(VelvetSpacing.md),
      child: LabelledRow(
        label: l10n.masterCreateBookingGuestLabel,
        value: '${guest.name} ${guest.surname}'.trim(),
        detail: guest.phone.isEmpty ? null : guest.phone,
        // THIRD-PARTY FREE TEXT — same bound as the wizard's own two copies
        // of this card (`booking_wizard_steps.dart`, mobile-security LOW
        // audit-fix cycle 1, 2026-08-20).
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
