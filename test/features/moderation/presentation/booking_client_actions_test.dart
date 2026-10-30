// Phase 425 D2/D3/D4 — the booking-detail client strip «⋯»: who sees it,
// what the actions sheet offers per role × booking kind, the block / unblock
// confirmations (copy verbatim from the approved UgcSafety preview), the
// server gates (`clientBlockable` / `clientBlocked` + `clientBlockId`, backend
// 397), the single-DELETE unblock and the 429 copy.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/salon_board_refresh_gate.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_counterparty_header.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/block_confirm_dialog.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/content_actions_sheet.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';
import '../support/fake_client_block_repository.dart';
import '../../../helpers/velvet_snack_matchers.dart';
import '../support/fake_content_report_repository.dart';

const String _clientFull = 'Олена Ковальчук';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._role);
  final UserRole _role;
  @override
  Future<AuthSession> build() async => AuthSession.authenticated(
    user: User(id: 'u1', email: 'u@e.com', role: _role),
    accessToken: 't',
  );
}

Booking _booking({
  String? clientId = 'c1',
  bool clientBlocked = false,
  String? clientBlockId,
  bool clientBlockable = true,
}) {
  final DateTime start = futureBookingStart();
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: clientId,
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
    clientBlocked: clientBlocked,
    clientBlockId: clientBlockId ?? (clientBlocked ? 'block-1' : null),
    clientBlockable: clientBlocked ? false : clientBlockable,
  );
}

class _Env {
  _Env({ClientBlockRepository? blocks, Set<ReportedTarget>? preReported})
    : blocks = blocks ?? FakeClientBlockRepository(),
      reports = FakeContentReportRepository(preReported: preReported);
  final ClientBlockRepository blocks;
  final FakeContentReportRepository reports;
  int detailBuilds = 0;
}

Future<_Env> _pump(
  WidgetTester tester,
  Booking booking, {
  required UserRole role,
  ClientBlockRepository? blocks,
  String? salonId,
  Set<ReportedTarget>? preReported,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final _Env env = _Env(blocks: blocks, preReported: preReported);
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id, salonId: salonId),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(_MockBookingRepository()),
      bookingDetailProvider(booking.id).overrideWith((ref) async {
        env.detailBuilds++;
        return booking;
      }),
      authProvider.overrideWith(() => _StubAuth(role)),
      clientBlockRepositoryProvider.overrideWithValue(env.blocks),
      contentReportRepositoryProvider.overrideWithValue(env.reports),
    ],
  );
  await tester.pumpAndSettle();
  return env;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingDetailScreen)));

final Finder _more = find.byKey(BookingCounterpartyHeader.clientMoreKey);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(_more);
  await tester.pumpAndSettle();
  expect(find.byType(ClientActionsSheet), findsOne);
}

