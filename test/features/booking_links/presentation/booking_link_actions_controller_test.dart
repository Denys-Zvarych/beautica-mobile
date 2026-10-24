// Phase 415 — BookingLinkActions (regenerate) + the BookingLinksPatch overlay.
//
// Real bookingLinksProvider / bookingLinksForAccountProvider over a mocked
// repository. Layer: Unit (ProviderContainer).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking_links/data/booking_links_repository.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_actions_controller.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_links_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fakes/fake_notification_repository.dart'
    show FixedRoleAuth;
import '../../../helpers/test_container.dart';

class _MockRepo extends Mock implements BookingLinksRepository {}

const String _salonAId = '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f';
const String _salonBId = '6c2f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f';

const BookingLink _salonA = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'lumiere',
  url: 'https://beautica.app/book/s/lumiere',
  displayName: 'Lumière',
  salonId: _salonAId,
  bookable: true,
);

const BookingLink _salonB = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'loft',
  url: 'https://beautica.app/book/s/loft',
  displayName: 'Loft',
  salonId: _salonBId,
  bookable: true,
);

BookingLink _next(BookingLink l, String slug) =>
    l.copyWith(slug: slug, url: 'https://beautica.app/book/s/$slug');

void main() {
  late _MockRepo repo;

  setUpAll(() => registerFallbackValue(_salonA));

  setUp(() {
    repo = _MockRepo();
    when(() => repo.getMine()).thenAnswer(
      // A NEW object per load, as the real mapper builds — the patch is
      // tied to the loaded value by identity.
      (_) async => BookingLinks(
        shareEnabled: true,
        links: List<BookingLink>.of(const <BookingLink>[_salonA, _salonB]),
      ),
    );
  });

  Future<ProviderContainer> loaded() async {
    final ProviderContainer c = makeTestContainer(
      overrides: <Object>[
        authProvider.overrideWith(() => FixedRoleAuth(UserRole.salonOwner)),
        bookingLinksRepositoryProvider.overrideWithValue(repo),
      ],
    );
    final ProviderSubscription<AsyncValue<BookingLinks>> sub = c.listen(
      bookingLinksProvider,
      (_, _) {},
    );
    addTearDown(sub.close);
    await c.read(bookingLinksProvider.future);
    return c;
  }

  List<String?> slugs(ProviderContainer c) =>
      c.read(bookingLinksProvider).value?.links.map((l) => l.slug).toList() ??
      <String?>[];

  test('done → only the target card is replaced, no refetch', () async {
    final ProviderContainer c = await loaded();
    when(() => repo.regenerate(any())).thenAnswer(
      (_) async => BookingLinkMutationOutcome.done(_next(_salonA, 'lumiere-2')),
    );

    final BookingLinkMutationOutcome? out = await c
        .read(bookingLinkActionsProvider.notifier)
        .regenerate(_salonA);
    await c.read(bookingLinksProvider.future);

    expect(out, isA<BookingLinkMutationDone>());
    expect(slugs(c), <String?>['lumiere-2', 'loft']);
    verify(() => repo.getMine()).called(1);
    expect(c.read(bookingLinkActionsProvider), isNull);
  });

  test('regenerating the replaced card again follows the chain', () async {
    final ProviderContainer c = await loaded();
    when(() => repo.regenerate(any())).thenAnswer((inv) async {
      final BookingLink l = inv.positionalArguments.single as BookingLink;
      return BookingLinkMutationOutcome.done(_next(l, '${l.slug}-n'));
    });
    final BookingLinkActions actions = c.read(
      bookingLinkActionsProvider.notifier,
    );

    await actions.regenerate(_salonA);
    await c.read(bookingLinksProvider.future);
    final BookingLink shown = c
        .read(bookingLinksProvider)
        .requireValue
        .links[0];
    await actions.regenerate(shown);
    await c.read(bookingLinksProvider.future);

    expect(slugs(c), <String?>['lumiere-n-n', 'loft']);
  });

  test('a fresh load drops the patch (server truth wins)', () async {
    final ProviderContainer c = await loaded();
    when(() => repo.regenerate(any())).thenAnswer(
      (_) async => BookingLinkMutationOutcome.done(_next(_salonA, 'lumiere-2')),
    );
    await c.read(bookingLinkActionsProvider.notifier).regenerate(_salonA);
    when(() => repo.getMine()).thenAnswer(
      // A NEW object per load, as the real mapper builds — the patch is
      // tied to the loaded value by identity.
      (_) async => BookingLinks(
        shareEnabled: true,
        links: List<BookingLink>.of(const <BookingLink>[_salonA, _salonB]),
      ),
    );

    c.invalidate(bookingLinksForAccountProvider);
    await c.read(bookingLinksProvider.future);

    expect(slugs(c), <String?>['lumiere', 'loft']);
  });

  for (final BookingLinkMutationOutcome outcome in <BookingLinkMutationOutcome>[
    const BookingLinkMutationOutcome.stale(),
    const BookingLinkMutationOutcome.unavailable(),
  ]) {
    test('${outcome.runtimeType} → the account cache refetches', () async {
      final ProviderContainer c = await loaded();
      when(() => repo.regenerate(any())).thenAnswer((_) async => outcome);

      final BookingLinkMutationOutcome? out = await c
          .read(bookingLinkActionsProvider.notifier)
          .regenerate(_salonA);
      await c.read(bookingLinksProvider.future);

      expect(out, outcome);
      verify(() => repo.getMine()).called(2);
      expect(slugs(c), <String?>['lumiere', 'loft']);
    });
  }

  test('rateLimited → nothing refetched, nothing replaced', () async {
    final ProviderContainer c = await loaded();
    when(
      () => repo.regenerate(any()),
    ).thenAnswer((_) async => const BookingLinkMutationOutcome.rateLimited());

    await c.read(bookingLinkActionsProvider.notifier).regenerate(_salonA);
    await c.read(bookingLinksProvider.future);

    verify(() => repo.getMine()).called(1);
    expect(slugs(c), <String?>['lumiere', 'loft']);
  });

  test('user switched mid-flight → result dropped, no patch written', () async {
    final ProviderContainer c = await loaded();
    final Completer<BookingLinkMutationOutcome> pending =
        Completer<BookingLinkMutationOutcome>();
    when(() => repo.regenerate(any())).thenAnswer((_) => pending.future);

    final Future<BookingLinkMutationOutcome?> call = c
        .read(bookingLinkActionsProvider.notifier)
        .regenerate(_salonA);
    (c.read(authProvider.notifier) as FixedRoleAuth).switchUser('u2');
    pending.complete(
      BookingLinkMutationOutcome.done(_next(_salonA, 'lumiere-2')),
    );

    expect(await call, isNull);
    expect(c.read(bookingLinksPatchesProvider), isNull);
    expect(c.read(bookingLinkActionsProvider), isNull);
  });

  test(
    'in flight: state names the card and a second call is ignored',
    () async {
      final ProviderContainer c = await loaded();
      final Completer<BookingLinkMutationOutcome> pending =
          Completer<BookingLinkMutationOutcome>();
      when(() => repo.regenerate(any())).thenAnswer((_) => pending.future);
      final BookingLinkActions actions = c.read(
        bookingLinkActionsProvider.notifier,
      );

      final Future<BookingLinkMutationOutcome?> first = actions.regenerate(
        _salonA,
      );
      expect(c.read(bookingLinkActionsProvider), 'lumiere');
      expect(await actions.regenerate(_salonB), isNull);
      verify(() => repo.regenerate(_salonA)).called(1);
      verifyNever(() => repo.regenerate(_salonB));

      pending.complete(const BookingLinkMutationOutcome.rateLimited());
      await first;
      expect(c.read(bookingLinkActionsProvider), isNull);
    },
  );

  test('a thrown Failure propagates and clears the in-flight state', () async {
    final ProviderContainer c = await loaded();
    when(
      () => repo.regenerate(any()),
    ).thenAnswer((_) async => throw const ServerFailure(statusCode: 403));

    await expectLater(
      c.read(bookingLinkActionsProvider.notifier).regenerate(_salonA),
      throwsA(isA<ServerFailure>()),
    );
    expect(c.read(bookingLinkActionsProvider), isNull);
  });
}
