import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for SupportControllerApi
void main() {
  final instance = BeauticaApi().getSupportControllerApi();

  group(SupportControllerApi, () {
    // Send a Help / Contact-us message to support
    //
    // Accepts a free-text message plus optional file attachments and emails the whole thing to the support inbox. Authenticated users only; the sender's identity is taken from the JWT, never from the request body.  Constraints: up to 5 attachments, each ≤ 5 MB, total ≤ 5 MB; allowed types JPEG, PNG, WebP, PDF (validated by content, not the declared header).
    //
    //Future<ApiResponseContactSupportResponse> contact({ ContactSupportRequest request, BuiltList<MultipartFile> attachments }) async
    test('test contact', () async {
      // TODO
    });
  });
}
