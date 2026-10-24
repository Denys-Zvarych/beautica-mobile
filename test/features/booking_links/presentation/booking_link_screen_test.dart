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
//     a non-UUID server salonId (dropped by the mapper) → no «Команда» link;
//   • loading skeleton; error → retry → cards;
//   • Copy → clipboard gets ONLY the link + `?s=c` (419; 418: no utm_*) +
//     success snack +
//     in-well check that clears after 1.6 s; clipboard failure → error snack,
//     no check;
//   • Share → share service gets «Записуйтеся …» + the bare link;
//   • kill-switch off while on screen → pops back.
//   • Phase 415 regenerate: header glyph on active cards → confirm (cancel =
//     no call) → new URL + success snack, Copy sends the NEW url; revoked
//     card (no URL / Copy / Share / glyph / note) → «Створити нове
//     посилання» → short-body confirm → active again; 409 warning + refetch;
//     404 → pops back; 429 / other → error snacks; owner with two salons —
//     the other card untouched; in flight → progress + dimmed actions.
//
// Finders use widget Keys (M2); snack text is asserted through the shared
// VelvetSnack matchers. Layer: Widget.

import 'dart:async';

import 'package:beautica_api/beautica_api.dart' as api;
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
import 'package:built_collection/built_collection.dart';
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
Key _regen(String id) => Key('btn-booking-link-regenerate-$id');
Key _recreate(String id) => Key('btn-booking-link-recreate-$id');
const Key _confirm = Key('regenerate-booking-link-confirm');
const Key _dismiss = Key('regenerate-booking-link-dismiss');
const Key _dialog = Key('regenerate-booking-link-dialog');

