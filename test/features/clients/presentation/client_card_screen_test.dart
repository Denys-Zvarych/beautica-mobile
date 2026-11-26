// M510 — the provider client card (CLI-48): every state, the phone / rating
// chips, the timeline (D4), the not-found state and one-layout-for-all; the
// salon master chips (CLI-73 / CLI-74): owner / admin only, hidden with 0
// masters, a chip re-reads ONLY the visits with its `masterId`.
//
// The repository is faked at the `ClientRepository` seam; the router is a stub
// that records the rating / booking routes the card opens. Layout at 360 / 414
// px and text 1.0× / 1.3× is checked by the suite-wide overflow guard (any
// RenderFlex overflow fails the test in tearDown). `pumpAndSettle` fires no
// Timer and the skeleton animates forever, so loads are awaited with
// `pumpUntil`-style pumps on a condition, never a fixed wait.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/share/clipboard_service.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';
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
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
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
  List<ClientServedMaster> served = const <ClientServedMaster>[],
}) => ClientCard(
  ref: ref,
  displayName: name,
  avatarUrl: avatarUrl,
  phone: phone,
  blocked: blocked,
  ratingAvg: avg,
  ratingCount: count,
  ratingDistribution: const <int>[9, 2, 1, 0, 0],
  servedByMasters: served,
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

  /// CLI-74 — per-`masterId` visit pages; a missing key falls back to [pages].
  Map<String?, List<List<ClientVisit>>> pagesByMaster =
      <String?, List<List<ClientVisit>>>{};

  /// The scope of every card / visits request, in order.
  final List<ClientListScope> cardScopes = <ClientListScope>[];
  final List<ClientListScope> visitScopes = <ClientListScope>[];

  /// Visit pages (0-based) that fail with a [NetworkFailure].
  final Set<int> failVisitPages = <int>{};

  /// M544 — the removal writes, in order (`remove:<scope>` / `restore:…`).
  final List<String> writes = <String>[];
  Failure? removeFailure;

  @override
  Future<void> removeFromList(ClientListScope scope, ClientRef client) async {
    writes.add('remove');
    final Failure? f = removeFailure;
    if (f != null) throw f;
  }

  @override
  Future<void> restoreToList(ClientListScope scope, ClientRef client) async {
    writes.add('restore');
    final Failure? f = restoreFailure;
    if (f != null) throw f;
  }

  /// M544 — when set, the undo's restore throws it.
  Failure? restoreFailure;

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    cardScopes.add(scope);
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
    visitScopes.add(scope);
    if (failVisitPages.contains(page)) throw const NetworkFailure();
    final String? masterId = switch (scope) {
      SalonClientListScope(:final String? masterId) => masterId,
      MyClientListScope() => null,
    };
    final List<List<ClientVisit>> served = pagesByMaster[masterId] ?? pages;
    return PageResponse<ClientVisit>(
      items: served[page],
      page: page,
      totalPages: served.length,
      totalElements: 0,
    );
  }

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
    this.scope = const ClientListScope.me(),
    this.onBook,
  });

  final _Repo repo;

  /// M543 — the card's «Записати» launcher; `null` → no button (today).
  final void Function(BuildContext, ClientPrefill)? onBook;
  final ClientListScope scope;
  final List<Object> extra;
  final ClientRef client;
  final UserRole? role;
  final _FakeClipboard clipboard = _FakeClipboard();
  final List<String> opened = <String>[];

  /// The injected clock's value (mutable for the app-resume test).
  DateTime now = _now;

  late final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            ClientCardScreen(
              scope: scope,
              client: client,
              cardBase: RouteNames.masterClients,
              bookingRoute: RouteNames.masterBookingDetail,
              onBookClient: onBook,
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
    clockProvider.overrideWithValue(() => now),
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
  ClientListScope scope = const ClientListScope.me(),
  void Function(BuildContext, ClientPrefill)? onBook,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final _Harness h = _Harness(
    repo,
    client: client,
    role: role,
    extra: extra,
    scope: scope,
    onBook: onBook,
  );
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
      // By the month row's key (Kyiv year * 12 + month); the values pin the
      // exact month-label format.
      String? month(int year, int m) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(
                ValueKey<String>('timeline-month-${year * 12 + m}'),
              ),
              matching: find.byType(Text),
            ),
          )
          .data;
      expect(month(2026, 11), 'Листопад 2026');
      expect(month(2026, 10), 'Жовтень 2026');
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
        expect(h.opened, <String>[
          '/master/bookings/b-peel?$kBookingFromClientCardQuery=1',
        ]);
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
      expect(h.opened, <String>[
        '/master/bookings/p1?$kBookingFromClientCardQuery=1',
      ]);
    });

    testWidgets('app resume re-reads now: a «Наступний візит» whose start '
        'passed while backgrounded moves into the history, no request', (
      tester,
    ) async {
      final _Repo repo = _Repo(
        card: (ref) => _card(ref),
        pages: <List<ClientVisit>>[
          <ClientVisit>[
            _visit(
              'soon',
              _now.add(const Duration(hours: 1)),
              status: BookingStatus.confirmed,
            ),
            _visit('p1', _now.subtract(const Duration(days: 9))),
          ],
        ],
      );
      final _Harness h = await _pump(tester, repo);
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsOneWidget);
      final int reads = repo.visitPages.length;

      h.now = _now.add(const Duration(hours: 2));
      for (final AppLifecycleState st in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsNothing);
      expect(find.byKey(ClientCardScreen.visitKey('soon')), findsOneWidget);
      expect(repo.visitPages.length, reads, reason: 'no refetch on resume');
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

  group('master chips (CLI-73 / CLI-74)', () {
    const ClientListScope salon = ClientListScope.salon(salonId: 's-1');
    // Chip ids are UUIDs: a non-UUID chip id is ignored (never queried).
    const String m1 = 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    const String m2 = 'c2eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    const List<ClientServedMaster> two = <ClientServedMaster>[
      ClientServedMaster(masterId: m2, name: 'Ірина'),
      ClientServedMaster(masterId: m1, name: 'Олена'),
    ];
    Finder chips() => find.byKey(ClientCardScreen.masterChipsKey);
    Finder chip(String id) => find.byKey(ClientCardScreen.masterChipKey(id));
    Finder all() => find.byKey(ClientCardScreen.masterChipAllKey);

    bool selected(WidgetTester tester, Finder f) =>
        tester.getSemantics(f).flagsCollection.isSelected == Tristate.isTrue;

    _Repo repoWithFilter() =>
        _Repo(
            card: (ClientRef r) => _card(r, served: two),
            pages: <List<ClientVisit>>[
              <ClientVisit>[
                _visit(
                  'all-future',
                  _now.add(const Duration(days: 3)),
                  status: BookingStatus.confirmed,
                ),
                _visit('all-past', _now.subtract(const Duration(days: 3))),
              ],
            ],
          )
          ..pagesByMaster = <String?, List<List<ClientVisit>>>{
            m1: <List<ClientVisit>>[
              <ClientVisit>[
                _visit('m1-past', _now.subtract(const Duration(days: 5))),
              ],
            ],
          };

    for (final UserRole role in <UserRole>[
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      testWidgets('$role: «Усі майстри» (selected) + one chip per master, '
          'server order, above the timeline', (tester) async {
        await _pump(tester, repoWithFilter(), role: role, scope: salon);
        expect(chips(), findsOneWidget);
        expect(
          find.descendant(
            of: all(),
            matching: find.text(_l10n(tester).clientMastersFilterAll),
          ),
          findsOneWidget,
        );
        expect(selected(tester, all()), isTrue);
        expect(selected(tester, chip(m1)), isFalse);
        expect(
          tester.getTopLeft(chip(m2)).dx,
          lessThan(tester.getTopLeft(chip(m1)).dx),
          reason: 'most recent first = server order',
        );
        expect(
          tester.getTopLeft(chips()).dy,
          lessThan(
            tester.getTopLeft(find.byKey(ClientCardScreen.nextVisitKey)).dy,
          ),
        );
      });
    }

    testWidgets('select a master → visits re-read with masterId (history AND '
        'next visit), card not refetched; «Усі майстри» clears from cache', (
      tester,
    ) async {
      final _Repo repo = repoWithFilter();
      await _pump(tester, repo, role: UserRole.salonOwner, scope: salon);
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsOneWidget);
      expect(repo.cardScopes, hasLength(1));

      await tester.tap(chip(m1));
      await _loaded(tester);
      await tester.pumpAndSettle();
      expect(
        repo.visitScopes.last,
        const ClientListScope.salon(salonId: 's-1', masterId: m1),
      );
      expect(find.byKey(ClientCardScreen.visitKey('m1-past')), findsOneWidget);
      expect(find.byKey(ClientCardScreen.visitKey('all-past')), findsNothing);
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsNothing);
      expect(selected(tester, chip(m1)), isTrue);
      expect(selected(tester, all()), isFalse);
      expect(chip(m2), findsOneWidget, reason: 'chips stay salon-wide');
      expect(repo.cardScopes, hasLength(1), reason: 'card not refetched');

      final int reads = repo.visitScopes.length;
      await tester.tap(all());
      await _loaded(tester);
      await tester.pumpAndSettle();
      // Cache-for: back to an already-opened chip reuses its pages.
      expect(repo.visitScopes, hasLength(reads), reason: 'no re-read');
      expect(find.byKey(ClientCardScreen.visitKey('all-past')), findsOneWidget);
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsOneWidget);
      expect(selected(tester, all()), isTrue);
      expect(repo.cardScopes, hasLength(1));
    });

    testWidgets('pull-to-refresh on «Усі» drops EVERY chip\'s cached visits: '
        'back to a chip opened before → refetched', (tester) async {
      final _Repo repo = repoWithFilter();
      await _pump(tester, repo, role: UserRole.salonOwner, scope: salon);
      await tester.tap(chip(m1));
      await _loaded(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(ClientCardScreen.visitKey('m1-past')), findsOneWidget);
      await tester.tap(all());
      await tester.pumpAndSettle();

      repo.pagesByMaster[m1] = <List<ClientVisit>>[
        <ClientVisit>[_visit('m1-new', _now.subtract(const Duration(days: 1)))],
      ];
      await tester.fling(
        find.byType(CustomScrollView).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      final int reads = repo.visitScopes.length;
      await tester.tap(chip(m1));
      await _loaded(tester);
      await tester.pumpAndSettle();
      expect(
        repo.visitScopes.length,
        greaterThan(reads),
        reason: 'the m1 instance was invalidated, not served from cache',
      );
      expect(find.byKey(ClientCardScreen.visitKey('m1-new')), findsOneWidget);
      expect(find.byKey(ClientCardScreen.visitKey('m1-past')), findsNothing);
    });

    testWidgets('a route masterId (master mode) → no chip row even when that '
        'master is among the chips; visits stay scoped to it', (tester) async {
      final _Repo repo = repoWithFilter();
      const ClientListScope routeScope = ClientListScope.salon(
        salonId: 's-1',
        masterId: m1,
      );
      await _pump(tester, repo, role: UserRole.salonAdmin, scope: routeScope);
      expect(chips(), findsNothing);
      expect(all(), findsNothing);
      expect(repo.visitScopes.toSet(), <ClientListScope>{routeScope});
    });

    testWidgets('a chip tap rebuilds the chips + timeline, NOT the header', (
      tester,
    ) async {
      await _pump(
        tester,
        repoWithFilter(),
        role: UserRole.salonOwner,
        scope: salon,
      );
      final Widget avatar = tester.widget(find.byType(ClientAvatar));
      final Widget name = tester.widget(find.byKey(ClientCardScreen.nameKey));

      await tester.tap(chip(m1));
      await _loaded(tester);
      await tester.pumpAndSettle();
      expect(selected(tester, chip(m1)), isTrue);
      expect(find.byKey(ClientCardScreen.visitKey('m1-past')), findsOneWidget);
      // A header rebuild would construct NEW widget instances.
      expect(
        identical(tester.widget(find.byType(ClientAvatar)), avatar),
        isTrue,
        reason: 'header avatar not rebuilt',
      );
      expect(
        identical(tester.widget(find.byKey(ClientCardScreen.nameKey)), name),
        isTrue,
        reason: 'header name not rebuilt',
      );
    });

    testWidgets('the avatar report is built once: a screen rebuild reuses '
        'the same PhotoViewerReport', (tester) async {
      await _pump(
        tester,
        repoWithFilter(),
        role: UserRole.salonOwner,
        scope: salon,
      );
      final ClientAvatar before = tester.widget(find.byType(ClientAvatar));
      expect(before.previewReport, isNotNull);

      tester.element(find.byType(ClientCardScreen)).markNeedsBuild();
      await tester.pump();
      final ClientAvatar after = tester.widget(find.byType(ClientAvatar));
      expect(identical(after, before), isFalse, reason: 'header rebuilt');
      expect(identical(after.previewReport, before.previewReport), isTrue);
    });

    testWidgets('a non-UUID chip id is ignored: no visits re-read, the '
        'selection stays', (tester) async {
      final _Repo repo = _Repo(
        card: (ClientRef r) => _card(
          r,
          served: const <ClientServedMaster>[
            ClientServedMaster(masterId: 'not-a-uuid', name: 'Ірина'),
            ClientServedMaster(masterId: m1, name: 'Олена'),
          ],
        ),
      );
      await _pump(tester, repo, role: UserRole.salonOwner, scope: salon);
      final int reads = repo.visitScopes.length;

      await tester.tap(chip('not-a-uuid'));
      await tester.pumpAndSettle();
      expect(repo.visitScopes, hasLength(reads));
      expect(repo.visitScopes.last, salon);
      expect(selected(tester, all()), isTrue);
      expect(selected(tester, chip('not-a-uuid')), isFalse);
    });

    testWidgets('owner master mode: servedByMasters (salon-wide) includes the '
        'owner\'s own row → still no chip row, no «Усі майстри», the visits '
        'stay scoped to the own row', (tester) async {
      const String own = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
      const ClientListScope ownScope = ClientListScope.salon(
        salonId: 's-1',
        masterId: own,
      );
      // Realistic: the backend's `servedByMasters` is salon-wide, so the
      // owner's own master row is always present beside the others.
      final _Repo repo = repoWithFilter()
        ..card = (ClientRef r) => _card(
          r,
          served: const <ClientServedMaster>[
            ClientServedMaster(masterId: own, name: 'Власниця'),
            ...two,
          ],
        );
      await _pump(tester, repo, role: UserRole.salonOwner, scope: ownScope);
      expect(chips(), findsNothing);
      expect(all(), findsNothing);
      expect(repo.visitScopes.toSet(), <ClientListScope>{ownScope});
    });

    testWidgets('one master → chip row: «Усі майстри» + that master', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repo(card: (ClientRef r) => _card(r, served: two.sublist(0, 1))),
        role: UserRole.salonOwner,
        scope: salon,
      );
      expect(chips(), findsOneWidget);
      expect(all(), findsOneWidget);
      expect(chip(m2), findsOneWidget);
      expect(chip(m1), findsNothing);
      expect(selected(tester, all()), isTrue);
    });

    testWidgets('no masters → no chip row', (tester) async {
      await _pump(
        tester,
        _Repo(card: _card),
        role: UserRole.salonOwner,
        scope: salon,
      );
      expect(chips(), findsNothing);
    });

    testWidgets('salon master → no chip row even with several masters', (
      tester,
    ) async {
      await _pump(
        tester,
        repoWithFilter(),
        role: UserRole.salonMaster,
        scope: salon,
      );
      expect(chips(), findsNothing);
    });

    testWidgets('independent master (me scope) → no chip row', (tester) async {
      await _pump(tester, repoWithFilter(), role: UserRole.independentMaster);
      expect(chips(), findsNothing);
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

  group('pull-to-refresh failure keeps the loaded card', () {
    Future<void> pull(WidgetTester tester) async {
      await tester.fling(
        find.byType(CustomScrollView).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('card refetch fails → header + timeline stay, error snack', (
      tester,
    ) async {
      final _Repo repo = _Repo(
        card: (ref) => _card(ref),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_visit('p1', _now.subtract(const Duration(days: 9)))],
        ],
      );
      await _pump(tester, repo);
      repo.cardFailure = const NetworkFailure();
      await pull(tester);
      expect(repo.cardScopes.length, greaterThan(1), reason: 'refetched');
      expect(find.byKey(ClientCardScreen.errorKey), findsNothing);
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      expect(find.byKey(ClientCardScreen.visitKey('p1')), findsOneWidget);
      expectVelvetSnack(
        const NetworkFailure().userMessage(
          tester.element(find.byType(ClientCardScreen)),
        ),
      );
    });

    testWidgets('visits refetch fails → the loaded timeline stays, error '
        'snack, no visits error state', (tester) async {
      final _Repo repo = _Repo(
        card: (ref) => _card(ref),
        pages: <List<ClientVisit>>[
          <ClientVisit>[_visit('p1', _now.subtract(const Duration(days: 9)))],
        ],
      );
      await _pump(tester, repo);
      repo.failVisitPages.add(0);
      await pull(tester);
      expect(repo.visitPages, <int>[0, 0]);
      expect(find.byKey(ClientCardScreen.visitsErrorKey), findsNothing);
      expect(find.byKey(ClientCardScreen.visitKey('p1')), findsOneWidget);
      expectVelvetSnack(
        const NetworkFailure().userMessage(
          tester.element(find.byType(ClientCardScreen)),
        ),
      );
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

    // Client-profile audit — the worst realistic header + chip row: one
    // unbreakable name word and a long master name on a chip, owner salon
    // card (chips shown) at the narrowest width and the largest text scale.
    testWidgets('360 px × text 1.3: a long single-word name and a long '
        'master-chip label do not overflow', (tester) async {
      const String m1 = 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
      const String longWord = 'Костянтинопольська-Хрещатицька';
      await _pump(
        tester,
        _Repo(
          card: (ref) => _card(
            ref,
            name: longWord,
            blocked: true,
            served: const <ClientServedMaster>[
              ClientServedMaster(
                masterId: m1,
                name: 'Олександра Ковальчук-Мельниченко',
              ),
            ],
          ),
          pages: <List<ClientVisit>>[
            <ClientVisit>[_visit('p', _now.subtract(const Duration(days: 9)))],
          ],
        ),
        role: UserRole.salonOwner,
        scope: const ClientListScope.salon(salonId: 's-1'),
        textScale: 1.3,
      );
      expect(find.byKey(ClientCardScreen.masterChipKey(m1)), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(ClientCardScreen.nameKey)).data,
        longWord,
      );
      // The chip row scrolls horizontally (by design): the long chip must
      // fit the screen on its own and be scrollable fully into view.
      final Finder chip = find.byKey(ClientCardScreen.masterChipKey(m1));
      expect(tester.getSize(chip).width, lessThan(360));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      expect(tester.getRect(chip).right, lessThanOrEqualTo(360));
      expect(tester.getRect(chip).left, greaterThanOrEqualTo(0));
    });

    // Audit cycle 2 — a ~41-char master name used to make the chip 367 px at
    // 360 px × 1.3 (label clipped, never ellipsised): the chip is now capped
    // at the row's width and its one-line label ends in an ellipsis.
    testWidgets('360 px × text 1.3: a 41-char master name ellipsises inside '
        'the screen, no overflow', (tester) async {
      const String m1 = 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
      const String longMaster = 'Олександра-Вікторія Ковальчук-Мельниченко';
      await _pump(
        tester,
        _Repo(
          card: (ref) => _card(
            ref,
            name: 'Олена Петренко',
            served: const <ClientServedMaster>[
              ClientServedMaster(masterId: m1, name: longMaster),
            ],
          ),
          pages: <List<ClientVisit>>[
            <ClientVisit>[_visit('p', _now.subtract(const Duration(days: 9)))],
          ],
        ),
        role: UserRole.salonOwner,
        scope: const ClientListScope.salon(salonId: 's-1'),
        textScale: 1.3,
      );
      final Finder chip = find.byKey(ClientCardScreen.masterChipKey(m1));
      expect(chip, findsOneWidget);
      expect(tester.takeException(), isNull);
      final Finder label = find.descendant(
        of: chip,
        matching: find.text(longMaster),
      );
      final Text text = tester.widget<Text>(label);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      // The label really is truncated (ellipsis drawn), not merely allowed to.
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        label,
      );
      expect(paragraph.didExceedMaxLines, isTrue);
      expect(tester.getSize(chip).width, lessThanOrEqualTo(360));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      expect(tester.getRect(chip).right, lessThanOrEqualTo(360));
      expect(tester.getRect(chip).left, greaterThanOrEqualTo(0));
    });
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

    testWidgets('salon master, guest: remove only (CLI-69, M544)', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repo(card: (ClientRef r) => _card(r)),
        client: _gst,
        role: UserRole.salonMaster,
        extra: env(anchor('b-1', clientId: null, blockable: false)),
      );
      await openSheet(tester);
      expect(find.byKey(ClientActionsSheet.reportKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.blockKey), findsNothing);
      expect(find.byKey(ClientActionsSheet.removeKey), findsOne);
    });

    // M544 (CLI-86) — «Прибрати зі списку» from the card: the card pops back
    // to where it was opened from and the undo snack shows there.
    Future<_Repo> pumpPushed(
      WidgetTester tester, {
      UserRole role = UserRole.salonOwner,
      Failure? removeFailure,
    }) async {
      final _Repo repo = regRepo()..removeFailure = removeFailure;
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: Text('list-page')),
          ),
          GoRoute(
            path: '/card',
            builder: (BuildContext context, GoRouterState state) =>
                const ClientCardScreen(
                  scope: ClientListScope.salon(salonId: 's-1'),
                  client: _reg,
                  cardBase: RouteNames.masterClients,
                  bookingRoute: RouteNames.masterBookingDetail,
                ),
          ),
        ],
      );
      final _Harness h = _Harness(repo, role: role, extra: env(anchor('bk-1')));
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpRoutedApp(
        router,
        overrides: h.overrides,
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();
      unawaited(router.push<void>('/card'));
      await _loaded(tester);
      return repo;
    }

    for (final UserRole role in <UserRole>[
      UserRole.salonOwner,
      UserRole.salonAdmin,
      UserRole.independentMaster,
      UserRole.salonMaster,
    ]) {
      testWidgets('$role: «Прибрати зі списку» is offered', (tester) async {
        await _pump(tester, regRepo(), role: role, extra: env(anchor('bk-1')));
        await openSheet(tester);
        expect(find.byKey(ClientActionsSheet.removeKey), findsOne);
      });
    }

    testWidgets('remove → back to the list + the undo snack with its '
        'countdown; «Повернути» calls restore once', (tester) async {
      final _Repo repo = await pumpPushed(tester);
      final AppLocalizations l10n = _l10n(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.removeKey));
      await tester.pump();
      // The list page is in the stack (offstage) all along: wait for the
      // card itself to leave.
      await pumpUntilGone(tester, find.byType(ClientCardScreen));

      expect(repo.writes, <String>['remove']);
      expect(find.byType(ClientCardScreen), findsNothing);
      expect(find.text('list-page'), findsOneWidget);
      expect(find.text(l10n.clientsRemovedSnack), findsOneWidget);
      expect(find.byKey(VelvetSnack.countdownKey), findsOneWidget);

      await tester.tap(find.text(l10n.clientsRemoveUndo));
      await tester.pump();
      await pumpUntilGone(tester, find.text(l10n.clientsRemovedSnack));
      expect(repo.writes, <String>['remove', 'restore']);
      await pumpPastVelvetSnack(tester, hasAction: true);
    });

    // PR #201 CI fix — the undo's error snack uses the ROOT navigator's
    // context (read through go_router): the card is gone by the time
    // «Повернути» fails, and the failure must still be shown on the list.
    testWidgets('restore fails AFTER the card popped → the failure snack shows '
        'on the list screen', (tester) async {
      final _Repo repo = await pumpPushed(tester)
        ..restoreFailure = const NetworkFailure();
      final AppLocalizations l10n = _l10n(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.removeKey));
      await tester.pump();
      await pumpUntilGone(tester, find.byType(ClientCardScreen));
      expect(find.text('list-page'), findsOneWidget);

      await tester.tap(find.text(l10n.clientsRemoveUndo));
      await tester.pump();
      final String message = const NetworkFailure().userMessage(
        tester.element(find.text('list-page')),
      );
      await pumpUntilFound(tester, find.text(message));
      expect(repo.writes, <String>['remove', 'restore']);
      expectVelvetSnack(message, variant: VelvetSnackVariant.error);
      expect(find.byType(ClientCardScreen), findsNothing);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets('a failed remove stays on the card with the error snack', (
      tester,
    ) async {
      final _Repo repo = await pumpPushed(
        tester,
        removeFailure: const NetworkFailure(),
      );
      final AppLocalizations l10n = _l10n(tester);
      await openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.removeKey));
      await tester.pump();
      await pumpUntilFound(tester, find.text(l10n.clientsRemoveFailed));

      expect(repo.writes, <String>['remove']);
      expect(find.byType(ClientCardScreen), findsOneWidget);
      expect(find.text(l10n.clientsRemoveFailed), findsOneWidget);
      expect(find.text(l10n.clientsRemovedSnack), findsNothing);
      await pumpPastVelvetSnack(tester);
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

    testWidgets('block on «Усі» drops EVERY chip\'s cached visits: back to a '
        'chip opened before → refetched (no stale cancelled visit)', (
      tester,
    ) async {
      const String m1 = 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
      const String m2 = 'c2eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
      final _Repo repo =
          _Repo(
              card: (ClientRef r) => _card(
                r,
                served: const <ClientServedMaster>[
                  ClientServedMaster(masterId: m2, name: 'Ірина'),
                  ClientServedMaster(masterId: m1, name: 'Олена'),
                ],
              ),
              pages: <List<ClientVisit>>[
                <ClientVisit>[
                  _visit('bk-1', _now.subtract(const Duration(days: 3))),
                ],
              ],
            )
            ..pagesByMaster = <String?, List<List<ClientVisit>>>{
              m1: <List<ClientVisit>>[
                <ClientVisit>[
                  _visit(
                    'm1-old',
                    _now.add(const Duration(days: 2)),
                    status: BookingStatus.confirmed,
                  ),
                ],
              ],
            };
      final FakeClientBlockRepository blocks = FakeClientBlockRepository();
      await _pump(
        tester,
        repo,
        role: UserRole.salonOwner,
        scope: const ClientListScope.salon(salonId: 's-1'),
        extra: env(anchor('bk-1'), blocks: blocks),
      );
      await tester.tap(find.byKey(ClientCardScreen.masterChipKey(m1)));
      await _loaded(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(ClientCardScreen.nextVisitKey), findsOneWidget);
      await tester.tap(find.byKey(ClientCardScreen.masterChipAllKey));
      await tester.pumpAndSettle();

      // The block cancels the m1 upcoming visit server-side: the m1 read now
      // serves only a past visit.
      repo.pagesByMaster[m1] = <List<ClientVisit>>[
        <ClientVisit>[_visit('m1-new', _now.subtract(const Duration(days: 1)))],
      ];
      await openSheet(tester);
      await tester.tap(find.byKey(ClientActionsSheet.blockKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BlockClientDialog.confirmKey));
      await tester.pumpAndSettle();
      expect(blocks.calls, <String>['block:bk-1']);

      final int reads = repo.visitScopes.length;
      await tester.tap(find.byKey(ClientCardScreen.masterChipKey(m1)));
      await _loaded(tester);
      await tester.pumpAndSettle();
      expect(
        repo.visitScopes.length,
        greaterThan(reads),
        reason: 'the m1 instance was invalidated, not served from cache',
      );
      expect(
        repo.visitScopes.last,
        const ClientListScope.salon(salonId: 's-1', masterId: m1),
      );
      expect(find.byKey(ClientCardScreen.visitKey('m1-new')), findsOneWidget);
      expect(
        find.byKey(ClientCardScreen.nextVisitKey),
        findsNothing,
        reason: 'the cancelled visit is no longer the upcoming one',
      );
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
        'no sheet, no report / block, an error snack (not silence)', (
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
      expectVelvetSnack(_l10n(tester).errUnknown);
      expect(blocks.calls, isEmpty);
      expect(reports.requests, isEmpty);
    });

    testWidgets('registered: a null-client anchor booking → no sheet, an '
        'error snack', (tester) async {
      await _pump(
        tester,
        regRepo(),
        extra: env(anchor('bk-1', clientId: null)),
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byType(ClientActionsSheet), findsNothing);
      expectVelvetSnack(_l10n(tester).errUnknown);
    });

    bool moreEnabled(WidgetTester tester) =>
        tester.widget<NeumorphicIconButton>(more).enabled;

    testWidgets('registered: «⋯» is disabled while the visits fail (no anchor '
        'yet) and does nothing on tap', (tester) async {
      final _Repo repo = regRepo()..failVisitPages.add(0);
      await _pump(tester, repo, extra: env(anchor('bk-1')));
      expect(find.byKey(ClientCardScreen.visitsErrorKey), findsOneWidget);
      expect(more, findsOneWidget);
      expect(moreEnabled(tester), isFalse);
      await tester.tap(more, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(ClientActionsSheet), findsNothing);
    });

    testWidgets('registered: «⋯» is disabled with no visits at all', (
      tester,
    ) async {
      final _Repo repo = _Repo(
        card: (ClientRef r) => _card(r),
        pages: <List<ClientVisit>>[<ClientVisit>[]],
      );
      await _pump(tester, repo, extra: env(anchor('bk-1')));
      expect(moreEnabled(tester), isFalse);
    });

    testWidgets('registered: «⋯» enables once the anchor visit is loaded', (
      tester,
    ) async {
      await _pump(tester, regRepo(), extra: env(anchor('bk-1')));
      expect(moreEnabled(tester), isTrue);
    });

    testWidgets('guest: «⋯» is enabled even before / without visits', (
      tester,
    ) async {
      final _Repo repo = _Repo(
        card: (ClientRef r) => _card(r),
        pages: <List<ClientVisit>>[<ClientVisit>[]],
      )..failVisitPages.add(0);
      await _pump(
        tester,
        repo,
        client: _gst,
        role: UserRole.independentMaster,
        extra: env(anchor('b-1', clientId: null)),
      );
      expect(moreEnabled(tester), isTrue);
    });
  });
  group('«Записати» (M543 / CLI-80)', () {
    Finder book() => find.byKey(ClientCardScreen.bookKey);

    ClientCard parts(
      ClientRef ref, {
      String? first = 'Оксана',
      String? last = 'Мельник',
      String? phone = _phone,
      String? avatarUrl,
      bool blocked = false,
      List<ClientServedMaster> served = const <ClientServedMaster>[],
    }) => _card(
      ref,
      avatarUrl: avatarUrl,
      phone: phone,
      blocked: blocked,
      served: served,
    ).copyWith(firstName: first, lastName: last);

    testWidgets('no launcher → no button (today\'s card)', (tester) async {
      await _pump(tester, _Repo(card: (ref) => parts(ref)));
      expect(book(), findsNothing);
    });

    for (final ClientRef client in <ClientRef>[_reg, _gst]) {
      testWidgets('launcher + loaded ${client.runtimeType} card → button '
          'under the chips; tap hands the fromCard prefill once', (
        tester,
      ) async {
        const String photo = 'https://cdn.example.test/o.jpg';
        final List<ClientPrefill> launched = <ClientPrefill>[];
        await _pump(
          tester,
          _Repo(card: (ref) => parts(ref, avatarUrl: photo)),
          client: client,
          onBook: (_, ClientPrefill p) => launched.add(p),
        );
        expect(book(), findsOneWidget);
        expect(find.text(_l10n(tester).clientCardBookCta), findsOneWidget);
        expect(
          tester.getTopLeft(book()).dy,
          greaterThan(tester.getBottomLeft(_ratingChip()).dy),
        );
        await tester.tap(book());
        await tester.pump();
        expect(launched, <ClientPrefill>[
          const ClientPrefill(
            firstName: 'Оксана',
            lastName: 'Мельник',
            phone: _phone,
            avatarUrl: photo,
            rating: 4.9,
            ratingCount: 12,
          ),
        ]);
        // M554 / CLI-D16 — the card's photo + rating ride along.
        expect(launched.single.avatarUrl, photo);
        expect(launched.single.rating, 4.9);
        expect(launched.single.ratingCount, 12);
      });
    }

    testWidgets('blocked client → button shown (owner rule)', (tester) async {
      await _pump(
        tester,
        _Repo(card: (ref) => parts(ref, blocked: true)),
        onBook: (_, _) {},
      );
      expect(find.byType(BlockedTag), findsOneWidget);
      expect(book(), findsOneWidget);
    });

    testWidgets('no phone → button shown, prefill phone null', (tester) async {
      final List<ClientPrefill> launched = <ClientPrefill>[];
      await _pump(
        tester,
        _Repo(card: (ref) => parts(ref, phone: null)),
        onBook: (_, ClientPrefill p) => launched.add(p),
      );
      await tester.tap(book());
      await tester.pump();
      expect(launched.single.phone, isNull);
      expect(launched.single.firstName, 'Оксана');
      expect(launched.single.lastName, 'Мельник');
    });

    testWidgets('nameless guest with a phone → button shown, names null', (
      tester,
    ) async {
      final List<ClientPrefill> launched = <ClientPrefill>[];
      await _pump(
        tester,
        _Repo(
          card: (ref) =>
              _card(ref, name: null).copyWith(firstName: null, lastName: null),
        ),
        client: _gst,
        onBook: (_, ClientPrefill p) => launched.add(p),
      );
      await tester.tap(book());
      await tester.pump();
      expect(launched, <ClientPrefill>[
        const ClientPrefill(phone: _phone, rating: 4.9, ratingCount: 12),
      ]);
      // No photo on the card → none in the prefill; the rating still rides.
      expect(launched.single.avatarUrl, isNull);
      expect(launched.single.rating, 4.9);
    });

    testWidgets('no name and no phone (anonymised) → no button', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repo(
          card: (ref) => _card(
            ref,
            name: null,
            phone: null,
          ).copyWith(firstName: null, lastName: null),
        ),
        onBook: (_, _) => fail('must not launch'),
      );
      expect(find.byKey(ClientCardScreen.nameKey), findsOneWidget);
      expect(book(), findsNothing);
    });

    testWidgets('loading → no button', (tester) async {
      final Completer<void> gate = Completer<void>();
      final _Harness h = _Harness(
        _Repo(card: (ref) => parts(ref), cardGate: gate),
        onBook: (_, _) {},
      );
      await tester.pumpRoutedApp(h.router, overrides: h.overrides);
      await tester.pump();
      expect(find.byKey(ClientCardScreen.skeletonKey), findsOneWidget);
      expect(book(), findsNothing);
      gate.complete();
      await _loaded(tester);
      expect(book(), findsOneWidget);
    });

    for (final Failure failure in const <Failure>[
      NotFoundFailure(),
      NetworkFailure(),
    ]) {
      testWidgets('${failure.runtimeType} → no button', (tester) async {
        final _Repo repo = _Repo(card: (ref) => parts(ref))
          ..cardFailure = failure;
        await _pump(tester, repo, onBook: (_, _) {});
        expect(find.byType(ErrorState), findsOneWidget);
        expect(book(), findsNothing);
      });
    }

    testWidgets('a selected master chip does not change the prefill; the '
        'launcher is called once', (tester) async {
      const String m1 = 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
      final List<ClientPrefill> launched = <ClientPrefill>[];
      await _pump(
        tester,
        _Repo(
          card: (ref) => parts(
            ref,
            served: const <ClientServedMaster>[
              ClientServedMaster(masterId: m1, name: 'Олена'),
            ],
          ),
        ),
        role: UserRole.salonOwner,
        scope: const ClientListScope.salon(salonId: 's-1'),
        onBook: (_, ClientPrefill p) => launched.add(p),
      );
      await tester.tap(find.byKey(ClientCardScreen.masterChipKey(m1)));
      await tester.pumpAndSettle();
      await tester.tap(book());
      await tester.pump();
      expect(launched, <ClientPrefill>[
        const ClientPrefill(
          firstName: 'Оксана',
          lastName: 'Мельник',
          phone: _phone,
          rating: 4.9,
          ratingCount: 12,
        ),
      ]);
      expect(launched.single.avatarUrl, isNull);
      expect(launched.single.rating, 4.9);
    });
  });
}