void main() {
  // Phase 428 add-on — report once, ever: an already-reported client loses
  // the REPORT entry only; the block action stays.
  group('already-reported client (phase 428)', () {
    const Set<ReportedTarget> reportedC1 = <ReportedTarget>{
      (type: ReportTargetType.clientProfile, id: 'c1'),
    };

    testWidgets('independent master: block stays, report is gone', (
      tester,
    ) async {
      // RED WHEN `_clientMoreFor` stops checking the reported set.
      await _pump(
        tester,
        _booking(),
        role: UserRole.independentMaster,
        preReported: reportedC1,
      );
      await _openSheet(tester);
      expect(find.byKey(ClientActionsSheet.reportKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.blockKey), findsOne);
    });

    testWidgets('salon master (report only): no «⋯» at all', (tester) async {
      await _pump(
        tester,
        _booking(),
        role: UserRole.salonMaster,
        preReported: reportedC1,
      );
      expect(_more, findsNothing);
    });

    testWidgets('reporting from the sheet hides the entry at once', (
      tester,
    ) async {
      // RED WHEN `ReportController.submit` stops calling `markReported`.
      final _Env env = await _pump(
        tester,
        _booking(),
        role: UserRole.independentMaster,
      );
      await _openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.reportKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReportSheet.reasonKey(ReportReason.spam)));
      await tester.pump();
      await tester.ensureVisible(find.byKey(ReportSheet.submitKey));
      await tester.tap(find.byKey(ReportSheet.submitKey));
      await tester.pumpAndSettle();
      expect(env.reports.requests, hasLength(1));
      await pumpPastVelvetSnack(tester);

      await _openSheet(tester);
      expect(find.byKey(ClientActionsSheet.reportKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.blockKey), findsOne);
    });
  });

  group('who gets the «⋯»', () {
    for (final UserRole role in <UserRole>[
      UserRole.independentMaster,
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      testWidgets('$role on a registered client: report + block', (
        tester,
      ) async {
        await _pump(tester, _booking(), role: role);
        await _openSheet(tester);
        final AppLocalizations l10n = _l10n(tester);
        expect(find.text(_clientFull), findsWidgets);
        expect(find.byKey(ClientActionsSheet.reportKey), findsOne);
        expect(find.text(l10n.clientActionReport), findsOne);
        expect(find.byKey(ClientActionsSheet.blockKey), findsOne);
        expect(find.text(l10n.clientActionBlock), findsOne);
        expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);
      });

      testWidgets('$role on a guest booking: block only (nothing to report)', (
        tester,
      ) async {
        await _pump(tester, _booking(clientId: null), role: role);
        await _openSheet(tester);
        expect(find.byKey(ClientActionsSheet.reportKey), findsNothing);
        expect(find.byKey(ClientActionsSheet.blockKey), findsOne);
      });
    }

    testWidgets('an already-blocked client offers «Розблокувати» instead', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(clientBlocked: true),
        role: UserRole.independentMaster,
      );
      await _openSheet(tester);
      expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.unblockKey), findsOne);
      expect(find.text(_l10n(tester).clientActionUnblock), findsOne);
    });

    testWidgets('clientBlockable false (STAFF walk-in / erased guest): no '
        '«Заблокувати» — a registered client keeps report only', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(clientBlockable: false),
        role: UserRole.independentMaster,
      );
      await _openSheet(tester);
      expect(find.byKey(ClientActionsSheet.reportKey), findsOne);
      expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);
    });

    testWidgets('clientBlockable false on a guest booking: no «⋯» at all', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(clientId: null, clientBlockable: false),
        role: UserRole.salonOwner,
      );
      expect(find.byKey(const Key('booking-detail-client-strip')), findsOne);
      expect(_more, findsNothing);
    });

    testWidgets('clientBlocked without a clientBlockId (broken payload) '
        'offers neither block nor unblock', (tester) async {
      final Booking booking = _booking(
        clientBlocked: true,
      ).copyWith(clientBlockId: null);
      await _pump(tester, booking, role: UserRole.independentMaster);
      await _openSheet(tester);
      expect(find.byKey(ClientActionsSheet.reportKey), findsOne);
      expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);
    });

    testWidgets('salon master on a registered client: report only', (
      tester,
    ) async {
      await _pump(tester, _booking(), role: UserRole.salonMaster);
      await _openSheet(tester);
      expect(find.byKey(ClientActionsSheet.reportKey), findsOne);
      expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);
    });

    testWidgets('salon master on a guest booking: no «⋯» at all', (
      tester,
    ) async {
      await _pump(tester, _booking(clientId: null), role: UserRole.salonMaster);
      expect(find.byKey(const Key('booking-detail-client-strip')), findsOne);
      expect(_more, findsNothing);
    });

    testWidgets('a client viewer never gets a «⋯» (clients never block)', (
      tester,
    ) async {
      await _pump(tester, _booking(), role: UserRole.client);
      expect(_more, findsNothing);
      expect(find.byType(ClientActionsSheet), findsNothing);
    });
  });

  group('report', () {
    testWidgets('opens the report sheet for the CLIENT_PROFILE of the client', (
      tester,
    ) async {
      final _Env env = await _pump(
        tester,
        _booking(),
        role: UserRole.salonMaster,
      );
      await _openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.reportKey));
      await tester.pumpAndSettle();

      expect(find.byType(ReportSheet), findsOne);
      expect(
        find.text(_l10n(tester).reportSubjectClient(_clientFull)),
        findsOne,
      );
      await tester.tap(find.byKey(ReportSheet.reasonKey(ReportReason.spam)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ReportSheet.submitKey));
      await tester.pumpAndSettle();

      expect(
        env.reports.requests.single.targetType,
        ReportTargetType.clientProfile,
      );
      expect(env.reports.requests.single.targetId, 'c1');
    });
  });

  group('block', () {
    testWidgets('confirm dialog copy is verbatim; confirming blocks, shows '
        '«Клієнта заблоковано» and refreshes the detail', (tester) async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository();
      final _Env env = await _pump(
        tester,
        _booking(),
        role: UserRole.independentMaster,
        blocks: repo,
      );
      final AppLocalizations l10n = _l10n(tester);
      await _openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.blockKey));
      await tester.pumpAndSettle();

      expect(find.byType(BlockClientDialog), findsOne);
      expect(
        // i18n-finder-ok: fixture / verbatim approved copy or server passthrough, asserted literally on purpose
        find.text('Заблокувати $_clientFull?'),
        findsOne,
      ); // i18n-finder-ok: verbatim preview copy
      expect(
        find.text(
          'Якщо ви заблокуєте цього клієнта, усі його майбутні записи до вас '
          'буде автоматично скасовано, і він не зможе записатися до вас, '
          'доки ви його не розблокуєте вручну.',
        ), // i18n-finder-ok: verbatim user-approved copy (2026-10-28)
        findsOne,
      );
      expect(
        find.descendant(
          of: find.byKey(BlockClientDialog.confirmKey),
          // i18n-finder-ok: verbatim approved button copy, asserted literally on purpose
          matching: find.text('Заблокувати'),
        ),
        findsOne,
      );
      expect(
        find.descendant(
          of: find.byKey(BlockClientDialog.dismissKey),
          // i18n-finder-ok: verbatim approved button copy, asserted literally on purpose
          matching: find.text('Скасувати'),
        ),
        findsOne,
      );

      final int buildsBefore = env.detailBuilds;
      await tester.tap(find.byKey(BlockClientDialog.confirmKey));
      await tester.pumpAndSettle();

      // The block list has no listener on this screen, so its invalidation
      // refetches nothing here (covered in block_notifier_test).
      expect(repo.calls, <String>['block:b1']);
      expect(find.text(l10n.clientBlockedSnack), findsOne);
      expect(env.detailBuilds, buildsBefore + 1);
    });

    // Phase 398 — the block auto-cancelled N future visits: the snack says
    // how many (ICU plural), replacing «Клієнта заблоковано»; 0 → the plain
    // snack.
    for (final (int count, String? snack) in <(int, String?)>[
      (0, null),
      (1, 'Скасовано 1 запис'), // i18n-finder-ok: verbatim plural form
      (3, 'Скасовано 3 записи'), // i18n-finder-ok: verbatim plural form
      (5, 'Скасовано 5 записів'), // i18n-finder-ok: verbatim plural form
    ]) {
      testWidgets('cancelledBookings $count → '
          '${snack ?? '«Клієнта заблоковано» only'}', (tester) async {
        final FakeClientBlockRepository repo = FakeClientBlockRepository()
          ..cancelOnNewBlock = count;
        await _pump(
          tester,
          _booking(),
          role: UserRole.independentMaster,
          blocks: repo,
        );
        final AppLocalizations l10n = _l10n(tester);
        await _openSheet(tester);
        await tester.tap(find.byKey(ClientActionsSheet.blockKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(BlockClientDialog.confirmKey));
        await tester.pumpAndSettle();

        expect(repo.calls, <String>['block:b1']);
        if (snack == null) {
          expect(find.text(l10n.clientBlockedSnack), findsOne);
          expect(
            find.textContaining('Скасовано'),
            findsNothing,
          ); // i18n-finder-ok: absence of the plural snack
        } else {
          expect(find.text(snack), findsOne);
          expect(find.text(l10n.clientBlockedSnack), findsNothing);
        }
      });
    }

    for (final UserRole role in <UserRole>[
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      testWidgets('$role (salon-wide block) gets the salon dialog body', (
        tester,
      ) async {
        await _pump(tester, _booking(), role: role);
        await _openSheet(tester);
        await tester.tap(find.byKey(ClientActionsSheet.blockKey));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Якщо ви заблокуєте цього клієнта, усі його майбутні записи до '
            'вашого салону буде автоматично скасовано, і він не зможе '
            'записатися до вашого салону, доки ви його не розблокуєте вручну.',
          ), // i18n-finder-ok: verbatim user-approved copy (2026-10-28)
          findsOne,
        );
        expect(find.text(_l10n(tester).blockDialogBody), findsNothing);
      });
    }

    // Phase 398 — the salon board mount forwards ITS salonId to the
    // bulk-cancel fan-out, so the salon «Записи» board (tab not selected →
    // deferred onto the refresh gate) drops the cancelled visits too.
    testWidgets('salon mount: a block that cancelled visits marks THIS '
        "salon's board stale; the plural snack replaces the plain one", (
      tester,
    ) async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository()
        ..cancelOnNewBlock = 2;
      await _pump(
        tester,
        _booking(),
        role: UserRole.salonOwner,
        blocks: repo,
        salonId: 'salon-1',
      );
      final AppLocalizations l10n = _l10n(tester);
      await _openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.blockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BlockClientDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.clientBlockCancelledBookingsSnack(2)), findsOne);
      final SalonBoardRefreshGate gate = ProviderScope.containerOf(
        tester.element(find.byType(BookingDetailScreen)),
      ).read(salonBoardRefreshGateProvider);
      expect(gate.takeStale('salon-1'), isTrue);
    });

    testWidgets('backing out of the confirm blocks nothing', (tester) async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository();
      await _pump(tester, _booking(), role: UserRole.salonOwner, blocks: repo);
      await _openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.blockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BlockClientDialog.dismissKey));
      await tester.pumpAndSettle();

      expect(find.byType(BlockClientDialog), findsNothing);
      expect(repo.calls, isEmpty);
    });

    testWidgets('a 429 shows the block rate-limit copy, never the success '
        'snack', (tester) async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository()
        ..nextFailure = const ClientBlockRateLimitedFailure();
      await _pump(
        tester,
        _booking(),
        role: UserRole.independentMaster,
        blocks: repo,
      );
      final AppLocalizations l10n = _l10n(tester);
      await _openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.blockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BlockClientDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(find.text(l10n.clientBlockedSnack), findsNothing);
      expect(find.text(l10n.clientBlockErrRateLimited), findsOne);
    });

    testWidgets('a STAFF walk-in (400) shows the mapped error', (tester) async {
      await _pump(
        tester,
        _booking(clientId: null),
        role: UserRole.independentMaster,
        blocks: FakeClientBlockRepository(staffBookingIds: <String>{'b1'}),
      );
      final BuildContext ctx = tester.element(find.byType(BookingDetailScreen));
      final String expected = const ValidationFailure(
        fieldErrors: <String, String>{},
      ).userMessage(ctx);
      await _openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.blockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BlockClientDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(find.text(expected), findsOne);
      expect(find.text(_l10n(tester).clientBlockedSnack), findsNothing);
    });
  });

  group('unblock', () {
    testWidgets('confirm dialog copy is verbatim; confirming unblocks with '
        'ONE DELETE of clientBlockId (no POST)', (tester) async {
      final FakeClientBlockRepository repo = FakeClientBlockRepository();
      await repo.block('b1');
      repo.calls.clear();
      await _pump(
        tester,
        _booking(clientBlocked: true),
        role: UserRole.salonAdmin,
        blocks: repo,
      );
      final AppLocalizations l10n = _l10n(tester);
      await _openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.unblockKey));
      await tester.pumpAndSettle();

      expect(find.byType(UnblockClientDialog), findsOne);
      expect(
        // i18n-finder-ok: fixture / verbatim approved copy or server passthrough, asserted literally on purpose
        find.text('Розблокувати $_clientFull?'),
        findsOne,
      ); // i18n-finder-ok: verbatim preview copy
      expect(
        find.text(
          'Клієнт знову зможе записатися до вас.',
        ), // i18n-finder-ok: verbatim preview copy
        findsOne,
      );
      expect(
        find.descendant(
          of: find.byKey(UnblockClientDialog.dismissKey),
          // i18n-finder-ok: verbatim approved button copy, asserted literally on purpose
          matching: find.text('Скасувати'),
        ),
        findsOne,
      ); // i18n-finder-ok: verbatim preview copy

      await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
      await tester.pumpAndSettle();

      expect(repo.calls, <String>['unblock:block-1']);
      expect(repo.stored, isEmpty);
      expect(find.text(l10n.clientUnblockedSnack), findsOne);
    });
  });
}
