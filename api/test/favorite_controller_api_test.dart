import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for FavoriteControllerApi
void main() {
  final instance = BeauticaApi().getFavoriteControllerApi();

  group(FavoriteControllerApi, () {
    //Future<ApiResponseFavoriteResponse> addFavorite(AddFavoriteRequest addFavoriteRequest) async
    test('test addFavorite', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseFavoriteMasterResponse> listMasterFavorites(Pageable pageable) async
    test('test listMasterFavorites', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseFavoriteSalonResponse> listSalonFavorites(Pageable pageable) async
    test('test listSalonFavorites', () async {
      // TODO
    });

    //Future removeFavorite(String targetType, String targetId) async
    test('test removeFavorite', () async {
      // TODO
    });
  });
}
