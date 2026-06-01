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
//     4. Valid submit calls repository.requestCategory once with name+displayName.
//     5. Slug validation rejects bad input (no repository call).
//     6. 409 → "already exists" SnackBar; 429 → "too many requests" SnackBar.
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
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

const _options = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'NAIL_ART', displayName: 'Нейл-арт'),
];

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

Future<void> _pumpForm(
  WidgetTester tester,
  _MockServiceRepository repo, {
  required void Function(MasterServiceCreate) onSubmit,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[
        serviceRepositoryProvider.overrideWithValue(repo),
      ].cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServiceForm(onSubmit: (input) async => onSubmit(input)),
          ),
        ),
      ),
    ),
  );
  // Resolve the approvedCategoriesProvider future.
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const MasterServiceCreate(name: 'x', durationMinutes: 1, price: 1),
    );
  });

  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    when(
      () => repo.fetchApprovedCategories(),
    ).thenAnswer((_) async => _options);
  });

  // ── 1. Renders displayName labels ──────────────────────────────────────────

  testWidgets('1. picker renders Ukrainian displayName labels', (tester) async {
    await _pumpForm(tester, repo, onSubmit: (_) {});

    expect(find.text('Манікюр'), findsOneWidget);
    expect(find.text('Нейл-арт'), findsOneWidget);
    // The English wire slug must NOT be displayed.
    expect(find.text('MANICURE'), findsNothing);
    expect(find.text('NAIL_ART'), findsNothing);
  });

  // ── 2. select → deselect → reselect; submitted value is the wire slug ───────

  testWidgets('2. select/deselect/reselect submits the wire name slug', (
    tester,
  ) async {
    MasterServiceCreate? submitted;
    await _pumpForm(tester, repo, onSubmit: (i) => submitted = i);

    final chip = find.byKey(const Key('chip-category-MANICURE'));

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
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
      '500',
    );

    // select → deselect → reselect
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(chip); // deselect
    await tester.pump();
    await tester.tap(chip); // reselect
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

  testWidgets('2b. deselecting all categories blocks submit (required)', (
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
        of: find.byKey(const Key('field-service-price')),
        matching: find.byType(TextField),
      ),
      '500',
    );

    final chip = find.byKey(const Key('chip-category-NAIL_ART'));
    await tester.tap(chip); // select
    await tester.pump();
    await tester.tap(chip); // deselect → no category selected
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();

    // Category is required by the backend; submit must be blocked.
    expect(submitted, isNull);
  });

  // ── 3. Suggest affordance opens the dialog ──────────────────────────────────

  testWidgets('3. suggest chip opens the category-request dialog', (
    tester,
  ) async {
    await _pumpForm(tester, repo, onSubmit: (_) {});

    final suggest = find.byKey(const Key('chip-category-suggest'));
    await tester.ensureVisible(suggest);
    await tester.tap(suggest);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('field-category-request-name')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('field-category-request-code')),
      findsOneWidget,
    );
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
    await tester.ensureVisible(find.byKey(const Key('chip-category-suggest')));
    await tester.tap(find.byKey(const Key('chip-category-suggest')));
    await tester.pumpAndSettle();

    // Typing a Ukrainian display name auto-derives the latin code slug.
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

  // ── 5. Bad slug fails validation (no repository call) ───────────────────────

  testWidgets('5. invalid slug blocks submit (no repository call)', (
    tester,
  ) async {
    when(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
      ),
    ).thenAnswer((_) async {});

    await _pumpForm(tester, repo, onSubmit: (_) {});
    await tester.ensureVisible(find.byKey(const Key('chip-category-suggest')));
    await tester.tap(find.byKey(const Key('chip-category-suggest')));
    await tester.pumpAndSettle();

    // Display name present, but the code is forced to an invalid value.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-category-request-name')),
        matching: find.byType(TextField),
      ),
      'Манікюр',
    );
    // Manually clear the auto-derived code so the slug is empty (invalid).
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('field-category-request-code')),
        matching: find.byType(TextField),
      ),
      '',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
    await tester.pumpAndSettle();

    verifyNever(
      () => repo.requestCategory(
        name: any(named: 'name'),
        displayName: any(named: 'displayName'),
      ),
    );
    // The dialog stays open and shows the code validation error.
    expect(_l10nNothing(tester), isTrue);
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
      // The fetch fails while [fail] is true, then succeeds once the retry flips
      // it. A returned Future.error (rather than a thrown Failure) is what the
      // FutureProvider resolves into AsyncError under pumpAndSettle here.
      var fail = true;
      when(() => repo.fetchApprovedCategories()).thenAnswer(
        (_) => fail
            ? Future<List<ServiceCategoryOption>>.error(const NetworkFailure())
            : Future<List<ServiceCategoryOption>>.value(_options),
      );

      await _pumpForm(tester, repo, onSubmit: (_) {});

      // Error state present, success chips absent.
      expect(find.byKey(const Key('category-chips-error')), findsOneWidget);
      expect(find.byKey(const Key('btn-category-retry')), findsOneWidget);
      expect(find.byKey(const Key('chip-category-MANICURE')), findsNothing);

      // Recovery: flip the stub to success, then tap retry. The retry chip
      // invalidates approvedCategoriesProvider, forcing a fresh repo call.
      fail = false;
      await tester.tap(find.byKey(const Key('btn-category-retry')));
      await tester.pumpAndSettle();

      // Re-fetch happened (the chip cleared and reloaded) and the success state
      // is now rendered.
      verify(() => repo.fetchApprovedCategories()).called(greaterThan(1));
      expect(find.byKey(const Key('category-chips-error')), findsNothing);
      expect(find.byKey(const Key('chip-category-MANICURE')), findsOneWidget);
      expect(find.text('Манікюр'), findsOneWidget);
    },
  );

  // ── 8. Picker loading skeleton ──────────────────────────────────────────────

  testWidgets('8. picker pending renders the loading skeleton', (tester) async {
    // A Completer that never completes → the provider stays in the loading
    // state so the skeleton row is rendered.
    final completer = Completer<List<ServiceCategoryOption>>();
    when(
      () => repo.fetchApprovedCategories(),
    ).thenAnswer((_) => completer.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Object>[
          serviceRepositoryProvider.overrideWithValue(repo),
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

    expect(find.byKey(const Key('category-chips-loading')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

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
}

/// Helper for test 5: confirms the dialog is still present (submit did not pop).
bool _l10nNothing(WidgetTester tester) =>
    find.byKey(const Key('field-category-request-code')).evaluate().isNotEmpty;
