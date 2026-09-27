// Phase 346 — composeSettlementLabel: pure unit cases for the row label,
// including the «м.»/«с.» type prefixes, the «обл.» oblast abbreviation and the Kyiv
// degenerate case.

import 'package:beautica_mobile/features/location/domain/settlement.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The nouns come from the real UA ARB, so the test tracks the shipped copy.
  final AppLocalizations uk = lookupAppLocalizations(const Locale('uk'));

  String label(Settlement s) => composeSettlementLabel(
    s,
    hromadaWord: uk.settlementHromadaWord,
    oblastWord: uk.settlementOblastAbbrev,
    cityPrefix: uk.settlementCityPrefix,
    villagePrefix: uk.settlementVillagePrefix,
  );

  group('composeSettlementLabel', () {
    test('the UA oblast abbreviation is «обл.»', () {
      expect(uk.settlementOblastAbbrev, 'обл.');
    });

    test('a settlement in a real oblast gets «обл.» after the oblast', () {
      expect(
        label(
          const Settlement(
            id: 's-lviv',
            name: 'Львів',
            oblastName: 'Львівська',
            settlementType: kSettlementTypeCity,
          ),
        ),
        'м. Львів, Львівська обл.',
      );
    });

    test('a hromada-disambiguated row ends with «обл.»', () {
      expect(
        label(
          const Settlement(
            id: 's-myk',
            name: 'Миколаївка',
            oblastName: 'Вінницька',
            hromadaName: 'Пищанська',
            settlementType: kSettlementTypeVillage,
          ),
        ),
        'с. Миколаївка, Пищанська громада, Вінницька обл.',
      );
    });

    test('the city of Київ is «м. Київ» — no «обл.», no repeated segment', () {
      final String kyiv = label(
        const Settlement(
          id: 's-kyiv',
          name: 'Київ',
          oblastName: 'Київ',
          settlementType: kSettlementTypeCity,
        ),
      );
      expect(kyiv, 'м. Київ');
      expect(kyiv, isNot(contains(uk.settlementOblastAbbrev)));
    });

    test(
      'a VILLAGE named Київ in Миколаївська is «с. Київ, Миколаївська обл.»',
      () {
        expect(
          label(
            const Settlement(
              id: 's-kyiv-village',
              name: 'Київ',
              oblastName: 'Миколаївська',
              settlementType: kSettlementTypeVillage,
            ),
          ),
          'с. Київ, Миколаївська обл.',
        );
      },
    );

    test('the UA city prefix is «м.»', () {
      expect(uk.settlementCityPrefix, 'м.');
    });

    test('a CITY is prefixed with «м.»', () {
      expect(
        label(
          const Settlement(
            id: 's-zp',
            name: 'Запоріжжя',
            oblastName: 'Запорізька',
            settlementType: kSettlementTypeCity,
          ),
        ),
        'м. Запоріжжя, Запорізька обл.',
      );
    });

    test('the UA village prefix is «с.»', () {
      expect(uk.settlementVillagePrefix, 'с.');
    });

    test('a VILLAGE is prefixed with «с.»', () {
      expect(
        label(
          const Settlement(
            id: 's-v',
            name: 'Іванівка',
            oblastName: 'Полтавська',
            settlementType: kSettlementTypeVillage,
          ),
        ),
        'с. Іванівка, Полтавська обл.',
      );
    });

    test('a SETTLEMENT (селище) is not prefixed', () {
      expect(
        label(
          const Settlement(
            id: 's-s',
            name: 'Козин',
            oblastName: 'Київська',
            settlementType: kSettlementTypeSettlement,
          ),
        ),
        'Козин, Київська обл.',
      );
    });

    test(
      'a row with no type is not prefixed — never guessed from the name',
      () {
        expect(
          label(
            const Settlement(id: 's-n', name: 'Львів', oblastName: 'Львівська'),
          ),
          'Львів, Львівська обл.',
        );
      },
    );

    test('a hromada-disambiguated VILLAGE reads «с. …, … громада, … обл.»', () {
      expect(
        label(
          const Settlement(
            id: 's-iv',
            name: 'Іванівка',
            oblastName: 'Полтавська',
            hromadaName: 'Шишацька',
            settlementType: kSettlementTypeVillage,
          ),
        ),
        'с. Іванівка, Шишацька громада, Полтавська обл.',
      );
    });

    for (final String type in <String>['city', 'HAMLET', 'CITY\u202E', '']) {
      test('an unknown type ${type.runes.toList()} gets NO prefix', () {
        expect(
          label(
            Settlement(
              id: 's-u',
              name: 'Львів',
              oblastName: 'Львівська',
              settlementType: type,
            ),
          ),
          'Львів, Львівська обл.',
        );
      });
    }

    test('an EMPTY localised prefix is skipped — no leading space', () {
      const Settlement lviv = Settlement(
        id: 's-lviv',
        name: 'Львів',
        oblastName: 'Львівська',
        settlementType: kSettlementTypeCity,
      );
      final String out = composeSettlementLabel(
        lviv,
        hromadaWord: uk.settlementHromadaWord,
        oblastWord: uk.settlementOblastAbbrev,
        cityPrefix: '',
        villagePrefix: '',
      );
      expect(out, 'Львів, Львівська обл.');
      expect(out, isNot(startsWith(' ')));
    });

    test('English ships NO type prefix and keeps «Oblast»', () {
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
      expect(en.settlementCityPrefix, isEmpty);
      expect(en.settlementVillagePrefix, isEmpty);
      expect(
        composeSettlementLabel(
          const Settlement(
            id: 's-v',
            name: 'Іванівка',
            oblastName: 'Полтавська',
            settlementType: kSettlementTypeVillage,
          ),
          hromadaWord: en.settlementHromadaWord,
          oblastWord: en.settlementOblastAbbrev,
          cityPrefix: en.settlementCityPrefix,
          villagePrefix: en.settlementVillagePrefix,
        ),
        'Іванівка, Полтавська Oblast',
      );
    });

    test('a CITY whose name sanitises to nothing leaves no bare «м.»', () {
      expect(
        label(
          const Settlement(
            id: 's-e',
            name: '  ',
            oblastName: 'Львівська',
            settlementType: kSettlementTypeCity,
          ),
        ),
        'Львівська обл.',
      );
    });

    test('an oblast that sanitises to nothing drops the whole segment — no '
        'dangling «обл.»', () {
      expect(
        label(const Settlement(id: 's-x', name: 'Львів', oblastName: '   ')),
        'Львів',
      );
    });
  });

  group('Settlement.fromResponse', () {
    test(
      'a NON-string settlementType parses to null (no throw, no prefix)',
      () {
        late final Settlement s;
        expect(
          () => s = Settlement.fromResponse(<String, dynamic>{
            'settlementId': 's-2',
            'nameUk': 'Полтава',
            'settlementType': 42,
            'oblastNameUk': 'Полтавська',
            'hromadaNameUk': null,
          }),
          returnsNormally,
        );
        expect(s.settlementType, isNull);
        expect(label(s), 'Полтава, Полтавська обл.');
      },
    );

    test('maps the wire settlementType, so a CITY row can be prefixed', () {
      final Settlement s = Settlement.fromResponse(<String, dynamic>{
        'settlementId': 's-1',
        'nameUk': 'Полтава',
        'settlementType': 'CITY',
        'oblastNameUk': 'Полтавська',
        'hromadaNameUk': null,
      });
      expect(s.settlementType, kSettlementTypeCity);
      expect(label(s), 'м. Полтава, Полтавська обл.');
    });
  });
}
