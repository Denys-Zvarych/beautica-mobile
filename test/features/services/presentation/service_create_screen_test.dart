// Phase 5.3 — Widget tests for ServiceCreateScreen + ServiceForm.
//
// Strategy:
//   - Pump [ServiceCreateScreen] inside [pumpApp] (which wraps it in a minimal
//     ProviderScope + MaterialApp with UK l10n).
//   - Override [serviceRepositoryProvider] with a [_MockServiceRepository]
//     so no real HTTP calls are made.
//   - Tap the submit CTA and inspect field-level error text.
//
// Coverage:
//   1. Empty name shows errRequired / errNameRequired.
//   2. Empty duration (digitsOnly formatter blocks non-digits; leaving it empty
//      after submit shows errRequired).
//   3. Zero duration shows errDurationPositive.
//   4. Duration > 1440 shows errDurationMax.
//   5. Negative price blocked by FilteringTextInputFormatter (digits-only;
//      cannot type '-', so entering '-500' leaves the field as '500').
//   6. Valid submit calls repository.create() with the correct payload.
//   7. Submit button disabled during loading (CTA shows CircularProgressIndicator).
//   8. Empty price shows errRequired (MEDIUM-1).
//   9. servicesListProvider is invalidated after successful create (MEDIUM-2).
//  10. Server error shows SnackBar and screen stays visible (HIGH-2 regression).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/presentation/service_create_screen.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// pump_app.dart intentionally not imported — this test pumps widgets directly.;

// ---------------------------------------------------------------------------
// Fakes + Mocks
// ---------------------------------------------------------------------------

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Stub [MasterService] returned by the mock on success.
const _stubService = MasterService(
  id: 'svc-new',
  name: 'Тест',
  durationMinutes: 30,
  price: 100,
);

/// Resolves the [AppLocalizations] from the pumped widget tree.
AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceCreateScreen)));

/// A minimal [ConsumerWidget] that watches [servicesListProvider] and records
/// every [AsyncValue] state it receives.
///
/// Placed above [ServiceCreateScreen] in the widget tree so the provider is
/// kept alive (has an active subscriber). When the create screen calls
/// [ref.invalidate(servicesListProvider)] the provider rebuilds, posting a new
/// [AsyncLoading] value that this listener captures.
class _ListWatcher extends ConsumerWidget {
  const _ListWatcher({required this.child, required this.states});

  final Widget child;

  /// Mutable list populated by the watcher on every state change.
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(servicesListProvider);
    states.add(value);
    return child;
  }
}

// ---------------------------------------------------------------------------
// Provider overrides
// ---------------------------------------------------------------------------

/// Overrides [serviceRepositoryProvider] with [mock] in a [ProviderScope].
List<Object> _overrides(_MockServiceRepository mock) {
  return <Object>[serviceRepositoryProvider.overrideWithValue(mock)];
}

