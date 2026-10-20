// Phase 413 — bookingLinksProvider + bookingLinksVisibleProvider (D3 / D4).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
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
  Future<bool> settledVisibility(ProviderContainer c) async {
    final ProviderSubscription<bool> sub = c.listen(
      bookingLinksVisibleProvider,
      (_, _) {},
    );
    addTearDown(sub.close);
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

    test('CLIENT 403 (repository error) → not visible, no throw', () async {
      when(
        () => repo.getMine(),
      ).thenAnswer((_) async => throw const ServerFailure(statusCode: 403));
      final ProviderContainer c = container(
        auth: () => FixedRoleAuth(UserRole.client),
      );

      expect(await settledVisibility(c), isFalse);
      expect(c.read(bookingLinksProvider).hasError, isTrue);
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
        (_, AsyncValue<BookingLinks> next) => states.add(next),
      );
      addTearDown(linksSub.close);
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
}
