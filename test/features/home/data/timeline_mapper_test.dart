// Phase 110 (13.9) wire-up — mobile-qa gap-closure — TIER 1 unit tests for
// [TimelineMapper.fromDtoList].
//
// WHY THIS FILE EXISTS
// --------------------
// Until this wire-up `beautyTimelineProvider` returned `const
// <TimelineEntry>[]` unconditionally — there was no mapper at all, so no
// test exercised the DTO→domain contract `timeline_mapper.dart`'s header
// documents (drop policy / sort policy / bookingId non-coercion policy).
// This file pins every one of those policies — a policy with no test is a
// comment, not a contract (same framing
// `test/features/passport/data/passport_mapper_test.dart` uses, which this
// file's structure mirrors).
//
// Pure Dart: no ProviderScope, no widget tree, no Dio.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/features/home/data/timeline_mapper.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:built_collection/built_collection.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// DTO builders
// ---------------------------------------------------------------------------

api.TimelineItemResponse _row({
  String? bookingId,
  String? categoryKey,
  String? categoryName,
  api.Date? date,
  String? masterId,
  String? serviceName,
}) => api.TimelineItemResponse(
  (b) => b
    ..bookingId = bookingId
    ..categoryKey = categoryKey
    ..categoryName = categoryName
    ..date = date
    ..masterId = masterId
    ..serviceName = serviceName,
);

BuiltList<api.TimelineItemResponse> _dtos(
  List<api.TimelineItemResponse> rows,
) => BuiltList<api.TimelineItemResponse>(rows);