// ---------------------------------------------------------------------------
// Test group
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeMasterServiceCreate());
  });

  late _MockServiceRepository mockRepo;

  setUp(() {
    mockRepo = _MockServiceRepository();
    // Default stub: create succeeds.
    when(() => mockRepo.create(any())).thenAnswer((_) async => _stubService);
    // Default stub for listMyServices — used when _ListWatcher subscribes to
    // servicesListProvider in test 9.
    when(
      () => mockRepo.listMyServices(),
    ).thenAnswer((_) async => const <MasterService>[]);
  });

  // Convenience: pump the screen.
  //
  // When [watcherStates] is provided, a [_ListWatcher] wraps the screen so
  // that [servicesListProvider] has an active subscriber and its state
  // transitions are recorded into [watcherStates].
  Future<void> pumpCreate(
    WidgetTester tester, {
    List<AsyncValue<Object?>>? watcherStates,
  }) async {
    final Widget screen = watcherStates != null
        ? _ListWatcher(
            states: watcherStates,
            child: const ServiceCreateScreen(),
          )
        : const ServiceCreateScreen();

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(mockRepo).cast(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: screen,
        ),
      ),
    );
    await tester.pump(); // settle initial build
  }

  // Convenience: tap the submit button and settle one frame.
  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
  }

  // ---------------------------------------------------------------------------
  // 1. Empty name shows a required-field error after submit.
  // ---------------------------------------------------------------------------
  testWidgets('empty name shows required error after submit', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    // Leave name empty; fill valid duration and price.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '30',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tapSubmit(tester);

    expect(find.text(l10n.errRequired), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 2. Empty duration shows errRequired after submit.
  // ---------------------------------------------------------------------------
  testWidgets('empty duration shows errRequired after submit', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    // Leave duration empty.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tapSubmit(tester);

    expect(find.text(l10n.errRequired), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 3. Zero duration shows errDurationPositive.
  // ---------------------------------------------------------------------------
  testWidgets('zero duration shows errDurationPositive', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '0',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tapSubmit(tester);

    expect(find.text(l10n.errDurationPositive), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 4. Duration > 1440 shows errDurationMax.
  // ---------------------------------------------------------------------------
  testWidgets('duration > 1440 shows errDurationMax', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '1441',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tapSubmit(tester);

    expect(find.text(l10n.errDurationMax), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // 5. Negative price blocked by FilteringTextInputFormatter.
  //    Typing '-500' into the price field leaves it as '500' (digitsOnly).
  // ---------------------------------------------------------------------------
  testWidgets('price field strips non-digit characters (digitsOnly formatter)', (
    tester,
  ) async {
    await pumpCreate(tester);

    final priceFinder = find.descendant(
      of: find.byKey(const Key('field-service-price')),
      matching: find.byType(TextField),
    );

    await tester.enterText(priceFinder, '-500');
    await tester.pump();

    // FilteringTextInputFormatter.digitsOnly strips the '-'; only '500' remains.
    final TextField tf = tester.widget<TextField>(priceFinder);
    expect(tf.controller?.text, '500');
  });

  // ---------------------------------------------------------------------------
  // 6. Valid submit calls repository.create() with the correct payload.
  // ---------------------------------------------------------------------------
  testWidgets('valid submit calls repository.create with correct data', (
    tester,
  ) async {
    await pumpCreate(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
      '500',
    );
    await tapSubmit(tester);
    await tester.pumpAndSettle();

    final captured = verify(() => mockRepo.create(captureAny())).captured;
    expect(captured.length, 1);
    final input = captured.first as MasterServiceCreate;
    expect(input.name, 'Манікюр');
    expect(input.durationMinutes, 60);
    expect(input.price, 500.0);
    // Description must be null — not included in the form (user decision).
    expect(input.description, isNull);
  });

  // ---------------------------------------------------------------------------
  // 7. Submit button disabled during loading.
  // ---------------------------------------------------------------------------
  testWidgets(
    'submit button shows spinner and is inactive while create is in-flight',
    (tester) async {
      // Make create() never complete so we can inspect the loading state.
      final completer = Completer<MasterService>();
      when(() => mockRepo.create(any())).thenAnswer((_) => completer.future);

      await pumpCreate(tester);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '30',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-price')),
          matching: find.byType(TextField),
        ),
        '200',
      );

      await tapSubmit(tester);
      await tester.pump();

      // The NeumorphicButton renders a CircularProgressIndicator when loading.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Tapping again while loading must not trigger a second create() call.
      await tester.tap(
        find.byKey(const Key('btn-submit-service')),
        warnIfMissed: false,
      );
      await tester.pump();

      // Only the original call — no second invocation.
      verify(() => mockRepo.create(any())).called(1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Clean up: complete the future so the test teardown is tidy.
      completer.complete(_stubService);
    },
  );

  // ---------------------------------------------------------------------------
  // 8. Empty price shows errRequired (MEDIUM-1).
  // ---------------------------------------------------------------------------
  testWidgets('empty price shows errRequired after submit', (tester) async {
    await pumpCreate(tester);
    final l10n = _l10n(tester);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    // Leave price empty.
    await tapSubmit(tester);

    expect(find.text(l10n.errRequired), findsWidgets);
  });

  // ---------------------------------------------------------------------------
  // 9. servicesListProvider is invalidated after successful create (MEDIUM-2).
  //
  // Strategy: a [_ListWatcher] widget watches [servicesListProvider] so the
  // provider has an active subscriber. Before submit there is at least one
  // data/loading state. After [ref.invalidate(servicesListProvider)] the
  // provider restarts, emitting an [AsyncLoading] state. We assert that the
  // watcher received more than one state (initial + post-invalidate loading).
  // ---------------------------------------------------------------------------
  testWidgets('servicesListProvider is invalidated after successful create', (
    tester,
  ) async {
    final states = <AsyncValue<Object?>>[];

    await pumpCreate(tester, watcherStates: states);
    await tester
        .pumpAndSettle(); // settle the initial servicesListProvider load

    final int stateCountBefore = states.length;

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-duration')),
        matching: find.byType(TextField),
      ),
      '60',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
      '500',
    );
    await tapSubmit(tester);
    await tester
        .pump(); // one frame — let Riverpod fire the invalidation rebuild
    await tester.pumpAndSettle(); // settle through loading → data

    // The provider must have emitted additional states after invalidation.
    // This confirms ref.invalidate(servicesListProvider) was called on the
    // create path — the only code that invalidates it is the onSubmit closure.
    expect(states.length, greaterThan(stateCountBefore));
  });

  // ---------------------------------------------------------------------------
  // 10. Server error shows SnackBar and screen stays visible (HIGH-2 regression).
  // ---------------------------------------------------------------------------
  testWidgets(
    'server error during create shows SnackBar and screen is not popped',
    (tester) async {
      when(() => mockRepo.create(any())).thenThrow(const ServerFailure());

      await pumpCreate(tester);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-duration')),
          matching: find.byType(TextField),
        ),
        '60',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-price')),
          matching: find.byType(TextField),
        ),
        '500',
      );
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      // A SnackBar must appear.
      expect(find.byType(SnackBar), findsOneWidget);

      // The create screen must still be in the tree (not popped).
      expect(find.byType(ServiceCreateScreen), findsOneWidget);
    },
  );
}
