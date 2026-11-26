// M542 — categoryIconUrlsProvider + CategoryIconStore.prefetch: the slug → URL
// map is derived from approvedCategoriesProvider (overridden directly), each
// URL is prefetched once, a disallowed host is never fetched, oversize bytes
// are refused, and a signed-out session yields an empty map with no fetch.
// Audit-fix cycle 1: prefetch waits for the frame gate and keeps ≤2 downloads
// in flight; oversize (checked via file.length() before readAsBytes, or
// aborted mid-download) and forbidden-markup bytes are refused, evicted from
// the disk cache and never re-fetched.
// Audit-fix cycle 2: rebuilds during an in-flight batch join the running batch
// instead of starting a parallel one — total concurrency stays ≤2.
// Audit-fix cycle 3: a slug's older URL finishing last never overwrites its
// newer icon; a call made during the batch's synchronous start joins it.

import 'dart:async';

import 'dart:typed_data';

import 'package:beautica_mobile/core/icons/category_icon_store.dart';
import 'package:beautica_mobile/core/media/beautica_image.dart'
    show MediaResponseTooLargeException;
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/category_icon_urls_provider.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _nailsUrl =
    'https://media.test/catalog/category-icons/NAILS/0123456789abcdef.svg';
const String _browsUrl =
    'https://media.test/catalog/category-icons/BROWS/fedcba9876543210.svg';
const String _evilUrl = 'https://evil.example/x.svg';

final Uint8List _svg = Uint8List.fromList(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"/>'.codeUnits,
);

/// A file that reports [reportedLength] and records whether its bytes were
/// read — proves the size check happens BEFORE `readAsBytes`.
class _LengthOnlyFile implements File {
  _LengthOnlyFile(this.reportedLength);

  final int reportedLength;
  bool bytesRead = false;

  @override
  Future<int> length() async => reportedLength;

  @override
  Future<Uint8List> readAsBytes() async {
    bytesRead = true;
    return Uint8List(reportedLength);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeIconCache implements BaseCacheManager {
  _FakeIconCache(this.bytesFor);

  final Uint8List Function(String url) bytesFor;
  final List<String> requested = <String>[];
  final List<String> removed = <String>[];

  /// Overrides the default in-memory file for a URL.
  Future<File> Function(String url)? fileFor;

  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    requested.add(url);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final Future<File> Function(String url)? custom = fileFor;
      if (custom != null) return await custom(url);
      return MemoryFileSystem().file('/${url.hashCode}.svg')
        ..writeAsBytesSync(bytesFor(url));
    } finally {
      inFlight--;
    }
  }

  @override
  Future<void> removeFile(String key) async => removed.add(key);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FixedAuth extends AuthNotifier {
  _FixedAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

const AuthSession _signedIn = AuthSession.authenticated(
  user: User(id: 'u-1', role: UserRole.client),
  accessToken: 'token',
);

({ProviderContainer container, _FakeIconCache cache, List<int> fetches})
_harness({
  AuthSession session = _signedIn,
  required List<ServiceCategoryOption> categories,
  Uint8List Function(String url)? bytesFor,
  Future<void> Function()? frameGate,
}) {
  final _FakeIconCache cache = _FakeIconCache(bytesFor ?? (_) => _svg);
  final List<int> fetches = <int>[0];
  final ProviderContainer container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(() => _FixedAuth(session)),
      approvedCategoriesProvider.overrideWith((ref) async {
        fetches[0]++;
        return categories;
      }),
      categoryIconCacheManagerProvider.overrideWithValue(cache),
      categoryIconFrameGateProvider.overrideWithValue(frameGate ?? () async {}),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, cache: cache, fetches: fetches);
}

Future<void> _settle(ProviderContainer c) async {
  c.listen(categoryIconUrlsProvider, (_, _) {});
  await c.read(authProvider.future);
  await c.read(approvedCategoriesProvider.future);
  // Let the fire-and-forget prefetches land.
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() => MediaConfig.debugAllowedHosts = <String>{'media.test'});
  tearDown(() => MediaConfig.debugAllowedHosts = null);

