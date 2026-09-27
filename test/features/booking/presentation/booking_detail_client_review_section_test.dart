// Phase 334 — «Відгук клієнта» on «Деталі запису»: the read-only block
// showing the PROVIDER the review their client left about them.
//
// The block is `ClientReviewSection`, which renders through the SHARED
// `ReviewCard` leaf (the same widget the salon «Відгуки» tab and the master's
// received-reviews screen use for every review they draw). `review_card_test`
// pins the leaf's own contract, including the two nullable widenings this
// phase needed; this suite pins the SCREEN's side of it:
//
//   * the two gates — provider-only, and only when `reviewByClient` is
//     non-null — and that BOTH are required, not just one;
//   * that the gate is NOT `status`, deliberately unlike
//     `providerCanReviewClient` next door;
//   * the stars-only degradation (the client rated without writing);
//   * the guest-name fallback;
//   * that the block sits BELOW the notes, which is the ordering the
//     chronology argument in the screen's own comment depends on;
//   * that a READ-ONLY `SALON_MASTER` sees it — the phase-331 capability gate
//     governs status TRANSITIONS, and must never reach the recap body.
//
// Every "absent" assertion is paired with a positive one in the same pump, so
// a `findsNothing` can never pass because the screen failed to render at all.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/client_authored_review.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_notes.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_summary_cards.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/client_review_section.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// Fixture identities injected BY this test — backend data, never app copy,
// and locale-invariant by construction (a person's name is not translated).
const String _clientFirst = 'Олена';
const String _clientLast = 'Ковальчук';
const String _clientFull = '$_clientFirst $_clientLast';
const String _reviewComment = 'Майстриня золоті руки, все ідеально!';
const String _clientBriefNote = 'Без ароматизаторів — алергія.';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

Booking _booking({
  BookingStatus status = BookingStatus.completed,
  ClientAuthoredReview? reviewByClient,
  String? clientId = 'c1',
  String? clientFirstName = _clientFirst,
  String? clientLastName = _clientLast,
  String? clientComment,
}) {
  // A FIXED PAST literal — the safe case `booking_fixture_dates.dart`
  // explicitly carves out (and `forbid_stale_future_date_fixture.sh` allows,
  // rule (a) barring only years >= the current one). A closed booking is in
  // the past by definition and this instant can never drift back into the
  // future, so it needs no now-anchored helper.
  final DateTime start = DateTime.utc(2024, 3, 12, 10);
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: clientId,
    clientFirstName: clientFirstName,
    clientLastName: clientLastName,
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
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
    clientComment: clientComment,
    reviewByClient: reviewByClient,
  );
}

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
      // The viewer role is derived from the SESSION — the same path
      // production uses — never by overriding `bookingViewerRoleProvider`.
      authProvider.overrideWith(
        () => _StubAuth(
          AuthSession.authenticated(
            user: User(id: 'u1', email: 'u@e.com', role: role),
            accessToken: 't',
          ),
        ),
      ),
    ],
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingDetailScreen)));

final Finder _section = find.byType(ClientReviewSection);

/// The screen's own chrome — used as the anti-vacuity witness beside every
/// `findsNothing`, so an absent section can never be an absent SCREEN.
final Finder _screenChrome = find.byType(BookingSummaryCards);

/// Star icons INSIDE the review block only, so nothing else on the screen can
/// contribute to the count.
Finder _sectionStars() =>
    find.descendant(of: _section, matching: find.byIcon(Icons.star_rounded));

/// How many of the block's five stars are painted FILLED — i.e. the score the
/// card actually draws.
///
/// [_sectionStars] counts the glyphs, and `ReviewStarRow` always draws five of
/// them whatever the rating (`review_card.dart:205-211` — only the colour
/// changes), so a count assertion alone can never see a wrong score. This is
/// the assertion that can: it is the same `accentDeep`-vs-`faint` distinction
/// `review_card_test`'s own `_filledStars` reads, scoped to this block.
int _sectionFilledStars(WidgetTester tester) => tester
    .widgetList<Icon>(_sectionStars())
    .where((Icon i) => i.color == BrandColors.accentDeep)
    .length;

