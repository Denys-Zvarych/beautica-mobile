// Phase 431 — RESCHEDULE_LIMIT_REACHED (backend PR #176) envelope decode.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isRescheduleLimitReached', () {
    test('the typed 409 envelope → true', () {
      expect(
        isRescheduleLimitReached(<String, dynamic>{
          'success': false,
          'data': <String, dynamic>{'code': 'RESCHEDULE_LIMIT_REACHED'},
          'message': 'Reschedule limit reached',
        }),
        isTrue,
      );
    });

    // Each malformed shape must return false WITHOUT throwing — a throw here
    // would escape the reschedule mapper and skip every other 409 arm.
    final Map<String, Object?> falseShapes = <String, Object?>{
      'null body': null,
      'string body': 'RESCHEDULE_LIMIT_REACHED',
      'list body': <Object?>[
        <String, dynamic>{'code': 'RESCHEDULE_LIMIT_REACHED'},
      ],
      'non-String-keyed map': <Object, Object?>{
        'data': <String, dynamic>{'code': 'RESCHEDULE_LIMIT_REACHED'},
      },
      'data missing': <String, dynamic>{'success': false},
      'data null': <String, dynamic>{'data': null},
      'data not a map': <String, dynamic>{'data': 'RESCHEDULE_LIMIT_REACHED'},
      'code at the top level, not under data': <String, dynamic>{
        'code': 'RESCHEDULE_LIMIT_REACHED',
      },
      'code missing': <String, dynamic>{'data': <String, dynamic>{}},
      'code not a string (int)': <String, dynamic>{
        'data': <String, dynamic>{'code': 431},
      },
      'code not a string (list)': <String, dynamic>{
        'data': <String, dynamic>{
          'code': <String>['RESCHEDULE_LIMIT_REACHED'],
        },
      },
      'a different code': <String, dynamic>{
        'data': <String, dynamic>{'code': 'CLIENT_BOOKING_CONFLICT'},
      },
      'case-mismatched code': <String, dynamic>{
        'data': <String, dynamic>{'code': 'reschedule_limit_reached'},
      },
    };

    for (final MapEntry<String, Object?> shape in falseShapes.entries) {
      test('${shape.key} → false, no throw', () {
        late bool result;
        expect(
          () => result = isRescheduleLimitReached(shape.value),
          returnsNormally,
        );
        expect(result, isFalse);
      });
    }
  });
}
