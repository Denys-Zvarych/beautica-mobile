// Phase 426 — «Заблоковані клієнти»: list (registered + guest rows), empty,
// loading, error + retry, and unblock (confirm → DELETE → row folds away →
// snack; dismiss → nothing; failure → error snack, row stays).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block.dart';
import 'package:beautica_mobile/features/moderation/presentation/blocked_clients_screen.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/block_confirm_dialog.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/blocked_entry_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/master_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_notification_repository.dart'
    show FixedRoleAuth;
import '../../../helpers/pump_app.dart';
import '../support/fake_client_block_repository.dart';

/// Pinned "now": 28 Oct 2026, noon UTC (Kyiv 15:00, same day).
DateTime _now() => DateTime.utc(2026, 10, 28, 12);

final ClientBlock _registered = ClientBlock(
  id: 'blk-client',
  kind: ClientBlockKind.client,
  displayName: 'Олег М.',
  createdAt: DateTime.utc(2026, 10, 12, 9),
);

final ClientBlock _guest = ClientBlock(
  id: 'blk-guest',
  kind: ClientBlockKind.guest,
  displayName: 'Ірина С.',
  maskedPhone: '+380 •• ••• 12 34',
  createdAt: DateTime.utc(2026, 10, 3, 9),
);

/// Blocked last year — the day line carries the year.
final ClientBlock _guestNoPhone = ClientBlock(
  id: 'blk-guest-old',
  kind: ClientBlockKind.guest,
  displayName: 'Клієнт',
  createdAt: DateTime.utc(2025, 3, 3, 9),
);

Future<FakeClientBlockRepository> _pump(
  WidgetTester tester, {
  List<ClientBlock> seeded = const <ClientBlock>[],
  FakeClientBlockRepository? repo,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final FakeClientBlockRepository r =
      repo ?? FakeClientBlockRepository(seeded: seeded);
  await tester.pumpApp(
    const BlockedClientsScreen(),
    overrides: <Object>[
      authProvider.overrideWith(
        () => FixedRoleAuth(UserRole.independentMaster),
      ),
      clientBlockRepositoryProvider.overrideWithValue(r),
      clockProvider.overrideWithValue(_now),
    ],
  );
  if (settle) await tester.pumpAndSettle();
  return r;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BlockedClientsScreen)));

Finder _card(String id) => find.byKey(ValueKey<String>('blocked-card-$id'));

Future<void> _tapUnblock(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey<String>('blocked-unblock-$id')));
  await tester.pumpAndSettle();
  expect(find.byType(UnblockClientDialog), findsOne);
}

