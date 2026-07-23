// mobile-qa (MO-6 — the multi-service VISIT «ВІДГУК ПРО МАЙСТРА») — behavioural
// suite for [AppointmentReviewScreen], the visit analogue of
// leave_review_screen_test.dart.
//
// The screen is the CLIENT's ONE-review-per-visit form. This suite proves the
// state machine the phase exists for:
//   • the rating gate — submit is disabled at rating 0, enabled after a star tap;
//   • the star widget — tapping «5» fills all five and crossfades «Чудово»;
//   • the submit wiring — a tap runs the REAL [AppointmentLeaveReview] notifier
//     through an overridden [appointmentRepositoryProvider] mock, so the exact
//     appointmentId/rating/comment reaching `createAppointmentReview` is asserted;
//   • success — the notifier invalidates `appointmentDetailProvider` (the visit
//     detail's `canReview` re-resolves false), the screen shows «Дякуємо за
//     відгук!» and pops back;
//   • the `!canReview` info state — a not-completed / already-reviewed visit
//     lands on the shared not-reviewable body, NOT the form;
//   • the already-reviewed 409 ([ReviewAlreadyExistsFailure]) — the notifier
//     INVALIDATES the detail (backlog row 60 fix for the visit path) so the
//     screen flips to the not-reviewable state in place, plus the localized
//     message surfaces in a SnackBar and the client does NOT pop;
//   • a generic API failure ([ReviewNotAllowedFailure]) — the message surfaces
//     and the client stays on the form;
//   • the fetch loading + error/retry states behind the shared top bar.
//
// Finders are key-first; every asserted string goes through l10n (CI no-raw-
// Cyrillic gate), matching leave_review_screen_test.dart.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/appointment_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/appointment_repository.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/appointment_review_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

const String _appointmentId = 'appt-1';

class _MockAppointmentRepository extends Mock
    implements AppointmentRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Appointment _appointment({
  BookingStatus status = BookingStatus.completed,
  required bool canReview,
}) {
  final DateTime start = DateTime.utc(2026, 7, 14, 15);
  return Appointment(
    id: _appointmentId,
    status: status,
    masterId: 'm1',
    // i18n-finder-ok: injected fixture identity, locale-invariant.
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterProfessionalTitle: 'Майстриня манікюру',
    masterType: 'INDEPENDENT_MASTER',
    startAt: start,
    endAt: start.add(const Duration(minutes: 150)),
    totalDurationMinutes: 150,
    totalPrice: 900,
    items: <AppointmentItem>[
      AppointmentItem(
        bookingId: 'v-1',
        masterServiceId: 'ms-1',
        serviceName: 'Манікюр з покриттям',
        startAt: start,
        endAt: start.add(const Duration(minutes: 90)),
        durationMinutes: 90,
        price: 500,
      ),
      AppointmentItem(
        bookingId: 'v-2',
        masterServiceId: 'ms-2',
        serviceName: 'Педикюр апаратний',
        startAt: start.add(const Duration(minutes: 90)),
        endAt: start.add(const Duration(minutes: 150)),
        durationMinutes: 60,
        price: 400,
      ),
    ],
    canReview: canReview,
    cityLabel: 'Київ',
    street: 'вул. Хрещатик',
    buildingNo: '12',
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AppointmentReviewScreen)));

