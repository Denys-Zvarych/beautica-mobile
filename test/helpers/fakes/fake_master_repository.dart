// Fake [MasterRepository] for widget tests.
//
// Returns a settled [Master] from [getMyProfile] so screens that land on the
// profile (e.g. via the authenticated-redirect router test) resolve to
// AsyncData on the first microtask — no real Dio request, no leaked Timer.
//
// Default behaviour mirrors [FakeAuthRepository]: read paths return settled
// data; un-exercised write paths throw [UnimplementedError].

import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';

/// In-memory [MasterRepository] implementation for tests.
///
/// Assign [profile] to control what [getMyProfile] returns.
final class FakeMasterRepository implements MasterRepository {
  FakeMasterRepository({Master? profile})
    : _profile = profile ?? _defaultMaster;

  final Master _profile;

  static const Master _defaultMaster = Master(
    id: 'user-1',
    firstName: 'Тест',
    lastName: 'Майстер',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.independentMaster,
  );

  @override
  Future<Master> getMyProfile(String masterId) async => _profile;

  @override
  Future<Master> getMasterById(String masterId) async => _profile;

  @override
  Future<void> updateLocality({
    required String cityId,
    String? districtId,
    required String street,
    required String buildingNo,
    String? locationNote,
  }) async => throw UnimplementedError('updateLocality not stubbed');

  @override
  Future<void> updateMyProfile(MasterUpdate update) async =>
      throw UnimplementedError('updateMyProfile not stubbed');
}