const BookingLink _revokedMaster = BookingLink(
  kind: BookingLinkKind.master,
  slug: null,
  url: null,
  displayName: 'Олена Коваль',
  bookable: false,
  status: BookingLinkStatus.revoked,
);

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
      expect(find.byKey(_card(_master.keyId)), findsOneWidget);
      expect(find.byKey(_card(_salonA.keyId)), findsNothing);
      expect(find.text(l10nOf(tester).bookingLinkMasterTitle), findsOneWidget);
    });

    testWidgets('SALON_OWNER → one SALON card per salon in backend order, NO '
        'master card', (tester) async {
      when(() => repo.getMine()).thenAnswer(
        (_) async => _enabled(<BookingLink>[_master, _salonA, _salonB]),
      );

      await pumpScreen(tester, role: UserRole.salonOwner);

      expect(find.byType(BookingLinkCard), findsNWidgets(2));
      expect(find.byKey(_card(_master.keyId)), findsNothing);
      final double aTop = tester
          .getTopLeft(find.byKey(_card(_salonA.keyId)))
          .dy;
      final double bTop = tester
          .getTopLeft(find.byKey(_card(_salonB.keyId)))
          .dy;
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
      expect(find.byKey(_card(_salonA.keyId)), findsOneWidget);
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
      await tester.tap(find.byKey(_copy(_master.keyId)));
      await pumpVelvetSnackIn(tester);
      verify(() => clipboard.copyText(any())).called(1);
      await pumpPastVelvetSnack(tester);

      await tester.tap(find.byKey(_setup(_master.keyId)));
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
      await tester.tap(find.byKey(_setup(_salonA.keyId)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stub-shell-salon-a-team')), findsOneWidget);
    });

    testWidgets('salon: a non-UUID salonId from the server → warning, but NO '
        '«Команда» link (MASVS-CODE-4)', (tester) async {
      // Through the real mapper, so the gate under test is the one that
      // keeps `x/../..?tab=` out of the `/salons/{id}/shell` path.
      final BookingLinks mapped = mapBookingLinks(
        api.BookingLinksResponse(
          (b) => b
            ..shareEnabled = true
            ..links =
                ListBuilder<api.BookingLinkResponse>(<api.BookingLinkResponse>[
                  api.BookingLinkResponse(
                    (l) => l
                      ..kind = api.BookingLinkResponseKindEnum.SALON
                      ..status = api.BookingLinkResponseStatusEnum.ACTIVE
                      ..slug = _salonA.slug
                      ..url = _salonA.url
                      ..displayName = _salonA.displayName
                      ..salonId = 'x/../..?tab='
                      ..bookable = false,
                  ),
                ]),
        ),
      );
      when(() => repo.getMine()).thenAnswer((_) async => mapped);

      await pumpScreen(tester, role: UserRole.salonOwner);

      expect(find.byKey(_card(_salonA.keyId)), findsOneWidget);
      expect(
        find.textContaining(l10nOf(tester).bookingLinkNotBookableSalon),
        findsOneWidget,
      );
      expect(find.byKey(_setup(_salonA.keyId)), findsNothing);
    });

    testWidgets('a bookable link shows no warning', (tester) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));

      await pumpScreen(tester, role: UserRole.independentMaster);

      expect(find.byKey(_setup(_master.keyId)), findsNothing);
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
      expect(find.byKey(_card(_master.keyId)), findsOneWidget);
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
      expect(find.byKey(_card(_master.keyId)), findsOneWidget);
    });
  });

  group('copy', () {
    testWidgets(
      'copies ONLY the link + "?s=c" (no utm_*), shows the success snack '
      'and the in-well check for 1.6 s',
      (tester) async {
        when(
          () => repo.getMine(),
        ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));

        await pumpScreen(tester, role: UserRole.independentMaster);
        final AppLocalizations l10n = l10nOf(tester);

        await tester.tap(find.byKey(_copy(_master.keyId)));
        await pumpVelvetSnackIn(tester);

        final String copied =
            verify(() => clipboard.copyText(captureAny())).captured.single
                as String;
        expect(copied, 'https://beautica.app/book/olena-koval-x7k2?s=c');
        expectVelvetSnack(
          l10n.bookingLinkCopied,
          variant: VelvetSnackVariant.success,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('booking-link-copied-${_master.keyId}')),
          findsOneWidget,
        );

        await tester.pump(BookingLinkCard.copiedDwell);
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('booking-link-copied-${_master.keyId}')),
          findsNothing,
        );
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets('clipboard failure → error snack, no check', (tester) async {
      when(() => clipboard.copyText(any())).thenAnswer((_) async => false);
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_salonA]));

      await pumpScreen(tester, role: UserRole.salonAdmin, salonId: 'salon-a');
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byKey(_copy(_salonA.keyId)));
      await pumpVelvetSnackIn(tester);

      expectVelvetSnack(
        l10n.bookingLinkCopyFailed,
        variant: VelvetSnackVariant.error,
      );
      expect(
        find.byKey(Key('booking-link-copied-${_salonA.keyId}')),
        findsNothing,
      );
      await pumpPastVelvetSnack(tester);
    });
  });

  group('share', () {
    testWidgets('master: «Записуйтеся онлайн: {link?s=s}»', (tester) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));

      await pumpScreen(tester, role: UserRole.independentMaster);
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byKey(_share(_master.keyId)));
      await tester.pumpAndSettle();

      const String url = 'https://beautica.app/book/olena-koval-x7k2?s=s';
      final List<dynamic> captured = verify(
        () => share.shareText(
          captureAny(),
          subject: captureAny(named: 'subject'),
        ),
      ).captured;
      // Exactly the localized text over the link + share flag — no subject.
      expect(captured, <Object?>[l10n.bookingLinkShareTextMaster(url), null]);
      verifyNever(() => clipboard.copyText(any()));
    });

    testWidgets('salon: name + salon link + "?s=s"; failure → error '
        'snack', (tester) async {
      when(
        () => share.shareText(any(), subject: any(named: 'subject')),
      ).thenAnswer((_) async => ShareOutcome.failed);
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_salonA]));

      await pumpScreen(tester, role: UserRole.salonOwner);
      final AppLocalizations l10n = l10nOf(tester);

      await tester.tap(find.byKey(_share(_salonA.keyId)));
      await pumpVelvetSnackIn(tester);

      const String url = 'https://beautica.app/book/s/lumiere-kyiv?s=s';
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

      await tester.tap(find.byKey(_share(hostile.keyId)));
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
      const String url = 'https://beautica.app/book/s/lumiere-kyiv?s=s';
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

  group('regenerate (phase 415)', () {
    setUpAll(() => registerFallbackValue(_master));

    BookingLink regenerated(BookingLink l, String slug) => l.copyWith(
      slug: slug,
      url: l.kind == BookingLinkKind.salon
          ? 'https://beautica.app/book/s/$slug'
          : 'https://beautica.app/book/$slug',
      bookable: true,
      status: BookingLinkStatus.active,
    );

    Future<void> confirmRegenerate(WidgetTester tester, Key button) async {
      await tester.tap(find.byKey(button));
      await tester.pumpAndSettle();
      expect(find.byKey(_dialog), findsOneWidget);
      await tester.tap(find.byKey(_confirm));
      await tester.pump();
    }

    testWidgets('active card: glyph with semantic label; cancel does nothing', (
      tester,
    ) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));

      await pumpScreen(tester, role: UserRole.independentMaster);
      final AppLocalizations l10n = l10nOf(tester);

      expect(find.byKey(_regen(_master.keyId)), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.bookingLinkRegenerate), findsWidgets);
      expect(
        tester.getSize(find.byKey(_regen(_master.keyId))).height,
        greaterThanOrEqualTo(48),
      );

      await tester.tap(find.byKey(_regen(_master.keyId)));
      await tester.pumpAndSettle();
      expect(find.text(l10n.bookingLinkRegenerateTitle), findsOneWidget);
      expect(find.text(l10n.bookingLinkRegenerateBody), findsOneWidget);

      await tester.tap(find.byKey(_dismiss));
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsNothing);
      verifyNever(() => repo.regenerate(any()));
    });

    testWidgets('confirm → new URL in place + success snack; Copy sends the '
        'new url with ?s=c', (tester) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));
      final Completer<BookingLinkMutationOutcome> pending =
          Completer<BookingLinkMutationOutcome>();
      when(() => repo.regenerate(any())).thenAnswer((_) => pending.future);

      await pumpScreen(tester, role: UserRole.independentMaster);
      final AppLocalizations l10n = l10nOf(tester);

      await confirmRegenerate(tester, _regen(_master.keyId));
      await tester.pump();

      // In flight: progress in the header slot, the glyph gone.
      expect(
        find.byKey(Key('booking-link-busy-${_master.keyId}')),
        findsOneWidget,
      );
      expect(find.byKey(_regen(_master.keyId)), findsNothing);
      // ...and Share / Copy dimmed to 0.5 and deaf to taps.
      final Finder dim = find.ancestor(
        of: find.byKey(_share(_master.keyId)),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(dim.first).opacity, 0.5);
      await tester.tap(find.byKey(_copy(_master.keyId)), warnIfMissed: false);
      await tester.pump();
      verifyNever(() => clipboard.copyText(any()));

      pending.complete(
        BookingLinkMutationOutcome.done(regenerated(_master, 'olena-new1')),
      );
      await pumpVelvetSnackIn(tester);
      expectVelvetSnack(
        l10n.bookingLinkRegenerated,
        variant: VelvetSnackVariant.success,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_card('olena-new1')), findsOneWidget);
      expect(find.byKey(_card(_master.keyId)), findsNothing);
      verify(() => repo.regenerate(_master)).called(1);
      verify(() => repo.getMine()).called(1);
      await pumpPastVelvetSnack(tester);

      await tester.tap(find.byKey(_copy('olena-new1')));
      await tester.pump();
      final String copied =
          verify(() => clipboard.copyText(captureAny())).captured.single
              as String;
      expect(copied, 'https://beautica.app/book/olena-new1?s=c');
      await tester.pumpAndSettle();
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('revoked card: state text, no URL / Copy / Share / glyph / '
        'note; recreate → short confirm → currentSlug null → active', (
      tester,
    ) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_revokedMaster]));
      when(() => repo.regenerate(any())).thenAnswer(
        (_) async => BookingLinkMutationOutcome.done(
          regenerated(_revokedMaster, 'olena-new2'),
        ),
      );

      await pumpScreen(tester, role: UserRole.independentMaster);
      final AppLocalizations l10n = l10nOf(tester);
      const String id = 'revoked-master';

      expect(find.byKey(_card(id)), findsOneWidget);
      expect(find.text(l10n.bookingLinkRevokedState), findsOneWidget);
      expect(find.text(l10n.bookingLinkRevokedBody), findsOneWidget);
      expect(find.byKey(const Key('booking-link-url-$id')), findsNothing);
      expect(find.byKey(_copy(id)), findsNothing);
      expect(find.byKey(_share(id)), findsNothing);
      expect(find.byKey(_regen(id)), findsNothing);
      expect(find.byKey(_setup(id)), findsNothing);
      expect(find.text(l10n.bookingLinkNotBookableMaster), findsNothing);

      await tester.tap(find.byKey(_recreate(id)));
      await tester.pumpAndSettle();
      expect(find.text(l10n.bookingLinkRegenerateBodyRevoked), findsOneWidget);
      expect(find.text(l10n.bookingLinkRegenerateBody), findsNothing);
      await tester.tap(find.byKey(_confirm));
      await pumpVelvetSnackIn(tester);
      await tester.pumpAndSettle();

      final BookingLink sent =
          verify(() => repo.regenerate(captureAny())).captured.single
              as BookingLink;
      expect(sent.slug, isNull);
      expect(sent.isRevoked, isTrue);
      expect(find.byKey(_card('olena-new2')), findsOneWidget);
      expect(find.byKey(_copy('olena-new2')), findsOneWidget);
      expect(find.text(l10n.bookingLinkRevokedState), findsNothing);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('409 → warning snack + the links are re-read', (tester) async {
      int loads = 0;
      when(() => repo.getMine()).thenAnswer((_) async {
        loads++;
        return _enabled(<BookingLink>[
          loads == 1 ? _master : regenerated(_master, 'olena-elsewhere'),
        ]);
      });
      when(
        () => repo.regenerate(any()),
      ).thenAnswer((_) async => const BookingLinkMutationOutcome.stale());

      await pumpScreen(tester, role: UserRole.independentMaster);
      final AppLocalizations l10n = l10nOf(tester);

      await confirmRegenerate(tester, _regen(_master.keyId));
      await pumpVelvetSnackIn(tester);
      expectVelvetSnack(
        l10n.bookingLinkChangedElsewhere,
        variant: VelvetSnackVariant.warning,
      );
      await tester.pumpAndSettle();

      expect(loads, 2);
      expect(find.byKey(_card('olena-elsewhere')), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('404 (sharing switched off) → pops back (414 D7)', (
      tester,
    ) async {
      int loads = 0;
      when(() => repo.getMine()).thenAnswer((_) async {
        loads++;
        return loads == 1
            ? _enabled(<BookingLink>[_master])
            : BookingLinks.hidden;
      });
      when(
        () => repo.regenerate(any()),
      ).thenAnswer((_) async => const BookingLinkMutationOutcome.unavailable());

      await pumpScreen(tester, role: UserRole.independentMaster);
      await confirmRegenerate(tester, _regen(_master.keyId));
      await tester.pumpAndSettle();

      expect(find.byType(BookingLinkScreen), findsNothing);
      expect(find.byKey(_home), findsOneWidget);
    });

    // The test above also passes through the load-driven D7 close (the
    // reload says hidden). Here the reload still says visible, so only the
    // screen's own close on `unavailable` can pop it — pins that arm.
    testWidgets('404 → pops back even when the reload still shows links', (
      tester,
    ) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));
      when(
        () => repo.regenerate(any()),
      ).thenAnswer((_) async => const BookingLinkMutationOutcome.unavailable());

      await pumpScreen(tester, role: UserRole.independentMaster);
      await confirmRegenerate(tester, _regen(_master.keyId));
      await tester.pumpAndSettle();

      expect(find.byType(BookingLinkScreen), findsNothing);
      expect(find.byKey(_home), findsOneWidget);
    });

    final Map<String, Object> errorCases = <String, Object>{
      '429': const BookingLinkMutationOutcome.rateLimited(),
      '403': const ServerFailure(statusCode: 403),
    };
    errorCases.forEach((String label, Object answer) {
      testWidgets('$label → error snack, card unchanged', (tester) async {
        when(
          () => repo.getMine(),
        ).thenAnswer((_) async => _enabled(<BookingLink>[_master]));
        when(() => repo.regenerate(any())).thenAnswer((_) async {
          if (answer is Failure) throw answer;
          return answer as BookingLinkMutationOutcome;
        });

        await pumpScreen(tester, role: UserRole.independentMaster);
        final AppLocalizations l10n = l10nOf(tester);
        final BuildContext ctx = tester.element(find.byType(BookingLinkScreen));

        await confirmRegenerate(tester, _regen(_master.keyId));
        await pumpVelvetSnackIn(tester);
        expectVelvetSnack(
          answer is Failure
              ? answer.userMessage(ctx)
              : l10n.bookingLinkTooManyChanges,
          variant: VelvetSnackVariant.error,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_card(_master.keyId)), findsOneWidget);
        expect(find.byKey(_regen(_master.keyId)), findsOneWidget);
        verify(() => repo.getMine()).called(1);
        await pumpPastVelvetSnack(tester);
      });
    });

    testWidgets('owner with two salons regenerates one — the other card is '
        'untouched', (tester) async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => _enabled(<BookingLink>[_salonA, _salonB]));
      when(() => repo.regenerate(any())).thenAnswer(
        (_) async => BookingLinkMutationOutcome.done(
          regenerated(_salonA, 'lumiere-new'),
        ),
      );

      await pumpScreen(tester, role: UserRole.salonOwner);
      await confirmRegenerate(tester, _regen(_salonA.keyId));
      await pumpVelvetSnackIn(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(_card('lumiere-new')), findsOneWidget);
      expect(find.byKey(_card(_salonA.keyId)), findsNothing);
      expect(find.byKey(_card(_salonB.keyId)), findsOneWidget);
      expect(find.byKey(_regen(_salonB.keyId)), findsOneWidget);
      final double newTop = tester
          .getTopLeft(find.byKey(_card('lumiere-new')))
          .dy;
      final double bTop = tester
          .getTopLeft(find.byKey(_card(_salonB.keyId)))
          .dy;
      expect(newTop, lessThan(bTop));
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('a salon link without a salon id shows no regenerate glyph', (
      tester,
    ) async {
      when(() => repo.getMine()).thenAnswer(
        (_) async =>
            _enabled(<BookingLink>[_salonA.copyWith(salonId: null), _salonB]),
      );

      await pumpScreen(tester, role: UserRole.salonOwner);

      expect(find.byKey(_regen(_salonA.keyId)), findsNothing);
      expect(find.byKey(_regen(_salonB.keyId)), findsOneWidget);
    });
  });
}
