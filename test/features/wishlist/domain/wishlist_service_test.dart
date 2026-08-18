// Phase 239 — [WishlistService.priceLabel], the ONLY price string either
// wish-list surface may draw.
//
// WHY THIS FILE EXISTS SEPARATELY FROM THE MAPPER'S
// ---------------------------------------------------------------------------
// `wishlist_mapper_test.dart` pins the WIRING — that `priceType`/`priceMin`/
// `priceMax` land on the model at all, and that a JSON integer survives the
// `num → double` coercion. This file pins the RESOLUTION: given a model, what
// string does the render site get.
//
// The distinction matters because `priceLabel` routes RANGE through the SHARED
// `formatBookingPrice` rather than building `'$min–$max ₴'` locally, and the
// entire justification for that routing is the hardening it inherits:
//
//   • `isRenderablePrice` — non-finite, negative (INCLUDING `-0.0`) and
//     exponent-notation magnitudes are refused rather than stringified;
//   • an unrenderable or absent CEILING collapses to the floor alone;
//   • a degenerate band (`max <= min`) collapses to the floor alone.
//
// A locally-written band would have NONE of them and would happily print
// «Infinity ₴» off a `jsonDecode('1e400')`. So these cases are not decoration —
// they ARE the argument for the design, and if they are not asserted here the
// next person to "simplify" `priceLabel` into an interpolation has nothing
// telling them why they must not.
//
// Pure Dart: no widget pumping, no providers.

import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:flutter_test/flutter_test.dart';

/// A wish-list entry with only the price shape varied — every other field is
/// irrelevant to [WishlistService.priceLabel] and is held constant so a failure
/// can only be about money.
WishlistService _entry({
  String priceDisplay = 'від 600 до 900 ₴',
  bool isRangePrice = false,
  double? priceMin,
  double? priceMax,
}) => WishlistService(
  masterServiceId: 'ms-1',
  masterId: 'm-1',
  serviceName: 'Нарощування вій — класика 2D',
  masterName: 'Олена Ковальчук',
  durationMinutes: 60,
  priceDisplay: priceDisplay,
  isRangePrice: isRangePrice,
  priceMin: priceMin,
  priceMax: priceMax,
);