  test(
    'map is built from the approved list (slug upper-cased, categories '
    'without iconUrl skipped) and each URL is prefetched exactly once',
    () async {
      final h = _harness(
        categories: const <ServiceCategoryOption>[
          ServiceCategoryOption(
            name: 'nails',
            displayName: 'Нігті',
            iconUrl: _nailsUrl,
          ),
          ServiceCategoryOption(
            name: 'BROWS',
            displayName: 'Брови',
            iconUrl: _browsUrl,
          ),
          ServiceCategoryOption(name: 'MAKEUP', displayName: 'Макіяж'),
        ],
      );
      await _settle(h.container);

      expect(h.container.read(categoryIconUrlsProvider), <String, String>{
        'NAILS': _nailsUrl,
        'BROWS': _browsUrl,
      });
      expect(
        h.cache.requested,
        unorderedEquals(<String>[_nailsUrl, _browsUrl]),
      );
      final Map<String, CategoryIconBytes> store = h.container.read(
        categoryIconStoreProvider,
      );
      expect(store.keys, unorderedEquals(<String>['NAILS', 'BROWS']));
      expect(store['NAILS']?.url, _nailsUrl);
      expect(store['NAILS']?.bytes, _svg);

      // A rebuild with the same list must not re-download.
      h.container.invalidate(approvedCategoriesProvider);
      await _settle(h.container);
      expect(h.cache.requested, hasLength(2));
    },
  );

