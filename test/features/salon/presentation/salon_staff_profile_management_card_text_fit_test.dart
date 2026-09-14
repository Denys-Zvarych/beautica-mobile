// 2026-09-14 (mobile-qa) — regression coverage for the CRITICAL text-
// truncation defect on the `ManagementActionCard` pair
// («Графік роботи» / «Послуги») of [SalonStaffProfileScreen].
//
// THE DEFECT
// ----------
// `VelvetText.managementCardLabel` / `managementCardValue` were transcribed
// from the approved preview at a literal `fontSize: 15` with `maxLines: 1`.
// Each card owns only ~half the screen minus the page, row and card padding,
// so the schedule value «Пн–Пт · 09:00–18:00» (145.5 dp at 15 sp) ellipsized
// on EVERY shipped width, and at 360 dp the hours half was lost entirely. A
// non-contiguous pattern («Пн, Ср, Пт · 10:00–19:00», 175.1 dp) was worse.
//
// WHY NOTHING CAUGHT IT (and why this file asserts the way it does)
// -----------------------------------------------------------------
//   • `test/helpers/overflow_guard.dart` and every `scripts/forbid_*.sh`
//     gate trip on a `RenderFlex overflowed` banner. A `TextOverflow
//     .ellipsis` is NOT a RenderFlex overflow — the paragraph fits its box
//     by design, it just drops glyphs. Those nets are structurally blind to
//     this whole defect class.
//   • A GOLDEN is self-referential (`feedback_golden_not_acceptance`): the
//     truncated render was baked into a regenerated PNG and re-rendering it
//     matched perfectly.
//   • Reading a widget field (`style.fontSize == 13`, `maxLines == 2`) is
//     vacuous (`project_widget_field_assertion_is_vacuous`) — it reads a
//     field, never layout, and stays green if the copy grows or the column
//     narrows.
//
// So the ONLY assertion that can see the defect is the laid-out paragraph
// itself: `RenderParagraph.didExceedMaxLines`. That flag is set by the text
// engine during layout and is `true` exactly when glyphs were dropped.
//
// FIXTURE CHOICE (`project_fixture_values_can_defang_assertions`)
// --------------------------------------------------------------
// The schedule fixture is deliberately the NON-CONTIGUOUS «Пн, Ср, Пт ·
// 10:00–19:00» shape, not the short «Пн–Пт · 09:00–18:00». A fixture that
// fits trivially would make every assertion below green forever regardless
// of the tokens. The anti-vacuity block asserts the value genuinely WRAPS at
// the narrow end, so a future copy/​token change that stops pressuring the
// layout fails loudly instead of silently defanging the file.
//
// MUTATION RECORD (mobile-qa, 2026-09-14) — see the QA report; the tokens
// were reverted to the shipped defect (15 sp / maxLines 1) with a `cp`
// backup and every case below was confirmed RED, then restored and GREEN.

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/management_action_card.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_member_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/salon_staff_profile_screen.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-1';
const String _kMemberId = 'staff-master-1';
const String _kMasterId = 'master-row-1';

const SalonStaffMember _member = SalonStaffMember(
  userId: _kMemberId,
  masterId: _kMasterId,
  role: SalonStaffRole.master,
  firstName: 'Олена',
  lastName: 'Ковальчук',
  professionalTitle: 'Майстер манікюру',
  phoneNumber: '+380671112233',
  avgRating: 4.8,
  reviewCount: 32,
  serviceCount: 99,
);

const ScheduleScope _scope = ScheduleScope.salonMaster(
  salonId: _kSalonId,
  masterId: _kMasterId,
);

/// Mon / Wed / Fri 10:00–19:00 — a NON-CONTIGUOUS pattern, so
/// `weeklyScheduleSummary` renders the long comma-joined «Пн, Ср, Пт ·
/// 10:00–19:00» form rather than the short «Пн–Пт» range. This is the
/// widest realistic value the card can be asked to carry and is what makes
/// every assertion in this file load-bearing. `validFrom` is in the past and
/// `validTo` is null, so the template is active under ANY clock — this
/// fixture is deliberately clock-independent and therefore raises no
/// pinned-vs-host clock coherence question (`project_test_clock_coherence_
/// invariant`).
final List<WeeklySchedule> _nonContiguousTemplate = <WeeklySchedule>[
  WeeklySchedule(
    id: 'wt-noncontig',
    validFrom: DateTime(2020, 1, 1),
    validTo: null,
    days: <TemplateDay>[
      for (int day = 1; day <= 7; day++)
        TemplateDay(
          dayOfWeek: day,
          label: 'day-$day',
          intervals: const <int>[1, 3, 5].contains(day)
              ? <WorkInterval>[
                  WorkInterval(
                    start: const TimeOfDay(hour: 10, minute: 0),
                    end: const TimeOfDay(hour: 19, minute: 0),
                  ),
                ]
              : const <WorkInterval>[],
        ),
    ],
  ),
];

