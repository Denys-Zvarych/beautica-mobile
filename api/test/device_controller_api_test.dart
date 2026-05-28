import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for DeviceControllerApi
void main() {
  final instance = BeauticaApi().getDeviceControllerApi();

  group(DeviceControllerApi, () {
    //Future registerToken(RegisterDeviceTokenRequest registerDeviceTokenRequest) async
    test('test registerToken', () async {
      // TODO
    });

    //Future unregisterToken(UnregisterDeviceTokenRequest unregisterDeviceTokenRequest) async
    test('test unregisterToken', () async {
      // TODO
    });
  });
}
