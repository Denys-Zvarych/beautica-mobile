// M552 — the client picker: «Мої клієнти» in a bottom sheet, returning the
// picked client's [ClientPrefill] (name parts + phone) for a booking form
// (wired in M553).
//
// NOTHING NEW VISUALLY (REUSE-FIRST, D1; owner skipped the M551 preview
// 2026-11-25): composed only of shipped widgets —
//   • showVelvetSheet(isScrollControlled: true) + VelvetSheetChrome (handle +
//     title; its additive `content` hosts the list in place of the padded
//     option column)                          (shared/widgets/velvet_sheet.dart)
//   • ClientListView — the SAME body as the «Клієнти» tab: SearchQueryField,
//     ClientListRow rows (blocked clients keep their «Заблоковано» chip and
//     stay pickable), skeleton / empty / no-match / error states
//   • ErrorState + retry when the picked client's card cannot be read.
//
// Scope is passed in, never inferred (D3): the caller decides
// `salon(salonId)` (owner / admin — the whole salon) vs `me()` (independent
// master — own clients only). The server enforces it.
//
// ROLE GATE: only SALON_OWNER, SALON_ADMIN and INDEPENDENT_MASTER may pick
// ([canPickClients]); a SALON_MASTER (read-only) or a CLIENT gets `null` and no
// sheet. Read from the settled session (fail closed), like every write gate.
// M553 shows / hides its button with the same helper.
//
// OWN LIST: the sheet's ClientListView runs on the picker's controller
// instance ([ClientListHost.picker]) — every open starts with an empty search
// and a search here never changes the «Клієнти» tab's list.
//
// The phone comes from the card (D2), fetched once on pick — the list keeps
// none. PII: never logged.

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart'
    show ClientListHost;
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_view.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/velvet_sheet.dart';

/// Whether [role] may pick an existing client into a booking form: the
/// salon's owner / admin and an independent master. A salon master's calendar
/// is read-only and a client has no client list — both `false`, as is `null`
/// (no settled session).
bool canPickClients(UserRole? role) => switch (role) {
  UserRole.salonOwner ||
  UserRole.salonAdmin ||
  UserRole.independentMaster => true,
  UserRole.salonMaster || UserRole.client || null => false,
};

/// Opens the picker over [scope]'s clients. Resolves the picked client's
/// prefill, or `null` when the sheet is dismissed — or, without opening
/// anything, when the signed-in role may not pick ([canPickClients]).
Future<ClientPrefill?> showClientPickerSheet(
  BuildContext context, {
  required ClientListScope scope,
}) {
  final UserRole? role = authUserRoleSettledOrNull(
    ProviderScope.containerOf(context, listen: false).read(authProvider),
  );
  if (!canPickClients(role)) {
    log('client picker refused for role ${role?.name}', name: _logTag);
    return Future<ClientPrefill?>.value();
  }
  return showVelvetSheet<ClientPrefill>(
    context,
    // A tall sheet with a search field: it rises above the keyboard.
    isScrollControlled: true,
    builder: (BuildContext _) => ClientPickerSheet(scope: scope),
  );
}

const String _logTag = 'feature.clients';

/// The picker sheet's body. See the file header.
class ClientPickerSheet extends ConsumerStatefulWidget {
  const ClientPickerSheet({super.key, required this.scope});

  final ClientListScope scope;

  static const Key sheetKey = Key('client-picker-sheet');
  static const Key cardErrorKey = Key('client-picker-card-error');

  /// Share of the screen height the sheet may take (the report sheet's).
  static const double _maxHeightFactor = 0.9;

  @override
  ConsumerState<ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends ConsumerState<ClientPickerSheet> {
  /// The row whose card is being read (re-entrant taps are ignored).
  ClientSummary? _picking;

  /// The row whose card read failed — the sheet shows the error + retry.
  ({ClientSummary summary, Failure failure})? _failed;

  Future<void> _pick(ClientSummary summary) async {
    if (_picking != null) return;
    _picking = summary;
    final ClientCardProvider provider = clientCardProvider(
      widget.scope,
      summary.ref,
    );
    // The card provider is autoDispose: hold it across the await.
    final ProviderSubscription<AsyncValue<ClientCard>> hold = ref.listenManual(
      provider,
      (_, _) {},
    );
    try {
      final ClientCard card = await ref.read(provider.future);
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      ModalRoute.of(context)?.navigator?.pop(ClientPrefill.fromCard(card));
    } on Object catch (e) {
      if (!mounted) return;
      setState(
        () => _failed = (
          summary: summary,
          failure: e is Failure ? e : UnknownFailure(cause: e),
        ),
      );
    } finally {
      hold.close();
      _picking = null;
    }
  }

  void _retry(ClientSummary summary) {
    ref.invalidate(clientCardProvider(widget.scope, summary.ref));
    setState(() => _failed = null);
    _pick(summary);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ({ClientSummary summary, Failure failure})? failed = _failed;
    return _KeyboardInset(
      key: ClientPickerSheet.sheetKey,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height *
              ClientPickerSheet._maxHeightFactor,
        ),
        child: VelvetSheetChrome(
          title: l10n.walkInPickClientTitle,
          content: failed == null
              ? ClientListView(
                  scope: widget.scope,
                  host: ClientListHost.picker,
                  searchHint: l10n.walkInPickClientSearchHint,
                  onRowTap: _pick,
                )
              : ErrorState(
                  key: ClientPickerSheet.cardErrorKey,
                  failure: failed.failure,
                  onRetry: () => _retry(failed.summary),
                ),
          children: const <Widget>[],
        ),
      ),
    );
  }
}

/// Rides [child] above the keyboard (showVelvetSheet isScrollControlled:
/// true). A leaf: only this padding rebuilds on each keyboard-animation frame
/// — [child] (the chrome + list) is built once by the sheet and passed in.
class _KeyboardInset extends StatelessWidget {
  const _KeyboardInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}
