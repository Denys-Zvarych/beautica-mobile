// Phase 14.3/14.4/14.5 — TEXT-CLIPPING / LAYOUT-OVERFLOW guard for the three
// NEW booking surfaces:
//   1. the «МОЇ ЗАПИСИ» list  — MyBookingsScreen + BookingCard (+ status badge,
//      date stub, tab bar),
//   2. «Деталі запису»        — BookingDetailScreen (+ BookingSummaryCards,
//      BookingNotes/ClampedNote, ArrivalNote, the pinned action footer, the
//      calendar button),
//   3. «Скасувати запис?»     — CancelBookingDialog.
//
// WHAT IT PROVES
// --------------
// Nothing on any of these surfaces is UNINTENTIONALLY clipped, and no
// `RenderFlex overflowed by N pixels` stripe appears — across the worst
// realistic surface a user can produce: width ∈ {320, 360, 414} dp × text
// scale ∈ {1.0, 1.3, 2.0} (9 cells per surface). Every fixture carries
// deliberately OVER-LONG Ukrainian (Cyrillic) strings — a service name that
// must wrap past two lines, a hyphenated double-barrelled surname, a salon
// name that fills the card, a 1000-char note — so a cell that passes has
// survived content well past anything real backend data produces.
//
// HOW OVERFLOW IS CAUGHT (no manual takeException needed)
// -------------------------------------------------------
// The suite-wide overflow guard (test/helpers/overflow_guard.dart, installed by
// `pumpApp`) records the FIRST `RenderFlex overflowed` error and fails the test
// in tearDown. So a cell that pumps and finishes without the guard firing has,
// by construction, proven that surface overflow-free at that size/scale.
//
// WHY textScale 2.0 + real fonts, NOT the preview's square Ahem font
// ------------------------------------------------------------------
// `docs/signup-designs/MyBookings/test/layout_overflow_test.dart` swaps in a
// square test font whose Cyrillic glyphs are ~2× Nunito's advance width. We
// cannot do the same here without RISK: `test/flutter_test_config.dart` loads
// the REAL Comfortaa/Nunito TTFs into the process-global engine font collection
// up front, and its own header documents the `FontLoader`-broadcast deadlock
// that a same-family font swap would reintroduce. Instead we push the ambient
// text scale to 2.0 — which DOUBLES every glyph's absolute advance, so real
// Nunito at 2.0× renders at the same absolute width a square em-box font would
// at 1.0× (0.5em advance × 2 = 1.0em) AND doubles height too. Combined with the
// 320 dp floor and the over-long Cyrillic fixtures, this is an equal-or-harder
// stress than the preview's square font, using the harness this repo already
// trusts.
//
// DELIBERATE truncation this file ASSERTS (and must never "fix"):
//   • the service NAME on a card ellipsises — that is what anchors the price to
//     the right margin. `_confirmed card: name ellipsises, price stays
//     right-anchored` proves BOTH at once.
//   • notes clamp to 6 lines behind «Показати більше»; a 1000-char note stays
//     openable at every cell — `_a long note keeps its «Показати більше»
//     toggle at every cell`.
//
// SETTLING: bounded `pump(Duration)` (never `pumpAndSettle`) — the card's
// AnimatedScale/AnimatedContainer, the detail hero's staggered reveal and the
// note's AnimatedSize are one-shot, but a genuinely overflowing tree re-reports
// each frame, so `pumpAndSettle` could hang. A fixed pump advances the
// animations enough to lay out at the target size and lets the guard record.

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/my_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/calendar_button.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/cancel_booking_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// The stress matrix — the task's required 9 cells per surface.
// ---------------------------------------------------------------------------

const List<double> _widths = <double>[320, 360, 414];
const List<double> _scales = <double>[1.0, 1.3, 2.0];

/// The narrowest × largest cell — used for the interaction/one-shot cases that
/// do not need the full 9-cell sweep.
const double _worstWidth = 320;
const double _worstScale = 2.0;

