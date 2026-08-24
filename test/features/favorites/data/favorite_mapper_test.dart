// Phase 111 (mobile-qa) — unit tests for [FavoriteMapper].
//
// WHY THIS FILE EXISTS
// --------------------
// Two audit findings in this chain were reported as FIXED but UNPINNED: the
// security auditor's own words were "deleting `_visibleOrNull(dto.locationNote)`
// from `favorite_mapper.dart:114` leaves the whole suite green". This file is
// the red-on-delete evidence for that call and for the empty-id DROP the
// mapper's header promises.
//
// Pure Dart against the generated built_value DTOs — no widget tree, no
// ProviderContainer, no Dio. Every assertion is on a returned [FavoriteItem].
//
// THE PAYLOADS ARE ESCAPES, NEVER LITERAL CHARACTERS. U+202E is written as an
// escape so this file does not itself embed a bidi override — the same rule
// `sanitize_display_text.dart` follows for the pattern it strips.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_mapper.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_item.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Payloads
// ---------------------------------------------------------------------------

/// U+202E RIGHT-TO-LEFT OVERRIDE embedded in an otherwise ordinary note.
///
/// The backend validates `locationNote` with `@Size(max = 1000)` and NOTHING
/// else — no character class — so this is a payload a hostile provider can
/// actually store. Rendered raw by `ResultAddressBlock`'s bare `Text(note)` it
/// reorders the address run around it on every client's list.
const String _hostileNote = 'entrance \u202Efrom the yard';

/// The same note with the override removed — what `sanitizeDisplayText` must
/// leave behind. Note the surrounding characters are UNCHANGED: the sanitizer
/// strips, it does not escape or elide.
const String _cleanNote = 'entrance from the yard';

/// A zero-width space is `isNotEmpty` BEFORE sanitization and empty after it.
/// A mapper that tested emptiness first would let this claim a rendered note
/// row (plus its 3dp gap) that shows nothing at all.
const String _zeroWidthOnlyNote = '\u200B\u200B';

// ---------------------------------------------------------------------------
// DTO builders
// ---------------------------------------------------------------------------

FavoriteMasterResponse _masterDto({
  String? masterId = 'master-1',
  String? firstName = 'Marta',
  String? lastName = 'Honchar',
  double? avgRating,
  String? cityLabel,
  String? districtLabel,
  String? street,
  String? buildingNo,
  String? locationNote,
}) => FavoriteMasterResponse(
  (FavoriteMasterResponseBuilder b) => b
    ..masterId = masterId
    ..firstName = firstName
    ..lastName = lastName
    ..avgRating = avgRating
    ..cityLabel = cityLabel
    ..districtLabel = districtLabel
    ..street = street
    ..buildingNo = buildingNo
    ..locationNote = locationNote,
);

FavoriteSalonResponse _salonDto({
  String? salonId = 'salon-1',
  String? name = 'Crystal Room',
  double? avgRating,
  String? cityLabel,
  String? districtLabel,
  String? street,
  String? buildingNo,
  String? locationNote,
}) => FavoriteSalonResponse(
  (FavoriteSalonResponseBuilder b) => b
    ..salonId = salonId
    ..name = name
    ..avgRating = avgRating
    ..cityLabel = cityLabel
    ..districtLabel = districtLabel
    ..street = street
    ..buildingNo = buildingNo
    ..locationNote = locationNote,
);

List<FavoriteItem> _masters(List<FavoriteMasterResponse> rows) =>
    FavoriteMapper.mastersFromDtoList(BuiltList<FavoriteMasterResponse>(rows));

List<FavoriteItem> _salons(List<FavoriteSalonResponse> rows) =>
    FavoriteMapper.salonsFromDtoList(BuiltList<FavoriteSalonResponse>(rows));

