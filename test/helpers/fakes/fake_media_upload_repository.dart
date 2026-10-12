// Shared [MediaUploadRepository] fake (phase 404). Serves the independent
// master's portfolio READ from [masterPortfolio] and records every read in
// [masterPortfolioReads] — the context-isolation tests assert it stays empty
// on owner / admin / salon-master surfaces (locked rule: no personal
// portfolio there). Every write throws: no 404 surface writes.

import 'dart:async';
import 'dart:io';

import 'package:beautica_mobile/core/media/portfolio/portfolio_notifier.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/upload/media_upload_repository.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';

class FakeMediaUploadRepository implements MediaUploadRepository {
  FakeMediaUploadRepository({
    this.masterPortfolio = const <PortfolioPhoto>[],
    this.masterPortfolioError,
  });

  /// What [getMasterPortfolio] returns.
  List<PortfolioPhoto> masterPortfolio;

  /// When non-null, [getMasterPortfolio] throws it instead.
  Object? masterPortfolioError;

  /// Every master id [getMasterPortfolio] was called with, in order.
  final List<String> masterPortfolioReads = <String>[];

  @override
  Future<List<PortfolioPhoto>> getMasterPortfolio(String masterId) async {
    masterPortfolioReads.add(masterId);
    final Object? error = masterPortfolioError;
    if (error != null) throw error;
    return masterPortfolio;
  }

  @override
  UploadTask<PortfolioPhoto> uploadPortfolioPhoto(
    PortfolioOwner owner,
    File file,
  ) => throw UnimplementedError();

  @override
  Future<void> deletePortfolioPhoto(PortfolioOwner owner, String mediaId) =>
      throw UnimplementedError();

  @override
  UploadTask<String> uploadAvatar(File file) => throw UnimplementedError();

  @override
  Future<void> deleteAvatar() => throw UnimplementedError();

  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) => throw UnimplementedError();

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) =>
      throw UnimplementedError();
}

/// A [PortfolioNotifier] that settles to [photos] with NO keep-alive timer.
///
/// Use as a family-wide override — `portfolioProvider.overrideWith(
/// FixedPortfolioNotifier.new)` — in tests whose `ProviderContainer`
/// outlives the widget tree (`UncontrolledProviderScope` + router
/// containers): the real notifier's 5-minute TTL timer would otherwise still
/// be pending at the test-invariant check.
class FixedPortfolioNotifier extends PortfolioNotifier {
  FixedPortfolioNotifier([this.photos = const <PortfolioPhoto>[]]);

  final List<PortfolioPhoto> photos;

  @override
  Future<List<PortfolioPhoto>> build(PortfolioOwner owner) async => photos;
}

/// A [PortfolioNotifier] that stays LOADING forever (no keep-alive timer) —
/// the D2 loading state, which renders the placeholder tiles. Pins the
/// screen goldens to the pre-404 placeholder render.
class LoadingPortfolioNotifier extends PortfolioNotifier {
  @override
  Future<List<PortfolioPhoto>> build(PortfolioOwner owner) =>
      Completer<List<PortfolioPhoto>>().future;
}
