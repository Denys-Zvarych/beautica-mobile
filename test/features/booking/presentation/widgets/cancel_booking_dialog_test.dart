// mobile-qa (booking-UI trim, 2026-07-15) — `CancelBookingDialog` note field.
//
// The «Майстер побачить цей коментар.» promise sub-line (`cancelBookingNotePromise`)
// was removed: the note is still OPTIONAL free text, but no longer advertises
// that the provider reads it. Its l10n key is deleted, so a literal re-add is
// already a compile break — this suite guards the STRUCTURAL and BEHAVIOURAL
// contract that a getter deletion alone doesn't:
//   • the note field now shows exactly its label + the field + the live counter
//     (no promise line wedged between the label and the input well);
//   • the field is still present and its text is still submitted intact —
//     confirming resolves to the trimmed note, an empty note resolves to '',
//     and backing out resolves to null (nothing cancelled).
//
// Drives `showCancelBookingDialog` directly (the same entry point
// `BookingDetailScreen` uses) so the resolved value — the exact payload
// `BookingRepository.cancelBooking` receives — is asserted at the source.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/cancel_booking_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

Booking _booking() {
  final DateTime start = DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

void main() {
  /// Pumps a host that opens the cancel dialog on first frame and captures its
  /// resolved value (the note string, or null on back-out).
  Future<void> pumpDialog(
    WidgetTester tester, {
    required void Function(String?) onResolved,
  }) async {
    // Tall surface so the whole dialog (incl. the bottom «Не скасовувати» button)
    // is on-screen and hit-testable without scrolling.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpApp(
      Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () async {
                final String? r = await showCancelBookingDialog(
                  context,
                  _booking(),
                );
                onResolved(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel-booking-dialog')), findsOneWidget);
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byKey(const Key('open'))));

  testWidgets(
    'the note field shows only its label + input + counter — the removed '
    'provider-reads-this promise line is absent',
    (tester) async {
      await pumpDialog(tester, onResolved: (_) {});
      final l10n = l10nOf(tester);

      // The note field and its label are still present.
      expect(
        find.byKey(const Key('cancel-booking-note-field')),
        findsOneWidget,
      );
      expect(find.text(l10n.cancelBookingNoteLabel), findsOneWidget);

      // Its immediate Column (the `_NoteField` body) carries exactly TWO header
      // Text widgets OUTSIDE the input well: the label and the live counter. The
      // hint Text lives INSIDE the field, so exclude the field subtree. The
      // deleted promise line would have made a third header Text — this count is
      // the structural regression guard.
      final Finder noteColumn = find
          .ancestor(
            of: find.byKey(const Key('cancel-booking-note-field')),
            matching: find.byType(Column),
          )
          .first;
      final int totalTexts = find
          .descendant(of: noteColumn, matching: find.byType(Text))
          .evaluate()
          .length;
      final int textsInField = find
          .descendant(
            of: find.byKey(const Key('cancel-booking-note-field')),
            matching: find.byType(Text),
          )
          .evaluate()
          .length;
      expect(
        totalTexts - textsInField,
        2,
        reason:
            'label + counter only; a re-added promise sub-line would make three',
      );
    },
  );

  testWidgets('confirming WITH a note resolves to the trimmed note', (
    tester,
  ) async {
    String? resolved;
    bool done = false;
    await pumpDialog(
      tester,
      onResolved: (String? r) {
        resolved = r;
        done = true;
      },
    );

    await tester.enterText(
      find.byKey(const Key('cancel-booking-note-field')),
      '  Захворіла.  ',
    );
    await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(resolved, 'Захворіла.');
  });

  testWidgets('confirming with an EMPTY note resolves to an empty string', (
    tester,
  ) async {
    String? resolved;
    bool done = false;
    await pumpDialog(
      tester,
      onResolved: (String? r) {
        resolved = r;
        done = true;
      },
    );

    await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(resolved, '');
  });

  testWidgets('backing out with «Не скасовувати» resolves to null', (
    tester,
  ) async {
    String? resolved;
    bool done = false;
    await pumpDialog(
      tester,
      onResolved: (String? r) {
        resolved = r;
        done = true;
      },
    );

    await tester.tap(find.byKey(const Key('cancel-booking-keep')));
    await tester.pumpAndSettle();

    expect(done, isTrue);
    expect(resolved, isNull);
  });
}
