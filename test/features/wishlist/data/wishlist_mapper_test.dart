// Phase 237 — [WishlistMapper], extended by phases 238 + 239.
//
// PHASE 239 REVERSED PART OF PHASE 237's RULE, AND THIS FILE PINS THE SEAM
// ---------------------------------------------------------------------------
// Phase 237 shipped "the backend formats the band and this app NEVER
// re-derives it". By explicit user decision that now holds for the
// `priceDisplay` FIELD only — the mapper still carries the wire string across
// byte-identical, and still does not format. What changed is that the mapper
// additionally carries `priceType`/`priceMin`/`priceMax`, and
// `WishlistService.priceLabel` (the ONLY thing a render site may draw)
// re-derives a RANGE through the SHARED `formatBookingPrice`.
//
// So every price case here asserts BOTH:
//   • `priceDisplay` — unchanged from the wire, on every path, and
//   • `priceLabel`   — what the two wish-list surfaces actually render.
// Asserting only the first would let a mapper that silently swallowed
// `priceMin` pass; asserting only the second would let one that mangled the
// wire string pass. `priceLabel`'s own edge behaviour (non-finite floors,
// collapsing ceilings) is pinned in `../domain/wishlist_service_test.dart`;
// what is under test HERE is the wiring from the DTO onto those three fields.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/wishlist/data/wishlist_mapper.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:flutter_test/flutter_test.dart';

api.FavoriteServiceResponse _dto({
  String? masterServiceId = 'ms-1',
  String? masterId = 'm-1',
  String? serviceName = 'Нарощування вій — класика 2D',
  String? firstName = 'Олена',
  String? lastName = 'Ковальчук',
  String? avatarUrl = 'https://cdn.example/av.png',
  int? durationMinutes = 60,
  String? priceDisplay = '800 ₴',
  // The three price fields phase 239 added. Typed `num?` on the wire exactly
  // as the generated DTO types them — a JSON integer decodes to `int`, which
  // is why the mapper must call `.toDouble()` rather than cast.
  api.FavoriteServiceResponsePriceTypeEnum? priceType,
  num? priceMin,
  num? priceMax,
}) {
  return api.FavoriteServiceResponse(
    (api.FavoriteServiceResponseBuilder b) => b
      ..masterServiceId = masterServiceId
      ..masterId = masterId
      ..serviceName = serviceName
      ..masterFirstName = firstName
      ..masterLastName = lastName
      ..masterAvatarUrl = avatarUrl
      ..durationMinutes = durationMinutes
      ..priceDisplay = priceDisplay
      ..priceType = priceType
      ..priceMin = priceMin
      ..priceMax = priceMax,
  );
}

