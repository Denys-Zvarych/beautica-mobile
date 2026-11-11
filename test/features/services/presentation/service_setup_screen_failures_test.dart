// [ServiceSetupScreen] widget tests:
// 503 busy / 409 duplicate on save, request affordances, retry snack lifetime.
//
// Split by phase from the former `service_setup_screen_test.dart`; the
// shared fixtures and helpers live in `service_setup_test_harness.dart`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_type_suggestion_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/velvet_snack_matchers.dart';
import 'service_setup_test_harness.dart';

void main() {
  late Harness h;

  setUp(() {
    h = Harness();
    registerFallbackValue(const <MasterServiceBulkItem>[]);
    registerFallbackValue(const MasterServiceUpdate());
  });

  // ── 503 BulkSetupBusyFailure — retry, and STAY on the screen ───────────────
  //
  // The per-master bulk lock was held past the backend's 3 s ceiling. The batch
  // is all-or-nothing, so NOTHING was written: the master's whole configuration
  // is still valid and a retry is the only useful next action. The screen must
  // therefore keep them where they are and hand them an explicit RETRY.
  //
  // The failure is stubbed ASYNCHRONOUSLY (`thenAnswer((_) async => throw …)`),
  // never `thenThrow`: a Dio-backed repository always fails asynchronously, and
  // a synchronous throw takes a different path through the notifier's
  // AsyncValue.guard than the one production hits.

  group('503 BulkSetupBusyFailure — retryable snackbar, no navigation', () {
    /// Stands up a single valid included row and taps save. Returns a counter
    /// that the bulkCreate stub increments on EVERY call, so the retry action's
    /// effect is observable as 1 → 2 rather than inferred.
    Future<int Function()> failingSaveOnce(
      WidgetTester tester,
      Failure failure,
    ) async {
      var calls = 0;
      when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
        calls++;
        throw failure;
      });

      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, 'type-classic');
      await fillRowFixed(tester, 'type-classic', duration: '60', price: '500');

      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      return () => calls;
    }

    testWidgets(
      'shows serviceSetupErrBusy with a RETRY action, keeps the master on the '
      'screen, and the action re-invokes bulkCreate (1 → 2)',
      (tester) async {
        final calls = await failingSaveOnce(
          tester,
          const BulkSetupBusyFailure(),
        );

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(calls(), 1);

        // The retry affordance itself — remove `onRetry` from lib/ and this is
        // the assertion that goes red. expectVelvetSnack's `actionLabel` param
        // asserts the trailing action text renders on the showing snack.
        expectVelvetSnack(
          l10n.serviceSetupErrBusy,
          variant: VelvetSnackVariant.error,
          actionLabel: l10n.serviceSetupRetry,
        );

        // The master stays put with their configuration intact.
        expect(find.byType(ServiceSetupScreen), findsOneWidget);
        expect(
          h.pushedRoutes,
          isEmpty,
          reason:
              'a 503 wrote nothing — navigating away would discard a still-'
              'valid selection',
        );
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);

        // Tapping RETRY re-submits — the observable proof that the action is
        // wired to _save and not a no-op label.
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(
          calls(),
          2,
          reason: 'the RETRY action must re-run the save, not merely dismiss',
        );
        expect(find.byType(ServiceSetupScreen), findsOneWidget);
        expect(h.pushedRoutes, isEmpty);
        // The retry re-fired the same (still-failing) save, which shows a
        // SECOND retryable snack — drain it so its dwell timer does not leak.
        await pumpPastVelvetSnack(tester, hasAction: true);
      },
    );

    testWidgets(
      'a NON-retryable failure (409) shows no action-carrying VelvetSnack — '
      'the retry affordance is specific to the 503 branch',
      (tester) async {
        final calls = await failingSaveOnce(
          tester,
          const ServiceDuplicateFailure(),
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(calls(), 1);
        expect(
          find.text(l10n.serviceSetupRetry),
          findsNothing,
          reason:
              'only the transient 503 gets a RETRY; a duplicate would fail '
              'identically on every retry',
        );
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── 409 ServiceDuplicateFailure on save — stay, do NOT pop ─────────────────
  //
  // In APPEND mode owned types are already un-includable, so reaching a 409 means
  // the catalogue changed underneath the screen (another device, or a type added
  // since it mounted). The batch was rolled back, so the selection is still
  // meaningful: the screen refreshes its snapshot sources and keeps the master
  // here to deselect the offender and re-save. Forcing a navigation would throw
  // away their unsaved configuration.

  group('409 ServiceDuplicateFailure on save keeps the selection', () {
    Future<void> pumpWithSingleValidRow(WidgetTester tester) async {
      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, 'type-classic');
      await fillRowFixed(tester, 'type-classic', duration: '60', price: '500');

      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows serviceErrDuplicate and does NOT leave the screen (the selection '
      'survives)',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => throw const ServiceDuplicateFailure());

        await pumpWithSingleValidRow(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(find.text(l10n.serviceErrDuplicate), findsOneWidget);

        expect(
          find.byType(ServiceSetupScreen),
          findsOneWidget,
          reason:
              'the batch was rolled back — popping would discard the master\'s '
              'unsaved configuration',
        );
        expect(h.pushedRoutes, isEmpty);
        // The row is still included AND still carries its typed values.
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find
                    .descendant(
                      of: find.byKey(const Key('setup_row_type-classic')),
                      matching: find.byType(TextField),
                    )
                    .first,
              )
              .controller
              ?.text,
          '60',
        );
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'CONTRAST — the identical flow with a SUCCESSFUL save DOES leave for the '
      'services list',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => createdService);

        await pumpWithSingleValidRow(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(find.text(l10n.serviceSetupSuccess), findsOneWidget);
        expect(
          h.pushedRoutes,
          contains(RouteNames.services),
          reason:
              'only the success path leaves — this is what makes the 409 "stays "'
              'assertion above meaningful rather than vacuous',
        );
        expect(find.byType(ServiceSetupScreen), findsNothing);
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── Request affordances — missing CATEGORY strip + per-category TYPE prompt ─
  //
  // Two requests with different scopes. The category strip sits above the chip
  // Wrap and takes no argument; the service-type prompt closes each expanded
  // category's rows and MUST forward that category's own wire slug. A prompt
  // that opens the dialog for the wrong category is the bug worth catching, so
  // the slug is read off the mounted dialog widget rather than inferred from the
  // fact that a dialog appeared.

  group('request affordances (category strip + per-category type prompt)', () {
    testWidgets('tapping btn-setup-request-category opens the category-request '
        'dialog', (tester) async {
      await pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          existingServices: const <MasterService>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CategoryRequestDialog), findsNothing);

      await tester.tap(find.byKey(const Key('btn-setup-request-category')));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryRequestDialog), findsOneWidget);
      expect(
        find.byKey(const Key('field-category-request-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('btn-submit-suggest-category')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a successful category request invalidates the catalogue and snackbars '
      'categoryRequestSuccess',
      (tester) async {
        when(
          () => h.repo.requestCategory(
            name: any(named: 'name'),
            displayName: any(named: 'displayName'),
            initialServiceName: any(named: 'initialServiceName'),
          ),
        ).thenAnswer((_) async {});

        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            existingServices: const <MasterService>[],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-request-category')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-category-request-name')),
            matching: find.byType(TextField),
          ),
          'Нарощування вій',
        );
        await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.byType(CategoryRequestDialog), findsNothing);
        expect(find.text(l10n.categoryRequestSuccess), findsOneWidget);
        verify(
          () => h.repo.requestCategory(
            name: any(named: 'name'),
            displayName: 'Нарощування вій',
            initialServiceName: any(named: 'initialServiceName'),
          ),
        ).called(1);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'each expanded category closes with its OWN suggest-type prompt, and the '
      'prompt threads THAT category\'s slug into the dialog',
      (tester) async {
        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[
              manicure,
              hair,
            ]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
              'HAIR': <ServiceTypeOption>[typeCut],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await expand(tester, 'MANICURE');
        await expand(tester, 'HAIR');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // One prompt per expanded category, each labelled with the category's
        // Ukrainian DISPLAY name (not its wire slug).
        expect(
          find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('suggest_type_HAIR')),
          findsOneWidget,
        );
        // Derived from the FIXTURES' own displayName rather than repeating the
        // literal: the label under test is exactly "whatever display name that
        // category carries", so sourcing it from the fixture proves the wiring
        // instead of proving two copies of a string match. It also keeps the
        // finder locale-free (`scripts/forbid_cyrillic_finder.sh`) — a
        // hardcoded 'Манікюр' here would silently become findsNothing the day
        // EN ships.
        expect(
          find.text(l10n.serviceSetupMissingTypePrompt(manicure.displayName)),
          findsOneWidget,
        );
        expect(
          find.text(l10n.serviceSetupMissingTypePrompt(hair.displayName)),
          findsOneWidget,
        );

        // Tap the SECOND category's prompt. If the prompt were wired to the
        // wrong category (or to one shared handler) the dialog would carry
        // 'MANICURE' and this would go red.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('suggest_type_HAIR')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('suggest_type_HAIR')),
                matching: find.byType(GestureDetector),
              )
              .last,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ServiceTypeSuggestionDialog), findsOneWidget);
        expect(
          tester
              .widget<ServiceTypeSuggestionDialog>(
                find.byType(ServiceTypeSuggestionDialog),
              )
              .categoryName,
          'HAIR',
          reason:
              'the prompt must forward its OWN category slug — a suggestion '
              'filed against the wrong category is silently wrong data',
        );
        expect(
          find.byKey(const Key('field-service-type-suggest-name')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the MANICURE prompt opens the dialog for MANICURE (the mirror of the '
      'HAIR case, so neither slug is hard-coded)',
      (tester) async {
        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[
              manicure,
              hair,
            ]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
              'HAIR': <ServiceTypeOption>[typeCut],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await expand(tester, 'MANICURE');
        await expand(tester, 'HAIR');

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
                matching: find.byType(GestureDetector),
              )
              .last,
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ServiceTypeSuggestionDialog>(
                find.byType(ServiceTypeSuggestionDialog),
              )
              .categoryName,
          'MANICURE',
        );
      },
    );

    testWidgets(
      'a successful service-type suggestion snackbars serviceTypeSuggestSuccess',
      (tester) async {
        when(
          () => h.repo.suggestServiceType(
            categoryName: any(named: 'categoryName'),
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async {});

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await expand(tester, 'MANICURE');

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
                matching: find.byType(GestureDetector),
              )
              .last,
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-service-type-suggest-name')),
            matching: find.byType(TextField),
          ),
          'Ламінування вій',
        );
        await tester.tap(
          find.byKey(const Key('btn-submit-suggest-service-type')),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.byType(ServiceTypeSuggestionDialog), findsNothing);
        expect(find.text(l10n.serviceTypeSuggestSuccess), findsOneWidget);
        verify(
          () => h.repo.suggestServiceType(
            categoryName: 'MANICURE',
            name: 'Ламінування вій',
            description: any(named: 'description'),
          ),
        ).called(1);
        await pumpPastVelvetSnack(tester);
      },
    );

    // ── The invalidate after a suggestion must actually REFRESH ──────────────
    //
    // `_suggestServiceType` ends with `ref.invalidate(serviceTypesProvider(slug))`
    // so an auto-approved suggestion "can appear on the next expand". That is a
    // behavioural promise, not a cosmetic one, and it is the only mechanism by
    // which a master ever sees the type they just suggested without killing the
    // app.
    //
    // The promise is currently BROKEN and the break is invisible: dropping the
    // provider does nothing, because `_toggleCategory` short-circuits on
    // `_rowsByCategory.containsKey(slug)` and re-expanding therefore never
    // re-reads the provider. Nothing in the 889-test suite noticed, because
    // every other test asserts only that the dialog closed and the snackbar
    // rendered.
    //
    // This test drives the OBSERVABLE consequence — re-expanding shows the
    // refreshed list — and additionally counts provider builds, so it fails on
    // the CAUSE (no refetch) rather than only on the symptom.
    testWidgets(
      'after a successful suggestion, re-expanding the category REFETCHES its '
      'types and renders the newly approved one',
      (tester) async {
        when(
          () => h.repo.suggestServiceType(
            categoryName: any(named: 'categoryName'),
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async {});

        // Counts real provider BUILDS. The first build models the catalogue
        // before the suggestion; every later one models the backend having
        // auto-approved it, so the refreshed list carries the extra type.
        var typeFetches = 0;

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          // Hand-built rather than via `h.overrides`: this test needs a
          // serviceTypesProvider override whose RESULT CHANGES between builds,
          // which the map-shaped helper cannot express. Duplicating a provider
          // override (helper list + extra entry) throws in Riverpod, so the
          // list is assembled once here.
          overrides: <Object>[
            serviceRepositoryProvider.overrideWithValue(h.repo),
            servicesListProvider.overrideWith(
              () => SeededServicesList(const <MasterService>[]),
            ),
            approvedCategoriesProvider.overrideWith(
              (ref) => const <ServiceCategoryOption>[manicure],
            ),
            serviceTypesProvider('MANICURE').overrideWith((ref) {
              typeFetches++;
              return typeFetches == 1
                  ? const <ServiceTypeOption>[typeClassic]
                  : const <ServiceTypeOption>[typeClassic, typeGel];
            }),
          ],
        );
        await expand(tester, 'MANICURE');

        // Baseline: exactly one build so far, and the not-yet-suggested type is
        // absent. This is the control that makes the post-suggestion assertion
        // non-vacuous — without it, a `findsOneWidget` on type-gel could be
        // satisfied by the type having been there all along.
        expect(typeFetches, 1);
        expect(find.byKey(const Key('setup_row_type-classic')), findsOneWidget);
        expect(find.byKey(const Key('setup_row_type-gel')), findsNothing);

        // Suggest a type for MANICURE and let it succeed.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
                matching: find.byType(GestureDetector),
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-service-type-suggest-name')),
            matching: find.byType(TextField),
          ),
          'Ламінування вій',
        );
        await tester.tap(
          find.byKey(const Key('btn-submit-suggest-service-type')),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.serviceTypeSuggestSuccess), findsOneWidget);
        // Drain the still-showing snack BEFORE the next tap: it is
        // bottom-anchored and would otherwise sit over the category chip,
        // hit-testing into the overlay and silently swallowing the tap below.
        await pumpPastVelvetSnack(tester);

        // Collapse, then re-expand — «the next expand», exactly as the
        // invalidate's own doc comment promises.
        await expand(tester, 'MANICURE'); // collapse
        await expand(tester, 'MANICURE'); // re-expand

        expect(
          typeFetches,
          greaterThanOrEqualTo(2),
          reason:
              'the invalidate is dead unless a re-expand actually re-reads the '
              'provider — `_toggleCategory` returns early on '
              '`_rowsByCategory.containsKey(slug)`, so the cached rows must be '
              'dropped alongside the invalidate for the refresh to happen',
        );
        expect(
          find.byKey(const Key('setup_row_type-gel')),
          findsOneWidget,
          reason:
              'a master who suggests a type and is told it was submitted must '
              'be able to see and configure it once approved, without '
              'restarting the app',
        );
      },
    );
  });

  // ── 503 RETRY AFTER LEAVING — the snack must not survive with a live action ─
  //
  // `_showErrorSnack` posts a VelvetSnack on the app's ROOT `Overlay` (see
  // `velvet_snack_host.dart`), which — like the retired `ScaffoldMessenger`-
  // backed bar before it — is NOT scoped to this route's own Navigator. So
  // WITHOUT the explicit `dispose()` → `unawaited(_retrySnack?.dismiss())`
  // call, the 503 snack (deliberately given the longer `dwellWithAction`, 6s,
  // so it is still up while the master decides) would survive a pop/go away
  // from the setup screen, with its «Повторити» action still wired to `_save`
  // on a State that is by then DISPOSED.
  //
  // `_save`'s very first statement is `AppLocalizations.of(context)`, so a tap
  // on a still-live action does not degrade — it throws on a deactivated
  // element. `dispose()`'s explicit dismiss is the fix; this test asserts the
  // INVARIANT it guarantees — no exception, and no second POST — leaving room
  // for the snack to still be mid-exit-animation at the moment we check rather
  // than asserting it is instantly gone.

  group('503 retry AFTER leaving the screen (disposed-state crash)', () {
    testWidgets(
      'tapping the retry action once the master has left must not throw and '
      'must not re-POST',
      (tester) async {
        var calls = 0;
        when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
          calls++;
          // Async, never `thenThrow` — a Dio-backed repository always fails
          // asynchronously, and a sync throw takes a different path through the
          // notifier's AsyncValue.guard than production hits.
          throw const BulkSetupBusyFailure();
        });

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await expand(tester, 'MANICURE');
        await toggleRowOn(tester, 'type-classic');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Precondition: the 503 branch ran and put its retry bar up.
        expect(calls, 1);
        expect(find.text(l10n.serviceSetupRetry), findsOneWidget);

        // Leave the screen the way a master would — the close affordance.
        await tester.tap(find.byKey(const Key('btn-setup-close')));
        await tester.pumpAndSettle();
        expect(
          find.byType(ServiceSetupScreen),
          findsNothing,
          reason:
              'precondition: the setup screen is gone and its State is '
              'disposed',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'leaving the screen must not throw on its own',
        );

        // `dispose()`'s `unawaited(_retrySnack?.dismiss())` starts an async
        // exit animation, so the snack may still be mid-teardown for a frame
        // or two — this stays a conditional tap (not an unconditional
        // `findsNothing`) so the test is not coupled to that animation timing.
        // Either way, "still there AND still live enough to crash on tap" is
        // the one outcome that must never happen.
        final Finder retry = find.text(l10n.serviceSetupRetry);
        if (retry.evaluate().isNotEmpty) {
          await tester.tap(retry);
          await tester.pumpAndSettle();
        }

        expect(
          tester.takeException(),
          isNull,
          reason:
              'even if the snack outlives the route for a frame (it lives on '
              'the ROOT Overlay, not scoped to this route), invoking its '
              'action must never run _save against a disposed ConsumerState '
              '(AppLocalizations.of on a deactivated element throws)',
        );
        expect(
          calls,
          1,
          reason:
              'a retry fired from a screen the master has already left must '
              'not silently POST their abandoned selection',
        );
      },
    );

    testWidgets(
      'CONTROL — retrying WITHOUT leaving still re-POSTs, so the assertion '
      'above is about the disposed state and not about retry being broken',
      (tester) async {
        var calls = 0;
        when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
          calls++;
          throw const BulkSetupBusyFailure();
        });

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await expand(tester, 'MANICURE');
        await toggleRowOn(tester, 'type-classic');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(calls, 1);

        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(calls, 2);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── _retrySnack handle lifetime ────────────────────────────────────────────
  //
  // `dispose` dismisses the tracked 503 snack so a route the master left cannot
  // leave a live retry action behind.
  //
  // This group predates the VelvetSnack migration and originally pinned a
  // `ScaffoldFeatureController`-specific footgun: a handle whose bar had
  // already left the `ScaffoldMessenger` queue (by timeout, swipe, or a third
  // party clearing it) made `close()` operate on an EMPTY queue —
  // `assert(_snackBars.first == controller)` threw `StateError: No element` in
  // debug, and silently killed an unrelated bar in release. `_retrySnack` had
  // to be nulled the instant its bar left the queue by any route OTHER than
  // `_showSnack` replacing it or `dispose` closing it, tracked via
  // `controller.closed.whenComplete` + an `identical()` guard against a
  // slow-completing older bar nulling a newer handle.
  //
  // VelvetSnack removes the whole footgun structurally: [VelvetSnackHandle]
  // wraps a `GlobalKey`, and `dismiss()` is `_key.currentState?.retire(...)` —
  // null-safe by construction. Calling `dismiss()` on a handle whose snack
  // already retired (by timeout, swipe, or single-slot pre-emption from a
  // NEWER snack) is simply a no-op; there is no queue to be out of sync with,
  // and no `identical()` guard is needed because `_showErrorSnack` overwrites
  // `_retrySnack` SYNCHRONOUSLY when it posts a new snack (no async completion
  // race to lose to). The tests below are kept as the regression net for that
  // null-safety property, updated for the mechanism that actually makes them
  // pass now.
  //
  // ALSO NOTE — the timeout IS now a reachable removal path, unlike before.
  // The old `SnackBar` set `persist = persist ?? action != null`, so a bar
  // carrying a `SnackBarAction` never auto-dismissed at all. VelvetSnack has no
  // such escape hatch: an action-carrying snack dwells LONGER
  // (`VelvetSnackMotion.dwellWithAction`, 6s, vs the plain 4s) but still
  // eventually retires on its own. The first test below pins that dwell
  // window instead of pinning eternal persistence.

  group('_retrySnack is dropped when its bar goes away on its own', () {
    /// Stands up one valid row, saves into a 503, and returns once the retry
    /// bar is up. The stub keeps failing, so a retry would 503 again.
    Future<void> saveInto503(WidgetTester tester) async {
      when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
        throw const BulkSetupBusyFailure();
      });

      await pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await expand(tester, 'MANICURE');
      await toggleRowOn(tester, 'type-classic');
      await fillRowFixed(tester, 'type-classic', duration: '60', price: '500');
      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('the 503 snack carries an action, so it dwells the LONGER '
        'dwellWithAction window (6s) rather than the plain 4s — but, unlike '
        'the retired SnackBar `persist` footgun, it still eventually retires '
        'on its own', (tester) async {
      await saveInto503(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      expect(find.text(l10n.serviceSetupRetry), findsOneWidget);

      // Past the PLAIN dwell (4s) but comfortably short of the action dwell
      // (6s) — proves the retry snack is using `dwellWithAction`, not the
      // shorter default, giving the master real time to reach the action.
      // fixed-wait-ok: probing a dwell WINDOW, not a race — the margin below
      // the 6s ceiling is deliberate, not a flaky timing guess.
      await tester.pump(VelvetSnackMotion.dwell + const Duration(seconds: 1));
      expect(
        find.text(l10n.serviceSetupRetry),
        findsOneWidget,
        reason:
            'a snack carrying an action must dwell VelvetSnackMotion.'
            'dwellWithAction (6s), not the plain 4s dwell — if this goes '
            'red the retry snack started expiring before the master can '
            'realistically reach the action',
      );

      // Unlike the retired ScaffoldMessenger-backed bar (`persist = persist
      // ?? action != null`, which NEVER auto-dismissed a bar carrying a
      // SnackBarAction), VelvetSnack has no such escape hatch — it always
      // eventually retires an action-carrying snack too, just later.
      await pumpPastVelvetSnack(tester, hasAction: true);
      expect(
        find.text(l10n.serviceSetupRetry),
        findsNothing,
        reason:
            'VelvetSnack auto-retires eventually even with an action — '
            'this is the deliberate behaviour change from the old SnackBar '
            '`persist` footgun this migration removes',
      );
    });

    testWidgets(
      'a 503 snack SWIPED away, then a dispose, must not throw — dismiss() '
      'on an already-retired handle is a safe no-op',
      (tester) async {
        await saveInto503(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(
          find.text(l10n.serviceSetupRetry),
          findsOneWidget,
          reason: 'precondition: the 503 branch put its retry snack up',
        );

        // The reachable unattended removal: the master flicks the snack away
        // rather than acting on it. VelvetSnack wires the exact same
        // `Dismissible` (DismissDirection.down) the old SnackBar did — see
        // `velvet_snack_host.dart`'s `_VelvetSnackScope.build()`.
        await tester.fling(
          find.byType(VelvetSnack),
          const Offset(0, 300),
          1000,
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.serviceSetupRetry),
          findsNothing,
          reason:
              'precondition: the swipe really removed the snack. If it is '
              'still up, the dispose assertion below is vacuous',
        );

        // Now leave. `dispose` will call `_retrySnack?.dismiss()`.
        await tester.tap(find.byKey(const Key('btn-setup-close')));
        await tester.pumpAndSettle();

        expect(
          find.byType(ServiceSetupScreen),
          findsNothing,
          reason: 'precondition: the State really was disposed',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'the swipe already retired the underlying `_VelvetSnackScopeState`'
              ', so its `GlobalKey.currentState` is null by the time dispose '
              'calls dismiss() — `VelvetSnackHandle.dismiss()` is null-safe by '
              'construction (`_key.currentState?.retire(...)`), unlike the '
              'retired `ScaffoldFeatureController.close()`, which asserted '
              '`_snackBars.first == controller` and threw on an empty queue',
        );
      },
    );

    testWidgets(
      'two 503s in a row — the second snack is still owned, so leaving '
      'dismisses it (the first snack retiring must not null the newer '
      'handle)',
      (tester) async {
        await saveInto503(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Retry immediately: `_showErrorSnack` posts a second retry snack,
        // which pre-empts (retires) the first via the single-slot host, and
        // SYNCHRONOUSLY overwrites `_retrySnack` with the new handle — no
        // async completion race to lose to (see the group doc comment above).
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.serviceSetupRetry),
          findsOneWidget,
          reason: 'precondition: the retry 503 posted a fresh retry snack',
        );

        await tester.tap(find.byKey(const Key('btn-setup-close')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text(l10n.serviceSetupRetry),
          findsNothing,
          reason:
              'dispose must still own the SECOND snack and dismiss it. If the '
              'first snack retiring had nulled `_retrySnack`, this snack would '
              'outlive the route with a live action bound to a disposed State',
        );
      },
    );

    testWidgets(
      '503 then SUCCESS — the untracked success snack survives the pop and '
      'the stale retry handle takes nothing with it',
      (tester) async {
        var calls = 0;
        when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
          calls++;
          if (calls == 1) throw const BulkSetupBusyFailure();
          return const <MasterService>[];
        });

        await pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await expand(tester, 'MANICURE');
        await toggleRowOn(tester, 'type-classic');
        await fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.serviceSetupRetry), findsOneWidget);

        // The retry succeeds: the single-slot VelvetSnack host pre-empts the
        // still-showing retry snack with an UNTRACKED success snack (never
        // routed through `_retrySnack`), and the screen leaves. The old
        // retry snack's underlying state retires as part of that
        // pre-emption, so `_retrySnack` — still holding THAT handle, since
        // the success path never touches the field — is stale by the time
        // dispose runs.
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(calls, 2);
        expect(tester.takeException(), isNull);
        expect(
          find.byType(ServiceSetupScreen),
          findsNothing,
          reason:
              'precondition: success replaces the setup route with the list',
        );
        expect(
          find.text(l10n.serviceSetupSuccess),
          findsOneWidget,
          reason:
              'the success snack is deliberately NOT tracked, so dispose '
              '(dismissing only the stale `_retrySnack` handle, a safe no-op '
              'here) must leave it alone — the master reads the confirmation '
              'on the list screen they were just returned to',
        );
        await pumpPastVelvetSnack(tester);
      },
    );
  });
}