void main() {
  group('list', () {
    testWidgets('registered + guest rows, newest first, with day lines', (
      tester,
    ) async {
      await _pump(
        tester,
        seeded: <ClientBlock>[_registered, _guest, _guestNoPhone],
      );
      final AppLocalizations l10n = _l10n(tester);

      expect(find.text(l10n.blockedClientsTitle), findsOne);
      expect(find.text(l10n.blockedClientsIntro), findsOne);
      expect(find.byType(BlockedEntryCard), findsNWidgets(3));
      // Server order kept.
      final double y1 = tester.getTopLeft(_card(_registered.id)).dy;
      final double y2 = tester.getTopLeft(_card(_guest.id)).dy;
      final double y3 = tester.getTopLeft(_card(_guestNoPhone.id)).dy;
      expect(y1 < y2 && y2 < y3, isTrue);

      // i18n-finder-ok: fixture names / uk_calendar day output (locale-invariant data)
      expect(find.text('Олег М.'), findsOne);
      // i18n-finder-ok: fixture names / uk_calendar day output (locale-invariant data)
      expect(find.text('Ірина С.'), findsOne);
      // i18n-finder-ok: fixture names / uk_calendar day output (locale-invariant data)
      expect(find.text(l10n.blockedClientsBlockedOn('12 жовтня')), findsOne);
      // i18n-finder-ok: fixture names / uk_calendar day output (locale-invariant data)
      expect(find.text(l10n.blockedClientsBlockedOn('3 жовтня')), findsOne);
      expect(
        // i18n-finder-ok: fixture names / uk_calendar day output (locale-invariant data)
        find.text(l10n.blockedClientsBlockedOn('3 березня 2025')),
        findsOne,
      );
      expect(find.text(l10n.blockedClientsUnblock), findsNWidgets(3));
    });

    testWidgets('masked phone only on a guest that has one', (tester) async {
      await _pump(
        tester,
        seeded: <ClientBlock>[_registered, _guest, _guestNoPhone],
      );
      expect(find.text('+380 •• ••• 12 34'), findsOne);
      expect(
        find.byKey(ValueKey<String>('blocked-phone-${_guest.id}')),
        findsOne,
      );
      expect(
        find.byKey(ValueKey<String>('blocked-phone-${_registered.id}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey<String>('blocked-phone-${_guestNoPhone.id}')),
        findsNothing,
      );
    });

    testWidgets('identity disc carries the name initials', (tester) async {
      await _pump(tester, seeded: <ClientBlock>[_registered, _guestNoPhone]);
      final MasterMark mark = tester.widget<MasterMark>(
        find.descendant(
          of: _card(_registered.id),
          matching: find.byType(MasterMark),
        ),
      );
      expect(mark.initials, 'ОМ');
      // i18n-finder-ok: fixture names / uk_calendar day output (locale-invariant data)
      expect(find.text('ОМ'), findsOne);
      // i18n-finder-ok: fixture names / uk_calendar day output (locale-invariant data)
      expect(find.text('К'), findsOne);
    });

    testWidgets('unblock action has a named screen-reader label', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(tester, seeded: <ClientBlock>[_guest]);
      expect(
        find.bySemanticsLabel(
          _l10n(tester).blockedClientsUnblockSemantics('Ірина С.'),
        ),
        findsOne,
      );
      handle.dispose();
    });
  });

  testWidgets('empty → notice with the preview copy, no cards', (tester) async {
    await _pump(tester);
    expect(find.byKey(BlockedClientsScreen.emptyKey), findsOne);
    expect(
      // i18n-finder-ok: verbatim approved preview copy
      find.text('Ви не заблокували жодного клієнта'),
      findsOne,
    );
    expect(
      // i18n-finder-ok: verbatim approved preview copy
      find.text('Заблокувати клієнта можна з запису: картка клієнта → «⋯».'),
      findsOne,
    );
    expect(find.byType(BlockedEntryCard), findsNothing);
  });

  testWidgets('loading → skeleton until the list lands', (tester) async {
    final Completer<void> gate = Completer<void>();
    final FakeClientBlockRepository repo = FakeClientBlockRepository(
      seeded: <ClientBlock>[_guest],
    )..listGate = gate.future;
    await _pump(tester, repo: repo, settle: false);
    await tester.pump();
    expect(find.byKey(BlockedClientsScreen.loadingKey), findsOne);
    expect(find.byType(BlockedEntryCard), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(BlockedClientsScreen.loadingKey), findsNothing);
    expect(_card(_guest.id), findsOne);
  });

  testWidgets('error → ErrorState; retry refetches the list', (tester) async {
    final FakeClientBlockRepository repo = FakeClientBlockRepository(
      seeded: <ClientBlock>[_guest],
    )..nextFailure = const UnknownFailure();
    // UnknownFailure is deterministic (no hidden auto-retry): the error
    // state renders at once.
    await _pump(tester, repo: repo);
    expect(find.byKey(BlockedClientsScreen.errorKey), findsOne);
    expect(find.byType(ErrorState), findsOne);
    expect(find.byType(BlockedEntryCard), findsNothing);

    await tester.tap(find.byKey(const Key('error_state_retry_button')));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsNothing);
    expect(_card(_guest.id), findsOne);
    expect(repo.calls.where((String c) => c == 'list'), hasLength(2));
  });

  group('unblock', () {
    testWidgets('confirm → DELETE by block id → row gone + snack', (
      tester,
    ) async {
      final FakeClientBlockRepository repo = await _pump(
        tester,
        seeded: <ClientBlock>[_registered, _guest],
      );
      final AppLocalizations l10n = _l10n(tester);
      await _tapUnblock(tester, _guest.id);
      // The 425 dialog, with the row's name.
      // i18n-finder-ok: fixture names / uk_calendar day output (locale-invariant data)
      expect(find.text(l10n.unblockDialogTitle('Ірина С.')), findsOne);

      await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('unblock:${_guest.id}'));
      // Unblocking never goes through POST /blocks (the list has the id).
      expect(repo.calls.where((String c) => c.startsWith('block:')), isEmpty);
      expect(_card(_guest.id), findsNothing);
      expect(_card(_registered.id), findsOne);
      expect(find.text(l10n.clientUnblockedSnack), findsOne);
      // The list was refetched after the write.
      expect(repo.calls.last, 'list');
    });

    testWidgets('dismissing the dialog changes nothing', (tester) async {
      final FakeClientBlockRepository repo = await _pump(
        tester,
        seeded: <ClientBlock>[_guest],
      );
      await _tapUnblock(tester, _guest.id);
      await tester.tap(find.byKey(UnblockClientDialog.dismissKey));
      await tester.pumpAndSettle();

      expect(repo.calls.where((String c) => c.startsWith('unblock:')), isEmpty);
      expect(_card(_guest.id), findsOne);
      expect(find.text(_l10n(tester).clientUnblockedSnack), findsNothing);
    });

    testWidgets('a failed DELETE keeps the row and shows the error', (
      tester,
    ) async {
      final FakeClientBlockRepository repo = await _pump(
        tester,
        seeded: <ClientBlock>[_guest],
      );
      await _tapUnblock(tester, _guest.id);
      repo.nextFailure = const NetworkFailure();
      await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = _l10n(tester);
      expect(_card(_guest.id), findsOne);
      expect(find.text(l10n.clientUnblockedSnack), findsNothing);
      expect(
        find.text(
          const NetworkFailure().userMessage(
            tester.element(find.byType(BlockedClientsScreen)),
          ),
        ),
        findsOne,
      );
    });

    testWidgets('unblocking the last row lands on the empty notice', (
      tester,
    ) async {
      await _pump(tester, seeded: <ClientBlock>[_guest]);
      await _tapUnblock(tester, _guest.id);
      await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(find.byType(BlockedEntryCard), findsNothing);
      expect(find.byKey(BlockedClientsScreen.emptyKey), findsOne);
    });
  });

  group('formatBlockedOnDay', () {
    final DateTime today = DateTime(2026, 10, 28);
    test('same Kyiv year → day + genitive month', () {
      expect(
        formatBlockedOnDay(DateTime.utc(2026, 10, 12, 9), today),
        '12 жовтня',
      );
    });
    test('another year → year appended', () {
      expect(
        formatBlockedOnDay(DateTime.utc(2025, 3, 3, 9), today),
        '3 березня 2025',
      );
    });
    test('the Kyiv day decides, not UTC (22:30 UTC = next Kyiv day)', () {
      expect(
        formatBlockedOnDay(DateTime.utc(2026, 10, 11, 22, 30), today),
        '12 жовтня',
      );
    });
  });

  group('ClientBlock.initials', () {
    ClientBlock named(String n) => ClientBlock(
      id: 'x',
      kind: ClientBlockKind.guest,
      displayName: n,
      createdAt: DateTime.utc(2026),
    );
    test(
      'two words → two letters',
      () => expect(named("Ім'я П.").initials, 'ІП'),
    );
    test('one word → one letter', () => expect(named('Клієнт').initials, 'К'));
    test('blank → empty', () => expect(named('  ').initials, ''));
  });
}