  test('signed out → empty map and NO categories fetch', () async {
    final h = _harness(
      session: const AuthSession.unauthenticated(),
      categories: const <ServiceCategoryOption>[
        ServiceCategoryOption(
          name: 'NAILS',
          displayName: 'Нігті',
          iconUrl: _nailsUrl,
        ),
      ],
    );
    h.container.listen(categoryIconUrlsProvider, (_, _) {});
    await h.container.read(authProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(h.container.read(categoryIconUrlsProvider), isEmpty);
    expect(h.fetches[0], 0);
    expect(h.cache.requested, isEmpty);
  });

  test('non-allow-listed host is never fetched and stays on the bundled '
      'fallback', () async {
    final h = _harness(
      categories: const <ServiceCategoryOption>[
        ServiceCategoryOption(
          name: 'NAILS',
          displayName: 'Нігті',
          iconUrl: _evilUrl,
        ),
      ],
    );
    await _settle(h.container);

    expect(h.cache.requested, isEmpty);
    expect(h.container.read(categoryIconStoreProvider), isEmpty);
  });

  test('oversize bytes (> 16 KiB) are refused', () async {
    final h = _harness(
      categories: const <ServiceCategoryOption>[
        ServiceCategoryOption(
          name: 'NAILS',
          displayName: 'Нігті',
          iconUrl: _nailsUrl,
        ),
      ],
      bytesFor: (_) => Uint8List(kMaxCategoryIconBytes + 1),
    );
    await _settle(h.container);

    expect(h.cache.requested, <String>[_nailsUrl]);
    expect(h.container.read(categoryIconStoreProvider), isEmpty);
    // Evicted from disk and refused for the session.
    expect(h.cache.removed, <String>[_nailsUrl]);
    h.container.invalidate(approvedCategoriesProvider);
    await _settle(h.container);
    expect(h.cache.requested, <String>[_nailsUrl]);
  });

  test('discard() drops the key and the URL is not re-fetched', () async {
    final h = _harness(
      categories: const <ServiceCategoryOption>[
        ServiceCategoryOption(
          name: 'NAILS',
          displayName: 'Нігті',
          iconUrl: _nailsUrl,
        ),
      ],
    );
    await _settle(h.container);
    h.container.read(categoryIconStoreProvider.notifier).discard('nails');
    expect(h.container.read(categoryIconStoreProvider), isEmpty);

    h.container.invalidate(approvedCategoriesProvider);
    await _settle(h.container);
    expect(h.cache.requested, <String>[_nailsUrl]);
    expect(h.container.read(categoryIconStoreProvider), isEmpty);
  });

  const ServiceCategoryOption nails = ServiceCategoryOption(
    name: 'NAILS',
    displayName: 'Нігті',
    iconUrl: _nailsUrl,
  );

  test(
    'oversize file is refused from file.length() — bytes never read',
    () async {
      final h = _harness(categories: const <ServiceCategoryOption>[nails]);
      final _LengthOnlyFile big = _LengthOnlyFile(kMaxCategoryIconBytes + 1);
      h.cache.fileFor = (_) async => big;
      await _settle(h.container);

      expect(big.bytesRead, isFalse);
      expect(h.container.read(categoryIconStoreProvider), isEmpty);
      expect(h.cache.removed, <String>[_nailsUrl]);
    },
  );

  test(
    'a download aborted over the cap is refused, evicted, not re-fetched',
    () async {
      final h = _harness(categories: const <ServiceCategoryOption>[nails]);
      h.cache.fileFor = (_) async =>
          throw const MediaResponseTooLargeException(kMaxCategoryIconBytes);
      await _settle(h.container);

      expect(h.container.read(categoryIconStoreProvider), isEmpty);
      expect(h.cache.removed, <String>[_nailsUrl]);
      h.container.invalidate(approvedCategoriesProvider);
      await _settle(h.container);
      expect(h.cache.requested, <String>[_nailsUrl]);
    },
  );

  for (final String markup in <String>[
    '<IMAGE href="https://x.test/a.png"/>',
    '<!doctype svg>',
    '<ScRiPt>alert(1)</script>',
  ]) {
    test('bytes containing forbidden markup are refused: $markup', () async {
      final h = _harness(
        categories: const <ServiceCategoryOption>[nails],
        bytesFor: (_) => Uint8List.fromList(
          '<svg xmlns="http://www.w3.org/2000/svg">$markup</svg>'.codeUnits,
        ),
      );
      await _settle(h.container);

      expect(h.container.read(categoryIconStoreProvider), isEmpty);
      expect(h.cache.removed, <String>[_nailsUrl]);
    });
  }

  test('nothing is fetched until the frame gate opens', () async {
    final Completer<void> frame = Completer<void>();
    final h = _harness(
      categories: const <ServiceCategoryOption>[nails],
      frameGate: () => frame.future,
    );
    await _settle(h.container);
    expect(h.container.read(categoryIconUrlsProvider), hasLength(1));
    expect(h.cache.requested, isEmpty);

    frame.complete();
    await _settle(h.container);
    expect(h.cache.requested, <String>[_nailsUrl]);
    expect(h.container.read(categoryIconStoreProvider).keys, <String>['NAILS']);
  });

  test('the first prefetch keeps at most 2 downloads in flight', () async {
    final List<ServiceCategoryOption> many = <ServiceCategoryOption>[
      for (int i = 0; i < 22; i++)
        ServiceCategoryOption(
          name: 'CAT_$i',
          displayName: 'c$i',
          iconUrl: 'https://media.test/catalog/category-icons/CAT_$i/$i.svg',
        ),
    ];
    final h = _harness(categories: many);
    h.cache.fileFor = (String url) async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return MemoryFileSystem().file('/${url.hashCode}.svg')
        ..writeAsBytesSync(_svg);
    };
    h.container.listen(categoryIconUrlsProvider, (_, _) {});
    await h.container.read(authProvider.future);
    await h.container.read(approvedCategoriesProvider.future);
    for (int i = 0; i < 100 && h.cache.requested.length < 22; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(h.cache.requested, hasLength(22));
    expect(h.cache.maxInFlight, kMaxConcurrentCategoryIconFetches);
    expect(kMaxConcurrentCategoryIconFetches, 2);
    expect(h.container.read(categoryIconStoreProvider), hasLength(22));
  });

  test(
    'two rebuilds during an in-flight batch join it: never more than 2 '
    'concurrent fetches, every URL (incl. one added mid-batch) fetched once',
    () async {
      String urlOf(int i) =>
          'https://media.test/catalog/category-icons/CAT_$i/$i.svg';
      final List<ServiceCategoryOption> cats = <ServiceCategoryOption>[
        for (int i = 0; i < 10; i++)
          ServiceCategoryOption(
            name: 'CAT_$i',
            displayName: 'c$i',
            iconUrl: urlOf(i),
          ),
      ];
      final h = _harness(categories: cats);
      h.cache.fileFor = (String url) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return MemoryFileSystem().file('/${url.hashCode}.svg')
          ..writeAsBytesSync(_svg);
      };
      h.container.listen(categoryIconUrlsProvider, (_, _) {});
      await h.container.read(authProvider.future);
      await h.container.read(approvedCategoriesProvider.future);
      for (int i = 0; i < 50 && h.cache.requested.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(h.cache.inFlight, greaterThan(0), reason: 'batch must be live');

      // Rebuild #1 — same list, while the first batch is downloading.
      h.container.invalidate(approvedCategoriesProvider);
      await h.container.read(approvedCategoriesProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(h.cache.requested.length, lessThan(10), reason: 'still in flight');

      // Rebuild #2 — adds a URL mid-batch.
      cats.add(
        ServiceCategoryOption(
          name: 'CAT_10',
          displayName: 'c10',
          iconUrl: urlOf(10),
        ),
      );
      h.container.invalidate(approvedCategoriesProvider);
      await h.container.read(approvedCategoriesProvider.future);

      for (int i = 0; i < 100 && h.cache.requested.length < 11; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(h.cache.maxInFlight, lessThanOrEqualTo(2));
      expect(
        h.cache.requested,
        unorderedEquals(<String>[for (int i = 0; i <= 10; i++) urlOf(i)]),
      );
      expect(h.container.read(categoryIconStoreProvider), hasLength(11));
    },
  );

  // Pins the real guarantee: a URL added via prefetchAll during an active
  // batch is fetched exactly once — whether it joins the running batch (its
  // workers take it) or arrives after the batch ended (a new batch starts).
  // The late call is swept one raw microtask at a time (depth 0..60) from the
  // moment the first download's file is handed back; each depth gets a fresh
  // container. Falsified by "join without queueing" (prefetchAll returning the
  // active future before `_pending.addAll`) and by a batch that ends after its
  // last worker stops (a URL queued in that gap is stranded).
  test('a URL added via prefetchAll during an active batch is fetched once '
      '(every injection depth)', () async {
    const String lateUrl =
        'https://media.test/catalog/category-icons/LATE/1111111111111111.svg';
    final List<int> joinedDepths = <int>[];
    for (int depth = 0; depth <= 60; depth++) {
      final h = _harness(categories: const <ServiceCategoryOption>[]);
      final CategoryIconStore store = h.container.read(
        categoryIconStoreProvider.notifier,
      );
      final Completer<Future<void>> lateCall = Completer<Future<void>>();
      void hop(int left) {
        if (left > 0) {
          scheduleMicrotask(() => hop(left - 1));
          return;
        }
        lateCall.complete(store.prefetchAll(<String, String>{'LATE': lateUrl}));
      }

      h.cache.fileFor = (String url) async {
        if (url == _nailsUrl && !lateCall.isCompleted) hop(depth);
        return MemoryFileSystem().file('/${url.hashCode}.svg')
          ..writeAsBytesSync(_svg);
      };

      final Future<void> first = store.prefetchAll(<String, String>{
        'NAILS': _nailsUrl,
      });
      await first;
      final Future<void> lateFuture = await lateCall.future;
      if (identical(lateFuture, first)) joinedDepths.add(depth);
      await lateFuture;
      for (int i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        h.cache.requested,
        <String>[_nailsUrl, lateUrl],
        reason: 'depth $depth: the late URL must be fetched exactly once',
      );
      expect(
        h.container.read(categoryIconStoreProvider).keys,
        unorderedEquals(<String>['NAILS', 'LATE']),
        reason: 'depth $depth',
      );
    }
    // Non-vacuous: some depths must land INSIDE the running batch, and the
    // sweep must also reach past its end (a later depth starts a new one).
    expect(joinedDepths, isNotEmpty);
    expect(joinedDepths.last, lessThan(60));
  });

  test('a slug whose URL changed mid-flight keeps the NEWER icon even when '
      'the older download finishes last', () async {
    const String oldUrl =
        'https://media.test/catalog/category-icons/NAILS/aaaaaaaaaaaaaaaa.svg';
    const String newUrl =
        'https://media.test/catalog/category-icons/NAILS/bbbbbbbbbbbbbbbb.svg';
    final Uint8List oldSvg = Uint8List.fromList('<svg id="old"/>'.codeUnits);
    final Uint8List newSvg = Uint8List.fromList('<svg id="new"/>'.codeUnits);
    final Completer<void> releaseOld = Completer<void>();
    final h = _harness(categories: const <ServiceCategoryOption>[]);
    h.cache.fileFor = (String url) async {
      if (url == oldUrl) await releaseOld.future;
      return MemoryFileSystem().file('/${url.hashCode}.svg')
        ..writeAsBytesSync(url == oldUrl ? oldSvg : newSvg);
    };
    final CategoryIconStore store = h.container.read(
      categoryIconStoreProvider.notifier,
    );

    final Future<void> slow = store.prefetch('NAILS', oldUrl);
    await store.prefetch('NAILS', newUrl);
    expect(h.container.read(categoryIconStoreProvider)['NAILS']?.url, newUrl);

    releaseOld.complete();
    await slow;

    expect(h.cache.requested, <String>[oldUrl, newUrl]);
    final CategoryIconBytes? held = h.container.read(
      categoryIconStoreProvider,
    )['NAILS'];
    expect(held?.url, newUrl, reason: 'the older download must not win');
    expect(held?.bytes, newSvg);
  });

  test('a prefetchAll made during the batch\'s synchronous start joins that '
      'batch (no second batch, ≤2 in flight)', () async {
    const String nestedUrl =
        'https://media.test/catalog/category-icons/LATE/1111111111111111.svg';
    final h = _harness(categories: const <ServiceCategoryOption>[]);
    final CategoryIconStore store = h.container.read(
      categoryIconStoreProvider.notifier,
    );
    Future<void>? nested;
    Future<File> slowFile(String url) async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return MemoryFileSystem().file('/${url.hashCode}.svg')
        ..writeAsBytesSync(_svg);
    }

    // getSingleFile runs synchronously up to its first await — i.e. inside
    // the first worker's synchronous start, before prefetchAll has returned.
    h.cache.fileFor = (String url) {
      if (url == _nailsUrl) {
        nested ??= store.prefetchAll(<String, String>{'LATE': nestedUrl});
      }
      return slowFile(url);
    };

    final Future<void> first = store.prefetchAll(<String, String>{
      'NAILS': _nailsUrl,
    });
    expect(nested, isNotNull, reason: 'the nested call ran synchronously');
    expect(identical(nested, first), isTrue, reason: 'it joined the batch');
    await first;

    expect(h.cache.requested, <String>[_nailsUrl, nestedUrl]);
    expect(h.cache.maxInFlight, lessThanOrEqualTo(2));
    expect(
      h.container.read(categoryIconStoreProvider).keys,
      unorderedEquals(<String>['NAILS', 'LATE']),
    );
  });
}
