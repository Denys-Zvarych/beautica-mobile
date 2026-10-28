import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for ReportControllerApi
void main() {
  final instance = BeauticaApi().getReportControllerApi();

  group(ReportControllerApi, () {
    // Report a review, photo or profile
    //
    // Reports a piece of user-generated content the caller can currently see. One report per (caller, target): repeating it returns the existing report with 200 instead of 201. Own content cannot be reported (400). A target the caller cannot see answers 404. At most 20 new reports per 24 hours per user (429).
    //
    //Future<ApiResponseReportResponse> createReport(CreateReportRequest createReportRequest) async
    test('test createReport', () async {
      // TODO
    });
  });
}
