// Widget tests for the dynamic category picker in ServiceForm and the
// "suggest a category" dialog.
//
// Coverage:
//   PICKER
//     1. Renders Ukrainian displayName labels from the stubbed provider.
//     2. select → deselect → reselect cycle works; the submitted value is the
//        wire `name` slug (not the displayName).
//     3. "Suggest" affordance opens the dialog.
//   DIALOG
//     3b. Only the display-name field is shown; the legacy editable code/slug
//         field is ABSENT (slug is derived internally at submit).
//     4. Valid submit calls repository.requestCategory once with the derived
//        slug as `name` and the raw display name as `displayName`.
//     5. A non-derivable (punctuation-only) name fails validation on the name
//        field; repository is NOT called.
//     6. 409 → "already exists" SnackBar; 429 → "too many requests" SnackBar.
//    15. Valid Ukrainian name → submit sends transliterated slug as `name`,
//        raw name as `displayName` (exact-arg mock assertion).
//    16. Empty name → required-field error; repository NOT called.
//   PICKER (audit-driven additions)
//     7. error → 'category-chips-error' renders + retry chip; tapping retry
//        re-fetches (repo called again) and the success chip row renders.
//     8. pending → 'category-chips-loading' skeleton renders.
//   DIALOG (audit-driven additions)
//     9. generic (non-Failure) exception → l10n.errUnknown SnackBar; dialog
//        stays open; submit button re-enabled (_submitting reset).
//    10. displayName > 100 chars → validation error; repository NOT called.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'widgets/select_dropdown_test_helpers.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

const _options = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'NAIL_ART', displayName: 'Нейл-арт'),
];

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

/// Builds a minimal single-route [GoRouter] hosting [child].
///
/// The suggest-a-category dialog pops itself with go_router's `context.pop`,
/// which requires a [GoRouter] ancestor in the tree. Hosting the form under a
/// `MaterialApp.router` (rather than a plain `MaterialApp`) supplies that
/// ancestor. `showDialog` still inserts the dialog as a root-Navigator overlay
/// route, and `context.pop` resolves the awaiting `showDialog<bool>` future
/// with the popped result exactly as `Navigator.of(context).pop` did.
GoRouter _formRouter(Widget child) {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) =>
            Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ],
  );
}

Future<void> _pumpForm(
  WidgetTester tester,
  _MockServiceRepository repo, {
  required void Function(MasterServiceCreate) onSubmit,
  // The approvedCategoriesProvider now feeds the picker directly (no longer via
  // repo.fetchApprovedCategories). Pass a custom resolver to exercise the
  // error / loading / alternate-list branches; the default is the happy list.
  Future<List<ServiceCategoryOption>> Function()? categories,
}) async {
  // Selecting a category mounts the second-level _ServiceTypeChips section,
  // making the form taller. Use a roomy viewport so every chip + the submit CTA
  // stay laid out and hit-testable (otherwise a select→deselect→reselect cycle
  // lands on a shifted offset that no longer hits the chip).
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        serviceRepositoryProvider.overrideWithValue(repo),
        approvedCategoriesProvider.overrideWith(
          (ref) async => categories != null ? await categories() : _options,
        ),
        // Selecting a category mounts _ServiceTypeChips → serviceTypesProvider.
        // Stub it to a calm empty list so no un-mocked fetch fires in-tree.
        serviceTypesProvider.overrideWith(
          (ref, String categoryName) async => const <ServiceTypeOption>[],
        ),
      ].cast(),
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        routerConfig: _formRouter(
          ServiceForm(onSubmit: (input) async => onSubmit(input)),
        ),
      ),
    ),
  );
  // Resolve the approvedCategoriesProvider future.
  await tester.pumpAndSettle();
}

/// A minimal pre-populated [MasterService] seeding the edit-flow form with a
/// category already selected (the chip selector reads `initial.category`).
MasterService _serviceWithCategory(String category) => MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Послуга',
  category: category,
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 ₴',
);