void main() {
  group('AppointmentReviewScreen — form + submit', () {
    /// Boots a two-route GoRouter (`/host` ⇄ the real visit review route) with
    /// the review screen already PUSHED onto `/host` (so `context.pop()` has a
    /// destination). `/host` also watches `appointmentDetailProvider` and renders
    /// its `canReview`, so an invalidation is observable AFTER a pop.
    Future<(GoRouter, _MockAppointmentRepository)> pumpReview(
      WidgetTester tester, {
      required Future<Appointment> Function(Ref ref) detail,
      _MockAppointmentRepository? repo,
    }) async {
      final _MockAppointmentRepository r = repo ?? _MockAppointmentRepository();
      final GoRouter router = GoRouter(
        initialLocation: '/host',
        routes: <RouteBase>[
          GoRoute(
            path: '/host',
            builder: (BuildContext context, _) => Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                final AsyncValue<Appointment> async = ref.watch(
                  appointmentDetailProvider(_appointmentId),
                );
                return Scaffold(
                  body: Column(
                    children: <Widget>[
                      TextButton(
                        key: const Key('go-review'),
                        onPressed: () => context.push(
                          RouteNames.appointmentReview(_appointmentId),
                        ),
                        child: const Text('go'),
                      ),
                      async.maybeWhen(
                        data: (Appointment a) => Text(
                          'cr:${a.canReview}',
                          key: const Key('host-canreview'),
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          GoRoute(
            path: '/bookings/visit/:appointmentId/review',
            builder: (BuildContext context, GoRouterState state) =>
                AppointmentReviewScreen(
                  appointmentId: state.pathParameters['appointmentId']!,
                ),
          ),
        ],
      );

      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          appointmentRepositoryProvider.overrideWithValue(r),
          appointmentDetailProvider(_appointmentId).overrideWith(detail),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('go-review')));
      await tester.pumpAndSettle();
      expect(find.byType(AppointmentReviewScreen), findsOneWidget);
      return (router, r);
    }

    testWidgets('submit is disabled at rating 0 and enabled after a star tap', (
      tester,
    ) async {
      await pumpReview(
        tester,
        detail: (ref) async => _appointment(canReview: true),
      );

      NeumorphicButton submit() => tester.widget<NeumorphicButton>(
        find.byKey(const Key('visit-review-submit')),
      );
      expect(
        submit().onPressed,
        isNull,
        reason: 'the required rating is unset, so submit must be disabled',
      );

      await tester.tap(find.byKey(const ValueKey<String>('review-star-3')));
      await tester.pumpAndSettle();

      expect(
        submit().onPressed,
        isNotNull,
        reason: 'a rating is now set, so submit must be enabled',
      );
    });

    testWidgets('tapping the 5th star fills all five and shows «Чудово»', (
      tester,
    ) async {
      await pumpReview(
        tester,
        detail: (ref) async => _appointment(canReview: true),
      );

      await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));
      expect(find.byIcon(Icons.star_border_rounded), findsNothing);
      expect(find.text(_l10n(tester).reviewRatingLabel5), findsOneWidget);
    });

    testWidgets(
      'submitting with a comment calls createAppointmentReview with the exact '
      'appointmentId, rating and comment',
      (tester) async {
        final _MockAppointmentRepository repo = _MockAppointmentRepository();
        when(
          () => repo.createAppointmentReview(
            any(),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenAnswer((_) async {});

        await pumpReview(
          tester,
          repo: repo,
          detail: (ref) async => _appointment(canReview: true),
        );

        await tester.tap(find.byKey(const ValueKey<String>('review-star-5')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('visit-review-comment')),
          'Чудова робота, дякую!',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('visit-review-submit')));
        await tester.pumpAndSettle();

        verify(
          () => repo.createAppointmentReview(
            _appointmentId,
            rating: 5,
            comment: 'Чудова робота, дякую!',
          ),
        ).called(1);
      },
    );

    testWidgets(
      'a successful submit invalidates appointmentDetailProvider, shows the '
      'thank-you SnackBar and pops back to the detail',
      (tester) async {
        final _MockAppointmentRepository repo = _MockAppointmentRepository();
        // The "server": before the review exists canReview is true; the write
        // flips `reviewed`, so the notifier's invalidation refetches a
        // NOW-not-reviewable visit.
        bool reviewed = false;
        int fetches = 0;
        when(
          () => repo.createAppointmentReview(
            any(),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenAnswer((_) async {
          reviewed = true;
        });

        final (GoRouter router, _) = await pumpReview(
          tester,
          repo: repo,
          detail: (ref) async {
            fetches++;
            return _appointment(canReview: !reviewed);
          },
        );
        expect(fetches, 1, reason: 'the initial detail fetch');

        await tester.tap(find.byKey(const ValueKey<String>('review-star-4')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('visit-review-submit')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byKey(const Key('host-canreview'))),
        );
        verify(
          () => repo.createAppointmentReview(
            _appointmentId,
            rating: 4,
            comment: '',
          ),
        ).called(1);
        // The thank-you SnackBar surfaced…
        expect(find.text(l10n.reviewSubmitSuccess), findsOneWidget);
        // …the screen popped back to /host…
        expect(find.byType(AppointmentReviewScreen), findsNothing);
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          '/host',
        );
        // …and the invalidation forced a refetch that now says canReview:false.
        expect(fetches, 2, reason: 'ref.invalidate(appointmentDetailProvider)');
        expect(find.text('cr:false'), findsOneWidget);

        await tester.pumpUntilGone(find.text(l10n.reviewSubmitSuccess));
      },
    );

    testWidgets(
      'an already-reviewed 409 (ReviewAlreadyExistsFailure) invalidates the '
      'detail so the screen flips to the not-reviewable state and surfaces the '
      'message (no pop)',
      (tester) async {
        final _MockAppointmentRepository repo = _MockAppointmentRepository();
        // The visit was reviewed elsewhere between opening this form and the
        // submit: the fetch starts canReview:true, the write 409s and flips it.
        bool reviewed = false;
        int fetches = 0;
        when(
          () => repo.createAppointmentReview(
            any(),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenAnswer((_) async {
          reviewed = true;
          throw const ReviewAlreadyExistsFailure();
        });

        await pumpReview(
          tester,
          repo: repo,
          detail: (ref) async {
            fetches++;
            return _appointment(canReview: !reviewed);
          },
        );
        expect(fetches, 1, reason: 'the initial (reviewable) fetch');

        await tester.tap(find.byKey(const ValueKey<String>('review-star-3')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('visit-review-submit')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = _l10n(tester);
        // The stale 409 refetched the detail (backlog row 60 fix)…
        expect(
          fetches,
          2,
          reason: 'the already-reviewed 409 invalidates appointmentDetail',
        );
        // …flipping the SAME screen (no pop) to the not-reviewable state…
        expect(find.byType(AppointmentReviewScreen), findsOneWidget);
        expect(
          find.byKey(const Key('visit-review-unavailable-back')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('visit-review-stars')), findsNothing);
        // …and the localized already-reviewed message surfaced.
        expect(find.text(l10n.reviewErrAlreadyReviewed), findsOneWidget);

        await tester.pumpUntilGone(find.text(l10n.reviewErrAlreadyReviewed));
      },
    );

    testWidgets(
      'a ReviewNotAllowedFailure surfaces the localized message and stays on '
      'the form (no pop)',
      (tester) async {
        final _MockAppointmentRepository repo = _MockAppointmentRepository();
        when(
          () => repo.createAppointmentReview(
            any(),
            rating: any(named: 'rating'),
            comment: any(named: 'comment'),
          ),
        ).thenThrow(const ReviewNotAllowedFailure());

        await pumpReview(
          tester,
          repo: repo,
          detail: (ref) async => _appointment(canReview: true),
        );

        await tester.tap(find.byKey(const ValueKey<String>('review-star-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('visit-review-submit')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = _l10n(tester);
        expect(find.text(l10n.reviewErrNotAllowed), findsOneWidget);
        expect(find.text(l10n.errUnknown), findsNothing);
        // Still on the form (no pop, canReview still true so no flip).
        expect(find.byType(AppointmentReviewScreen), findsOneWidget);
        expect(find.byKey(const Key('visit-review-stars')), findsOneWidget);

        await tester.pumpUntilGone(find.text(l10n.reviewErrNotAllowed));
      },
    );

    testWidgets('a not-reviewable visit renders the info state, not the form', (
      tester,
    ) async {
      await pumpReview(
        tester,
        detail: (ref) async => _appointment(canReview: false),
      );

      expect(
        find.byKey(const Key('visit-review-unavailable-back')),
        findsOneWidget,
      );
      expect(find.text(_l10n(tester).reviewUnavailableTitle), findsOneWidget);
      expect(find.byKey(const Key('visit-review-stars')), findsNothing);
      expect(find.byKey(const Key('visit-review-submit')), findsNothing);
    });

    testWidgets('shows a spinner while the visit loads', (tester) async {
      final Completer<Appointment> completer = Completer<Appointment>();
      final GoRouter router = GoRouter(
        initialLocation: '/bookings/visit/$_appointmentId/review',
        routes: <RouteBase>[
          GoRoute(
            path: '/bookings/visit/:appointmentId/review',
            builder: (BuildContext context, GoRouterState state) =>
                AppointmentReviewScreen(
                  appointmentId: state.pathParameters['appointmentId']!,
                ),
          ),
        ],
      );
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          appointmentDetailProvider(
            _appointmentId,
          ).overrideWith((ref) => completer.future),
        ],
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('visit-review-back')), findsOneWidget);

      completer.complete(_appointment(canReview: true));
      await tester.pumpAndSettle();
    });

    testWidgets('shows the error state with a retry on a failed fetch', (
      tester,
    ) async {
      final GoRouter router = GoRouter(
        initialLocation: '/bookings/visit/$_appointmentId/review',
        routes: <RouteBase>[
          GoRoute(
            path: '/bookings/visit/:appointmentId/review',
            builder: (BuildContext context, GoRouterState state) =>
                AppointmentReviewScreen(
                  appointmentId: state.pathParameters['appointmentId']!,
                ),
          ),
        ],
      );
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          appointmentDetailProvider(
            _appointmentId,
          ).overrideWith((ref) async => throw Exception('down')),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('visit-review-error-retry')), findsOneWidget);
      await tester.tap(find.byKey(const Key('visit-review-error-retry')));
      await tester.pump();
      expect(find.byKey(const Key('visit-review-error-retry')), findsOneWidget);
    });
  });
}
