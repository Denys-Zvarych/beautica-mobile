// Shared walk-in / reschedule CLIENT identity card.
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
// WIDENED (RESCHEDULE parity, 2026-08-22): the RESCHEDULE path has no guest
// step (`WalkInGuest` is always `null` there — see `booking_confirm_args
// .dart`'s header), so it could never populate the original [GuestIdentityCard]
// constructor. Rather than hand-copy a second `NeumorphicCard`+`LabelledRow`
// block, this file now exposes a second entry point,
// [GuestIdentityCard.identity], that takes a plain `name`/`phone` pair (as
// recovered from `Booking.clientFirstName`/`clientLastName` via
// `BookingDisplayX.clientName` — `Booking` carries no client phone field, so
// the reschedule path always passes `phone: null`) and builds the IDENTICAL
// `NeumorphicCard` + `LabelledRow` tree — ONE `build()` method, branching only
// on which constructor supplied the name/detail. Both constructors keep the
// same
// `maxLines: 2, overflow: TextOverflow.ellipsis` third-party-free-text bound
// (mobile-security LOW, audit-fix cycle 1, 2026-08-20).
//
// REUSE, not a NEW atom: this is a thin composition of two already-shared
// primitives ([NeumorphicCard], [LabelledRow]) — no bespoke layout of its own.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/create_master_booking_request.dart' show WalkInGuest;
import 'labelled_row.dart';

/// The counterparty's identity — name + optional phone — in a bordered
/// neumorphic card, occupying the visual slot the master's own [MasterStrip]
/// identity card would otherwise take on this screen.
///
/// Two entry points share one render:
///   * the default constructor — the walk-in [WalkInGuest] (name + phone,
///     both always present).
///   * [GuestIdentityCard.identity] — the RESCHEDULE path's plain
///     name/optional-phone pair (see the file header).
class GuestIdentityCard extends StatelessWidget {
  const GuestIdentityCard({super.key, required this.guest})
    : _name = null,
      _phone = null,
      _label = null;

  /// RESCHEDULE entry point — see the file header. [label] defaults to the
  /// shipped «Клієнт» label (`AppLocalizations.bookingClientLabel`) when
  /// omitted.
  const GuestIdentityCard.identity({
    super.key,
    required String name,
    String? phone,
    String? label,
  }) : _name = name,
       _phone = phone,
       _label = label,
       guest = null;

  /// The walk-in guest carried on this flow's args. [WalkInGuest.name] /
  /// [WalkInGuest.surname] are two separate required fields on the domain
  /// model (never a single combined name) — joined here exactly as the
  /// retired wizard's own guest card did. `null` when built via
  /// [GuestIdentityCard.identity].
  final WalkInGuest? guest;

  /// Set only by [GuestIdentityCard.identity].
  final String? _name;
  final String? _phone;
  final String? _label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final WalkInGuest? g = guest;
    final String label = _label ?? l10n.masterCreateBookingGuestLabel;
    final String value = g != null
        ? '${g.name} ${g.surname}'.trim()
        : (_name ?? '');
    final String? detail = g != null
        ? (g.phone.isEmpty ? null : g.phone)
        : _phone;
    return NeumorphicCard(
      showBorder: true,
      padding: const EdgeInsets.all(VelvetSpacing.md),
      child: LabelledRow(
        label: label,
        value: value,
        detail: detail,
        // THIRD-PARTY FREE TEXT — same bound as the wizard's own two copies
        // of this card (`booking_wizard_steps.dart`, mobile-security LOW
        // audit-fix cycle 1, 2026-08-20).
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
