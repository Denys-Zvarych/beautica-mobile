import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for GuestTelegramLinkControllerApi
void main() {
  final instance = BeauticaApi().getGuestTelegramLinkControllerApi();

  group(GuestTelegramLinkControllerApi, () {
    //Future<GuestTelegramLinkResponse> linkToken(GuestTelegramTokenRequest guestTelegramTokenRequest) async
    test('test linkToken', () async {
      // TODO
    });

    //Future<GuestTelegramStatusResponse> status(GuestTelegramTokenRequest guestTelegramTokenRequest) async
    test('test status', () async {
      // TODO
    });

    //Future unlink(GuestTelegramTokenRequest guestTelegramTokenRequest) async
    test('test unlink', () async {
      // TODO
    });
  });
}
