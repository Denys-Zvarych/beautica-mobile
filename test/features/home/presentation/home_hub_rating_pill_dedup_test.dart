// Phase 13.7 — HomeHub provider de-dup REGRESSION/BEHAVIOUR guard.
//
// Refactor under test (home_hub_screen.dart):
//   • `_HomeHubBody` no longer watches `clientProfileProvider` at all.
//   • `_ProfileSection` (leaf) watches the FULL clientProfileProvider for the
//     name / city / phone card.
//   • `_StatPillsRow` (leaf) watches a NARROW `.select` slice —
//     `clientProfileProvider.select((v) => v.whenData((p) => p.clientRating))` —
//     so the rating pill rebuilds only when the rating itself changes, not on a
//     name / photo / city edit.
//
// These tests pin the BEHAVIOUR the de-dup must preserve: the rating pill still
// renders the correct rating sourced from clientProfileProvider, and the
// data / loading / error states of that provider still render the expected
// leaf UI (no blank screen, no swapped state). They are the behaviour-
// preservation net for the `.select` narrowing — they would go red if the slice
// were wired to the wrong field or the leaf state mapping regressed.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// No-op ScreenProtectionManager (the home hub acquires it in initState).
// ---------------------------------------------------------------------------

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

// ---------------------------------------------------------------------------
// Sample data — a profile WITH a concrete rating so the pill value is unique.
// ---------------------------------------------------------------------------

const _ratedProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: 4.7,
  memberSinceYear: 2026,
);

/// Builds the override list for the home hub, parameterised by the
/// clientProfileProvider override only — the other section providers are always
/// settled to empty data so they cannot interfere with the rating-pill / profile
/// assertions. `profileOverride` is the raw provider override (so callers can
/// inject data / loading / error precisely).
List<Object> _overrides(Object profileOverride) {
  return <Object>[
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    profileOverride,
    nextAppointmentProvider.overrideWith((ref) async => null),
    favoriteMastersProvider.overrideWith(
      (ref) async => const <FavoriteMasterItem>[],
    ),
    beautyTimelineProvider.overrideWith((ref) async => const <TimelineEntry>[]),
    unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
  ];
}

void main() {
  group('HomeHub rating-pill de-dup (clientProfileProvider .select slice)', () {
    testWidgets('data state: rating pill renders the rating sourced from '
        'clientProfileProvider (and profile card still renders the name)', (
      tester,
    ) async {
      await tester.pumpApp(
        const HomeHubScreen(),
        overrides: _overrides(
          clientProfileProvider.overrideWith((ref) async => _ratedProfile),
        ),
      );
      // Settle the provider future, then run out the 1100 ms reveal.
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1100));

      // The rating pill (leaf .select consumer) shows the rating value.
      expect(find.byType(MyRatingStatCard), findsOneWidget);
      expect(
        find.text('4.7'),
        findsOneWidget,
        reason:
            'the rating pill must render clientRating from the '
            'clientProfileProvider.select((p) => p.clientRating) slice',
      );

      // The profile leaf (full-provider consumer) still renders the name —
      // proves the de-dup did not break the sibling profile card.
      expect(
        find.byKey(const Key('home_profile_name')),
        findsOneWidget,
        reason:
            'the profile card leaf must still render from the full '
            'clientProfileProvider after the body stopped watching it',
      );
      expect(find.text('Олена Тест'), findsOneWidget);
    });

    testWidgets(
      'loading state: rating pill shows the skeleton (no MyRatingStatCard) '
      'while clientProfileProvider is loading',
      (tester) async {
        // A never-completing future keeps the provider in AsyncLoading.
        final completer = Completer<ClientProfileSummary>();
        addTearDown(() {
          if (!completer.isCompleted) completer.complete(_ratedProfile);
        });

        await tester.pumpApp(
          const HomeHubScreen(),
          overrides: _overrides(
            clientProfileProvider.overrideWith((ref) => completer.future),
          ),
        );
        // Run the reveal animation only; the profile future stays pending so
        // we deliberately do NOT pumpAndSettle (it would hang).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1100));

        // The rating slice is AsyncLoading → the pill renders its skeleton, so
        // the data widget must be ABSENT.
        expect(
          find.byType(MyRatingStatCard),
          findsNothing,
          reason:
              'while clientProfileProvider is loading the rating pill must '
              'render the skeleton, not the MyRatingStatCard data widget',
        );
        // The profile leaf is also loading → its name is not shown.
        expect(find.byKey(const Key('home_profile_name')), findsNothing);
      },
    );

    testWidgets(
      'error state: failing clientProfileProvider renders the rating pill as '
      'a graceful "—" (MyRatingStatCard, clientRating: null) without blanking '
      'siblings or escaping an exception',
      (tester) async {
        // The rating slice now PRESERVES the error state:
        //   clientProfileProvider.select((v) => v.map(data/error/loading))
        // — a production fix replaced the old `.whenData(...)` (which collapsed
        // error→loading, leaving the `error:` branch dead code / a perpetual
        // skeleton). With `.map`, an AsyncError in the source flows through to
        // the pill's `error:` branch, which renders
        // `MyRatingStatCard(clientRating: null)` → a graceful "—".
        //
        // To assert that settled-error render DETERMINISTICALLY we (a) throw
        // SYNCHRONOUSLY in the override so the FutureProvider resolves to
        // AsyncError on its very first build with no intervening AsyncLoading
        // frame, and (b) DISABLE Riverpod 3.x's auto-retry via the ProviderScope
        // `retry: (_, _) => null` knob so the error stays put and leaves no
        // pending backoff Timer (which would otherwise make pumpAndSettle hang /
        // fail the test on a dangling timer). Production keeps the default retry.
        await tester.pumpApp(
          const HomeHubScreen(),
          retry: (_, _) => null,
          overrides: _overrides(
            clientProfileProvider.overrideWith(
              (ref) => throw Exception('profile boom'),
            ),
          ),
        );
        // Error is settled synchronously; settle the reveal animation, then run
        // out the 1100 ms reveal exactly like the data case.
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 1100));

        // The rating pill now renders the DATA widget in its graceful empty
        // form — MyRatingStatCard with a null rating, not a perpetual skeleton.
        final ratingFinder = find.byType(MyRatingStatCard);
        expect(
          ratingFinder,
          findsOneWidget,
          reason:
              'a clientProfileProvider error must flow through the .select(map) '
              'rating slice to the pill error branch → '
              'MyRatingStatCard(clientRating: null), NOT a perpetual skeleton',
        );
        expect(
          tester.widget<MyRatingStatCard>(ratingFinder).clientRating,
          isNull,
          reason:
              'the error branch must pass clientRating: null so the pill '
              'degrades gracefully',
        );
        // null clientRating renders the "—" placeholder glyph. (Finding this is
        // also implicit proof the loading skeleton was replaced: the data widget
        // and the skeleton are mutually exclusive branches of the same `when`.)
        expect(
          find.text('—'),
          findsOneWidget,
          reason: 'a null rating renders the "—" graceful-empty value',
        );

        // One failing provider must not blank the whole screen — a sibling
        // card (next appointment empty state) still renders. This is the
        // independent-card invariant the de-dup must preserve: each section is
        // built from its own AsyncValue.
        expect(
          find.byKey(const Key('next_appointment_empty')),
          findsOneWidget,
          reason: 'a clientProfileProvider error must not blank sibling cards',
        );

        // The screen handles the failing provider gracefully — no exception
        // bubbles out of any builder.
        expect(tester.takeException(), isNull);
      },
    );
  });
}
