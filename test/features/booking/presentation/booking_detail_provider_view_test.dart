// Phase 7.2 — the PROVIDER view of «Деталі запису».
//
// One screen, role-branched off the session (locked decision D5). This suite
// proves the branch is real and that it is EXACTLY two things wide — the
// counterparty header and the action footer — with everything else shared.
//
// The regression half matters as much as the new half: the shipped CLIENT
// detail (Phase 14.4) must be behaviourally unchanged, so every provider-view
// assertion here has a client-view twin.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_viewer_role.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_notes.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// Fixture identities injected BY these tests — NOT app copy. They are
// locale-invariant by construction (a person's name is not translated), which
// is exactly the case the `i18n-finder-ok` annotation exists for. Declared once
// so the same constant drives both the fixture and the assertion.
const String _clientFirst = 'Олена';
const String _clientLast = 'Ковальчук';
const String _clientFull = '$_clientFirst $_clientLast';
const String _masterFull = 'Марія Іванюк';
const String _masterTitle = 'Майстриня манікюру';
const String _guestFirst = 'Ірина';
const String _guestLast = 'Гість';
const String _serviceName = 'Манікюр з покриттям';

const String _providerDeclineNote = 'Майстер захворів, перепрошуємо.';
const String _providerNoShowNote = 'Клієнт не прийшов на візит.';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

User _user(UserRole role) => User(id: 'u1', email: 'u@e.com', role: role);

Booking _booking({
  String id = 'b1',
  BookingStatus status = BookingStatus.confirmed,
  String? clientId = 'c1',
  String? clientFirstName = _clientFirst,
  String? clientLastName = _clientLast,
  String? providerComment,
  String? salonName,
  DateTime? startAt,
}) {
  final DateTime start = startAt ?? DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    clientId: clientId,
    clientFirstName: clientFirstName,
    clientLastName: clientLastName,
    serviceId: 's1',
    serviceName: _serviceName,
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    street: 'вул. Городоцька',
    buildingNo: '12',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    providerComment: providerComment,
    masterProfessionalTitle: _masterTitle,
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingDetailScreen)));

/// Pumps «Деталі запису» with [booking], under a session carrying [role].
///
/// The viewer role is derived from `authProvider` — the SAME path production
/// uses — rather than by overriding `bookingViewerRoleProvider` directly. That
/// is deliberate: overriding the derived provider would test the branch while
/// leaving the derivation (the part that can actually be got wrong, and the
/// reason it is not a constructor flag) unexercised.
Future<void> _pump(
  WidgetTester tester,
  Booking booking, {
  required UserRole role,
}) async {
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(_MockBookingRepository()),
      bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
      authProvider.overrideWith(
        () => _StubAuth(
          AuthSession.authenticated(user: _user(role), accessToken: 't'),
        ),
      ),
    ],
  );
  await tester.pumpAndSettle();
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

