import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for UserControllerApi
void main() {
  final instance = BeauticaApi().getUserControllerApi();

  group(UserControllerApi, () {
    //Future<ApiResponseUserProfileResponse> getMe() async
    test('test getMe', () async {
      // TODO
    });

    //Future<ApiResponseUserProfileResponse> updateMe(UpdateProfileRequest updateProfileRequest) async
    test('test updateMe', () async {
      // TODO
    });
  });
}
