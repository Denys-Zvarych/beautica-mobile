// M510 — the provider client card (CLI-48): every state, the phone / rating
// chips, the timeline (D4), the not-found state and one-layout-for-all.
//
// The repository is faked at the `ClientRepository` seam; the router is a stub
// that records the rating / booking routes the card opens. Layout at 360 / 414
// px and text 1.0× / 1.3× is checked by the suite-wide overflow guard (any
// RenderFlex overflow fails the test in tearDown). `pumpAndSettle` fires no
// Timer and the skeleton animates forever, so loads are awaited with
// `pumpUntil`-style pumps on a condition, never a fixed wait.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_own_rating.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/blocked_tag.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/phone_link.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_readout.dart';
import 'package:beautica_mobile/features/moderation/data/block_repository.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/block_confirm_dialog.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/content_actions_sheet.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:beautica_mobile/shared/widgets/profile_photo_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../helpers/fakes/fake_notification_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/route_pump.dart';
import '../../../helpers/velvet_snack_matchers.dart';
import '../../moderation/support/fake_client_block_repository.dart';
import '../../moderation/support/fake_content_report_repository.dart';

final DateTime _now = DateTime.utc(2026, 11, 20, 12);

const ClientRef _reg = ClientRef.registered('u-1');
const ClientRef _gst = ClientRef.guest('b-1');
const String _phone = '+380671234567';

/// [_phone] as DISPLAYED (the UA input mask); call / copy keep [_phone].
const String _phoneShown = '+380 67 123 45 67';

ClientVisit _visit(
  String key,
  DateTime at, {
  BookingStatus status = BookingStatus.completed,
  String service = 'Манікюр',
}) => ClientVisit(
  visitKey: key,
  startsAt: at,
  items: <ClientVisitItem>[
    ClientVisitItem(
      // One row per BOOKING: the row key is the bookingId.
      bookingId: key,
      serviceName: service,
      status: status,
      startsAt: at,
      price: 650,
    ),
  ],
);

ClientCard _card(
  ClientRef ref, {
  String? name = 'Оксана Мельник',
  String? avatarUrl,
  String? phone = _phone,
  bool blocked = false,
  double? avg = 4.9,
  int count = 12,
}) => ClientCard(
  ref: ref,
  displayName: name,
  avatarUrl: avatarUrl,
  phone: phone,
  blocked: blocked,
  ratingAvg: avg,
  ratingCount: count,
  ratingDistribution: const <int>[9, 2, 1, 0, 0],
);

class _Repo implements ClientRepository {
  _Repo({
    required this.card,
    this.pages = const <List<ClientVisit>>[<ClientVisit>[]],
    this.cardGate,
  });

  ClientCard Function(ClientRef ref)? card;
  final List<List<ClientVisit>> pages;
  final Completer<void>? cardGate;
  final List<int> visitPages = <int>[];
  Failure? cardFailure;

  /// Visit pages (0-based) that fail with a [NetworkFailure].
  final Set<int> failVisitPages = <int>{};

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    await cardGate?.future;
    final Failure? f = cardFailure;
    if (f != null) throw f;
    return card!(client);
  }

  @override
  Future<PageResponse<ClientVisit>> getVisits(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    visitPages.add(page);
    if (failVisitPages.contains(page)) throw const NetworkFailure();
    return PageResponse<ClientVisit>(
      items: pages[page],
      page: page,
      totalPages: pages.length,
      totalElements: 0,
    );
  }

  @override
  Future<PageResponse<ClientOwnRating>> getOwnRatings(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async => const PageResponse<ClientOwnRating>(
    items: <ClientOwnRating>[],
    page: 0,
    totalPages: 1,
    totalElements: 0,
  );

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
}

class _MockUrlLauncher extends Mock
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {}

class _FakeClipboard implements ClipboardService {
  final List<String> copied = <String>[];
  bool ok = true;

  @override
  Future<bool> copyText(String text) async {
    copied.add(text);
    return ok;
  }
}

class _Harness {
  _Harness(
    this.repo, {
    this.client = _reg,
    this.role,
    this.extra = const <Object>[],
  });

  final _Repo repo;
  final List<Object> extra;
  final ClientRef client;
  final UserRole? role;
  final _FakeClipboard clipboard = _FakeClipboard();
  final List<String> opened = <String>[];

