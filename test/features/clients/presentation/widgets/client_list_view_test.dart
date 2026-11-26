// M552 — ClientListView, the «Клієнти» list body promoted out of
// ClientsScreen: the default row tap still opens the card, the additive
// `onRowTap` replaces it, the additive `searchHint` replaces the placeholder.
// (Every list state is covered through ClientsScreen in clients_screen_test.)
// M544 — swipe-to-remove + the undo snack with its countdown bar.

import 'package:dio/dio.dart' show CancelToken;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart'
    show VelvetSnackMotion;
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart'
    show ClientListHost, kClientSearchDebounce;
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_view.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_removed_snack.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/swipe_action_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/fakes/fake_notification_repository.dart';
import '../../../../helpers/pump_app.dart';
import '../../../../helpers/velvet_snack_matchers.dart';

class _FakeRepo implements ClientRepository {
  _FakeRepo(this.rows);

  final List<ClientSummary> rows;

  /// The `q` of every list call, in order.
  final List<String?> queries = <String?>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// M544 — server-side removals and the write log.
  final Set<ClientRef> removed = <ClientRef>{};
  final List<String> writes = <String>[];
  Object? removeError;

  @override
  Future<void> removeFromList(ClientListScope scope, ClientRef client) async {
    writes.add('remove');
    final Object? e = removeError;
    if (e != null) throw e;
    removed.add(client);
  }

  @override
  Future<void> restoreToList(ClientListScope scope, ClientRef client) async {
    writes.add('restore');
    removed.remove(client);
  }

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) {
    queries.add(q);
    return Future<PageResponse<ClientSummary>>.value(
      PageResponse<ClientSummary>(
        items: page == 0
            ? <ClientSummary>[
                for (final ClientSummary r in rows)
                  if (!removed.contains(r.ref)) r,
              ]
            : <ClientSummary>[],
        page: page,
        totalPages: 1,
        totalElements: rows.length,
      ),
    );
  }
}

final DateTime _now = DateTime.utc(2026, 11, 16, 10);

const ClientSummary _oksana = ClientSummary(
  ref: ClientRef.registered('u1'),
  displayName: 'Оксана Мельник',
);

const ClientSummary _ivan = ClientSummary(
  ref: ClientRef.guest('b2'),
  displayName: 'Іван Коваль',
);

Future<List<String>> _pump(
  WidgetTester tester, {
  void Function(ClientSummary)? onRowTap,
  String? searchHint,
  _FakeRepo? repo,
  ClientListHost host = ClientListHost.tab,
}) async {
  final List<String> opened = <String>[];
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: ClientListView(
            scope: const ClientListScope.me(),
            cardBase: RouteNames.masterClients,
            onRowTap: onRowTap,
            searchHint: searchHint,
            host: host,
          ),
        ),
      ),
      GoRoute(
        path: '${RouteNames.masterClients}/user/:userId',
        builder: (BuildContext context, GoRouterState state) {
          opened.add(state.uri.toString());
          return const Scaffold(body: Text('card-user'));
        },
      ),
    ],
  );
  await tester.pumpRoutedApp(
    router,
    overrides: <Object>[
      clientRepositoryProvider.overrideWithValue(
        repo ?? _FakeRepo(<ClientSummary>[_oksana]),
      ),
      authProvider.overrideWith(
        () => FixedRoleAuth(UserRole.independentMaster),
      ),
      clockProvider.overrideWithValue(() => _now),
    ],
    retry: (_, _) => null,
  );
  await tester.pumpAndSettle();
  return opened;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ClientListView)));

