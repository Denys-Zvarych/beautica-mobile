// Phase 414 — «Посилання для запису» screen (BookingLinkScreen).
//
// Real bookingLinksProvider (so the role scoping is exercised end to end)
// over a mocked repository; mocked clipboard / share services.
//
// Coverage:
//   • INDEPENDENT_MASTER → one MASTER card (a stray SALON link is dropped);
//   • SALON_OWNER → one SALON card per salon, NO master card (user decision
//     2026-10-20), backend order kept;
//   • SALON_ADMIN → its salon card only;
//   • SALON_MASTER / CLIENT reaching the route → screen closes, no card;
//   • not-bookable warning + «Налаштувати» → services, «Команда» → salon team;
//   • loading skeleton; error → retry → cards;
//   • Copy → clipboard gets ONLY the utm_source=copy URL + success snack +
//     in-well check that clears after 1.6 s; clipboard failure → error snack,
//     no check;
//   • Share → share service gets «Записуйтеся …» + the utm_source=share URL;
//   • kill-switch off while on screen → pops back.
//
// Finders use widget Keys (M2); snack text is asserted through the shared
// VelvetSnack matchers. Layer: Widget.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:beautica_mobile/core/share/share_service.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking_links/data/booking_links_repository.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_screen.dart';
import 'package:beautica_mobile/features/booking_links/presentation/widgets/booking_link_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_notification_repository.dart'
    show FixedRoleAuth;
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

class _MockRepo extends Mock implements BookingLinksRepository {}

class _MockClipboard extends Mock implements ClipboardService {}

class _MockShare extends Mock implements ShareService {}

const BookingLink _master = BookingLink(
  kind: BookingLinkKind.master,
  slug: 'olena-koval-x7k2',
  url: 'https://beautica.app/book/olena-koval-x7k2',
  displayName: 'Олена Коваль',
  bookable: true,
);

const BookingLink _salonA = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'lumiere-kyiv',
  url: 'https://beautica.app/book/s/lumiere-kyiv',
  displayName: 'Lumière',
  salonId: 'salon-a',
  bookable: true,
);

const BookingLink _salonB = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'beauty-loft-8r2c',
  url: 'https://beautica.app/book/s/beauty-loft-8r2c',
  displayName: 'Beauty Loft',
  salonId: 'salon-b',
  bookable: true,
);

BookingLinks _enabled(List<BookingLink> links) =>
    BookingLinks(shareEnabled: true, links: links);

Key _card(String slug) => Key('booking-link-card-$slug');
Key _copy(String slug) => Key('btn-booking-link-copy-$slug');
Key _share(String slug) => Key('btn-booking-link-share-$slug');
Key _setup(String slug) => Key('link-booking-link-setup-$slug');

const Key _home = Key('stub-home');

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: SizedBox(key: _home)),
    ),
    GoRoute(
      path: RouteNames.bookingLinks,
      builder: (_, _) => const BookingLinkScreen(),
    ),
    GoRoute(
      path: RouteNames.services,
      builder: (_, _) =>
          const Scaffold(body: SizedBox(key: Key('stub-services'))),
    ),
    GoRoute(
      path: '/salons/:salonId/shell',
      builder: (_, GoRouterState s) => Scaffold(
        body: SizedBox(
          key: Key(
            'stub-shell-${s.pathParameters['salonId']}-'
            '${s.uri.queryParameters['tab']}',
          ),
        ),
      ),
    ),
  ],
);

