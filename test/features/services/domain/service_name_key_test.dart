// serviceNameKey — client mirror of backend 464 `canonicalName` + lower().

import 'package:beautica_mobile/features/services/domain/service_name_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('serviceNameKey', () {
    test('internal space runs, edge spaces and case all canonicalise to one '
        'key', () {
      expect(
        serviceNameKey('Манікюр  класичний'),
        serviceNameKey(' манікюр КЛАСИЧНИЙ '),
      );
      expect(serviceNameKey('Манікюр  класичний'), 'манікюр класичний');
    });

    test('NBSP and other NFKC-folded Unicode spaces count as spaces', () {
      expect(
        serviceNameKey('Манікюр\u00A0\u202Fкласичний'),
        'манікюр класичний',
      );
      expect(
        serviceNameKey('\u3000Манікюр\u2009класичний'),
        'манікюр класичний',
      );
    });

    test('full-width ASCII folds to ASCII', () {
      expect(serviceNameKey('ＳＰＡ\u3000２'), 'spa 2');
    });

    test('№ is kept verbatim (backend nfkcKeepingNumeroSign)', () {
      expect(serviceNameKey('Манікюр №2'), 'манікюр №2');
    });

    test('a different name stays a different key', () {
      expect(
        serviceNameKey('Манікюр класичний'),
        isNot(serviceNameKey('Манікюр авторський')),
      );
    });

    test('blank is empty', () {
      expect(serviceNameKey('   '), isEmpty);
      expect(serviceNameKey(''), isEmpty);
    });
  });
}