void main() {
  // -------------------------------------------------------------------------
  // The role derivation itself
  // -------------------------------------------------------------------------

  group('viewer role derivation', () {
    testWidgets('an INDEPENDENT_MASTER session resolves to the provider view', (
      tester,
    ) async {
      await _pump(tester, _booking(), role: UserRole.independentMaster);
      final BookingViewerRole viewer = ProviderScope.containerOf(
        tester.element(find.byType(BookingDetailScreen)),
      ).read(bookingViewerRoleProvider);
      expect(viewer, BookingViewerRole.provider);
      expect(viewer.isProvider, isTrue);
    });

    testWidgets('a CLIENT session resolves to the client view', (tester) async {
      await _pump(tester, _booking(), role: UserRole.client);
      final BookingViewerRole viewer = ProviderScope.containerOf(
        tester.element(find.byType(BookingDetailScreen)),
      ).read(bookingViewerRoleProvider);
      expect(viewer, BookingViewerRole.client);
      expect(viewer.isProvider, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Branch 1 — the counterparty header
  // -------------------------------------------------------------------------

  group('counterparty header', () {
    testWidgets('the MASTER sees the CLIENT, never the master', (tester) async {
      await _pump(tester, _booking(), role: UserRole.independentMaster);

      expect(find.byKey(const Key('booking-detail-client-strip')), findsOne);
      expect(
        find.text(_clientFull),
        findsOne,
      ); // i18n-finder-ok: test fixture name, not app copy
      // The master's own name/title must not appear — the master knows who
      // they are; showing it would waste the identity slot.
      expect(
        find.text(_masterFull),
        findsNothing,
      ); // i18n-finder-ok: test fixture name, not app copy
      expect(
        find.text(_masterTitle),
        findsNothing,
      ); // i18n-finder-ok: test fixture value, not app copy
    });

    testWidgets('the CLIENT still sees the MASTER (14.4 regression gate)', (
      tester,
    ) async {
      await _pump(tester, _booking(), role: UserRole.client);

      expect(
        find.byKey(const Key('booking-detail-client-strip')),
        findsNothing,
      );
      expect(
        find.text(_masterFull),
        findsOne,
      ); // i18n-finder-ok: test fixture name, not app copy
      expect(
        find.text(_clientFull),
        findsNothing,
      ); // i18n-finder-ok: test fixture name, not app copy
    });

    testWidgets(
      'a guest/LINK booking (null clientId) renders its name and marks itself '
      'as a link booking — it does not crash',
      (tester) async {
        // The backend resolves guestName/guestSurname INTO clientFirstName/
        // clientLastName server-side, so a link booking arrives with a real
        // name and a null clientId. That combination is the whole LINK flow.
        await _pump(
          tester,
          _booking(
            clientId: null,
            clientFirstName: _guestFirst,
            clientLastName: _guestLast,
          ),
          role: UserRole.independentMaster,
        );

        expect(tester.takeException(), isNull);
        expect(
          find.text('$_guestFirst $_guestLast'),
          findsOne,
        ); // i18n-finder-ok: test fixture name, not app copy
        expect(
          find.text(_l10n(tester).bookingDetailGuestBookingLabel),
          findsOne,
        );
      },
    );

    testWidgets(
      'a guest booking with NO surname renders the first name alone',
      (tester) async {
        // `guestSurname` is a nullable column — a guest booking legitimately
        // carries a first name and nothing else.
        await _pump(
          tester,
          _booking(
            clientId: null,
            clientFirstName: _guestFirst,
            clientLastName: null,
          ),
          role: UserRole.independentMaster,
        );

        expect(tester.takeException(), isNull);
        expect(
          find.text(_guestFirst),
          findsOne,
        ); // i18n-finder-ok: test fixture name, not app copy
      },
    );

    testWidgets('a nameless record falls back to «Гість» rather than blank', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(clientFirstName: null, clientLastName: null),
        role: UserRole.independentMaster,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_l10n(tester).bookingDetailGuestClient), findsOne);
    });

    testWidgets(
      'the link-booking marker keys off clientId, NOT a missing name — a '
      'registered client with an incomplete profile is never labelled a guest',
      (tester) async {
        await _pump(
          tester,
          // Registered (clientId set) but nameless.
          _booking(clientFirstName: null, clientLastName: null),
          role: UserRole.independentMaster,
        );

        expect(
          find.text(_l10n(tester).bookingDetailGuestBookingLabel),
          findsNothing,
        );
      },
    );

    // mobile-qa (2026-07-20) — `_ClientStrip`'s `isDead` dimming
    // (`booking_counterparty_header.dart`) had no test anywhere in the suite:
    // the only other reference to this widget is a shadow-decoration guard,
    // not a behavioural one. A CANCELLED/DECLINED counterparty must render at
    // `Opacity(0.7)` — the same treatment `MasterStripFromBooking` gives the
    // master strip on the client side — so the two branches read as one
    // screen; a regression here (e.g. the status check inverted or dropped)
    // would silently un-dim a dead booking's client row with nothing to catch
    // it.
    testWidgets('a CANCELLED booking dims the client strip to Opacity(0.7); a '
        'CONFIRMED one renders at full opacity', (tester) async {
      await _pump(
        tester,
        _booking(status: BookingStatus.cancelled),
        role: UserRole.independentMaster,
      );

      final Opacity dimmed = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const Key('booking-detail-client-strip')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(
        dimmed.opacity,
        0.7,
        reason:
            'a CANCELLED booking\'s counterparty must be visibly dimmed, '
            'mirroring MasterStripFromBooking\'s own dead-booking treatment',
      );
    });

    testWidgets(
      'a DECLINED booking also dims the client strip to Opacity(0.7)',
      (tester) async {
        await _pump(
          tester,
          _booking(status: BookingStatus.declined),
          role: UserRole.independentMaster,
        );

        final Opacity dimmed = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(const Key('booking-detail-client-strip')),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(dimmed.opacity, 0.7);
      },
    );

    testWidgets(
      'a CONFIRMED (live) booking renders the client strip at full opacity — '
      'the dimming is status-scoped, not unconditional',
      (tester) async {
        await _pump(
          tester,
          _booking(status: BookingStatus.confirmed),
          role: UserRole.independentMaster,
        );

        final Opacity live = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(const Key('booking-detail-client-strip')),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(live.opacity, 1);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Branch 2 — the footer slot
  // -------------------------------------------------------------------------

  group('footer slot', () {
    testWidgets(
      'the provider footer is EMPTY in 7.2 — no client actions leak through',
      (tester) async {
        // CONFIRMED is the status with the richest client footer, so it is the
        // one that would most visibly leak.
        await _pump(
          tester,
          _booking(status: BookingStatus.confirmed),
          role: UserRole.independentMaster,
        );

        expect(
          find.byKey(const Key('booking-detail-reschedule')),
          findsNothing,
        );
        expect(find.byKey(const Key('booking-detail-cancel')), findsNothing);
        expect(
          find.text(_l10n(tester).bookingDetailRebookCta),
          findsNothing,
          reason:
              '«Записатись знову» would have the master book themselves — it '
              'is a client capability, not merely a hidden one.',
        );
      },
    );

    testWidgets('no client footer at any status for a provider viewer', (
      tester,
    ) async {
      for (final BookingStatus status in BookingStatus.filterable) {
        await _pump(
          tester,
          _booking(status: status),
          role: UserRole.independentMaster,
        );
        // A POSITIVE anchor first. Every assertion below is a `findsNothing`,
        // and a `findsNothing` passes just as happily against a stale or
        // half-built tree as against a correct one — so prove the screen for
        // THIS status actually rendered before trusting the absences.
        expect(
          find.byKey(const Key('booking-detail-client-strip')),
          findsOne,
          reason: 'the provider view did not render at $status',
        );
        expect(
          find.byKey(const Key('booking-detail-reschedule')),
          findsNothing,
          reason: 'reschedule leaked at $status',
        );
        expect(
          find.byKey(const Key('booking-detail-cancel')),
          findsNothing,
          reason: 'cancel leaked at $status',
        );
        expect(
          find.byKey(const Key('booking-detail-leave-review')),
          findsNothing,
          reason: 'leave-review leaked at $status',
        );
      }
    });

    testWidgets(
      'the CLIENT footer is untouched — CONFIRMED still offers reschedule + '
      'cancel (14.4 regression gate)',
      (tester) async {
        await _pump(
          tester,
          _booking(status: BookingStatus.confirmed),
          role: UserRole.client,
        );

        expect(find.byKey(const Key('booking-detail-reschedule')), findsOne);
        expect(find.byKey(const Key('booking-detail-cancel')), findsOne);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Everything else is SHARED — the branch must not have widened
  // -------------------------------------------------------------------------

  group('shared surface', () {
    testWidgets('price renders with «₴» for the provider viewer', (
      tester,
    ) async {
      await _pump(tester, _booking(), role: UserRole.independentMaster);
      expect(find.textContaining('650 ₴'), findsWidgets);
      expect(find.textContaining('грн'), findsNothing);
    });

    testWidgets('the service name renders for both viewers', (tester) async {
      for (final UserRole role in <UserRole>[
        UserRole.independentMaster,
        UserRole.client,
      ]) {
        await _pump(tester, _booking(), role: role);
        expect(
          // i18n-finder-ok: test fixture service name, not app copy
          find.text(_serviceName),
          findsOne,
          reason: 'service name missing for $role',
        );
      }
    });

    // Locked product decision (2026-07-14): booking notes are symmetric and
    // mutually visible. The client seeing a provider's no-show account is
    // INTENDED — audience-based suppression was explicitly rejected, so these
    // two tests exist to fail loudly if someone later "fixes" it as a leak.
    //
    // One status per test (rather than both in a loop): each needs its own
    // fresh pump, and a shared-tester loop obscures which status regressed.
    testWidgets(
      'providerComment renders for the CLIENT on DECLINED — pins mutual '
      'visibility against a future "privacy fix"',
      (tester) async {
        await _pump(
          tester,
          _booking(
            status: BookingStatus.declined,
            providerComment: _providerDeclineNote,
          ),
          role: UserRole.client,
        );
        expect(find.byType(BookingNotes), findsOne);
        expect(find.textContaining(_providerDeclineNote), findsOne);
      },
    );

    testWidgets(
      'providerComment renders for the CLIENT on NOT_COMPLETED — the no-show '
      'account is deliberately visible to the client, not suppressed',
      (tester) async {
        await _pump(
          tester,
          _booking(
            status: BookingStatus.notCompleted,
            providerComment: _providerNoShowNote,
          ),
          role: UserRole.client,
        );
        expect(find.byType(BookingNotes), findsOne);
        expect(find.textContaining(_providerNoShowNote), findsOne);
      },
    );

    testWidgets('notes render for the PROVIDER viewer too — no suppression', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(
          status: BookingStatus.declined,
          providerComment: _providerDeclineNote,
        ),
        role: UserRole.independentMaster,
      );
      expect(find.byType(BookingNotes), findsOne);
      expect(find.textContaining(_providerDeclineNote), findsOne);
    });
  });

  // -------------------------------------------------------------------------
  // Branch 3 — add-to-calendar is CLIENT-ONLY (security finding S1)
  // -------------------------------------------------------------------------
  //
  // `booking_detail_screen.dart` gates the calendar icon on
  // `!viewer.isProvider && canAddToCalendar && !isPast`. The `!viewer.isProvider`
  // half is a PRIVACY control, not a layout choice: the event body is composed
  // from the counterparty identity, so on the provider side the export would
  // write the CLIENT's name (and the visit address) into the device calendar —
  // a third-party store, frequently cloud-synced, outside the app's control.
  //
  // That half was deleted during review and all 786 booking tests still passed:
  // `canAddToCalendar` is a pure STATUS predicate and every other assertion
  // about the icon happens to pump a CLIENT session, so nothing observed the
  // role at all. These two tests are the only thing standing between that
  // deletion and a silent PII leak.
  //
  // Both halves are asserted deliberately. Absent-for-provider alone would pass
  // if the icon disappeared for EVERYONE (e.g. the status gate inverted), which
  // is a different bug wearing the same green tick — so the client-side twin
  // pins that the control still exists at all.

  group('add-to-calendar is client-only (S1)', () {
    /// A CONFIRMED booking comfortably in the future, so the `!isPast` half of
    /// the gate is satisfied and the role half is what is under test.
    ///
    /// Derived from `DateTime.now()` rather than a literal on purpose: `isPast`
    /// compares against the wall clock, so a hardcoded date would quietly turn
    /// both tests vacuous the day it elapsed — the icon would be absent for the
    /// client for the WRONG reason and the provider assertion would pass
    /// without exercising the gate.
    Booking futureConfirmed() =>
        _booking(startAt: DateTime.now().toUtc().add(const Duration(days: 30)));

    testWidgets('the PROVIDER never gets the calendar action', (tester) async {
      await _pump(tester, futureConfirmed(), role: UserRole.independentMaster);

      expect(
        find.byKey(const Key('booking-detail-add-calendar')),
        findsNothing,
        reason:
            'The provider view exposed add-to-calendar. The event is composed '
            'from the counterparty identity, so exporting it here writes the '
            "CLIENT's name and the visit address into the device calendar. The "
            '`!viewer.isProvider` half of the gate has been removed.',
      );
    });

    testWidgets('the CLIENT still gets it (control — the gate is role-scoped, '
        'not a blanket removal)', (tester) async {
      await _pump(tester, futureConfirmed(), role: UserRole.client);

      expect(
        find.byKey(const Key('booking-detail-add-calendar')),
        findsOne,
        reason:
            'The calendar action vanished for the CLIENT too, so the '
            'provider-side assertion above is no longer evidence of anything. '
            'Suspect the status/isPast half of the gate rather than the role '
            'half.',
      );
    });
  });
}
