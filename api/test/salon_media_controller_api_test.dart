import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for SalonMediaControllerApi
void main() {
  final instance = BeauticaApi().getSalonMediaControllerApi();

  group(SalonMediaControllerApi, () {
    // Remove the salon logo or cover (SALON_OWNER of this salon only)
    //
    // Idempotent: 204 even when the slot is already empty.
    //
    //Future deleteSalonImage(String salonId, String slot) async
    test('test deleteSalonImage', () async {
      // TODO
    });

    // Upload or replace the salon logo or cover (SALON_OWNER of this salon only)
    //
    // Multipart field `file`: JPEG, PNG or WebP (detected by magic bytes), max 5 MB. `slot` is `logo` (1:1) or `cover` (16:9). Returns the updated salon.
    //
    //Future<ApiResponseSalonResponse> uploadSalonImage(String salonId, String slot, MultipartFile file) async
    test('test uploadSalonImage', () async {
      // TODO
    });
  });
}
