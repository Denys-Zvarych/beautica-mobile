// Phase 13.6 — Salon mappers: data-layer translation from generated DTOs to
// domain models.
//
// Every `fromDto` here is a pure translation boundary between a generated
// `beautica_api` type and a domain entity in `features/salon/domain/`.
// Generated DTO types must not cross this boundary into the domain or
// presentation layers.
//
// Error contract (backlog pattern — ServerFailure for a missing required id):
//   - [SalonMapper.fromDto] requires [PublicSalonResponse.id]; a null value
//     indicates a broken backend contract and surfaces as [ServerFailure].
//   - All other nullable fields are passed through as `null`, except the two
//     optional contact fields (`phone`, `instagramUrl`), which are normalised
//     through `SalonMapper._blankToNull` — see that helper's doc for the
//     `""`-vs-null wire contract it exists to absorb.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart'
    show ServicePriceType;
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';

import '../domain/bookable_master_assignment.dart';
import '../domain/pending_invite.dart';
import '../domain/salon.dart';
import '../domain/salon_master_summary.dart';
import '../domain/salon_portfolio_photo.dart';
import '../domain/salon_review.dart';
import '../domain/salon_service_catalog.dart';
import '../domain/salon_staff_member.dart';

/// Converts generated `beautica_api` types into the domain [Salon] entity and
/// its related read-model entities.
///
/// Pure translation — no network calls, no state. Inject / call only from
/// [HttpSalonRepository].
abstract final class SalonMapper {
  /// Maps a [PublicSalonResponse] DTO to the domain [Salon] model.
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.id] is absent,
  /// signalling a broken backend contract rather than a network/auth failure.
  static Salon fromDto(PublicSalonResponse dto) {
    final id = dto.id;
    if (id == null || id.isEmpty) {
      log(
        'PublicSalonResponse.id is null — broken backend contract',
        name: 'feature.salon.mapper',
        level: 1000,
      );
      throw const ServerFailure(statusCode: null);
    }

    return Salon(
      id: id,
      name: dto.name ?? '',
      description: dto.description,
      city: dto.city,
      region: dto.region,
      address: dto.address,
      cityId: dto.cityId,
      // `PublicSalonResponse.oblastId`, shipped backend `dbe27a5` alongside
      // the SalonAddressEditScreen work — see [Salon.oblastId]'s doc.
      oblastId: dto.oblastId,
      districtId: dto.districtId,
      street: dto.street,
      buildingNo: dto.buildingNo,
      locationNote: dto.locationNote,
      // `PublicSalonResponse.phone` now ships on the PUBLIC read path too
      // (backend + regenerated client — `public_salon_response.dart`), closing
      // the Phase 21.2 gap this line used to hard-code `null` for. Both
      // contact fields go through [_blankToNull]: the backend serves `""`
      // verbatim for a cleared field, which must not reach the UI as a
      // present-but-empty contact row — see [Salon.phone]'s doc.
      phone: _blankToNull(dto.phone),
      instagramUrl: _blankToNull(dto.instagramUrl),
      avatarUrl: dto.avatarUrl,
      coverImageUrl: dto.coverImageUrl,
      avgRating: dto.avgRating?.toDouble(),
      reviewCount: dto.reviewCount ?? 0,
    );
  }

  /// Maps a [SalonResponse] DTO (`PATCH /salons/{salonId}`'s owner/admin-
  /// facing response) to the domain [Salon] model.
  ///
  /// [SalonResponse] carries `phone` — and so, as of the backend change that
  /// closed the Phase 21.2 gap, does [PublicSalonResponse] ([fromDto]) — but
  /// it does NOT carry `coverImageUrl`, `avgRating`, or
  /// `reviewCount` (those are public-read-only aggregates). This method maps
  /// every field [SalonResponse] DOES carry and leaves the three it doesn't
  /// as `null`/`0` — callers (`SalonManagementProfile.save`) MUST merge those
  /// three back in from the previously-loaded [Salon] via `copyWith` rather
  /// than rendering this result directly, or the hero card's rating/review
  /// count/cover photo would incorrectly reset after every save.
  ///
  /// Throws [ServerFailure] (statusCode `null`) when [dto.id] is absent,
  /// mirroring [fromDto].
  static Salon fromUpdateDto(SalonResponse dto) {
    final id = dto.id;
    if (id == null || id.isEmpty) {
      log(
        'SalonResponse.id is null — broken backend contract',
        name: 'feature.salon.mapper',
        level: 1000,
      );
      throw const ServerFailure(statusCode: null);
    }

    return Salon(
      id: id,
      name: dto.name ?? '',
      description: dto.description,
      city: dto.city,
      region: dto.region,
      address: dto.address,
      cityId: dto.cityId,
      // Finding 3 (2026-08-28) — SalonResponse.oblastId, added alongside the
      // SalonAddressEditScreen work. See [Salon.oblastId]'s doc.
      oblastId: dto.oblastId,
      districtId: dto.districtId,
      street: dto.street,
      buildingNo: dto.buildingNo,
      locationNote: dto.locationNote,
      // Same blank-guard as [fromDto] — `PATCH /salons/{salonId}` echoes a
      // cleared contact field back as `""`, and the merged state this feeds
      // is rendered by the same two «Контакти» blocks. Keeping BOTH read
      // paths on [_blankToNull] is what makes "a blank contact never reaches
      // the domain" a real invariant rather than a per-screen guard.
      phone: _blankToNull(dto.phone),
      instagramUrl: _blankToNull(dto.instagramUrl),
      avatarUrl: dto.avatarUrl,
      // Deliberately NOT carried by SalonResponse — see method doc. Callers
      // must copyWith these back in from the previous [Salon].
      coverImageUrl: null,
      avgRating: null,
      reviewCount: 0,
      // Phase 21.1 — `SalonResponse.isPrimary` DOES carry this (unlike
      // `PublicSalonResponse`, which [fromDto] above leaves `null`). Also the
      // per-item mapping `getMySalons()` reuses for `GET /salons/mine`'s
      // `List<SalonResponse>` — see that method's own doc for why the SAME
      // DTO type makes this reuse exact, not a guess.
      isPrimary: dto.isPrimary,
    );
  }

  /// Normalises a blank optional contact field to `null`.
  ///
  /// LOCKED WIRE CONTRACT: the backend serves `""` VERBATIM when an owner
  /// clears `phone`/`instagramUrl` — it is NOT normalised to `null`
  /// server-side (pinned by backend tests). A raw pass-through would therefore
  /// hand the UI a present-but-empty contact, rendering an empty
  /// [ContactTile] row and an empty «Контакти» section heading. Returns `null`
  /// for a null or whitespace-only value, the trimmed value otherwise.
  static String? _blankToNull(String? value) {
    final String? trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// Maps [MasterSummaryResponse] (the salon masters-rail entry) to
/// [SalonMasterSummary].
abstract final class SalonMasterMapper {
  /// Entries with a null/empty `masterId` are dropped (logged) rather than
  /// thrown — one broken rail entry must not blank the whole "Майстри" tab.
  static List<SalonMasterSummary> fromDtoList(
    Iterable<MasterSummaryResponse> dtos,
  ) {
    final List<SalonMasterSummary> out = <SalonMasterSummary>[];
    for (final MasterSummaryResponse dto in dtos) {
      final String? masterId = dto.masterId;
      if (masterId == null || masterId.isEmpty) {
        log(
          'MasterSummaryResponse.masterId is null — dropping rail entry',
          name: 'feature.salon.mapper',
          level: 900,
        );
        continue;
      }
      out.add(
        SalonMasterSummary(
          masterId: masterId,
          firstName: dto.firstName ?? '',
          lastName: dto.lastName ?? '',
          professionalTitle: dto.professionalTitle,
          avatarUrl: dto.avatarUrl,
          avgRating: dto.avgRating?.toDouble(),
          reviewCount: dto.reviewCount ?? 0,
          type: _masterTypeFromDto(dto.masterType),
        ),
      );
    }
    return out;
  }

  static MasterType _masterTypeFromDto(MasterSummaryResponseMasterTypeEnum? e) {
    if (e == MasterSummaryResponseMasterTypeEnum.INDEPENDENT_MASTER) {
      return MasterType.independentMaster;
    }
    if (e == MasterSummaryResponseMasterTypeEnum.SALON_OWNER) {
      return MasterType.salonOwner;
    }
    // Covers SALON_MASTER and any future/unknown value — fail-safe.
    return MasterType.salonMaster;
  }
}

/// Maps [SalonStaffMemberResponse] (`GET /salons/{salonId}/staff`, Phase
/// 21.5) to [SalonStaffMember].
abstract final class SalonStaffMemberMapper {
  /// Entries with a null/empty `userId` are dropped (logged) rather than
  /// thrown — one broken roster entry must not blank the whole staff list.
  static List<SalonStaffMember> fromDtoList(
    Iterable<SalonStaffMemberResponse> dtos,
  ) {
    final List<SalonStaffMember> out = <SalonStaffMember>[];
    for (final SalonStaffMemberResponse dto in dtos) {
      final String? userId = dto.userId;
      if (userId == null || userId.isEmpty) {
        log(
          'SalonStaffMemberResponse.userId is null — dropping roster entry',
          name: 'feature.salon.mapper',
          level: 900,
        );
        continue;
      }
      out.add(
        SalonStaffMember(
          userId: userId,
          masterId: dto.masterId,
          role: _staffRoleFromDto(dto.role),
          firstName: dto.firstName ?? '',
          lastName: dto.lastName ?? '',
          professionalTitle: dto.professionalTitle,
          avatarUrl: dto.avatarUrl,
          phoneNumber: dto.phoneNumber,
          instagram: dto.instagram,
          bio: dto.bio,
          avgRating: dto.avgRating?.toDouble(),
          reviewCount: dto.reviewCount ?? 0,
          serviceCount: dto.serviceCount ?? 0,
        ),
      );
    }
    return out;
  }

  static SalonStaffRole _staffRoleFromDto(SalonStaffMemberResponseRoleEnum? e) {
    if (e == SalonStaffMemberResponseRoleEnum.SALON_ADMIN) {
      return SalonStaffRole.admin;
    }
    // Covers SALON_MASTER and any future/unknown value — fail-safe (this
    // endpoint's contract never returns CLIENT/SALON_OWNER/INDEPENDENT_MASTER
    // — mirrors [SalonMasterMapper._masterTypeFromDto]'s own precedent).
    return SalonStaffRole.master;
  }
}

/// Maps [PendingInviteResponse] (`GET /salons/{salonId}/invites/pending`) to
/// the domain [PendingInvite] (Phase 21.11).
abstract final class PendingInviteMapper {
  /// Entries with a null/empty `inviteId` are dropped (logged) rather than
  /// thrown — one broken row must not blank the whole pending list, and an
  /// entry with no id could not be cancelled anyway. Mirrors
  /// [SalonStaffMemberMapper.fromDtoList]'s own precedent.
  ///
  /// A null `createdAt` falls back to the Unix epoch rather than dropping the
  /// row: the timestamp only drives a soft "надіслано …" caption, so a
  /// missing one must not hide an invite the viewer needs to cancel.
  static List<PendingInvite> fromDtoList(Iterable<PendingInviteResponse> dtos) {
    final List<PendingInvite> out = <PendingInvite>[];
    for (final PendingInviteResponse dto in dtos) {
      final String? inviteId = dto.inviteId;
      if (inviteId == null || inviteId.isEmpty) {
        log(
          'PendingInviteResponse.inviteId is null — dropping invite entry',
          name: 'feature.salon.mapper',
          level: 900,
        );
        continue;
      }
      out.add(
        PendingInvite(
          inviteId: inviteId,
          recipientEmail: dto.recipientEmail ?? '',
          role: _inviteRoleFromWire(dto.role),
          createdAt:
              dto.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    }
    return out;
  }

  /// The wire `role` is a bare String on this DTO (not a generated enum), so
  /// it is matched literally. Anything other than `SALON_ADMIN` — including a
  /// null or an unknown future value — falls back to
  /// [SalonStaffRole.master], the same fail-safe direction
  /// [SalonStaffMemberMapper._staffRoleFromDto] takes.
  static SalonStaffRole _inviteRoleFromWire(String? role) =>
      role == 'SALON_ADMIN' ? SalonStaffRole.admin : SalonStaffRole.master;
}

/// Maps [BookableMasterResponse] (`GET
/// /salons/{salonId}/services/{serviceDefId}/masters`) to
/// [BookableMasterAssignment].
abstract final class SalonBookableMasterMapper {
  /// Entries missing `masterId`/`masterServiceId` are dropped (logged) rather
  /// than thrown — one broken row must not blank the whole master-selection
  /// step for the service.
  static List<BookableMasterAssignment> fromDtoList(
    Iterable<BookableMasterResponse> dtos,
  ) {
    final List<BookableMasterAssignment> out = <BookableMasterAssignment>[];
    for (final BookableMasterResponse dto in dtos) {
      final String? masterId = dto.masterId;
      final String? masterServiceId = dto.masterServiceId;
      if (masterId == null ||
          masterId.isEmpty ||
          masterServiceId == null ||
          masterServiceId.isEmpty) {
        log(
          'BookableMasterResponse missing masterId/masterServiceId — '
          'dropping row',
          name: 'feature.salon.mapper',
          level: 900,
        );
        continue;
      }
      out.add((masterId: masterId, masterServiceId: masterServiceId));
    }
    return out;
  }
}

/// Maps [SalonServiceCatalogResponse] to the domain
/// [SalonServiceCategoryEntry] list.
abstract final class SalonServiceCatalogMapper {
  static List<SalonServiceCategoryEntry> fromDto(
    SalonServiceCatalogResponse dto,
  ) {
    final categories = dto.categories;
    if (categories == null) return const <SalonServiceCategoryEntry>[];

    final List<SalonServiceCategoryEntry> out = <SalonServiceCategoryEntry>[];
    for (final group in categories) {
      final services = group.services ?? const <ServiceDefinitionResponse>[];
      final category = group.category ?? '';
      out.add(
        SalonServiceCategoryEntry(
          category: category,
          displayName: group.displayName ?? category,
          count: group.count ?? services.length,
          services: <SalonCatalogService>[
            for (final ServiceDefinitionResponse s in services)
              SalonCatalogService(
                id: s.id ?? '',
                name: s.name ?? '',
                durationLabel: DurationMinutes.format(
                  s.baseDurationMinutes ?? 0,
                ),
                priceDisplay: s.priceDisplay ?? '',
                photoUrl: s.photoUrl,
                category: s.category,
                serviceTypeSlug: s.serviceTypeSlug,
                serviceTypeNameUk: s.serviceTypeNameUk,
                durationMinutes: s.baseDurationMinutes,
                priceType:
                    s.priceType == ServiceDefinitionResponsePriceTypeEnum.RANGE
                    ? ServicePriceType.range
                    : ServicePriceType.fixed,
                priceMin: s.priceMin?.toDouble(),
                priceMax: s.priceMax?.toDouble(),
                // Three-state wire contract (true/false/null) collapses to
                // two-state here — null means "no favorite answer applies"
                // (anonymous/non-CLIENT caller) and the heart only has
                // filled/hollow, so it reads identically to "not
                // favourited". Mirrors `master_service_mapper.dart`'s
                // `MasterService.isFavorite` mapping.
                isFavorite: s.isFavorite ?? false,
              ),
          ],
        ),
      );
    }
    return out;
  }
}

/// Maps `MediaFileResponse` (portfolio entries) to [SalonPortfolioPhoto].
abstract final class SalonPortfolioMapper {
  /// Entries with a null/empty `id` or `url` are dropped (logged) rather than
  /// thrown — one broken photo must not blank the whole portfolio rail.
  static List<SalonPortfolioPhoto> fromDtoList(
    Iterable<MediaFileResponse> dtos,
  ) {
    final List<SalonPortfolioPhoto> out = <SalonPortfolioPhoto>[];
    for (final MediaFileResponse dto in dtos) {
      final String? id = dto.id;
      final String? url = dto.url;
      if (id == null || id.isEmpty || url == null || url.isEmpty) {
        log(
          'MediaFileResponse missing id/url — dropping portfolio entry',
          name: 'feature.salon.mapper',
          level: 900,
        );
        continue;
      }
      out.add(SalonPortfolioPhoto(id: id, url: url));
    }
    return out;
  }
}

/// Maps [SalonReviewSummaryResponse] to the domain [SalonReviewSummary], and
/// [SalonReviewResponse] to [SalonReviewItem].
abstract final class SalonReviewMapper {
  /// [ratingDistribution] arrives as unordered `{rating, count}` buckets
  /// (only non-zero buckets are guaranteed present pre-regen — the current
  /// backend contract zero-fills all five). This reduces it to a fixed
  /// highest-first `List<int>` (index 0 = 5★ … index 4 = 1★) regardless of
  /// wire order, defaulting any missing bucket to 0.
  static SalonReviewSummary summaryFromDto(SalonReviewSummaryResponse dto) {
    final List<int> distribution = List<int>.filled(5, 0);
    for (final bucket in dto.ratingDistribution ?? const <RatingBucket>[]) {
      final int? star = bucket.rating;
      if (star == null || star < 1 || star > 5) continue;
      distribution[5 - star] = bucket.count ?? 0;
    }
    return SalonReviewSummary(
      avgRating: dto.avgRating?.toDouble(),
      reviewCount: dto.reviewCount ?? 0,
      distribution: distribution,
    );
  }

  /// Entries with a null/empty `id` are dropped (logged) rather than thrown —
  /// one broken review must not blank the whole "Відгуки" tab.
  static List<SalonReviewItem> reviewsFromDtoList(
    Iterable<SalonReviewResponse> dtos,
  ) {
    final List<SalonReviewItem> out = <SalonReviewItem>[];
    for (final SalonReviewResponse dto in dtos) {
      final String? id = dto.id;
      if (id == null || id.isEmpty) {
        log(
          'SalonReviewResponse.id is null — dropping review entry',
          name: 'feature.salon.mapper',
          level: 900,
        );
        continue;
      }
      final String masterName =
          '${dto.masterFirstName ?? ''} ${dto.masterLastName ?? ''}'.trim();
      out.add(
        SalonReviewItem(
          id: id,
          masterId: dto.masterId ?? '',
          masterName: masterName,
          clientDisplayName: dto.clientDisplayName ?? '',
          serviceName: dto.serviceName,
          rating: dto.rating ?? 0,
          comment: dto.comment ?? '',
          // instant-ok: last-resort fallback for a malformed/absent DTO timestamp
          createdAt: dto.createdAt ?? DateTime.now(),
        ),
      );
    }
    return out;
  }
}
