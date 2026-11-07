import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for AndroidAppConfig
void main() {
  final instance = AndroidAppConfigBuilder();
  // TODO add properties to the builder and call build()

  group(AndroidAppConfig, () {
    // Minimum supported Android versionCode (pubspec +N build number)
    // int minVersionCode
    test('to test the property `minVersionCode`', () async {
      // TODO
    });

    // Latest Android versionCode on Google Play
    // int latestVersionCode
    test('to test the property `latestVersionCode`', () async {
      // TODO
    });

    // Google Play listing URL
    // String storeUrl
    test('to test the property `storeUrl`', () async {
      // TODO
    });
  });
}
