// Phase 13.3 — Unit tests for [SearchFiltersController] + the sibling
// [SearchFilterLabelsController].
//
// Pure-Dart provider units: no widget tree. Each test builds a fresh
// [ProviderContainer] (disposed in addTearDown) so keepAlive controller state
// never leaks between cases.
//
// Coverage:
//   SearchFiltersController
//     • initial state is const SearchFilters()
//     • setQuery — NORMALISES, decides, and REPORTS. Normalisation is
//       control-strip → trim → cap at kSearchMaxQueryLength UTF-16 CODE UNITS
//       (rune-walked, so a surrogate pair is never bisected). The decision is
//       three-way and now returns a SearchQueryOutcome:
//         blank                        → CLEAR to null   (outcome: cleared)
//         1 … kSearchMinQueryLength-1  → CLEAR to null   (outcome: belowMinimum)
//         kSearchMinQueryLength+       → APPLY           (outcome: applied)
//       A sub-minimum term is still NEVER promoted onto the wire model (the
//       backend answers a below-minimum `q` with an empty page), but it no
//       longer HOLDS the previous term either: holding it is precisely what
//       left stale results + a stale applied-query chip on screen under a term
//       the user had already shortened. The rejected term stays observable on
//       the sibling SearchQueryDraftController, which is what the field's error
//       ring, the disabled «Показати майстрів» CTA and the filters ↔ results
//       field sync all read.
//     • the draft mirror — setQuery writes the normalised term onto
//       searchQueryDraftControllerProvider on EVERY call; clearFilters/reset
//       empty it.
//     • selectCity — sets cityId (+ districtId); clearing cityId clears district
//     • toggleServiceType — single-select replaces prior; re-tap clears
//     • setMaxPrice — sets maxPrice; >= kSearchPriceCeiling → null boundary;
//       null → null; minPrice always stays null (single-thumb control)
//     • reset — back to const SearchFilters()
//     • logout reset — flipping authProvider to Unauthenticated rebuilds the
//       controller to const SearchFilters() (the keepAlive per-user self-clear)
//   SearchFilterLabelsController
//     • labels live OUT of SearchFilters (no label fields on the wire model);
//       set/clear cityName + categoryName independently; reset clears both

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/pending_service_preselection_provider.dart';
import 'package:beautica_mobile/features/discovery/domain/search_filters.dart';
import 'package:beautica_mobile/features/discovery/presentation/state/search_filters_controller.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/location/state/location_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_auth_repository.dart';
import '../../../helpers/fakes/fake_secure_storage.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _testUser = User(
  id: 'u-client-1',
  email: 'client@beautica.ua',
  role: UserRole.client,
  firstName: 'Дмитро',
  lastName: 'Клієнт',
);

const _authenticated = AsyncData<AuthSession>(
  AuthSession.authenticated(user: _testUser, accessToken: 'tok'),
);

const _unauthenticated = AsyncData<AuthSession>(AuthSession.unauthenticated());

// ---------------------------------------------------------------------------
// A mutable AuthNotifier stub. Unlike the fixed-state stub, [emit] lets a test
// flip the settled session AFTER build() so a watcher (the search controllers)
// rebuilds — exercising the logout self-clear contract.
// ---------------------------------------------------------------------------

class _MutableAuthNotifier extends AuthNotifier {
  _MutableAuthNotifier(this._initial);

  final AsyncValue<AuthSession> _initial;

  @override
  Future<AuthSession> build() async {
    state = _initial;
    return _initial.value ?? const AuthSession.unauthenticated();
  }

  void emit(AsyncValue<AuthSession> next) => state = next;
}

/// Builds a fresh container with the auth graph stubbed to [auth].
///
/// Returns the container AND the mutable auth notifier handle so a test can
/// flip the session mid-flight (logout reset). The container is disposed via
/// addTearDown so keepAlive controller state never leaks across tests.
({ProviderContainer container, _MutableAuthNotifier auth}) _make({
  AsyncValue<AuthSession> auth = _authenticated,
  // ProviderContainer.overrides expects List<Override>; that name is not
  // exported by this Riverpod version, so extra overrides are passed as
  // List<Object> and the combined list is `.cast()`-ed (the house pattern —
  // see test/helpers/pump_app.dart).
  List<Object> extra = const <Object>[],
}) {
  final notifier = _MutableAuthNotifier(auth);
  final container = ProviderContainer(
    retry: beauticaProviderRetry,
    overrides: <Object>[
      authProvider.overrideWith(() => notifier),
      authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
      secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
      ...extra,
    ].cast(),
  );
  addTearDown(container.dispose);
  return (container: container, auth: notifier);
}

SearchFiltersController _filters(ProviderContainer c) =>
    c.read(searchFiltersControllerProvider.notifier);

SearchFilters _state(ProviderContainer c) =>
    c.read(searchFiltersControllerProvider);

