import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for DashboardControllerApi
void main() {
  final instance = BeauticaApi().getDashboardControllerApi();

  group(DashboardControllerApi, () {
    //Future<ApiResponseRevenueResponse> getRevenueSummary({ Date from, Date to, String filterMasterId, String serviceDefId, String salonId }) async
    test('test getRevenueSummary', () async {
      // TODO
    });
  });
}