  late final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            ClientCardScreen(
              scope: const ClientListScope.me(),
              client: client,
              cardBase: RouteNames.masterClients,
              bookingRoute: RouteNames.masterBookingDetail,
            ),
      ),
      GoRoute(
        path: '${RouteNames.masterClients}/user/:userId/rating',
        builder: (BuildContext context, GoRouterState state) {
          opened.add(state.uri.toString());
          return const Scaffold(body: Text('rating-page'));
        },
      ),
      GoRoute(
        path: '${RouteNames.masterClients}/guest/:bookingId/rating',
        builder: (BuildContext context, GoRouterState state) {
          opened.add(state.uri.toString());
          return const Scaffold(body: Text('rating-page'));
        },
      ),
      GoRoute(
        path: '${RouteNames.masterBookings}/:id',
        builder: (BuildContext context, GoRouterState state) {
          opened.add(state.uri.toString());
          return const Scaffold(body: Text('booking-detail'));
        },
      ),
    ],
  );

  List<Object> get overrides => <Object>[
    clientRepositoryProvider.overrideWithValue(repo),
    authProvider.overrideWith(
      () => FixedRoleAuth(role ?? UserRole.independentMaster),
    ),
    clockProvider.overrideWithValue(() => _now),
    clipboardServiceProvider.overrideWithValue(clipboard),
    ...extra,
  ];
}

Future<_Harness> _pump(
  WidgetTester tester,
  _Repo repo, {
  ClientRef client = _reg,
  UserRole? role,
  double width = 360,
  double? textScale,
  List<Object> extra = const <Object>[],
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final _Harness h = _Harness(repo, client: client, role: role, extra: extra);
  await tester.pumpRoutedApp(
    h.router,
    overrides: h.overrides,
    retry: (_, _) => null,
  );
  await _loaded(tester);
  return h;
}

/// Pumps until the card has resolved (the skeleton animates forever, so
/// `pumpAndSettle` would never return while it shows).
Future<void> _loaded(WidgetTester tester) async {
  await tester.pump();
  await pumpUntilGone(tester, find.byKey(ClientCardScreen.skeletonKey));
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ClientCardScreen)));

Finder _phoneChip() => find.byKey(ClientCardScreen.phoneChipKey);
Finder _ratingChip() => find.byKey(ClientCardScreen.ratingChipKey);

/// Every widget type under the card, in tree order — the "same layout" probe.
List<Type> _treeTypes(WidgetTester tester) => <Type>[
  for (final Element e
      in find
          .descendant(
            of: find.byType(ClientCardScreen),
            matching: find.byWidgetPredicate((_) => true),
          )
          .evaluate())
    e.widget.runtimeType,
];