/// Pumps a [ServiceForm] seeded with [initial] (edit flow). Optionally clamps
/// the surface to a narrow [physicalWidth]dp viewport so layout regressions
/// (e.g. a Wrap that refuses to wrap) push chips off-screen.
Future<void> _pumpFormWithInitial(
  WidgetTester tester,
  _MockServiceRepository repo, {
  required MasterService initial,
  double? physicalWidth,
  // Feeds approvedCategoriesProvider directly (see _pumpForm). Defaults to the
  // happy list; pass an empty / alternate list to exercise label-fallback cases.
  List<ServiceCategoryOption> categories = _options,
}) async {
  if (physicalWidth != null) {
    tester.view.physicalSize = Size(physicalWidth, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: <Object>[
        serviceRepositoryProvider.overrideWithValue(repo),
        approvedCategoriesProvider.overrideWith((ref) async => categories),
        // The seeded initial.category mounts _ServiceTypeChips on pump → stub
        // serviceTypesProvider to an empty list so no real fetch fires.
        serviceTypesProvider.overrideWith(
          (ref, String categoryName) async => const <ServiceTypeOption>[],
        ),
      ].cast(),
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        routerConfig: _formRouter(
          ServiceForm(initial: initial, onSubmit: (_) async {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const MasterServiceCreate(
        name: 'x',
        durationMinutes: 1,
        priceType: ServicePriceType.fixed,
        price: 1,
        category: 'MANICURE',
      ),
    );
  });

  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
  });

  // ── 1. Renders displayName labels ──────────────────────────────────────────

  testWidgets('1. picker renders Ukrainian displayName labels', (tester) async {
    await _pumpForm(tester, repo, onSubmit: (_) {});

    // Labels live inside the dropdown menu now — open it to inspect them.
    await openCategoryMenu(tester);

    expect(find.text('Манікюр'), findsOneWidget);
    expect(find.text('Нейл-арт'), findsOneWidget);
    // The English wire slug must NOT be displayed.
    expect(find.text('MANICURE'), findsNothing);
    expect(find.text('NAIL_ART'), findsNothing);
  });

  // ── 2. select → deselect → reselect; submitted value is the wire slug ───────

  testWidgets('2. selecting a category submits the wire name slug', (
    tester,
  ) async {
    MasterServiceCreate? submitted;
    await _pumpForm(tester, repo, onSubmit: (i) => submitted = i);

    // Fill required fields so submit passes validation.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Послуга',
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
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '500',
    );

    // Re-select twice (open menu → pick the same option) to prove the selection
    // is stable and re-selecting does not break the wire-value contract.
    await selectCategoryOption(tester, 'MANICURE');
    await selectCategoryOption(tester, 'MANICURE');
    // Service type is mandatory on create — select one (name already typed, so
    // the auto-fill does not clobber it).
    (tester.state(find.byType(ServiceForm)) as dynamic).onServiceTypeSelected(
      const ServiceTypeOption(
        id: 'stype-manicure',
        slug: 'MANICURE_A',
        nameUk: 'Класичний манікюр',
        categoryName: 'MANICURE',
      ),
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();

    expect(submitted, isNotNull);
    expect(
      submitted!.category,
      'MANICURE',
      reason: 'submitted value must be the wire slug, not the displayName',
    );
  });

  testWidgets('2b. no category selected blocks submit (required)', (
    tester,
  ) async {
    MasterServiceCreate? submitted;
    await _pumpForm(tester, repo, onSubmit: (i) => submitted = i);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.byType(TextField),
      ),
      'Послуга',
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
        of: find.byKey(const Key('pricing-fixed-amount')),
        matching: find.byType(TextField),
      ),
      '500',
    );

    // Leave the category dropdown untouched (no selection).
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();

    // Category is required by the backend; submit must be blocked.
    expect(submitted, isNull);
    // The inline required error renders beneath the category field.
    expect(find.text(_l10n(tester).serviceCategoryRequired), findsOneWidget);
  });

  // ── 3. Suggest affordance opens the dialog ──────────────────────────────────

  testWidgets('3. suggest action opens the category-request dialog', (
    tester,
  ) async {
    await _pumpForm(tester, repo, onSubmit: (_) {});

    await openCategoryMenu(tester);
    final suggest = find.byKey(const Key('chip-category-suggest'));
    await tester.ensureVisible(suggest);
    await tester.tap(suggest);
    await tester.pumpAndSettle();

    // Only the display-name field is shown. The legacy editable code/slug field
    // was removed — the slug is now derived internally at submit time.
    expect(
      find.byKey(const Key('field-category-request-name')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('field-category-request-code')), findsNothing);
  });

  // ── 4. Valid submit calls requestCategory once ──────────────────────────────

  testWidgets('4. dialog valid submit calls requestCategory once', (
    tester,
  ) async {
    when(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
      ),
    ).thenAnswer((_) async {});

    await _pumpForm(tester, repo, onSubmit: (_) {});
    await openCategoryMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('chip-category-suggest')));
    await tester.tap(find.byKey(const Key('chip-category-suggest')));
    await tester.pumpAndSettle();

    // Type a Ukrainian display name. The latin wire slug is derived internally
    // at submit time (no code field) — the captured `name` proves it works.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-category-request-name')),
        matching: find.byType(TextField),
      ),
      'Нейл-арт',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
    await tester.pumpAndSettle();

    final captured = verify(
      () => repo.requestCategory(
        name: captureAny(named: 'name'),
        displayName: captureAny(named: 'displayName'),
      ),
    ).captured;
    // captured is [name, displayName].
    expect(captured[0], 'NEIL_ART');
    expect(captured[1], 'Нейл-арт');
  });

  // ── 5. Non-derivable name fails validation (no repository call) ─────────────

  testWidgets('5. punctuation-only name (no derivable slug) blocks submit; '
      'name-field error shown; repository NOT called', (tester) async {
    when(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
      ),
    ).thenAnswer((_) async {});

    await _pumpForm(tester, repo, onSubmit: (_) {});
    final l10n = _l10n(tester);
    await openCategoryMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('chip-category-suggest')));
    await tester.tap(find.byKey(const Key('chip-category-suggest')));
    await tester.pumpAndSettle();

    // A punctuation-only name derives to an empty (invalid) slug, so the name
    // field — the only input now — surfaces the slug-contract error itself.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-category-request-name')),
        matching: find.byType(TextField),
      ),
      '!!!',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
    await tester.pumpAndSettle();

    // (a) The slug-contract error is surfaced (the name field is the only
    // input, and the dialog renders its error row just below it).
    expect(find.text(l10n.categoryRequestCodeError), findsOneWidget);
    // (b) The repository was never reached.
    verifyNever(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
      ),
    );
    // The dialog stays open (submit did not pop).
    expect(
      find.byKey(const Key('field-category-request-name')),
      findsOneWidget,
    );
  });

  // ── 6. 409 / 429 surface the right SnackBar ─────────────────────────────────

  testWidgets('6a. 409 shows the already-exists SnackBar', (tester) async {
    when(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
      ),
    ).thenThrow(const CategoryAlreadyExistsFailure());

    await _pumpForm(tester, repo, onSubmit: (_) {});
    final l10n = _l10n(tester);
    await openCategoryMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('chip-category-suggest')));
    await tester.tap(find.byKey(const Key('chip-category-suggest')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-category-request-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
    await tester.pump(); // start async
    await tester.pump(); // SnackBar inserted

    expect(find.text(l10n.categoryRequestErrExists), findsOneWidget);
  });

  testWidgets('6b. 429 shows the throttled SnackBar', (tester) async {
    when(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
      ),
    ).thenThrow(const CategoryRequestThrottledFailure());

    await _pumpForm(tester, repo, onSubmit: (_) {});
    final l10n = _l10n(tester);
    await openCategoryMenu(tester);
    await tester.ensureVisible(find.byKey(const Key('chip-category-suggest')));
    await tester.tap(find.byKey(const Key('chip-category-suggest')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-category-request-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
    await tester.pump();
    await tester.pump();

    expect(find.text(l10n.categoryRequestErrThrottled), findsOneWidget);
  });

  // ── 7. Picker error + retry ─────────────────────────────────────────────────

  testWidgets(
    '7. picker error renders error state + retry chip; retry re-fetches',
    (tester) async {
      // approvedCategoriesProvider now feeds the picker directly. The resolver
      // fails while [fail] is true, then succeeds once the retry flips it; the
      // retry's `ref.invalidate(approvedCategoriesProvider)` re-runs this same
      // (sticky) override, so flipping the flag changes what the re-fetch yields.
      var fail = true;
      await _pumpForm(
        tester,
        repo,
        onSubmit: (_) {},
        categories: () async {
          if (fail) throw const NetworkFailure();
          return _options;
        },
      );

      // The closed category field shows an error affordance (not a chevron),
      // and no option is selectable yet.
      expect(
        find.descendant(
          of: find.byKey(const Key('select-category-field')),
          matching: find.byIcon(Icons.error_outline_rounded),
        ),
        findsOneWidget,
      );

      // Opening the menu surfaces an escapable error state with a Retry button.
      await openCategoryMenu(tester);
      expect(find.byKey(const Key('select-menu-error')), findsOneWidget);
      expect(find.byKey(const Key('select-menu-retry')), findsOneWidget);

      // Recovery: flip the resolver to success, then tap retry. The retry button
      // closes the sheet and invalidates approvedCategoriesProvider, forcing a
      // fresh fetch that now resolves to data.
      fail = false;
      await tester.tap(find.byKey(const Key('select-menu-retry')));
      await tester.pumpAndSettle();

      // Re-fetch happened: the error affordance is gone and the refreshed
      // options render in the (now resolved) menu — proving a real reload, not a
      // stale error frame.
      expect(
        find.descendant(
          of: find.byKey(const Key('select-category-field')),
          matching: find.byIcon(Icons.error_outline_rounded),
        ),
        findsNothing,
        reason: 'a successful retry must clear the error affordance',
      );
      await openCategoryMenu(tester);
      expect(find.byKey(const Key('select-menu-error')), findsNothing);
      expect(find.byKey(const Key('chip-category-MANICURE')), findsOneWidget);
      expect(find.text('Манікюр'), findsOneWidget);
    },
  );

  // ── 8. Picker loading skeleton ──────────────────────────────────────────────

  testWidgets('8. picker pending renders the loading skeleton', (tester) async {
    // A Completer that never completes → the provider stays in the loading
    // state so the skeleton row is rendered.
    final completer = Completer<List<ServiceCategoryOption>>();

    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          serviceRepositoryProvider.overrideWithValue(repo),
          approvedCategoriesProvider.overrideWith((ref) => completer.future),
        ].cast(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServiceForm(onSubmit: (_) async {}),
            ),
          ),
        ),
      ),
    );
    // Single pump only — do NOT settle (the future never resolves).
    await tester.pump();

    // The closed category field shows its inline loading spinner affordance.
    expect(
      find.descendant(
        of: find.byKey(const Key('select-category-field')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    // Resolve the future so the widget tree can be torn down cleanly.
    completer.complete(_options);
    await tester.pumpAndSettle();
  });

  // ── 9. Dialog generic-failure branch ────────────────────────────────────────

  testWidgets(
    '9. generic exception shows errUnknown SnackBar; dialog stays open; '
    'submit re-enabled',
    (tester) async {
      // A non-Failure, non-409/429 error → the dialog falls back to errUnknown.
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
        ),
      ).thenThrow(Exception('boom'));

      await _pumpForm(tester, repo, onSubmit: (_) {});
      final l10n = _l10n(tester);
      await openCategoryMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('chip-category-suggest')),
      );
      await tester.tap(find.byKey(const Key('chip-category-suggest')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-category-request-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
      await tester.pump(); // start async
      await tester.pump(); // SnackBar inserted

      // Generic fallback message.
      expect(find.text(l10n.errUnknown), findsOneWidget);
      // Dialog stays open (did not pop).
      expect(
        find.byKey(const Key('field-category-request-name')),
        findsOneWidget,
      );
      // Submit button re-enabled — _submitting reset, so the CTA is tappable
      // again (no in-flight spinner).
      expect(
        find.descendant(
          of: find.byKey(const Key('btn-submit-suggest-category')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: '_submitting must be reset so the submit CTA is re-enabled',
      );
    },
  );

  // ── 9b. Dialog in-flight submitting state (never-completing request) ─────────

  testWidgets(
    '9b. while requestCategory is in flight the submit CTA shows its spinner, '
    'the inputs are disabled, and the dialog stays open',
    (tester) async {
      // Hold the request open on a Completer that never resolves during the
      // assertions → the dialog sits in its _submitting state so we can observe
      // the in-flight loading affordance in isolation.
      final completer = Completer<void>();
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) => completer.future);

      await _pumpForm(tester, repo, onSubmit: (_) {});
      await openCategoryMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('chip-category-suggest')),
      );
      await tester.tap(find.byKey(const Key('chip-category-suggest')));
      await tester.pumpAndSettle();

      // Valid name so submit passes validation and reaches the repository.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-category-request-name')),
          matching: find.byType(TextField),
        ),
        'Манікюр',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
      // Single pump advances into the in-flight state WITHOUT settling — the
      // request future never resolves, so pumpAndSettle would hang.
      await tester.pump();

      // (a) The submit CTA renders its in-flight spinner.
      expect(
        find.descendant(
          of: find.byKey(const Key('btn-submit-suggest-category')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason:
            'the submit button shows a spinner while the request is in '
            'flight',
      );

      // (b) The label/icon layer is swapped out for the spinner — the send icon
      // is gone, proving the CTA is in its loading (not idle, tappable) state.
      expect(
        find.descendant(
          of: find.byKey(const Key('btn-submit-suggest-category')),
          matching: find.byIcon(Icons.send_rounded),
        ),
        findsNothing,
        reason: 'the idle label/icon is replaced by the in-flight spinner',
      );

      // (c) The name field is disabled while submitting (no double-edit).
      final TextField nameField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('field-category-request-name')),
          matching: find.byType(TextField),
        ),
      );
      expect(
        nameField.enabled,
        isFalse,
        reason: 'inputs lock while the request is in flight',
      );

      // (d) The dialog stays open (it did not pop while awaiting the request).
      expect(
        find.byKey(const Key('field-category-request-name')),
        findsOneWidget,
      );

      // Resolve the request so the dialog pops and no pending timer leaks into
      // teardown.
      completer.complete();
      await tester.pumpAndSettle();
    },
  );

  // ── 10. displayName length validation (> 100 chars) ─────────────────────────

  testWidgets(
    '10. displayName over 100 chars fails validation; repo NOT called',
    (tester) async {
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async {});

      await _pumpForm(tester, repo, onSubmit: (_) {});
      final l10n = _l10n(tester);
      await openCategoryMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('chip-category-suggest')),
      );
      await tester.tap(find.byKey(const Key('chip-category-suggest')));
      await tester.pumpAndSettle();

      // 101 latin chars. enterText routes through the field's input formatters
      // (including LengthLimitingTextInputFormatter, which would clamp it to
      // 100), so to exercise the _nameError length backstop — the defence
      // against a paste/IME bypass of the formatter — set the underlying
      // controller text directly past the cap.
      final TextField nameField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('field-category-request-name')),
          matching: find.byType(TextField),
        ),
      );
      nameField.controller!.text = 'A' * 101;
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
      await tester.pumpAndSettle();

      // Validation error surfaced; repository never reached.
      expect(find.text(l10n.categoryRequestNameTooLong), findsOneWidget);
      verifyNever(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
        ),
      );
      // Dialog stays open.
      expect(
        find.byKey(const Key('field-category-request-name')),
        findsOneWidget,
      );
    },
  );

  // ── 11. Selected category ABSENT from the approved list → humanized label ────

  testWidgets(
    '11. selected BROWS absent from approved list shows humanized label, '
    'never the raw slug; wire value preserved on submit',
    (tester) async {
      // Approved list does NOT contain BROWS (deactivated/retired category).
      await _pumpFormWithInitial(
        tester,
        repo,
        initial: _serviceWithCategory('BROWS'),
        categories: _options,
      );

      // The persisted selection stays visible in the closed dropdown field even
      // though BROWS is absent from the approved list.
      final field = find.byKey(const Key('select-category-field'));
      expect(field, findsOneWidget);

      // The raw ALL-CAPS slug must NOT be rendered as the label.
      expect(find.text('BROWS'), findsNothing);
      // The humanized form is shown instead, inside the closed field.
      expect(
        find.descendant(of: field, matching: find.text('Brows')),
        findsOneWidget,
      );
    },
  );

  // ── 12. Empty approved list + a selected category → no raw slug leaked ───────

  testWidgets(
    '12. empty approved list + selected category renders humanized label, '
    'never the raw slug',
    (tester) async {
      // Transient empty list while the backend is slow / returns nothing.
      await _pumpFormWithInitial(
        tester,
        repo,
        initial: _serviceWithCategory('NAIL_ART'),
        categories: const <ServiceCategoryOption>[],
      );

      final field = find.byKey(const Key('select-category-field'));
      expect(field, findsOneWidget);

      // Raw slug never shown; multi-word slug humanized to title-case in the
      // closed field.
      expect(find.text('NAIL_ART'), findsNothing);
      expect(
        find.descendant(of: field, matching: find.text('Nail Art')),
        findsOneWidget,
      );
    },
  );

  // ── 13. Selected category PRESENT in approved list → Ukrainian displayName ───

  testWidgets(
    '13. selected category present in approved list shows the Ukrainian '
    'displayName (happy-path regression guard)',
    (tester) async {
      await _pumpFormWithInitial(
        tester,
        repo,
        initial: _serviceWithCategory('MANICURE'),
        categories: _options,
      );

      final field = find.byKey(const Key('select-category-field'));
      expect(field, findsOneWidget);

      // Ukrainian label, not the slug nor a humanized fallback — in the field.
      expect(
        find.descendant(of: field, matching: find.text('Манікюр')),
        findsOneWidget,
      );
      expect(find.text('MANICURE'), findsNothing);
      expect(find.text('Manicure'), findsNothing);
    },
  );

  // ── 14. Narrow viewport: closed field stays within the visible viewport ──────

  testWidgets(
    '14. on a narrow ~360dp viewport the selected category dropdown field '
    'renders inside the visible viewport (no horizontal overflow)',
    (tester) async {
      const many = <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
        ServiceCategoryOption(name: 'NAIL_ART', displayName: 'Нейл-арт'),
        ServiceCategoryOption(name: 'PEDICURE', displayName: 'Педикюр'),
        ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
        ServiceCategoryOption(name: 'COLORING', displayName: 'Фарбування'),
        ServiceCategoryOption(name: 'MAKEUP', displayName: 'Макіяж'),
        ServiceCategoryOption(name: 'BROWS', displayName: 'Брови'),
      ];
      await _pumpFormWithInitial(
        tester,
        repo,
        initial: _serviceWithCategory('BROWS'),
        physicalWidth: 360,
        categories: many,
      );

      final field = find.byKey(const Key('select-category-field'));
      expect(field, findsOneWidget);

      // The full-width dropdown field must lie within the screen bounds.
      final Rect rect = tester.getRect(field);
      final Size screen =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        rect.left,
        greaterThanOrEqualTo(0),
        reason: 'field must not be clipped off the left edge',
      );
      expect(
        rect.right,
        lessThanOrEqualTo(screen.width + 0.5),
        reason: 'field must not overflow horizontally',
      );
      expect(
        rect.top,
        greaterThanOrEqualTo(0),
        reason: 'field must be within the visible viewport',
      );
    },
  );

  // ── 15. Valid Ukrainian name → derived slug + raw displayName (exact args) ───

  testWidgets(
    '15. valid Ukrainian name submits the transliterated slug as name and the '
    'raw display name as displayName',
    (tester) async {
      // Strict arg match (M4): the stub only matches the EXACT derived slug +
      // raw name pair, so the test fails if internal derivation drifts.
      // 'Нарощування вій' → transliterates to 'NAROSHCHUVANNIA_VII'.
      when(
        () => repo.requestCategory(
          name: 'NAROSHCHUVANNIA_VII',
          displayName: 'Нарощування вій',
        ),
      ).thenAnswer((_) async {});

      await _pumpForm(tester, repo, onSubmit: (_) {});
      await openCategoryMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('chip-category-suggest')),
      );
      await tester.tap(find.byKey(const Key('chip-category-suggest')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-category-request-name')),
          matching: find.byType(TextField),
        ),
        'Нарощування вій',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
      await tester.pumpAndSettle();

      // Exactly one call, matching the strict stub above.
      verify(
        () => repo.requestCategory(
          name: 'NAROSHCHUVANNIA_VII',
          displayName: 'Нарощування вій',
        ),
      ).called(1);
    },
  );

  // ── 16. Empty name → required-field error; repository NOT called ─────────────

  testWidgets(
    '16. empty name shows the required-field error; repository NOT called',
    (tester) async {
      when(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
        ),
      ).thenAnswer((_) async {});

      await _pumpForm(tester, repo, onSubmit: (_) {});
      final l10n = _l10n(tester);
      await openCategoryMenu(tester);
      await tester.ensureVisible(
        find.byKey(const Key('chip-category-suggest')),
      );
      await tester.tap(find.byKey(const Key('chip-category-suggest')));
      await tester.pumpAndSettle();

      // Submit with the name field left blank.
      await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
      await tester.pumpAndSettle();

      // Required-field error rendered (single input → unambiguous).
      expect(find.text(l10n.categoryRequestNameError), findsOneWidget);
      // Repository never reached.
      verifyNever(
        () => repo.requestCategory(
          name: any(named: 'name'),
          displayName: any(named: 'displayName'),
        ),
      );
    },
  );
}
