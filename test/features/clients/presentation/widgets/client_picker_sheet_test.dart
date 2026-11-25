// M552 — showClientPickerSheet: «Мої клієнти» over the shared ClientListView;
// a pick reads the client's CARD once and resolves its ClientPrefill (name
// parts + E.164 phone); a card failure shows ErrorState + retry without
// closing; a dismiss resolves `null`. Blocked clients keep their chip and
// stay pickable (owner 2026-11-25). Audit cycle 1: only owner / admin /
// independent master may open it (canPickClients); the picker's search is its
// own — never the «Клієнти» tab's — and every open starts empty.

import 'package:dio/dio.dart' show CancelToken;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_list_controller.dart'
    show kClientSearchDebounce;
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_row.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_list_view.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_picker_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fakes/fake_notification_repository.dart';
import '../../../../helpers/pump_app.dart';

class _FakeRepo implements ClientRepository {
  _FakeRepo(this.rows, this.cards);

  final List<ClientSummary> rows;

  /// Card per handle; a [Failure] value is thrown instead.
  final Map<ClientRef, Object> cards;
  final List<({ClientListScope scope, ClientRef client})> cardCalls =
      <({ClientListScope scope, ClientRef client})>[];
  final List<ClientListScope> listScopes = <ClientListScope>[];

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
    listScopes.add(scope);
    final List<ClientSummary> hits = <ClientSummary>[
      for (final ClientSummary r in rows)
        if (q == null || (r.displayName ?? '').contains(q)) r,
    ];
    return Future<PageResponse<ClientSummary>>.value(
      PageResponse<ClientSummary>(
        items: page == 0 ? hits : <ClientSummary>[],
        page: page,
        totalPages: 1,
        totalElements: rows.length,
      ),
    );
  }

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    cardCalls.add((scope: scope, client: client));
    final Object? card = cards[client];
    if (card is ClientCard) return card;
    throw card ?? const NotFoundFailure();
  }
}

final DateTime _now = DateTime.utc(2026, 11, 16, 10);

const ClientRef _u1 = ClientRef.registered('u1');
const ClientRef _u2 = ClientRef.registered('u2');
const ClientRef _g1 = ClientRef.guest('g1');

const List<ClientSummary> _rows = <ClientSummary>[
  ClientSummary(ref: _u1, displayName: 'Оксана Мельник'),
  ClientSummary(ref: _u2, displayName: 'Марта Бойко', blocked: true),
  ClientSummary(ref: _g1, displayName: 'Ірина Коваль'),
];

class _Result {
  bool done = false;
  ClientPrefill? value;
}

const Key _tabKey = Key('tab-list');

Future<_Result> _open(
  WidgetTester tester,
  _FakeRepo repo, {
  ClientListScope scope = const ClientListScope.me(),
  UserRole role = UserRole.independentMaster,

  /// Also mounts the «Клієнти» tab's list (same scope) behind the sheet.
  bool withTab = false,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final _Result result = _Result();
  await tester.pumpApp(
    Scaffold(
      body: Column(
        children: <Widget>[
          Builder(
            builder: (BuildContext context) => TextButton(
              key: const Key('open-picker'),
              onPressed: () async {
                result.value = await showClientPickerSheet(
                  context,
                  scope: scope,
                );
                result.done = true;
              },
              child: const Text('open'),
            ),
          ),
          if (withTab)
            Expanded(
              child: ClientListView(
                key: _tabKey,
                scope: scope,
                onRowTap: (_) {},
              ),
            ),
        ],
      ),
    ),
    overrides: <Object>[
      clientRepositoryProvider.overrideWithValue(repo),
      authProvider.overrideWith(() => FixedRoleAuth(role)),
      clockProvider.overrideWithValue(() => _now),
    ],
    retry: (_, _) => null,
  );
  // Settle the session first, as the app's router always has by now: the
  // role gate reads the SETTLED session and fails closed on a cold one.
  ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  ).read(authProvider);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open-picker')));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _reopen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-picker')));
  await tester.pumpAndSettle();
}

Finder _inPicker(Finder f) =>
    find.descendant(of: find.byType(ClientPickerSheet), matching: f);

Finder _inTab(Finder f) =>
    find.descendant(of: find.byKey(_tabKey), matching: f);

String _pickerSearchText(WidgetTester tester) => tester
    .widget<EditableText>(_inPicker(find.byType(EditableText)))
    .controller
    .text;

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ClientPickerSheet)));