void main() {
  group('FavoriteMapper — locationNote sanitization (security MEDIUM pin)', () {
    // RED WHEN `_visibleOrNull(dto.locationNote)` at favorite_mapper.dart:114
    // becomes a bare `dto.locationNote`.
    test('strips a bidi override from a MASTER row note', () {
      final List<FavoriteItem> items = _masters(<FavoriteMasterResponse>[
        _masterDto(locationNote: _hostileNote),
      ]);

      expect(items.single.locationNote, _cleanNote);
      // Belt and braces: name the code point so a partial strip (e.g. a
      // sanitizer regression that only handled zero-widths) still fails here
      // rather than silently passing the equality above on a different string.
      expect(items.single.locationNote, isNot(contains('\u202E')));
    });

    // RED WHEN the same call at favorite_mapper.dart:136 is deleted. Pinned
    // SEPARATELY from the master row: the two arms are independent lines and a
    // single-arm regression is exactly the shape a copy-paste produces.
    test('strips a bidi override from a SALON row note', () {
      final List<FavoriteItem> items = _salons(<FavoriteSalonResponse>[
        _salonDto(locationNote: _hostileNote),
      ]);

      expect(items.single.locationNote, _cleanNote);
      expect(items.single.locationNote, isNot(contains('\u202E')));
    });

    test('folds a zero-width-only note to null on BOTH kinds', () {
      final FavoriteItem master = _masters(<FavoriteMasterResponse>[
        _masterDto(locationNote: _zeroWidthOnlyNote),
      ]).single;
      final FavoriteItem salon = _salons(<FavoriteSalonResponse>[
        _salonDto(locationNote: _zeroWidthOnlyNote),
      ]).single;

      // Sanitize-then-test, not test-then-sanitize: a zero-width-only note
      // is `isNotEmpty` BEFORE stripping, so the wrong order renders an
      // empty note row.
      expect(master.locationNote, isNull);
      expect(salon.locationNote, isNull);
    });

    test('folds a whitespace-only note to null', () {
      expect(
        _masters(<FavoriteMasterResponse>[
          _masterDto(locationNote: '   '),
        ]).single.locationNote,
        isNull,
      );
    });

    test('sanitizes city and district labels too', () {
      final FavoriteItem item = _masters(<FavoriteMasterResponse>[
        _masterDto(
          cityLabel: 'Kyiv\u200B',
          districtLabel: '\u202DShevchenkivskyi',
        ),
      ]).single;

      expect(item.cityLabel, 'Kyiv');
      expect(item.districtLabel, 'Shevchenkivskyi');
    });
  });

  group('FavoriteMapper — the empty-id DROP (the `?? \'\'` defect)', () {
    // The whole reason this mapper exists. `booking_mapper.dart:119` writes
    // `masterId: dto.masterId ?? ''`, which SUCCEEDS into a card that navigates
    // to `/masters/` — go_router's "page not found". The mapper must drop.
    test('drops a master row whose masterId is a whitespace-only string', () {
      final List<FavoriteItem> items = _masters(<FavoriteMasterResponse>[
        _masterDto(masterId: 'master-keep'),
        _masterDto(masterId: '   ', firstName: 'Ghost'),
      ]);

      // The row is GONE, not rendered with an empty id.
      expect(items, hasLength(1));
      expect(items.single.id, 'master-keep');
      // And the survivor is untouched — dropping must not reorder or corrupt
      // the good rows beside the bad one.
      expect(items.single.name, 'Marta Honchar');
    });

    test('drops a master row whose masterId is null or empty', () {
      expect(
        _masters(<FavoriteMasterResponse>[_masterDto(masterId: null)]),
        isEmpty,
      );
      expect(
        _masters(<FavoriteMasterResponse>[_masterDto(masterId: '')]),
        isEmpty,
      );
    });

    test('drops a salon row whose salonId is whitespace-only', () {
      final List<FavoriteItem> items = _salons(<FavoriteSalonResponse>[
        _salonDto(salonId: '  \t '),
        _salonDto(salonId: 'salon-keep'),
      ]);

      expect(items, hasLength(1));
      expect(items.single.id, 'salon-keep');
    });

    test('TRIMS a surviving id rather than carrying the padding into a '
        'route', () {
      // `' master-1 '` is usable — but only after trimming. Carrying the raw
      // value would build `/masters/%20master-1%20`.
      final FavoriteItem item = _masters(<FavoriteMasterResponse>[
        _masterDto(masterId: ' master-1 '),
      ]).single;

      expect(item.id, 'master-1');
      expect(item.target.id, 'master-1');
    });
  });

  group('FavoriteMapper — rating folding', () {
    test('folds a backend 0.0 to null so the card never libels a provider', () {
      final FavoriteItem item = _masters(<FavoriteMasterResponse>[
        _masterDto(avgRating: 0),
      ]).single;

      expect(item.rating, isNull);
      expect(item.hasRating, isFalse);
    });

    test('keeps a real rating verbatim', () {
      final FavoriteItem item = _salons(<FavoriteSalonResponse>[
        _salonDto(avgRating: 4.7),
      ]).single;

      expect(item.rating, 4.7);
      expect(item.hasRating, isTrue);
    });
  });

  group('FavoriteMapper — identity', () {
    test('joins both name halves and sanitizes each', () {
      final FavoriteItem item = _masters(<FavoriteMasterResponse>[
        _masterDto(firstName: 'Marta\u200B', lastName: '\u202EHonchar'),
      ]).single;

      expect(item.name, startsWith('Marta '));
      expect(item.name, isNot(contains('\u200B')));
    });

    test('a master with only one name half gets no stray separator', () {
      expect(
        _masters(<FavoriteMasterResponse>[
          _masterDto(firstName: 'Marta', lastName: null),
        ]).single.name,
        'Marta',
      );
    });

    test('initialsOf takes the first CODE POINT of the first two words', () {
      expect(FavoriteMapper.initialsOf('Marta Honchar'), 'MH');
      expect(FavoriteMapper.initialsOf('Marta'), 'M');
      expect(FavoriteMapper.initialsOf(''), '');
      // Three words → still exactly two initials.
      expect(FavoriteMapper.initialsOf('Anna Maria Petrenko'), 'AM');
      // A non-BMP first letter must come back as ONE whole code point, not
      // half a surrogate pair. `substring(0, 1)` would return an unrenderable
      // lone surrogate here and agree with `runes.first` on every Cyrillic
      // seed row — which is exactly why the wrong one would never be caught by
      // a fixture drawn from real data.
      expect('𝒜lice'.substring(0, 1).length, 1);
      expect(FavoriteMapper.initialsOf('𝒜lice Bee').runes.first, 0x1D49C);
    });
  });

  group('FavoriteMapper — kind discriminator', () {
    test('a master row maps to FavoriteKind.master and a master target', () {
      final FavoriteItem item = _masters(<FavoriteMasterResponse>[
        _masterDto(),
      ]).single;

      expect(item.kind, FavoriteKind.master);
      expect(item.isMaster, isTrue);
      expect(item.target.type.name, 'master');
    });

    test('a salon row maps to FavoriteKind.salon and a salon target', () {
      final FavoriteItem item = _salons(<FavoriteSalonResponse>[
        _salonDto(),
      ]).single;

      expect(item.kind, FavoriteKind.salon);
      expect(item.isMaster, isFalse);
      expect(item.target.type.name, 'salon');
    });

    test('neither DTO can produce a salonName — isAffiliated is false', () {
      // Pins the documented contract gap. The day a DTO grows `salonName`,
      // THIS test is what tells whoever wires it that the affiliation line and
      // the address suppression it gates are now reachable.
      expect(
        _masters(<FavoriteMasterResponse>[_masterDto()]).single.isAffiliated,
        isFalse,
      );
    });
  });
}
