// Phase 5.5 — Widget tests for DeleteServiceDialog.
// Phase 319 — extended for the `blocked` variant (D1/D2).
//
// Coverage:
//   1. Unconditional variant: title, body, confirm + cancel buttons present.
//   2. Tapping confirm pops with true.
//   3. Tapping cancel pops with false.
//   4. Delete button (Key('btn-delete-service')) is visible on ServiceEditScreen
//      when service data is loaded. (mobile-backlog row 421, LOW, pre-existing:
//      this duplicates an assertion already in service_edit_screen_test.dart —
//      accepted as-is; not grown further.)
//   5. `blocked: true` renders the blocked title + count-less body and offers
//      NO destructive confirm button — the absence assertion, not just the
//      title, per phase 319's test-scope note.
//   6. `blocked: true` dismissed via its sole action (the shared cancel key)
//      pops `false`/`null`, never `true` — there is nothing to confirm.
//   7. Neither variant renders `deleteServiceBlockedBody(count)` — the
//      retained plural must not leak a fabricated count into the UI.
//
// `blocked` omitted (case 1-4) is the "every current caller renders
// identically" proof for D1 — it is the case most likely to be silently
// dropped by a change that flips the default.
//
// Finders use Key-based lookups per the M3 convention — never raw literal text.

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_edit_screen.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/delete_service_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

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
  priceDisplay: '300 ₴',
);

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pumps a widget that opens [DeleteServiceDialog] via [showDialog] on button
/// tap, then waits for it to appear.
///
/// [blocked] is `null` by default, which constructs `DeleteServiceDialog()`
/// with the `blocked` ARGUMENT ITSELF OMITTED — not merely forwarded as
/// `false` — so the "every current caller renders identically" cases (1-4,
/// 7a) actually exercise the constructor's OWN default rather than an
/// explicit `blocked: false` a test file supplies. A test helper that always
/// forwards an explicit value would pass even if
/// `DeleteServiceDialog`'s default flipped to `true` (mutation check 1)
/// — that gap is exactly what this omission closes. Pass `true` to construct
/// the blocked variant explicitly.
///
/// Returns the [Future<bool?>] that [showDialog] resolves to. Callers can
/// simulate button taps and then await the future.
Future<Future<bool?>> _pumpDialogTrigger(
  WidgetTester tester, {
  bool? blocked,
}) async {
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
                  builder: (_) => blocked == null
                      ? const DeleteServiceDialog()
                      : DeleteServiceDialog(blocked: blocked),
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
      retry: beauticaProviderRetry,
      overrides: [
        serviceRepositoryProvider.overrideWithValue(repo),
        // The edit screen mounts a section that watches approvedCategories
        // Provider (now sourced directly from categoryRequestApiProvider).
        // Override it so the screen settles without a real API hit.
        approvedCategoriesProvider.overrideWith(
          (ref) async => const <ServiceCategoryOption>[
            ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
          ],
        ),
      ],
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

  // ── 5. blocked variant: blocked title/body, NO destructive confirm ────────

  testWidgets(
    '5. blocked:true shows the blocked title/body and offers NO confirm '
    'button',
    (tester) async {
      await _pumpDialogTrigger(tester, blocked: true);

      final BuildContext ctx = tester.element(find.byKey(const Key('trigger')));
      final l10n = AppLocalizations.of(ctx);

      expect(find.byKey(const Key('delete-service-dialog')), findsOneWidget);
      expect(find.text(l10n.deleteServiceBlockedTitle), findsOneWidget);
      expect(find.text(l10n.deleteServiceBlockedBodyNoCount), findsOneWidget);

      // Assert the ABSENCE of the destructive button, not just the changed
      // title — a title-only assertion would pass on a dialog that still
      // offers a delete that cannot work (phase 319 test-scope note).
      expect(
        find.byKey(const Key('btn-confirm-delete-service')),
        findsNothing,
        reason: 'the blocked variant has nothing left to confirm',
      );
      // The sole action reuses the existing cancel key — no new key, no
      // forked finder (D1).
      expect(
        find.byKey(const Key('btn-cancel-delete-service')),
        findsOneWidget,
      );
    },
  );

  // ── 6. blocked variant: dismiss never resolves true ───────────────────────

  testWidgets(
    '6. blocked:true dismissed via its sole action resolves false, never true',
    (tester) async {
      final dialogFuture = await _pumpDialogTrigger(tester, blocked: true);

      await tester.tap(find.byKey(const Key('btn-cancel-delete-service')));
      await tester.pumpAndSettle();

      final bool? result = await dialogFuture;
      expect(result, isNot(isTrue));
      expect(result, isFalse);
    },
  );

  // ── 7. Neither variant leaks the retained plural body with a fabricated ───
  // ──    count ───────────────────────────────────────────────────────────

  testWidgets(
    '7a. unblocked variant never renders deleteServiceBlockedBody(count) — '
    'the retained plural must not leak a fabricated count',
    (tester) async {
      await _pumpDialogTrigger(tester);
      final BuildContext ctx = tester.element(find.byKey(const Key('trigger')));
      final l10n = AppLocalizations.of(ctx);

      // Sample a couple of plural forms — any of them appearing would mean
      // the retained plural leaked into the UI.
      expect(find.text(l10n.deleteServiceBlockedBody(0)), findsNothing);
      expect(find.text(l10n.deleteServiceBlockedBody(1)), findsNothing);
      expect(find.text(l10n.deleteServiceBlockedBody(3)), findsNothing);
    },
  );

  testWidgets(
    '7b. blocked variant never renders deleteServiceBlockedBody(count) — '
    'the retained plural must not leak a fabricated count',
    (tester) async {
      await _pumpDialogTrigger(tester, blocked: true);
      final BuildContext ctx = tester.element(find.byKey(const Key('trigger')));
      final l10n = AppLocalizations.of(ctx);

      expect(find.text(l10n.deleteServiceBlockedBody(0)), findsNothing);
      expect(find.text(l10n.deleteServiceBlockedBody(1)), findsNothing);
      expect(find.text(l10n.deleteServiceBlockedBody(3)), findsNothing);
    },
  );
}
