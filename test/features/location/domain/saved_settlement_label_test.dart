// Phase 346 follow-up (backend phase-330) — the SAVED-locality label.
//
// A saved locality (profile / salon / master read) must read exactly like a
// picked «Населений пункт» row («м. Львів, Львівська обл.»), built by the same
// composeSettlementLabel — and must fall back to today's bare name when the
// read carries no settlement type.

import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/features/location/presentation/saved_settlement_label.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppLocalizations uk = lookupAppLocalizations(const Locale('uk'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  Settlement? saved({
    String? id = 'city-1',
    String? name = 'Львів',
    String? type = kSettlementTypeCity,
    String? hromada,
    String? oblast = 'Львівська',
  }) => Settlement.fromSaved(
    id: id,
    name: name,
    settlementType: type,
    hromadaName: hromada,
    oblastName: oblast,
  );

  group('Settlement.fromSaved', () {
    test('returns null when there is no settlement name', () {
      expect(saved(name: null), isNull);
    });

    test('carries every part, and a null id/oblast as empty strings', () {
      final Settlement? s = saved(id: null, oblast: null, hromada: 'Шишацька');
      expect(s, isNotNull);
      expect(s?.id, '');
      expect(s?.name, 'Львів');
      expect(s?.oblastName, '');
      expect(s?.hromadaName, 'Шишацька');
      expect(s?.settlementType, kSettlementTypeCity);
    });
  });

  group('savedSettlementLabel (UA)', () {
    test('a saved CITY reads exactly as the picker row', () {
      final Settlement? s = saved();
      expect(savedSettlementLabel(uk, s), 'м. Львів, Львівська обл.');
      // Same function as the picker — byte-identical to composeSettlementLabel.
      expect(
        savedSettlementLabel(uk, s),
        composeSettlementLabel(
          s!,
          hromadaWord: uk.settlementHromadaWord,
          oblastWord: uk.settlementOblastAbbrev,
          cityPrefix: uk.settlementCityPrefix,
          villagePrefix: uk.settlementVillagePrefix,
        ),
      );
    });

    test('a saved ambiguous VILLAGE carries its hromada', () {
      expect(
        savedSettlementLabel(
          uk,
          saved(
            name: 'Іванівка',
            type: kSettlementTypeVillage,
            hromada: 'Шишацька',
            oblast: 'Полтавська',
          ),
        ),
        'с. Іванівка, Шишацька громада, Полтавська обл.',
      );
    });

    test('a saved Kyiv drops its self-named region segment', () {
      expect(
        savedSettlementLabel(uk, saved(name: 'Київ', oblast: 'Київ')),
        'м. Київ',
      );
    });

    test('a null settlement type falls back to the BARE name — no oblast, '
        'no prefix, never guessed', () {
      expect(savedSettlementLabel(uk, saved(type: null)), 'Львів');
    });

    test('a TOWN (no prefix yet) still gets its oblast', () {
      expect(
        savedSettlementLabel(
          uk,
          saved(name: 'Буча', type: 'TOWN', oblast: 'Київська'),
        ),
        'Буча, Київська обл.',
      );
    });

    test('a missing oblast drops the segment with no dangling comma', () {
      expect(savedSettlementLabel(uk, saved(oblast: null)), 'м. Львів');
    });

    test('null settlement and an invisible name both yield null', () {
      expect(savedSettlementLabel(uk, null), isNull);
      expect(savedSettlementLabel(uk, saved(name: '\u200B ')), isNull);
      expect(
        savedSettlementLabel(uk, saved(name: '\u200B ', type: null)),
        isNull,
      );
    });

    test('every part is sanitised (the bare fallback too)', () {
      expect(
        savedSettlementLabel(
          uk,
          saved(name: 'Льв\u200Bів', oblast: 'Льві\u202Eвська'),
        ),
        'м. Львів, Львівська обл.',
      );
      expect(
        savedSettlementLabel(uk, saved(name: ' Льв\u200Bів ', type: null)),
        'Львів',
      );
    });
  });

  test('savedSettlementLabel (EN) uses the English words (no prefix)', () {
    expect(
      savedSettlementLabel(en, saved()),
      'Львів, Львівська ${en.settlementOblastAbbrev}',
    );
  });
}
