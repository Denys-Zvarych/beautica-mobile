import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for AppConfigApi
void main() {
  final instance = BeauticaApi().getAppConfigApi();

  group(AppConfigApi, () {
    // Minimum and latest supported app builds
    //
    // Public. Compare against the Android versionCode (pubspec +N), never the semver string.
    //
    //Future<ApiResponseAppConfigResponse> getConfig() async
    test('test getConfig', () async {
      // TODO
    });
  });
}
