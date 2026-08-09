// Phase 13.8 wire-up — TIER 2 chain tests: ClientControllerApi → repository →
// mapper → passportProvider → PassportScreen.
//
// WHY THIS FILE EXISTS — READ BEFORE WEAKENING ANY OVERRIDE HERE
// --------------------------------------------------------------
// The Beauty Passport shipped showing the empty state to EVERY user, forever:
// `passportRepositoryProvider` bound a `PlaceholderPassportRepository` whose
// `getMyPassport()` returned `Passport.empty()` and never called the endpoint,
// which had been live since backend 19.5 and was already in the generated Dio
// client. 62 green widget tests and a green E2E missed it for one reason:
// EVERY widget test overrode `passportProvider` DIRECTLY — above the
// repository — so the repository→mapper→provider chain had zero coverage. The
// suite was asserting its own fixtures.
//
// This file closes that hole by overriding at the BOTTOM of the chain
// (`clientApiProvider`, the generated API) and letting everything above it run
// for real. Overriding `passportProvider` — or `passportRepositoryProvider`
// with a fake — in any test here would reopen the exact blind spot: the tests
// would pass again against a placeholder that calls nothing.
//
// RETRY: `beauticaProviderRetry` (the pumpApp/production default) classifies a
// 5xx `ServerFailure` as TRANSIENT, so an element parks in
// `AsyncLoading(retrying: true)` — which still reports `hasError == true` —
// through `pumpAndSettle` and never reaches `AsyncError`. Every error-path case
// below therefore disables retry explicitly and asserts the runtime type
// `AsyncError`, not merely `hasError`.

import 'dart:async';

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_client_provider.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/data/passport_repository.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_derived_block.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_identity_strip.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/pump_app.dart';

class _MockClientControllerApi extends Mock
    implements api.ClientControllerApi {}

const String _path = '/api/v1/clients/me/passport';

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

/// Derived values carried by [_populatedEnvelope] and asserted as rendered
/// chips. Declared ONCE so the fixture and its assertions cannot drift, and so
/// the finders read the payload instead of re-typing it — these are BACKEND
/// DATA, never AppLocalizations copy, so they survive the EN locale landing.
const List<String> _wireDistricts = <String>['Центр', 'Сихів', 'Франківський'];
const int _wireBudgetAvg = 600;
const List<String> _wireCities = <String>['Львів', 'Київ'];
const int _wireReviewsWritten = 3;

/// Deliberately not the current year — a re-derived-from-the-clock join year
/// could not produce it.
const int _wireMemberSinceYear = 2021;

/// A populated wire envelope. Every value differs from the empty passport AND
/// from the other values in the fixture, so no assertion can be satisfied by a
/// stale/blank/default reading (a `bookingsConsidered` of 0 or an empty chip
/// list is exactly what the shipped bug produced).
Response<api.ApiResponsePassportResponse> _populatedEnvelope() =>
    Response<api.ApiResponsePassportResponse>(
      requestOptions: RequestOptions(path: _path),
      statusCode: 200,
      data: api.ApiResponsePassportResponse(
        (b) => b
          ..success = true
          ..data.favoriteDistricts.replace(_wireDistricts)
          ..data.favoriteCities.replace(_wireCities)
          ..data.bookingsConsidered = 7
          ..data.reviewsWritten = _wireReviewsWritten
          ..data.memberSinceYear = _wireMemberSinceYear
          ..data.budget.avg = _wireBudgetAvg
          ..data.budget.min = 400
          ..data.budget.max = 800
          ..data.budget.currency = 'UAH',
      ),
    );

Response<api.ApiResponsePassportResponse> _emptyEnvelope() =>
    Response<api.ApiResponsePassportResponse>(
      requestOptions: RequestOptions(path: _path),
      statusCode: 200,
      data: api.ApiResponsePassportResponse(
        (b) => b
          ..success = true
          ..data.favoriteDistricts.replace(const <String>[])
          ..data.favoriteCities.replace(const <String>[])
          ..data.bookingsConsidered = 0
          ..data.reviewsWritten = 0
          ..data.memberSinceYear = _wireMemberSinceYear,
      ),
    );

DioException _serverError() => DioException(
  requestOptions: RequestOptions(path: _path),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: _path),
    statusCode: 500,
  ),
);

/// Overrides ONLY the generated API — the repository, mapper and provider above
/// it all run for real. This is the whole point of the file.
List<Object> _chainOverrides(api.ClientControllerApi mock) => <Object>[
  clientApiProvider.overrideWithValue(mock),
];

