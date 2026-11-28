// M509 — «Клієнти»: the provider's client list (B507), one screen for every
// provider role and both client kinds (CLI-46 / CLI-47).
//
// Ported literally from the approved preview
// `docs/signup-designs/ClientsTab/lib/screens/clients_screen.dart`, laid out
// like the master «Архів» / «Записи» tab lists: Scaffold(base) →
// SafeArea(bottom: false) → [VelvetTopBar] (no back — a tab root) → search →
// refresh → ListView ([kMyBookingsListPadding]), the bar in
// `Scaffold.bottomNavigationBar` (the `ProfileScaffold.bottomNavBar` rule: never
// nested in the body's SafeArea).
//
// Hosts — the screen is scope-agnostic; the host supplies the scope, the card
// base route and the bar:
//   salon shell (owner / admin)  scope salon(salonId)            bar: the shell's
//   owner master mode            scope salon(salonId, masterId)  bar: master bar
//   independent master           scope me                        bar: master bar
//   salon master                 scope me                        bar: master bar
//
// The body (search · paged list · states · row tap → card) is the shared
// [ClientListView] (M552, promoted from this file verbatim) — the client-
// picker sheet renders the same widget. A row tap opens the client's card
// (M510) — a registered row at `user/:id`, a guest at `guest/:bookingId`
// below [cardBase].
//
// PII: names render, never log; no phone anywhere (CLI-47).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_view.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/velvet_top_bar.dart';

/// The «Клієнти» tab body for one [scope].
class ClientsScreen extends StatelessWidget {
  const ClientsScreen({
    super.key,
    required this.scope,
    required this.cardBase,
    this.bottomNavBar,
  });

  /// Which clients to list.
  final ClientListScope scope;

  /// The list route the card routes hang under (`clientCardRoute`).
  final String cardBase;

  /// The host's bottom bar, mounted in `Scaffold.bottomNavigationBar`. `null`
  /// when an enclosing shell already supplies it (the salon shell).
  final Widget? bottomNavBar;

  static const Key screenKey = Key('clients-screen');
  static const Key searchKey = ClientListView.searchKey;
  static const Key listKey = ClientListView.listKey;
  static const Key skeletonKey = ClientListView.skeletonKey;
  static const Key errorKey = ClientListView.errorKey;
  static const Key emptyKey = ClientListView.emptyKey;
  static const Key noMatchKey = ClientListView.noMatchKey;
  static const Key loadMoreRetryKey = ClientListView.loadMoreRetryKey;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      key: screenKey,
      backgroundColor: BrandColors.base,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            VelvetTopBar(title: l10n.clientsTitle),
            Expanded(
              child: ClientListView(scope: scope, cardBase: cardBase),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottomNavBar,
    );
  }
}
