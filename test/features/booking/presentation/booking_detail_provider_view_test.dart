// Phase 7.2 — the PROVIDER view of «Деталі запису».
//
// One screen, role-branched off the session (locked decision D5). This suite
// proves the branch is real and that it is EXACTLY two things wide — the
// counterparty header and the action footer — with everything else shared.
//
// The regression half matters as much as the new half: the shipped CLIENT
// detail (Phase 14.4) must be behaviourally unchanged, so every provider-view
// assertion here has a client-view twin.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_viewer_role.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_counterparty_header.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_notes.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/dim_probe.dart';
import '../../../helpers/fake_media_cache.dart';
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
const String _clientBriefNote = 'Без ароматизаторів — алергія.';
const String _clientCancelNote = 'Плани змінилися, вибачте.';

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
  String masterId = 'm1',
  String? salonId,
  BookingStatus status = BookingStatus.confirmed,
  String? clientId = 'c1',
  String? clientFirstName = _clientFirst,
  String? clientLastName = _clientLast,
  String? providerComment,
  String? clientComment,
  String? clientCancellationNote,
  String? clientAvatarUrl,
  double? clientAvgRating,
  int? clientReviewCount,
  String? salonName,
  DateTime? startAt,
}) {
  final DateTime start = startAt ?? futureBookingStart();
  return Booking(
    id: id,
    masterId: masterId,
    salonId: salonId,
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    clientId: clientId,
    clientFirstName: clientFirstName,
    clientLastName: clientLastName,
    clientAvatarUrl: clientAvatarUrl,
    clientAvgRating: clientAvgRating,
    clientReviewCount: clientReviewCount,
    serviceId: 's1',
    serviceName: _serviceName,
    categoryName: 'NAIL_SERVICE',
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
    clientComment: clientComment,
    clientCancellationNote: clientCancellationNote,
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
  MasterMeCallCounter? masterMeCalls,
}) async {
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(_MockBookingRepository()),
      bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
      // Spy: `GET /masters/me` must never be read by this screen.
      if (masterMeCalls != null)
        masterProfileProvider.overrideWith(
          () => _CountingMasterProfile(masterMeCalls),
        ),
      authProvider.overrideWith(
        () => _StubAuth(
          AuthSession.authenticated(user: _user(role), accessToken: 't'),
        ),
      ),
    ],
  );
  await tester.pumpAndSettle();
}

/// Counts `GET /masters/me` builds — the screen must make none.
class MasterMeCallCounter {
  int builds = 0;
}

class _CountingMasterProfile extends MasterProfile {
  _CountingMasterProfile(this._counter);

  final MasterMeCallCounter _counter;