List<Object> _screenOverrides(api.ClientControllerApi mock) => <Object>[
  screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
  clientProfileProvider.overrideWith((ref) async => _sampleProfile),
  clientApiProvider.overrideWithValue(mock),
  // Phase 238: the page's fourth block (`WishlistSection`) watches
  // `wishlistProvider`. Silenced with a fake repository so it neither attempts a
  // real call nor paints its own failure card over the assertions below.
  //
  // THIS IS NOT A RELAXATION OF THE FILE'S RULE. The ban is on stubbing the
  // PASSPORT chain — `passportProvider` or `passportRepositoryProvider` — which
  // is the chain under test. The wish list is an unrelated feature that merely
  // shares the page; leaving it live would add noise, not coverage. Its own
  // chain is covered by the wish-list suite.
  wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
  // NOTE the absence of a `passportProvider` override. Adding one back would
  // sever the chain under test — see the file header.
];

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

void main() {
  late _MockClientControllerApi clientApi;

  setUp(() {
    clientApi = _MockClientControllerApi();
  });

  group('passportRepositoryProvider — binding', () {
    // STRUCTURAL GUARD. The shipped bug was a one-line binding to a repository
    // that called nothing. This pins the binding itself, so re-introducing any
    // non-HTTP stand-in fails immediately and by name rather than surfacing as
    // "the screen is empty for everyone" three phases later.
    test('binds the live HttpPassportRepository, never a placeholder', () {
      final container = ProviderContainer(
        overrides: _chainOverrides(clientApi).cast(),
      );
      addTearDown(container.dispose);

      expect(
        container.read(passportRepositoryProvider),
        isA<HttpPassportRepository>(),
      );
    });
  });

  group('passportProvider — full chain off the generated API', () {
    // THE TEST THAT WOULD HAVE CAUGHT THE SHIPPED BUG.
    //
    // Under the placeholder binding this fails on the very first assertion:
    // `bookingsConsidered` reads 0, both chip lists read empty and `budget`
    // reads null, because the wire payload was never consulted. Confirmed RED
    // by temporarily re-adding a `passportRepositoryProvider` override that
    // returns an empty passport — all six expectations below fail and the
    // `verify` reports 0 calls.
    test('a populated response reaches the domain model intact', () async {
      when(
        () => clientApi.getPassport(),
      ).thenAnswer((_) async => _populatedEnvelope());

      final container = ProviderContainer(
        overrides: _chainOverrides(clientApi).cast(),
      );
      addTearDown(container.dispose);

      final Passport p = await container.read(passportProvider.future);

      verify(() => clientApi.getPassport()).called(1);
      expect(p.favoriteDistricts, _wireDistricts);
      expect(p.favoriteCities, _wireCities);
      expect(p.bookingsConsidered, 7);
      expect(p.reviewsWritten, _wireReviewsWritten);
      expect(p.memberSinceYear, _wireMemberSinceYear);
      expect(p.budget!.avg, _wireBudgetAvg.toDouble());
      expect(p.budget!.max, 800.0);
      expect(
        p.isEmpty,
        isFalse,
        reason:
            'the provider must surface the real payload — an always-empty '
            'passport is the exact defect this chain test exists to catch',
      );
      expect(p, isNot(Passport.empty(memberSinceYear: _wireMemberSinceYear)));
    });

    test('an empty response still resolves to the empty passport', () async {
      when(
        () => clientApi.getPassport(),
      ).thenAnswer((_) async => _emptyEnvelope());

      final container = ProviderContainer(
        overrides: _chainOverrides(clientApi).cast(),
      );
      addTearDown(container.dispose);

      final Passport p = await container.read(passportProvider.future);

      verify(() => clientApi.getPassport()).called(1);
      expect(p, Passport.empty(memberSinceYear: _wireMemberSinceYear));
    });

    test(
      'a transport failure surfaces as a terminal AsyncError<Passport>',
      () async {
        when(
          () => clientApi.getPassport(),
        ).thenAnswer((_) async => throw _serverError());

        final container = ProviderContainer(
          overrides: _chainOverrides(clientApi).cast(),
          // Retry OFF. With any retry policy the element parks in
          // `AsyncLoading(retrying: true)` — which reports `hasError == true`
          // while NOT being an `AsyncError` — so a hasError-only assertion here
          // could never fail. See the file header.
          retry: (_, _) => null,
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(passportProvider.future),
          throwsA(isA<ServerFailure>()),
        );

        final AsyncValue<Passport> state = container.read(passportProvider);
        // Runtime type, not `hasError` — the mid-retry loading shape satisfies
        // `hasError` and would make this assertion unfailable.
        expect(state, isA<AsyncError<Passport>>());
        expect(state.error, isA<ServerFailure>());
        expect(
          state.value,
          isNull,
          reason:
              'a failed fetch must NOT resolve to an empty passport — that '
              'collapse is what made the broken data layer invisible',
        );
      },
    );
  });

  group('PassportScreen — rendered off the real chain (no provider stub)', () {
    // THE SCREEN-LEVEL TWIN of the chain test. Every widget test in
    // passport_screen_test.dart overrides `passportProvider` directly and
    // therefore renders its own fixture; this one renders whatever the WIRE
    // says, through the real repository and mapper.
    //
    // Confirmed RED against the shipped behaviour: with the repository swapped
    // back to an empty-passport stand-in, the derived block is absent and every
    // locality finder reports findsNothing, exactly as in production.
    //
    // PHASE 238 RE-POINT. `PassportCard` (passport_table.dart) was deleted with
    // its whole file, so "did the payload reach the screen" is now asserted
    // against its two replacements: [PassportIdentityStrip] (the client's
    // standing) and [PassportDerivedBlock] (localities + average spend). The
    // `passport_find_master_button` empty hero went with it, so the empty case
    // below asserts what the page ACTUALLY renders for a history-less client —
    // the strip alone, with the derived block dropped.
    testWidgets(
      'a populated payload reaches the identity strip AND the derived block',
      (tester) async {
        when(
          () => clientApi.getPassport(),
        ).thenAnswer((_) async => _populatedEnvelope());

        await tester.pumpApp(
          const PassportScreen(),
          overrides: _screenOverrides(clientApi),
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();

        expect(
          find.byKey(const Key('passport_identity_strip')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('passport_derived_block')), findsOneWidget);
        expect(find.byType(PassportIdentityStrip), findsOneWidget);
        expect(find.byType(PassportDerivedBlock), findsOneWidget);

        // Derived values from the WIRE payload — each one impossible to render
        // from the empty passport. Asserted against the SAME constants the mock
        // served, so fixture and expectation cannot drift.
        //
        // SCOPED to the derived block, not page-wide: the profile block above
        // renders the client's own city, which can legitimately coincide with a
        // derived favourite city. A page-wide finder would then report two
        // matches and fail for a reason that has nothing to do with the chain.
        for (final String locality in <String>[
          ..._wireDistricts,
          ..._wireCities,
        ]) {
          expect(
            find.descendant(
              of: find.byKey(const Key('passport_derived_block')),
              // i18n-finder-ok: values come from the mocked envelope, never
              // AppLocalizations.
              matching: find.text(locality),
            ),
            findsOneWidget,
            reason:
                'derived locality "$locality" from the wire payload must render',
          );
        }
        expect(
          find.text(l10n.passportBudgetAverage(_wireBudgetAvg)),
          findsOneWidget,
        );
        // The standing line and the join YEAR, both straight off the wire.
        expect(
          find.text(l10n.passportReviewsLeft(_wireReviewsWritten)),
          findsOneWidget,
        );
        expect(
          find.text(l10n.passportMemberSince('$_wireMemberSinceYear')),
          findsOneWidget,
        );

        expect(find.byKey(const Key('passport_error_state')), findsNothing);
        expect(find.byKey(const Key('passport_skeleton')), findsNothing);
        verify(() => clientApi.getPassport()).called(1);
      },
    );

    testWidgets(
      'an EMPTY payload renders the strip alone, derived block dropped',
      (tester) async {
        // The counterpart: proves the no-derived-data rendering is EARNED from
        // the wire (empty lists, null budget) rather than hardcoded. A suite
        // that only asserted the populated case could be satisfied by a mapper
        // that never produces an empty passport at all.
        when(
          () => clientApi.getPassport(),
        ).thenAnswer((_) async => _emptyEnvelope());

        await tester.pumpApp(
          const PassportScreen(),
          overrides: _screenOverrides(clientApi),
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();

        // The strip STAYS — it is what makes a history-less passport meaningful
        // and is why Phase 238 could delete the empty hero outright.
        expect(
          find.byKey(const Key('passport_identity_strip')),
          findsOneWidget,
        );
        expect(find.text(l10n.passportReviewsLeft(0)), findsOneWidget);
        expect(
          find.text(l10n.passportMemberSince('$_wireMemberSinceYear')),
          findsOneWidget,
          reason:
              'the join year is a WIRE value even for an empty passport — a '
              'screen re-deriving it from the clock would print the current '
              'year here',
        );

        expect(
          find.byKey(const Key('passport_derived_block')),
          findsNothing,
          reason:
              'nothing derivable ⇒ the caller drops the whole block rather '
              'than rendering an empty card',
        );
        expect(find.byKey(const Key('passport_error_state')), findsNothing);
        verify(() => clientApi.getPassport()).called(1);
      },
    );

    testWidgets(
      'a 500 renders the ERROR card off the real chain, never a no-data page',
      (tester) async {
        // The end-to-end version of the error split: the failure originates at
        // the TRANSPORT (a Dio 500), travels through the repository's typed
        // mapping and the provider, and must land on the error card. The widget
        // test injects the failure at `passportProvider`, so it cannot prove the
        // repository maps transport errors at all.
        when(
          () => clientApi.getPassport(),
        ).thenAnswer((_) async => throw _serverError());

        await tester.pumpApp(
          const PassportScreen(),
          overrides: _screenOverrides(clientApi),
          // Retry OFF — see the file header: a 5xx is classified transient, so
          // the default policy would keep the element in AsyncLoading(retrying)
          // through pumpAndSettle and this test would assert a skeleton forever.
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();

        expect(find.byKey(const Key('passport_error_state')), findsOneWidget);
        expect(find.text(l10n.passportErrorTitle), findsOneWidget);
        expect(find.byKey(const Key('passport_retry_button')), findsOneWidget);

        // A transport failure must be visually distinct from "no history yet"
        // ALL THE WAY from Dio to the rendered card. With the empty hero gone,
        // that means the strip must be absent too: a strip full of zeroes is
        // precisely the "new client" rendering an error must never collapse to.
        expect(
          find.byKey(const Key('passport_identity_strip')),
          findsNothing,
          reason:
              'an errored passport must not render the standing strip — a '
              'zero-filled strip reads as a brand-new client',
        );
        expect(find.byKey(const Key('passport_derived_block')), findsNothing);
      },
    );

    testWidgets(
      'a refresh over a GOOD passport keeps the strip, never flashes a skeleton',
      (tester) async {
        // Pins the seamless-reload branch (`isLoading` with a RETAINED value).
        // `ref.invalidate` keeps the previous value, so a refresh over an
        // already-rendered passport must keep painting it; a naive `.when()`
        // would collapse to the skeleton and make every background refresh look
        // like a cold load. Untestable from a stubbed `passportProvider` — the
        // retained-value shape only arises when a real async fetch is in
        // flight, which is why it lives in this file.
        final Completer<Response<api.ApiResponsePassportResponse>> second =
            Completer<Response<api.ApiResponsePassportResponse>>();
        var call = 0;
        when(() => clientApi.getPassport()).thenAnswer((_) async {
          call++;
          if (call == 1) return _populatedEnvelope();
          return second.future;
        });

        await tester.pumpApp(
          const PassportScreen(),
          overrides: _screenOverrides(clientApi),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('passport_identity_strip')),
          findsOneWidget,
        );

        // Kick a refresh and hold the response open.
        final BuildContext ctx = tester.element(find.byType(PassportScreen));
        ProviderScope.containerOf(
          ctx,
          listen: false,
        ).invalidate(passportProvider);
        await tester.pump();

        expect(call, 2, reason: 'the refresh must re-issue the real GET');
        expect(
          find.byKey(const Key('passport_identity_strip')),
          findsOneWidget,
          reason:
              'an in-flight refresh over a retained passport must keep the '
              'strip on screen — collapsing to the skeleton is the regression',
        );
        expect(
          find.byKey(const Key('passport_derived_block')),
          findsOneWidget,
          reason: 'the derived block is retained by the same value',
        );
        expect(find.byKey(const Key('passport_skeleton')), findsNothing);
        expect(find.byKey(const Key('passport_error_state')), findsNothing);

        // Let the refresh land so no pending future outlives the test.
        second.complete(_populatedEnvelope());
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('passport_identity_strip')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retry re-hits the endpoint and renders the recovered payload',
      (tester) async {
        // Proves the user-driven retry goes all the way back to the TRANSPORT —
        // the call count is the assertion that a stubbed provider cannot make.
        var attempt = 0;
        when(() => clientApi.getPassport()).thenAnswer((_) async {
          attempt++;
          if (attempt == 1) throw _serverError();
          return _populatedEnvelope();
        });

        await tester.pumpApp(
          const PassportScreen(),
          overrides: _screenOverrides(clientApi),
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('passport_error_state')), findsOneWidget);
        expect(attempt, 1);

        await tester.tap(find.byKey(const Key('passport_retry_button')));
        await tester.pumpAndSettle();

        expect(attempt, 2, reason: 'retry must re-issue the real GET');
        verify(() => clientApi.getPassport()).called(2);
        expect(
          find.byKey(const Key('passport_identity_strip')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('passport_derived_block')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('passport_derived_block')),
            // i18n-finder-ok: value comes from the mocked envelope, never
            // AppLocalizations.
            matching: find.text(_wireDistricts.first),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('passport_error_state')), findsNothing);
      },
    );
  });
}
