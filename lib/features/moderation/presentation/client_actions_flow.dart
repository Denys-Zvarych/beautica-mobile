// Phase 425 / 428 — a provider's «⋯» on a CLIENT: report a registered client,
// block / unblock (R3, docs/specs/moderation.md).
//
// PROMOTED (2026-11-21) out of `booking_detail_screen.dart`'s private
// `_clientMoreFor` / `_onClientMore` / `_showBlockOutcome`, so the client card
// offers the SAME actions with the SAME gating, sheet, dialogs and writes —
// one flow, two hosts. «Деталі запису» calls it exactly as it used to run the
// private code (behaviour unchanged).
//
// Everything is addressed through ONE booking of the client: the block write
// is `POST /blocks { bookingId }` (the server derives the target), unblock is
// `DELETE /blocks/{clientBlockId}` from that booking's detail read.
//
// PII: the client's name is shown in the sheet / dialogs, never logged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/moderation/application/block_notifier.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block_access.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/block_confirm_dialog.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/content_actions_sheet.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

/// What the «⋯» may offer for one client — see [clientActionsGateFor].
typedef ClientActionsGate = ({
  bool canReport,
  bool canBlock,
  bool blocked,
  bool salonScope,
});

/// Phase 425 D2/D3 — the gate for [booking]'s client, or `null` when there is
/// nothing to offer: report a REGISTERED client (every provider role, unless
/// [reported] already — report once, ever); block / unblock only for the
/// roles [clientBlocksAllowedFor] admits (independent master, salon owner,
/// salon admin — never a salon master), and then only as the server allows:
/// «Заблокувати» when `clientBlockable`, «Розблокувати» when `clientBlocked`
/// with its `clientBlockId`. A null role fails closed.
ClientActionsGate? clientActionsGateFor(
  Booking booking,
  UserRole? role, {
  required bool reported,
}) {
  if (role == null || role == UserRole.client) return null;
  final bool canReport = booking.clientId != null && !reported;
  final bool roleMayBlock = clientBlocksAllowedFor(role);
  final String? blockId = booking.clientBlockId;
  final bool blocked = booking.clientBlocked && blockId != null;
  final bool canBlock =
      roleMayBlock &&
      (blocked || (!booking.clientBlocked && booking.clientBlockable));
  if (!canReport && !canBlock) return null;
  return (
    canReport: canReport,
    canBlock: canBlock,
    blocked: blocked,
    // Phase 398 — a salon owner / admin blocks for the whole salon.
    salonScope: role == UserRole.salonOwner || role == UserRole.salonAdmin,
  );
}

/// Opens the client actions sheet for [booking]'s client and runs the picked
/// action. [salonId] is the salon board the host was drilled into from
/// (`null` everywhere else — see `BookingDetailScreen.salonId`). [onChanged]
/// runs after a successful block / unblock (the card refreshes its tag).
Future<void> runClientActions(
  BuildContext context,
  WidgetRef ref, {
  required Booking booking,
  required ClientActionsGate gate,
  String? salonId,
  VoidCallback? onChanged,
}) async {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String name = booking.clientName ?? l10n.bookingDetailGuestClient;
  final ClientAction? action = await showClientActionsSheet(
    context,
    name: name,
    canReport: gate.canReport,
    canBlock: gate.canBlock,
    blocked: gate.blocked,
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case ClientAction.report:
      final String? clientId = booking.clientId;
      if (clientId == null) return;
      await showReportSheet(
        context,
        targetType: ReportTargetType.clientProfile,
        targetId: clientId,
        subject: l10n.reportSubjectClient(name),
      );
    case ClientAction.block:
      if (!await showBlockClientDialog(
        context,
        name,
        salonScope: gate.salonScope,
      )) {
        return;
      }
      if (!context.mounted) return;
      final BlockWriteResult result = await ref
          .read(clientBlockControllerProvider.notifier)
          .block(booking.id, salonId: salonId);
      if (!context.mounted) return;
      // Phase 398 — the block auto-cancelled future visits: say how many
      // (the snack host is single-slot, so this REPLACES the plain
      // «Клієнта заблоковано», never stacks on it).
      _showBlockOutcome(context, result, switch (result) {
        BlockWriteDone(:final int cancelledBookings)
            when cancelledBookings > 0 =>
          l10n.clientBlockCancelledBookingsSnack(cancelledBookings),
        _ => l10n.clientBlockedSnack,
      }, onChanged);
    case ClientAction.unblock:
      final String? blockId = booking.clientBlockId;
      if (blockId == null) return;
      if (!await showUnblockClientDialog(context, name)) return;
      if (!context.mounted) return;
      final BlockWriteResult result = await ref
          .read(clientBlockControllerProvider.notifier)
          .unblock(bookingId: booking.id, blockId: blockId);
      if (!context.mounted) return;
      _showBlockOutcome(context, result, l10n.clientUnblockedSnack, onChanged);
  }
}

/// Success → [successMessage] (+ [onChanged]); failure → its own copy; a call
/// ignored because another write was in flight → nothing at all.
void _showBlockOutcome(
  BuildContext context,
  BlockWriteResult result,
  String successMessage,
  VoidCallback? onChanged,
) {
  switch (result) {
    case BlockWriteDone():
      showSuccessSnack(context, successMessage);
      onChanged?.call();
    case BlockWriteFailed(:final Failure failure):
      showErrorSnack(context, failure.userMessage(context));
    case BlockWriteInProgress():
      return;
  }
}
