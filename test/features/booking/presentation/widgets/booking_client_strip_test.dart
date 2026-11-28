// M509 — the three ADDITIVE params on BookingClientStrip (`details`, `onTap`,
// `semanticsLabel`) and the proof that omitting them leaves the strip as the
// booking detail / reschedule confirm render it.

import 'package:beautica_mobile/core/media/beautica_image.dart'
    show debugMediaCacheManager;
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_client_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip_shell.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fake_media_cache.dart';
import '../../../../helpers/pump_app.dart';
import '../../../../helpers/rendered_image_url.dart';

const Key _detailsKey = Key('strip-details-probe');

// Walk-in fixture data (named, never a literal at a finder call site).
const String _kFirst = 'Ірина';
const String _kLast = 'Коваль';
const String _kInitials = 'ІК';
const String _kPhone = '+380671234567';
const String _kAvatar = 'https://media.test/avatars/b-iryna.png';
const double _kRating = 4.5;
const int _kRatingCount = 3;

Finder get _shell => find.byKey(BookingClientStrip.defaultShellKey);

Finder _inReadout(String text) => find.descendant(
  of: find.descendant(of: _shell, matching: find.byType(MasterRatingReadout)),
  matching: find.text(text),
);

/// Lets `RemoteImage` build its network `Image` (allow-listed host, no I/O).
void _allowMedia() {
  MediaConfig.debugAllowedHosts = <String>{'media.test'};
  debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
  addTearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
  });
}

