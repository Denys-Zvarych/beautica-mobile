// Phase 425 D2/D3 — the client actions sheet behind the booking-detail client
// strip's «⋯».
//
// Ported 1:1 from the approved preview
// `docs/signup-designs/UgcSafety/lib/widgets/moderation_widgets.dart`
// (`showContentActionsSheet`). Composed of `VelvetSheetChrome` +
// `VelvetSheetOptionRow(leading:, labelStyle:)` exactly as the image-source
// sheet is — no `PopupMenuButton`, no new chrome. The client-side profile
// «⋯» does NOT use this sheet: it opens the report sheet directly (D1).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/velvet_sheet.dart';

/// What the provider picked on the client actions sheet.
enum ClientAction {
  report,
  block,
  unblock,

  /// M544 (CLI-86) — «Прибрати зі списку»: remove from the «Клієнти» list.
  remove,
}

/// Opens the client actions sheet titled with the client's [name].
///
/// [canReport] — a registered client (there is no `CLIENT_PROFILE` to report
/// on a guest booking). [canBlock] — independent master, salon owner or
/// salon admin (a salon master reports only). [blocked] swaps «Заблокувати
/// клієнта» for «Розблокувати». [canRemove] (M544, ADDITIVE, default
/// `false`) adds «Прибрати зі списку» last. Resolves `null` when dismissed.
Future<ClientAction?> showClientActionsSheet(
  BuildContext context, {
  required String name,
  required bool canReport,
  required bool canBlock,
  bool blocked = false,
  bool canRemove = false,
}) {
  assert(
    canReport || canBlock || canRemove,
    'An actions sheet with no actions.',
  );
  return showVelvetSheet<ClientAction>(
    context,
    builder: (BuildContext _) => ClientActionsSheet(
      name: name,
      canReport: canReport,
      canBlock: canBlock,
      blocked: blocked,
      canRemove: canRemove,
    ),
  );
}

/// The sheet body — see [showClientActionsSheet].
class ClientActionsSheet extends StatelessWidget {
  const ClientActionsSheet({
    super.key,
    required this.name,
    required this.canReport,
    required this.canBlock,
    this.blocked = false,
    this.canRemove = false,
  });

  final String name;
  final bool canReport;
  final bool canBlock;
  final bool blocked;

  /// M544 — offer «Прибрати зі списку» (see [showClientActionsSheet]).
  final bool canRemove;

  static const Key reportKey = Key('client-action-report');
  static const Key blockKey = Key('client-action-block');
  static const Key unblockKey = Key('client-action-unblock');
  static const Key removeKey = Key('client-action-remove');

  static const double _iconSize = 22;

  void _pop(BuildContext context, ClientAction action) =>
      ModalRoute.of(context)?.navigator?.pop(action);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return VelvetSheetChrome(
      title: name,
      children: <Widget>[
        if (canReport)
          VelvetSheetOptionRow(
            tapKey: reportKey,
            label: l10n.clientActionReport,
            leading: const Icon(
              Icons.outlined_flag_rounded,
              size: _iconSize,
              color: BrandColors.accentDeep,
            ),
            onTap: () => _pop(context, ClientAction.report),
          ),
        if (canBlock && !blocked)
          VelvetSheetOptionRow(
            tapKey: blockKey,
            label: l10n.clientActionBlock,
            leading: const Icon(
              Icons.block_rounded,
              size: _iconSize,
              color: BrandColors.error,
            ),
            labelStyle: VelvetText.discSortOption.copyWith(
              color: BrandColors.error,
            ),
            onTap: () => _pop(context, ClientAction.block),
          ),
        if (canBlock && blocked)
          VelvetSheetOptionRow(
            tapKey: unblockKey,
            label: l10n.clientActionUnblock,
            leading: const Icon(
              Icons.lock_open_rounded,
              size: _iconSize,
              color: BrandColors.accentDeep,
            ),
            onTap: () => _pop(context, ClientAction.unblock),
          ),
        // Not destructive-red: removal hides a list row only, nothing is
        // lost and a new booking brings the client back (CLI-83).
        if (canRemove)
          VelvetSheetOptionRow(
            tapKey: removeKey,
            label: l10n.clientsRemoveAction,
            leading: const Icon(
              Icons.person_remove_outlined,
              size: _iconSize,
              color: BrandColors.accentDeep,
            ),
            onTap: () => _pop(context, ClientAction.remove),
          ),
      ],
    );
  }
}