void main() {
  testWidgets('sheet: title «Мої клієнти», hint «Ім\'я або телефон», the '
      'shared list with every row; the passed scope is listed', (tester) async {
    final repo = _FakeRepo(_rows, <ClientRef, Object>{});
    const ClientListScope scope = ClientListScope.salon(salonId: 's1');
    await _open(tester, repo, scope: scope);
    final AppLocalizations l10n = _l10n(tester);

    expect(l10n.walkInPickClientTitle, 'Мої клієнти');
    expect(l10n.walkInPickClientSearchHint, "Ім'я або телефон");
    expect(find.text(l10n.walkInPickClientTitle), findsOneWidget);
    expect(find.text(l10n.walkInPickClientSearchHint), findsOneWidget);
    expect(find.byType(ClientListView), findsOneWidget);
    expect(find.byType(ClientListRow), findsNWidgets(3));
    expect(repo.listScopes.toSet(), <ClientListScope>{scope});
  });

  testWidgets('tap a row → resolves the card prefill with its phone', (
    tester,
  ) async {
    final repo = _FakeRepo(_rows, <ClientRef, Object>{
      _u1: const ClientCard(
        ref: _u1,
        displayName: 'Оксана Мельник',
        firstName: 'Оксана',
        lastName: 'Мельник',
        phone: '+380671234567',
      ),
    });
    final _Result r = await _open(tester, repo);

    await tester.tap(find.byKey(const Key('client-row-u1')));
    await tester.pumpAndSettle();

    expect(r.done, isTrue);
    expect(
      r.value,
      const ClientPrefill(
        firstName: 'Оксана',
        lastName: 'Мельник',
        phone: '+380671234567',
      ),
    );
    expect(repo.cardCalls, hasLength(1), reason: 'the card is read once');
    expect(find.byType(ClientPickerSheet), findsNothing);
  });

  testWidgets('registered without a verified phone → phone == null; a card '
      'with NEITHER name part (pre-B550) falls back to the display name', (
    tester,
  ) async {
    final repo = _FakeRepo(_rows, <ClientRef, Object>{
      _u1: const ClientCard(ref: _u1, displayName: 'Оксана Мельник'),
    });
    final _Result r = await _open(tester, repo);

    await tester.tap(find.byKey(const Key('client-row-u1')));
    await tester.pumpAndSettle();

    expect(r.value, const ClientPrefill(firstName: 'Оксана Мельник'));
    expect(r.value?.phone, isNull);
  });

  testWidgets('a blocked client shows the chip and is pickable', (
    tester,
  ) async {
    final repo = _FakeRepo(_rows, <ClientRef, Object>{
      _u2: const ClientCard(
        ref: _u2,
        displayName: 'Марта Бойко',
        firstName: 'Марта',
        lastName: 'Бойко',
        phone: '+380501112233',
        blocked: true,
      ),
    });
    final _Result r = await _open(tester, repo);

    expect(find.byKey(ClientListRow.blockedKey), findsOneWidget);
    await tester.tap(find.byKey(const Key('client-row-u2')));
    await tester.pumpAndSettle();

    expect(r.value?.firstName, 'Марта');
    expect(r.value?.phone, '+380501112233');
  });

  testWidgets('card 404 → ErrorState + retry, the sheet stays; retry that '
      'succeeds resolves the prefill', (tester) async {
    final Map<ClientRef, Object> cards = <ClientRef, Object>{
      _g1: const NotFoundFailure(),
    };
    final repo = _FakeRepo(_rows, cards);
    final _Result r = await _open(tester, repo);

    await tester.tap(find.byKey(const Key('client-row-g1')));
    await tester.pumpAndSettle();

    expect(r.done, isFalse, reason: 'no pop, no prefill');
    expect(find.byType(ClientPickerSheet), findsOneWidget);
    expect(find.byKey(ClientPickerSheet.cardErrorKey), findsOneWidget);
    expect(find.byType(ClientListView), findsNothing);

    cards[_g1] = const ClientCard(
      ref: _g1,
      displayName: 'Ірина Коваль',
      phone: '+380631234567',
    );
    await tester.tap(find.text(_l10n(tester).retryLabel));
    await tester.pumpAndSettle();

    expect(r.done, isTrue);
    expect(
      r.value,
      const ClientPrefill(firstName: 'Ірина Коваль', phone: '+380631234567'),
    );
    expect(repo.cardCalls, hasLength(2));
  });

  testWidgets('dismiss → null', (tester) async {
    final repo = _FakeRepo(_rows, <ClientRef, Object>{});
    final _Result r = await _open(tester, repo);

    await tester.tapAt(const Offset(180, 20)); // the barrier above the sheet
    await tester.pumpAndSettle();

    expect(find.byType(ClientPickerSheet), findsNothing);
    expect(r.done, isTrue);
    expect(r.value, isNull);
    expect(repo.cardCalls, isEmpty);
  });

  test('fromCard: surname only → firstName stays null (no display-name '
      'fallback); first name only → lastName null', () {
    expect(
      ClientPrefill.fromCard(
        const ClientCard(
          ref: _u1,
          displayName: 'Оксана Мельник',
          lastName: 'Мельник',
        ),
      ),
      const ClientPrefill(lastName: 'Мельник'),
    );
    expect(
      ClientPrefill.fromCard(
        const ClientCard(
          ref: _u1,
          displayName: 'Оксана Мельник',
          firstName: '  ',
          lastName: 'Мельник',
        ),
      ),
      const ClientPrefill(lastName: 'Мельник'),
      reason: 'a blank first name with a surname is still surname-only',
    );
    expect(
      ClientPrefill.fromCard(
        const ClientCard(ref: _g1, displayName: 'Ірина К.', firstName: 'Ірина'),
      ),
      const ClientPrefill(firstName: 'Ірина'),
    );
  });

  test('fromCard keeps only an E.164 phone', () {
    expect(
      ClientPrefill.fromCard(
        const ClientCard(ref: _u1, displayName: 'A', phone: '0671234567'),
      ).phone,
      isNull,
    );
    expect(
      ClientPrefill.fromCard(const ClientCard(ref: _g1)),
      const ClientPrefill(),
      reason: 'a nameless card prefills no name (never an empty string)',
    );
    expect(
      ClientPrefill.fromCard(
        const ClientCard(
          ref: _g1,
          firstName: '  ',
          lastName: '',
          displayName: 'Ірина',
        ),
      ),
      const ClientPrefill(firstName: 'Ірина'),
      reason: 'a blank part counts as absent',
    );
    expect(
      ClientPrefill.fromCard(
        const ClientCard(ref: _u1, firstName: 'A', phone: '+380671234567'),
      ).toString(),
      isNot(contains('380')),
      reason: 'PII stays out of toString',
    );
  });

  group('role gate (canPickClients)', () {
    test('only owner, admin and independent master may pick', () {
      expect(
        <UserRole?, bool>{
          for (final UserRole? role in <UserRole?>[...UserRole.values, null])
            role: canPickClients(role),
        },
        <UserRole?, bool>{
          UserRole.client: false,
          UserRole.salonOwner: true,
          UserRole.salonAdmin: true,
          UserRole.salonMaster: false,
          UserRole.independentMaster: true,
          null: false,
        },
      );
    });

    for (final UserRole role in <UserRole>[
      UserRole.salonMaster,
      UserRole.client,
    ]) {
      testWidgets('${role.name}: no sheet, resolves null, lists nothing', (
        tester,
      ) async {
        final repo = _FakeRepo(_rows, <ClientRef, Object>{});
        final _Result r = await _open(tester, repo, role: role);

        expect(find.byType(ClientPickerSheet), findsNothing);
        expect(r.done, isTrue);
        expect(r.value, isNull);
        expect(repo.listScopes, isEmpty);
      });
    }

    testWidgets('an unsettled session fails closed (no sheet)', (tester) async {
      final repo = _FakeRepo(_rows, <ClientRef, Object>{});
      final _Result result = _Result();
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              key: const Key('open-cold'),
              onPressed: () async {
                result.value = await showClientPickerSheet(
                  context,
                  scope: const ClientListScope.me(),
                );
                result.done = true;
              },
              child: const Text('open'),
            ),
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
      await tester.tap(find.byKey(const Key('open-cold')));
      await tester.pumpAndSettle();

      expect(find.byType(ClientPickerSheet), findsNothing);
      expect(result.done, isTrue);
      expect(result.value, isNull);
    });

    for (final UserRole role in <UserRole>[
      UserRole.salonOwner,
      UserRole.salonAdmin,
      UserRole.independentMaster,
    ]) {
      testWidgets('${role.name}: the sheet opens', (tester) async {
        final repo = _FakeRepo(_rows, <ClientRef, Object>{});
        final _Result r = await _open(
          tester,
          repo,
          role: role,
          scope: const ClientListScope.salon(salonId: 's1'),
        );

        expect(find.byKey(ClientPickerSheet.sheetKey), findsOneWidget);
        expect(r.done, isFalse);
      });
    }
  });

  testWidgets('a picker search never changes the «Клієнти» tab list, and a '
      'reopened picker starts with an empty search', (tester) async {
    final repo = _FakeRepo(_rows, <ClientRef, Object>{});
    await _open(tester, repo, withTab: true);
    expect(_inTab(find.byType(ClientListRow)), findsNWidgets(3));
    expect(_inPicker(find.byType(ClientListRow)), findsNWidgets(3));

    await tester.enterText(
      _inPicker(find.byKey(ClientListView.searchKey)),
      'Окс',
    );
    await tester.pump(kClientSearchDebounce);
    await tester.pumpAndSettle();
    expect(_inPicker(find.byType(ClientListRow)), findsOneWidget);
    expect(
      _inTab(find.byType(ClientListRow)),
      findsNWidgets(3),
      reason: 'the tab list is untouched by the picker search',
    );

    await tester.tapAt(const Offset(180, 20)); // dismiss
    await tester.pumpAndSettle();
    expect(find.byType(ClientPickerSheet), findsNothing);
    expect(_inTab(find.byType(ClientListRow)), findsNWidgets(3));

    await _reopen(tester);
    expect(_pickerSearchText(tester), isEmpty);
    expect(_inPicker(find.byType(ClientListRow)), findsNWidgets(3));
  });
}