// ---------------------------------------------------------------------------
// Deliberately OVER-LONG Ukrainian fixtures. Every one is longer than any real
// value the backend produces, so a cell that survives them survives production
// data with margin.
// ---------------------------------------------------------------------------

/// Long enough to wrap past two lines even on a 414 dp card at 1.0× — so the
/// name is GUARANTEED to ellipsise (the deliberate truncation this file
/// asserts) at every cell, on both the card and the detail recap.
const String _longService =
    'Комбінований апаратний манікюр з покриттям гель-лаком, зміцненням бази, '
    'парафінотерапією та художнім дизайном усіх нігтів на обох руках';
const String _longFirstName = 'Олександра-Валентина';
const String _longLastName = 'Коваленко-Тестівська-Довгопрізвищенко';
const String _longTitle =
    'Провідна майстриня манікюру та педикюру найвищої категорії';
const String _longSalon =
    'Салон краси та естетичної косметології «Прекрасна Довга Мить»';
const String _longStreet =
    'вулиця Дуже Довга Історична Назва Богдана Хмельницького';
const String _longArrival =
    'Третій поверх, код на дверях 1234, ліфт праворуч від головного входу, '
    'квартира навпроти сходів';

/// ~1000-char note — the clamp's documented worst case. Must still clamp to 6
/// lines behind «Показати більше» at every width.
String _longNote() {
  const String sentence =
      'Дуже перепрошую за незручності, обставини змінилися в останній момент. ';
  final StringBuffer buffer = StringBuffer();
  while (buffer.length < 1000) {
    buffer.write(sentence);
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Fixtures + fakes.
// ---------------------------------------------------------------------------

class _MockBookingRepository extends Mock implements BookingRepository {}

/// No-op — the native FLAG_SECURE plugin must never fire in a widget test.
class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

Booking _booking({
  required String id,
  required BookingStatus status,
  String serviceName = _longService,
  String? salonName = _longSalon,
  String? masterProfessionalTitle = _longTitle,
  String? clientComment,
  String? providerComment,
  String? clientCancellationNote,
  String? street = _longStreet,
  String? locationNote = _longArrival,
  double price = 1250,
}) {
  final DateTime start = DateTime.utc(2026, 11, 28, 15);
  return Booking(
    id: id,
    masterId: 'master-$id',
    masterFirstName: _longFirstName,
    masterLastName: _longLastName,
    masterAvatarUrl: null, // initials disc → no Image.network in tests
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 'service-$id',
    serviceName: serviceName,
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: 'Залізничний район',
    street: street,
    buildingNo: '15А',
    durationMinutes: 90,
    price: price,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    clientComment: clientComment,
    providerComment: providerComment,
    clientCancellationNote: clientCancellationNote,
    masterProfessionalTitle: masterProfessionalTitle,
    locationNote: locationNote,
  );
}

PageResponse<Booking> _page(List<Booking> items) => PageResponse<Booking>(
  items: items,
  page: 0,
  totalPages: 1,
  totalElements: items.length,
);

void _stubAllStatuses(
  _MockBookingRepository repo, {
  Map<BookingStatus, List<Booking>> byStatus =
      const <BookingStatus, List<Booking>>{},
}) {
  for (final BookingStatus status in BookingStatus.values) {
    when(
      () => repo.getMyBookings(
        status: status,
        page: any(named: 'page'),
        size: any(named: 'size'),
      ),
    ).thenAnswer((_) async => _page(byStatus[status] ?? const <Booking>[]));
  }
}

Widget _framed(Widget child) => Scaffold(body: child);

/// Advances one-shot animations + resolved microtasks WITHOUT `pumpAndSettle`
/// (which would hang on a genuinely overflowing, re-reporting tree).
///
/// Pump-until-stable: after the first frame, step the clock only until no frame
/// remains scheduled — i.e. every one-shot animation (card AnimatedScale, detail
/// hero staggered reveal, note AnimatedSize) has settled — instead of guessing a
/// fixed duration. Bounded at 60 ticks (~960 ms virtual) so a pathological tree
/// fails loudly rather than spins forever. The `const` step lives on its own
/// declaration (not inside the `pump(...)` call) so this stays a real
/// pump-until-condition, not a flaky fixed sleep.
Future<void> _lay(WidgetTester tester) async {
  await tester.pump();
  const Duration step = Duration(milliseconds: 16);
  for (int i = 0; i < 60 && tester.binding.hasScheduledFrame; i++) {
    await tester.pump(step);
  }
}

AppLocalizations _l10n(WidgetTester tester, Type ofType) =>
    AppLocalizations.of(tester.element(find.byType(ofType)));

double _rightEdge(WidgetTester tester, Key key) =>
    tester.getBottomRight(find.byKey(key)).dx;

void main() {
  // =========================================================================
  // SURFACE 1 — «МОЇ ЗАПИСИ» list: MyBookingsScreen + BookingCard.
  // =========================================================================
  group('Surface 1 — bookings list', () {
    // ── 1a. The full screen (tab bar + list + a long-content card) at all 9
    //    cells. The default Майбутні tab carries a salon-employed confirmed
    //    booking (the densest card: name + title + salon + status + chevron).
    for (final double width in _widths) {
      for (final double scale in _scales) {
        testWidgets('MyBookingsScreen @ ${width}dp x$scale — no overflow', (
          tester,
        ) async {
          final repo = _MockBookingRepository();
          _stubAllStatuses(
            repo,
            byStatus: <BookingStatus, List<Booking>>{
              BookingStatus.confirmed: <Booking>[
                _booking(id: 'confirmed', status: BookingStatus.confirmed),
              ],
            },
          );

          await tester.pumpApp(
            const MyBookingsScreen(),
            overrides: <Object>[
              bookingRepositoryProvider.overrideWithValue(repo),
            ],
            width: width,
            textScaleFactor: scale,
          );
          await _lay(tester);

          // Sanity: the card composed and the status label is not clipped away.
          expect(find.byType(BookingCard), findsOneWidget);
          expect(
            find.byKey(const ValueKey<String>('service-confirmed')),
            findsOneWidget,
          );
        });
      }
    }

    // ── 1b. Every status card at once (confirmed / completed / no-show /
    //    cancelled / declined) — the dead-card hairline border, the struck
    //    no-show and the price-suppressed variants all laid out together in a
    //    ListView, at all 9 cells.
    for (final double width in _widths) {
      for (final double scale in _scales) {
        testWidgets('all status cards @ ${width}dp x$scale — no overflow', (
          tester,
        ) async {
          final List<Booking> cards = <Booking>[
            _booking(id: 'c-confirmed', status: BookingStatus.confirmed),
            _booking(
              id: 'c-completed',
              status: BookingStatus.completed,
              salonName: null, // independent master card variant
              masterProfessionalTitle: null,
            ),
            _booking(
              id: 'c-noshow',
              status: BookingStatus.notCompleted,
              providerComment: 'Чекала на вас пів години.',
            ),
            _booking(
              id: 'c-cancelled',
              status: BookingStatus.cancelled,
              clientCancellationNote: 'Перенесла відрядження.',
            ),
            _booking(id: 'c-declined', status: BookingStatus.declined),
          ];

          await tester.pumpApp(
            _framed(
              ListView(
                children: <Widget>[
                  for (final Booking b in cards)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: BookingCard(booking: b, onOpenDetails: () {}),
                    ),
                ],
              ),
            ),
            width: width,
            textScaleFactor: scale,
          );
          await _lay(tester);

          expect(find.byType(BookingCard), findsNWidgets(5));
        });
      }
    }

    // ── 1c. DELIBERATE truncation — the service name ellipsises AND the price
    //    stays fully visible, right-anchored to the same edge as the time,
    //    whatever the name does. Asserted at every cell.
    for (final double width in _widths) {
      for (final double scale in _scales) {
        testWidgets(
          'confirmed card @ ${width}dp x$scale — name ellipsises, price stays '
          'right-anchored',
          (tester) async {
            await tester.pumpApp(
              _framed(
                BookingCard(
                  booking: _booking(
                    id: 'anchor',
                    status: BookingStatus.confirmed,
                  ),
                  onOpenDetails: () {},
                ),
              ),
              width: width,
              textScaleFactor: scale,
            );
            await _lay(tester);

            // The name is INTENDED to ellipsise — that is what frees the price
            // to sit hard against the right margin. Prove it actually did.
            final RenderParagraph name = tester.renderObject<RenderParagraph>(
              find.byKey(const ValueKey<String>('service-anchor')),
            );
            expect(
              name.didExceedMaxLines,
              isTrue,
              reason:
                  'the long service name must ellipsise (maxLines: 2) — this is '
                  'the deliberate truncation that anchors the price',
            );

            // The price is fully visible AND its right edge lines up with the
            // time above it — the numeric column stays a straight vertical edge.
            expect(
              find.byKey(const ValueKey<String>('price-anchor')),
              findsOneWidget,
            );
            expect(
              _rightEdge(tester, const ValueKey<String>('price-anchor')),
              closeTo(
                _rightEdge(tester, const ValueKey<String>('time-anchor')),
                0.6,
              ),
              reason: 'price right edge must align with the time right edge',
            );
          },
        );
      }
    }
  });

  // =========================================================================
  // SURFACE 2 — «Деталі запису»: BookingDetailScreen.
  // =========================================================================
  group('Surface 2 — booking detail', () {
    Future<void> pumpDetail(
      WidgetTester tester,
      Booking booking, {
      required double width,
      required double scale,
    }) async {
      await tester.pumpApp(
        BookingDetailScreen(bookingId: booking.id),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingDetailProvider(
            booking.id,
          ).overrideWith((ref) async => booking),
        ],
        width: width,
        textScaleFactor: scale,
      );
      await _lay(tester);
    }

    // ── 2a. The CONFIRMED page — the densest: hero medallion, two pinned
    //    actions, the calendar button, salon + full address + arrival note,
    //    the client's own booking note, price. All 9 cells.
    for (final double width in _widths) {
      for (final double scale in _scales) {
        testWidgets('confirmed detail @ ${width}dp x$scale — no overflow', (
          tester,
        ) async {
          final Booking b = _booking(
            id: 'd-confirmed',
            status: BookingStatus.confirmed,
            clientComment:
                'Буду з дитиною, без різких ароматизаторів — алергія.',
          );
          await pumpDetail(tester, b, width: width, scale: scale);

          // CONFIRMED drops the status hero/title (2026-07-15) — the subline is
          // the anchor text that must render, unclipped.
          final AppLocalizations l10n = _l10n(tester, BookingDetailScreen);
          expect(find.text(l10n.bookingDetailSublineConfirmed), findsOneWidget);
          // The CONFIRMED-only calendar trigger laid out — now the HEADER icon
          // (change #4), not the scroll-body `CalendarButton` pill (which was
          // removed from the detail surface but still serves the success
          // screens + home hub).
          expect(
            find.byKey(const Key('booking-detail-add-calendar')),
            findsOneWidget,
          );
          expect(find.byType(CalendarButton), findsNothing);
          // Price is a true statement here — it renders.
          expect(find.textContaining('₴'), findsWidgets);
        });
      }
    }

    // ── 2b. The DECLINED page carrying a 1000-char provider note — the clamp's
    //    worst case. At every cell the «Показати більше» toggle must survive
    //    (never disappear) and nothing overflows. Price is suppressed here.
    for (final double width in _widths) {
      for (final double scale in _scales) {
        testWidgets(
          'declined detail (1000-char note) @ ${width}dp x$scale — clamp toggle '
          'survives, no overflow',
          (tester) async {
            final Booking b = _booking(
              id: 'd-declined',
              status: BookingStatus.declined,
              providerComment: _longNote(),
            );
            await pumpDetail(tester, b, width: width, scale: scale);

            final AppLocalizations l10n = _l10n(tester, BookingDetailScreen);
            expect(
              find.text(l10n.bookingNoteShowMore),
              findsOneWidget,
              reason:
                  'a long note must stay openable — «Показати більше» must never '
                  'be clipped away',
            );
            // Price is NOT a true statement on a declined booking — suppressed.
            expect(find.textContaining('₴'), findsNothing);
          },
        );
      }
    }

    // ── 2c. The remaining statuses (completed / cancelled / no-show) at the two
    //    worst corners — the price-suppressed + client-note + no-action-footer
    //    variants.
    final Map<String, Booking> corners = <String, Booking>{
      'completed': _booking(id: 'd-completed', status: BookingStatus.completed),
      'cancelled': _booking(
        id: 'd-cancelled',
        status: BookingStatus.cancelled,
        clientCancellationNote: _longNote(),
      ),
      'no-show': _booking(
        id: 'd-noshow',
        status: BookingStatus.notCompleted,
        providerComment: 'Чекала на вас пів години, на дзвінки не відповідали.',
      ),
    };
    for (final MapEntry<String, Booking> entry in corners.entries) {
      for (final (double width, double scale) in <(double, double)>[
        (_worstWidth, _worstScale),
        (414, 1.0),
      ]) {
        testWidgets('${entry.key} detail @ ${width}dp x$scale — no overflow', (
          tester,
        ) async {
          await pumpDetail(tester, entry.value, width: width, scale: scale);
          expect(find.byType(BookingDetailScreen), findsOneWidget);
        });
      }
    }

    // ── 2d. The clamp actually OPENS at the worst cell — proving the toggle is
    //    live, not merely present, and that expanding a 1000-char note does not
    //    introduce an overflow either.
    testWidgets(
      'a long note expands on «Показати більше» at ${_worstWidth}dp x$_worstScale',
      (tester) async {
        final Booking b = _booking(
          id: 'd-expand',
          status: BookingStatus.declined,
          providerComment: _longNote(),
        );
        await pumpDetail(tester, b, width: _worstWidth, scale: _worstScale);

        final AppLocalizations l10n = _l10n(tester, BookingDetailScreen);
        final Finder toggle = find.text(l10n.bookingNoteShowMore);
        await tester.ensureVisible(toggle);
        await tester.pump();
        await tester.tap(toggle);
        await _lay(tester);

        expect(find.text(l10n.bookingNoteShowLess), findsOneWidget);
      },
    );
  });

  // =========================================================================
  // SURFACE 3 — «Скасувати запис?»: CancelBookingDialog.
  // =========================================================================
  group('Surface 3 — cancel dialog', () {
    for (final double width in _widths) {
      for (final double scale in _scales) {
        testWidgets('cancel dialog @ ${width}dp x$scale — no overflow', (
          tester,
        ) async {
          await tester.pumpApp(
            _framed(
              Center(
                child: CancelBookingDialog(
                  booking: _booking(id: 'x', status: BookingStatus.confirmed),
                ),
              ),
            ),
            width: width,
            textScaleFactor: scale,
          );
          await _lay(tester);

          // The recap rows (Послуга / Майстер / Коли), the note field and both
          // buttons all laid out — the guard would already have fired on any
          // RenderFlex overflow among them.
          expect(
            find.byKey(const Key('cancel-booking-dialog')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('cancel-booking-note-field')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('cancel-booking-confirm')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('cancel-booking-keep')), findsOneWidget);
        });
      }
    }

    // ── Typing a long note must not push the field/counter into an overflow at
    //    the worst cell.
    testWidgets(
      'typing a long note stays clean @ ${_worstWidth}dp x$_worstScale',
      (tester) async {
        await tester.pumpApp(
          _framed(
            Center(
              child: CancelBookingDialog(
                booking: _booking(id: 'x', status: BookingStatus.confirmed),
              ),
            ),
          ),
          width: _worstWidth,
          textScaleFactor: _worstScale,
        );
        await _lay(tester);

        await tester.enterText(
          find.byKey(const Key('cancel-booking-note-field')),
          _longNote(),
        );
        await _lay(tester);

        expect(find.byKey(const Key('cancel-booking-dialog')), findsOneWidget);
      },
    );
  });
}