void main() {
  testWidgets('default row tap opens the card (unchanged)', (tester) async {
    final List<String> opened = await _pump(tester);

    await tester.tap(find.byKey(const Key('client-row-u1')));
    await tester.pumpAndSettle();

    expect(opened, <String>['${RouteNames.masterClients}/user/u1']);
    expect(find.text('card-user'), findsOneWidget);
  });

  testWidgets('onRowTap replaces the navigation', (tester) async {
    final List<ClientSummary> tapped = <ClientSummary>[];
    final List<String> opened = await _pump(tester, onRowTap: tapped.add);

    await tester.tap(find.byKey(const Key('client-row-u1')));
    await tester.pumpAndSettle();

    expect(tapped, <ClientSummary>[_oksana]);
    expect(opened, isEmpty, reason: 'no card route when onRowTap is set');
    expect(find.byType(ClientListView), findsOneWidget);
  });

  testWidgets('searchHint replaces the placeholder', (tester) async {
    await _pump(tester, searchHint: 'Custom hint');

    expect(find.text('Custom hint'), findsOneWidget);
    expect(find.text(_l10n(tester).clientsSearchHint), findsNothing);
  });

  testWidgets('no searchHint → the «Клієнти» placeholder', (tester) async {
    await _pump(tester);

    expect(find.text(_l10n(tester).clientsSearchHint), findsOneWidget);
    expect(find.byKey(ClientListView.searchKey), findsOneWidget);
  });

  // M552 audit P2 — closing the host right after typing must not fetch.
  testWidgets('dispose inside the search debounce cancels the search', (
    tester,
  ) async {
    final _FakeRepo repo = _FakeRepo(<ClientSummary>[_oksana]);
    final ValueNotifier<bool> shown = ValueNotifier<bool>(true);
    addTearDown(shown.dispose);
    await tester.pumpApp(
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: shown,
          builder: (BuildContext context, bool on, Widget? _) => on
              ? ClientListView(
                  scope: const ClientListScope.me(),
                  onRowTap: (_) {},
                )
              : const SizedBox.shrink(),
        ),
      ),
      overrides: <Object>[
        clientRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(
          () => FixedRoleAuth(UserRole.independentMaster),
        ),
        clockProvider.overrideWithValue(() => _now),
      ],
      retry: (_, _) => null,
    );
    await tester.pumpAndSettle();
    expect(repo.queries, <String?>[null]);

    await tester.enterText(find.byKey(ClientListView.searchKey), 'Окс');
    await tester.pump(kClientSearchDebounce ~/ 2);
    shown.value = false;
    await tester.pump();
    // The tab's controller is still cached (kClientListCacheFor), so only the
    // cancel stops the timer from re-querying.
    await tester.pump(kClientSearchDebounce * 2);

    expect(repo.queries, <String?>[null], reason: 'no fetch after close');
  });

  // ---------------------------------------------------------------------------
  // M544 — swipe to remove + undo snack (CLI-86).
  // ---------------------------------------------------------------------------

  Finder rowOf(ClientSummary s) => find.byKey(Key('client-row-${s.id}'));

  /// Swipes [s]'s row end-to-start, then pumps until [until] shows (the
  /// Dismissible finishes, the write resolves, a snack enters).
  Future<void> swipe(WidgetTester tester, ClientSummary s, Finder until) async {
    await tester.drag(
      find.byKey(ClientListView.dismissibleKey(s)),
      const Offset(-600, 0),
    );
    await tester.pump();
    await tester.pumpUntilFound(until);
  }

  double countdownValue(WidgetTester tester) => tester
      .widget<FractionallySizedBox>(
        find.descendant(
          of: find.byKey(VelvetSnack.countdownKey),
          matching: find.byType(FractionallySizedBox),
        ),
      )
      .widthFactor!;

  testWidgets('swipe removes the row; «Повернути» before the countdown ends '
      'brings it back at the same position (restore once)', (tester) async {
    final _FakeRepo repo = _FakeRepo(<ClientSummary>[_oksana, _ivan]);
    await _pump(tester, repo: repo);
    final AppLocalizations l10n = _l10n(tester);

    // The reveal is the shared swipe background with the client copy.
    await tester.drag(
      find.byKey(ClientListView.dismissibleKey(_oksana)),
      const Offset(-80, 0),
    );
    await tester.pump();
    expect(find.byType(SwipeActionBackground), findsWidgets);
    expect(find.text(l10n.clientsRemoveSwipe), findsOneWidget);
    await tester.pumpAndSettle(); // springs back (below the threshold)

    await swipe(tester, _oksana, find.text(l10n.clientsRemovedSnack));
    expect(rowOf(_oksana), findsNothing);
    expect(repo.writes, <String>['remove']);
    expect(find.text(l10n.clientsRemovedSnack), findsOneWidget);
    expect(find.byKey(VelvetSnack.countdownKey), findsOneWidget);

    final double early = countdownValue(tester);
    // fixed-wait-ok: samples the countdown bar 2 s apart — the elapsed time
    // IS the quantity under test.
    await tester.pump(const Duration(seconds: 2));
    final double later = countdownValue(tester);
    expect(later, lessThan(early), reason: 'the bar drains');

    await tester.tap(find.text(l10n.clientsRemoveUndo));
    await tester.pump();
    await tester.pumpUntilFound(rowOf(_oksana));
    expect(repo.writes, <String>['remove', 'restore']);
    expect(rowOf(_oksana), findsOneWidget);
    // Same position: first row, above Іван.
    expect(
      tester.getTopLeft(rowOf(_oksana)).dy,
      lessThan(tester.getTopLeft(rowOf(_ivan)).dy),
    );
    await pumpPastVelvetSnack(tester, hasAction: true);
  });

  testWidgets('the countdown ends: the snack closes and the row stays gone '
      '(after a refetch too)', (tester) async {
    final _FakeRepo repo = _FakeRepo(<ClientSummary>[_oksana, _ivan]);
    await _pump(tester, repo: repo);
    final AppLocalizations l10n = _l10n(tester);

    await swipe(tester, _oksana, find.text(l10n.clientsRemovedSnack));
    // Timer-driven: pump frames until the dwell retires the snack (the
    // helper's 10 s budget covers the 5 s window + entrance + exit).
    await tester.pumpUntilGone(find.text(l10n.clientsRemovedSnack));
    expect(kClientRemoveUndoWindow, const Duration(seconds: 5));
    expect(find.text(l10n.clientsRemovedSnack), findsNothing);
    expect(rowOf(_oksana), findsNothing);
    expect(rowOf(_ivan), findsOneWidget);
    expect(repo.writes, <String>['remove']);
  });

  testWidgets('a failed remove puts the row back and shows the error snack, '
      'never the undo snack', (tester) async {
    final _FakeRepo repo = _FakeRepo(<ClientSummary>[_oksana, _ivan])
      ..removeError = const NetworkFailure();
    await _pump(tester, repo: repo);
    final AppLocalizations l10n = _l10n(tester);

    await swipe(tester, _oksana, find.text(l10n.clientsRemoveFailed));
    expect(rowOf(_oksana), findsOneWidget);
    expect(find.text(l10n.clientsRemoveFailed), findsOneWidget);
    expect(find.text(l10n.clientsRemovedSnack), findsNothing);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('the row offers «Прибрати зі списку» as a screen-reader action', (
    tester,
  ) async {
    await _pump(tester);
    final AppLocalizations l10n = _l10n(tester);
    final Semantics semantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byKey(ClientListView.dismissibleKey(_oksana)),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      semantics.properties.customSemanticsActions?.keys.map(
        (CustomSemanticsAction a) => a.label,
      ),
      contains(l10n.clientsRemoveAction),
    );
  });

  testWidgets('the picker host never swipes', (tester) async {
    await _pump(tester, onRowTap: (_) {}, host: ClientListHost.picker);
    expect(rowOf(_oksana), findsOneWidget);
    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets('a session change dismisses the undo snack; «Повернути» never '
      'writes under another session (security)', (tester) async {
    final _FakeRepo repo = _FakeRepo(<ClientSummary>[_oksana, _ivan]);
    final FixedRoleAuth auth = FixedRoleAuth(UserRole.independentMaster);
    final GoRouter router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(
                body: ClientListView(
                  scope: ClientListScope.me(),
                  cardBase: RouteNames.masterClients,
                ),
              ),
        ),
      ],
    );
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        clientRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(() => auth),
        clockProvider.overrideWithValue(() => _now),
      ],
      retry: (_, _) => null,
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = _l10n(tester);

    await swipe(tester, _oksana, find.text(l10n.clientsRemovedSnack));
    expect(find.byKey(VelvetSnack.actionKey), findsOneWidget);
    auth.switchUser('someone-else');
    await tester.pump();
    // Bounded by the EXIT animation, far inside the 5 s undo window: the
    // snack is gone because of the session change, not because the window
    // ran out (a `pumpUntilGone` here would also pass on the timeout).
    await tester.pump(VelvetSnackMotion.exit);
    await tester.pump(VelvetSnackMotion.exit);
    expect(find.text(l10n.clientsRemovedSnack), findsNothing);
    expect(find.byKey(VelvetSnack.actionKey), findsNothing);
    expect(repo.writes, <String>['remove'], reason: 'no restore');
    await pumpPastVelvetSnack(tester, hasAction: true);
  });
}
