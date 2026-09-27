import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for SearchSuggestionControllerApi
void main() {
  final instance = BeauticaApi().getSearchSuggestionControllerApi();

  group(SearchSuggestionControllerApi, () {
    // Autocomplete suggestions for the search box
    //
    // Ranked CATEGORY and SERVICE suggestions available at the caller's place (or the national list with no place chosen). Never 404s; no match or nothing available returns an empty list.
    //
    //Future<ApiResponseListSearchSuggestionResponse> suggest(SearchSuggestionRequest request) async
    test('test suggest', () async {
      // TODO
    });
  });
}
