// Shared fake [SalonRepository] for widget tests — promoted (REUSE-FIRST,
// mobile-qa finding, Phase 21.2 audit) out of two near-identical private
// `_FakeSalonRepository` classes that had drifted apart:
//   - `salon_management_profile_screen_test.dart` needed a real
//     [updateSalon] that applies the partial request onto the held [Salon]
//     (so a save round-trip is observable) plus [updateError] injection.
//   - `salon_settings_screen_test.dart` only needed [deleteSalon] with
//     [deleteError] injection; its [updateSalon] was an `UnimplementedError`
//     guard that this screen never exercises.
//
// This single fake supports BOTH: [updateSalon] always applies the diff (the
// settings-screen tests never call it, so the guard's absence changes no
// assertion), and both [updateError] / [deleteError] are available for
// whichever screen's tests need to inject a failure.
//
// [salon] is a required constructor param (no hidden default) — each caller
// passes its own fixture explicitly so assertions that compare against a
// local `_stubSalon` stay obviously correct.

import 'package:beautica_api/beautica_api.dart' show UpdateSalonRequest;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/bookable_master_assignment.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_portfolio_photo.dart';
import 'package:beautica_mobile/features/salon/domain/salon_review.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';

/// In-memory [SalonRepository] fake for widget tests.
///
/// `updateSalon` APPLIES the partial request onto the held [Salon] (mirroring
/// what the backend does) so a save round-trip is observable by re-reading
/// the screen, and records every [UpdateSalonRequest] sent so the dirty-field
/// diff can be asserted. `deleteSalon` just counts calls unless [deleteError]
/// is set.
class FakeSalonRepository implements SalonRepository {
  FakeSalonRepository({
    required Salon salon,
    this.masters = const <SalonMasterSummary>[],
  }) : _salon = salon;

  Salon _salon;
  final List<SalonMasterSummary> masters;

  final List<UpdateSalonRequest> updateRequests = <UpdateSalonRequest>[];
  int deleteCalls = 0;
  Failure? updateError;
  Failure? deleteError;

  @override
  Future<void> create({required SalonCreateDto dto}) async {}

  @override
  Future<List<Salon>> getMySalons() async => <Salon>[_salon];

  @override
  Future<Salon> getSalonById(String salonId) async => _salon;

  @override
  Future<List<SalonMasterSummary>> getSalonMasters(String salonId) async =>
      masters;

  @override
  Future<List<SalonServiceCategoryEntry>> getSalonServiceCatalog(
    String salonId,
  ) async => const <SalonServiceCategoryEntry>[];

  @override
  Future<SalonReviewSummary> getSalonReviewSummary(String salonId) async =>
      const SalonReviewSummary();

  @override
  Future<List<SalonReviewItem>> getSalonReviews({
    required String salonId,
    required SalonReviewSort sort,
    int page = 0,
    int size = kSalonReviewsPageSize,
  }) async => const <SalonReviewItem>[];

  @override
  Future<List<SalonPortfolioPhoto>> getSalonPortfolio(String salonId) async =>
      const <SalonPortfolioPhoto>[];

  @override
  Future<List<BookableMasterAssignment>> getBookableMasters({
    required String salonId,
    required String serviceDefId,
  }) async => const <BookableMasterAssignment>[];

  @override
  Future<Salon> updateSalon(String salonId, UpdateSalonRequest request) async {
    updateRequests.add(request);
    if (updateError != null) throw updateError!;
    _salon = _salon.copyWith(
      name: request.name ?? _salon.name,
      description: request.description ?? _salon.description,
      phone: request.phone ?? _salon.phone,
      instagramUrl: request.instagramUrl ?? _salon.instagramUrl,
    );
    return _salon;
  }

  @override
  Future<void> deleteSalon(String salonId) async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
  }
}
