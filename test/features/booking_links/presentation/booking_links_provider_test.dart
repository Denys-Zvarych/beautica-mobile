// Phase 413 — bookingLinksProvider + bookingLinksVisibleProvider (D3 / D4).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:fake_async/fake_async.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking_links/data/booking_links_repository.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_links_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_notification_repository.dart'
    show FixedRoleAuth;
import '../../../helpers/test_container.dart';

class _MockBookingLinksRepository extends Mock
    implements BookingLinksRepository {}

class _SignedOutAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

const BookingLink _master = BookingLink(
  kind: BookingLinkKind.master,
  slug: 'anna',
  url: 'https://beautica.app/book/anna',
  displayName: 'Anna',
  bookable: true,
);

void main() {
  late _MockBookingLinksRepository repo;

  setUp(() => repo = _MockBookingLinksRepository());

  ProviderContainer container({AuthNotifier Function()? auth}) =>
      makeTestContainer(
        overrides: <Object>[
          authProvider.overrideWith(
            auth ?? () => FixedRoleAuth(UserRole.independentMaster),
          ),
          bookingLinksRepositoryProvider.overrideWithValue(repo),
        ],
      );

  /// Reads the visibility after the links load settles (success or error).
  /// Listens to BOTH the row's provider and the screen's one: since the cache
  /// split they are siblings over the per-account family, not a chain.
  Future<bool> settledVisibility(ProviderContainer c) async {
    final ProviderSubscription<bool> sub = c.listen(
      bookingLinksVisibleProvider,
      (_, _) {},
    );
    addTearDown(sub.close);
    final ProviderSubscription<AsyncValue<BookingLinks>> linksSub = c.listen(
      bookingLinksProvider,
      (_, _) {},
    );
    addTearDown(linksSub.close);
    await c
        .read(bookingLinksProvider.future)
        .then<void>((_) {}, onError: (_) {});
    return c.read(bookingLinksVisibleProvider);
  }

  group('BookingLinks.isVisible truth table', () {
    final List<({bool shareEnabled, List<BookingLink> links, bool visible})>
    rows = <({bool shareEnabled, List<BookingLink> links, bool visible})>[
      (shareEnabled: true, links: <BookingLink>[_master], visible: true),
      (shareEnabled: true, links: <BookingLink>[], visible: false),
      (shareEnabled: false, links: <BookingLink>[_master], visible: false),
      (shareEnabled: false, links: <BookingLink>[], visible: false),
    ];
    for (final r in rows) {
      test('shareEnabled=${r.shareEnabled}, links=${r.links.length} → '
          '${r.visible}', () {
        expect(
          BookingLinks(shareEnabled: r.shareEnabled, links: r.links).isVisible,
          r.visible,
        );
      });
    }
  });

  group('bookingLinksVisibleProvider', () {
    test('enabled with a link → visible', () async {
      when(() => repo.getMine()).thenAnswer(
        (_) async => const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master],
        ),
      );
      final ProviderContainer c = container();

      expect(await settledVisibility(c), isTrue);
      expect(c.read(bookingLinksProvider).value?.links, <BookingLink>[_master]);
    });

    test('kill-switch off → not visible', () async {
      when(() => repo.getMine()).thenAnswer((_) async => BookingLinks.hidden);

      expect(await settledVisibility(container()), isFalse);
    });

    for (final UserRole role in <UserRole>[
      UserRole.client,
      UserRole.salonMaster,
    ]) {
      test('${role.name} → hidden without ever calling the backend', () async {
        when(
          () => repo.getMine(),
        ).thenAnswer((_) async => throw const ServerFailure(statusCode: 403));
        final ProviderContainer c = container(auth: () => FixedRoleAuth(role));

        expect(await settledVisibility(c), isFalse);
        expect(c.read(bookingLinksProvider).value, BookingLinks.hidden);
        verifyNever(() => repo.getMine());
      });
    }

    test('repository error → not visible, no throw', () async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => throw const ServerFailure(statusCode: 403));
      final ProviderContainer c = container();

      expect(await settledVisibility(c), isFalse);
      expect(c.read(bookingLinksProvider).hasError, isTrue);
    });

    test('a refresh that still holds this account\'s value stays visible '
        '(no blink)', () async {
      final ProviderContainer c = container();
      when(() => repo.getMine()).thenAnswer(
        (_) async => const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master],
        ),
      );
      final List<bool> visibility = <bool>[];
      final ProviderSubscription<bool> sub = c.listen(
        bookingLinksVisibleProvider,
        (_, bool next) => visibility.add(next),
      );
      addTearDown(sub.close);
      final ProviderSubscription<AsyncValue<BookingLinks>> linksSub = c.listen(
        bookingLinksProvider,
        (_, _) {},
      );
      addTearDown(linksSub.close);
      await c.read(bookingLinksProvider.future);
      expect(c.read(bookingLinksVisibleProvider), isTrue);
      visibility.clear();

      final Completer<BookingLinks> pending = Completer<BookingLinks>();
      when(() => repo.getMine()).thenAnswer((_) => pending.future);
      c.invalidate(bookingLinksForAccountProvider);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(bookingLinksProvider).isLoading, isTrue);
      expect(c.read(bookingLinksVisibleProvider), isTrue);

      pending.complete(
        const BookingLinks(shareEnabled: true, links: <BookingLink>[_master]),
      );
      await c.read(bookingLinksProvider.future);
      expect(c.read(bookingLinksVisibleProvider), isTrue);
      expect(visibility, isNot(contains(false)));
      verify(() => repo.getMine()).called(2);
    });

    test('while loading → not visible', () async {
      final Completer<BookingLinks> pending = Completer<BookingLinks>();
      when(() => repo.getMine()).thenAnswer((_) => pending.future);
      final ProviderContainer c = container();
      final ProviderSubscription<bool> sub = c.listen(
        bookingLinksVisibleProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      final ProviderSubscription<AsyncValue<BookingLinks>> linksSub = c.listen(
        bookingLinksProvider,
        (_, _) {},
      );
      addTearDown(linksSub.close);
      await c.read(authProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(bookingLinksProvider).isLoading, isTrue);
      expect(c.read(bookingLinksVisibleProvider), isFalse);

      pending.complete(
        const BookingLinks(shareEnabled: true, links: <BookingLink>[_master]),
      );
      await c.read(bookingLinksProvider.future);
      expect(c.read(bookingLinksVisibleProvider), isTrue);
    });

    test('a transient failure stays hidden through the retry, then shows '
        'once the retry succeeds', () async {
      int calls = 0;
      when(() => repo.getMine()).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw const NetworkFailure();
        return const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master],
        );
      });
      final ProviderContainer c = container();
      final List<AsyncValue<BookingLinks>> states =
          <AsyncValue<BookingLinks>>[];
      final List<bool> visibility = <bool>[];
      final ProviderSubscription<AsyncValue<BookingLinks>> linksSub = c.listen(
        bookingLinksProvider,
        (_, _) {},
      );
      addTearDown(linksSub.close);
      // The row reads the per-account family (the fetch + cache), so that is
      // where the retry shape is observed.
      final ProviderSubscription<AsyncValue<BookingLinks>> accountSub = c
          .listen(
            bookingLinksForAccountProvider('u1', UserRole.independentMaster),
            (_, AsyncValue<BookingLinks> next) => states.add(next),
          );
      addTearDown(accountSub.close);
      final ProviderSubscription<bool> visSub = c.listen(
        bookingLinksVisibleProvider,
        (_, bool next) => visibility.add(next),
        fireImmediately: true,
      );
      addTearDown(visSub.close);

      await c.read(bookingLinksProvider.future);

      // The mid-retry shape (loading WITH the error) was actually reached.
      expect(
        states.any((AsyncValue<BookingLinks> s) => s.isLoading && s.hasError),
        isTrue,
      );
      expect(calls, 2);
      // Hidden throughout the failure + retry window; shown once it recovers.
      expect(visibility, <bool>[false]);
      expect(c.read(bookingLinksVisibleProvider), isTrue);
    });

    test('logout after a visible load → hidden, no backend call', () async {
      when(() => repo.getMine()).thenAnswer(
        (_) async => const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master],
        ),
      );
      final ProviderContainer c = container();
      expect(await settledVisibility(c), isTrue);

      c.read(authProvider.notifier).state = const AsyncData<AuthSession>(
        AuthSession.unauthenticated(),
      );

      expect(await settledVisibility(c), isFalse);
      expect(c.read(bookingLinksProvider).value, BookingLinks.hidden);
      verify(() => repo.getMine()).called(1);
    });

    test('signed out → hidden without calling the backend', () async {
      final ProviderContainer c = container(auth: _SignedOutAuth.new);

      expect(await settledVisibility(c), isFalse);
      expect(c.read(bookingLinksProvider).value, BookingLinks.hidden);
      verifyNever(() => repo.getMine());
    });
  });

  group('session scoping', () {
    test('an account switch refetches; the old links are not reused', () async {
      when(() => repo.getMine()).thenAnswer(
        (_) async => const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master],
        ),
      );
      final ProviderContainer c = container();
      expect(await settledVisibility(c), isTrue);
      verify(() => repo.getMine()).called(1);

      when(() => repo.getMine()).thenAnswer((_) async => BookingLinks.hidden);
      (c.read(authProvider.notifier) as FixedRoleAuth).switchUser('u2');

      expect(await settledVisibility(c), isFalse);
      expect(c.read(bookingLinksProvider).value, BookingLinks.hidden);
      verify(() => repo.getMine()).called(1);
    });

    test(
      'after an account switch the previous account\'s links never read as '
      'visible — neither while reloading nor when the reload fails',
      () async {
        when(() => repo.getMine()).thenAnswer(
          (_) async => const BookingLinks(
            shareEnabled: true,
            links: <BookingLink>[_master],
          ),
        );
        final ProviderContainer c = container();
        expect(await settledVisibility(c), isTrue);

        final Completer<BookingLinks> pending = Completer<BookingLinks>();
        when(() => repo.getMine()).thenAnswer((_) => pending.future);
        (c.read(authProvider.notifier) as FixedRoleAuth).switchUser('u2');
        await Future<void>.delayed(Duration.zero);

        // Riverpod keeps the PREVIOUS value on the reloading AsyncValue.
        expect(c.read(bookingLinksProvider).value?.isVisible, isTrue);
        expect(c.read(bookingLinksProvider).isLoading, isTrue);
        expect(c.read(bookingLinksVisibleProvider), isFalse);

        pending.completeError(const ServerFailure(statusCode: 403));
        await c
            .read(bookingLinksProvider.future)
            .then<void>((_) {}, onError: (_) {});
        await Future<void>.delayed(Duration.zero);

        expect(c.read(bookingLinksProvider).hasError, isTrue);
        expect(c.read(bookingLinksProvider).value?.isVisible, isTrue);
        expect(c.read(bookingLinksVisibleProvider), isFalse);
      },
    );

    test('a silent token refresh (same user) does NOT refetch', () async {
      when(() => repo.getMine()).thenAnswer(
        (_) async => const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master],
        ),
      );
      final ProviderContainer c = container();
      expect(await settledVisibility(c), isTrue);

      final FixedRoleAuth auth = c.read(authProvider.notifier) as FixedRoleAuth;
      final Authenticated current =
          c.read(authProvider).value! as Authenticated;
      auth.state = AsyncData<AuthSession>(
        AuthSession.authenticated(
          user: current.user,
          accessToken: 'refreshed-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(c.read(bookingLinksVisibleProvider), isTrue);
      verify(() => repo.getMine()).called(1);
    });
  });

  // Phase 414 perf — the per-account cache (60 s after the last listener).
  group('cache', () {
    const BookingLinks visibleLinks = BookingLinks(
      shareEnabled: true,
      links: <BookingLink>[_master],
    );

    /// One hub "open": listen to the row's provider until it settles, then
    /// leave.
    void openHub(ProviderContainer c, FakeAsync async) {
      final ProviderSubscription<bool> sub = c.listen(
        bookingLinksVisibleProvider,
        (_, _) {},
      );
      async.elapse(Duration.zero);
      expect(c.read(bookingLinksVisibleProvider), isTrue);
      sub.close();
      async.flushMicrotasks();
    }

    test('reopening within 60 s does not refetch; after 60 s it does', () {
      fakeAsync((FakeAsync async) {
        when(() => repo.getMine()).thenAnswer((_) async => visibleLinks);
        final ProviderContainer c = container();

        openHub(c, async);
        async.elapse(const Duration(seconds: 59));
        openHub(c, async);
        verify(() => repo.getMine()).called(1);

        // The re-listen cancelled the first timer; a fresh 60 s runs now.
        async.elapse(bookingLinksCacheTtl + const Duration(seconds: 1));
        openHub(c, async);
        verify(() => repo.getMine()).called(1);
      });
    });

    test('logout drops the cache: hidden, no fetch; the same user signing '
        'back in refetches', () {
      fakeAsync((FakeAsync async) {
        when(() => repo.getMine()).thenAnswer((_) async => visibleLinks);
        final ProviderContainer c = container();
        openHub(c, async);
        final AuthSession signedIn = c.read(authProvider).requireValue;

        c.read(authProvider.notifier).state = const AsyncData<AuthSession>(
          AuthSession.unauthenticated(),
        );
        async.flushMicrotasks();
        final ProviderSubscription<bool> sub = c.listen(
          bookingLinksVisibleProvider,
          (_, _) {},
        );
        final ProviderSubscription<AsyncValue<BookingLinks>> linksSub = c
            .listen(bookingLinksProvider, (_, _) {});
        async.elapse(Duration.zero);
        expect(c.read(bookingLinksVisibleProvider), isFalse);
        expect(c.read(bookingLinksProvider).value, BookingLinks.hidden);
        sub.close();
        linksSub.close();
        verify(() => repo.getMine()).called(1);

        c.read(authProvider.notifier).state = AsyncData<AuthSession>(signedIn);
        async.flushMicrotasks();
        openHub(c, async);
        verify(() => repo.getMine()).called(1);
      });
    });

    // P2 race (perf re-audit, cycle 2): the hooks must exist BEFORE the
    // fetch settles, and a fetch that settles for a stale account must not
    // be pinned.
    /// Settles the session first: the family reads it after the fetch, and
    /// an unsettled session would read as "account gone" (a vacuous pass).
    void signIn(ProviderContainer c, FakeAsync async) {
      final ProviderSubscription<AsyncValue<AuthSession>> auth = c.listen(
        authProvider,
        (_, _) {},
      );
      addTearDown(auth.close);
      async.elapse(Duration.zero);
      expect(c.read(authProvider).value, isA<Authenticated>());
    }

    final BookingLinksForAccountProvider u1Links =
        bookingLinksForAccountProvider('u1', UserRole.independentMaster);

    test('the last listener leaving DURING the fetch still expires the entry '
        '60 s later', () {
      fakeAsync((FakeAsync async) {
        final Completer<BookingLinks> pending = Completer<BookingLinks>();
        when(() => repo.getMine()).thenAnswer((_) => pending.future);
        final ProviderContainer c = container();
        signIn(c, async);
        // Something outside the hub keeps the instance alive across the
        // fetch (the screen's provider, a pushed route…), so it is still
        // mounted when the fetch settles.
        final ProviderSubscription<AsyncValue<BookingLinks>> direct = c.listen(
          u1Links,
          (_, _) {},
        );
        async.elapse(Duration.zero);
        direct.close();
        async.flushMicrotasks();

        pending.complete(visibleLinks);
        async.flushMicrotasks();

        async.elapse(bookingLinksCacheTtl + const Duration(seconds: 1));
        expect(c.exists(u1Links), isFalse);

        when(() => repo.getMine()).thenAnswer((_) async => visibleLinks);
        openHub(c, async);
        verify(() => repo.getMine()).called(2);
      });
    });

    test('logout during the in-flight fetch: nothing is cached, the next '
        'account sees nothing of the old one', () {
      fakeAsync((FakeAsync async) {
        final Completer<BookingLinks> pending = Completer<BookingLinks>();
        when(() => repo.getMine()).thenAnswer((_) => pending.future);
        final ProviderContainer c = container();
        signIn(c, async);
        final ProviderSubscription<AsyncValue<BookingLinks>> direct = c.listen(
          u1Links,
          (_, _) {},
        );
        async.elapse(Duration.zero);
        final AuthSession signedIn = c.read(authProvider).requireValue;

        c.read(authProvider.notifier).state = const AsyncData<AuthSession>(
          AuthSession.unauthenticated(),
        );
        async.flushMicrotasks();
        pending.complete(visibleLinks);
        async.flushMicrotasks();

        // The stale fetch settles as hidden, not as the old account's links.
        expect(c.read(u1Links).value, BookingLinks.hidden);
        direct.close();
        async.elapse(Duration.zero);
        // …and is not pinned: gone as soon as nobody listens.
        expect(c.exists(u1Links), isFalse);

        // Another account signs in: nothing of u1's links shows.
        when(() => repo.getMine()).thenAnswer((_) async => BookingLinks.hidden);
        (c.read(authProvider.notifier) as FixedRoleAuth).state =
            AsyncData<AuthSession>(signedIn);
        (c.read(authProvider.notifier) as FixedRoleAuth).switchUser('u2');
        async.flushMicrotasks();
        final ProviderSubscription<bool> sub = c.listen(
          bookingLinksVisibleProvider,
          (_, _) {},
        );
        final ProviderSubscription<AsyncValue<BookingLinks>> linksSub = c
            .listen(bookingLinksProvider, (_, _) {});
        async.elapse(Duration.zero);
        expect(c.read(bookingLinksVisibleProvider), isFalse);
        expect(c.read(bookingLinksProvider).value, BookingLinks.hidden);
        sub.close();
        linksSub.close();
        verify(() => repo.getMine()).called(2);
      });
    });

    test('a role change during the in-flight fetch: the stale response is '
        'hidden and not pinned', () {
      fakeAsync((FakeAsync async) {
        final Completer<BookingLinks> pending = Completer<BookingLinks>();
        when(() => repo.getMine()).thenAnswer((_) => pending.future);
        final ProviderContainer c = container();
        signIn(c, async);
        final ProviderSubscription<AsyncValue<BookingLinks>> direct = c.listen(
          u1Links,
          (_, _) {},
        );
        async.elapse(Duration.zero);

        final Authenticated current =
            c.read(authProvider).requireValue as Authenticated;
        c.read(authProvider.notifier).state = AsyncData<AuthSession>(
          AuthSession.authenticated(
            user: current.user.copyWith(role: UserRole.salonMaster),
            accessToken: current.accessToken,
          ),
        );
        async.flushMicrotasks();
        pending.complete(visibleLinks);
        async.flushMicrotasks();

        expect(c.read(u1Links).value, BookingLinks.hidden);
        direct.close();
        async.elapse(Duration.zero);
        expect(c.exists(u1Links), isFalse);
      });
    });
  });

  // Phase 414 — role scoping inside bookingLinksProvider (user decision
  // 2026-10-20): independent master → MASTER only; owner/admin → SALON only;
  // salon master → nothing, whatever the server sends.
  group('role scoping (phase 414)', () {
    const BookingLink salon = BookingLink(
      kind: BookingLinkKind.salon,
      slug: 'lumiere',
      url: 'https://beautica.app/book/s/lumiere',
      displayName: 'Lumière',
      salonId: 'salon-1',
      bookable: true,
    );
    const BookingLinks both = BookingLinks(
      shareEnabled: true,
      links: <BookingLink>[_master, salon],
    );

    final Map<UserRole, List<BookingLink>> expected =
        <UserRole, List<BookingLink>>{
          UserRole.independentMaster: <BookingLink>[_master],
          UserRole.salonOwner: <BookingLink>[salon],
          UserRole.salonAdmin: <BookingLink>[salon],
          UserRole.salonMaster: <BookingLink>[],
        };
    expected.forEach((UserRole role, List<BookingLink> links) {
      test('${role.name} → ${links.map((l) => l.kind.name).toList()}; '
          'visible=${links.isNotEmpty}', () async {
        when(() => repo.getMine()).thenAnswer((_) async => both);
        final ProviderContainer c = container(auth: () => FixedRoleAuth(role));

        expect(await settledVisibility(c), links.isNotEmpty);
        expect(c.read(bookingLinksProvider).value?.links, links);
      });
    });
  });
}