void main() {
  group('should_mapAllFields_when_dtoIsComplete', () {
    test('every field lands on the domain model', () {
      final WishlistService s = WishlistMapper.fromDto(_dto());

      expect(s.masterServiceId, 'ms-1');
      expect(s.masterId, 'm-1');
      expect(s.serviceName, 'Нарощування вій — класика 2D');
      expect(s.masterName, 'Олена Ковальчук');
      expect(s.masterAvatarUrl, 'https://cdn.example/av.png');
      expect(s.durationMinutes, 60);
      expect(s.priceDisplay, '800 ₴');
      // No priceType on the wire ⇒ FIXED, and FIXED renders the wire string.
      expect(s.isRangePrice, isFalse);
      expect(s.priceMin, isNull);
      expect(s.priceMax, isNull);
      expect(s.priceLabel, '800 ₴');
      // The favorite key is the SERVICE id, never the master id — keying it on
      // masterId would remove the wrong favorite and still return 204.
      expect(s.favoriteTargetId, 'ms-1');
    });

    test('a page maps in wire order — the backend ranks it', () {
      final List<WishlistService> out =
          WishlistMapper.fromDtoList(<api.FavoriteServiceResponse>[
            _dto(masterServiceId: 'a'),
            _dto(masterServiceId: 'b'),
            _dto(masterServiceId: 'c'),
          ]);
      expect(
        out.map((WishlistService s) => s.masterServiceId).toList(),
        <String>['a', 'b', 'c'],
      );
    });
  });

  group('should_keepPriceDisplayVerbatim_when_anyPriceShape', () {
    // The `priceDisplay` FIELD is still carried byte-identical on every path —
    // phase 239 changed what is RENDERED (`priceLabel`), not what is stored.
    // Both spellings the contract has carried are asserted, so the test pins
    // "unchanged" rather than "matches one particular format" — a mapper that
    // normalised either one into the other would fail on the other case.
    for (final String band in <String>[
      'від 600 до 900 ₴',
      '600–900 ₴',
      '12500–25000 ₴',
    ]) {
      test('«$band» arrives byte-identical', () {
        expect(
          WishlistMapper.fromDto(_dto(priceDisplay: band)).priceDisplay,
          band,
        );
      });
    }

    test('the mapper itself still formats NOTHING', () {
      // A RANGE row whose `priceDisplay` is absent keeps an EMPTY
      // `priceDisplay` — the mapper does not fill the wire field in from the
      // bounds. The band appears on `priceLabel`, which is where the
      // re-derivation lives; keeping the two apart is what stops a second money
      // formatter growing in the data layer.
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceDisplay: null,
          priceType: api.FavoriteServiceResponsePriceTypeEnum.RANGE,
          priceMin: 600,
          priceMax: 900,
        ),
      );
      expect(s.priceDisplay, '');
      expect(s.priceLabel, '600–900 ₴');
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 239 — priceType / priceMin / priceMax are carried across, and
  // `priceLabel` resolves them.
  // ---------------------------------------------------------------------------
  group('should_renderWireStringVerbatim_when_priceIsFixed', () {
    test('a FIXED row passes priceDisplay through UNCHANGED', () {
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceDisplay: '800 ₴',
          priceType: api.FavoriteServiceResponsePriceTypeEnum.FIXED,
          priceMin: 800,
        ),
      );

      expect(s.isRangePrice, isFalse);
      expect(s.priceMin, 800.0, reason: 'carried across even for FIXED');
      // The whole FIXED decision: there is nothing to fix about «800 ₴», so the
      // floor is NOT re-formatted over the top of it. A mapper (or a
      // `priceLabel`) that ran FIXED through `formatBookingPrice` would produce
      // the same digits here but would fork the rounding on any non-integer
      // price — this asserts the wire string wins.
      expect(s.priceLabel, '800 ₴');
    });

    test('an unusual FIXED wire string is not normalised either', () {
      // «Від 1 200 ₴» is not a shape this app's own formatter can produce, so a
      // verbatim pass-through is the only way it survives.
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceDisplay: 'Від 1 200 ₴',
          priceType: api.FavoriteServiceResponsePriceTypeEnum.FIXED,
          priceMin: 1200,
        ),
      );
      expect(s.priceLabel, 'Від 1 200 ₴');
    });
  });

  group('should_renderEnDashBand_when_priceIsRange', () {
    test('RANGE with both bounds becomes the app\'s own band', () {
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          // The LONG backend form. It must NOT be what renders — that is the
          // whole measured reason phase 239 reversed the rule (~138 dp needed
          // vs 126 dp available on the compact card).
          priceDisplay: 'від 600 до 900 ₴',
          priceType: api.FavoriteServiceResponsePriceTypeEnum.RANGE,
          priceMin: 600,
          priceMax: 900,
        ),
      );

      expect(s.isRangePrice, isTrue);
      expect(s.priceMin, 600.0);
      expect(s.priceMax, 900.0);
      // The field is still the wire string…
      expect(s.priceDisplay, 'від 600 до 900 ₴');
      // …and the RENDERED label is the en-dash band, from the shared formatter.
      expect(s.priceLabel, '600–900 ₴');
      expect(
        s.priceLabel,
        isNot(contains('від')),
        reason:
            'the long backend form reached the render label — it does not fit '
            'the 126 dp compact card and the redesign forbids an ellipsis',
      );
    });

    test('the en-dash is U+2013, not an ASCII hyphen', () {
      // The app convention is the EN-DASH band; `ServicePriceDisplay` uses
      // ' - ' deliberately and the two must not be confused (see
      // `booking_price_labels.dart`'s header).
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceType: api.FavoriteServiceResponsePriceTypeEnum.RANGE,
          priceMin: 600,
          priceMax: 900,
        ),
      );
      expect(s.priceLabel.contains('–'), isTrue);
      expect(s.priceLabel.contains('-'), isFalse);
    });
  });

  group('should_fallBackToWireString_when_rangeFloorIsMissing', () {
    test('RANGE with a NULL priceMin renders priceDisplay', () {
      // A broken payload, but the backend still sent something a human can
      // read. Falling back to it states something TRUE in the wrong house
      // style; falling back to «—» would throw away a price the client can
      // actually use.
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceDisplay: 'від 600 до 900 ₴',
          priceType: api.FavoriteServiceResponsePriceTypeEnum.RANGE,
          priceMin: null,
          priceMax: 900,
        ),
      );

      expect(s.isRangePrice, isTrue);
      expect(s.priceMin, isNull);
      expect(s.priceMax, 900.0, reason: 'the ceiling is still carried across');
      expect(s.priceLabel, 'від 600 до 900 ₴');
    });

    test('a missing floor AND a missing priceDisplay renders nothing', () {
      // `priceLabel` is empty ⇒ `showsPrice` is false ⇒ both surfaces omit the
      // pill entirely. An empty recessed well announcing an absent figure is
      // the failure mode this avoids.
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceDisplay: null,
          priceType: api.FavoriteServiceResponsePriceTypeEnum.RANGE,
          priceMin: null,
        ),
      );
      expect(s.priceLabel, '');
    });
  });

  group('should_readAsFixed_when_priceTypeIsAbsent', () {
    test('no priceType + both bounds ⇒ FIXED, never a fabricated band', () {
      // Defaulting an ABSENT enum to RANGE would send a single-price row down
      // the band path and print its one price as a FLOOR — «600 ₴» would
      // silently start meaning "from 600". The fallback that renders the
      // backend's own string is always safe; this is the direction that is not.
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceDisplay: '600 ₴',
          priceType: null,
          priceMin: 600,
          priceMax: 900,
        ),
      );

      expect(s.isRangePrice, isFalse);
      expect(s.priceLabel, '600 ₴');
      expect(
        s.priceLabel,
        isNot('600–900 ₴'),
        reason:
            'an absent priceType was read as RANGE — a FIXED price would be '
            'restated as the floor of a band the master never set',
      );
    });

    test('an explicit FIXED and an absent priceType agree', () {
      expect(
        WishlistMapper.fromDto(
          _dto(
            priceType: api.FavoriteServiceResponsePriceTypeEnum.FIXED,
            priceMin: 600,
            priceMax: 900,
          ),
        ).isRangePrice,
        WishlistMapper.fromDto(
          _dto(priceType: null, priceMin: 600, priceMax: 900),
        ).isRangePrice,
      );
    });
  });

  group('should_acceptIntegerBounds_when_jsonCarriesWholeNumbers', () {
    // THE `as double?` TRAP. The generated DTO types both bounds `num?`, and a
    // JSON integer decodes to `int` — so a bare `dto.priceMin as double?` cast
    // passes on «600.0» and THROWS on «600», i.e. it fails only against the
    // payloads a real backend actually sends. `.toDouble()` is the fix, and
    // these two cases are what make it load-bearing: the `int` case is the one
    // that regresses.
    test('an INT priceMin/priceMax maps without throwing', () {
      const int intMin = 600;
      const int intMax = 900;
      expect(
        intMin,
        isA<int>(),
        reason: 'the fixture must be an int, not 600.0',
      );
      expect(intMax, isA<int>());

      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceType: api.FavoriteServiceResponsePriceTypeEnum.RANGE,
          priceMin: intMin,
          priceMax: intMax,
        ),
      );

      expect(s.priceMin, 600.0);
      expect(s.priceMax, 900.0);
      expect(s.priceMin, isA<double>());
      expect(s.priceMax, isA<double>());
      expect(s.priceLabel, '600–900 ₴');
    });

    test('a DOUBLE priceMin/priceMax maps to the identical label', () {
      // The case a broken `as double?` cast would ALSO pass, kept beside the
      // int case so the pair reads as "both wire shapes, one result".
      const double dblMin = 600.0;
      const double dblMax = 900.0;
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceType: api.FavoriteServiceResponsePriceTypeEnum.RANGE,
          priceMin: dblMin,
          priceMax: dblMax,
        ),
      );

      expect(s.priceMin, 600.0);
      expect(s.priceLabel, '600–900 ₴');
    });

    test('a fractional bound is rounded by the shared formatter, not here', () {
      // The mapper stores what arrived; `formatBookingPrice`'s
      // `toStringAsFixed(0)` owns the rounding. Splitting it any other way
      // would fork the rounding away from every other money surface.
      final WishlistService s = WishlistMapper.fromDto(
        _dto(
          priceType: api.FavoriteServiceResponsePriceTypeEnum.RANGE,
          priceMin: 600.4,
          priceMax: 899.6,
        ),
      );
      expect(s.priceMin, 600.4, reason: 'stored unrounded');
      expect(s.priceLabel, '600–900 ₴');
    });
  });

  group('should_tolerateNullAvatar', () {
    test('a null avatar maps to null, not to an empty string', () {
      expect(
        WishlistMapper.fromDto(_dto(avatarUrl: null)).masterAvatarUrl,
        isNull,
      );
    });
  });

  group('name joining', () {
    test('one half missing yields no stray space', () {
      expect(WishlistMapper.fromDto(_dto(lastName: null)).masterName, 'Олена');
      expect(
        WishlistMapper.fromDto(_dto(firstName: null)).masterName,
        'Ковальчук',
      );
    });

    test('blank parts are treated as absent', () {
      expect(
        WishlistMapper.fromDto(
          _dto(firstName: '  ', lastName: '  '),
        ).masterName,
        '',
      );
    });
  });

  group('absent-value policy', () {
    test('a missing masterServiceId throws ServerFailure', () {
      expect(
        () => WishlistMapper.fromDto(_dto(masterServiceId: null)),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a missing masterId throws ServerFailure', () {
      expect(
        () => WishlistMapper.fromDto(_dto(masterId: null)),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a missing serviceName is empty, not a failure', () {
      expect(WishlistMapper.fromDto(_dto(serviceName: null)).serviceName, '');
    });

    test('a missing duration is 0 — never a fabricated 60', () {
      expect(
        WishlistMapper.fromDto(_dto(durationMinutes: null)).durationMinutes,
        0,
      );
    });
  });
}