/// 24 services — drives the «Послуги» card's value to the longest shipped
/// plural form («24 послуги», the `few` branch of `staffProfileServicesCount`)
/// rather than the trivially-short «Ще немає» empty copy.
final List<MasterService> _services = _servicesOfLength(24);

List<MasterService> _servicesOfLength(int n) => List<MasterService>.generate(
  n,
  (int i) => MasterService(
    id: 'svc-$i',
    serviceDefId: 'def-$i',
    name: 'Послуга $i',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
    category: 'NAILS',
  ),
  growable: false,
);

class _NonContiguousWeekly extends WeeklyScheduleNotifier {
  @override
  Future<List<WeeklySchedule>> build(ScheduleScope scope) async =>
      _nonContiguousTemplate;
}

List<Object> _overrides({List<MasterService>? services}) => <Object>[
  salonStaffMemberProfileProvider(
    _kSalonId,
    _kMemberId,
  ).overrideWith((Ref ref) async => (_member, services ?? _services)),
  approvedCategoriesProvider.overrideWith(
    (ref) async => const <ServiceCategoryOption>[],
  ),
  weeklyScheduleProvider(_scope).overrideWith(_NonContiguousWeekly.new),
];

// ---------------------------------------------------------------------------
// Paragraph helpers — the whole point of this file.
// ---------------------------------------------------------------------------

const Key _kScheduleCard = Key('salon-staff-profile-schedule-row');
const Key _kServicesCard = Key('salon-staff-profile-services-row');

Finder _line(Key card, Key line) =>
    find.descendant(of: find.byKey(card), matching: find.byKey(line));

RenderParagraph _paragraph(WidgetTester tester, Key card, Key line) {
  final Finder f = _line(card, line);
  expect(
    f,
    findsOneWidget,
    reason: 'card $card must render exactly one $line paragraph',
  );
  return tester.renderObject<RenderParagraph>(f);
}

/// The number of laid-out lines the paragraph actually occupies.
///
/// `RenderParagraph` does not expose `computeLineMetrics()` publicly in this
/// Flutter channel, so the count is derived from the selection boxes: every
/// visual line has its own `top`, so the number of DISTINCT tops is the
/// number of lines. (A single line can yield several boxes when the run is
/// split by style or bidi, hence the de-duplication.)
int _lineCount(RenderParagraph p) {
  final String plain = p.text.toPlainText();
  if (plain.isEmpty) return 0;
  final List<TextBox> boxes = p.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plain.length),
  );
  return boxes.map((TextBox b) => b.top.toStringAsFixed(2)).toSet().length;
}

/// The advance width of [s] laid out unconstrained in [style] at [scale].
///
/// Used to measure the longest WORD against the card's column. A word wider
/// than the column is not ellipsized — Flutter breaks it MID-WORD — which is
/// a legibility defect `didExceedMaxLines` is structurally blind to.
double _advance(String s, TextStyle style, double scale) {
  final TextPainter tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout();
  return tp.width;
}

/// Asserts the laid-out paragraph dropped NO glyphs.
///
/// `didExceedMaxLines` is the text engine's own answer to "did this
/// paragraph need more lines than it was allowed", computed during layout.
/// It is the only signal that distinguishes a fitted render from an
/// ellipsized one — neither the widget fields nor the overflow guard nor a
/// golden can tell them apart.
void _expectNotTruncated(
  WidgetTester tester, {
  required Key card,
  required Key line,
  required String at,
}) {
  final RenderParagraph p = _paragraph(tester, card, line);
  expect(
    p.didExceedMaxLines,
    isFalse,
    reason:
        '$at — «${p.text.toPlainText()}» was ELLIPSIZED inside a '
        '${p.size.width.toStringAsFixed(1)} dp column across '
        '${_lineCount(p)} line(s). This is the exact defect '
        'the 2026-09-14 fix removed: a TextOverflow.ellipsis is not a '
        'RenderFlex overflow, so nothing else in the suite can see it.',
  );
}

// ---------------------------------------------------------------------------
// The matrix
// ---------------------------------------------------------------------------

/// Every shipped phone width the app supports, narrowest first. 320 dp is the
/// floor (iPhone SE 1st gen / small Android); 414 dp the common large-phone
/// width.
const List<double> _kWidths = <double>[320, 360, 375, 414];

