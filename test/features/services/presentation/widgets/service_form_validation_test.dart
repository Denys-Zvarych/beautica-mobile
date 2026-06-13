// Regression tests for the 2026-06-03 validation-hardening work on the mobile
// services form. Pumps [ServiceForm] in isolation (not the full screen) so the
// client-side `validator:` paths and the backend field-error mapping are
// exercised directly.
//
// Coverage closed here (gaps flagged by mobile-dev + mobile-perf):
//   1. THE ORIGINATING BUG — duration 1123 rejected client-side with the
//      max-480 message; 480 accepted, 481 rejected, 0 rejected, non-integer
//      rejected, whitespace rejected.
//   2. Inline backend-error mapping — onSubmit throws ValidationFailure with a
//      field-keyed `fieldErrors` map → message rendered INLINE on the matching
//      field (baseDurationMinutes, name, priceMax), never a generic snackbar.
//      Plus the GENERIC-FALLBACK case: an unmapped server field → snackbar with
//      the server message.
//   3. RANGE decimal price — 2-dp accepted, 3-dp rejected by the formatter,
//      priceMax must be strictly > priceMin (equal → rejected, max<min →
//      rejected).
//   4. Name is OPTIONAL — blank / whitespace name submits an empty name (no
//      required error); only a >100-char name is rejected (too-long message).
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider overridden
// with a mock so approvedCategoriesProvider resolves without real HTTP. No raw
// network, no real storage. l10n strings resolved off the pumped tree (M2) —
// never hardcoded Ukrainian literals.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'select_dropdown_test_helpers.dart';

// ---------------------------------------------------------------------------
// Mocks + fallbacks
// ---------------------------------------------------------------------------

class _MockServiceRepository extends Mock implements ServiceRepository {}

class _FakeMasterServiceCreate extends Fake implements MasterServiceCreate {}

// ---------------------------------------------------------------------------
// Finders for the form fields (by Key, never by localised label — M2).
// ---------------------------------------------------------------------------

final _nameField = find.descendant(
  of: find.byKey(const Key('field-service-name')),
  matching: find.byType(TextField),
);
final _durationField = find.descendant(
  of: find.byKey(const Key('field-service-duration')),
  matching: find.byType(TextField),
);
final _fixedPriceField = find.descendant(
  of: find.byKey(const Key('pricing-fixed-amount')),
  matching: find.byType(TextField),
);
final _rangeMinField = find.descendant(
  of: find.byKey(const Key('pricing-range-min')),
  matching: find.byType(TextField),
);
final _rangeMaxField = find.descendant(
  of: find.byKey(const Key('pricing-range-max')),
  matching: find.byType(TextField),
);

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ServiceForm)));

