// Phase 13.8 — BEAUTY PASSPORT mapper.
//
// Maps the backend's derived passport aggregate (`GET /clients/me/passport`,
// backend 19.5) into the pure-Dart [Passport] domain model. The generated DTO
// type would never escape the data layer.
//
// CONTRACT NOT YET SHIPPED: `GET /clients/me/passport` (backend 19.5) is not in
// the committed OpenAPI client, so there is no generated DTO to map. Until it
// lands, [PassportMapper.placeholder] returns an empty passport so the screen
// compiles and renders its empty/loading states — mirroring how the Home Hub
// notifier placeholders the other 19.x endpoints (`home_hub_notifier.dart`).
//
// TODO(19.5): when the OpenAPI client exposes the passport DTO, add
//   `static Passport fromDto(GeneratedPassportDto dto) => …`
// here and call it from the repository instead of [placeholder]. Do NOT invent
// the contract — wire it only once the backend ships and the client regenerates.
//
// Pure Dart: no Flutter imports in this file.

import '../domain/passport.dart';

/// Maps the backend passport aggregate into the [Passport] domain model.
abstract final class PassportMapper {
  /// Placeholder used while `GET /clients/me/passport` (backend 19.5) is not in
  /// the committed OpenAPI client. Returns an empty passport so the screen
  /// renders its encouraging empty state rather than failing.
  ///
  /// TODO(19.5): replace with `fromDto` once the contract ships.
  static Passport placeholder() => Passport.empty();
}