/// 1.0 = default; 1.3 = the accessibility setting a large share of users
/// actually run. Beyond 1.3 the card is expected to wrap further, which is
/// what `maxLines: 2` / `maxLines: 3` exist for.
const List<double> _kTextScales = <double>[1.0, 1.3];

Future<void> _pump(
  WidgetTester tester,
  double width,
  double scale, {
  List<MasterService>? services,
}) async {
  await tester.pumpApp(
    const SalonStaffProfileScreen(salonId: _kSalonId, memberId: _kMemberId),
    overrides: _overrides(services: services),
    width: width,
    height: 3000,
    textScaleFactor: scale,
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final double width in _kWidths) {
    for (final double scale in _kTextScales) {
      final String at = '${width.toInt()} dp @ textScale $scale';

      testWidgets(
        'management cards render label and value UNTRUNCATED at $at',
        (tester) async {
          await _pump(tester, width, scale);

          // Both cards must actually be mounted — otherwise every assertion
          // below would vacuously pass on a finder that resolves to nothing.
          expect(find.byKey(_kScheduleCard), findsOneWidget);
          expect(find.byKey(_kServicesCard), findsOneWidget);

          for (final (Key card, String name) in <(Key, String)>[
            (_kScheduleCard, 'schedule'),
            (_kServicesCard, 'services'),
          ]) {
            _expectNotTruncated(
              tester,
              card: card,
              line: kManagementActionCardLabelKey,
              at: '$name card LABEL at $at',
            );
            _expectNotTruncated(
              tester,
              card: card,
              line: kManagementActionCardValueKey,
              at: '$name card VALUE at $at',
            );
          }
        },
      );
    }
  }

  // -------------------------------------------------------------------------
  // Anti-vacuity — proves the fixture genuinely PRESSURES the layout.
  //
  // Without this, every assertion above could pass because the copy happens
  // to be short, not because the tokens are right
  // (`project_fixture_values_can_defang_assertions`). These cases pin that
  // the schedule value needs MORE THAN ONE line at the narrow widths, i.e.
  // that a `maxLines: 1` token — the shipped defect — could not have
  // satisfied the matrix above.
  // -------------------------------------------------------------------------
  group('anti-vacuity — the fixture moves the assertion', () {
    testWidgets('the schedule value WRAPS at 320 dp @ 1.0 (so a maxLines: 1 '
        'token could not have passed the matrix above)', (tester) async {
      await _pump(tester, 320, 1.0);

      final RenderParagraph p = _paragraph(
        tester,
        _kScheduleCard,
        kManagementActionCardValueKey,
      );
      expect(
        _lineCount(p),
        greaterThan(1),
        reason:
            'the non-contiguous «Пн, Ср, Пт · 10:00–19:00» fixture must not '
            'fit on one line in a half-width card — if it does, the whole '
            'matrix above has been defanged and needs a longer fixture',
      );
    });

    testWidgets('the schedule value needs a THIRD line at 320 dp @ 1.3 — '
        'maxLines: 3 on the value token is load-bearing, not defensive', (
      tester,
    ) async {
      await _pump(tester, 320, 1.3);

      final RenderParagraph p = _paragraph(
        tester,
        _kScheduleCard,
        kManagementActionCardValueKey,
      );
      expect(
        _lineCount(p),
        greaterThanOrEqualTo(3),
        reason:
            'measured 2026-09-14: the narrowest shipped width at the common '
            'large-font setting needs three lines for a non-contiguous '
            'weekly summary. Dropping the value token back to maxLines: 2 '
            'would re-introduce the truncation this file exists to forbid.',
      );
    });

    testWidgets('the rendered paragraph carries the card`s FULL value string '
        '(no silent drop between widget and paragraph)', (tester) async {
      await _pump(tester, 360, 1.0);

      final ManagementActionCard card = tester.widget<ManagementActionCard>(
        find.byKey(_kScheduleCard),
      );
      final RenderParagraph p = _paragraph(
        tester,
        _kScheduleCard,
        kManagementActionCardValueKey,
      );
      expect(p.text.toPlainText(), card.value);
      expect(
        card.value.length,
        greaterThan(18),
        reason:
            'guards the fixture itself: a short summary here (e.g. a «Пн–Пт» '
            'contiguous range, or «Не задано») would silently weaken every '
            'assertion in this file',
      );
    });
  });

  // -------------------------------------------------------------------------
  // The pair must stay height-synchronised while wrapping.
  //
  // Both cards sit inside an `IntrinsicHeight` > `Row(stretch)`; a value that
  // wraps to three lines in one card must not leave the sibling short. This
  // is the layout consequence of the fix, and it is not covered anywhere
  // else.
  // -------------------------------------------------------------------------
  testWidgets('both cards keep identical height when one wraps further', (
    tester,
  ) async {
    await _pump(tester, 320, 1.3);

    expect(
      tester.getSize(find.byKey(_kScheduleCard)).height,
      moreOrLessEquals(
        tester.getSize(find.byKey(_kServicesCard)).height,
        epsilon: 0.5,
      ),
      reason:
          'IntrinsicHeight + CrossAxisAlignment.stretch must keep the pair '
          'level even when the schedule value wraps to three lines and the '
          'services value to one',
    );
    // Anti-vacuity for the case above: the heights being equal is only
    // meaningful if the two cards are genuinely carrying DIFFERENT line
    // counts. Equal heights with equal content proves nothing.
    expect(
      _lineCount(
        _paragraph(tester, _kScheduleCard, kManagementActionCardValueKey),
      ),
      greaterThan(
        _lineCount(
          _paragraph(tester, _kServicesCard, kManagementActionCardValueKey),
        ),
      ),
    );
  });

  // -------------------------------------------------------------------------
  // THE SERVICES CARD'S WRAP INVARIANT — measured, not assumed.
  //
  // 2026-09-14 (mobile-qa, closing the LOW raised on the first pass of this
  // file). The schedule card truncates readily, so its assertions are
  // obviously load-bearing. The services card is the opposite: MEASURED
  // below, NO string it can produce truncates at any matrix cell. That makes
  // the eight services-card assertions in the matrix above an INVARIANT
  // GUARD rather than weak coverage — but only if the invariant is stated
  // and pinned, instead of being left as a happy accident of today's copy.
  //
  // WHAT THE CARD CAN ACTUALLY PRODUCE (`salon_staff_profile_screen.dart`
  // D3): `staffProfileServicesEmpty` for a resolved-empty catalogue, else
  // `staffProfileServicesCount(n)` — a four-branch ICU plural
  // (one/few/many/other). There is no other producer.
  //
  // MEASURED 2026-09-14 at the TIGHTEST matrix cell (320 dp x textScale 1.3,
  // where the text column is 96.0 dp), against the shipped
  // `VelvetText.managementCardValue` / `managementCardLabel`:
  //
  //   value, full advance   «9999 послуг»    113.4 dp  -> WRAPS (2 of 3 lines)
  //                         «9999 services»  125.2 dp  -> WRAPS (2 of 3 lines)
  //   value, longest WORD   «послуги»         78.2 dp  -> 17.8 dp headroom
  //                         «services»        77.6 dp  -> 18.4 dp headroom
  //   label, full advance   «Послуги»         75.1 dp  -> 20.9 dp headroom
  //                         «Services»        73.9 dp  -> 22.1 dp headroom
  //
  // WHAT THIS GUARDS, PRECISELY — established by mutation, not assumed. The
  // first draft of this block claimed an over-wide word would be ELLIPSIZED;
  // mutation A falsified that and the claim is corrected here rather than
  // quietly kept.
  //
  // MUTATION A (value token 14 -> 18 sp, pushing «послуга» to 100.4 dp
  // against the same 96.0 dp column): the rendered `didExceedMaxLines` cases
  // below stayed GREEN. Flutter does not ellipsize an over-wide word — it
  // breaks it mid-word («посл» / «уга») and carries on. So truncation really
  // is unreachable for this card at any producible value, and the eight
  // services-card cells in the matrix above are an invariant guard exactly
  // as measured.
  //
  // The headroom assertion therefore guards a DIFFERENT regression that
  // nothing else in this repo watches: a services value whose longest word
  // exceeds the column renders as a mid-word split. No `didExceedMaxLines`,
  // no `overflow_guard.dart`, and no golden (it would simply be rebaselined)
  // can see that. THAT is what makes these assertions earn their place
  // instead of merely completing a matrix — and mutation A turns this
  // assertion RED while leaving every other case in the file green, which is
  // the proof it is load-bearing on its own axis.
  //
  // The narrowest measured headroom is 17.8 dp, so the floor below is 12 dp:
  // comfortably under today's margin (no failures on rounding or a
  // font-fallback difference) and comfortably above zero (a copy change to a
  // longer noun, a larger value token, or a narrower column fails HERE,
  // loudly).
  // -------------------------------------------------------------------------
  group('services card — the wrap invariant, measured not assumed', () {
    testWidgets('every producible services value keeps >= 12 dp of headroom '
        'on its longest word at 320 dp x 1.3, so no producible value ever '
        'renders as a mid-word split (both locales)', (tester) async {
      await _pump(tester, 320, 1.3);

      // The column is read off the REAL laid-out card, never hard-coded —
      // a layout change that narrows it re-tightens this assertion on its
      // own instead of leaving a stale constant behind.
      final RenderParagraph rendered = _paragraph(
        tester,
        _kServicesCard,
        kManagementActionCardValueKey,
      );
      final double column = rendered.constraints.maxWidth;
      expect(
        column,
        lessThan(200),
        reason:
            'sanity: the services card text column at 320 dp must be the '
            'half-width one (~96 dp), not an unconstrained surface — a '
            'measurement taken against infinity would pass forever',
      );

      for (final Locale locale in const <Locale>[Locale('uk'), Locale('en')]) {
        final AppLocalizations l10n = await AppLocalizations.delegate.load(
          locale,
        );
        // Every producer the D3 branch can reach. The counts span all four
        // ICU plural branches plus an absurd four-digit catalogue.
        final List<String> producible = <String>[
          l10n.staffProfileServicesEmpty,
          for (final int n in <int>[1, 2, 5, 24, 99, 144, 999, 9999])
            l10n.staffProfileServicesCount(n),
          l10n.masterServicesLabel,
        ];

        for (final String candidate in producible) {
          final bool isLabel = candidate == l10n.masterServicesLabel;
          final TextStyle style = isLabel
              ? VelvetText.managementCardLabel
              : VelvetText.managementCardValue;
          final double widestWord = candidate
              .split(' ')
              .map((String w) => _advance(w, style, 1.3))
              .reduce((double a, double b) => a > b ? a : b);

          expect(
            column - widestWord,
            greaterThanOrEqualTo(12.0),
            reason:
                '${locale.languageCode}: «$candidate» — its longest word '
                'measures ${widestWord.toStringAsFixed(1)} dp against a '
                '${column.toStringAsFixed(1)} dp column, leaving only '
                '${(column - widestWord).toStringAsFixed(1)} dp. A word '
                'wider than the column is NOT ellipsized — Flutter breaks '
                'it mid-word, which no didExceedMaxLines / overflow-guard / '
                'golden check can see. Measured headroom on 2026-09-14 was '
                '17.8 dp (uk) / 18.4 dp (en); if this now fails, the copy, '
                'the value token or the card width changed and the services '
                'card is at risk.',
          );
        }
      }
    });

    // The measurement above is arithmetic on a TextPainter. This case is the
    // RENDERED counterpart: every ICU plural branch driven through the real
    // screen at the tightest cell, so the invariant is proven on the actual
    // widget tree and not only on a detached painter.
    for (final (int count, String branch) in const <(int, String)>[
      (0, 'empty -> «Ще немає»'),
      (1, 'one -> «1 послуга»'),
      (2, 'few -> «2 послуги»'),
      (5, 'many -> «5 послуг»'),
      (9999, 'other, four digits -> «9999 послуг»'),
    ]) {
      testWidgets('rendered: $branch fits at 320 dp x 1.3', (tester) async {
        await _pump(tester, 320, 1.3, services: _servicesOfLength(count));

        _expectNotTruncated(
          tester,
          card: _kServicesCard,
          line: kManagementActionCardValueKey,
          at: 'services VALUE, plural branch $branch',
        );
        _expectNotTruncated(
          tester,
          card: _kServicesCard,
          line: kManagementActionCardLabelKey,
          at: 'services LABEL, plural branch $branch',
        );
        // Anti-vacuity: the branch really is the one named — a card stuck on
        // one fixture would pass all five of these identically.
        final ManagementActionCard card = tester.widget<ManagementActionCard>(
          find.byKey(_kServicesCard),
        );
        expect(card.value, contains(count == 0 ? 'Ще' : '$count'));
      });
    }
  });

  // -------------------------------------------------------------------------
  // Guard against the card ever being pinned back to a single line.
  // -------------------------------------------------------------------------
  testWidgets('neither text line is pinned to maxLines: 1', (tester) async {
    await _pump(tester, 414, 1.0);

    for (final Key card in <Key>[_kScheduleCard, _kServicesCard]) {
      for (final Key line in <Key>[
        kManagementActionCardLabelKey,
        kManagementActionCardValueKey,
      ]) {
        final Text text = tester.widget<Text>(_line(card, line));
        expect(
          text.maxLines,
          greaterThan(1),
          reason:
              'a single-line management card cannot carry a real weekly '
              'summary at any shipped width — see this file`s header',
        );
      }
    }
  });
}
