// M509 — «Клієнти» list screen: every state, the row, the search rules, paging
// and the row tap.
//
// The repository is faked at the `ClientRepository` seam; the router is a
// stub that only records the card route a row opens. Layout at 360 / 414 px
// and text 1.3× is checked by the suite-wide overflow guard (any RenderFlex
// overflow fails the test in tearDown).
//
// Debounce: the controller's `Timer` is driven with `tester.pump(<duration>)`
// — `pumpAndSettle` fires no Timer.

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/clients_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_row.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/list_card_skeleton.dart';
import 'package:beautica_mobile/shared/widgets/search_query_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

typedef _Hook =
    Future<PageResponse<ClientSummary>>? Function(int page, String? q);

class _FakeRepo implements ClientRepository {
  // M510 — the card reads are not exercised here.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  _FakeRepo(this.rows);

  List<ClientSummary> rows;
  _Hook? hook;
  final List<({int page, String? q})> calls = <({int page, String? q})>[];

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) {
    calls.add((page: page, q: q));
    final Future<PageResponse<ClientSummary>>? taken = hook?.call(page, q);
    if (taken != null) return taken;
    final List<ClientSummary> matching = q == null
        ? rows
        : rows
              .where((ClientSummary r) => (r.displayName ?? '').contains(q))
              .toList();
    final int from = page * size;
    final List<ClientSummary> slice = from >= matching.length
        ? <ClientSummary>[]
        : matching.sublist(from, (from + size).clamp(0, matching.length));
    return Future<PageResponse<ClientSummary>>.value(
      PageResponse<ClientSummary>(
        items: slice,
        page: page,
        totalPages: (matching.length / size).ceil(),
        totalElements: matching.length,
      ),
    );
  }
}

final DateTime _now = DateTime.utc(2026, 11, 16, 10);

ClientSummary _registered({
  String id = 'u1',
  String? name = 'Оксана Мельник',
  double? avg = 4.9,
  int count = 12,
  bool blocked = false,
  DateTime? last,
  DateTime? next,
}) => ClientSummary(
  ref: ClientRef.registered(id),
  displayName: name,
  lastVisitAt: last ?? DateTime.utc(2026, 11, 7, 10), // 7 лис, Kyiv 12:00
  nextVisitAt: next ?? DateTime.utc(2026, 11, 20, 12), // пт, 20 лис, 14:00
  completedVisits: 9,
  ratingAvg: avg,
  ratingCount: count,
  blocked: blocked,
);

ClientSummary _guest({String id = 'g1', String? name = 'Ірина Коваль'}) =>
    ClientSummary(
      ref: ClientRef.guest(id),
      displayName: name,
      lastVisitAt: DateTime.utc(2026, 10, 1, 10),
      completedVisits: 3,
    );

class _Harness {
  _Harness(this.repo, {this.scope = const ClientListScope.me()});

  final _FakeRepo repo;
  final ClientListScope scope;
  final List<String> opened = <String>[];

  /// The injected clock's value (mutable for the app-resume test).
  DateTime now = _now;

  late final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            ClientsScreen(scope: scope, cardBase: RouteNames.masterClients),
      ),
      GoRoute(
        path: '${RouteNames.masterClients}/user/:userId',
        builder: (BuildContext context, GoRouterState state) {
          opened.add(state.uri.toString());
          return const Scaffold(body: Text('card-user'));
        },
      ),
      GoRoute(
        path: '${RouteNames.masterClients}/guest/:bookingId',
        builder: (BuildContext context, GoRouterState state) {
          opened.add(state.uri.toString());
          return const Scaffold(body: Text('card-guest'));
        },
      ),
    ],
  );

  List<Object> get overrides => <Object>[
    clientRepositoryProvider.overrideWithValue(repo),
    authProvider.overrideWith(() => FixedRoleAuth(UserRole.independentMaster)),
    clockProvider.overrideWithValue(() => now),
  ];
}