void main() {
  group('header', () {
    testWidgets('registered with a photo: 96 dp avatar, name, no tag', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repo(
          card: (ref) =>
              _card(ref, avatarUrl: 'https://cdn.example.test/o.jpg'),
        ),
      );
      final ClientAvatar avatar = tester.widget<ClientAvatar>(
        find.byType(ClientAvatar),
      );
      expect(avatar.size, 96);
      expect(avatar.imageUrl, isNotNull);
      expect(avatar.previewOnTap, isTrue, reason: 'the card opts in (CLI-69)');
      expect(find.byType(ProfilePhotoPreviewTap), findsOneWidget);
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      // i18n-finder-ok: asserts the exact data value
      expect(find.text('Оксана Мельник'), findsOneWidget);
      expect(find.byType(BlockedTag), findsNothing);
    });

    testWidgets('no photo → 68 dp monogram with the initials', (tester) async {
      await _pump(tester, _Repo(card: (ref) => _card(ref)));
      expect(tester.widget<ClientAvatar>(find.byType(ClientAvatar)).size, 68);
      // The inert wrapper builds NO gesture / button semantics for a monogram.
      expect(
        find.descendant(
          of: find.byType(ProfilePhotoPreviewTap),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
        reason: 'a monogram is not tappable',
      );
      expect(
        find.bySemanticsLabel(_l10n(tester).profilePhotoViewAction),
        findsNothing,
      );
      // i18n-finder-ok: asserts the exact data value
      expect(find.text('ОМ'), findsOneWidget);
    });

    testWidgets('blocked → «Заблоковано» tag', (tester) async {
      await _pump(tester, _Repo(card: (ref) => _card(ref, blocked: true)));
      expect(find.byType(BlockedTag), findsOneWidget);
      expect(find.text(_l10n(tester).clientBlockedBadge), findsOneWidget);
    });

    testWidgets('nameless client reads «Гість»', (tester) async {
      await _pump(
        tester,
        _Repo(card: (ref) => _card(ref, name: null)),
        client: _gst,
      );
      expect(find.text(_l10n(tester).bookingDetailGuestClient), findsOneWidget);
    });
  });

  group('one layout for every kind and role (D1)', () {
    testWidgets('guest and registered with equal data build the SAME tree', (
      tester,
    ) async {
      final _Repo repo = _Repo(
        card: (ref) => _card(ref),
        pages: <List<ClientVisit>>[
          <ClientVisit>[
            _visit(
              'f',
              _now.add(const Duration(days: 3)),
              status: BookingStatus.confirmed,
            ),
            _visit('p', _now.subtract(const Duration(days: 9))),
          ],
        ],
      );
      await _pump(tester, repo, client: _reg);
      final List<Type> registered = _treeTypes(tester);

      await tester.pumpWidget(const SizedBox());
      await _pump(tester, repo, client: _gst);
      final List<Type> guest = _treeTypes(tester);

      expect(guest, registered);
    });

    for (final UserRole role in <UserRole>[
      UserRole.independentMaster,
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      for (final ClientRef ref in <ClientRef>[_reg, _gst]) {
        testWidgets('$role sees the phone chip for ${ref.runtimeType}', (
          tester,
        ) async {
          await _pump(
            tester,
            _Repo(card: (r) => _card(r, count: 0, avg: null)),
            client: ref,
            role: role,
          );
          expect(_phoneChip(), findsOneWidget);
          expect(find.text(_phoneShown), findsOneWidget);
          expect(find.text(_phone), findsNothing);
        });
      }
    }

    for (final ClientRef ref in <ClientRef>[_reg, _gst]) {
      testWidgets('salon master never sees a phone (${ref.runtimeType})', (
        tester,
      ) async {
        await _pump(
          tester,
          _Repo(card: (r) => _card(r)),
          client: ref,
          role: UserRole.salonMaster,
        );
        expect(_phoneChip(), findsNothing);
        expect(find.text(_phone), findsNothing);
        expect(find.text(_phoneShown), findsNothing);
        expect(_ratingChip(), findsOneWidget);
      });
    }

    testWidgets('phone null → no phone chip', (tester) async {
      await _pump(tester, _Repo(card: (ref) => _card(ref, phone: null)));
      expect(_phoneChip(), findsNothing);
      expect(_ratingChip(), findsOneWidget);
    });
  });

  group('phone sheet', () {
    testWidgets('chip → sheet with call and copy', (tester) async {
      await _pump(tester, _Repo(card: (ref) => _card(ref)));
      await tester.tap(_phoneChip());
      await tester.pumpAndSettle();
      final AppLocalizations l10n = _l10n(tester);
      expect(find.byKey(kPhoneSheetCallKey), findsOneWidget);
      expect(find.byKey(kPhoneSheetCopyKey), findsOneWidget);
      expect(find.text(l10n.clientCall), findsOneWidget);
      expect(find.text(l10n.clientCopyPhone), findsOneWidget);
      // Sheet title is the formatted number too (chip + title).
      expect(find.text(_phoneShown), findsNWidgets(2));
    });

    testWidgets('copy → clipboard + «Номер скопійовано»', (tester) async {
      final _Harness h = await _pump(tester, _Repo(card: (ref) => _card(ref)));
      await tester.tap(_phoneChip());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kPhoneSheetCopyKey));
      await pumpVelvetSnackIn(tester);
      expect(h.clipboard.copied, <String>[_phone]);
      expectVelvetSnack(_l10n(tester).clientPhoneCopied);
      expect(find.byKey(kPhoneSheetCopyKey), findsNothing);
      await pumpPastVelvetSnack(tester);
    });

    group('call', () {
      late _MockUrlLauncher launcher;
      late UrlLauncherPlatform original;

      setUp(() {
        original = UrlLauncherPlatform.instance;
        launcher = _MockUrlLauncher();
        UrlLauncherPlatform.instance = launcher;
        registerFallbackValue(const LaunchOptions());
      });
      tearDown(() => UrlLauncherPlatform.instance = original);

      testWidgets('«Зателефонувати» launches the tel: URI', (tester) async {
        when(
          () => launcher.launchUrl(any(), any()),
        ).thenAnswer((_) async => true);
        await _pump(tester, _Repo(card: (ref) => _card(ref)));
        await tester.tap(_phoneChip());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(kPhoneSheetCallKey));
        await tester.pumpAndSettle();
        final String launched =
            verify(
                  () => launcher.launchUrl(captureAny(), any()),
                ).captured.single
                as String;
        expect(launched, 'tel:$_phone');
        expect(find.byKey(kPhoneSheetCallKey), findsNothing);
      });
    });
  });

  group('rating chip', () {
    testWidgets('rated → «4,9 · 12 оцінок», opens the rating page', (
      tester,
    ) async {
      final _Harness h = await _pump(tester, _Repo(card: (ref) => _card(ref)));
      expect(
        find.text('4,9 · ${_l10n(tester).clientRatingCount(12)}'),
        findsOneWidget,
      );
      await tester.tap(_ratingChip());
      await tester.pumpAndSettle();
      expect(h.opened, <String>['/master/clients/user/u-1/rating']);
      expect(find.text('rating-page'), findsOneWidget);
    });

    testWidgets('a guest\'s rating page route is the guest one', (
      tester,
    ) async {
      final _Harness h = await _pump(
        tester,
        _Repo(card: (ref) => _card(ref)),
        client: _gst,
      );
      await tester.tap(_ratingChip());
      await tester.pumpAndSettle();
      expect(h.opened, <String>['/master/clients/guest/b-1/rating']);
    });

    for (final ClientRef ref in <ClientRef>[_reg, _gst]) {
      testWidgets('unrated (${ref.runtimeType}) → «Ще немає оцінок», not '
          'tappable', (tester) async {
        final _Harness h = await _pump(
          tester,
          _Repo(card: (r) => _card(r, avg: null, count: 0)),
          client: ref,
        );
        expect(find.byKey(RatingReadout.emptyKey), findsOneWidget);
        expect(find.text(_l10n(tester).clientRatingEmpty), findsOneWidget);
        await tester.tap(_ratingChip());
        await tester.pumpAndSettle();
        expect(h.opened, isEmpty);
        expect(find.text('rating-page'), findsNothing);
      });
    }
  });

  group('timeline (D4)', () {
    testWidgets('next visit is the head and is not repeated in history', (
      tester,
    ) async {
      final ClientVisit next = _visit(
        'next',
        _now.add(const Duration(days: 3)),
        status: BookingStatus.confirmed,
      );
      await _pump(
        tester,
        _Repo(
          card: (ref) => _card(ref),
          pages: <List<ClientVisit>>[
            <ClientVisit>[
              next,
              _visit('p1', _now.subtract(const Duration(days: 9))),
            ],
          ],
        ),
      );
      final AppLocalizations l10n = _l10n(tester);
      expect(find.text(l10n.clientNextVisitTitle), findsOneWidget);
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsOneWidget);
      expect(find.byKey(ClientCardScreen.visitKey('next')), findsNothing);
      expect(find.byKey(ClientCardScreen.visitKey('p1')), findsOneWidget);
      expect(find.text(l10n.clientHistoryTitle), findsOneWidget);
    });

    testWidgets('no upcoming visit → no «Наступний візит»', (tester) async {
      await _pump(
        tester,
        _Repo(
          card: (ref) => _card(ref),
          pages: <List<ClientVisit>>[
            <ClientVisit>[_visit('p1', _now.subtract(const Duration(days: 9)))],
          ],
        ),
      );
      expect(find.text(_l10n(tester).clientNextVisitTitle), findsNothing);
    });

    testWidgets('month labels follow KYIV time, not UTC', (tester) async {
      // 2026-10-31 22:30Z is 00:30 on 1 Nov in Kyiv (EET, UTC+2).
      await _pump(
        tester,
        _Repo(
          card: (ref) => _card(ref),
          pages: <List<ClientVisit>>[
            <ClientVisit>[
              _visit('nov', DateTime.utc(2026, 10, 31, 22, 30)),
              _visit('oct', DateTime.utc(2026, 10, 30, 10)),
            ],
          ],
        ),
      );
      // i18n-finder-ok: asserts the exact month-label format
      expect(find.text('Листопад 2026'), findsOneWidget);
      // i18n-finder-ok: asserts the exact month-label format
      expect(find.text('Жовтень 2026'), findsOneWidget);
    });

    testWidgets('no master name, counters, kind label or «З нами з»', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repo(
          card: (ref) => _card(ref),
          pages: <List<ClientVisit>>[
            <ClientVisit>[_visit('p1', _now.subtract(const Duration(days: 9)))],
          ],
        ),
      );
      for (final String banned in <String>[
        'Візитів',
        'Завершено',
        'Заплановано',
        'Клієнт Beautica',
        'З нами з',
        'Запис за посиланням',
      ]) {
        expect(find.textContaining(banned), findsNothing, reason: banned);
      }
    });

    testWidgets('empty history → the notice', (tester) async {
      await _pump(tester, _Repo(card: (ref) => _card(ref)));
      expect(find.byKey(ClientCardScreen.historyEmptyKey), findsOneWidget);
      expect(find.text(_l10n(tester).clientHistoryEmptyTitle), findsOneWidget);
    });

    group('one row per booking (BOOK-05)', () {
      const String longName = 'Пілінг шкіри голови та комплексний догляд';
      // The API groups two bookings of one appointment into one visit; the
      // card must still show one row per booking.
      ClientVisit grouped() {
        final DateTime at = _now.subtract(const Duration(days: 4));
        return ClientVisit(
          visitKey: 'appt-1',
          startsAt: at,
          items: <ClientVisitItem>[
            ClientVisitItem(
              bookingId: 'b-lips',
              serviceName: 'Губи',
              status: BookingStatus.cancelled,
              startsAt: at,
              price: 12000,
            ),
            ClientVisitItem(
              bookingId: 'b-peel',
              serviceName: longName,
              status: BookingStatus.completed,
              startsAt: at.add(const Duration(hours: 1)),
              price: 950,
              priceMax: 2000,
            ),
          ],
        );
      }

      Future<_Harness> pumpGrouped(WidgetTester tester) => _pump(
        tester,
        _Repo(
          card: (ref) => _card(ref),
          pages: <List<ClientVisit>>[
            <ClientVisit>[grouped()],
          ],
        ),
      );

      testWidgets('a grouped visit renders as separate rows, each its own '
          'status and its own booking detail', (tester) async {
        final _Harness h = await pumpGrouped(tester);
        final Finder lips = find.byKey(ClientCardScreen.visitKey('b-lips'));
        final Finder peel = find.byKey(ClientCardScreen.visitKey('b-peel'));
        expect(lips, findsOneWidget);
        expect(peel, findsOneWidget);
        expect(find.byKey(ClientCardScreen.visitKey('appt-1')), findsNothing);
        expect(
          find.descendant(of: lips, matching: find.byType(BookingStatusBadge)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: peel, matching: find.byType(BookingStatusBadge)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: lips, matching: find.text(longName)),
          findsNothing,
        );
        await tester.tap(peel);
        await tester.pumpAndSettle();
        expect(h.opened, <String>['/master/bookings/b-peel']);
      });

      testWidgets('a long service name wraps by WORD, not per letter (360)', (
        tester,
      ) async {
        await pumpGrouped(tester);
        final RenderParagraph p = tester.renderObject<RenderParagraph>(
          find.text(longName),
        );
        // Every word fits the name's width, so no word is broken across
        // lines (the bug wrapped «Пілінг / шкіри / голов / и»).
        for (final String word in longName.split(' ')) {
          final TextPainter tp = TextPainter(
            text: TextSpan(text: word, style: p.text.style),
            textDirection: TextDirection.ltr,
            textScaler: p.textScaler,
          )..layout();
          expect(tp.width, lessThanOrEqualTo(p.size.width), reason: word);
          tp.dispose();
        }
        // The name has at least half the card's content width.
        final double card = tester
            .getSize(find.byKey(ClientCardScreen.visitKey('b-peel')))
            .width;
        expect(p.size.width, greaterThan(card / 2));
      });

      testWidgets('each row is announced with ITS booking\'s status', (
        tester,
      ) async {
        await pumpGrouped(tester);
        final AppLocalizations l10n = _l10n(tester);
        String label(String id) => tester
            .getSemantics(find.byKey(ClientCardScreen.visitKey(id)))
            .label;
        final String cancelled = l10n.bookingStatusSemantics(
          l10n.bookingStatusCancelled,
        );
        final String completed = l10n.bookingStatusSemantics(
          l10n.bookingStatusCompleted,
        );
        expect(label('b-lips'), contains(cancelled));
        expect(label('b-lips'), contains('Губи'));
        expect(label('b-lips'), isNot(contains(completed)));
        expect(label('b-peel'), contains(completed));
        expect(label('b-peel'), contains(longName));
        expect(label('b-peel'), isNot(contains(cancelled)));
      });
    });

    testWidgets('a visit row opens its booking detail', (tester) async {
      final _Harness h = await _pump(
        tester,
        _Repo(
          card: (ref) => _card(ref),
          pages: <List<ClientVisit>>[
            <ClientVisit>[_visit('p1', _now.subtract(const Duration(days: 9)))],
          ],
        ),
      );
      await tester.tap(find.byKey(ClientCardScreen.visitKey('p1')));
      await tester.pumpAndSettle();
      expect(h.opened, <String>['/master/bookings/p1']);
    });

    testWidgets('scrolling to the end loads the next page of visits', (
      tester,
    ) async {
      final _Repo repo = _Repo(
        card: (ref) => _card(ref),
        pages: <List<ClientVisit>>[
          <ClientVisit>[
            for (int i = 0; i < 12; i++)
              _visit('a$i', _now.subtract(Duration(days: 10 + i))),
          ],
          <ClientVisit>[_visit('b0', _now.subtract(const Duration(days: 200)))],
        ],
      );
      await _pump(tester, repo);
      expect(repo.visitPages, <int>[0]);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();
      expect(repo.visitPages, <int>[0, 1]);
      expect(find.byKey(ClientCardScreen.visitKey('b0')), findsOneWidget);
    });

    testWidgets('a failed first visits page → its own retry, the header '
        'stays; retry reloads the timeline', (tester) async {
      final _Repo repo = _Repo(
        card: (ref) => _card(ref),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_visit('p1', _now.subtract(const Duration(days: 9)))],
        ],
      )..failVisitPages.add(0);
      await _pump(tester, repo);
      expect(find.byKey(ClientCardScreen.visitsErrorKey), findsOneWidget);
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      expect(_ratingChip(), findsOneWidget);
      expect(find.byKey(ClientCardScreen.errorKey), findsNothing);

      repo.failVisitPages.clear();
      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await tester.pumpAndSettle();
      expect(repo.visitPages, <int>[0, 0]);
      expect(find.byKey(ClientCardScreen.visitsErrorKey), findsNothing);
      expect(find.byKey(ClientCardScreen.visitKey('p1')), findsOneWidget);
    });

    testWidgets('a failed visits append → the retry footer, no retry storm; '
        'tapping it loads the page', (tester) async {
      final _Repo repo = _Repo(
        card: (ref) => _card(ref),
        pages: <List<ClientVisit>>[
          <ClientVisit>[
            for (int i = 0; i < 12; i++)
              _visit('a$i', _now.subtract(Duration(days: 10 + i))),
          ],
          <ClientVisit>[_visit('b0', _now.subtract(const Duration(days: 200)))],
        ],
      )..failVisitPages.add(1);
      await _pump(tester, repo);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();
      expect(repo.visitPages, <int>[0, 1]);
      expect(find.byKey(ClientCardScreen.visitsRetryMoreKey), findsOneWidget);
      expect(find.byKey(ClientCardScreen.visitKey('b0')), findsNothing);

      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(repo.visitPages, <int>[0, 1], reason: 'paused until retry');

      repo.failVisitPages.clear();
      await tester.tap(find.byKey(ClientCardScreen.visitsRetryMoreKey));
      await tester.pumpAndSettle();
      expect(repo.visitPages, <int>[0, 1, 1]);
      expect(find.byKey(ClientCardScreen.visitsRetryMoreKey), findsNothing);
      expect(find.byKey(ClientCardScreen.visitKey('b0')), findsOneWidget);
    });

    testWidgets('the timeline is a lazy sliver: off-screen visits are not '
        'built; each row carries its visit key', (tester) async {
      final _Repo repo = _Repo(
        card: (ref) => _card(ref),
        pages: <List<ClientVisit>>[
          <ClientVisit>[
            for (int i = 0; i < 60; i++)
              _visit('a$i', _now.subtract(Duration(days: 10 + i))),
          ],
        ],
      );
      await _pump(tester, repo);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(SliverList), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('a0')), findsOneWidget);
      expect(
        find.byKey(ClientCardScreen.visitKey('a59'), skipOffstage: false),
        findsNothing,
        reason: 'a 60-visit history must not build every row up front',
      );
    });
  });

  group('states', () {
    testWidgets('loading → skeleton', (tester) async {
      final Completer<void> gate = Completer<void>();
      final _Harness h = _Harness(
        _Repo(card: (ref) => _card(ref), cardGate: gate),
      );
      await tester.pumpRoutedApp(h.router, overrides: h.overrides);
      await tester.pump();
      expect(find.byKey(ClientCardScreen.skeletonKey), findsOneWidget);
      gate.complete();
      await _loaded(tester);
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
    });

    testWidgets('404 → «Клієнта не знайдено» + back, no retry', (tester) async {
      final _Repo repo = _Repo(card: (ref) => _card(ref))
        ..cardFailure = const NotFoundFailure();
      await _pump(tester, repo);
      expect(find.byKey(ClientCardScreen.notFoundKey), findsOneWidget);
      expect(find.text(_l10n(tester).clientNotFound), findsOneWidget);
      expect(find.byKey(const Key('error_state_retry_button')), findsNothing);
      expect(find.byKey(ClientCardScreen.backKey), findsOneWidget);
    });

    testWidgets('a guest handle attached to an account since the list '
        'loaded (404 after attach) → the same not-found state', (tester) async {
      final _Repo repo = _Repo(card: (ref) => _card(ref))
        ..cardFailure = const NotFoundFailure();
      await _pump(tester, repo, client: _gst);
      expect(find.byKey(ClientCardScreen.notFoundKey), findsOneWidget);
      expect(find.text(_l10n(tester).clientNotFound), findsOneWidget);
    });

    testWidgets('other failure → retry that reloads', (tester) async {
      final _Repo repo = _Repo(card: (ref) => _card(ref))
        ..cardFailure = const NetworkFailure();
      await _pump(tester, repo);
      expect(find.byKey(ClientCardScreen.errorKey), findsOneWidget);
      expect(find.byType(ErrorState), findsOneWidget);
      repo.cardFailure = null;
      await tester.tap(find.byKey(const Key('error_state_retry_button')));
      await _loaded(tester);
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
    });
  });

  group('layout (no overflow — the suite guard fails on any)', () {
    for (final double width in <double>[360, 414]) {
      for (final double scale in <double>[1.0, 1.3]) {
        testWidgets('${width.toInt()} px × text $scale', (tester) async {
          await _pump(
            tester,
            _Repo(
              card: (ref) => _card(
                ref,
                name: 'Олександра Ковальчук-Мельниченко',
                blocked: true,
              ),
              pages: <List<ClientVisit>>[
                <ClientVisit>[
                  _visit(
                    'f',
                    _now.add(const Duration(days: 2)),
                    status: BookingStatus.confirmed,
                    service: 'Манікюр з покриттям гель-лаком та дизайном',
                  ),
                  _visit('p', _now.subtract(const Duration(days: 9))),
                ],
              ],
            ),
            width: width,
            textScale: scale,
          );
          expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
        });
      }
    }
  });

  // ── 2026-11-21 — the top bar «⋯»: the SAME report / block / unblock flow
  //    as the provider «Деталі запису» client strip, through ONE booking of
  //    the client (guest: the card's anchor; registered: the newest visit).
  group('«⋯» client actions', () {
    Booking anchor(
      String id, {
      String? clientId = 'u-1',
      bool blocked = false,
      bool blockable = true,
    }) {
      final DateTime start = _now.subtract(const Duration(days: 3));
      return Booking(
        id: id,
        masterId: 'm1',
        masterFirstName: 'Марія',
        masterLastName: 'Іванюк',
        masterType: 'INDEPENDENT_MASTER',
        clientId: clientId,
        clientFirstName: 'Оксана',
        clientLastName: 'Мельник',
        serviceId: 's1',
        serviceName: 'Манікюр',
        durationMinutes: 60,
        price: 500,
        startAt: start,
        endAt: start.add(const Duration(minutes: 60)),
        status: BookingStatus.completed,
        canReview: false,
        clientBlocked: blocked,
        clientBlockId: blocked ? 'block-1' : null,
        clientBlockable: !blocked && blockable,
      );
    }

    final Finder more = find.byKey(ClientCardScreen.moreKey);

    _Repo regRepo({bool blocked = false}) => _Repo(
      card: (ClientRef r) => _card(r, blocked: blocked),
      pages: <List<ClientVisit>>[
        <ClientVisit>[_visit('bk-1', _now.subtract(const Duration(days: 3)))],
      ],
    );

    List<Object> env(
      Booking b, {
      FakeClientBlockRepository? blocks,
      FakeContentReportRepository? reports,
    }) => <Object>[
      bookingDetailProvider(b.id).overrideWith((ref) async => b),
      clientBlockRepositoryProvider.overrideWithValue(
        blocks ?? FakeClientBlockRepository(),
      ),
      contentReportRepositoryProvider.overrideWithValue(
        reports ?? FakeContentReportRepository(),
      ),
    ];

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byType(ClientActionsSheet), findsOne);
    }

    for (final UserRole role in <UserRole>[
      UserRole.independentMaster,
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      testWidgets('$role, registered: report + block', (tester) async {
        await _pump(tester, regRepo(), role: role, extra: env(anchor('bk-1')));
        await openSheet(tester);
        expect(find.byKey(ClientActionsSheet.reportKey), findsOne);
        expect(find.byKey(ClientActionsSheet.blockKey), findsOne);
        expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);
      });
    }

    testWidgets('salon master, registered: report only', (tester) async {
      await _pump(
        tester,
        regRepo(),
        role: UserRole.salonMaster,
        extra: env(anchor('bk-1', blockable: false)),
      );
      await openSheet(tester);
      expect(find.byKey(ClientActionsSheet.reportKey), findsOne);
      expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.unblockKey), findsNothing);
    });

    testWidgets('salon master, guest: no «⋯» at all', (tester) async {
      await _pump(
        tester,
        _Repo(card: (ClientRef r) => _card(r)),
        client: _gst,
        role: UserRole.salonMaster,
        extra: env(anchor('b-1', clientId: null, blockable: false)),
      );
      expect(more, findsNothing);
    });

    testWidgets('independent master, guest: block only, through the card\'s '
        'own anchor booking', (tester) async {
      final FakeClientBlockRepository blocks = FakeClientBlockRepository();
      await _pump(
        tester,
        _Repo(card: (ClientRef r) => _card(r)),
        client: _gst,
        extra: env(anchor('b-1', clientId: null), blocks: blocks),
      );
      await openSheet(tester);
      expect(find.byKey(ClientActionsSheet.reportKey), findsNothing);
      await tester.tap(find.byKey(ClientActionsSheet.blockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BlockClientDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(blocks.calls, <String>['block:b-1']);
    });

    testWidgets('block → «Заблоковано» tag after the card refreshes', (
      tester,
    ) async {
      bool blockedNow = false;
      final _Repo repo = _Repo(
        card: (ClientRef r) => _card(r, blocked: blockedNow),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_visit('bk-1', _now.subtract(const Duration(days: 3)))],
        ],
      );
      final FakeClientBlockRepository blocks = FakeClientBlockRepository();
      await _pump(tester, repo, extra: env(anchor('bk-1'), blocks: blocks));
      expect(find.byKey(BlockedTag.tagKey), findsNothing);

      await openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.blockKey));
      await tester.pumpAndSettle();
      blockedNow = true;
      await tester.tap(find.byKey(BlockClientDialog.confirmKey));
      await tester.pump();
      await pumpUntilFound(tester, find.byKey(BlockedTag.tagKey));

      expect(blocks.calls, <String>['block:bk-1']);
      expect(find.byKey(BlockedTag.tagKey), findsOne);
      expect(find.text(_l10n(tester).clientBlockedSnack), findsOne);
    });

    testWidgets('an already-blocked client offers «Розблокувати»', (
      tester,
    ) async {
      final FakeClientBlockRepository blocks = FakeClientBlockRepository();
      await _pump(
        tester,
        regRepo(blocked: true),
        extra: env(anchor('bk-1', blocked: true), blocks: blocks),
      );
      await openSheet(tester);
      expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
      await tester.tap(find.byKey(ClientActionsSheet.unblockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UnblockClientDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(blocks.calls, <String>['unblock:block-1']);
    });

    testWidgets('report opens the existing report sheet for the client '
        'profile', (tester) async {
      final FakeContentReportRepository reports = FakeContentReportRepository();
      await _pump(
        tester,
        regRepo(),
        extra: env(anchor('bk-1'), reports: reports),
      );
      await openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.reportKey));
      await tester.pumpAndSettle();
      expect(find.byType(ReportSheet), findsOne);
      await tester.tap(find.byKey(ReportSheet.reasonKey(ReportReason.spam)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ReportSheet.submitKey));
      await tester.tap(find.byKey(ReportSheet.submitKey));
      await tester.pumpAndSettle();
      expect(
        reports.requests.single.targetType,
        ReportTargetType.clientProfile,
      );
      expect(reports.requests.single.targetId, 'u-1');
    });

    testWidgets('registered: the anchor booking belongs to ANOTHER client → '
        '«⋯» does nothing (no sheet, no report / block, no snack)', (
      tester,
    ) async {
      final FakeClientBlockRepository blocks = FakeClientBlockRepository();
      final FakeContentReportRepository reports = FakeContentReportRepository();
      await _pump(
        tester,
        regRepo(),
        extra: env(
          anchor('bk-1', clientId: 'u-other'),
          blocks: blocks,
          reports: reports,
        ),
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byType(ClientActionsSheet), findsNothing);
      expect(find.byType(ReportSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(blocks.calls, isEmpty);
      expect(reports.requests, isEmpty);
    });

    testWidgets('registered: a null-client anchor booking → «⋯» does nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        regRepo(),
        extra: env(anchor('bk-1', clientId: null)),
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byType(ClientActionsSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
