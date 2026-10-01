// Phase 363 audit — `NotificationCopy.sanitize`: server-supplied names are
// stripped of control / bidi characters, whitespace-collapsed, trimmed and
// isolated (FSI..PDI) before they are spliced into a sentence.
//
// Every special code point is spelled with `String.fromCharCode`, never as a
// literal, so the test source itself stays plain ASCII.

import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_copy.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:flutter_test/flutter_test.dart';

String _c(int code) => String.fromCharCode(code);

final String _fsi = _c(0x2068);
final String _pdi = _c(0x2069);

String _iso(String s) => '$_fsi$s$_pdi';

void main() {
  group('sanitize', () {
    test('should_isolateAPlainName', () {
      expect(NotificationCopy.sanitize('Олена'), _iso('Олена'));
    });

    test('should_returnNull_when_nullBlankOrOnlyInvisible', () {
      expect(NotificationCopy.sanitize(null), isNull);
      expect(NotificationCopy.sanitize(''), isNull);
      expect(NotificationCopy.sanitize('  \n\t '), isNull);
      expect(
        NotificationCopy.sanitize('${_c(0x202E)}${_c(0x0000)}${_c(0x200F)}'),
        isNull,
      );
    });

    test('should_stripEveryBidiOverrideEmbeddingAndIsolate', () {
      final List<int> bidi = <int>[
        0x200E, 0x200F, 0x061C, // marks
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, // embeddings + overrides
        0x2066, 0x2067, 0x2068, 0x2069, // isolates (a name's OWN are removed)
      ];
      for (final int code in bidi) {
        expect(
          NotificationCopy.sanitize('ab${_c(code)}cd'),
          _iso('abcd'),
          reason: 'U+${code.toRadixString(16).toUpperCase()}',
        );
      }
    });

    test('should_notLetARightToLeftOverrideReorderTheName', () {
      final String out = NotificationCopy.sanitize('Анна${_c(0x202E)}Коваль')!;
      expect(out.contains(_c(0x202E)), isFalse);
      expect(out, _iso('АннаКоваль'));
    });

    test('should_stripC0AndC1Controls', () {
      final String raw = <int>[
        0x01,
        0x07,
        0x1B,
        0x7F,
        0x80,
        0x9F,
      ].map(_c).join('x');
      expect(
        NotificationCopy.sanitize('a${_c(0x07)}b${_c(0x9F)}c'),
        _iso('abc'),
      );
      expect(NotificationCopy.sanitize(raw), _iso('xxxxx'));
    });

    test('should_collapseNewlinesAndWhitespaceRunsToOneSpace_andTrim', () {
      expect(
        NotificationCopy.sanitize('  Олена \n\r\n  Коваль\t\tМайстер  '),
        _iso('Олена Коваль Майстер'),
      );
      expect(
        NotificationCopy.sanitize('a${_c(0x2028)}b${_c(0x0085)}c'),
        _iso('a b c'),
      );
    });

    test('should_collapseTheSpaceLeftBehindByAStrippedCharacter', () {
      expect(NotificationCopy.sanitize('a ${_c(0x202E)} b'), _iso('a b'));
    });

    test('should_treatANameOfOnlyZeroWidthSpacesAsMissing', () {
      expect(NotificationCopy.sanitize(_c(0x200B) * 5), isNull);
      expect(
        NotificationCopy.sanitize(
          '${_c(0x200B)}${_c(0x200C)}${_c(0x200D)}${_c(0x2060)}'
          '${_c(0x00AD)}${_c(0x034F)}${_c(0x180E)}${_c(0xFE0F)}',
        ),
        isNull,
      );
    });

    test('should_stripEveryAddedInvisibleCodePoint', () {
      final List<int> codes = <int>[
        0x200B, //
        0x2060, 0x2061, 0x2062, 0x2063, 0x2064, //
        0x00AD, 0x034F, 0x180E, //
      ];
      for (final int code in codes) {
        expect(
          NotificationCopy.sanitize('ab${_c(code)}cd'),
          _iso('abcd'),
          reason: 'U+${code.toRadixString(16).toUpperCase()}',
        );
      }
    });

    test('should_keepZwjZwnjAndVariationSelectors_inTheOutput', () {
      final List<int> kept = <int>[
        0x200C,
        0x200D,
        for (int c = 0xFE00; c <= 0xFE0F; c++) c,
      ];
      for (final int code in kept) {
        expect(
          NotificationCopy.sanitize('ab${_c(code)}cd'),
          _iso('ab${_c(code)}cd'),
          reason: 'U+${code.toRadixString(16).toUpperCase()}',
        );
      }
    });

    test('should_preserveAHeartWithVariationSelector', () {
      final String heart = '${_c(0x2764)}${_c(0xFE0F)}';
      expect(NotificationCopy.sanitize(heart), _iso(heart));
      expect(NotificationCopy.sanitize('Ol $heart'), _iso('Ol $heart'));
    });

    test('should_keepAZwjFamilyEmojiAsOneUnchangedGrapheme', () {
      final String family = <int>[
        0x1F469,
        0x200D,
        0x1F469,
        0x200D,
        0x1F467,
        0x200D,
        0x1F466,
      ].map(_c).join();
      expect(family.characters.length, 1);
      final String out = NotificationCopy.sanitize(family)!;
      expect(out, _iso(family));
      expect(out.characters.length, 3, reason: 'FSI + family + PDI');
    });

    test('should_treatANameOfOnlyZwjAndVariationSelectorsAsMissing', () {
      expect(NotificationCopy.sanitize('${_c(0x200D)}${_c(0xFE0F)}'), isNull);
      expect(NotificationCopy.sanitize(' ${_c(0x200C)} '), isNull);
    });

    test('should_capMarks_when_zwjIsInterleavedBetweenThem', () {
      final String unit = '${_c(0x0301)}${_c(0x0301)}${_c(0x200D)}';
      final String out = NotificationCopy.sanitize('a${unit * 20}')!;
      final String body = out.substring(1, out.length - 1);
      expect(body.runes.where((int r) => r == 0x0301).length, 2);
      expect(body.runes.where((int r) => r == 0x200D).length, 1);
      expect(body, 'a${_c(0x0301)}${_c(0x0301)}${_c(0x200D)}');
    });

    test('should_collapseConsecutiveJoinersToOne', () {
      final String zw = '${_c(0x200D)}${_c(0x200C)}${_c(0x200D)}';
      expect(NotificationCopy.sanitize('a${zw}b'), _iso('a${_c(0x200D)}b'));
    });

    test('should_treatANameOfOnlyBlankFillersAsMissing', () {
      final Map<String, List<int>> groups = <String, List<int>>{
        'supplementary variation selectors': <int>[0xE0100, 0xE01EF, 0xE0150],
        'mongolian free variation selectors': <int>[0x180B, 0x180C, 0x180D],
        'hangul fillers': <int>[0x115F, 0x1160, 0x3164, 0xFFA0],
        'braille blank': <int>[0x2800],
      };
      groups.forEach((String name, List<int> codes) {
        expect(
          NotificationCopy.sanitize(codes.map(_c).join()),
          isNull,
          reason: name,
        );
        expect(
          NotificationCopy.sanitize(' ${codes.map(_c).join(' ')} '),
          isNull,
          reason: '$name with spaces',
        );
        for (final int code in codes) {
          expect(
            NotificationCopy.sanitize(_c(code)),
            isNull,
            reason: 'U+${code.toRadixString(16).toUpperCase()}',
          );
        }
      });
    });

    test('should_stripBlankFillersAroundAVisibleName', () {
      final String fillers = '${_c(0x2800)}${_c(0x3164)}';
      expect(NotificationCopy.sanitize('${fillers}Ol$fillers'), _iso('Ol'));
    });

    test('should_notLetLeadingFillersPushTheRealTextOut', () {
      expect(
        NotificationCopy.sanitize('${_c(0x3164) * 100}Olena'),
        _iso('Olena'),
      );
    });

    test(
      'should_treatANameOfOnlyAnyOneFormatOrPlaceholderCodePointAsMissing',
      () {
        final List<int> codes = <int>[
          0x17B4,
          0xFFFC,
          0x1D173, // surrogate pair, Cf
          0x1D159, // musical null notehead, So, draws blank
          0x13430, // Egyptian format control
          0x1BCA0, // shorthand format control
          0x0300, // combining mark with no base
          0xE0100, // variation selector supplement
        ];
        for (final int code in codes) {
          final String hex = code.toRadixString(16).toUpperCase();
          expect(NotificationCopy.sanitize(_c(code)), isNull, reason: 'U+$hex');
          expect(
            NotificationCopy.sanitize(_c(code) * 10),
            isNull,
            reason: 'U+$hex x10',
          );
        }
      },
    );

    test('should_capMarksOfAnyScript_byUnicodeCategoryNotBlock', () {
      for (final int mark in <int>[0x0591, 0x064B, 0x0488]) {
        final String hex = mark.toRadixString(16).toUpperCase();
        final String out = NotificationCopy.sanitize('a${_c(mark) * 300}')!;
        final String body = out.substring(1, out.length - 1);
        expect(
          body.runes.where((int r) => r == mark).length,
          lessThanOrEqualTo(2),
          reason: 'U+$hex',
        );
      }
    });

    test('should_dropMarksThatHaveNoBase_atStartOrAfterASpace', () {
      expect(NotificationCopy.sanitize('${_c(0x301)}${_c(0x301)}A'), _iso('A'));
      expect(
        NotificationCopy.sanitize('Анна ${_c(0x301)}Марія'),
        _iso('Анна Марія'),
      );
    });

    test('should_dropJoinersAndSelectorsThatHaveNoBase_atTheStart', () {
      expect(
        NotificationCopy.sanitize('${_c(0x200D)}${_c(0xFE0F)}A'),
        _iso('A'),
      );
    });

    test('should_treatANameOfOnlyNullNoteheadsAsMissing', () {
      expect(NotificationCopy.sanitize(_c(0x1D159) * 80), isNull);
    });

    test('should_keepLegitimateMarkedNamesUnchanged', () {
      final List<String> names = <String>[
        'שָׁלוֹם',
        'مُحَمَّد',
        'Йосип',
        'Иосип'.replaceFirst('И', 'и${_c(0x0306)}'),
        '❤️',
        '👩‍👩‍👧‍👦',
        '1${_c(0xFE0F)}${_c(0x20E3)}',
      ];
      for (final String n in names) {
        expect(NotificationCopy.sanitize(n), _iso(n), reason: n);
      }
    });

    test(
      'should_keepAnEllipsisAndEndOnAWholeGrapheme_when80ZwjFamiliesCut',
      () {
        final String family = <int>[
          0x1F469,
          0x200D,
          0x1F469,
          0x200D,
          0x1F467,
          0x200D,
          0x1F466,
        ].map(_c).join();
        final String out = NotificationCopy.sanitize(family * 80)!;
        expect(
          out.length,
          lessThanOrEqualTo(NotificationCopy.maxOutputUnits + 2),
        );
        final String body = out.substring(1, out.length - 1);
        expect(body.endsWith('…'), isTrue);
        final String kept = body.substring(0, body.length - 1);
        expect(kept, isNotEmpty);
        expect(kept.characters.every((String g) => g == family), isTrue);
      },
    );

    test('should_boundTheWrappedOutputAt322Units', () {
      for (final String unit in <String>[
        _c(0x1F600),
        '${_c(0x1F469)}${_c(0x200D)}${_c(0x1F467)}',
        'ж',
      ]) {
        expect(
          NotificationCopy.sanitize(unit * 500)!.length,
          lessThanOrEqualTo(322),
        );
      }
    });

    test('should_treatATruncationThatLeavesOnlyAnEllipsisAsMissing', () {
      // One ~600-unit grapheme (a joined emoji chain) cannot fit the budget.
      final String chain = List<String>.filled(
        200,
        _c(0x1F600),
      ).join(_c(0x200D));
      expect(chain.characters.length, 1);
      expect(NotificationCopy.sanitize(chain), isNull);
    });

    test('should_leaveRepresentativeNamesAndEmojiUnchanged', () {
      final List<String> names = <String>[
        '${_c(0x2764)}${_c(0xFE0F)}',
        '${_c(0x1F468)}${_c(0x200D)}${_c(0x1F469)}${_c(0x200D)}${_c(0x1F467)}',
        '1${_c(0xFE0F)}${_c(0x20E3)}',
        '${_c(0x1F1FA)}${_c(0x1F1E6)}',
        'Олена Ковальчук',
        'Анна-Марія',
        "O'Connor",
        'محمد علي',
      ];
      for (final String name in names) {
        expect(NotificationCopy.sanitize(name), _iso(name), reason: name);
      }
    });

    test('should_leaveAnEightyUnitNameUntouched_andStillCapALongOne', () {
      expect(NotificationCopy.sanitize('в' * 80), _iso('в' * 80));
      expect(NotificationCopy.sanitize('в' * 81), _iso('${'в' * 80}…'));
    });

    test('should_stripTheTagBlockSurrogatePairs', () {
      final String tags = <int>[0xE0001, 0xE0041, 0xE007F].map(_c).join();
      expect(NotificationCopy.sanitize('Ol${tags}ena'), _iso('Olena'));
      expect(NotificationCopy.sanitize(tags), isNull);
    });

    test('should_leaveALegitimateNameUnchanged', () {
      for (final String name in <String>[
        "О'Коннор",
        'Анна-Марія',
        "Д’Артаньян",
        'Їжак Євген',
        'Zoë Müller',
      ]) {
        expect(NotificationCopy.sanitize(name), _iso(name), reason: name);
      }
    });

    test('should_keepOneVariationSelectorPerBase_notThousands', () {
      final String out = NotificationCopy.sanitize('a${_c(0xFE0F) * 5000}')!;
      expect(out, _iso('a${_c(0xFE0F)}'));
      expect(out.length, lessThan(10));
    });

    test('should_processAndCapAHugeRawString', () {
      final String out = NotificationCopy.sanitize('ж' * 100000)!;
      expect(out, _iso('${'ж' * 80}…'));
      expect(
        NotificationCopy.sanitize('x${_c(0xFE0F)}' * 50000)!.length,
        lessThanOrEqualTo(NotificationCopy.maxOutputUnits + 2),
      );
    });

    test('should_notSplitASurrogatePairAtTheRawBoundary', () {
      // 1023 invisible units, then a pair straddling unit 1024. A naive cut
      // leaves a lone high surrogate (visible, non-blank); the back-off
      // leaves only invisibles, so the name is blank.
      final String raw = '${_c(0x200B) * 1023}${_c(0x1F600)}';
      expect(NotificationCopy.sanitize(raw), isNull);
      // A pair wholly inside the bound survives intact.
      expect(
        NotificationCopy.sanitize('${_c(0x1F600)}${_c(0x200B) * 2000}'),
        _iso(_c(0x1F600)),
      );
    });

    test('should_keepEmojiSequencesIntactUnderTheSelectorCap', () {
      final String keycap = '1${_c(0xFE0F)}${_c(0x20E3)}';
      expect(NotificationCopy.sanitize(keycap), _iso(keycap));
      final String flag = '${_c(0x1F1FA)}${_c(0x1F1E6)}';
      expect(NotificationCopy.sanitize(flag), _iso(flag));
      final String family =
          '${_c(0x1F468)}${_c(0x200D)}${_c(0x1F469)}${_c(0x200D)}'
          '${_c(0x1F467)}';
      expect(NotificationCopy.sanitize(family), _iso(family));
    });

    test('should_capAtEightyCharacters_andAppendAnEllipsis', () {
      final String long = 'а' * 200;
      expect(NotificationCopy.sanitize(long), _iso('${'а' * 80}…'));
      // Exactly at the cap: untouched.
      expect(NotificationCopy.sanitize('б' * 80), _iso('б' * 80));
    });

    test('should_countUserPerceivedCharacters_notCodeUnits', () {
      // Emoji are surrogate pairs: 80 of them is 80 characters, not 160.
      final String emoji = '\u{1F600}' * 80;
      expect(NotificationCopy.sanitize(emoji), _iso(emoji));
      expect(
        NotificationCopy.sanitize('\u{1F600}' * 81),
        _iso('${'\u{1F600}' * 80}…'),
      );
    });

    test('should_keepAtMostTwoConsecutiveCombiningMarks', () {
      final String marks = _c(0x0301) * 12;
      expect(
        NotificationCopy.sanitize(
          'a$marks'
          'b$marks',
        ),
        _iso('a${_c(0x0301) * 2}b${_c(0x0301) * 2}'),
      );
      // One mark (a stress accent) is untouched.
      expect(
        NotificationCopy.sanitize('ма${_c(0x0301)}ма'),
        _iso('ма${_c(0x0301)}ма'),
      );
    });
  });

  group('body', () {
    final AppLocalizationsUk uk = AppLocalizationsUk();

    AppNotification row(NotificationParams params) => AppNotification(
      id: '00000000-0000-4000-8000-000000000001',
      type: AppNotificationType.bookingCreated,
      createdAt: DateTime.utc(2026, 9, 30, 10),
      read: false,
      target: const NotificationTarget.none(),
      params: params,
    );

    test('should_spliceOnlySanitisedValues_intoTheSentence', () {
      final String? body = NotificationCopy.body(
        uk,
        row(
          NotificationParams(
            counterpartName: 'Олена${_c(0x202E)}\nКоваль',
            serviceName: 'Ман${_c(0x202B)}ікюр',
            serviceCount: 2,
            startsAt: DateTime.utc(2026, 10, 3, 11, 30),
          ),
        ),
        isClient: false,
      );

      expect(body, isNotNull);
      expect(body!.contains(_c(0x202E)), isFalse);
      expect(body.contains(_c(0x202B)), isFalse);
      expect(body.contains('\n'), isFalse);
      expect(body, contains(_iso('Олена Коваль')));
      expect(body, contains(_iso('Манікюр')));
    });

    test('should_treatAnAllInvisibleNameAsMissing', () {
      final String? body = NotificationCopy.body(
        uk,
        row(
          NotificationParams(
            counterpartName: '${_c(0x202E)}${_c(0x200F)}',
            serviceName: 'Манікюр',
            serviceCount: 1,
            startsAt: DateTime.utc(2026, 10, 3, 11, 30),
          ),
        ),
        isClient: false,
      );

      expect(body, uk.notificationsParamsGone);
    });

    test('should_sanitiseTheInviteSubject', () {
      final String? body = NotificationCopy.body(
        uk,
        AppNotification(
          id: '00000000-0000-4000-8000-000000000002',
          type: AppNotificationType.inviteAccepted,
          createdAt: DateTime.utc(2026, 9, 30, 10),
          read: false,
          target: const NotificationTarget.none(),
          params: NotificationParams(subjectName: 'Ірина${_c(0x202E)}'),
        ),
        isClient: false,
      );

      expect(body, contains(_iso('Ірина')));
      expect(body!.contains(_c(0x202E)), isFalse);
    });
  });
}
