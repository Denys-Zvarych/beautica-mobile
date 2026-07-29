// HomeHub rating-pill SOURCE + de-coupling REGRESSION/BEHAVIOUR guard.
//
// Wiring under test (home_hub_screen.dart):
//   • `_ProfileSection` (leaf) watches the FULL clientProfileProvider for the
//     name / city / phone card.
//   • `_StatPillsRow` (leaf) watches the AUTHORITATIVE `myRatingProvider`
//     (`GET /users/me/rating`) — the SAME source `MyRatingScreen` (the detail
//     window opened by tapping the pill) reads. It no longer reads the profile
//     summary's `clientRating` slice, which was unpopulated and rendered "—".
//
// These tests pin the behaviour the wiring must preserve:
//   1. The pill renders the real rating from `myRatingProvider` — EVEN WHEN the
//      profile summary's `clientRating` is null (proves the source switch: the
//      pill and `MyRatingScreen` now agree on the real number).
//   2. The pill is de-coupled from profile edits — a loading RATING shows the
//      skeleton while the sibling profile card still renders its name.
//   3. A failing `myRatingProvider` degrades to a graceful "—"
//      (`MyRatingStatCard`, clientRating: null), without blanking siblings or
//      escaping an exception.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/home/presentation/widgets/passport_preview_card.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
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
// Sample data — a profile whose OWN `clientRating` slice is null. The pill must
// still show a real number, proving it reads `myRatingProvider`, not this field.
// ---------------------------------------------------------------------------

const _profileNoRating = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2026,
);

/// Builds the override list for the home hub, parameterised by the
/// `myRatingProvider` override only — the profile is always settled to
/// [_profileNoRating] and the other section providers to empty data, so they
/// cannot interfere with the rating-pill / profile assertions. `ratingOverride`
/// is the raw provider override (so callers can inject data / loading / error
/// precisely).
List<Object> _overrides(Object ratingOverride) {
  return <Object>[
    screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
    ratingOverride,
    clientProfileProvider.overrideWith((ref) async => _profileNoRating),
    nextAppointmentProvider.overrideWith((ref) async => null),
    favoriteMastersProvider.overrideWith(
      (ref) async => const <FavoriteMasterItem>[],
    ),
    beautyTimelineProvider.overrideWith((ref) async => const <TimelineEntry>[]),
    unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
  ];
}

void main() {
  group('HomeHub rating pill — sourced from myRatingProvider', () {
    testWidgets(
      'data state: rating pill renders the real rating from myRatingProvider '
      'even when the profile summary clientRating is null',
      (tester) async {
        await tester.pumpApp(
          const HomeHubScreen(),
          overrides: _overrides(
            myRatingProvider.overrideWith(
              (ref) async =>
                  const ClientRating(avgRating: 4.7, reviewCount: 12),
            ),
          ),
        );
        // Settle the providers, then run out the 1100 ms reveal.
        await tester.pumpAndSettle();
        // fixed-wait-ok: running out a time-driven CurvedAnimation — no condition to pump-until.
        await tester.pump(const Duration(milliseconds: 1100));

        expect(find.byType(MyRatingStatCard), findsOneWidget);
        expect(
          find.text('4.7'),
          findsOneWidget,
          reason:
              'the pill must render avgRating from myRatingProvider — the same '
              'authoritative source MyRatingScreen reads — NOT the profile '
              'summary clientRating slice (which is null here)',
        );
        expect(
          tester
              .widget<MyRatingStatCard>(find.byType(MyRatingStatCard))
              .clientRating,
          4.7,
          reason:
              'the pill value must come straight from ClientRating.avgRating',
        );

        // The profile leaf still renders the name from clientProfileProvider —
        // proves the rating source switch did not touch the sibling card.
        expect(find.byKey(const Key('home_profile_name')), findsOneWidget);
        // i18n-finder-ok: client display name is fixture data, not UI copy
        expect(find.text('Олена Тест'), findsOneWidget);
      },
    );

    testWidgets(
      'de-coupling: a loading rating shows the skeleton while the sibling '
      'profile card still renders its name',
      (tester) async {
        // A never-completing future keeps myRatingProvider in AsyncLoading.
        final completer = Completer<ClientRating>();
        addTearDown(() {
          if (!completer.isCompleted) completer.complete(const ClientRating());
        });

        await tester.pumpApp(
          const HomeHubScreen(),
          overrides: _overrides(
            myRatingProvider.overrideWith((ref) => completer.future),
          ),
        );
        // The profile future settles; the rating future stays pending, so we
        // deliberately do NOT pumpAndSettle (it would hang on the completer).
        await tester.pump();
        // fixed-wait-ok: running out a time-driven CurvedAnimation — no condition to pump-until.
        await tester.pump(const Duration(milliseconds: 1100));

        // Rating is AsyncLoading → the pill renders its skeleton, so the data
        // widget must be ABSENT.
        expect(
          find.byType(MyRatingStatCard),
          findsNothing,
          reason:
              'while myRatingProvider is loading the pill must render the '
              'skeleton, not the MyRatingStatCard data widget',
        );
        // The profile card is settled and independent of the rating — its name
        // still renders, proving the pill no longer couples the two.
        expect(
          find.byKey(const Key('home_profile_name')),
          findsOneWidget,
          reason:
              'a loading RATING must not blank the profile card — the rating '
              'pill is de-coupled from clientProfileProvider',
        );
      },
    );

    testWidgets(
      'error state: a failing myRatingProvider renders the pill as a graceful '
      '"—" (MyRatingStatCard, clientRating: null) without blanking siblings or '
      'escaping an exception',
      (tester) async {
        // Throw SYNCHRONOUSLY so the provider resolves to AsyncError on its
        // first build (no intervening AsyncLoading frame), and DISABLE Riverpod
        // 3.x auto-retry via `retry: (_, _) => null` so the error stays put and
        // leaves no pending backoff Timer (which would hang pumpAndSettle).
        await tester.pumpApp(
          const HomeHubScreen(),
          retry: (_, _) => null,
          overrides: _overrides(
            myRatingProvider.overrideWith(
              (ref) => throw Exception('rating boom'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // fixed-wait-ok: running out a time-driven CurvedAnimation — no condition to pump-until.
        await tester.pump(const Duration(milliseconds: 1100));

        // The pill renders the DATA widget in its graceful empty form —
        // MyRatingStatCard with a null rating, not a perpetual skeleton.
        final ratingFinder = find.byType(MyRatingStatCard);
        expect(
          ratingFinder,
          findsOneWidget,
          reason:
              'a myRatingProvider error must flow to the pill error branch → '
              'MyRatingStatCard(clientRating: null), NOT a perpetual skeleton',
        );
        expect(
          tester.widget<MyRatingStatCard>(ratingFinder).clientRating,
          isNull,
          reason:
              'the error branch must pass clientRating: null so the pill '
              'degrades gracefully',
        );
        expect(
          find.text('—'),
          findsOneWidget,
          reason: 'a null rating renders the "—" graceful-empty value',
        );

        // One failing provider must not blank the whole screen — a sibling card
        // (next appointment empty state) still renders.
        expect(
          find.byKey(const Key('next_appointment_empty')),
          findsOneWidget,
          reason: 'a myRatingProvider error must not blank sibling cards',
        );

        // No exception bubbles out of any builder.
        expect(tester.takeException(), isNull);
      },
    );
  });
}
