// Phase 469 — serviceNameHints unit matrix.
//
// D2: the "shared fixture cases" group below is mirrored verbatim by website
// 036 (`src/lib/booking/serviceHint.ts`). Same inputs → same expected strings.
// Change one suite only together with the other.

import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_name_hint.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceHintInput _in(
  String id,
  String displayedName,
  int minutes, {
  String? customName,
}) => ServiceHintInput(
  id: id,
  displayedName: displayedName,
  customName: customName,
  durationMinutes: minutes,
);

/// A shared fixture case: inputs + the exact expected map.
typedef _Fixture = ({
  String name,
  List<ServiceHintInput> items,
  Map<String, String> expected,
});

final List<_Fixture> _sharedFixtures = <_Fixture>[
  (
    name: 'F1 single service — no hint',
    items: <ServiceHintInput>[_in('a', 'Класичний масаж', 60)],
    expected: <String, String>{},
  ),
  (
    name: 'F2 same-name pair 60 + 90 — duration hints',
    items: <ServiceHintInput>[
      _in('a', 'Класичний масаж', 60),
      _in('b', 'Класичний масаж', 90),
    ],
    expected: <String, String>{'a': '1 год', 'b': '1 год 30 хв'},
  ),
  (
    name: 'F3 pair differing only by case and outer spaces — grouped',
    items: <ServiceHintInput>[
      _in('a', 'Класичний масаж', 45),
      _in('b', '  класичний МАСАЖ ', 30),
    ],
    expected: <String, String>{'a': '45 хв', 'b': '30 хв'},
  ),
  (
    name: 'F4 renamed copy — its own name, no hint; sibling alone — no hint',
    items: <ServiceHintInput>[
      _in('a', 'Класичний масаж', 60),
      _in(
        'b',
        'Масаж спини авторський',
        90,
        customName: 'Масаж спини авторський',
      ),
    ],
    expected: <String, String>{},
  ),
  (
    name: 'F5 custom name differs from the displayed name — custom name hint',
    items: <ServiceHintInput>[
      _in('a', 'Класичний масаж', 60, customName: 'Ранковий'),
      _in('b', 'Класичний масаж', 60),
    ],
    expected: <String, String>{'a': 'Ранковий', 'b': '1 год'},
  ),
  (
    name: 'F6 custom name equal to displayed (case/space) — duration hint',
    items: <ServiceHintInput>[
      _in('a', 'Класичний масаж', 60, customName: ' класичний масаж'),
      _in('b', 'Класичний масаж', 90),
    ],
    expected: <String, String>{'a': '1 год', 'b': '1 год 30 хв'},
  ),
  (
    name: 'F7 three copies — every member hinted',
    items: <ServiceHintInput>[
      _in('a', 'Стрижка', 30),
      _in('b', 'Стрижка', 60),
      _in('c', 'Стрижка', 90),
    ],
    expected: <String, String>{'a': '30 хв', 'b': '1 год', 'c': '1 год 30 хв'},
  ),
  (
    name: 'F8 two groups + a unique service in one list',
    items: <ServiceHintInput>[
      _in('a', 'Стрижка', 30),
      _in('b', 'Манікюр', 60),
      _in('c', 'Стрижка', 45),
      _in('d', 'Манікюр', 90),
      _in('e', 'Педикюр', 60),
    ],
    expected: <String, String>{
      'a': '30 хв',
      'c': '45 хв',
      'b': '1 год',
      'd': '1 год 30 хв',
    },
  ),
  (
    name: 'F9 empty list — no hints',
    items: <ServiceHintInput>[],
    expected: <String, String>{},
  ),
];

MasterService _svc(
  String id, {
  required String name,
  String? typeName,
  required int minutes,
}) => MasterService(
  id: id,
  serviceDefId: 'def-$id',
  name: name,
  serviceTypeNameUk: typeName,
  durationMinutes: minutes,
);

void main() {
  group(
    'serviceNameHints — shared fixture cases (mirrored by website 036)',
    () {
      for (final _Fixture f in _sharedFixtures) {
        test(f.name, () {
          expect(serviceNameHints(f.items), f.expected);
        });
      }
    },
  );

  group('serviceNameHints — rule details', () {
    test('duration text comes from DurationMinutes.format, no new format', () {
      final Map<String, String> hints = serviceNameHints(<ServiceHintInput>[
        _in('a', 'X', 135),
        _in('b', 'X', 20),
      ]);
      expect(hints['a'], DurationMinutes.format(135));
      expect(hints['b'], DurationMinutes.format(20));
    });

    test('blank custom name falls back to the duration', () {
      final Map<String, String> hints = serviceNameHints(<ServiceHintInput>[
        _in('a', 'X', 60, customName: '   '),
        _in('b', 'X', 90, customName: ''),
      ]);
      expect(hints, <String, String>{'a': '1 год', 'b': '1 год 30 хв'});
    });
  });

  group('masterServiceNameHints — MasterService adapter', () {
    test('displayed name = custom name, else the type name', () {
      final Map<String, String> hints = masterServiceNameHints(<MasterService>[
        _svc('a', name: '', typeName: 'Класичний масаж', minutes: 60),
        _svc('b', name: '', typeName: 'Класичний масаж', minutes: 90),
        _svc(
          'c',
          name: 'Масаж спини авторський',
          typeName: 'Класичний масаж',
          minutes: 90,
        ),
      ]);
      expect(hints, <String, String>{'a': '1 год', 'b': '1 год 30 хв'});
    });

    test(
      'a custom name equal to the type name groups with type-named rows',
      () {
        final Map<String, String> hints =
            masterServiceNameHints(<MasterService>[
              _svc(
                'a',
                name: 'Класичний масаж',
                typeName: 'Класичний масаж',
                minutes: 60,
              ),
              _svc('b', name: '', typeName: 'Класичний масаж', minutes: 90),
            ]);
        expect(hints, <String, String>{'a': '1 год', 'b': '1 год 30 хв'});
      },
    );
  });
}