void main() {
  group('should_passWireStringThrough_when_priceIsFixed', () {
    test('FIXED renders priceDisplay verbatim', () {
      expect(_entry(priceDisplay: '800 ₴').priceLabel, '800 ₴');
    });

    test('FIXED ignores the bounds entirely', () {
      // Bounds may be present on a FIXED row (the backend sends `priceMin` for
      // both types). They must not be able to reach the label: re-deriving
      // «600 ₴» from them would fork the rounding away from every other
      // surface for exactly zero gain.
      expect(
        _entry(priceDisplay: '800 ₴', priceMin: 600, priceMax: 900).priceLabel,
        '800 ₴',
      );
    });

    test('FIXED with an EMPTY priceDisplay stays empty', () {
      // A legacy definition carrying no price. Empty means "nothing to show" —
      // it never means zero, and it must not become «0 ₴».
      expect(_entry(priceDisplay: '').priceLabel, '');
      expect(_entry(priceDisplay: '').priceLabel, isNot(contains('0')));
    });

    test('FIXED does NOT fall through to the «—» placeholder', () {
      // `priceUnavailableLabel` is `formatBookingPrice`'s answer for an
      // unstatable FLOOR. A FIXED row never enters that function, so a blank
      // price must render as blank, not as an em-dash that would look like a
      // failed lookup on a card that shows «—» nowhere else.
      expect(_entry(priceDisplay: '').priceLabel, isNot(priceUnavailableLabel));
    });
  });

  group('should_renderEnDashBand_when_priceIsRange', () {
    test('a two-bound RANGE becomes the app\'s own band', () {
      final WishlistService s = _entry(
        isRangePrice: true,
        priceMin: 600,
        priceMax: 900,
      );
      expect(s.priceLabel, '600–900 ₴');
    });

    test('the long backend form never reaches the label', () {
      // The measured reason phase 239 reversed phase 237's rule: «від 600 до
      // 900 ₴» is ~138 dp and the compact card has 126 dp, and the redesign
      // forbids an ellipsis.
      final WishlistService s = _entry(
        priceDisplay: 'від 600 до 900 ₴',
        isRangePrice: true,
        priceMin: 600,
        priceMax: 900,
      );
      expect(s.priceLabel, isNot(s.priceDisplay));
      expect(s.priceLabel, isNot(contains('від')));
      expect(
        s.priceDisplay,
        'від 600 до 900 ₴',
        reason: 'the wire string itself is still stored unchanged',
      );
    });

    test('it is byte-identical to the shared formatter\'s own output', () {
      // Pins the ROUTING, not just the digits: a hand-rolled
      // `'$min–$max ₴'` that happened to agree on this input would still be a
      // second money formatter. Comparing against `formatBookingPrice` makes
      // divergence — not merely wrongness — the failure.
      expect(
        _entry(isRangePrice: true, priceMin: 600, priceMax: 900).priceLabel,
        formatBookingPrice(price: 600, priceMax: 900),
      );
    });

    test('a wide band keeps whole hryvnia, no decimals, one suffix', () {
      expect(
        _entry(isRangePrice: true, priceMin: 12500, priceMax: 25000).priceLabel,
        '12500–25000 ₴',
      );
    });
  });

  group('should_collapseToFloor_when_ceilingCarriesNoInformation', () {
    test('a NULL ceiling renders the floor alone', () {
      expect(_entry(isRangePrice: true, priceMin: 600).priceLabel, '600 ₴');
    });

    test('a DEGENERATE band (min == max) collapses', () {
      // «600–600 ₴» carries no more information than «600 ₴» and reads as a
      // rendering bug.
      expect(
        _entry(isRangePrice: true, priceMin: 600, priceMax: 600).priceLabel,
        '600 ₴',
      );
    });

    test('an INVERTED band (max < min) collapses to the floor', () {
      // «900–600 ₴» would be worse than useless if a bad row ever reached the
      // client. The floor is the figure that survives.
      expect(
        _entry(isRangePrice: true, priceMin: 900, priceMax: 600).priceLabel,
        '900 ₴',
      );
    });

    test('an INFINITE ceiling collapses instead of printing «Infinity»', () {
      // Reachable from the wire: `jsonDecode('1e400')` yields
      // `double.infinity` WITHOUT throwing.
      expect(
        _entry(
          isRangePrice: true,
          priceMin: 600,
          priceMax: double.infinity,
        ).priceLabel,
        '600 ₴',
      );
    });

    test('a NaN ceiling collapses', () {
      expect(
        _entry(
          isRangePrice: true,
          priceMin: 600,
          priceMax: double.nan,
        ).priceLabel,
        '600 ₴',
      );
    });

    test(
      'a NEGATIVE ceiling collapses rather than colliding with the dash',
      () {
        // «600–-300 ₴» is unreadable; the minus sign fights the en-dash.
        expect(
          _entry(isRangePrice: true, priceMin: 600, priceMax: -300).priceLabel,
          '600 ₴',
        );
      },
    );

    test('an exponent-magnitude ceiling collapses', () {
      // `(1e21).toStringAsFixed(0)` is `'1e+21'` — plain digits stop there.
      expect(
        _entry(isRangePrice: true, priceMin: 600, priceMax: 1e21).priceLabel,
        '600 ₴',
      );
    });
  });

  group('should_renderPlaceholder_when_rangeFloorIsUnstatable', () {
    // A floor that exists and is GARBAGE is the one case where there is
    // genuinely nothing honest to print — there is no floor left to fall back
    // TO. The label is the neutral «—», with NO «₴» suffix: appending the
    // currency would assert a hryvnia amount the app does not have.
    for (final (String name, double floor) in <(String, double)>[
      ('positive infinity', double.infinity),
      ('negative infinity', double.negativeInfinity),
      ('NaN', double.nan),
      ('a negative floor', -500),
      ('negative ZERO (−0.0 ≥ 0 is true — the `isNegative` case)', -0.0),
      ('an exponent magnitude (1e21)', 1e21),
    ]) {
      test('$name renders «—»', () {
        final WishlistService s = _entry(
          isRangePrice: true,
          priceMin: floor,
          priceMax: 900,
        );
        expect(s.priceLabel, priceUnavailableLabel);
        expect(s.priceLabel, '—');
        expect(
          s.priceLabel,
          isNot(contains(bookingPriceCurrencySuffix)),
          reason:
              'the placeholder must carry no currency claim — «— ₴» would '
              'assert a hryvnia amount that is not known',
        );
      });
    }

    test('the fallback is priceDisplay ONLY when the floor is ABSENT', () {
      // The seam this pair exists to pin, and it is easy to get backwards:
      //   • floor missing  ⇒ the backend still sent a readable long form, so
      //     show it (wrong house style beats no information);
      //   • floor garbage  ⇒ «—» (there is no honest figure to state).
      final WishlistService absent = _entry(
        priceDisplay: 'від 600 до 900 ₴',
        isRangePrice: true,
        priceMin: null,
        priceMax: 900,
      );
      final WishlistService garbage = _entry(
        priceDisplay: 'від 600 до 900 ₴',
        isRangePrice: true,
        priceMin: double.infinity,
        priceMax: 900,
      );

      expect(absent.priceLabel, 'від 600 до 900 ₴');
      expect(garbage.priceLabel, '—');
      expect(
        absent.priceLabel,
        isNot(garbage.priceLabel),
        reason:
            'an absent floor and an unstatable one are different states and '
            'must not be collapsed into one branch',
      );
    });
  });

  group('favoriteTargetId', () {
    test('is the masterServiceId, never the masterId', () {
      // Keying the un-favourite on `masterId` would remove the WRONG favorite
      // and still return 204 — a silent, unobservable data loss.
      final WishlistService s = _entry();
      expect(s.favoriteTargetId, s.masterServiceId);
      expect(s.favoriteTargetId, isNot(s.masterId));
    });

    test('is the serviceDefId on a SALON row, never salonId', () {
      const WishlistService s = WishlistService(
        sourceType: WishlistSourceType.salon,
        salonId: 'salon-1',
        serviceDefId: 'def-1',
        serviceName: 'Ламінування вій',
        durationMinutes: 60,
        priceDisplay: '800 ₴',
      );
      expect(s.favoriteTargetId, 'def-1');
      expect(s.favoriteTargetId, isNot(s.salonId));
    });
  });

  // ---------------------------------------------------------------------------
  // Phase F — the SALON arm's priceLabel: verbatim on EVERY shape, unlike the
  // MASTER arm's RANGE reformat above.
  // ---------------------------------------------------------------------------
  group('should_renderVerbatim_when_sourceTypeIsSalon', () {
    WishlistService salonEntry({
      String priceDisplay = 'від 600 до 900 ₴',
      bool isRangePrice = false,
      double? priceMin,
      double? priceMax,
    }) => WishlistService(
      sourceType: WishlistSourceType.salon,
      salonId: 'salon-1',
      serviceDefId: 'def-1',
      serviceName: 'Ламінування вій',
      durationMinutes: 60,
      priceDisplay: priceDisplay,
      isRangePrice: isRangePrice,
      priceMin: priceMin,
      priceMax: priceMax,
    );

    test('a RANGE-shaped salon row does NOT get the en-dash reformat', () {
      // The MASTER-row behaviour this file pins above — the whole reason a
      // SALON row needs its own group: it must NOT inherit it.
      final WishlistService s = salonEntry(
        priceDisplay: 'від 600 до 900 ₴',
        isRangePrice: true,
        priceMin: 600,
        priceMax: 900,
      );
      expect(s.priceLabel, 'від 600 до 900 ₴');
      expect(
        s.priceLabel,
        isNot(contains('–')),
        reason:
            'a SALON row must agree byte-for-byte with the catalogue tile it '
            'was favourited from, which prints the backend long form',
      );
    });

    test(
      'even a floor/ceiling pair that WOULD collapse on a MASTER row is ignored',
      () {
        // Proves priceLabel short-circuits on sourceType BEFORE it ever looks
        // at isRangePrice/priceMin/priceMax — a garbage floor here must not
        // produce the MASTER arm's «—» placeholder.
        final WishlistService s = salonEntry(
          priceDisplay: 'Ціна за запитом',
          isRangePrice: true,
          priceMin: double.infinity,
          priceMax: 900,
        );
        expect(s.priceLabel, 'Ціна за запитом');
      },
    );

    test(
      'a FIXED-shaped salon row renders verbatim too (no behaviour change)',
      () {
        final WishlistService s = salonEntry(priceDisplay: '800 ₴');
        expect(s.priceLabel, '800 ₴');
      },
    );

    test('an EQUAL-BOUNDS salon row is NOT collapsed to the single figure — '
        'this is the specific case a MASTER-row-style reformat would break', () {
      // The measured reason a SALON row cannot share the MASTER arm's
      // reformat (see the file header's "Why a SALON row skips the RANGE
      // reformat entirely"): the backend renders an equal-bounds band
      // (`price_max == base_price`) as «від 600 до 600 ₴», but THIS APP'S
      // OWN `formatBookingPrice` collapses `min == max` to the bare floor
      // («600 ₴» — see `should_collapseToFloor_when_ceilingCarriesNoInformation`
      // above). Every OTHER salon-arm case in this group uses DIFFERING
      // bounds (600/900), which would also fail if routed through
      // `formatBookingPrice` (producing «600–900 ₴» instead of the long
      // form) — but a differing-bounds fixture cannot distinguish "still
      // verbatim" from "collapsed the same way a MASTER row's degenerate
      // band collapses", because collapse-to-floor and the equal-bounds
      // wire string share nothing to compare against by accident. THIS
      // fixture is the one where a regression that quietly routed salon
      // rows through the MASTER reformat would produce a DIFFERENT,
      // silently-wrong number rather than merely a differently-shaped one.
      final WishlistService s = salonEntry(
        priceDisplay: 'від 600 до 600 ₴',
        isRangePrice: true,
        priceMin: 600,
        priceMax: 600,
      );
      expect(s.priceLabel, 'від 600 до 600 ₴');
      expect(
        s.priceLabel,
        isNot('600 ₴'),
        reason:
            'formatBookingPrice(600, 600) collapses to the bare floor — if '
            'priceLabel ever routed a salon row through it, THIS is the '
            'string it would silently produce instead',
      );
    });
  });

  group('the new price fields participate in value equality', () {
    // Riverpod hands the list straight to `ref.watch`, so a model whose `==`
    // ignored the bounds would let a price change slip through without a
    // rebuild — the entry would keep rendering its old band.
    test('two entries differing only in priceMin are NOT equal', () {
      expect(
        _entry(isRangePrice: true, priceMin: 600, priceMax: 900),
        isNot(_entry(isRangePrice: true, priceMin: 700, priceMax: 900)),
      );
    });

    test('two entries differing only in isRangePrice are NOT equal', () {
      expect(
        _entry(isRangePrice: true, priceMin: 600),
        isNot(_entry(isRangePrice: false, priceMin: 600)),
      );
    });

    test('identical entries are equal and share a hashCode', () {
      final WishlistService a = _entry(
        isRangePrice: true,
        priceMin: 600,
        priceMax: 900,
      );
      final WishlistService b = _entry(
        isRangePrice: true,
        priceMin: 600,
        priceMax: 900,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith flips a FIXED row onto the band path', () {
      final WishlistService fixed = _entry(priceDisplay: '800 ₴');
      expect(fixed.priceLabel, '800 ₴');

      final WishlistService ranged = fixed.copyWith(
        isRangePrice: true,
        priceMin: 600,
        priceMax: 900,
      );
      expect(ranged.priceLabel, '600–900 ₴');
      expect(
        fixed.priceLabel,
        '800 ₴',
        reason: 'copyWith must not mutate the original',
      );
    });
  });

  group('isRangePrice is carried, never inferred from priceMax', () {
    test('a RANGE row whose ceiling failed to serialise is still a RANGE', () {
      // The reason the flag is explicit: keying the band on `priceMax != null`
      // would turn this row FIXED and state its FLOOR as if it were the whole
      // price.
      final WishlistService s = _entry(
        priceDisplay: 'від 600 ₴',
        isRangePrice: true,
        priceMin: 600,
      );
      expect(s.isRangePrice, isTrue);
      expect(s.priceLabel, '600 ₴');
      expect(
        s.priceLabel,
        isNot(s.priceDisplay),
        reason: 'it took the RANGE path, not the verbatim FIXED pass-through',
      );
    });
  });
}
