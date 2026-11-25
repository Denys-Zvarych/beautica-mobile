// M552 — ClientListView, the «Клієнти» list body promoted out of
// ClientsScreen: the default row tap still opens the card, the additive
// `onRowTap` replaces it, the additive `searchHint` replaces the placeholder.
// (Every list state is covered through ClientsScreen in clients_screen_test.)

import 'package:dio/dio.dart' show CancelToken;
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart'
    show kClientSearchDebounce;
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_view.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/fakes/fake_notification_repository.dart';
import '../../../../helpers/pump_app.dart';

class _FakeRepo implements ClientRepository {
  _FakeRepo(this.rows);

  final List<ClientSummary> rows;

  /// The `q` of every list call, in order.
  final List<String?> queries = <String?>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

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
        items: page == 0 ? rows : <ClientSummary>[],
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

Future<List<String>> _pump(
  WidgetTester tester, {
  void Function(ClientSummary)? onRowTap,
  String? searchHint,
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
        _FakeRepo(<ClientSummary>[_oksana]),
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
}
