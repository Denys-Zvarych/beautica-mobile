// Phase 363 audit — `NotificationCopy.sanitize`: server-supplied names are
// stripped of control / bidi characters, whitespace-collapsed, trimmed and
// isolated (FSI..PDI) before they are spliced into a sentence.
//
// Every special code point is spelled with `String.fromCharCode`, never as a
// literal, so the test source itself stays plain ASCII.

import 'package:beautica_mobile/features/notifications/domain/app_notification.dart';
import 'package:beautica_mobile/features/notifications/presentation/notification_copy.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:flutter/material.dart';
import 'package:beautica_mobile/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
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

    group('masterName', () {
      NotificationParams params({String? master}) => NotificationParams(
        counterpartName: 'Олена',
        serviceName: 'Манікюр',
        serviceCount: 1,
        startsAt: DateTime.utc(2026, 10, 3, 11, 30),
        masterName: master,
      );

      test('should_appendMaster_when_providerAndMasterPresent', () {
        final String? body = NotificationCopy.body(
          uk,
          row(params(master: 'Ірина')),
          isClient: false,
          showMaster: true,
        );
        expect(body, contains(_iso('Ірина')));
        expect(body, contains(_iso('Олена')));
        expect(body, isNot(uk.notificationsParamsGone));
      });

      test('should_keepPlainText_when_masterMissingOrInvisible', () {
        final String plain = NotificationCopy.body(
          uk,
          row(params()),
          isClient: false,
        )!;
        final String blank = NotificationCopy.body(
          uk,
          row(params(master: _c(0x202E))),
          isClient: false,
          showMaster: true,
        )!;
        expect(plain, isNot(uk.notificationsParamsGone));
        expect(blank, plain);
      });

      test('should_notShowMaster_when_recipientIsClient', () {
        final String? body = NotificationCopy.body(
          uk,
          row(params(master: 'Ірина')),
          isClient: true,
          showMaster: true,
        );
        expect(body!.contains(_iso('Ірина')), isFalse);
      });

      test('should_ignoreMaster_when_viewerNotOwnerOrAdmin', () {
        // salon master / independent master: showMaster defaults to false.
        final String plain = NotificationCopy.body(
          uk,
          row(params()),
          isClient: false,
        )!;
        final String? body = NotificationCopy.body(
          uk,
          row(params(master: 'Ірина')),
          isClient: false,
        );
        expect(body, plain);
        expect(body!.contains('Ірина'), isFalse);
      });

      test('should_ignoreMaster_when_clientEvenIfShowMasterSet', () {
        final String plain = NotificationCopy.body(
          uk,
          row(params()),
          isClient: true,
        )!;
        final String? body = NotificationCopy.body(
          uk,
          row(params(master: 'Ірина')),
          isClient: true,
          showMaster: true,
        );
        expect(body, plain);
      });

      test('should_sanitiseMaster_rtlAndControlChars', () {
        final String? body = NotificationCopy.body(
          uk,
          row(params(master: 'Ір${_c(0x202E)}и\nна')),
          isClient: false,
          showMaster: true,
        );
        expect(body, contains(_iso('Іри на')));
        expect(body!.contains(_c(0x202E)), isFalse);
        expect(body.contains('\n'), isFalse);
      });

      test('should_capOverlongMaster_likeCounterpart', () {
        final String long = 'М' * 5000;
        final String masterBody = NotificationCopy.body(
          uk,
          row(params(master: long)),
          isClient: false,
          showMaster: true,
        )!;
        final String counterpartBody = NotificationCopy.body(
          uk,
          row(
            NotificationParams(
              counterpartName: long,
              serviceName: 'Манікюр',
              serviceCount: 1,
              startsAt: DateTime.utc(2026, 10, 3, 11, 30),
            ),
          ),
          isClient: false,
        )!;
        expect(masterBody.length, lessThan(2500));
        expect(masterBody.contains('…'), isTrue);
        expect(counterpartBody.contains('…'), isTrue);
      });

      test('should_appendMaster_when_rescheduled', () {
        final String? body = NotificationCopy.body(
          uk,
          AppNotification(
            id: '00000000-0000-4000-8000-000000000003',
            type: AppNotificationType.bookingRescheduled,
            createdAt: DateTime.utc(2026, 9, 30, 10),
            read: false,
            target: const NotificationTarget.none(),
            params: params(master: 'Ірина'),
          ),
          isClient: false,
          showMaster: true,
        );
        expect(body, contains(_iso('Ірина')));
      });
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

  // Phase 412 — category-request / service-type-suggestion decisions.
  group('catalog decisions (phase 412)', () {
    final AppLocalizationsUk uk = AppLocalizationsUk();

    AppNotification row(AppNotificationType type, NotificationParams params) =>
        AppNotification(
          id: '00000000-0000-4000-8000-000000000001',
          type: type,
          createdAt: DateTime.utc(2026, 10, 14, 10),
          read: false,
          target: const NotificationTarget.serviceCatalog(),
          params: params,
        );

    String? body(AppNotificationType t, NotificationParams p) =>
        NotificationCopy.body(uk, row(t, p), isClient: false);

    const NotificationParams full = NotificationParams(
      categoryName: 'Манікюр',
      serviceName: 'Гель-лак',
      decisionReason: 'Дублікат',
    );

    test('should_notLeakReasonOrNamesInToString', () {
      const String sentinel = 'SENTINEL-REASON-7f3a';
      const NotificationParams p = NotificationParams(
        decisionReason: sentinel,
        categoryName: 'SENTINEL-CAT',
        counterpartName: 'SENTINEL-CP',
        serviceName: 'SENTINEL-SVC',
        subjectName: 'SENTINEL-SUBJ',
        masterName: 'SENTINEL-MASTER',
        salonName: 'SENTINEL-SALON',
      );
      expect(p.toString(), isNot(contains('SENTINEL')));
      expect(
        AppNotification(
          id: 'n',
          type: AppNotificationType.categoryRequestRejected,
          createdAt: DateTime.utc(2026),
          read: false,
          target: const NotificationTarget.none(),
          params: p,
        ).toString(),
        isNot(contains('SENTINEL')),
      );
    });

    test('should_renderTheFourTitles', () {
      String t(AppNotificationType x) =>
          NotificationCopy.title(uk, x, isClient: false);
      expect(
        t(AppNotificationType.categoryRequestApproved),
        'Категорію схвалено',
      );
      expect(
        t(AppNotificationType.categoryRequestRejected),
        'Категорію відхилено',
      );
      expect(
        t(AppNotificationType.serviceTypeSuggestionApproved),
        'Тип послуги схвалено',
      );
      expect(
        t(AppNotificationType.serviceTypeSuggestionRejected),
        'Тип послуги відхилено',
      );
      expect(t(AppNotificationType.unknown), 'Нове сповіщення');
    });

    test('should_nameTheCategoryOrServiceType_inEachBody', () {
      expect(
        body(AppNotificationType.categoryRequestApproved, full),
        'Категорія «${_iso('Манікюр')}» тепер доступна для ваших послуг',
      );
      expect(
        body(AppNotificationType.serviceTypeSuggestionApproved, full),
        'Тип послуги «${_iso('Гель-лак')}» у категорії «${_iso('Манікюр')}» '
        'тепер доступний',
      );
    });

    test('should_appendReasonLine_onlyOnRejectedWithReason', () {
      expect(
        body(AppNotificationType.categoryRequestRejected, full),
        'Запит на категорію «${_iso('Манікюр')}» відхилено\n'
        'Причина: ${_iso('Дублікат')}',
      );
      expect(
        body(AppNotificationType.serviceTypeSuggestionRejected, full),
        'Пропозицію типу послуги «${_iso('Гель-лак')}» (${_iso('Манікюр')}) '
        'відхилено\nПричина: ${_iso('Дублікат')}',
      );
      // No reason / blank reason: no second line.
      for (final String? reason in <String?>[null, '  ']) {
        final String? b = body(
          AppNotificationType.categoryRequestRejected,
          NotificationParams(categoryName: 'Манікюр', decisionReason: reason),
        );
        expect(b, isNot(contains('Причина')), reason: '$reason');
        expect(b!.contains('\n'), isFalse);
      }
      // An approved row never shows a reason, even if the wire carried one.
      expect(
        body(AppNotificationType.categoryRequestApproved, full),
        isNot(contains('Причина')),
      );
      expect(
        body(AppNotificationType.serviceTypeSuggestionApproved, full),
        isNot(contains('Причина')),
      );
    });

    test('should_sanitiseTheReason', () {
      final String? b = body(
        AppNotificationType.categoryRequestRejected,
        NotificationParams(
          categoryName: 'Манікюр',
          decisionReason: 'Погано${_c(0x202E)}\nдуже',
        ),
      );
      expect(b!.contains(_c(0x202E)), isFalse);
      expect(b, endsWith('Причина: ${_iso('Погано дуже')}'));
    });

    test('should_notCutTheReasonAt80_but_stillCapNamesAt80', () {
      final String reason250 = 'р' * 250;
      final String? b = body(
        AppNotificationType.categoryRequestRejected,
        NotificationParams(categoryName: 'Манікюр', decisionReason: reason250),
      );
      expect(b, endsWith('Причина: ${_iso(reason250)}'));
      expect(b, isNot(contains('…')));

      // Names keep the 80-grapheme cap.
      final String? n = body(
        AppNotificationType.categoryRequestRejected,
        NotificationParams(categoryName: 'н' * 250),
      );
      expect(n, contains('${'н' * 80}…'));
      expect(n, isNot(contains('н' * 81)));
    });

    test('should_capTheReasonAt300Graphemes', () {
      final String? b = body(
        AppNotificationType.categoryRequestRejected,
        NotificationParams(categoryName: 'Манікюр', decisionReason: 'р' * 400),
      );
      expect(b, contains('${'р' * 300}…'));
      expect(b, isNot(contains('р' * 301)));
    });

    test('should_keepDefaultSanitizeCapAt80', () {
      expect(NotificationCopy.sanitize('р' * 250), _iso('${'р' * 80}…'));
      expect(
        NotificationCopy.sanitize('р' * 250, maxLength: 300, maxUnits: 600),
        _iso('р' * 250),
      );
    });

    testWidgets('should_boundALongReasonByTheTileLineClamp', (tester) async {
      final AppNotification item = row(
        AppNotificationType.categoryRequestRejected,
        NotificationParams(
          categoryName: 'Манікюр',
          decisionReason: List<String>.filled(40, 'довгоочікувана').join(' '),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: NotificationTile(
                item: item,
                isClient: false,
                bodyMaxLines: 3,
              ),
            ),
          ),
        ),
      );
      final Text text = tester.widget<Text>(
        find.byWidgetPredicate(
          (Widget w) => w is Text && (w.data ?? '').contains('Причина'),
        ),
      );
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    test('should_fallBackToParamsGone_when_aRequiredNameIsMissing', () {
      expect(
        body(
          AppNotificationType.categoryRequestApproved,
          NotificationParams.empty,
        ),
        uk.notificationsParamsGone,
      );
      expect(
        body(
          AppNotificationType.categoryRequestRejected,
          const NotificationParams(decisionReason: 'x'),
        ),
        uk.notificationsParamsGone,
      );
      // Service-type rows need BOTH names.
      expect(
        body(
          AppNotificationType.serviceTypeSuggestionApproved,
          const NotificationParams(categoryName: 'Манікюр'),
        ),
        uk.notificationsParamsGone,
      );
      expect(
        body(
          AppNotificationType.serviceTypeSuggestionRejected,
          const NotificationParams(serviceName: 'Гель-лак'),
        ),
        uk.notificationsParamsGone,
      );
    });

    test('should_useCheckForApprovedAndCancelForRejected', () {
      expect(
        NotificationCopy.glyph(AppNotificationType.categoryRequestApproved),
        Icons.check_circle_rounded,
      );
      expect(
        NotificationCopy.glyph(
          AppNotificationType.serviceTypeSuggestionApproved,
        ),
        Icons.check_circle_rounded,
      );
      expect(
        NotificationCopy.glyph(AppNotificationType.categoryRequestRejected),
        Icons.cancel_rounded,
      );
      expect(
        NotificationCopy.glyph(
          AppNotificationType.serviceTypeSuggestionRejected,
        ),
        Icons.cancel_rounded,
      );
    });

    test('should_flagOnlyTheFourTypesAsCatalogDecisions', () {
      final Set<AppNotificationType> flagged = AppNotificationType.values
          .where(NotificationCopy.isCatalogDecision)
          .toSet();
      expect(flagged, <AppNotificationType>{
        AppNotificationType.categoryRequestApproved,
        AppNotificationType.categoryRequestRejected,
        AppNotificationType.serviceTypeSuggestionApproved,
        AppNotificationType.serviceTypeSuggestionRejected,
      });
    });
  });

  // Phase 428 — moderation outcomes: locked UK copy (backend 415 D2), glyphs,
  // role-agnostic (D6).
  group('moderation outcomes (phase 428)', () {
    final AppLocalizationsUk uk = AppLocalizationsUk();

    AppNotification row(
      AppNotificationType type, {
      ModeratedContentKind? kind,
    }) => AppNotification(
      id: '00000000-0000-4000-8000-000000000001',
      type: type,
      createdAt: DateTime.utc(2026, 10, 29, 10),
      read: false,
      target: const NotificationTarget.none(),
      params: NotificationParams(contentKind: kind),
    );

    const String reporterTitle = 'Скаргу розглянуто';
    final Map<AppNotificationType, String> reporterBodies =
        <AppNotificationType, String>{
          AppNotificationType.reportContentRemoved:
              'Дякуємо! Ми переглянули вашу скаргу, і вміст видалено.',
          AppNotificationType.reportNoViolation:
              'Ми переглянули вашу скаргу і не знайшли порушень правил.',
          AppNotificationType.reportReviewed:
              'Дякуємо! Ми переглянули вашу скаргу.',
        };

    for (final MapEntry<AppNotificationType, String> e
        in reporterBodies.entries) {
      test('${e.key.name}: title, body and glyph — same for every role', () {
        for (final bool isClient in <bool>[true, false]) {
          expect(
            NotificationCopy.title(uk, e.key, isClient: isClient),
            reporterTitle,
          );
          expect(
            NotificationCopy.body(uk, row(e.key), isClient: isClient),
            e.value,
          );
        }
        expect(NotificationCopy.glyph(e.key), Icons.fact_check_rounded);
      });
    }

    test('reportReviewed on a PROFILE says the report was confirmed; every '
        'other kind keeps the neutral line', () {
      // RED WHEN the PROFILE branch in `NotificationCopy.body` is dropped.
      const AppNotificationType t = AppNotificationType.reportReviewed;
      expect(
        NotificationCopy.body(
          uk,
          row(t, kind: ModeratedContentKind.profile),
          isClient: true,
        ),
        "Дякуємо! Скаргу підтверджено — ми зв'яжемося з власником профілю.",
      );
      for (final ModeratedContentKind? kind in <ModeratedContentKind?>[
        ModeratedContentKind.review,
        ModeratedContentKind.clientReview,
        ModeratedContentKind.portfolioPhoto,
        null,
      ]) {
        expect(
          NotificationCopy.body(uk, row(t, kind: kind), isClient: false),
          'Дякуємо! Ми переглянули вашу скаргу.',
          reason: '$kind',
        );
      }
    });

    test('contentRemoved: title, glyph and a body per contentKind', () {
      const AppNotificationType t = AppNotificationType.contentRemoved;
      expect(NotificationCopy.title(uk, t, isClient: true), 'Вміст видалено');
      expect(NotificationCopy.title(uk, t, isClient: false), 'Вміст видалено');
      expect(NotificationCopy.glyph(t), Icons.gpp_maybe_rounded);

      const String review =
          'Ваш відгук видалено через порушення правил спільноти.';
      final Map<ModeratedContentKind?, String> bodies =
          <ModeratedContentKind?, String>{
            ModeratedContentKind.review: review,
            ModeratedContentKind.clientReview:
                'Ваш відгук про клієнта видалено через порушення правил '
                'спільноти.',
            ModeratedContentKind.portfolioPhoto:
                'Ваше фото видалено через порушення правил спільноти.',
            // D3 fallback.
            ModeratedContentKind.profile: review,
            null: review,
          };
      for (final MapEntry<ModeratedContentKind?, String> e in bodies.entries) {
        expect(
          NotificationCopy.body(uk, row(t, kind: e.key), isClient: false),
          e.value,
          reason: '${e.key}',
        );
      }
    });

    test('reviewAboutYouRemoved: title, glyph and one body for REVIEW and '
        'CLIENT_REVIEW', () {
      const AppNotificationType t = AppNotificationType.reviewAboutYouRemoved;
      expect(NotificationCopy.title(uk, t, isClient: true), 'Відгук видалено');
      expect(NotificationCopy.title(uk, t, isClient: false), 'Відгук видалено');
      expect(NotificationCopy.glyph(t), Icons.reviews_rounded);
      for (final ModeratedContentKind? kind in <ModeratedContentKind?>[
        ModeratedContentKind.review,
        ModeratedContentKind.clientReview,
        null,
      ]) {
        expect(
          NotificationCopy.body(uk, row(t, kind: kind), isClient: true),
          'Відгук про вас видалено модерацією Beautica: він порушував правила '
          'спільноти.',
          reason: '$kind',
        );
      }
    });

    test('none of the 5 renders the «unknown» title', () {
      for (final AppNotificationType t in <AppNotificationType>[
        ...reporterBodies.keys,
        AppNotificationType.contentRemoved,
        AppNotificationType.reviewAboutYouRemoved,
      ]) {
        expect(
          NotificationCopy.title(uk, t, isClient: true),
          isNot(uk.notificationTitleUnknown),
        );
      }
    });
  });
}
