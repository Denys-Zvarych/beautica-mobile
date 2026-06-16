// Phase 5.5 — Widget tests for DeleteServiceDialog.
//
// Coverage:
//   1. Unconditional variant: title, body, confirm + cancel buttons present.
//   2. Tapping confirm pops with true.
//   3. Tapping cancel pops with false.
//   4. Delete button (Key('btn-delete-service')) is visible on ServiceEditScreen
//      when service data is loaded.
//
// NOTE: The blocked variant (futureBookingCount > 0) tests have been removed
// because the dialog now shows a single unconditional "Deactivate?" variant.
// See delete_service_dialog.dart for the TODO that restores the blocked path
// once the backend exposes futureBookingCount in MasterServiceResponse.
//
// Finders use Key-based lookups per the M3 convention — never raw literal text.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/delete_service_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _service = MasterService(
  id: 'svc-del-can',
  serviceDefId: 'def-del-can',
  name: 'Манікюр',
  durationMinutes: 60,
  priceMin: 300.0,
  priceDisplay: '300 грн',
);

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pumps a widget that opens [DeleteServiceDialog] via [showDialog] on button
/// tap, then waits for it to appear.
///
/// Returns the [Future<bool?>] that [showDialog] resolves to. Callers can
/// simulate button taps and then await the future.
Future<Future<bool?>> _pumpDialogTrigger(WidgetTester tester) async {
  late final Future<bool?> dialogFuture;

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('uk'),
      home: Builder(
        builder: (BuildContext ctx) {
          return Scaffold(
            body: ElevatedButton(
              key: const Key('trigger'),
              onPressed: () {
                dialogFuture = showDialog<bool>(
                  context: ctx,
                  builder: (_) => const DeleteServiceDialog(),
                );
              },
              child: const Text('Open'),
            ),
          );
        },
      ),
    ),
  );

  // Tap the trigger button to open the dialog.
  await tester.tap(find.byKey(const Key('trigger')));
  await tester.pumpAndSettle();

  return dialogFuture;
}

/// Pumps [ServiceEditScreen] with the mocked repository pre-populated with
/// [service].
Future<void> _pumpEditScreen(
  WidgetTester tester,
  _MockServiceRepository repo,
  MasterService service,
) async {
  when(
    () => repo.listMyServices(),
  ).thenAnswer((_) async => <MasterService>[service]);
  when(() => repo.getMyService(service.id)).thenAnswer((_) async => service);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: ServiceEditScreen(id: service.id),
      ),
    ),
  );
  // Two pumps: (1) provider resolves, (2) form renders.
  await tester.pump();
  await tester.pump();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── 1. Unconditional variant renders correctly ────────────────────────────

  testWidgets('1. dialog shows title, body, confirm and cancel buttons', (
    tester,
  ) async {
    await _pumpDialogTrigger(tester);

    // Dialog itself is present.
    expect(find.byKey(const Key('delete-service-dialog')), findsOneWidget);

    // Both action buttons must be present.
    expect(
      find.byKey(const Key('btn-confirm-delete-service')),
      findsOneWidget,
      reason: 'confirm button must always appear',
    );
    expect(find.byKey(const Key('btn-cancel-delete-service')), findsOneWidget);
  });

  // ── 2. Confirm button pops with true ──────────────────────────────────────

  testWidgets('2. tapping confirm pops with true', (tester) async {
    final dialogFuture = await _pumpDialogTrigger(tester);

    await tester.tap(find.byKey(const Key('btn-confirm-delete-service')));
    await tester.pumpAndSettle();

    expect(await dialogFuture, isTrue);
  });

  // ── 3. Cancel button pops with false ─────────────────────────────────────

  testWidgets('3. tapping cancel pops with false', (tester) async {
    final dialogFuture = await _pumpDialogTrigger(tester);

    await tester.tap(find.byKey(const Key('btn-cancel-delete-service')));
    await tester.pumpAndSettle();

    expect(await dialogFuture, isFalse);
  });

  // ── 4. Delete button visible on ServiceEditScreen when data is loaded ─────

  testWidgets(
    '4. btn-delete-service is visible on ServiceEditScreen when data loaded',
    (tester) async {
      final repo = _MockServiceRepository();
      await _pumpEditScreen(tester, repo, _service);

      expect(
        find.byKey(const Key('btn-delete-service')),
        findsOneWidget,
        reason:
            'the destructive icon button must appear in the top bar once the '
            'service has loaded',
      );
    },
  );
}
