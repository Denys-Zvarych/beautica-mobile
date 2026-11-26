// M542 — category slug → remote icon URL (SVC-04 / SVC-58).
//
// Derived from the existing [approvedCategoriesProvider] — no new network
// call. On data it asks [CategoryIconStore] to prefetch every URL into the
// dedicated `categoryIcons` disk cache; [CategoryIconGlyph] then swaps the
// bundled icon for the remote one once its bytes are in the store.
//
// Gated on a signed-in session: `GET /service-categories/approved` is
// authenticated-only, and this provider is listened to from the app root
// (`BeauticaApp`), which is alive before login. Signed out → empty map and
// no fetch. Watching the narrowed user id (not the bare auth provider) keeps a
// token refresh from re-running it.
//
// The prefetch waits for [categoryIconFrameGateProvider] (the end of the
// current frame — so the screen just opened after login paints first) and
// then runs through [CategoryIconStore.prefetchAll], which keeps at most
// `kMaxConcurrentCategoryIconFetches` (2) downloads in flight.

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/icons/category_icon_store.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../data/service_repository.dart';
import '../domain/service_category_option.dart';

part 'category_icon_urls_provider.g.dart';

/// Completes once the current frame has rendered — the prefetch's start gate.
/// Tests override it with an immediate (or manually completed) future.
@Riverpod(keepAlive: true)
Future<void> Function() categoryIconFrameGate(Ref ref) =>
    () => SchedulerBinding.instance.endOfFrame;

/// Uppercase wire slug → `iconUrl` for every approved category that has one.
@Riverpod(keepAlive: true)
Map<String, String> categoryIconUrls(Ref ref) {
  final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
  if (userId == null) return const <String, String>{};

  final List<ServiceCategoryOption> categories =
      ref.watch(approvedCategoriesProvider).value ??
      const <ServiceCategoryOption>[];
  final Map<String, String> urls = <String, String>{
    for (final ServiceCategoryOption c in categories)
      if ((normaliseCategoryIconKey(c.name), c.iconUrl) case (
        final String key?,
        final String url?,
      ))
        key: url,
  };

  if (urls.isNotEmpty) {
    final Future<void> Function() afterFrame = ref.read(
      categoryIconFrameGateProvider,
    );
    final CategoryIconStore store = ref.read(
      categoryIconStoreProvider.notifier,
    );
    unawaited(() async {
      await afterFrame();
      if (!ref.mounted) return;
      await store.prefetchAll(urls);
    }());
  }
  return urls;
}
