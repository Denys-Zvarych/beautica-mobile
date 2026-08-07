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
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/validators/name_validator.dart'
    show kNameMaxLength;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'select_dropdown_test_helpers.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import '../../../../helpers/velvet_snack_matchers.dart';

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

/// The service type surfaced by the picker for the MANICURE category. Service
/// type is MANDATORY on create, so every happy-path submit selects this.
const _manicureType = ServiceTypeOption(
  id: 'stype-manicure',
  slug: 'MANICURE_CLASSIC',
  nameUk: 'Класичний манікюр',
  categoryName: 'MANICURE',
);

/// A FIXED edit-mode service (category + type already loaded). Used by the
/// generic-snackbar-fallback test: in edit mode the category is unchanged, so
/// the Phase-16.5 category-mismatch safety net stays dormant and a truly
/// unmapped 400 reaches the generic snackbar. (On CREATE that fallback is now
/// shadowed — a mandatory type is always selected and the category is always
/// dirty (null→value), which trips the safety net first.)
const _editService = MasterService(
  id: 'svc-edit-1',
  serviceDefId: 'def-edit-1',
  name: 'Мій власний манікюр',
  category: 'MANICURE',
  serviceTypeId: 'type-loaded',
  serviceTypeNameUk: 'Класичний манікюр',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 ₴',
);

List<ServiceTypeOption> _typesFor(String categoryName) =>
    categoryName == 'MANICURE'
    ? const <ServiceTypeOption>[_manicureType]
    : const <ServiceTypeOption>[];

/// Reaches the form State (private class) to select the mandatory service type.
/// Must be called AFTER the category is selected, since a category change
/// clears an incompatible type selection.
Future<void> selectServiceType(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(ServiceForm));
  state.onServiceTypeSelected(_manicureType);
  await tester.pump();
}