void main() {
  group('SearchFiltersController — initial', () {
    test('starts at an empty const SearchFilters()', () {
      final c = _make().container;
      expect(_state(c), const SearchFilters());
    });
  });

  group('SearchFiltersController.setQuery', () {
    test('keeps a trimmed non-blank value', () {
      final c = _make().container;

      _filters(c).setQuery('  манікюр  ');

      expect(_state(c).query, 'манікюр');
    });

    test('normalises an empty string to null', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр'); // first set a value

      _filters(c).setQuery('');

      expect(_state(c).query, isNull);
    });

    test('normalises a whitespace-only string to null', () {
      final c = _make().container;

      _filters(c).setQuery('   ');

      expect(_state(c).query, isNull);
    });

    test('normalises a null query to null', () {
      final c = _make().container;
      // Priming MUST use a 3+ character term: a 1-character one is REJECTED,
      // not applied, so it would leave `query` null and this test would pass
      // vacuously — it would no longer prove that null CLEARS anything.
      _filters(c).setQuery('манікюр');
      expect(_state(c).query, 'манікюр', reason: 'priming must have taken');

      _filters(c).setQuery(null);

      expect(_state(c).query, isNull);
    });
  });

  // ── setQuery normalisation ────────────────────────────────────────────────
  //
  // Everything below pins ORDERING and UNIT choices that are load-bearing. Each
  // has a cheaper-looking implementation that is wrong in a way no other test in
  // this repo would notice:
  //
  //   • strip-before-trim — Dart's `trim()` whitespace set does NOT include the
  //     C0 control characters, so trimming first leaves a stray space behind.
  //   • rune-walk truncation — `substring(0, 100)` can bisect a surrogate pair
  //     and emit a LONE SURROGATE, which is not valid text on the wire.
  //   • code-unit cap — the widget's `maxLength` counts GRAPHEMES; the backend's
  //     `@Size(max = 100)` counts UTF-16 code units, exactly as Dart's
  //     `String.length` does. 51 astral emoji are 51 graphemes but 102 units:
  //     under a grapheme cap they sail past the widget and 400 at the backend.
  group('SearchFiltersController.setQuery normalisation', () {
    test('control characters are stripped BEFORE trimming', () {
      final c = _make().container;

      // A leading control character shields the space that follows it from
      // `trim()`. Strip first and the space becomes leading, so trim removes it;
      // trim first and the value keeps a stray leading space forever.
      _filters(c).setQuery('\u0001 abc');

      expect(
        _state(c).query,
        'abc',
        reason:
            'trim-first would yield " abc" — U+0001 is not in Dart trim()s '
            'whitespace set, so it shields the space from being trimmed',
      );
    });

    test('interior control characters are removed, not replaced', () {
      final c = _make().container;

      _filters(c).setQuery('ма\u0009ні\u000Aкюр');

      expect(_state(c).query, 'манікюр');
    });

    test('a term of exactly kSearchMaxQueryLength units is untouched', () {
      final c = _make().container;
      final String exact = 'a' * kSearchMaxQueryLength;

      _filters(c).setQuery(exact);

      expect(_state(c).query, exact);
      expect(_state(c).query!.length, kSearchMaxQueryLength);
    });

    test('an over-long ASCII term is capped at kSearchMaxQueryLength', () {
      final c = _make().container;

      _filters(c).setQuery('a' * 250);

      expect(_state(c).query!.length, kSearchMaxQueryLength);
    });

    test('truncation drops a boundary-straddling emoji WHOLE — never a lone '
        'surrogate', () {
      final c = _make().container;
      // 99 ASCII + one astral emoji = 101 UTF-16 code units. The cut lands
      // INSIDE the surrogate pair.
      final String input = '${'a' * 99}😀';
      expect(input.length, 101, reason: 'fixture sanity: 99 + 2 units');

      _filters(c).setQuery(input);

      final String applied = _state(c).query!;

      expect(
        applied.length,
        99,
        reason:
            'the emoji cannot fit in the remaining single unit, so the whole '
            'rune is dropped',
      );
      expect(applied, 'a' * 99);

      // The counterfactual — this is what makes the test discriminate. A
      // `substring(0, 100)` implementation WOULD produce a lone high
      // surrogate, so asserting only the length above would not catch it.
      final String viaSubstring = input.substring(0, kSearchMaxQueryLength);
      expect(
        viaSubstring.length,
        kSearchMaxQueryLength,
        reason: 'substring hits the cap exactly…',
      );
      expect(
        viaSubstring.codeUnits.last,
        allOf(greaterThanOrEqualTo(0xD800), lessThanOrEqualTo(0xDBFF)),
        reason:
            '…but its last unit is an UNPAIRED HIGH SURROGATE — the exact '
            'corruption the rune walk exists to prevent',
      );
      expect(
        applied.codeUnits.any((int u) => u >= 0xD800 && u <= 0xDFFF),
        isFalse,
        reason: 'the real implementation emits no surrogate at all here',
      );
    });

    test(
      'the cap counts UTF-16 CODE UNITS, not graphemes — 51 astral emoji are '
      'capped to 50',
      () {
        final c = _make().container;
        const String emoji = '😀';
        expect(emoji.length, 2, reason: 'fixture sanity: astral = 2 units');

        final String input = emoji * 51;
        expect(input.runes.length, 51, reason: '51 graphemes…');
        expect(input.length, 102, reason: '…but 102 code units');

        _filters(c).setQuery(input);

        final String applied = _state(c).query!;
        expect(
          applied.length,
          lessThanOrEqualTo(kSearchMaxQueryLength),
          reason:
              'THE point of the fix: a grapheme cap would let all 51 through '
              'at 102 units and the backend @Size(max = 100) would 400',
        );
        expect(applied.runes.length, 50);
        expect(applied.length, 100);
      },
    );

    test('a cut that exposes trailing whitespace is trimmed again', () {
      final c = _make().container;

      // 99 chars, then a space at unit 100, then more — the cap lands on the
      // space, which must not survive as a trailing character.
      _filters(c).setQuery('${'a' * 99} bbbb');

      expect(_state(c).query, 'a' * 99);
      expect(
        _state(c).query!.endsWith(' '),
        isFalse,
        reason: 'the post-cap trim exists exactly for this',
      );
    });
  });

  // ── setQuery BELOW-MINIMUM semantics ──────────────────────────────────────
  //
  // This group used to pin the exact opposite contract ("HOLD the previously
  // applied query"), and that contract WAS the defect: a bare `return` left the
  // state untouched, so the results screen read back an unchanged applied query,
  // never re-keyed, and kept the previous term's cards plus its applied-query
  // chip on screen with no signal that the keystroke had been rejected. The
  // wire invariant it protected is still intact — a sub-minimum term is STILL
  // never promoted onto SearchFilters.query — but the previous term now goes
  // with it, and the caller is told which of the two null-producing cases it
  // got.
  group('SearchFiltersController.setQuery below-minimum semantics', () {
    test('a 1-character term CLEARS the previously applied query', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр');

      _filters(c).setQuery('м');

      expect(
        _state(c).query,
        isNull,
        reason:
            'holding it is what left stale results and a stale chip under a '
            'term the user had already deleted',
      );
    });

    test('a 1-character term reports belowMinimum', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр');

      expect(_filters(c).setQuery('м'), SearchQueryOutcome.belowMinimum);
    });

    test('a 2-character term CLEARS the previously applied query', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр');

      _filters(c).setQuery('ма');

      expect(_state(c).query, isNull);
      expect(_filters(c).setQuery('ма'), SearchQueryOutcome.belowMinimum);
    });

    test('a sub-minimum term is NEVER promoted onto the wire model', () {
      final c = _make().container;

      _filters(c).setQuery('ма');

      expect(
        _state(c).query,
        isNull,
        reason:
            'SearchFilters.query is the wire model: null, or something the '
            'backend will honour. The below-minimum term lives on the draft.',
      );
    });

    test('the below-minimum term IS observable, on the draft', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр');

      _filters(c).setQuery('ма');

      expect(
        c.read(searchQueryDraftControllerProvider),
        'ма',
        reason:
            'the whole point of the fix: the term is not silently swallowed, '
            'it is just kept OUT of the wire model — the CTA gate, the field '
            'error and the cross-screen sync all read it here',
      );
    });

    test(
      'a padded 2-character term is below-minimum (normalisation first)',
      () {
        final c = _make().container;
        _filters(c).setQuery('манікюр');

        expect(
          _filters(c).setQuery('  ма  '),
          SearchQueryOutcome.belowMinimum,
          reason:
              'the decision is made on the NORMALISED term — the padding must '
              'not inflate it past the minimum',
        );
        expect(_state(c).query, isNull);
        expect(
          c.read(searchQueryDraftControllerProvider),
          'ма',
          reason: 'the draft carries the NORMALISED term, not the raw padding',
        );
      },
    );

    test('a\u0009b normalises to 2 chars and is therefore below-minimum', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр');

      expect(
        _filters(c).setQuery('a\u0009b'),
        SearchQueryOutcome.belowMinimum,
        reason:
            'intentional: the tab is stripped, leaving "ab" — a 2-character '
            'term. A raw-length check would have applied it.',
      );
      expect(_state(c).query, isNull);
    });

    test('a below-minimum term with NO prior query leaves it null', () {
      final c = _make().container;

      expect(_filters(c).setQuery('ма'), SearchQueryOutcome.belowMinimum);
      expect(_state(c).query, isNull);
    });

    test(
      'a 2-character Cyrillic term is below-minimum (no locale shortcut)',
      () {
        final c = _make().container;
        _filters(c).setQuery('манікюр');

        expect(_filters(c).setQuery('ма'), SearchQueryOutcome.belowMinimum);
        expect(_state(c).query, isNull);
      },
    );

    test('exactly kSearchMinQueryLength characters APPLIES', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр');

      expect(
        _filters(c).setQuery('ман'),
        SearchQueryOutcome.applied,
        reason: 'the minimum is inclusive — 3 is enough',
      );
      expect(_state(c).query, 'ман');
    });

    test('blank CLEARS, and is reported as cleared — NOT as an error', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр');

      final SearchQueryOutcome outcome = _filters(c).setQuery('   ');

      expect(_state(c).query, isNull);
      expect(
        outcome,
        SearchQueryOutcome.cleared,
        reason:
            'an empty box is a perfectly good filters-only search. Collapsing '
            'it into belowMinimum would put a red error under an empty field '
            'and disable the CTA for a legitimate query-less search.',
      );
      expect(c.read(searchQueryDraftControllerProvider), '');
    });

    test('cleared and belowMinimum are distinguishable despite both nulling '
        'query', () {
      final c = _make().container;

      expect(_filters(c).setQuery(''), SearchQueryOutcome.cleared);
      expect(_state(c).query, isNull);

      expect(_filters(c).setQuery('ма'), SearchQueryOutcome.belowMinimum);
      expect(_state(c).query, isNull);

      // Same wire model, opposite UI treatment — the outcome is the ONLY way a
      // caller can tell "no term" from "term rejected".
    });

    test('completing the term re-applies it and clears the error state', () {
      final c = _make().container;
      _filters(c).setQuery('ма');
      expect(_state(c).query, isNull);

      expect(_filters(c).setQuery('манікюр'), SearchQueryOutcome.applied);
      expect(_state(c).query, 'манікюр');
      expect(c.read(searchQueryDraftControllerProvider), 'манікюр');
    });
  });

  // ── the draft mirror ──────────────────────────────────────────────────────
  group('SearchQueryDraftController', () {
    test('starts empty', () {
      final c = _make().container;
      expect(c.read(searchQueryDraftControllerProvider), '');
    });

    test('setQuery mirrors the normalised term whatever the outcome', () {
      final c = _make().container;

      _filters(c).setQuery('  манікюр  ');
      expect(c.read(searchQueryDraftControllerProvider), 'манікюр');

      _filters(c).setQuery('ма');
      expect(c.read(searchQueryDraftControllerProvider), 'ма');

      _filters(c).setQuery('');
      expect(c.read(searchQueryDraftControllerProvider), '');
    });

    test('clearFilters empties the draft as well as the applied query', () {
      final c = _make().container;
      _filters(c).setQuery('ма');
      expect(c.read(searchQueryDraftControllerProvider), 'ма');

      _filters(c).clearFilters();

      expect(
        c.read(searchQueryDraftControllerProvider),
        '',
        reason:
            '«Скинути фільтри» must leave the box genuinely empty — a surviving '
            'below-minimum draft would keep the field red and the CTA disabled '
            'over a filter set that carries no query at all',
      );
    });

    test('reset empties the draft as well as the applied query', () {
      final c = _make().container;
      _filters(c).setQuery('манікюр');

      _filters(c).reset();

      expect(c.read(searchQueryDraftControllerProvider), '');
    });
  });

  group('SearchFiltersController.selectCity', () {
    test('sets cityId with no district', () {
      final c = _make().container;

      _filters(c).selectCity(cityId: 'city-kyiv');

      expect(_state(c).cityId, 'city-kyiv');
      expect(_state(c).districtId, isNull);
    });

    test('sets cityId then districtId via selectDistrict', () {
      final c = _make().container;

      _filters(c).selectCity(cityId: 'city-kyiv');
      _filters(c).selectDistrict(districtId: 'dist-1');

      expect(_state(c).cityId, 'city-kyiv');
      expect(_state(c).districtId, 'dist-1');
    });

    test('clearing the city (cityId: null) also clears the district', () {
      final c = _make().container;
      _filters(c).selectCity(cityId: 'city-kyiv');
      _filters(c).selectDistrict(districtId: 'dist-1');

      _filters(c).selectCity(cityId: null);

      expect(_state(c).cityId, isNull);
      expect(
        _state(c).districtId,
        isNull,
        reason: 'a district is meaningless without its city — must be cleared',
      );
    });

    test('a districtId passed with a null cityId is dropped', () {
      final c = _make().container;

      _filters(c).selectDistrict(districtId: 'dist-orphan');

      expect(_state(c).cityId, isNull);
      expect(_state(c).districtId, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // Item 4 — Region → City → District cascading filter.
  //
  // The region (oblast) is a UI-only narrowing step: it is persisted on
  // SearchFilters.oblastId so the picker can re-open the right city list and
  // the applied-filter chips can show the region label, but it is NEVER sent to
  // the wire (the repository assertion lives in search_repository_test.dart's
  // "oblastId is UI-only" group). The district is OPTIONAL — a search proceeds
  // with a city alone. Changing the city clears any stale district.
  // -------------------------------------------------------------------------
  group('SearchFiltersController.selectOblast — cascade level 1', () {
    test('selecting an oblast sets oblastId (city/district stay null)', () {
      final c = _make().container;

      _filters(c).selectOblast(oblastId: 'oblast-kyiv');

      expect(_state(c).oblastId, 'oblast-kyiv');
      expect(_state(c).cityId, isNull);
      expect(_state(c).districtId, isNull);
    });

    test('selecting a city KEEPS the chosen oblast (stays in region)', () {
      final c = _make().container;
      _filters(c).selectOblast(oblastId: 'oblast-kyiv');

      _filters(c).selectCity(cityId: 'city-kyiv');

      expect(
        _state(c).oblastId,
        'oblast-kyiv',
        reason: 'picking a city must not drop the region it lives in',
      );
      expect(_state(c).cityId, 'city-kyiv');
    });

    test('a city + NO district is a valid (district-optional) selection', () {
      final c = _make().container;
      _filters(c)
        ..selectOblast(oblastId: 'oblast-kyiv')
        ..selectCity(cityId: 'city-kyiv');

      // District left unset — the search proceeds on the city scope alone.
      expect(_state(c).cityId, 'city-kyiv');
      expect(_state(c).districtId, isNull);
    });

    test(
      're-running the region→city cascade CLEARS a stale district (the screen '
      'always re-selects the oblast first, which resets cityId+districtId)',
      () {
        final c = _make().container;
        _filters(c)
          ..selectOblast(oblastId: 'oblast-kyiv')
          ..selectCity(cityId: 'city-kyiv')
          ..selectDistrict(districtId: 'dist-pechersk');
        expect(_state(c).districtId, 'dist-pechersk');

        // The picker commits a new pick via selectOblast → selectCity (see
        // search_filters_screen.dart _onPickLocality). selectOblast resets the
        // whole locality, so the stale district from the prior city is dropped.
        _filters(c)
          ..selectOblast(oblastId: 'oblast-kyiv')
          ..selectCity(cityId: 'city-other');

        expect(_state(c).cityId, 'city-other');
        expect(
          _state(c).districtId,
          isNull,
          reason:
              'a district from the old city is meaningless in the new city '
              '— the oblast-first re-selection clears it',
        );
        expect(_state(c).oblastId, 'oblast-kyiv');
      },
    );

    test('a bare selectCity to a new non-null city PRESERVES the district (the '
        'cascade integrity is enforced by the oblast-first re-selection, not by '
        'selectCity itself)', () {
      final c = _make().container;
      _filters(c)
        ..selectOblast(oblastId: 'oblast-kyiv')
        ..selectCity(cityId: 'city-kyiv')
        ..selectDistrict(districtId: 'dist-pechersk');

      // A standalone selectCity (NOT preceded by selectOblast) only swaps the
      // city id; it keeps the district. This pins the actual contract so a
      // future change to selectCity's clear-semantics is a deliberate edit.
      _filters(c).selectCity(cityId: 'city-other');

      expect(_state(c).cityId, 'city-other');
      expect(_state(c).districtId, 'dist-pechersk');
    });

    test('clearing the oblast clears the whole locality (city + district)', () {
      final c = _make().container;
      _filters(c)
        ..selectOblast(oblastId: 'oblast-kyiv')
        ..selectCity(cityId: 'city-kyiv')
        ..selectDistrict(districtId: 'dist-pechersk');

      _filters(c).selectOblast(oblastId: null);

      expect(_state(c).oblastId, isNull);
      expect(_state(c).cityId, isNull);
      expect(_state(c).districtId, isNull);
    });
  });

  group('SearchFiltersController.toggleServiceType', () {
    test('selecting a category sets categoryKey', () {
      final c = _make().container;

      _filters(c).toggleServiceType('NAILS');

      expect(_state(c).categoryKey, 'NAILS');
    });

    test(
      'selecting a different category REPLACES the prior (single-select)',
      () {
        final c = _make().container;
        _filters(c).toggleServiceType('NAILS');

        _filters(c).toggleServiceType('BROWS');

        expect(_state(c).categoryKey, 'BROWS');
      },
    );

    test('re-tapping the selected category clears it', () {
      final c = _make().container;
      _filters(c).toggleServiceType('NAILS');

      _filters(c).toggleServiceType('NAILS');

      expect(_state(c).categoryKey, isNull);
    });
  });

  group('SearchFiltersController.setMaxPrice', () {
    test('sets an in-range ceiling', () {
      final c = _make().container;

      _filters(c).setMaxPrice(1200);

      expect(_state(c).maxPrice, 1200);
    });

    test('a value AT the ceiling collapses to null ("будь-яка")', () {
      final c = _make().container;

      _filters(c).setMaxPrice(kSearchPriceCeiling);

      expect(
        _state(c).maxPrice,
        isNull,
        reason: 'value == kSearchPriceCeiling means no upper bound',
      );
    });

    test('a value ABOVE the ceiling collapses to null', () {
      final c = _make().container;

      _filters(c).setMaxPrice(kSearchPriceCeiling + 500);

      expect(_state(c).maxPrice, isNull);
    });

    test('a value just BELOW the ceiling is kept', () {
      final c = _make().container;

      _filters(c).setMaxPrice(kSearchPriceCeiling - 100);

      expect(_state(c).maxPrice, kSearchPriceCeiling - 100);
    });

    test('null clears the ceiling', () {
      final c = _make().container;
      _filters(c).setMaxPrice(1000);

      _filters(c).setMaxPrice(null);

      expect(_state(c).maxPrice, isNull);
    });

    test('the single-thumb control never sets minPrice', () {
      final c = _make().container;

      _filters(c).setMaxPrice(1000);

      expect(
        _state(c).minPrice,
        isNull,
        reason: 'setMaxPrice must leave minPrice null (single-thumb slider)',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Regression guard — the search price ceiling was raised 5000 → 20000
  // (kSearchPriceDivisions 50 → 40, i.e. a 500-₴ step). The existing
  // setMaxPrice group above asserts only against the *symbol*
  // kSearchPriceCeiling, so it passes under EITHER ceiling and cannot catch a
  // regression of the value itself. THESE cases pin concrete rupee-values that
  // straddle the old 5000 bound: each would have FAILED under the old ceiling
  // (a 12000 max collapsed to null / "no upper bound" when the ceiling was
  // 5000, since 12000 >= 5000). They lock the raised ceiling in place.
  // -------------------------------------------------------------------------
  group('SearchFiltersController — 20000 price ceiling (raised from 5000)', () {
    test('kSearchPriceCeiling is 20000 and divisions is 40 (500-₴ step)', () {
      expect(kSearchPriceCeiling, 20000);
      expect(kSearchPriceDivisions, 40);
      // Sanity: 40 divisions over a 20000 span is a 500-₴ increment.
      expect(kSearchPriceCeiling / kSearchPriceDivisions, 500);
    });

    test(
      'a 12000 max (above the OLD 5000 ceiling) is RETAINED as a finite upper '
      'bound — under the old ceiling this collapsed to null (unbounded)',
      () {
        final c = _make().container;

        _filters(c).setMaxPrice(12000);

        expect(
          _state(c).maxPrice,
          12000,
          reason:
              'the key regression guard: 12000 < 20000 so it is a real finite '
              'ceiling now; with the old ceiling of 5000, 12000 >= 5000 would '
              'have cleared maxPrice to null',
        );
      },
    );

    test('a max at exactly 20000 collapses to null ("будь-яка")', () {
      final c = _make().container;

      _filters(c).setMaxPrice(20000);

      expect(
        _state(c).maxPrice,
        isNull,
        reason: '20000 == kSearchPriceCeiling means no upper bound',
      );
    });

    test(
      '19500 (one 500-step below the new ceiling) is kept as a finite max',
      () {
        final c = _make().container;

        _filters(c).setMaxPrice(19500);

        expect(_state(c).maxPrice, 19500);
      },
    );

    test('a max above 20000 clamps behaviour: 25000 collapses to null', () {
      final c = _make().container;

      _filters(c).setMaxPrice(25000);

      expect(_state(c).maxPrice, isNull);
    });

    test(
      'setMinPrice retains 12000 as a finite floor (above the old 5000 ceiling)',
      () {
        final c = _make().container;

        _filters(c).setMinPrice(12000);

        expect(
          _state(c).minPrice,
          12000,
          reason: 'the raised ceiling clamps to [0, 20000], so 12000 survives',
        );
      },
    );

    test('setPriceRange keeps a min 8000 / max 15000 pair — both above the old '
        'ceiling, both finite under 20000', () {
      final c = _make().container;

      _filters(c).setPriceRange(min: 8000, max: 15000);

      expect(_state(c).minPrice, 8000);
      expect(_state(c).maxPrice, 15000);
    });
  });

  group('SearchFiltersController.reset', () {
    test('clears every populated field back to const SearchFilters()', () {
      final c = _make().container;
      _filters(c)
        ..setQuery('манікюр')
        ..selectCity(cityId: 'city-kyiv')
        ..selectDistrict(districtId: 'dist-1')
        ..toggleServiceType('NAILS')
        ..setMaxPrice(1200);
      // Precondition: state is genuinely non-empty.
      expect(_state(c), isNot(const SearchFilters()));

      _filters(c).reset();

      expect(_state(c), const SearchFilters());
    });

    test('also clears any pending booking service pre-selection', () {
      final c = _make().container;
      // A prior search handed a pre-selection into the booking flow …
      c
          .read(pendingServicePreselectionControllerProvider.notifier)
          .set(
            targetId: 'master-1',
            serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
            serviceTypeLabels: const <String>{},
          );
      expect(c.read(pendingServicePreselectionControllerProvider), isNotNull);

      _filters(c).reset();

      // … resetting the filters must drop it so a cleared filter never leaks a
      // stale service pre-check into a later booking.
      expect(
        c.read(pendingServicePreselectionControllerProvider),
        isNull,
        reason: 'reset() must clear the pending booking pre-selection too',
      );
    });
  });

  // -------------------------------------------------------------------------
  // clearFilters — «Скинути фільтри». Resets every NON-location facet (query,
  // category, per-service selection, rating floor, price band, sort) back to the
  // empty baseline WHILE preserving the currently-resolved locality (oblast →
  // city → district) and its display labels. Crucially it does this by mutating
  // state in place (a single copyWith omitting the locality ids) — it NEVER
  // re-reads the profile or re-resolves the location taxonomy, so none of the
  // location providers is touched.
  // -------------------------------------------------------------------------
  group('SearchFiltersController.clearFilters', () {
    test(
      'clears every NON-location facet but PRESERVES the resolved locality + its '
      'labels, and re-resolves NO location taxonomy',
      () {
        // Spy fakes for the three taxonomy providers — clearFilters must never
        // read them (the locality carries through untouched), so every counter
        // must stay at 0 across the clear.
        var oblastCalls = 0;
        var cityCalls = 0;
        var districtCalls = 0;
        final c = _make(
          extra: <Object>[
            oblastListProvider.overrideWith((ref) async {
              oblastCalls++;
              return const <Oblast>[];
            }),
            cityListProvider('oblast-kyiv').overrideWith((ref) async {
              cityCalls++;
              return const <City>[];
            }),
            districtListProvider('city-kyiv').overrideWith((ref) async {
              districtCalls++;
              return const <CityDistrict>[];
            }),
          ],
        ).container;

        // Arrange — a fully-populated filter set: locality (oblast→city→district)
        // PLUS every clearable facet reachable through the public API.
        _filters(c)
          ..selectOblast(oblastId: 'oblast-kyiv')
          ..selectCity(cityId: 'city-kyiv')
          ..selectDistrict(districtId: 'dist-pechersk')
          ..setQuery('манікюр')
          ..toggleServiceType('NAILS')
          ..setPriceRange(min: 300, max: 900)
          ..setSort(SearchSort.priceAsc);
        // Seed the sibling label + service-selection controllers too.
        c.read(searchFilterLabelsControllerProvider.notifier)
          ..setOblastName('Київська')
          ..setCityName('Київ')
          ..setDistrictName('Печерський')
          ..setCategoryName('Манікюр');
        c.read(searchServiceSelectionControllerProvider.notifier)
          ..toggle('classic')
          ..toggle('gel');
        // Precondition: genuinely non-empty, non-default state.
        expect(_state(c).categoryKey, 'NAILS');
        expect(_state(c).sort, SearchSort.priceAsc);

        // Act.
        _filters(c).clearFilters();

        // Assert — every NON-location facet reset to its baseline ...
        final SearchFilters s = _state(c);
        expect(s.query, isNull);
        expect(s.categoryKey, isNull);
        expect(s.serviceTypeSlugs, isEmpty);
        expect(
          s.minRating,
          isNull,
          reason: 'clear drops any rating floor (defensive — no public seeder)',
        );
        expect(s.minPrice, isNull);
        expect(s.maxPrice, isNull);
        expect(
          s.sort,
          SearchSort.ratingDesc,
          reason: 'clear resets the ordering to the ratingDesc default',
        );

        // ... while the resolved locality carries straight through untouched.
        expect(s.oblastId, 'oblast-kyiv');
        expect(s.cityId, 'city-kyiv');
        expect(s.districtId, 'dist-pechersk');

        // The label controller keeps the three locality names, drops ONLY the
        // category label.
        final SearchFilterLabels labels = c.read(
          searchFilterLabelsControllerProvider,
        );
        expect(labels.oblastName, 'Київська');
        expect(labels.cityName, 'Київ');
        expect(labels.districtName, 'Печерський');
        expect(labels.categoryName, isNull);

        // The second-level per-service selection is emptied.
        expect(c.read(searchServiceSelectionControllerProvider), isEmpty);

        // No location taxonomy endpoint was re-read across the clear — the
        // locality is preserved by an in-place copyWith, never a re-resolve.
        expect(oblastCalls, 0);
        expect(cityCalls, 0);
        expect(districtCalls, 0);
      },
    );

    test(
      'leaves a location-only state fully intact (clear is a no-op there)',
      () {
        final c = _make().container;
        _filters(c)
          ..selectOblast(oblastId: 'oblast-kyiv')
          ..selectCity(cityId: 'city-kyiv');

        _filters(c).clearFilters();

        expect(_state(c).oblastId, 'oblast-kyiv');
        expect(_state(c).cityId, 'city-kyiv');
        // Nothing clearable was set, so the whole state is location-only.
        expect(_state(c).query, isNull);
        expect(_state(c).categoryKey, isNull);
      },
    );

    test('also clears any pending booking service pre-selection', () {
      final c = _make().container;
      c
          .read(pendingServicePreselectionControllerProvider.notifier)
          .set(
            targetId: 'salon-xyz',
            serviceTypeSlugs: <String>{'CLASSIC_MANICURE'},
            serviceTypeLabels: const <String>{},
          );
      expect(c.read(pendingServicePreselectionControllerProvider), isNotNull);

      _filters(c).clearFilters();

      expect(
        c.read(pendingServicePreselectionControllerProvider),
        isNull,
        reason:
            '«Скинути фільтри» must drop the pending booking pre-selection so a '
            'cleared filter never leaks a stale service pre-check',
      );
    });
  });

  group('SearchFiltersController — logout self-clear', () {
    test('rebuilds to const SearchFilters() when the session goes '
        'Unauthenticated', () {
      final made = _make(auth: _authenticated);
      final c = made.container;

      // Populate a filter set on the authenticated session.
      _filters(c)
        ..selectCity(cityId: 'city-kyiv')
        ..toggleServiceType('NAILS')
        ..setMaxPrice(900);
      expect(_state(c).cityId, 'city-kyiv');

      // Flip the watched authProvider to Unauthenticated (logout).
      made.auth.emit(_unauthenticated);

      // The keepAlive controller watches authProvider, so build() re-runs and
      // the per-user filter set is shed — no manual eviction needed.
      expect(
        _state(c),
        const SearchFilters(),
        reason: 'a fresh session must not inherit the prior user\'s search',
      );
    });
  });

  group('SearchFilterLabelsController', () {
    test('starts empty (both labels null)', () {
      final c = _make().container;
      final labels = c.read(searchFilterLabelsControllerProvider);

      expect(labels.cityName, isNull);
      expect(labels.categoryName, isNull);
    });

    test('sets and clears the city + category labels independently', () {
      final c = _make().container;
      final notifier = c.read(searchFilterLabelsControllerProvider.notifier);

      notifier.setCityName('Львів');
      notifier.setCategoryName('Манікюр');
      var labels = c.read(searchFilterLabelsControllerProvider);
      expect(labels.cityName, 'Львів');
      expect(labels.categoryName, 'Манікюр');

      // Clearing the category leaves the city untouched.
      notifier.setCategoryName(null);
      labels = c.read(searchFilterLabelsControllerProvider);
      expect(labels.categoryName, isNull);
      expect(labels.cityName, 'Львів');
    });

    test('reset clears both labels', () {
      final c = _make().container;
      final notifier = c.read(searchFilterLabelsControllerProvider.notifier);
      notifier.setCityName('Львів');
      notifier.setCategoryName('Манікюр');

      notifier.reset();

      final labels = c.read(searchFilterLabelsControllerProvider);
      expect(labels.cityName, isNull);
      expect(labels.categoryName, isNull);
    });

    // -----------------------------------------------------------------------
    // cityHasDistricts — the UI-only flag that gates the District row on the
    // filters screen. It is set when a city is picked (mirroring
    // City.hasDistricts) and MUST reset to false the moment the city is cleared
    // (no city → no districts → the District row falls back to disabled). The
    // flag never reaches the wire (search_repository_test.dart pins that the
    // request carries only location.cityId/districtId).
    // -----------------------------------------------------------------------
    test('cityHasDistricts defaults to false', () {
      final c = _make().container;

      expect(
        c.read(searchFilterLabelsControllerProvider).cityHasDistricts,
        isFalse,
      );
    });

    test('setCityHasDistricts(true) records the flag', () {
      final c = _make().container;
      final notifier = c.read(searchFilterLabelsControllerProvider.notifier);

      notifier
        ..setCityName('Київ')
        ..setCityHasDistricts(true);

      expect(
        c.read(searchFilterLabelsControllerProvider).cityHasDistricts,
        isTrue,
      );
    });

    test(
      'clearing the city name (setCityName(null)) resets cityHasDistricts to '
      'false',
      () {
        final c = _make().container;
        final notifier = c.read(searchFilterLabelsControllerProvider.notifier);
        notifier
          ..setCityName('Київ')
          ..setCityHasDistricts(true);
        expect(
          c.read(searchFilterLabelsControllerProvider).cityHasDistricts,
          isTrue,
        );

        // Clearing the city must drop the districts flag — the District row has
        // no city to subdivide, so it falls back to disabled.
        notifier.setCityName(null);

        expect(c.read(searchFilterLabelsControllerProvider).cityName, isNull);
        expect(
          c.read(searchFilterLabelsControllerProvider).cityHasDistricts,
          isFalse,
          reason: 'no city → no districts → the flag must reset',
        );
      },
    );

    test('setting a NEW city name keeps the prior cityHasDistricts until '
        'explicitly updated (only a null clear resets it)', () {
      final c = _make().container;
      final notifier = c.read(searchFilterLabelsControllerProvider.notifier);
      notifier
        ..setCityName('Київ')
        ..setCityHasDistricts(true);

      // Swapping to another non-null city name does NOT auto-reset the flag —
      // the screen always pairs setCityName with a fresh setCityHasDistricts, so
      // this pins that only the null-clear path zeroes it.
      notifier.setCityName('Львів');

      expect(c.read(searchFilterLabelsControllerProvider).cityName, 'Львів');
      expect(
        c.read(searchFilterLabelsControllerProvider).cityHasDistricts,
        isTrue,
        reason: 'a non-null city swap preserves the flag (only null resets it)',
      );
    });

    test('labels are NOT mirrored onto SearchFilters (separate model)', () {
      final c = _make().container;

      c.read(searchFilterLabelsControllerProvider.notifier)
        ..setCityName('Львів')
        ..setCategoryName('Манікюр');

      // SearchFilters carries ids/slugs only — setting display labels must not
      // touch the wire model.
      expect(_state(c), const SearchFilters());
    });
  });

  // -------------------------------------------------------------------------
  // SearchServiceSelectionController — the Variant A («Рейка + послуги»)
  // second-level service-chip selection set. Multi-select; reset imperatively
  // on a category change AND automatically on a session flip (logout/login).
  // -------------------------------------------------------------------------
  group('SearchServiceSelectionController', () {
    Set<String> selection(ProviderContainer c) =>
        c.read(searchServiceSelectionControllerProvider);
    SearchServiceSelectionController notifier(ProviderContainer c) =>
        c.read(searchServiceSelectionControllerProvider.notifier);

    test('starts as an empty set', () {
      final c = _make().container;
      expect(selection(c), isEmpty);
    });

    test('toggle adds a key when absent', () {
      final c = _make().container;

      notifier(c).toggle('haircut');

      expect(selection(c), <String>{'haircut'});
    });

    test('toggle is multi-select — distinct keys accumulate', () {
      final c = _make().container;

      notifier(c)
        ..toggle('haircut')
        ..toggle('coloring');

      expect(selection(c), <String>{'haircut', 'coloring'});
    });

    test('toggle removes a key when already present', () {
      final c = _make().container;
      notifier(c).toggle('haircut');

      notifier(c).toggle('haircut');

      expect(selection(c), isEmpty);
    });

    test('clear drops every selected service', () {
      final c = _make().container;
      notifier(c)
        ..toggle('haircut')
        ..toggle('coloring');
      expect(selection(c), isNotEmpty);

      notifier(c).clear();

      expect(selection(c), isEmpty);
    });

    test('rebuilds to an empty set when the session goes Unauthenticated', () {
      final made = _make(auth: _authenticated);
      final c = made.container;

      notifier(c)
        ..toggle('haircut')
        ..toggle('coloring');
      expect(selection(c), isNotEmpty);

      // Flip the watched authProvider to Unauthenticated (logout). The keepAlive
      // controller watches authProvider, so build() re-runs and the per-user
      // service selection is shed — mirroring SearchFiltersController.
      made.auth.emit(_unauthenticated);

      expect(
        selection(c),
        isEmpty,
        reason: 'a fresh session must not inherit the prior user\'s services',
      );
    });
  });
}
