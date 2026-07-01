// Fake [ServiceRepository] for widget tests.
//
// Returns settled (empty by default) read results so the profile screen's
// services section resolves without touching the real Dio stack or leaking a
// Timer. Default behaviour mirrors [FakeAuthRepository]: read paths return
// settled data; un-exercised write paths throw [UnimplementedError].

import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';

/// In-memory [ServiceRepository] implementation for tests.
///
/// Assign [services] / [categories] to control the read responses.
final class FakeServiceRepository implements ServiceRepository {
  FakeServiceRepository({
    List<MasterService>? services,
    List<ServiceCategoryOption>? categories,
  }) : _services = services ?? const <MasterService>[],
       _categories = categories ?? const <ServiceCategoryOption>[];

  final List<MasterService> _services;
  final List<ServiceCategoryOption> _categories;

  @override
  Future<List<MasterService>> listMyServices() async => _services;

  @override
  Future<List<MasterService>> getMasterServices(String masterId) async =>
      _services;

  @override
  Future<List<ServiceCategoryOption>> fetchApprovedCategories() async =>
      _categories;

  @override
  Future<List<ServiceTypeOption>> fetchServiceTypes(
    String categoryName,
  ) async => const <ServiceTypeOption>[];

  @override
  Future<MasterService> getMyService(String id) async =>
      throw UnimplementedError('getMyService not stubbed');

  @override
  Future<MasterService> create(MasterServiceCreate input) async =>
      throw UnimplementedError('create not stubbed');

  @override
  Future<List<MasterService>> bulkCreate(
    List<MasterServiceBulkItem> items,
  ) async => throw UnimplementedError('bulkCreate not stubbed');

  @override
  Future<MasterService> update(
    String serviceDefId,
    MasterServiceUpdate patch, {
    required String assignmentId,
  }) async => throw UnimplementedError('update not stubbed');

  @override
  Future<void> deactivate(String serviceDefId) async =>
      throw UnimplementedError('deactivate not stubbed');

  @override
  Future<void> requestCategory({
    required String name,
    required String displayName,
    String? initialServiceName,
  }) async => throw UnimplementedError('requestCategory not stubbed');

  @override
  Future<void> suggestServiceType({
    required String categoryName,
    required String name,
    String? description,
  }) async => throw UnimplementedError('suggestServiceType not stubbed');
}
