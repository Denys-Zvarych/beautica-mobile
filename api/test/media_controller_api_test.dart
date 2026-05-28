import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for MediaControllerApi
void main() {
  final instance = BeauticaApi().getMediaControllerApi();

  group(MediaControllerApi, () {
    //Future deleteAvatar() async
    test('test deleteAvatar', () async {
      // TODO
    });

    //Future deletePortfolioPhoto(String mediaId) async
    test('test deletePortfolioPhoto', () async {
      // TODO
    });

    //Future<ApiResponsePageMediaFileResponse> getMasterPortfolio(String masterId) async
    test('test getMasterPortfolio', () async {
      // TODO
    });

    //Future<ApiResponsePageMediaFileResponse> getSalonPortfolio(String salonId) async
    test('test getSalonPortfolio', () async {
      // TODO
    });

    //Future<ApiResponseAvatarResponse> uploadAvatar({ UploadPortfolioPhotoRequest uploadPortfolioPhotoRequest }) async
    test('test uploadAvatar', () async {
      // TODO
    });

    //Future<ApiResponseMediaFileResponse> uploadPortfolioPhoto({ UploadPortfolioPhotoRequest uploadPortfolioPhotoRequest }) async
    test('test uploadPortfolioPhoto', () async {
      // TODO
    });
  });
}
