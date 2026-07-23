// Phase 13.8 — BEAUTY PASSPORT repository.
//
// Fetches the CLIENT's auto-derived passport aggregate. The concrete
// implementation will call `GET /clients/me/passport` (backend 19.5) through
// the generated OpenAPI client and map via [PassportMapper.fromDto].
//
// CONTRACT NOT YET SHIPPED: backend 19.5 is not in the committed OpenAPI client,
// so [PlaceholderPassportRepository] returns an empty passport (TODO 19.5),
// consistent with how the Home Hub placeholders its 19.x cards. When the
// endpoint ships, add an `HttpPassportRepository` that calls the generated API
// and maps the DTO, then swap the provider binding.
//
// Pure Dart at the interface level; the placeholder impl has no Flutter import.

import '../domain/passport.dart';
import 'passport_mapper.dart';

/// Reads the CLIENT's derived beauty passport.
abstract interface class PassportRepository {
  /// Returns the signed-in client's auto-derived passport. Throws a typed
  /// `Failure` on transport/contract errors once wired to the real endpoint.
  Future<Passport> getMyPassport();
}

/// Placeholder repository used until `GET /clients/me/passport` (backend 19.5)
/// lands in the committed OpenAPI client. Always returns an empty passport so
/// the screen renders its encouraging empty state.
///
/// TODO(19.5): replace the provider binding with an `HttpPassportRepository`
/// that calls the generated API and maps via `PassportMapper.fromDto`.
final class PlaceholderPassportRepository implements PassportRepository {
  const PlaceholderPassportRepository();

  @override
  Future<Passport> getMyPassport() async => PassportMapper.placeholder();
}
