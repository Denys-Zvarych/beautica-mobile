// M544 (CLI-82, CLI-86) — the ONE remove / restore write for a «Клієнти» row,
// shared by the list swipe ([ClientListController.remove] / `restore`) and
// the client card «⋯» (`client_card_screen.dart`).
//
// WHO REFRESHES WHEN:
//   • Card «⋯» ([removeClientFromList]): the list behind the card must drop
//     the row now, so the WHOLE family is invalidated at once.
//   • List swipe ([ClientListController.remove]): the list on screen already
//     dropped the row (optimistic) and keeps its loaded pages. The OTHER list
//     instances — the owner's `masterId` views and the picker read the same
//     salon-scoped removal (CLI-82, CLI-85) — are told ONCE, when the undo
//     window of the LAST swipe in a burst closes, through
//     [ClientListRemovalBroadcast]: a debounced epoch every list instance
//     listens to; the instance(s) that made the burst skip it.
//   • Restore failure: the whole family refetches (server truth).
//
// Same "invalidate tear-off" shape as `invalidateClientViews`, so a `Ref`, a
// `WidgetRef` or a `ProviderContainer` (the card path, which outlives the
// card) all fit. Removal never touches the card or its visits (CLI-84).

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';

part 'client_list_removal.g.dart';

/// How long «Повернути» stays offered (CLI-86).
const Duration kClientRemoveUndoWindow = Duration(seconds: 5);

/// When the other list instances hear about a swipe burst: once the last
/// swipe's undo snack has entered and its window has run out.
final Duration kClientRemovalBroadcastDelay =
    kClientRemoveUndoWindow + VelvetSnackMotion.enter;

/// The stable identity of one list instance: its family key. Never the
/// notifier object — a rebuild makes a new one, and holding it would keep a
/// disposed controller (its pages, client names) alive.
typedef ClientListSource = ({ClientListScope scope, ClientListHost host});

/// Which removals a scope's write lands in: a salon's list (owner, admin and
/// their `masterId` views share it, CLI-82) or the signed-in master's own.
/// The two never affect each other.
String clientRemovalScopeKey(ClientListScope scope) => switch (scope) {
  SalonClientListScope(:final String salonId) => 'salon:$salonId',
  MyClientListScope() => 'me',
};

/// One broadcast: [epoch] bumps per burst; [scopes] are the removal scopes
/// ([clientRemovalScopeKey]) it changed; [sources] are the list instances
/// that made it (they already show the result and skip the refetch). Values
/// only — no instance references.
typedef ClientListRemovalEpoch = ({
  int epoch,
  Set<String> scopes,
  Set<ClientListSource> sources,
});

/// The debounced "a swipe burst changed the lists" signal. See the header.
@Riverpod(keepAlive: true)
class ClientListRemovalBroadcast extends _$ClientListRemovalBroadcast {
  Timer? _timer;

  /// Net pending change per source and client: remove +1, restore −1. A
  /// restore that cancels its own pending remove nets to 0 and is dropped —
  /// no change, nobody refetches.
  final Map<ClientListSource, Map<ClientRef, int>> _pending =
      <ClientListSource, Map<ClientRef, int>>{};

  @override
  ClientListRemovalEpoch build() {
    ref.onDispose(() => _timer?.cancel());
    return (
      epoch: 0,
      scopes: const <String>{},
      sources: const <ClientListSource>{},
    );
  }

  /// A successful swipe remove by [source].
  void removed(ClientListSource source, ClientRef client) =>
      _record(source, client, 1);

  /// A successful undo by [source].
  void restored(ClientListSource source, ClientRef client) =>
      _record(source, client, -1);

  /// Drops EVERY pending change and stops the debounce: the caller is about
  /// to invalidate the whole list family (a failed restore), which reloads
  /// every list — a later flush would only refetch them all a second time.
  void cancelAll() {
    _pending.clear();
    _rearm();
  }

  void _record(ClientListSource source, ClientRef client, int delta) {
    final Map<ClientRef, int> net = _pending.putIfAbsent(
      source,
      () => <ClientRef, int>{},
    );
    final int next = (net[client] ?? 0) + delta;
    if (next == 0) {
      net.remove(client);
    } else {
      net[client] = next;
    }
    if (net.isEmpty) _pending.remove(source);
    _rearm();
  }

  /// (Re)starts the debounce while anything is pending, so a burst ends in
  /// ONE broadcast; stops it when nothing is.
  void _rearm() {
    _timer?.cancel();
    _timer = _pending.isEmpty
        ? null
        : Timer(kClientRemovalBroadcastDelay, _flush);
  }

  void _flush() {
    _timer = null;
    final Set<ClientListSource> sources = Set<ClientListSource>.unmodifiable(
      _pending.keys,
    );
    _pending.clear();
    if (sources.isEmpty) return;
    state = (
      epoch: state.epoch + 1,
      scopes: Set<String>.unmodifiable(<String>{
        for (final ClientListSource s in sources)
          clientRemovalScopeKey(s.scope),
      }),
      sources: sources,
    );
  }
}

/// Whether the list instance [self] must refetch for [burst]: only when the
/// burst changed its removal scope, and it did not make the whole burst
/// alone (then it already shows the result).
bool clientListNeedsRefetch(
  ClientListRemovalEpoch burst,
  ClientListSource self,
) {
  if (!burst.scopes.contains(clientRemovalScopeKey(self.scope))) return false;
  return !(burst.sources.length == 1 && burst.sources.contains(self));
}

/// Card path: removes [client] from [scope]'s list, then drops every cached
/// list at once (the list behind the card must lose the row). Throws the
/// repository's [Failure] (nothing is invalidated then).
Future<void> removeClientFromList(
  ClientRepository repository,
  void Function(ProviderOrFamily) invalidate,
  ClientListScope scope,
  ClientRef client,
) async {
  await repository.removeFromList(scope, client);
  invalidate(clientListControllerProvider);
}

/// Card path undo: restores, then drops every cached list EITHER WAY (on
/// failure the refetch shows the server's truth). Returns the error, or
/// `null`.
Future<Object?> restoreClientToList(
  ClientRepository repository,
  void Function(ProviderOrFamily) invalidate,
  ClientListScope scope,
  ClientRef client,
) async {
  Object? error;
  try {
    await repository.restoreToList(scope, client);
  } catch (e) {
    error = e;
  }
  invalidate(clientListControllerProvider);
  return error;
}
