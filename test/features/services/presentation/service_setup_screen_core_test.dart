// [ServiceSetupScreen] widget tests:
// catalogue states, expansion, footer CTA, save.
//
// Split by phase from the former `service_setup_screen_test.dart`; the
// shared fixtures and helpers live in `service_setup_test_harness.dart`.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
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

  // ── Log-safe error summary ─────────────────────────────────────────────────

  group('error summary (log-safe)', () {
    test('a server failure logs type + status code, never its cause', () {
      final summary = debugServiceSetupErrorSummary(
        const ServerFailure(statusCode: 409, cause: 'GET /secret/url?token=x'),
      );
      expect(summary, 'ServerFailure(409)');
      expect(summary, isNot(contains('secret')));
    });

    test('a server failure without a status code logs null', () {
      expect(
        debugServiceSetupErrorSummary(const ServerFailure()),
        'ServerFailure(null)',
      );
    });

    test('any other error logs only its runtime type', () {
      expect(
        debugServiceSetupErrorSummary(StateError('leaky /path message')),
        'StateError',
      );
    });
  });

  // ── Catalogue states ───────────────────────────────────────────────────────

  group('catalogue states', () {
    testWidgets('loading — shows a progress indicator', (tester) async {
      await pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncLoading<List<ServiceCategoryOption>>(),
        ),
      );
      await tester.pump(); // one frame; provider future never completes

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error — shows ErrorState; retry re-reads categories', (
      tester,
    ) async {
      await pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncError<List<ServiceCategoryOption>>(
            NetworkFailure(),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('service_setup_error_state')),
        findsOneWidget,
      );
      expect(find.byType(ErrorState), findsOneWidget);

      // The retry affordance must exist and be tappable without throwing.
      final retry = find.descendant(
        of: find.byType(ErrorState),
        matching: find.byType(GestureDetector),
      );
      expect(retry, findsWidgets);
    });

    testWidgets('data — renders a chip per category by key', (tester) async {
      await pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure, hair]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('cat_MANICURE')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('cat_HAIR')), findsOneWidget);
    });
  });

  // ── Expansion + rows ─────────────────────────────────────────────────────────

  // ── Category-icon wiring (mobile-qa gap-closure, 2026-08-27) ────────────────
  //
  // service_setup_widgets_test.dart proves CategoryChip/CategoryGroupHeader
  // render whatever iconAsset they are handed. It hand-feeds that value, so it
  // cannot catch a wiring regression at the CALL SITE (e.g. this screen
  // swapping `categoryIconOrNullFor` for the never-null `categoryIconFor`, or
  // passing the wrong category's slug/name). These tests drive the resolver
  // through the real screen + real ServiceCategoryOption fixtures instead.
  group('category-icon wiring (resolver reached through the real screen)', () {
    testWidgets(
      'chip renders the resolver-mapped asset for its own category, not a '
      'sibling\'s',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[
              manicure,
              hair,
            ]),
          ),
        );
        await tester.pumpAndSettle();

        final AppIcon manicureIcon = tester.widget<AppIcon>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('cat_MANICURE')),
            matching: find.byType(AppIcon),
          ),
        );
        expect(
          manicureIcon.asset,
          equals(BeauticaAssetIcons.categoryNailService),
        );

        final AppIcon hairIcon = tester.widget<AppIcon>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('cat_HAIR')),
            matching: find.byType(AppIcon),
          ),
        );
        expect(hairIcon.asset, equals(BeauticaAssetIcons.categoryHairdressing));
        expect(hairIcon.asset, isNot(equals(manicureIcon.asset)));
      },
    );

    testWidgets(
      'expanded group header renders the SAME resolved asset as its chip',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final AppIcon headerIcon = tester.widget<AppIcon>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('group_MANICURE')),
            matching: find.byType(AppIcon),
          ),
        );
        expect(
          headerIcon.asset,
          equals(BeauticaAssetIcons.categoryNailService),
        );
      },
    );

    testWidgets(
      'a blank-slug/blank-name category renders NO icon on its CHIP through '
      'the screen (proves categoryIconOrNullFor, not categoryIconFor, is '
      'wired at the chip call site)',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[blank]),
          ),
        );
        await tester.pumpAndSettle();

        final chip = find.byKey(const ValueKey<String>('cat_'));
        expect(chip, findsOneWidget);
        expect(
          find.descendant(of: chip, matching: find.byType(AppIcon)),
          findsNothing,
          reason:
              'categoryIconFor() never returns null (it falls back to the '
              'cosmetology asset) — an AppIcon here means the call site '
              'regressed off categoryIconOrNullFor',
        );
      },
    );

    testWidgets(
      'a blank-slug/blank-name category renders NO icon on its EXPANDED '
      'GROUP HEADER either (proves categoryIconOrNullFor is wired at the '
      '_expandedSlots call site too — a separate call site from the chip '
      'above, and the one an isolated chip-only assertion would miss)',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[blank]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              '': const <ServiceTypeOption>[],
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('cat_')));
        await tester.pumpAndSettle();

        final header = find.byKey(const ValueKey<String>('group_'));
        expect(header, findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.byType(AppIcon)),
          findsNothing,
          reason:
              'categoryIconFor() never returns null — an AppIcon on a blank '
              'category\'s group header means _expandedSlots regressed off '
              'categoryIconOrNullFor',
        );
      },
    );
  });

  group('category expansion', () {
    testWidgets('selecting a category expands it and shows service-type rows', (
      tester,
    ) async {
      await pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('group_MANICURE')),
        findsOneWidget,
      );
      // The first row is on-screen; the second lives below the fold in the
      // lazy SliverList, so scroll it into view before asserting.
      expect(find.byKey(const Key('setup_row_type-classic')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('setup_row_type-gel')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('setup_row_type-gel')), findsOneWidget);
    });
  });

  // ── Footer count + CTA enable/disable ──────────────────────────────────────

  group('footer CTA', () {
    testWidgets('disabled (onPressed null) when nothing is included', (
      tester,
    ) async {
      await pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[manicure]),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      // No selection → footer shows the empty CTA copy.
      expect(find.text(l10n.serviceSetupCtaEmpty), findsOneWidget);
    });

    testWidgets(
      'expanding a category (opt-in: rows default OFF) keeps the count at zero '
      'and the CTA disabled; toggling rows ON raises the count',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic, typeGel],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Opt-in model: just revealing the rows includes NOTHING → the footer
        // still shows the empty CTA copy and the save callback is null.
        expect(find.text(l10n.serviceSetupCtaEmpty), findsOneWidget);
        expect(find.text(l10n.serviceSetupCtaCreate(2)), findsNothing);
        expect(saveOnPressed(tester), isNull);

        // Toggle the first row ON — count rises to 1, CTA becomes enabled.
        await toggleRowOn(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
        expect(saveOnPressed(tester), isNotNull);

        // Toggle the second row ON (scroll it into view first) — count rises
        // to 2.
        await tester.scrollUntilVisible(
          find.byKey(const Key('setup_row_type-gel')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await toggleRowOn(tester, 'type-gel');
        expect(find.text(l10n.serviceSetupCtaCreate(2)), findsOneWidget);
      },
    );
  });

  // ── Save path ────────────────────────────────────────────────────────────────

  group('save', () {
    testWidgets(
      'tapping save with a valid included row calls bulkCreate and navigates '
      'to the services list',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => createdService);

        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        // Opt-in: include the row FIRST, else it is excluded and the save is a
        // no-op (CTA disabled) — bulkCreate would never be called.
        await toggleRowOn(tester, 'type-classic');

        // Fill the duration (the row's leading VelvetField — the first
        // TextField in the card) and the fixed price (keyed field).
        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-classic')),
                matching: find.byType(TextField),
              )
              .first,
          '60',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-fixed-amount')),
          '500',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(h.pushedRoutes, contains(RouteNames.services));
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'invalid range (max <= min) flags the row and blocks save — bulkCreate '
      'never called',
      (tester) async {
        await pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Opt-in: include the row first so it participates in validation.
        await toggleRowOn(tester, 'type-classic');

        // Switch the row to RANGE mode and enter an invalid range.
        await tester.tap(find.byKey(const Key('pricing-toggle-range')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-classic')),
                matching: find.byType(TextField),
              )
              .first,
          '60',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-range-min')),
          '500',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-range-max')),
          '300', // max <= min → invalid
        );
        await tester.pumpAndSettle();

        // The cross-field range error line appears (only on invalid range).
        expect(find.text(l10n.pricingRangeHint), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );
  });
}