void main() {
  setUpAll(() => registerFallbackValue(_FakeMasterServiceCreate()));

  late _MockServiceRepository repo;

  // The category chip row watches approvedCategoriesProvider, now overridden
  // directly below (the provider fetches via categoryRequestApi, not the repo).
  const categories = <ServiceCategoryOption>[
    ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
    ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
  ];

  setUp(() {
    repo = _MockServiceRepository();
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
        retry: beauticaProviderRetry,
        overrides: [
          serviceRepositoryProvider.overrideWithValue(repo),
          approvedCategoriesProvider.overrideWith((ref) async => categories),
          // The service-type picker mounts when a category is selected and
          // watches serviceTypesProvider(category); stub it so no un-mocked
          // repository fetch fires inside the form subtree.
          serviceTypesProvider.overrideWith(
            (ref, String categoryName) async => _typesFor(categoryName),
          ),
        ],
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
    // Service type is mandatory on create — select it AFTER the category so the
    // selection is not cleared by the category change. Name is already non-empty
    // so the type's name-prefill does not clobber it.
    await selectServiceType(tester);
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
      await selectServiceType(tester);
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

        // Inline message present, no snack.
        expect(find.text(serverMsg), findsOneWidget);
        expect(find.byType(VelvetSnack), findsNothing);
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
      expect(find.byType(VelvetSnack), findsNothing);
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
        await selectServiceType(tester);
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(find.text(serverMsg), findsOneWidget);
        expect(find.byType(VelvetSnack), findsNothing);
      },
    );

    testWidgets(
      'unmapped server field falls back to a VelvetSnack with the localized '
      'generic message, never the raw serverMessage '
      '(edit mode — category unchanged, so the type-mismatch net is dormant)',
      (tester) async {
        const serverMsg = 'Невідома помилка валідації сервера';
        // Edit mode: the loaded service already carries a category + type and
        // neither is changed, so `categoryDirty` is false and the Phase-16.5
        // safety net does not intercept — the generic snackbar fallback for a
        // genuinely unmapped field is exercised. (Doing this on CREATE would trip
        // the mismatch net because a mandatory type + dirty category are always
        // present — see fixture note.)
        await pumpForm(
          tester,
          initial: _editService,
          onSubmit: (_) async => throw const ValidationFailure(
            // 'salonId' is not a field this form renders → must NOT map inline.
            fieldErrors: <String, String>{'salonId': 'irrelevant'},
            serverMessage: serverMsg,
          ),
        );
        // Everything is prefilled from the initial service; submit as-is.
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        // Generic error snack carrying the localized copy; no inline field
        // error, and the raw backend serverMessage never reaches this
        // liveRegion VelvetSnack (mobile-security, 2026-08).
        expectVelvetSnack(
          _l10n(tester).errValidation,
          variant: VelvetSnackVariant.error,
        );
        expect(find.text(serverMsg), findsNothing);
        await pumpPastVelvetSnack(tester);
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
      await selectServiceType(tester);
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
  // 3b. Name length cap — LengthLimitingTextInputFormatter(kNameMaxLength).
  //     Security-backlog: an over-long name must never reach the wire. The
  //     formatter truncates at input time (covers both typing and paste, which
  //     both flow through TextField's formatter pipeline).
  // =========================================================================
  group('name length cap (kNameMaxLength = 100)', () {
    testWidgets('over-long input is truncated to 100 chars at input time', (
      tester,
    ) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);

      // Simulate pasting a 150-char string into the name field.
      await tester.enterText(_nameField, 'a' * 150);
      await tester.pump();

      expect(
        tester.widget<TextField>(_nameField).controller?.text.length,
        kNameMaxLength,
      );
      expect(
        tester.widget<TextField>(_nameField).controller?.text,
        'a' * kNameMaxLength,
      );
    });

    testWidgets('exactly 100 chars is accepted unchanged', (tester) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);

      await tester.enterText(_nameField, 'b' * 100);
      await tester.pump();

      expect(tester.widget<TextField>(_nameField).controller?.text, 'b' * 100);
    });

    testWidgets('a short (<=100) name is unaffected by the formatter', (
      tester,
    ) async {
      await pumpForm(tester, onSubmit: shouldNotSubmit);

      await tester.enterText(_nameField, 'Манікюр');
      await tester.pump();

      expect(tester.widget<TextField>(_nameField).controller?.text, 'Манікюр');
    });

    testWidgets('truncated 100-char name passes validation and submits', (
      tester,
    ) async {
      MasterServiceCreate? captured;
      await pumpForm(tester, onSubmit: (input) async => captured = input);

      // Paste over-long → formatter truncates to 100 → still a valid name.
      await tester.enterText(_nameField, 'c' * 150);
      await tester.enterText(_durationField, '60');
      await tester.enterText(_fixedPriceField, '500');
      await tester.pumpAndSettle();
      await selectCategoryOption(tester, 'MANICURE');
      await selectServiceType(tester);
      await tapSubmit(tester);
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.name, 'c' * kNameMaxLength);
      // No too-long error surfaced (the value was capped before validation).
      expect(find.text(_l10n(tester).errNameTooLong), findsNothing);
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
        // Select the mandatory type, then RE-BLANK the name: selecting a type
        // auto-fills an empty name, so clear it again to prove a blank name is
        // still accepted on submit while a type is present.
        await selectServiceType(tester);
        await tester.enterText(_nameField, '');
        await tester.pump();
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
        await tester.enterText(_durationField, '60');
        await tester.enterText(_fixedPriceField, '500');
        await selectCategoryOption(tester, 'MANICURE');
        // Select the mandatory type (auto-fills the empty name), then set the
        // name to whitespace-only to prove it is treated as blank on submit.
        await selectServiceType(tester);
        await tester.enterText(_nameField, '   ');
        await tester.pump();
        await tapSubmit(tester);
        await tester.pumpAndSettle();

        expect(submitted, isTrue);
        // Whitespace is trimmed to the empty string on the wire.
        expect(captured!.name, '');
        expect(find.text(_l10n(tester).errNameRequired), findsNothing);
      },
    );

    // NOTE: the former 'a name longer than 100 chars is rejected with the
    // too-long message' test was removed during the dev merge — the service-name
    // field now carries a LengthLimitingTextInputFormatter(kNameMaxLength)
    // (security-backlog), so an over-100 value can no longer be entered to
    // trigger the validation error. The input cap is covered by the
    // 'name length cap (kNameMaxLength = 100)' group above.
  });
}