void main() {
  late _MockRepo repo;
  late _MockClipboard clipboard;
  late _MockShare share;

  setUp(() {
    repo = _MockRepo();
    clipboard = _MockClipboard();
    share = _MockShare();
    when(() => clipboard.copyText(any())).thenAnswer((_) async => true);
    when(
      () => share.shareText(any(), subject: any(named: 'subject')),
    ).thenAnswer((_) async => ShareOutcome.shared);
  });

  /// Pumps the screen pushed over a stub home (so a close can pop).
  Future<GoRouter> pumpScreen(
    WidgetTester tester, {
    required UserRole role,
    String? salonId,
  }) async {
    final GoRouter router = _router();
    addTearDown(router.dispose);
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        authProvider.overrideWith(() => FixedRoleAuth(role, salonId: salonId)),
        bookingLinksRepositoryProvider.overrideWithValue(repo),
        clipboardServiceProvider.overrideWithValue(clipboard),
        shareServiceProvider.overrideWithValue(share),
      ],
    );
    await tester.pumpAndSettle();
    unawaited(router.push(RouteNames.bookingLinks));
    await tester.pumpAndSettle();
    return router;
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(BookingLinkScreen)));

  group('cards per role', () {
    testWidgets('INDEPENDENT_MASTER → one MASTER card; a stray SALON link is '
        'dropped client-side', (tester) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master, _salonA]));

      await pumpScreen(tester, role: UserRole.independentMaster);

      expect(find.byType(BookingLinkCard), findsOneWidget);
      expect(find.byKey(_card(_master.slug)), findsOneWidget);
      expect(find.byKey(_card(_salonA.slug)), findsNothing);
      expect(find.text(l10nOf(tester).bookingLinkMasterTitle), findsOneWidget);
    });

    testWidgets('SALON_OWNER → one SALON card per salon in backend order, NO '
        'master card', (tester) async {
      when(() => repo.getMine()).thenAnswer(
        (_) async => _enabled(<BookingLink>[_master, _salonA, _salonB]),
      );

      await pumpScreen(tester, role: UserRole.salonOwner);

      expect(find.byType(BookingLinkCard), findsNWidgets(2));
      expect(find.byKey(_card(_master.slug)), findsNothing);
      final double aTop = tester.getTopLeft(find.byKey(_card(_salonA.slug))).dy;
      final double bTop = tester.getTopLeft(find.byKey(_card(_salonB.slug))).dy;
      expect(aTop, lessThan(bTop), reason: 'backend order is kept');
      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.bookingLinkSalonTitle('Lumière')), findsOneWidget);
      expect(
        find.text(l10n.bookingLinkSalonTitle('Beauty Loft')),
        findsOneWidget,
      );
      expect(find.text(l10n.bookingLinkMasterTitle), findsNothing);
    });

    testWidgets('SALON_ADMIN → its salon card only', (tester) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_salonA]));

      await pumpScreen(tester, role: UserRole.salonAdmin, salonId: 'salon-a');

      expect(find.byType(BookingLinkCard), findsOneWidget);
      expect(find.byKey(_card(_salonA.slug)), findsOneWidget);
    });

    for (final UserRole role in <UserRole>[
      UserRole.salonMaster,
      UserRole.client,
    ]) {
      testWidgets('${role.name} reaching the route → screen closes, no card', (
        tester,
      ) async {
        when(
          () => repo.getMine(),
        ).thenAnswer((_) async => _enabled(<BookingLink>[_master, _salonA]));

        await pumpScreen(tester, role: role);

        expect(find.byType(BookingLinkScreen), findsNothing);
        expect(find.byType(BookingLinkCard), findsNothing);
        expect(find.byKey(_home), findsOneWidget);
        verifyNever(() => repo.getMine());
      });
    }
  });

  group('not bookable (D6)', () {
    testWidgets('master: warning + «Налаштувати» → services; actions stay '
        'enabled', (tester) async {
      when(() => repo.getMine()).thenAnswer(
        (_) async => _enabled(<BookingLink>[_master.copyWith(bookable: false)]),
      );

      await pumpScreen(tester, role: UserRole.independentMaster);
      final AppLocalizations l10n = l10nOf(tester);

      expect(
        find.textContaining(l10n.bookingLinkNotBookableMaster),
        findsOneWidget,
      );
      // Sharing stays enabled on a not-bookable link.
      await tester.tap(find.byKey(_copy(_master.slug)));
      await pumpVelvetSnackIn(tester);
      verify(() => clipboard.copyText(any())).called(1);
      await pumpPastVelvetSnack(tester);

      await tester.tap(find.byKey(_setup(_master.slug)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stub-services')), findsOneWidget);
    });

    testWidgets('salon: warning + «Команда» → salon shell team tab', (
      tester,
    ) async {
      when(() => repo.getMine()).thenAnswer(
        (_) async => _enabled(<BookingLink>[_salonA.copyWith(bookable: false)]),
      );

      await pumpScreen(tester, role: UserRole.salonOwner);
      final AppLocalizations l10n = l10nOf(tester);

      expect(
        find.textContaining(l10n.bookingLinkNotBookableSalon),
        findsOneWidget,
      );
      await tester.tap(find.byKey(_setup(_salonA.slug)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stub-shell-salon-a-team')), findsOneWidget);
    });

    testWidgets('a bookable link shows no warning', (tester) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));

      await pumpScreen(tester, role: UserRole.independentMaster);

      expect(find.byKey(_setup(_master.slug)), findsNothing);
      expect(
        find.textContaining(l10nOf(tester).bookingLinkNotBookableMaster),
        findsNothing,
      );
    });
  });

  group('loading / error', () {
    testWidgets('loading → skeleton, then the cards', (tester) async {
      final Completer<BookingLinks> pending = Completer<BookingLinks>();
      when(() => repo.getMine()).thenAnswer((_) => pending.future);

      final GoRouter router = _router();
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          authProvider.overrideWith(
            () => FixedRoleAuth(UserRole.independentMaster),
          ),
          bookingLinksRepositoryProvider.overrideWithValue(repo),
          clipboardServiceProvider.overrideWithValue(clipboard),
          shareServiceProvider.overrideWithValue(share),
        ],
      );
      await tester.pumpAndSettle();
      unawaited(router.push(RouteNames.bookingLinks));
      // The shimmer never settles — pump frames until the skeleton shows.
      await tester.pumpUntilFound(
        find.byKey(const Key('booking-links-loading')),
      );
      expect(find.byType(BookingLinkCard), findsNothing);

      pending.complete(_enabled(<BookingLink>[_master]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('booking-links-loading')), findsNothing);
      expect(find.byKey(_card(_master.slug)), findsOneWidget);
    });

    testWidgets('error → ErrorState; retry refetches and shows the cards', (
      tester,
    ) async {
      int calls = 0;
      when(() => repo.getMine()).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw const ServerFailure(statusCode: 400);
        return _enabled(<BookingLink>[_master]);
      });

      await pumpScreen(tester, role: UserRole.independentMaster);

      expect(find.byKey(const Key('error_state_retry_button')), findsOneWidget);
      expect(find.byType(BookingLinkCard), findsNothing);

      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.byKey(_card(_master.slug)), findsOneWidget);
    });
  });

  group('copy', () {
    testWidgets('copies ONLY the utm_source=copy URL, shows the success snack '
        'and the in-well check for 1.6 s', (tester) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));

      await pumpScreen(tester, role: UserRole.independentMaster);
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byKey(_copy(_master.slug)));
      await pumpVelvetSnackIn(tester);

      final String copied =
          verify(() => clipboard.copyText(captureAny())).captured.single
              as String;
      expect(
        copied,
        'https://beautica.app/book/olena-koval-x7k2'
        '?utm_source=copy&utm_medium=social&utm_campaign=master_link',
      );
      expectVelvetSnack(
        l10n.bookingLinkCopied,
        variant: VelvetSnackVariant.success,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('booking-link-copied-${_master.slug}')),
        findsOneWidget,
      );

      await tester.pump(BookingLinkCard.copiedDwell);
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('booking-link-copied-${_master.slug}')),
        findsNothing,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('clipboard failure → error snack, no check', (tester) async {
      when(() => clipboard.copyText(any())).thenAnswer((_) async => false);
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_salonA]));

      await pumpScreen(tester, role: UserRole.salonAdmin, salonId: 'salon-a');
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byKey(_copy(_salonA.slug)));
      await pumpVelvetSnackIn(tester);

      expectVelvetSnack(
        l10n.bookingLinkCopyFailed,
        variant: VelvetSnackVariant.error,
      );
      expect(
        find.byKey(Key('booking-link-copied-${_salonA.slug}')),
        findsNothing,
      );
      await pumpPastVelvetSnack(tester);
    });
  });

  group('share', () {
    testWidgets('master: «Записуйтеся онлайн: {utm_source=share URL}»', (
      tester,
    ) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));

      await pumpScreen(tester, role: UserRole.independentMaster);
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byKey(_share(_master.slug)));
      await tester.pumpAndSettle();

      const String url =
          'https://beautica.app/book/olena-koval-x7k2'
          '?utm_source=share&utm_medium=social&utm_campaign=master_link';
      final List<dynamic> captured = verify(
        () => share.shareText(
          captureAny(),
          subject: captureAny(named: 'subject'),
        ),
      ).captured;
      // Exactly the localized text over the UTM'd URL — and no subject.
      expect(captured, <Object?>[l10n.bookingLinkShareTextMaster(url), null]);
      verifyNever(() => clipboard.copyText(any()));
    });

    testWidgets('salon: name + utm_source=share salon URL; failure → error '
        'snack', (tester) async {
      when(
        () => share.shareText(any(), subject: any(named: 'subject')),
      ).thenAnswer((_) async => ShareOutcome.failed);
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_salonA]));

      await pumpScreen(tester, role: UserRole.salonOwner);
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byKey(_share(_salonA.slug)));
      await pumpVelvetSnackIn(tester);

      const String url =
          'https://beautica.app/book/s/lumiere-kyiv'
          '?utm_source=share&utm_medium=social&utm_campaign=salon_link';
      final String text =
          verify(
                () => share.shareText(
                  captureAny(),
                  subject: any(named: 'subject'),
                ),
              ).captured.single
              as String;
      expect(text, l10n.bookingLinkShareTextSalon('Lumière', url));
      expectVelvetSnack(
        l10n.bookingLinkShareFailed,
        variant: VelvetSnackVariant.error,
      );
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('salon: bidi + control chars are stripped from the name in '
        'the share text', (tester) async {
      when(
        () => share.shareText(any(), subject: any(named: 'subject')),
      ).thenAnswer((_) async => ShareOutcome.shared);
      const BookingLink hostile = BookingLink(
        kind: BookingLinkKind.salon,
        slug: 'lumiere-kyiv',
        url: 'https://beautica.app/book/s/lumiere-kyiv',
        displayName: 'Lum\u202Eière\nSpa\u2066\u200F',
        salonId: 'salon-a',
        bookable: true,
      );
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[hostile]));

      await pumpScreen(tester, role: UserRole.salonOwner);
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byKey(_share(hostile.slug)));
      await tester.pump();

      final String text =
          verify(
                () => share.shareText(
                  captureAny(),
                  subject: any(named: 'subject'),
                ),
              ).captured.single
              as String;
      expect(text, isNot(contains('\u202E')));
      expect(text, isNot(contains('\n')));
      expect(text, isNot(contains('\u2066')));
      expect(text, isNot(contains('\u200F')));
      const String url =
          'https://beautica.app/book/s/lumiere-kyiv'
          '?utm_source=share&utm_medium=social&utm_campaign=salon_link';
      expect(text, l10n.bookingLinkShareTextSalon('LumièreSpa', url));
    });
  });

  final Map<String, BookingLinks> hiddenPayloads = <String, BookingLinks>{
    'kill-switch off': const BookingLinks(
      shareEnabled: false,
      links: <BookingLink>[_master],
    ),
    'no links': const BookingLinks(shareEnabled: true, links: <BookingLink>[]),
  };
  hiddenPayloads.forEach((String label, BookingLinks payload) {
    testWidgets('$label on load → pops back (D7)', (tester) async {
      when(() => repo.getMine()).thenAnswer((_) async => payload);

      await pumpScreen(tester, role: UserRole.independentMaster);

      expect(find.byType(BookingLinkScreen), findsNothing);
      expect(find.byKey(_home), findsOneWidget);
    });
  });
}