  @override
  Future<Master> build() async {
    _counter.builds++;
    return const Master(
      id: 'owner-master',
      firstName: 'Власна',
      lastName: 'Майстриня',
      reviewCount: 0,
      type: MasterType.salonOwner,
    );
  }
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
    // Track 27.x Wave A filled the provider footer with its OWN actions
    // (reschedule/decline/complete — see `booking_detail_provider_footer_test
    // .dart`). What stays pinned HERE is narrower but still load-bearing: no
    // CLIENT-keyed action ever leaks into a provider viewer, at any status.
    testWidgets(
      'CONFIRMED never leaks a CLIENT action to the provider footer',
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
  // Branch 4 — NOTE FRAMING is viewer-relative (mobile-security LOW,
  // 2026-07-22)
  // -------------------------------------------------------------------------
  //
  // Every note assertion in the "shared surface" group above stops at
  // `find.byType(BookingNotes), findsOne` plus the note BODY. That is exactly
  // the coverage that let the framing bug ship in the first place: the block
  // renders, and the words are there, whichever heading and whichever
  // container the app wrapped them in. On `/master/bookings/:id` a master was
  // reading the CLIENT's brief under «Ваші побажання» (*your* wishes) and the
  // client's cancellation note under «Ваша причина» (*your* reason), while
  // their OWN `providerComment` came back in the recessed [InboundNote] well —
  // the container that means "somebody else wrote this to you". Every
  // attribution on the app's own dispute record was inverted for the provider,
  // and the whole suite stayed green.
  //
  // So these tests assert the two things the body text cannot:
  //   • the HEADING (resolved through l10n — never a Cyrillic literal), and
  //   • the CONTAINER, which is the library's primary authorship signal
  //     ("depth is authorship": [InboundNote]'s recessed well = arrived,
  //     [OutboundNote]'s hairline rule = your own words).
  //
  // Each provider-view case has its CLIENT-view twin, because a framing fix
  // that simply inverted the rule everywhere would satisfy either half alone.

  group('note framing is viewer-relative', () {
    /// The container [note] is rendered inside — the authorship signal.
    /// Returns `InboundNote` / `OutboundNote` as a Type so failures name the
    /// wrong container directly.
    Type containerOf(WidgetTester tester, String noteText) {
      final Finder text = find.textContaining(noteText);
      expect(
        text,
        findsOneWidget,
        reason: 'the note body «$noteText» did not render at all',
      );
      final bool inbound = find
          .ancestor(of: text, matching: find.byType(InboundNote))
          .evaluate()
          .isNotEmpty;
      return inbound ? InboundNote : OutboundNote;
    }

    // ── The client's booking-time brief ──────────────────────────────────

    testWidgets(
      'PROVIDER view: the client\'s brief arrives — «Побажання клієнта», in '
      'the recessed inbound well',
      (tester) async {
        await _pump(
          tester,
          _booking(clientComment: _clientBriefNote),
          role: UserRole.independentMaster,
        );

        expect(
          find.text(_l10n(tester).bookingNoteHeadingClientWishes),
          findsOne,
          reason:
              'the master read the client\'s brief under a «Ваші …» heading '
              '— the note is not theirs',
        );
        expect(
          find.text(_l10n(tester).bookingNoteHeadingYourWishes),
          findsNothing,
        );
        expect(
          containerOf(tester, _clientBriefNote),
          InboundNote,
          reason:
              'the client\'s brief rendered in the hairline OUTBOUND '
              'container on the PROVIDER view. Depth is authorship (see '
              '`booking_notes.dart`\'s library doc): words that ARRIVED must '
              'sit in the recessed well, or the container contradicts the '
              'heading directly above it.',
        );
      },
    );

    testWidgets(
      'CLIENT view: the same brief is handed back — «Ваші побажання», as '
      'outbound marginalia (regression twin)',
      (tester) async {
        await _pump(
          tester,
          _booking(clientComment: _clientBriefNote),
          role: UserRole.client,
        );

        expect(find.text(_l10n(tester).bookingNoteHeadingYourWishes), findsOne);
        expect(
          find.text(_l10n(tester).bookingNoteHeadingClientWishes),
          findsNothing,
        );
        expect(containerOf(tester, _clientBriefNote), OutboundNote);
      },
    );

    // ── The client's cancellation note ───────────────────────────────────

    testWidgets(
      'PROVIDER view: the client\'s cancellation note arrives — «Причина '
      'клієнта», inbound',
      (tester) async {
        await _pump(
          tester,
          _booking(
            status: BookingStatus.cancelled,
            clientCancellationNote: _clientCancelNote,
          ),
          role: UserRole.independentMaster,
        );

        expect(
          find.text(_l10n(tester).bookingNoteHeadingClientReason),
          findsOne,
        );
        expect(
          find.text(_l10n(tester).bookingNoteHeadingYourReason),
          findsNothing,
          reason:
              '«Ваша причина» told the master they cancelled their own '
              'booking — the client did',
        );
        expect(containerOf(tester, _clientCancelNote), InboundNote);
      },
    );

    testWidgets(
      'CLIENT view: their own cancellation note is «Ваша причина», outbound '
      '(regression twin)',
      (tester) async {
        await _pump(
          tester,
          _booking(
            status: BookingStatus.cancelled,
            clientCancellationNote: _clientCancelNote,
          ),
          role: UserRole.client,
        );

        expect(find.text(_l10n(tester).bookingNoteHeadingYourReason), findsOne);
        expect(
          find.text(_l10n(tester).bookingNoteHeadingClientReason),
          findsNothing,
        );
        expect(containerOf(tester, _clientCancelNote), OutboundNote);
      },
    );

    // ── The provider's own comment ───────────────────────────────────────

    testWidgets(
      'PROVIDER view: their OWN decline comment is «Ваш коментар», outbound — '
      'never recessed as though it had arrived',
      (tester) async {
        await _pump(
          tester,
          _booking(
            status: BookingStatus.declined,
            providerComment: _providerDeclineNote,
          ),
          role: UserRole.independentMaster,
        );

        expect(
          find.text(_l10n(tester).bookingNoteHeadingYourComment),
          findsOne,
        );
        expect(
          containerOf(tester, _providerDeclineNote),
          OutboundNote,
          reason:
              'the master\'s own words came back in the recessed inbound '
              'well — the container that means "somebody else wrote this to '
              'you"',
        );
      },
    );

    testWidgets(
      'PROVIDER view: the same holds for a NOT_COMPLETED (no-show) account',
      (tester) async {
        await _pump(
          tester,
          _booking(
            status: BookingStatus.notCompleted,
            providerComment: _providerNoShowNote,
          ),
          role: UserRole.independentMaster,
        );

        expect(
          find.text(_l10n(tester).bookingNoteHeadingYourComment),
          findsOne,
        );
        expect(containerOf(tester, _providerNoShowNote), OutboundNote);
      },
    );

    testWidgets(
      'CLIENT view: the provider\'s comment is attributed to them and arrives '
      'inbound (regression twin)',
      (tester) async {
        final Booking b = _booking(
          status: BookingStatus.declined,
          providerComment: _providerDeclineNote,
        );
        await _pump(tester, b, role: UserRole.client);

        expect(
          find.text(
            _l10n(tester).bookingNoteHeadingProviderComment(b.providerGenitive),
          ),
          findsOne,
        );
        expect(
          find.text(_l10n(tester).bookingNoteHeadingYourComment),
          findsNothing,
          reason:
              '«Ваш коментар» would tell the client they wrote the '
              'provider\'s decline reason',
        );
        expect(containerOf(tester, _providerDeclineNote), InboundNote);
      },
    );

    // ── Both notes at once: the two containers must DIFFER ────────────────

    testWidgets(
      'PROVIDER view: a booking carrying BOTH the client\'s brief and the '
      'provider\'s own comment renders them in DIFFERENT containers — the '
      'distinction is the point',
      (tester) async {
        // The library doc's motivating case, from the provider's side: one
        // screen, two notes, opposite authorship. If both collapse into the
        // same container the reader has lost the primary signal, even with
        // correct headings.
        await _pump(
          tester,
          _booking(
            status: BookingStatus.declined,
            clientComment: _clientBriefNote,
            providerComment: _providerDeclineNote,
          ),
          role: UserRole.independentMaster,
        );

        expect(containerOf(tester, _clientBriefNote), InboundNote);
        expect(containerOf(tester, _providerDeclineNote), OutboundNote);
        expect(
          containerOf(tester, _clientBriefNote),
          isNot(containerOf(tester, _providerDeclineNote)),
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Branch 5 — the CONFIRMED reminder subline is CLIENT-ONLY
  // (mobile-qa, 2026-07-26)
  // -------------------------------------------------------------------------
  //
  // `_subline`'s CONFIRMED branch returns `l10n.bookingDetailSublineConfirmed`
  // («Нагадаємо про запис напередодні.») — a promise the APP makes to the
  // CLIENT: it will remind them the day before. The PROVIDER makes no such
  // promise to themselves, so the branch now short-circuits to `null` when
  // `viewer.isProvider`, and the master no longer reads a reminder addressed to
  // the client. The role is resolved through `bookingViewerRoleProvider`, so a
  // session that fails to resolve fails CLOSED to the client (who is entitled
  // to the reminder), never the other way.
  //
  // The fixture is a FUTURE CONFIRMED booking on purpose: `_subline` has a
  // SECOND `null` gate for an elapsed booking (`b.isPast`), so an accidentally
  // past fixture would make the provider assertion pass for the wrong reason
  // and turn the client twin vacuous. `_booking()` defaults to
  // `futureBookingStart()`, keeping the role half the only thing under test.
  //
  // Both halves are asserted: absent-for-provider alone would also pass if the
  // subline vanished for EVERYONE, so the client twin pins that the reminder
  // still ships at all.

  group('CONFIRMED reminder subline is client-only', () {
    testWidgets('the PROVIDER does not see the day-before reminder subline', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(status: BookingStatus.confirmed),
        role: UserRole.independentMaster,
      );

      expect(
        find.text(_l10n(tester).bookingDetailSublineConfirmed),
        findsNothing,
        reason:
            'The provider view rendered «Нагадаємо про запис напередодні.» — '
            'a reminder the app promises the CLIENT, not the master. The '
            '`viewer.isProvider` short-circuit in `_subline`\'s CONFIRMED '
            'branch has been removed.',
      );
    });

    testWidgets(
      'the CLIENT still sees it (control — suppression is role-scoped, not a '
      'blanket removal)',
      (tester) async {
        await _pump(
          tester,
          _booking(status: BookingStatus.confirmed),
          role: UserRole.client,
        );

        expect(
          find.text(_l10n(tester).bookingDetailSublineConfirmed),
          findsOneWidget,
          reason:
              'The reminder vanished for the CLIENT too, so the provider-side '
              'assertion above is no longer evidence of anything. Suspect the '
              'CONFIRMED branch or the isPast gate rather than the role half.',
        );
      },
    );
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
    Booking futureConfirmed() => _booking(startAt: futureBookingStart());

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
  // The `Opacity.opacity` field assertions above prove the WIDGET is configured,
  // not that the pixels dim (Phase 299: CI goldens discard layer opacity, and a
  // field read cannot see the compositor). Phase 301 observes `_ClientStrip`'s
  // `isDead ? 0.7 : 1` through the real compositor.
  //
  // The strip's content does not depend on status, so the same `_booking`
  // fixture CONFIRMED vs CANCELLED/DECLINED differs ONLY in the dim. The public
  // header is pumped twice side by side, each in its own boundary over a solid
  // `base` ground. Tolerance 0.04: 8-bit rounding of `0.7·d` on the avatar's
  // soft edges biases the summed ratio a touch low (see the master-strip probe
  // in booking_detail_screen_test.dart, which measures 0.670).
  group('Phase 301 — client strip dim on a dead booking (pixel probe)', () {
    const Key keyFull = Key('client-strip-dim-full');
    const Key keyDim = Key('client-strip-dim-dim');

    Widget cell(Key key, Booking b) => RepaintBoundary(
      key: key,
      child: ColoredBox(
        color: BrandColors.base,
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.md),
          child: SizedBox(
            width: 340,
            child: BookingCounterpartyHeader(
              booking: b,
              viewer: BookingViewerRole.provider,
            ),
          ),
        ),
      ),
    );

    Future<void> probe(
      WidgetTester tester, {
      required BookingStatus status,
      required double expected,
    }) async {
      await tester.pumpApp(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            cell(keyFull, _booking()),
            cell(keyDim, _booking(status: status)),
          ],
        ),
      );
      await tester.pump();

      await expectDimRatio(
        tester: tester,
        dimmed: find.byKey(keyDim),
        full: find.byKey(keyFull),
        ground: BrandColors.base,
        expected: expected,
        tolerance: 0.04,
      );
    }

    testWidgets(
      'a CANCELLED client strip composites to 0.7 of the live one',
      (tester) => probe(tester, status: BookingStatus.cancelled, expected: 0.7),
    );

    testWidgets(
      'a DECLINED client strip composites to 0.7 of the live one',
      (tester) => probe(tester, status: BookingStatus.declined, expected: 0.7),
    );

    // The 0.04 band cannot see a 0.7 -> 0.73/0.75 drift. This pins the dim
    // TIGHTLY against the SAME live header hand-wrapped in `Opacity(0.7)`: both
    // sides share the 8-bit rounding bias, so the ratio is 1.0 +- 0.015.
    for (final BookingStatus dead in <BookingStatus>[
      BookingStatus.cancelled,
      BookingStatus.declined,
    ]) {
      testWidgets('a $dead client strip matches a hand-wrapped Opacity(0.7) '
          'control', (tester) async {
        const Key keyControl = Key('client-strip-dim-control');
        await tester.pumpApp(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RepaintBoundary(
                key: keyControl,
                child: ColoredBox(
                  color: BrandColors.base,
                  child: Opacity(
                    opacity: 0.7,
                    child: Padding(
                      padding: const EdgeInsets.all(VelvetSpacing.md),
                      child: SizedBox(
                        width: 340,
                        child: BookingCounterpartyHeader(
                          booking: _booking(),
                          viewer: BookingViewerRole.provider,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              cell(keyDim, _booking(status: dead)),
            ],
          ),
        );
        await tester.pump();

        await expectDimRatio(
          tester: tester,
          dimmed: find.byKey(keyDim),
          full: find.byKey(keyControl),
          ground: BrandColors.base,
          expected: 1.0,
          tolerance: 0.015,
        );
      });
    }

    testWidgets(
      'a COMPLETED client strip is NOT dimmed (ratio 1.0)',
      (tester) => probe(tester, status: BookingStatus.completed, expected: 1.0),
    );
  });

  group('client strip photo (provider viewer)', () {
    const String host = 'cdn.example.com';
    const String photoUrl = 'https://$host/avatars/client-1.png';
    const Key photoKey = Key('booking-detail-client-avatar-photo');
    final Finder strip = find.byKey(const Key('booking-detail-client-strip'));
    late FakeMediaCacheManager fake;

    setUp(() {
      MediaConfig.debugAllowedHosts = <String>{host};
      fake = FakeMediaCacheManager(mediaLoadingForever);
      debugMediaCacheManager = fake;
    });

    tearDown(() {
      debugMediaCacheManager = null;
      MediaConfig.debugAllowedHosts = null;
      imageCache.clear();
      imageCache.clearLiveImages();
    });

    testWidgets('an allowlisted https clientAvatarUrl renders the photo from '
        'that exact URL, not the monogram', (tester) async {
      fake.responder = mediaLoaded;
      final Booking b = _booking(clientAvatarUrl: photoUrl);
      await _pump(tester, b, role: UserRole.independentMaster);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      final Finder img = find.descendant(
        of: find.byKey(photoKey),
        matching: find.byType(Image),
      );
      expect(img, findsOneWidget);
      final ImageProvider<Object> provider = tester.widget<Image>(img).image;
      expect(provider, isA<ResizeImage>());
      final ImageProvider<Object> inner =
          (provider as ResizeImage).imageProvider;
      expect(inner, isA<CachedNetworkImageProvider>());
      expect((inner as CachedNetworkImageProvider).url, photoUrl);
      expect(fake.getFileStreamCalls, greaterThan(0));
      expect(
        find.descendant(of: strip, matching: find.text(b.clientInitials!)),
        findsNothing,
        reason: 'a loaded photo replaces the monogram',
      );
    });

    testWidgets('a null clientAvatarUrl shows the monogram and no network '
        'image', (tester) async {
      final Booking b = _booking();
      await _pump(tester, b, role: UserRole.independentMaster);

      expect(b.clientInitials, isNotEmpty);
      expect(
        find.descendant(of: strip, matching: find.text(b.clientInitials!)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: strip, matching: find.byType(Image)),
        findsNothing,
      );
      expect(fake.getFileStreamCalls, 0);
    });

    for (final String bad in <String>[
      'http://$host/avatars/client-1.png',
      'https://evil.example.net/avatars/client-1.png',
    ]) {
      testWidgets('a rejected URL ($bad) shows the monogram and never '
          'fetches', (tester) async {
        final Booking b = _booking(clientAvatarUrl: bad);
        await _pump(tester, b, role: UserRole.independentMaster);

        expect(
          find.descendant(of: strip, matching: find.text(b.clientInitials!)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: strip, matching: find.byType(Image)),
          findsNothing,
        );
        expect(fake.getFileStreamCalls, 0);
      });
    }
  });

  group('client strip rating readout (provider viewer)', () {
    final Finder strip = find.byKey(const Key('booking-detail-client-strip'));

    testWidgets('a rated registered client shows ★ 4.7 and the review count', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(clientAvgRating: 4.7, clientReviewCount: 12),
        role: UserRole.independentMaster,
      );
      expect(find.descendant(of: strip, matching: find.text('4.7')), findsOne);
      expect(find.descendant(of: strip, matching: find.text('(12)')), findsOne);
      final double figureX = tester
          .getTopLeft(find.descendant(of: strip, matching: find.text('4.7')))
          .dx;
      final double countX = tester
          .getTopLeft(find.descendant(of: strip, matching: find.text('(12)')))
          .dx;
      expect(
        figureX,
        lessThan(countX),
        reason: 'the figure precedes the count: «★ 4.7 (12)»',
      );
      expect(
        find.descendant(of: strip, matching: find.byIcon(Icons.star_rounded)),
        findsOne,
      );
    });

    testWidgets(
      'an unreviewed registered client shows the em-dash, never 0.0',
      (tester) async {
        await _pump(
          tester,
          _booking(clientAvgRating: 0, clientReviewCount: 0),
          role: UserRole.independentMaster,
        );
        expect(find.descendant(of: strip, matching: find.text('—')), findsOne);
        expect(
          find.descendant(of: strip, matching: find.text('0.0')),
          findsNothing,
        );
      },
    );

    testWidgets('an unreviewed client\'s semantics say "no reviews yet", not '
        '«Рейтинг —»', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await _pump(
        tester,
        _booking(clientAvgRating: null, clientReviewCount: 0),
        role: UserRole.independentMaster,
      );
      final String label = tester.getSemantics(strip).label;
      expect(label, contains(_l10n(tester).masterReviewsEmpty));
      expect(label, isNot(contains('Рейтинг')));
      handle.dispose();
    });

    testWidgets('a guest booking shows NO rating at all', (tester) async {
      await _pump(
        tester,
        _booking(clientId: null),
        role: UserRole.independentMaster,
      );
      expect(
        find.descendant(of: strip, matching: find.byIcon(Icons.star_rounded)),
        findsNothing,
      );
      expect(
        find.descendant(of: strip, matching: find.text('—')),
        findsNothing,
      );
    });
  });

  group('performing-master strip (salon viewer)', () {
    const Key strip = Key('booking-detail-performing-master-strip');

    testWidgets('an OWNER sees the strip with the master name on another '
        'master\'s salon booking', (tester) async {
      await _pump(
        tester,
        _booking(salonName: 'Салон'),
        role: UserRole.salonOwner,
      );
      expect(find.byKey(strip), findsOne);
      expect(
        find.descendant(
          of: find.byKey(strip),
          matching: find.text(_masterFull),
        ),
        findsOne,
      ); // i18n-finder-ok: test fixture name, not app copy
      expect(find.byKey(const Key('booking-detail-client-strip')), findsOne);
    });

    testWidgets('an OWNER sees the strip on a booking whose master row is '
        'their own, and makes NO /masters/me call', (tester) async {
      final MasterMeCallCounter calls = MasterMeCallCounter();
      await _pump(
        tester,
        _booking(salonName: 'Салон', masterId: 'owner-master'),
        role: UserRole.salonOwner,
        masterMeCalls: calls,
      );
      expect(find.byKey(strip), findsOne);
      expect(
        find.descendant(
          of: find.byKey(strip),
          matching: find.text(_masterFull),
        ),
        findsOne,
      ); // i18n-finder-ok: test fixture name, not app copy
      expect(find.byKey(const Key('booking-detail-client-strip')), findsOne);
      expect(calls.builds, 0);
    });

    testWidgets('an ADMIN sees the strip, and makes NO /masters/me call', (
      tester,
    ) async {
      final MasterMeCallCounter calls = MasterMeCallCounter();
      await _pump(
        tester,
        _booking(salonName: 'Салон'),
        role: UserRole.salonAdmin,
        masterMeCalls: calls,
      );
      expect(find.byKey(strip), findsOne);
      expect(calls.builds, 0);
    });

    testWidgets('a SALON_MASTER never sees the strip', (tester) async {
      await _pump(
        tester,
        _booking(salonName: 'Салон'),
        role: UserRole.salonMaster,
      );
      expect(find.byKey(strip), findsNothing);
    });

    testWidgets('an INDEPENDENT_MASTER never sees the strip', (tester) async {
      await _pump(tester, _booking(), role: UserRole.independentMaster);
      expect(find.byKey(strip), findsNothing);
    });

    testWidgets('an OWNER viewing an INDEPENDENT-master (non-salon) booking '
        'sees no strip', (tester) async {
      await _pump(tester, _booking(), role: UserRole.salonOwner);
      expect(find.byKey(const Key('booking-detail-client-strip')), findsOne);
      expect(find.byKey(strip), findsNothing);
    });

    testWidgets('a CANCELLED booking dims BOTH strips to Opacity(0.7)', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(salonName: 'Салон', status: BookingStatus.cancelled),
        role: UserRole.salonAdmin,
      );
      for (final Key k in <Key>[
        strip,
        const Key('booking-detail-client-strip'),
      ]) {
        final Opacity o = tester.widget<Opacity>(
          find
              .ancestor(of: find.byKey(k), matching: find.byType(Opacity))
              .first,
        );
        expect(o.opacity, 0.7);
      }
    });
  });
}