void main() {
  setUpAll(() => registerFallbackValue(_FakeMasterServiceCreate()));

  late _MockServiceRepository repo;

  setUp(() {
    repo = _MockServiceRepository();
    // The category chip row watches approvedCategoriesProvider → repository.
    when(() => repo.fetchApprovedCategories()).thenAnswer(
      (_) async => const <ServiceCategoryOption>[
        ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
        ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
      ],
    );
  });

  /// Pump a [ServiceForm] with [onSubmit] inside a fresh ProviderScope.
  ///
  /// Returns nothing; callers drive the form via the field finders above.
  /// A tall viewport keeps the submit button hittable (the PricingField makes
  /// the column tall — mirrors the existing screen test harness).
  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MasterServiceCreate) onSubmit,
    MasterService? initial,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [serviceRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServiceForm(initial: initial, onSubmit: onSubmit),
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // initial build
  }

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
  }

  /// onSubmit that should never be called (validation must block it).
  Future<void> shouldNotSubmit(MasterServiceCreate _) async {
    fail('onSubmit must not be called when client validation fails');
  }

  /// Fills name + category + fixed price so only the duration field is exercised.
  Future<void> fillValidExceptDuration(WidgetTester tester) async {
    await tester.enterText(_nameField, 'Манікюр');
    await tester.enterText(_fixedPriceField, '500');
    await selectCategoryOption(tester, 'MANICURE');
  }

  // =========================================================================
  // 1. THE ORIGINATING BUG — duration max-480 enforced client-side.
  // =========================================================================
  group('duration max-480 (originating 1123 bug)', () {
    testWidgets('1123 is rejected inline with the max-480 message', (
      tester,
    ) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);
      await fillValidExceptDuration(tester);
      // 481 is 3 digits (within the LengthLimitingTextInputFormatter(3) limit)
      // and exceeds the 480-minute cap — the max-480 validation must block it.
      // The former '1123' was 4 digits and silently truncated to '112' by the
      // formatter, which is a valid duration and caused onSubmit to fire.
      await tester.enterText(_durationField, '481');
      await tapSubmit(tester);

      expect(find.text(_l10n(tester).errDurationMax), findsOneWidget);
    });

    testWidgets('481 (one over the cap) is rejected with the max message', (
      tester,
    ) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);
      await fillValidExceptDuration(tester);
      await tester.enterText(_durationField, '481');
      await tapSubmit(tester);

      expect(find.text(_l10n(tester).errDurationMax), findsOneWidget);
    });

    testWidgets('480 (exact cap) is accepted — onSubmit fires', (tester) async {
      var submitted = false;
      MasterServiceCreate? captured;
      await pumpForm(
        tester,
        onSubmit: (input) async {
          submitted = true;
          captured = input;
        },
      );
      await fillValidExceptDuration(tester);
      await tester.enterText(_durationField, '480');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(submitted, isTrue);
      expect(captured!.durationMinutes, 480);
      // No max error rendered.
      expect(find.text(_l10n(tester).errDurationMax), findsNothing);
    });

    testWidgets('0 is rejected with the positive message', (tester) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);
      await fillValidExceptDuration(tester);
      await tester.enterText(_durationField, '0');
      await tapSubmit(tester);

      expect(find.text(_l10n(tester).errDurationPositive), findsOneWidget);
    });

    testWidgets('empty / whitespace duration is rejected as required', (
      tester,
    ) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);
      await fillValidExceptDuration(tester);
      // The digitsOnly formatter strips spaces, so a whitespace entry collapses
      // to empty — which must surface the required-field error.
      await tester.enterText(_durationField, '   ');
      await tapSubmit(tester);

      expect(find.text(_l10n(tester).errRequired), findsWidgets);
    });
  });

  // =========================================================================
  // 2. INLINE BACKEND-ERROR MAPPING + generic-fallback snackbar.
  // =========================================================================
  group('backend ValidationFailure field mapping', () {
    /// Fills a fully-valid FIXED form (passes client validation) so the only
    /// way an error appears is the backend mapping.
    Future<void> fillFullyValidFixed(WidgetTester tester) async {
      await tester.enterText(_nameField, 'Манікюр');
      await tester.enterText(_durationField, '60');
      await tester.enterText(_fixedPriceField, '500');
      await selectCategoryOption(tester, 'MANICURE');
    }

    testWidgets(
      'baseDurationMinutes server error renders INLINE on the duration field, '
      'not a snackbar',
      (tester) async {
        const serverMsg = 'Тривалість суперечить графіку роботи';
        await pumpForm(
          tester,
          onSubmit: (_) async => throw const ValidationFailure(
            fieldErrors: <String, String>{'baseDurationMinutes': serverMsg},
          ),
        );
        await fillFullyValidFixed(tester);
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        // Inline message present, no snackbar.
        expect(find.text(serverMsg), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('name server error renders inline on the name field', (
      tester,
    ) async {
      const serverMsg = "Назва вже використовується";
      await pumpForm(
        tester,
        onSubmit: (_) async => throw const ValidationFailure(
          fieldErrors: <String, String>{'name': serverMsg},
        ),
      );
      await fillFullyValidFixed(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(find.text(serverMsg), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
      'priceMax (RANGE field) server error renders inline beneath the pair',
      (tester) async {
        const serverMsg = 'Максимальна ціна завелика';
        await pumpForm(
          tester,
          onSubmit: (_) async => throw const ValidationFailure(
            fieldErrors: <String, String>{'priceMax': serverMsg},
          ),
        );
        // Switch to RANGE and fill a client-valid min/max pair.
        await tester.tap(find.byKey(const Key('pricing-toggle-range')));
        await tester.pump();
        await tester.pumpAndSettle();
        await tester.enterText(_nameField, 'Манікюр');
        await tester.enterText(_durationField, '60');
        await tester.enterText(_rangeMinField, '400');
        await tester.enterText(_rangeMaxField, '700');
        await selectCategoryOption(tester, 'MANICURE');
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(find.text(serverMsg), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets(
      'unmapped server field falls back to a SnackBar with the server message',
      (tester) async {
        const serverMsg = 'Невідома помилка валідації сервера';
        await pumpForm(
          tester,
          onSubmit: (_) async => throw const ValidationFailure(
            // 'salonId' is not a field this form renders → must NOT map inline.
            fieldErrors: <String, String>{'salonId': 'irrelevant'},
            serverMessage: serverMsg,
          ),
        );
        await fillFullyValidFixed(tester);
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        // Generic snackbar carrying the server message; no inline field error.
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(serverMsg), findsOneWidget);
      },
    );

    testWidgets('editing the duration field clears its stale server error', (
      tester,
    ) async {
      const serverMsg = 'Тривалість суперечить графіку роботи';
      await pumpForm(
        tester,
        onSubmit: (_) async => throw const ValidationFailure(
          fieldErrors: <String, String>{'baseDurationMinutes': serverMsg},
        ),
      );
      await fillFullyValidFixed(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(find.text(serverMsg), findsOneWidget);

      // Editing the duration must drop the stale inline server message.
      await tester.enterText(_durationField, '90');
      await tester.pump();
      expect(find.text(serverMsg), findsNothing);
    });
  });

  // =========================================================================
  // 3. RANGE decimal price precision + strict max > min.
  // =========================================================================
  group('RANGE decimal price', () {
    Future<void> toRange(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('pricing-toggle-range')));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('2-decimal min/max accepted; onSubmit gets parsed doubles', (
      tester,
    ) async {
      MasterServiceCreate? captured;
      await pumpForm(tester, onSubmit: (input) async => captured = input);
      await toRange(tester);
      await tester.enterText(_nameField, 'Манікюр');
      await tester.enterText(_durationField, '60');
      await tester.enterText(_rangeMinField, '400.25');
      await tester.enterText(_rangeMaxField, '700.50');
      await selectCategoryOption(tester, 'MANICURE');
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.priceType, ServicePriceType.range);
      expect(captured!.priceMin, 400.25);
      expect(captured!.priceMax, 700.50);
    });

    testWidgets('3-decimal entry is rejected wholesale by the formatter', (
      tester,
    ) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);
      await toRange(tester);

      await tester.enterText(_rangeMinField, '400.25');
      await tester.pump();
      expect(
        tester.widget<TextField>(_rangeMinField).controller?.text,
        '400.25',
      );

      // The third decimal must be rejected — the field keeps the valid value.
      await tester.enterText(_rangeMinField, '400.255');
      await tester.pump();
      expect(
        tester.widget<TextField>(_rangeMinField).controller?.text,
        '400.25',
      );
    });

    testWidgets('non-numeric entry is rejected by the formatter', (
      tester,
    ) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);
      await toRange(tester);

      await tester.enterText(_rangeMaxField, 'abc');
      await tester.pump();
      // Letters never pass the decimal formatter → field stays empty.
      expect(tester.widget<TextField>(_rangeMaxField).controller?.text, '');
    });

    testWidgets(
      'priceMax == priceMin is rejected (strictly greater required)',
      (tester) async {
        await pumpForm(tester, onSubmit: shouldNotSubmit);
        await toRange(tester);
        await tester.enterText(_nameField, 'Манікюр');
        await tester.enterText(_durationField, '60');
        await tester.enterText(_rangeMinField, '500');
        await tester.enterText(_rangeMaxField, '500');
        await tapSubmit(tester);
        await tester.pump();

        expect(find.text(_l10n(tester).errPriceMaxGtMin), findsOneWidget);
      },
    );

    testWidgets('priceMax < priceMin is rejected', (tester) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);
      await toRange(tester);
      await tester.enterText(_nameField, 'Манікюр');
      await tester.enterText(_durationField, '60');
      await tester.enterText(_rangeMinField, '800');
      await tester.enterText(_rangeMaxField, '500');
      await tapSubmit(tester);
      await tester.pump();

      expect(find.text(_l10n(tester).errPriceMaxGtMin), findsOneWidget);
    });
  });

  // =========================================================================
  // 4. Name is OPTIONAL (Item 4). A blank / whitespace name is VALID — submit
  //    proceeds, no required error. Only a too-long value is rejected.
  //    (Updated 2026-06-08: the required-name contract was removed — the backend
  //    now defaults a blank name to the selected service-type name.)
  // =========================================================================
  group('name optional (required-name contract removed)', () {
    testWidgets(
      'blank name is VALID → onSubmit fires with an empty name, no required '
      'error',
      (tester) async {
        var submitted = false;
        MasterServiceCreate? captured;
        await pumpForm(
          tester,
          onSubmit: (input) async {
            submitted = true;
            captured = input;
          },
        );
        // Leave the name field blank; fill everything else.
        await tester.enterText(_durationField, '60');
        await tester.enterText(_fixedPriceField, '500');
        await selectCategoryOption(tester, 'MANICURE');
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(
          submitted,
          isTrue,
          reason: 'a blank name must not block submit (name is optional)',
        );
        // The blank name flows through verbatim — NOT substituted with the
        // category / type name (the _effectiveName stopgap was removed).
        expect(captured!.name, '');
        // No required-name error is ever rendered.
        expect(find.text(_l10n(tester).errNameRequired), findsNothing);
      },
    );

    testWidgets(
      'whitespace-only name is treated as blank → VALID, submits empty name',
      (tester) async {
        var submitted = false;
        MasterServiceCreate? captured;
        await pumpForm(
          tester,
          onSubmit: (input) async {
            submitted = true;
            captured = input;
          },
        );
        await tester.enterText(_nameField, '   ');
        await tester.enterText(_durationField, '60');
        await tester.enterText(_fixedPriceField, '500');
        await selectCategoryOption(tester, 'MANICURE');
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(submitted, isTrue);
        // Whitespace is trimmed to the empty string on the wire.
        expect(captured!.name, '');
        expect(find.text(_l10n(tester).errNameRequired), findsNothing);
      },
    );

    testWidgets(
      'a name longer than 100 chars is rejected with the too-long message',
      (tester) async {
        await pumpForm(tester, onSubmit: shouldNotSubmit);
        // 101 characters — one over the backend @Size(max = 100) cap.
        await tester.enterText(_nameField, 'я' * 101);
        await tester.enterText(_durationField, '60');
        await tester.enterText(_fixedPriceField, '500');
        await selectCategoryOption(tester, 'MANICURE');
        await tapSubmit(tester);
        await tester.pump();

        expect(find.text(_l10n(tester).errNameTooLong), findsOneWidget);
      },
    );
  });
}
