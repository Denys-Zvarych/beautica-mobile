// mobile-qa (2026-07-22) — the TWO surfaces that branch on
// `BookingStatus.unknown` and had no test.
//
// `unknown` is the security-S1 arm: a status this build does not recognise,
// which is reachable the moment the backend ships a new booking state ahead of
// a mobile release. Two behaviours hang off it, and BOTH fail silently — the
// screen renders, nothing throws, no overflow guard fires:
//
//   1. `booking_notes.dart` folds `unknown` into `forStatus`'s NO-NOTE branch,
//      deliberately: `providerComment` on an unrecognised status "could be
//      anything", and attributing it under «Коментар майстра»/«Ваш коментар»
//      would put words in someone's mouth on the app's own dispute record.
//      A `switch` arm that fell through to `declined`/`notCompleted` would
//      render that note with a confident, possibly wrong attribution.
//   2. `booking_card.dart`'s `_shadows` gives `unknown` the MIDDLE depth
//      stratum (`extrudedSmall`) — present and tappable, but not claiming
//      CONFIRMED's proud lift, which is the depth cue for "this is
//      happening", nor sinking to the dead-card ground shadow. Depth is the
//      card's non-text status channel (it survives greyscale), so getting it
//      wrong is a real mis-statement, not decoration.
//
// The `unknown` fixtures below deliberately carry EVERY note field populated:
// a booking that has nothing to say would make the no-note assertions pass for
// the wrong reason.

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/booking/application/booking_viewer_role.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_notes.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/booking_fixture_dates.dart';
import '../../../../helpers/pump_app.dart';

const String _clientBrief = 'Без ароматизаторів — алергія.';
const String _clientCancelNote = 'Плани змінилися, вибачте.';
const String _providerNote = 'Майстер захворів, перепрошуємо.';

final AppLocalizations _uk = lookupAppLocalizations(const Locale('uk'));

Booking _booking({
  required BookingStatus status,
  String? clientComment = _clientBrief,
  String? clientCancellationNote = _clientCancelNote,
  String? providerComment = _providerNote,
}) {
  final DateTime start = futureBookingStart();
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c1',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    clientComment: clientComment,
    clientCancellationNote: clientCancellationNote,
    providerComment: providerComment,
  );
}

