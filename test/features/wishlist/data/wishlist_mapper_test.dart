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

import 'dart:io';

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

/// Phase F — a SALON-arm wire row: `sourceType: SALON`, salon ids set, master
/// ids ALL absent (exactly the shape the backend contract promises).
api.FavoriteServiceResponse _salonDto({
  String? salonId = 'salon-1',
  String? salonName = 'Салон краси «Оксамит»',
  String? salonAvatarUrl = 'https://cdn.example/salon.png',
  String? serviceDefId = 'def-1',
  String? serviceName = 'Ламінування вій',
  int? durationMinutes = 60,
  String? priceDisplay = 'від 600 до 900 ₴',
}) {
  return api.FavoriteServiceResponse(
    (api.FavoriteServiceResponseBuilder b) => b
      ..sourceType = api.FavoriteServiceResponseSourceTypeEnum.SALON
      ..salonId = salonId
      ..salonName = salonName
      ..salonAvatarUrl = salonAvatarUrl
      ..serviceDefId = serviceDefId
      ..serviceName = serviceName
      ..durationMinutes = durationMinutes
      ..priceDisplay = priceDisplay,
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

  // ---------------------------------------------------------------------------
  // Phase F — the SALON arm.
  // ---------------------------------------------------------------------------
  group('should_mapSalonArm_when_sourceTypeIsSalon', () {
    test('every salon field lands on the domain model', () {
      final WishlistService s = WishlistMapper.fromDto(_salonDto());

      expect(s.sourceType, WishlistSourceType.salon);
      expect(s.salonId, 'salon-1');
      expect(s.salonName, 'Салон краси «Оксамит»');
      expect(s.salonAvatarUrl, 'https://cdn.example/salon.png');
      expect(s.serviceDefId, 'def-1');
      expect(s.serviceName, 'Ламінування вій');
      expect(s.durationMinutes, 60);
      expect(
        s.favoriteTargetId,
        'def-1',
        reason:
            'a SALON row un-favourites by serviceDefId, never masterServiceId',
      );
    });

    test('the master fields are ALL null on a SALON row', () {
      final WishlistService s = WishlistMapper.fromDto(_salonDto());

      expect(s.masterServiceId, isNull);
      expect(s.masterId, isNull);
      expect(s.masterName, isNull);
      expect(s.masterAvatarUrl, isNull);
    });

    test(
      'priceDisplay renders VERBATIM even for a RANGE band, unlike a MASTER row',
      () {
        // The Phase 239 MASTER-arm reformat (`priceLabel` → en-dash band via
        // `formatBookingPrice`) must NOT apply here — a SALON row's price
        // must agree byte-for-byte with the catalogue tile it was favourited
        // from, and the backend's own long form is what that tile shows.
        final WishlistService s = WishlistMapper.fromDto(
          _salonDto(priceDisplay: 'від 600 до 900 ₴'),
        );
        expect(s.priceLabel, 'від 600 до 900 ₴');
        expect(s.priceLabel, isNot(contains('–')));
      },
    );

    test('a FIXED-shaped salon price also renders verbatim', () {
      final WishlistService s = WishlistMapper.fromDto(
        _salonDto(priceDisplay: '800 ₴'),
      );
      expect(s.priceLabel, '800 ₴');
    });

    test('a null salonName is carried through as null, not fabricated', () {
      // Mirrors the MASTER arm's masterName policy: the mapper does not
      // invent a placeholder, presentation owns that fallback.
      final WishlistService s = WishlistMapper.fromDto(
        _salonDto(salonName: null),
      );
      expect(s.salonName, isNull);
    });

    test('an absent sourceType is read as MASTER, never SALON', () {
      // Every row shipped before Phase F carried no `sourceType` at all —
      // this is what keeps them reading as the arm they always were.
      final WishlistService s = WishlistMapper.fromDto(_dto());
      expect(s.sourceType, WishlistSourceType.master);
    });
  });

  group('absent-value policy — SALON arm', () {
    test('a missing salonId throws ServerFailure', () {
      expect(
        () => WishlistMapper.fromDto(_salonDto(salonId: null)),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a missing serviceDefId throws ServerFailure', () {
      expect(
        () => WishlistMapper.fromDto(_salonDto(serviceDefId: null)),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Phase F — the landmine fix: `fromDtoList` drops the ONE bad row instead of
  // failing the whole page. `fromDto` (called directly, above) still throws —
  // this is the difference between the two call sites, and it is the whole
  // point of the split.
  // ---------------------------------------------------------------------------
  group('should_dropOneRow_when_fromDtoListHitsAMalformedRow', () {
    test('a malformed MASTER row is dropped; the other rows survive', () {
      final List<WishlistService> out = WishlistMapper.fromDtoList(
        <api.FavoriteServiceResponse>[
          _dto(masterServiceId: 'a'),
          _dto(masterServiceId: null), // malformed — missing masterServiceId
          _dto(masterServiceId: 'c'),
        ],
      );
      expect(
        out.map((WishlistService s) => s.favoriteTargetId).toList(),
        <String>['a', 'c'],
      );
    });

    test('a malformed SALON row is dropped; the other rows survive', () {
      final List<WishlistService> out = WishlistMapper.fromDtoList(
        <api.FavoriteServiceResponse>[
          _salonDto(serviceDefId: 'x'),
          _salonDto(salonId: null), // malformed — missing salonId
          _salonDto(serviceDefId: 'z'),
        ],
      );
      expect(
        out.map((WishlistService s) => s.favoriteTargetId).toList(),
        <String>['x', 'z'],
      );
    });

    test('a MIXED page survives a bad row of EITHER arm', () {
      // The exact shape of the regression this phase fixes: before it, ONE
      // salon row missing its ids threw out of `fromDto`, propagated through
      // `List.map`, and blanked the entire Beauty Passport wish-list section
      // — including every good MASTER row on the same page.
      final List<WishlistService> out = WishlistMapper.fromDtoList(
        <api.FavoriteServiceResponse>[
          _dto(masterServiceId: 'm1'),
          _salonDto(salonId: null), // malformed SALON row
          _salonDto(serviceDefId: 's1'),
          _dto(masterServiceId: null), // malformed MASTER row
          _dto(masterServiceId: 'm2'),
        ],
      );
      expect(
        out.map((WishlistService s) => s.favoriteTargetId).toList(),
        <String>['m1', 's1', 'm2'],
      );
    });

    test(
      'an all-malformed page maps to an empty list, not a thrown Failure',
      () {
        final List<WishlistService> out = WishlistMapper.fromDtoList(
          <api.FavoriteServiceResponse>[
            _dto(masterServiceId: null),
            _salonDto(salonId: null),
          ],
        );
        expect(out, isEmpty);
      },
    );

    test('fromDto called DIRECTLY still throws — only the list drops', () {
      // Pins the split itself: a single-row caller (this test, and any future
      // one) must still see the contract break rather than a silent empty
      // model.
      expect(
        () => WishlistMapper.fromDto(_dto(masterServiceId: null)),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // mobile-security finding — a dropped row must be observable in a RELEASE
  // build, not just in debug.
  //
  // WHY THIS IS PARTLY A STRUCTURAL (SOURCE-SCAN) GUARD, NOT A RUNTIME ASSERT
  // ---------------------------------------------------------------------------
  // `dart:developer`'s `log()` posts a VM-service/Timeline event with no
  // supported test-time interception hook (unlike `debugPrint`, it does not
  // go through `Zone.current.print`), and `kDebugMode` is a compile-time
  // constant that is always `true` under `flutter test` — there is no way to
  // toggle "release mode" from inside a test to observe the gate actually
  // opening. So the *runtime emission itself* is not directly assertable
  // here; what IS assertable, and what the fix is actually about, is that the
  // source no longer wraps the drop-path logging in a `kDebugMode` check.
  // This mirrors the existing structural-guard precedent for a same-shaped
  // problem: `test/features/booking/impeller_circle_shadow_guard_test.dart`
  // (a render artifact Skia/goldens cannot reproduce, so the guard reads raw
  // source instead).
  //
  // The BEHAVIOURAL half (a malformed row is dropped, survivors intact) is
  // already pinned by `should_dropOneRow_when_fromDtoListHitsAMalformedRow`
  // above — not repeated here.
  group('mobile-security — dropped-row logging must survive in release', () {
    late String code;

    setUpAll(() {
      // Package-root-relative — `flutter test`'s cwd is `beautica-mobile/`.
      final File file = File('lib/features/wishlist/data/wishlist_mapper.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Guarded source not found at the expected path.',
      );
      // Comments stripped BEFORE the `kDebugMode` check below — the doc
      // comments explaining this very fix legitimately name `kDebugMode` in
      // prose (e.g. "never gated on kDebugMode"), and a raw substring search
      // over the whole file would flag its own explanation.
      code = _stripLineAndBlockComments(file.readAsStringSync());
    });

    test('the mapper never references kDebugMode — the drop-path log(...) '
        'calls must be unconditional', () {
      expect(
        code.contains('kDebugMode'),
        isFalse,
        reason:
            'A `kDebugMode` gate around the drop-path log(...) means a '
            'malformed row silently vanishes with zero telemetry in a '
            'release build — exactly the mobile-security finding this '
            'guards against. Log unconditionally instead (see '
            '`salon_mapper.dart`\'s drop-logging precedent).',
      );
    });

    test('the guard is not vacuous — the file still declares the two '
        'drop-path log(...) calls it protects', () {
      // Proves the absence above means "fixed", not "the logging was
      // deleted entirely" or "the file moved".
      expect(code.contains("'fromDto(MASTER): missing "), isTrue);
      expect(code.contains("'fromDto(SALON): missing "), isTrue);
    });

    test('neither drop-path log(...) CALL interpolates a row value — only the '
        'arm and the missing FIELD NAME', () {
      // Scoped to the log(...) call arguments specifically (not the whole
      // file — `dto.serviceName` etc. legitimately appear elsewhere in the
      // mapper, e.g. building the returned WishlistService). No PII: the
      // message may say WHICH field is missing ("masterServiceId",
      // "salonId", …) as a literal string, but must never interpolate a
      // value the row actually carried (an id, a service name, a salon
      // name).
      final List<String> logCalls = _logCallArgs(code);
      expect(
        logCalls.length,
        2,
        reason:
            'expected exactly the MASTER-arm and SALON-arm drop-path '
            'log(...) calls — if this count changed, update this guard '
            'deliberately rather than let it silently widen or narrow.',
      );
      for (final String call in logCalls) {
        expect(
          call.contains('dto.'),
          isFalse,
          reason:
              'a drop-path log(...) call must never interpolate a raw '
              'DTO field (row id / service name / salon name) — only the '
              'arm and the missing field NAME as a literal. '
              'Offending call: $call',
        );
      }
    });
  });
}

/// Strips `//` line comments and `/* */` block comments, leaving string
/// literals untouched (unlike the fuller stripper in
/// `impeller_circle_shadow_guard_test.dart`, this guard's checks need to
/// inspect the CONTENTS of the log message string literals, not just code).
String _stripLineAndBlockComments(String src) {
  final StringBuffer buf = StringBuffer();
  int i = 0;
  final int n = src.length;
  while (i < n) {
    final String c = src[i];
    final String next = i + 1 < n ? src[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < n && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i < n && !(src[i] == '*' && i + 1 < n && src[i + 1] == '/')) {
        i++;
      }
      i += 2;
      buf.write(' ');
      continue;
    }
    buf.write(c);
    i++;
  }
  return buf.toString();
}

/// Balanced-parenthesis argument substring of every `log(...)` call in
/// [source]. Mirrors the `_boxDecorationArgs`/`_ctorArgs` precedent in
/// `impeller_circle_shadow_guard_test.dart` — a generic depth-counted
/// extractor so nested parens (string interpolation, ternaries) don't break
/// the match.
List<String> _logCallArgs(String source) {
  final List<String> out = <String>[];
  final RegExp ctor = RegExp(r'\blog\s*\(');
  for (final RegExpMatch m in ctor.allMatches(source)) {
    int depth = 1;
    int j = m.end;
    final int start = j;
    while (j < source.length && depth > 0) {
      final String ch = source[j];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      }
      j++;
    }
    out.add(source.substring(start, j - 1));
  }
  return out;
}