void main() {
  group('the block renders for the provider', () {
    testWidgets('a provider on a booking carrying a review sees the card, the '
        'score and the comment verbatim', (tester) async {
      await _pump(
        tester,
        _booking(
          reviewByClient: const ClientAuthoredReview(
            rating: 5,
            comment: _reviewComment,
          ),
        ),
        role: UserRole.independentMaster,
      );

      expect(_section, findsOneWidget);
      expect(_sectionStars(), findsNWidgets(5));
      // i18n-finder-ok: the review body is backend data, not UI copy.
      expect(find.text(_reviewComment), findsOneWidget);
      expect(
        find.text(_l10n(tester).bookingDetailClientReviewHeading),
        findsOneWidget,
      );
    });

    testWidgets('the card is keyed by the BOOKING id under the client-review '
        'prefix — the payload carries no review id of its own', (tester) async {
      await _pump(
        tester,
        _booking(
          reviewByClient: const ClientAuthoredReview(
            rating: 3,
            comment: _reviewComment,
          ),
        ),
        role: UserRole.independentMaster,
      );

      expect(
        find.byKey(const Key('${ClientReviewSection.keyPrefix}-b1')),
        findsOneWidget,
      );
    });

    testWidgets('a stars-only review (the client rated without writing) '
        'renders the score and NO comment body', (tester) async {
      await _pump(
        tester,
        _booking(reviewByClient: const ClientAuthoredReview(rating: 4)),
        role: UserRole.independentMaster,
      );

      expect(_section, findsOneWidget);
      expect(
        _sectionStars(),
        findsNWidgets(5),
        reason:
            'the ★ row IS the review when there is no comment — it must '
            'not collapse to an empty state',
      );
      // Nothing but the client's name is left in the card's text.
      final Iterable<String> cardTexts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(ReviewCard),
              matching: find.byType(Text),
            ),
          )
          .map((Text t) => t.data ?? '');
      expect(cardTexts, <String>[_clientFull]);
    });

    testWidgets('a guest booking attributes the review to the localized '
        'guest label, never an empty name', (tester) async {
      await _pump(
        tester,
        _booking(
          clientId: null,
          clientFirstName: null,
          clientLastName: null,
          reviewByClient: const ClientAuthoredReview(
            rating: 5,
            comment: _reviewComment,
          ),
        ),
        role: UserRole.independentMaster,
      );

      final String guest = _l10n(tester).bookingDetailGuestClient;
      expect(
        find.descendant(of: _section, matching: find.text(guest)),
        findsOneWidget,
      );
    });
  });

  // mobile-qa 2026-09-15 — the gap this group closes. Every assertion above
  // counts star GLYPHS (`findsNWidgets(5)`), and `ReviewStarRow` draws five
  // whatever the score, so the whole suite stayed GREEN with the section's
  // `rating: review.rating` replaced by a hardcoded `rating: 5` — as did the
  // integration flow, which asserts only the card key and the comment. The
  // provider would have read the wrong score off a real review with nothing
  // red anywhere. The score is pinned twice here on purpose: once as PAINT
  // (the filled-star count, what a sighted provider sees) and once as SPEECH
  // (the Semantics label, the only channel that carries the number at all —
  // a screen reader cannot interpret five bare Icon glyphs).
  group('the score the CLIENT gave', () {
    testWidgets('the ★ row fills exactly `rating` stars, not five — a '
        '2-star review must not read as praise', (tester) async {
      await _pump(
        tester,
        _booking(
          reviewByClient: const ClientAuthoredReview(
            rating: 2,
            comment: _reviewComment,
          ),
        ),
        role: UserRole.independentMaster,
      );

      expect(_sectionStars(), findsNWidgets(5), reason: 'five glyphs drawn');
      expect(
        _sectionFilledStars(tester),
        2,
        reason:
            'the payload rating must reach the card — a constant, an '
            'off-by-one, or the booking\'s own canReview flag standing in '
            'for it would all keep the glyph count at five',
      );
    });

    testWidgets('a screen reader hears the score and the comment — the ★ row '
        'is five bare Icons and announces nothing on its own', (tester) async {
      // Disposed inline, not via addTearDown: the framework's "a
      // SemanticsHandle was active at the end of the test" check runs BEFORE
      // tear-downs (same idiom as master_booking_card_client_avatar_test).
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          _booking(
            reviewByClient: const ClientAuthoredReview(
              rating: 2,
              comment: _reviewComment,
            ),
          ),
          role: UserRole.independentMaster,
        );

        final AppLocalizations l10n = _l10n(tester);
        expect(
          find.bySemanticsLabel(
            RegExp(
              RegExp.escape(
                l10n.bookingDetailClientReviewSemantics(2, _reviewComment),
              ),
            ),
          ),
          findsOneWidget,
          reason:
              'the block excludes its descendants from semantics, so this '
              'one label IS everything the block announces — it must carry '
              'the real score and the real comment',
        );
        expect(
          find.bySemanticsLabel(
            RegExp(
              RegExp.escape(
                l10n.bookingDetailClientReviewSemanticsNoComment(2),
              ),
            ),
          ),
          findsNothing,
          reason: 'the commented review must not take the no-comment phrasing',
        );
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a stars-only review announces the no-comment phrasing, never '
        'a dangling sentence with an empty body', (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          _booking(reviewByClient: const ClientAuthoredReview(rating: 4)),
          role: UserRole.independentMaster,
        );

        final AppLocalizations l10n = _l10n(tester);
        expect(
          find.bySemanticsLabel(
            RegExp(
              RegExp.escape(
                l10n.bookingDetailClientReviewSemanticsNoComment(4),
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(
          _sectionFilledStars(tester),
          4,
          reason: 'anti-vacuity — the same block really did draw a 4',
        );
      } finally {
        handle.dispose();
      }
    });
  });

  group('the two gates', () {
    testWidgets('a CLIENT viewer never sees the block, even when the booking '
        'carries a review', (tester) async {
      await _pump(
        tester,
        _booking(
          reviewByClient: const ClientAuthoredReview(
            rating: 5,
            comment: _reviewComment,
          ),
        ),
        role: UserRole.client,
      );

      expect(
        _screenChrome,
        findsOneWidget,
        reason: 'anti-vacuity — the detail screen really did render',
      );
      expect(
        _section,
        findsNothing,
        reason:
            'the client WROTE this review and has «Мої відгуки» for it; '
            'echoing it back on the visit page is noise, not privacy',
      );
      // i18n-finder-ok: backend review body must not leak onto the client view.
      expect(find.text(_reviewComment), findsNothing);
    });

    testWidgets('a provider on a booking with NO review sees no block and no '
        'empty state', (tester) async {
      await _pump(tester, _booking(), role: UserRole.independentMaster);

      expect(_screenChrome, findsOneWidget, reason: 'anti-vacuity');
      expect(_section, findsNothing);
      expect(
        find.text(_l10n(tester).bookingDetailClientReviewHeading),
        findsNothing,
        reason:
            'a null reviewByClient means "this surface did not answer the '
            'question" on every listing, so no placeholder may be built on '
            'it — not even the heading',
      );
    });
  });

  group('what the block is NOT gated on', () {
    testWidgets('status — a review on a CANCELLED booking still renders, '
        'deliberately unlike providerCanReviewClient next door', (
      tester,
    ) async {
      await _pump(
        tester,
        _booking(
          status: BookingStatus.cancelled,
          reviewByClient: const ClientAuthoredReview(
            rating: 2,
            comment: _reviewComment,
          ),
        ),
        role: UserRole.independentMaster,
      );

      expect(
        _section,
        findsOneWidget,
        reason:
            'reviewByClient is a FACT, not a capability — re-ANDing it '
            'with COMPLETED would blank a real review off the screen',
      );
    });

    testWidgets('the phase-331 read-only capability — a SALON_MASTER sees the '
        'block, because that gate governs status TRANSITIONS and must never '
        'reach the recap body', (tester) async {
      await _pump(
        tester,
        _booking(
          reviewByClient: const ClientAuthoredReview(
            rating: 5,
            comment: _reviewComment,
          ),
        ),
        role: UserRole.salonMaster,
      );

      expect(_section, findsOneWidget);
      // i18n-finder-ok: backend review body.
      expect(find.text(_reviewComment), findsOneWidget);
    });
  });

  testWidgets('the block sits BELOW the notes — the recap reads '
      'chronologically, brief first and review last', (tester) async {
    await _pump(
      tester,
      _booking(
        clientComment: _clientBriefNote,
        reviewByClient: const ClientAuthoredReview(
          rating: 5,
          comment: _reviewComment,
        ),
      ),
      role: UserRole.independentMaster,
    );

    expect(
      find.byType(BookingNotes),
      findsOneWidget,
      reason: 'anti-vacuity — the ordering claim needs BOTH blocks on screen',
    );
    expect(_section, findsOneWidget);
    expect(
      tester.getTopLeft(_section).dy,
      greaterThan(tester.getTopLeft(find.byType(BookingNotes)).dy),
      reason:
          'the notes were written DURING the booking (the brief at '
          'creation, the reason at closure) and the review comes AFTER '
          'closure, so the column must read top to bottom in that order',
    );
  });
}