void main() {
  group('TimelineMapper.fromDtoList — drop policy', () {
    test('a row with a null date is dropped', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(categoryName: 'Манікюр', date: null),
        ]),
      );

      expect(
        entries,
        isEmpty,
        reason:
            'nothing to place the row on the rail with, and nothing to '
            'sort it by',
      );
    });

    test('a row with BOTH categoryKey and categoryName null is dropped', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            categoryKey: null,
            categoryName: null,
            date: api.Date(2026, 6, 18),
          ),
        ]),
      );

      expect(
        entries,
        isEmpty,
        reason: 'nothing to label the medallion or resolve an icon from',
      );
    });

    test('a row with BOTH categoryKey and categoryName EMPTY (not null) is '
        'also dropped', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(categoryKey: '', categoryName: '', date: api.Date(2026, 6, 18)),
        ]),
      );

      expect(
        entries,
        isEmpty,
        reason:
            'an empty string is exactly as unrenderable as null — a '
            'blank medallion with an empty caption is not correct either '
            'way',
      );
    });

    test('a row with categoryKey present but categoryName null is KEPT (falls '
        'back to the key)', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            categoryKey: 'NAIL_SERVICE',
            categoryName: null,
            date: api.Date(2026, 6, 18),
          ),
        ]),
      );

      expect(entries, hasLength(1));
      expect(entries.single.category, 'NAIL_SERVICE');
    });

    test('a valid row survives alongside a dropped one — one bad row must not '
        'blank the whole rail', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(categoryName: 'Манікюр', date: null), // dropped
          _row(categoryName: 'Брови', date: api.Date(2026, 5, 12)), // kept
        ]),
      );

      expect(entries, hasLength(1));
      expect(entries.single.category, 'Брови');
    });
  });

  group('TimelineMapper.fromDtoList — bookingId passthrough policy', () {
    test('a null bookingId maps through as null', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            bookingId: null,
            categoryName: 'Манікюр',
            date: api.Date(2026, 6, 18),
          ),
        ]),
      );

      expect(entries.single.bookingId, isNull);
    });

    // THE REGRESSION GUARD named directly by the mobile-qa gap: a recorded
    // incident had `?? ''` coerce a missing bookingId into an empty string,
    // which silently "worked" until it reached a route that 404'd on it.
    // `timeline_mapper.dart`'s header calls this out by name — this pins it.
    test(
      'an EMPTY STRING bookingId on the wire maps through UNCHANGED — it is '
      'NEVER coerced to null, and a null bookingId is NEVER coerced to ""',
      () {
        final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
          _dtos(<api.TimelineItemResponse>[
            _row(
              bookingId: '',
              categoryName: 'Манікюр',
              date: api.Date(2026, 6, 18),
            ),
          ]),
        );

        expect(
          entries.single.bookingId,
          '',
          reason:
              'the wire sent an empty string; the mapper must carry that '
              'value through EXACTLY as received, not normalise it to '
              'null — the tap-guard downstream (BeautyTimelineSection\'s '
              '_TimelineNode) is what decides tappability from '
              'isNotEmpty, and this mapper has no business pre-deciding '
              'that for it',
        );
        expect(
          entries.single.bookingId,
          isNotNull,
          reason:
              'a real (if degenerate) non-null value assertion — rules out '
              'an accidental pass via two nulls comparing equal',
        );
      },
    );

    test('a populated bookingId maps through verbatim', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            bookingId: 'bkg-42',
            categoryName: 'Манікюр',
            date: api.Date(2026, 6, 18),
          ),
        ]),
      );

      expect(entries.single.bookingId, 'bkg-42');
    });
  });

  group('TimelineMapper.fromDtoList — sort policy', () {
    test('rows are re-sorted most-recent-first regardless of wire order', () {
      // Deliberately fed in ASCENDING (oldest-first) order — the mapper must
      // not simply trust the wire order (the backend already sorts DESC in
      // production, but this proves the CLIENT-side sort independently of
      // that backend behaviour).
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            bookingId: 'oldest',
            categoryName: 'Педикюр',
            date: api.Date(2026, 4, 2),
          ),
          _row(
            bookingId: 'middle',
            categoryName: 'Брови',
            date: api.Date(2026, 5, 12),
          ),
          _row(
            bookingId: 'newest',
            categoryName: 'Манікюр',
            date: api.Date(2026, 6, 18),
          ),
        ]),
      );

      expect(entries, hasLength(3));
      expect(entries[0].bookingId, 'newest');
      expect(entries[1].bookingId, 'middle');
      expect(entries[2].bookingId, 'oldest');
    });

    test('rows already DESCENDING on the wire stay in that order', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            bookingId: 'newest',
            categoryName: 'Манікюр',
            date: api.Date(2026, 6, 18),
          ),
          _row(
            bookingId: 'oldest',
            categoryName: 'Педикюр',
            date: api.Date(2026, 4, 2),
          ),
        ]),
      );

      expect(entries[0].bookingId, 'newest');
      expect(entries[1].bookingId, 'oldest');
    });
  });

  group('TimelineMapper.fromDtoList — caption preference policy', () {
    test('categoryName is preferred over categoryKey for the caption', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            categoryKey: 'NAIL_SERVICE',
            categoryName: 'Манікюр',
            date: api.Date(2026, 6, 18),
          ),
        ]),
      );

      expect(
        entries.single.category,
        'Манікюр',
        reason:
            'categoryName wins when both are present — categoryKey is '
            'carried separately for icon resolution, not the caption',
      );
    });

    test(
      'categoryKey is used ONLY as a fallback when categoryName is absent',
      () {
        final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
          _dtos(<api.TimelineItemResponse>[
            _row(
              categoryKey: 'NAIL_SERVICE',
              categoryName: null,
              date: api.Date(2026, 6, 18),
            ),
          ]),
        );

        expect(entries.single.category, 'NAIL_SERVICE');
      },
    );

    test('categoryKey is carried through on entries.categoryKey regardless of '
        'which value won the caption', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            categoryKey: 'NAIL_SERVICE',
            categoryName: 'Манікюр',
            date: api.Date(2026, 6, 18),
          ),
        ]),
      );

      expect(entries.single.category, 'Манікюр');
      expect(
        entries.single.categoryKey,
        'NAIL_SERVICE',
        reason:
            'the stable key must survive on its own field even though '
            'categoryName won the caption — categoryIconFor (called from '
            'beauty_timeline_section.dart) reads categoryKey separately',
      );
    });
  });

  group('TimelineMapper.fromDtoList — serviceName passthrough', () {
    test('serviceName maps through verbatim, unrendered by the rail today', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(
            categoryName: 'Манікюр',
            date: api.Date(2026, 6, 18),
            serviceName: 'Класичний манікюр',
          ),
        ]),
      );

      expect(entries.single.serviceName, 'Класичний манікюр');
    });

    test('a null serviceName maps through as null (not an empty string)', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(<api.TimelineItemResponse>[
          _row(categoryName: 'Манікюр', date: api.Date(2026, 6, 18)),
        ]),
      );

      expect(entries.single.serviceName, isNull);
    });
  });

  group('TimelineMapper.fromDtoList — empty input', () {
    test('an empty row list maps to an empty entry list', () {
      final List<TimelineEntry> entries = TimelineMapper.fromDtoList(
        _dtos(const <api.TimelineItemResponse>[]),
      );

      expect(entries, isEmpty);
    });
  });
}