Future<_Harness> _pump(
  WidgetTester tester,
  _FakeRepo repo, {
  ClientListScope scope = const ClientListScope.me(),
  double width = 360,
  double? textScale,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final _Harness h = _Harness(repo, scope: scope);
  await tester.pumpRoutedApp(
    h.router,
    overrides: h.overrides,
    retry: (_, _) => null,
  );
  await tester.pumpAndSettle();
  return h;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ClientsScreen)));

Finder _search() => find.byKey(ClientsScreen.searchKey);

void main() {
  group('states', () {
    testWidgets('loading → skeleton, no rows', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[]);
      final Completer<PageResponse<ClientSummary>> gate =
          Completer<PageResponse<ClientSummary>>();
      repo.hook = (_, _) => gate.future;
      final _Harness h = _Harness(repo);
      await tester.pumpRoutedApp(h.router, overrides: h.overrides);
      await tester.pump();

      expect(find.byKey(ClientsScreen.skeletonKey), findsOneWidget);
      expect(find.byType(ListCardSkeleton), findsOneWidget);
      expect(find.byType(ClientListRow), findsNothing);
      // The search stays available while loading.
      expect(_search(), findsOneWidget);
      gate.complete(
        const PageResponse<ClientSummary>(
          items: <ClientSummary>[],
          page: 0,
          totalPages: 0,
          totalElements: 0,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('empty roster → notice, the search field is HIDDEN', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(<ClientSummary>[]));
      final AppLocalizations l10n = _l10n(tester);

      expect(find.byKey(ClientsScreen.emptyKey), findsOneWidget);
      expect(find.text(l10n.clientsEmptyTitle), findsOneWidget);
      expect(find.text(l10n.clientsEmptyBody), findsOneWidget);
      expect(_search(), findsNothing);
      expect(find.byType(SearchQueryField), findsNothing);
    });

    testWidgets('no match for a term → no-match notice, search stays', (
      tester,
    ) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      await _pump(tester, repo);

      await tester.enterText(_search(), 'Zz');
      await tester.pump(kClientSearchDebounce);
      await tester.pumpAndSettle();

      expect(find.byKey(ClientsScreen.noMatchKey), findsOneWidget);
      expect(find.text(_l10n(tester).clientsNoMatchTitle), findsOneWidget);
      expect(_search(), findsOneWidget);
      expect(find.byKey(ClientsScreen.emptyKey), findsNothing);
    });

    testWidgets('error → ErrorState + retry reloads', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      // 1: before the session settles the list is empty with NO fetch (logged
      // out), so only the post-settle fetch fails.
      int failures = 1;
      repo.hook = (_, _) => failures-- > 0
          ? Future<PageResponse<ClientSummary>>.error(const NetworkFailure())
          : null;
      await _pump(tester, repo);

      expect(find.byKey(ClientsScreen.errorKey), findsOneWidget);
      expect(find.byType(ErrorState), findsOneWidget);

      await tester.tap(find.text(_l10n(tester).retryLabel));
      await tester.pumpAndSettle();

      expect(find.byKey(ClientsScreen.errorKey), findsNothing);
      expect(find.byKey(const Key('client-row-u1')), findsOneWidget);
    });

    testWidgets('list → one row per client, header «Клієнти», no back', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(<ClientSummary>[_registered(), _guest()]));
      expect(find.byKey(ClientsScreen.listKey), findsOneWidget);
      expect(find.byType(ClientListRow), findsNWidgets(2));
      expect(find.text(_l10n(tester).clientsTitle), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
    });
  });

  group('row (CLI-47)', () {
    testWidgets('registered: name, ★ figure, short «Ост.» / «Наст.» dates', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(<ClientSummary>[_registered()]));
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Оксана Мельник'), findsOneWidget);
      expect(find.text('4.9'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(ClientListRow.lastKey)).data,
        'Ост.: 7 лис',
      );
      expect(
        tester.widget<Text>(find.byKey(ClientListRow.nextKey)).data,
        'Наст.: пт, 20 лис, 14:00',
      );
    });

    testWidgets('no phone and no completed-visits count anywhere in the tree', (
      tester,
    ) async {
      await _pump(tester, _FakeRepo(<ClientSummary>[_registered(), _guest()]));
      final Iterable<String> texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? t.textSpan?.toPlainText() ?? '');
      for (final String t in texts) {
        expect(t, isNot(contains('+380')), reason: 'no phone');
        expect(t, isNot(matches(RegExp(r'\d{9,}'))), reason: 'no phone digits');
        expect(t.toLowerCase(), isNot(contains('візит')), reason: t);
      }
      // completedVisits is 9 / 3 in the fixtures — never rendered.
      expect(find.text('9'), findsNothing);
      expect(find.text('3'), findsNothing);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.textContaining('Завершено'), findsNothing);
    });

    testWidgets('null name → «Гість»', (tester) async {
      await _pump(tester, _FakeRepo(<ClientSummary>[_guest(name: null)]));
      expect(find.text(_l10n(tester).bookingDetailGuestClient), findsOneWidget);
    });

    testWidgets('a guest row looks like any row: «—» readout, NO «Запис за '
        'посиланням» kind label', (tester) async {
      await _pump(tester, _FakeRepo(<ClientSummary>[_guest()]));
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Ірина Коваль'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      // i18n-finder-ok: asserts the removed UA copy never renders
      expect(find.text('Запис за посиланням'), findsNothing);
    });

    testWidgets('unrated registered client → «—»', (tester) async {
      await _pump(
        tester,
        _FakeRepo(<ClientSummary>[_registered(avg: null, count: 0)]),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('a client with no visits yet renders neither date line', (
      tester,
    ) async {
      await _pump(
        tester,
        _FakeRepo(<ClientSummary>[
          const ClientSummary(
            ref: ClientRef.registered('u9'),
            displayName: 'Нова Клієнтка',
          ),
        ]),
      );
      expect(find.byKey(ClientListRow.lastKey), findsNothing);
      expect(find.byKey(ClientListRow.nextKey), findsNothing);
    });

    testWidgets('blocked → the «Заблоковано» chip', (tester) async {
      await _pump(
        tester,
        _FakeRepo(<ClientSummary>[_registered(blocked: true)]),
      );
      expect(find.byKey(ClientListRow.blockedKey), findsOneWidget);
      expect(find.text(_l10n(tester).clientBlockedBadge), findsOneWidget);
    });

    testWidgets('screen-reader label keeps the long «останній візит … / '
        'Наступний: …» form and the blocked flag', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(
        tester,
        _FakeRepo(<ClientSummary>[_registered(blocked: true)]),
      );
      final SemanticsNode node = tester.getSemantics(
        find.byKey(const Key('client-row-u1')),
      );
      expect(node.label, contains('Клієнт: Оксана Мельник'));
      expect(node.label, contains('останній візит тиждень тому'));
      expect(node.label, contains('Наступний: пт, 20 лис, 14:00'));
      expect(node.label, contains('Заблоковано'));
      expect(node.label, isNot(contains('Ост.')));
      handle.dispose();
    });

    for (final double width in <double>[360, 414]) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets('no overflow at $width px × text $scale (long wrapping '
            'dates, blocked chip, long name)', (tester) async {
          await _pump(
            tester,
            _FakeRepo(<ClientSummary>[
              _registered(
                name: 'Олександра Мар’яна Тетяна-Вікторія Коваленко-Шевченко',
                blocked: true,
              ),
              _guest(name: null),
            ]),
            width: width,
            textScale: scale,
          );
          expect(find.byType(ClientListRow), findsNWidgets(2));
          // The date lines wrap instead of ellipsizing.
          expect(
            tester.widget<Text>(find.byKey(ClientListRow.nextKey)).overflow,
            isNot(TextOverflow.ellipsis),
          );
        });
      }
    }
  });

  group('app resume re-reads now', () {
    testWidgets('a «Наст.» whose start passed while backgrounded is dropped '
        'on resume, with no refetch', (tester) async {
      final _FakeRepo repo = _FakeRepo(<ClientSummary>[
        _registered(next: _now.add(const Duration(hours: 1))),
      ]);
      final _Harness h = await _pump(tester, repo);
      expect(find.byKey(ClientListRow.nextKey), findsOneWidget);
      final int reads = repo.calls.length;

      h.now = _now.add(const Duration(hours: 2));
      for (final AppLifecycleState st in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pumpAndSettle();

      expect(find.byKey(ClientListRow.nextKey), findsNothing);
      expect(find.byKey(ClientListRow.lastKey), findsOneWidget);
      expect(repo.calls.length, reads, reason: 'no refetch on resume');
    });
  });

  group('search (B507 `q`)', () {
    testWidgets('2 chars → debounce → q sent; the list is re-queried', (
      tester,
    ) async {
      final repo = _FakeRepo(<ClientSummary>[
        _registered(),
        _registered(id: 'u2', name: 'Іван Петренко'),
      ]);
      await _pump(tester, repo);
      final int base = repo.calls.length;
      expect(repo.calls.every((c) => c.q == null), isTrue);

      await tester.enterText(_search(), 'Ів');
      await tester.pump(); // nothing yet: inside the debounce window
      expect(repo.calls, hasLength(base));
      await tester.pump(kClientSearchDebounce);
      await tester.pumpAndSettle();

      expect(repo.calls.last.q, 'Ів');
      expect(repo.calls.last.page, 0);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Іван Петренко'), findsOneWidget);
      // i18n-finder-ok: asserts the exact approved UA copy / data value
      expect(find.text('Оксана Мельник'), findsNothing);
    });

    testWidgets('1 char: red error line, NO q is sent', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      await _pump(tester, repo);
      final int base = repo.calls.length;

      await tester.enterText(_search(), 'О');
      await tester.pump(kClientSearchDebounce);
      await tester.pumpAndSettle();

      expect(
        find.text(_l10n(tester).clientsSearchMinLengthError),
        findsOneWidget,
      );
      expect(repo.calls, hasLength(base), reason: 'only the initial load');
      expect(repo.calls.every((c) => c.q == null), isTrue);
    });

    testWidgets('whitespace only: no q, no error line', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      await _pump(tester, repo);
      final int base = repo.calls.length;
      await tester.enterText(_search(), '   ');
      await tester.pump(kClientSearchDebounce);
      await tester.pumpAndSettle();
      expect(repo.calls, hasLength(base));
      expect(
        find.byKey(const Key('search_query_min_length_hint')),
        findsNothing,
      );
    });

    testWidgets('a focused search is UNFOCUSED when a card is opened, and '
        'stays unfocused (no keyboard) on return', (tester) async {
      final _Harness h = await _pump(
        tester,
        _FakeRepo(<ClientSummary>[_registered()]),
      );
      FocusNode fieldFocus() => tester
          .widget<EditableText>(
            find.descendant(of: _search(), matching: find.byType(EditableText)),
          )
          .focusNode;
      await tester.tap(_search());
      await tester.pump();
      expect(fieldFocus().hasFocus, isTrue);
      // A keyboard dismissed with back leaves the field focused; the row tap
      // is what must drop it.
      await tester.tap(find.byKey(const Key('client-row-u1')));
      await tester.pumpAndSettle();
      expect(find.text('card-user'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ClientsScreen), findsOneWidget);
      expect(fieldFocus().hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('the field caps input at 50 characters', (tester) async {
      await _pump(tester, _FakeRepo(<ClientSummary>[_registered()]));
      await tester.enterText(_search(), 'я' * 80);
      await tester.pump();
      expect(tester.widget<TextField>(_search()).controller!.text.length, 50);
    });
  });

  group('paging', () {
    testWidgets('scrolling near the end appends page 2 (footer spinner while '
        'loading)', (tester) async {
      final List<ClientSummary> rows = <ClientSummary>[
        for (int i = 0; i < 30; i++) _registered(id: 'u$i', name: 'Клієнт $i'),
      ];
      final repo = _FakeRepo(rows);
      await _pump(tester, repo);
      expect(repo.calls.every((c) => c.page == 0), isTrue);

      final Completer<PageResponse<ClientSummary>> gate =
          Completer<PageResponse<ClientSummary>>();
      repo.hook = (int page, _) => page == 1 ? gate.future : null;

      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -4000),
      );
      await tester.pump();
      await tester.pump();

      expect(repo.calls.last.page, 1);
      expect(
        find.byKey(const Key('my_bookings_load_more_spinner')),
        findsOneWidget,
      );

      gate.complete(
        PageResponse<ClientSummary>(
          items: rows.sublist(20),
          page: 1,
          totalPages: 2,
          totalElements: 30,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('my_bookings_load_more_spinner')),
        findsNothing,
      );
      expect(repo.calls.where((c) => c.page == 1), hasLength(1));
    });

    testWidgets('a failed page 2 keeps the rendered rows, drops the spinner '
        'and does not re-fire on further scrolling', (tester) async {
      final List<ClientSummary> rows = <ClientSummary>[
        for (int i = 0; i < 30; i++) _registered(id: 'u$i', name: 'Клієнт $i'),
      ];
      final repo = _FakeRepo(rows);
      await _pump(tester, repo);
      repo.hook = (int page, _) => page == 1
          ? Future<PageResponse<ClientSummary>>.error(const NetworkFailure())
          : null;

      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();
      final int page2Calls = repo.calls.where((c) => c.page == 1).length;
      expect(page2Calls, 1);

      expect(
        find.byKey(const Key('my_bookings_load_more_spinner')),
        findsNothing,
      );
      expect(find.byKey(ClientsScreen.errorKey), findsNothing);
      expect(find.byKey(const Key('client-row-u19')), findsOneWidget);

      await tester.drag(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(
        repo.calls.where((c) => c.page == 1),
        hasLength(page2Calls),
        reason: 'no retry storm on scroll',
      );
    });

    testWidgets(
      'a failed page 2 shows a retry footer; tapping it re-requests page 2',
      (tester) async {
        final List<ClientSummary> rows = <ClientSummary>[
          for (int i = 0; i < 30; i++)
            _registered(id: 'u$i', name: 'Клієнт $i'),
        ];
        final repo = _FakeRepo(rows);
        await _pump(tester, repo);
        bool fail = true;
        repo.hook = (int page, _) => page == 1 && fail
            ? Future<PageResponse<ClientSummary>>.error(const NetworkFailure())
            : null;
        await tester.drag(
          find.byKey(ClientsScreen.listKey),
          const Offset(0, -4000),
        );
        await tester.pumpAndSettle();

        final Finder retry = find.byKey(ClientsScreen.loadMoreRetryKey);
        expect(retry, findsOneWidget, reason: 'the append failure has a UI');
        expect(find.text(_l10n(tester).clientsLoadMoreFailed), findsOneWidget);

        fail = false;
        await tester.ensureVisible(retry);
        await tester.pumpAndSettle();
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(repo.calls.where((c) => c.page == 1), hasLength(2));
        expect(retry, findsNothing);
      },
    );

    testWidgets('pull to refresh reloads page 0', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      await _pump(tester, repo);
      final int base = repo.calls.length;
      await tester.fling(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(
        repo.calls.length,
        base + 1,
        reason: 'the refresh itself fires exactly ONE extra request',
      );
      expect(repo.calls.last.page, 0);
    });

    testWidgets('a FAILED pull to refresh keeps the rows and shows an error '
        'snack, no full-page error', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      await _pump(tester, repo);
      repo.hook = (int page, _) =>
          Future<PageResponse<ClientSummary>>.error(const NetworkFailure());
      final int base = repo.calls.length;
      await tester.fling(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(repo.calls.length, base + 1);
      expect(find.byKey(ClientsScreen.errorKey), findsNothing);
      expect(find.byKey(const Key('client-row-u1')), findsOneWidget);
      expectVelvetSnack(
        const NetworkFailure().userMessage(
          tester.element(find.byType(ClientsScreen)),
        ),
      );
    });

    testWidgets('a refresh keeps the rows (no skeleton flash)', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      await _pump(tester, repo);
      final Completer<PageResponse<ClientSummary>> gate =
          Completer<PageResponse<ClientSummary>>();
      repo.hook = (int page, _) => gate.future;
      final int base = repo.calls.length;
      const Duration frame = Duration(milliseconds: 16); // one frame per pump
      await tester.fling(
        find.byKey(ClientsScreen.listKey),
        const Offset(0, 400),
        1000,
      );
      // Pump until the refresh request is actually in flight (condition, not a
      // guessed duration), then assert the rows are still on screen.
      for (int i = 0; i < 100 && repo.calls.length == base; i++) {
        await tester.pump(frame);
      }
      expect(repo.calls.length, base + 1, reason: 'the refresh is in flight');
      expect(find.byKey(const Key('client-row-u1')), findsOneWidget);
      expect(find.byKey(ClientsScreen.skeletonKey), findsNothing);
      gate.complete(
        PageResponse<ClientSummary>(
          items: <ClientSummary>[_registered()],
          page: 0,
          totalPages: 1,
          totalElements: 1,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('a NEW search shows the skeleton, not the old rows', (
      tester,
    ) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      await _pump(tester, repo);
      expect(find.byKey(const Key('client-row-u1')), findsOneWidget);
      final Completer<PageResponse<ClientSummary>> gate =
          Completer<PageResponse<ClientSummary>>();
      repo.hook = (int page, String? q) => q == null ? null : gate.future;
      await tester.enterText(_search(), 'Zz');
      const Duration frame = Duration(milliseconds: 16); // one frame per pump
      for (int i = 0; i < 100 && repo.calls.last.q != 'Zz'; i++) {
        await tester.pump(frame);
      }
      expect(repo.calls.last.q, 'Zz', reason: 'the search is in flight');
      expect(find.byKey(ClientsScreen.skeletonKey), findsOneWidget);
      expect(find.byKey(const Key('client-row-u1')), findsNothing);
      gate.complete(
        const PageResponse<ClientSummary>(
          items: <ClientSummary>[],
          page: 0,
          totalPages: 0,
          totalElements: 0,
        ),
      );
      await tester.pumpAndSettle();
    });
  });

  group('row tap → card route', () {
    testWidgets('a registered row opens …/user/:userId', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[_registered(), _guest()]);
      final _Harness h = await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('client-row-u1')));
      await tester.pumpAndSettle();
      expect(h.opened.single, '${RouteNames.masterClients}/user/u1');
      expect(find.text('card-user'), findsOneWidget);
    });

    testWidgets('a guest row opens …/guest/:bookingId', (tester) async {
      final repo = _FakeRepo(<ClientSummary>[_registered(), _guest()]);
      final _Harness h = await _pump(tester, repo);
      await tester.tap(find.byKey(const Key('client-row-g1')));
      await tester.pumpAndSettle();
      expect(h.opened.single, '${RouteNames.masterClients}/guest/g1');
      expect(find.text('card-guest'), findsOneWidget);
    });

    testWidgets('owner master mode: the card route carries ?masterId=', (
      tester,
    ) async {
      final repo = _FakeRepo(<ClientSummary>[_registered()]);
      final _Harness h = await _pump(
        tester,
        repo,
        scope: const ClientListScope.salon(salonId: 's1', masterId: 'm-7'),
      );
      await tester.tap(find.byKey(const Key('client-row-u1')));
      await tester.pumpAndSettle();
      expect(
        h.opened.single,
        '${RouteNames.masterClients}/user/u1?masterId=m-7',
      );
    });
  });
}