void main() {
  group('defaults (booking detail + reschedule confirm)', () {
    testWidgets('no onTap → inert shell, no button semantics, no details', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const BookingClientStrip(
          name: 'Оксана Мельник',
          rating: 4.9,
          reviewCount: 12,
        ),
      );
      final MasterStripShell shell = tester.widget<MasterStripShell>(
        find.byType(MasterStripShell),
      );
      expect(shell.onTap, isNull);
      expect(shell.middleLine, isNull, reason: 'no qualifier, no details');
      expect(find.byType(InkWell), findsNothing);
      handle.dispose();
    });

    testWidgets('an unrated guest shows NO client-kind label and the «—» '
        'readout (CLI-101)', (tester) async {
      await tester.pumpApp(const BookingClientStrip(name: 'Ірина'));
      // CLI-100 (M568): the former «Запис за посиланням» qualifier is gone.
      // i18n-finder-ok: asserts the removed UA copy never renders
      expect(find.text('Запис за посиланням'), findsNothing);
      expect(_inReadout(MasterStrip.noRatingLabel), findsOneWidget);
      final MasterStripShell shell = tester.widget<MasterStripShell>(
        find.byType(MasterStripShell),
      );
      expect(shell.middleLine, isNull, reason: 'no qualifier line');
    });

    testWidgets('the computed semantics label is used when none is given', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const BookingClientStrip(name: 'Оксана', rating: 4.9, reviewCount: 12),
      );
      final SemanticsNode node = tester.getSemantics(
        find.byKey(BookingClientStrip.defaultShellKey),
      );
      expect(node.label, contains('Оксана'));
      expect(node.label, contains('4.9'));
      handle.dispose();
    });
  });

  group('additive params', () {
    testWidgets('details render in the sub-line of a guest, no qualifier', (
      tester,
    ) async {
      await tester.pumpApp(
        const BookingClientStrip(
          name: 'Ірина',
          details: Text('Ост.: 7 лис', key: _detailsKey),
        ),
      );
      expect(find.byKey(_detailsKey), findsOneWidget);
      // CLI-100 (M568): no «Запис за посиланням» above the details.
      // i18n-finder-ok: asserts the removed UA copy never renders
      expect(find.text('Запис за посиланням'), findsNothing);
    });

    testWidgets('details alone (no qualifier) still render', (tester) async {
      await tester.pumpApp(
        const BookingClientStrip(
          name: 'Оксана',
          details: Text('Наст.: пт', key: _detailsKey),
        ),
      );
      expect(find.byKey(_detailsKey), findsOneWidget);
    });

    testWidgets('onTap is forwarded to the shell and fires on tap', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpApp(
        BookingClientStrip(name: 'Оксана', onTap: () => taps++),
      );
      expect(
        tester.widget<MasterStripShell>(find.byType(MasterStripShell)).onTap,
        isNotNull,
      );
      await tester.tap(find.byKey(BookingClientStrip.defaultShellKey));
      expect(taps, 1);
    });

    testWidgets('semanticsLabel replaces the computed label', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const BookingClientStrip(
          name: 'Оксана',
          rating: 4.9,
          reviewCount: 12,
          semanticsLabel: 'власний підпис',
        ),
      );
      final SemanticsNode node = tester.getSemantics(
        find.byKey(BookingClientStrip.defaultShellKey),
      );
      expect(node.label, contains('власний підпис'));
      expect(node.label, isNot(contains('4.9')));
      handle.dispose();
    });
  });

  // 2026-11-25 (BOOK-79/80) — the walk-in review card: a picked client's
  // photo + ★, a hand-typed one's monogram + «—», the phone as sub-line.
  group('BookingClientStrip.walkIn', () {
    testWidgets('a picked client renders its photo and ★ readout', (
      tester,
    ) async {
      _allowMedia();
      await tester.pumpApp(
        BookingClientStrip.walkIn(
          firstName: _kFirst,
          lastName: _kLast,
          phone: _kPhone,
          avatarUrl: _kAvatar,
          rating: _kRating,
          reviewCount: _kRatingCount,
        ),
      );
      expect(renderedImageUrls(tester, within: _shell), <String>[_kAvatar]);
      expect(_inReadout(_kRating.toStringAsFixed(1)), findsOneWidget);
      expect(_inReadout('($_kRatingCount)'), findsOneWidget);
      expect(_inReadout(MasterStrip.noRatingLabel), findsNothing);
      expect(
        find.descendant(of: _shell, matching: find.text('$_kFirst $_kLast')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _shell, matching: find.text(_kPhone)),
        findsOneWidget,
      );
    });

    testWidgets('a hand-typed walk-in falls back to the monogram and «—», '
        'under the «Клієнт» caption', (tester) async {
      _allowMedia();
      await tester.pumpApp(
        Builder(
          builder: (BuildContext context) => BookingClientStrip.walkIn(
            firstName: _kFirst,
            lastName: _kLast,
            phone: _kPhone,
            topLabel: AppLocalizations.of(
              context,
            ).masterCreateBookingGuestLabel,
          ),
        ),
      );
      final AppLocalizations l10n = AppLocalizations.of(tester.element(_shell));
      expect(renderedImageUrls(tester, within: _shell), isEmpty);
      expect(
        find.descendant(of: _shell, matching: find.text(_kInitials)),
        findsOneWidget,
      );
      expect(_inReadout(MasterStrip.noRatingLabel), findsOneWidget);
      expect(
        find.descendant(
          of: _shell,
          matching: find.text(l10n.masterCreateBookingGuestLabel),
        ),
        findsOneWidget,
      );
      // No client-kind label (CLI-100).
      // i18n-finder-ok: asserts the removed UA copy never renders
      expect(find.text('Запис за посиланням'), findsNothing);
    });

    testWidgets('a blank phone draws no sub-line', (tester) async {
      await tester.pumpApp(
        BookingClientStrip.walkIn(
          firstName: _kFirst,
          lastName: _kLast,
          phone: '',
        ),
      );
      expect(
        tester
            .widget<MasterStripShell>(find.byType(MasterStripShell))
            .middleLine,
        isNull,
      );
    });
  });

  group('semanticsDetail (additive, 2026-11-25)', () {
    testWidgets('the walk-in phone is appended to the computed label', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        BookingClientStrip.walkIn(
          firstName: _kFirst,
          lastName: _kLast,
          phone: _kPhone,
          rating: _kRating,
          reviewCount: _kRatingCount,
        ),
      );
      final String label = tester.getSemantics(_shell).label;
      expect(label, contains('$_kFirst $_kLast'));
      expect(label, contains(_kRating.toStringAsFixed(1)));
      expect(label, endsWith(', $_kPhone'));
      handle.dispose();
    });

    testWidgets('an explicit semanticsLabel wins — the detail is ignored', (
      tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpApp(
        const BookingClientStrip(
          name: _kFirst,
          semanticsLabel: 'власний підпис',
          semanticsDetail: _kPhone,
        ),
      );
      final String label = tester.getSemantics(_shell).label;
      expect(label, contains('власний підпис'));
      expect(label, isNot(contains(_kPhone)));
      handle.dispose();
    });
  });

  // M569 (CLI-101): ★ for every client kind, the additive `details`, and the
  // walk-in strip's additive `onTap`.
  group('M569 — one client strip on every provider booking page', () {
    Booking guestBooking({int? reviewCount, double? avg}) {
      final DateTime start = DateTime.utc(2020, 7, 14, 12);
      return Booking(
        id: 'b-guest',
        masterId: 'm1',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        masterType: 'INDEPENDENT_MASTER',
        clientFirstName: _kFirst,
        clientLastName: _kLast,
        clientAvgRating: avg,
        clientReviewCount: reviewCount,
        serviceId: 's1',
        serviceName: 'Манікюр',
        durationMinutes: 60,
        price: 500,
        startAt: start,
        endAt: start.add(const Duration(minutes: 60)),
        status: BookingStatus.completed,
        canReview: false,
      );
    }

    testWidgets('fromBooking: a LINK guest with 3 ratings shows the ★ readout '
        '(was hidden before M569)', (tester) async {
      await tester.pumpApp(
        BookingClientStrip.fromBooking(
          guestBooking(avg: _kRating, reviewCount: _kRatingCount),
        ),
      );
      expect(_inReadout(_kRating.toStringAsFixed(1)), findsOneWidget);
    });

    testWidgets('fromBooking: an unrated guest shows «—»', (tester) async {
      await tester.pumpApp(BookingClientStrip.fromBooking(guestBooking()));
      expect(_inReadout(MasterStrip.noRatingLabel), findsOneWidget);
    });

    testWidgets(
      'fromBooking: details render as the sub-line; none by default',
      (tester) async {
        await tester.pumpApp(
          BookingClientStrip.fromBooking(
            guestBooking(),
            details: const Text('visit', key: _detailsKey),
          ),
        );
        expect(find.byKey(_detailsKey), findsOneWidget);
        await tester.pumpApp(BookingClientStrip.fromBooking(guestBooking()));
        final MasterStripShell shell = tester.widget<MasterStripShell>(
          find.byType(MasterStripShell),
        );
        expect(shell.middleLine, isNull);
      },
    );

    testWidgets('walkIn: onTap makes the strip tappable; absent → inert', (
      tester,
    ) async {
      int taps = 0;
      await tester.pumpApp(
        BookingClientStrip.walkIn(
          firstName: _kFirst,
          lastName: _kLast,
          onTap: () => taps++,
        ),
      );
      await tester.tap(_shell);
      expect(taps, 1);
      await tester.pumpApp(
        BookingClientStrip.walkIn(firstName: _kFirst, lastName: _kLast),
      );
      expect(
        tester.widget<MasterStripShell>(find.byType(MasterStripShell)).onTap,
        isNull,
      );
    });
  });
}