void main() {
  // ==========================================================================
  // 1. BookingNotes — `unknown` renders NO outcome note, for EITHER viewer
  // ==========================================================================

  group('BookingNotes on an unrecognised status', () {
    for (final BookingViewerRole viewer in BookingViewerRole.values) {
      test('forStatus resolves to null for $viewer — an unrecognised status '
          'never attributes providerComment to anyone', () {
        final Booking b = _booking(status: BookingStatus.unknown);

        expect(
          BookingNoteSpec.forStatus(b, _uk, viewer: viewer),
          isNull,
          reason:
              'the unknown arm fell through to a real status\'s branch, so '
              '«$_providerNote» would render under a confident authorship '
              'heading this build has no basis for',
        );
        // Fixture guard — the same booking DOES produce an outcome note on a
        // recognised status, so the null above is the `unknown` arm's doing
        // and not an empty fixture.
        expect(
          BookingNoteSpec.forStatus(
            _booking(status: BookingStatus.declined),
            _uk,
            viewer: viewer,
          ),
          isNotNull,
        );
      });
    }

    test('the CLIENT BRIEF is unaffected — it is written at booking time and '
        'says nothing about the outcome, so an unknown status must not '
        'suppress it', () {
      final Booking b = _booking(status: BookingStatus.unknown);

      final BookingNoteSpec? brief = BookingNoteSpec.clientBriefFor(
        b,
        _uk,
        viewer: BookingViewerRole.client,
      );
      expect(brief, isNotNull);
      expect(brief!.text, _clientBrief);
      expect(
        BookingNotes.has(b, _uk, viewer: BookingViewerRole.client),
        isTrue,
        reason: 'the brief alone is enough for the block to render',
      );
    });

    testWidgets('the rendered block shows the brief and NOT the provider '
        'comment or the cancellation note', (WidgetTester tester) async {
      await tester.pumpApp(
        BookingNotes(
          booking: _booking(status: BookingStatus.unknown),
          viewer: BookingViewerRole.client,
        ),
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: test fixture note bodies injected by this file, not
      // app copy.
      expect(find.textContaining(_clientBrief), findsOneWidget);
      expect(
        find.textContaining(_providerNote),
        findsNothing,
        reason:
            'the provider comment rendered on an unrecognised status — the '
            'app asserted an authorship it cannot support',
      );
      expect(find.textContaining(_clientCancelNote), findsNothing);
    });

    testWidgets(
      'with ONLY outcome notes present, the block collapses to nothing at all',
      (WidgetTester tester) async {
        await tester.pumpApp(
          // `Center` loosens the constraints — as `MaterialApp.home` the
          // block would be force-expanded to the full surface and its
          // zero-height contract would be unobservable.
          Center(
            child: BookingNotes(
              booking: _booking(
                status: BookingStatus.unknown,
                clientComment: null,
              ),
              viewer: BookingViewerRole.provider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(InboundNote),
          findsNothing,
          reason: 'a recessed well means "somebody wrote this to you"',
        );
        expect(find.byType(OutboundNote), findsNothing);
        expect(find.byType(ClampedNote), findsNothing);
        expect(
          tester.getSize(find.byType(BookingNotes)).height,
          0,
          reason: 'BookingNotes must render a zero-height box, not padding',
        );
      },
    );
  });

  // ==========================================================================
  // 2. BookingCard — the depth stratum per status, `unknown` included
  // ==========================================================================

  group('BookingCard depth stratum (depth-as-time-axis)', () {
    /// The card's own decorated box — the `AnimatedContainer` that carries
    /// `boxShadow`. Scoped to the one whose decoration has the card radius so
    /// an inner decorated child (the photo well, the price pill) cannot be
    /// picked up instead.
    List<BoxShadow>? cardShadows(WidgetTester tester) {
      final Iterable<AnimatedContainer> containers = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byType(BookingCard),
              matching: find.byType(AnimatedContainer),
            ),
          );
      for (final AnimatedContainer c in containers) {
        final Decoration? d = c.decoration;
        if (d is BoxDecoration &&
            d.borderRadius == BorderRadius.circular(VelvetRadii.card)) {
          return d.boxShadow;
        }
      }
      fail('no card-radius AnimatedContainer found under BookingCard');
    }

    Future<List<BoxShadow>?> shadowsFor(
      WidgetTester tester,
      BookingStatus status,
    ) async {
      await tester.pumpApp(
        SingleChildScrollView(
          child: BookingCard(
            booking: _booking(status: status),
            onOpenDetails: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      return cardShadows(tester);
    }

    testWidgets(
      'an UNRECOGNISED status sits in the MIDDLE stratum — the same lift as '
      'COMPLETED/NOT_COMPLETED, never CONFIRMED\'s proud lift and never the '
      'dead-card ground shadow',
      (WidgetTester tester) async {
        final List<BoxShadow>? unknown = await shadowsFor(
          tester,
          BookingStatus.unknown,
        );
        final List<BoxShadow>? completed = await shadowsFor(
          tester,
          BookingStatus.completed,
        );
        final List<BoxShadow>? confirmed = await shadowsFor(
          tester,
          BookingStatus.confirmed,
        );
        final List<BoxShadow>? cancelled = await shadowsFor(
          tester,
          BookingStatus.cancelled,
        );

        expect(unknown, isNotNull);
        expect(
          unknown,
          completed,
          reason:
              'unknown must share the shallow middle stratum with the past '
              'statuses',
        );
        expect(
          unknown,
          isNot(confirmed),
          reason:
              'the proud CONFIRMED lift is the depth cue for "this is '
              'happening" — an unrecognised status must not claim it',
        );
        expect(
          unknown,
          isNot(cancelled),
          reason:
              'the flat dead-card ground shadow says "this appointment is '
              'gone", which is equally a claim this build cannot make',
        );
      },
    );

    testWidgets('the three strata are genuinely distinct — CONFIRMED, the '
        'past group, and the dead group each get their own depth', (
      WidgetTester tester,
    ) async {
      // Positive control for the test above: if every status resolved to the
      // same shadow list, the `isNot` assertions there would be the only
      // thing failing and the cause would be ambiguous.
      final List<BoxShadow>? confirmed = await shadowsFor(
        tester,
        BookingStatus.confirmed,
      );
      final List<BoxShadow>? notCompleted = await shadowsFor(
        tester,
        BookingStatus.notCompleted,
      );
      final List<BoxShadow>? declined = await shadowsFor(
        tester,
        BookingStatus.declined,
      );
      final List<BoxShadow>? cancelled = await shadowsFor(
        tester,
        BookingStatus.cancelled,
      );

      expect(confirmed, isNot(notCompleted));
      expect(notCompleted, isNot(declined));
      expect(
        declined,
        cancelled,
        reason: 'both cancellation states sink to the same flat stratum',
      );
    });
  });
}
