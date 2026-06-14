// Phase 16.2 — ServiceTypeMapper: data-layer translation from the generated
// slug-contract DTO [PlatformServiceTypeResponse] to the domain
// [ServiceTypeOption].
//
// The 16.1 client exposes the service-type lookup as
// `PlatformServiceTypeResponse { id, slug, nameUk, categoryName }`. Every field
// is nullable on the generated DTO; this mapper is total — it substitutes empty
// strings for any absent field so the picker never crashes on a partial row.
// Filtering of unusable rows (empty id/slug) is the repository's concern, not
// the mapper's.
//
// Pure translation class — no network calls, no state, no presentation logic.
// Call only from [HttpServiceRepository].

import 'package:beautica_api/beautica_api.dart';

import '../domain/service_type_option.dart';

/// Translates the generated [PlatformServiceTypeResponse] into the domain
/// [ServiceTypeOption] used by the second-level service-type picker.
abstract final class ServiceTypeMapper {
  /// Maps a single [PlatformServiceTypeResponse] DTO to [ServiceTypeOption].
  ///
  /// Total mapping: nullable wire fields fall back to empty strings. The
  /// repository drops rows whose [ServiceTypeOption.id] or
  /// [ServiceTypeOption.slug] is empty (unselectable) — this mapper itself
  /// never throws.
  static ServiceTypeOption fromDto(PlatformServiceTypeResponse dto) {
    return ServiceTypeOption(
      id: dto.id ?? '',
      slug: dto.slug ?? '',
      nameUk: dto.nameUk ?? '',
      categoryName: dto.categoryName ?? '',
    );
  }

  /// Maps a list of [PlatformServiceTypeResponse] DTOs to domain options,
  /// dropping any entry whose wire [id] or [slug] is empty (unselectable).
  static List<ServiceTypeOption> fromDtoList(
    Iterable<PlatformServiceTypeResponse> dtos,
  ) => dtos
      .map(fromDto)
      .where((o) => o.id.isNotEmpty && o.slug.isNotEmpty)
      .toList(growable: false);
}
