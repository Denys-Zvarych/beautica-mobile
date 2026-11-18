// PROMOTED (M515) from `verification_screen.dart` (`_ResolvedLocality` +
// the role switch of `_saveProviderProfile`), byte-for-byte, so the legacy
// email-verification path and the phone-first register path (address step,
// session issued at once) persist the registration locality through ONE
// implementation:
//   INDEPENDENT_MASTER → PATCH /independent-masters/me  (provider profile)
//   SALON_OWNER        → POST  /salons                   (creates the salon)
//   CLIENT             → PATCH /users/me                 (user row only)
//   SALON_ADMIN / _MASTER → no-op (invite flow, no address step).
// Rethrows the typed [Failure] so the caller surfaces it (never silent).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failures.dart';
import '../../master/data/master_repository.dart';
import '../../salon/data/salon_repository.dart';
import '../../user/data/user_repository.dart';
import '../domain/user_role.dart';

/// The effective registration slice to persist once a session exists —
/// sourced from the in-memory draft or the durable `PendingLocality` blob.
final class RegistrationLocality {
  const RegistrationLocality({
    required this.role,
    required this.localityProvided,
    required this.cityId,
    required this.districtId,
    required this.street,
    required this.buildingNo,
    required this.locationNote,
    required this.salonName,
    required this.phone,
  });

  final UserRole role;

  /// `true` when the user provably chose a city on Step 3 (de-silences the
  /// lost-draft case for CLIENT). `false` for a genuine CLIENT skip.
  final bool localityProvided;

  final String? cityId;
  final String? districtId;
  final String street;
  final String buildingNo;
  final String locationNote;
  final String salonName;
  final String phone;
}

/// Persists [locality] with the role's endpoint (see the file header).
Future<void> saveRegistrationLocality(
  WidgetRef ref,
  RegistrationLocality locality,
) async {
  final cityId = locality.cityId;
  final bool isCityMissing = cityId == null || cityId.isEmpty;

  if (isCityMissing) {
    switch (locality.role) {
      case UserRole.independentMaster:
      case UserRole.salonOwner:
        // Provider roles require a city — the Step 3 address wizard is
        // mandatory for them and the PATCH / POST cannot succeed without it.
        // A missing city here means the state was lost AND the durable blob
        // could not supply it — surface a typed failure so the user can go
        // back to Step 3, instead of silently creating a located-less account.
        throw const ProviderMissingCityFailure();
      case UserRole.client:
        // De-silence the lost-draft case: if the user provably chose a city
        // (the blob recorded localityProvided == true) but we still cannot
        // resolve it, the durable blob was unexpectedly missing/corrupt. Do
        // NOT block /done, but log it (debug-only, ids only) so the loss is
        // not invisible. A genuine CLIENT skip (localityProvided == false)
        // stays a silent no-op — the legitimate path.
        if (locality.localityProvided && kDebugMode) {
          log(
            'CLIENT chose a city on Step 3 but locality could not be '
            'persisted (durable blob missing/corrupt); skipping PATCH',
            name: 'auth.verification',
            level: 900,
          );
        }
        return;
      case UserRole.salonAdmin:
      case UserRole.salonMaster:
        // Invite-flow roles never run Step 3.
        return;
    }
  }

  final districtId = locality.districtId;

  switch (locality.role) {
    case UserRole.independentMaster:
      await ref
          .read(masterRepositoryProvider)
          .updateLocality(
            cityId: cityId,
            districtId: districtId,
            street: locality.street,
            buildingNo: locality.buildingNo,
            locationNote: locality.locationNote,
          );
    case UserRole.salonOwner:
      await ref
          .read(salonRepositoryProvider)
          .create(
            dto: SalonCreateDto(
              name: locality.salonName,
              cityId: cityId,
              districtId: districtId,
              street: locality.street,
              buildingNo: locality.buildingNo,
              locationNote: locality.locationNote,
              phone: locality.phone,
            ),
          );
    case UserRole.client:
      // CLIENT has no provider profile, but locality must still be persisted
      // — the register endpoint drops these fields (RegisterRequest doesn't
      // declare them), so PATCH /users/me is the FIRST point they reach the
      // DB. Mirrors the INDEPENDENT_MASTER branch above.
      await ref
          .read(userRepositoryProvider)
          .updateLocality(
            cityId: cityId,
            districtId: districtId,
            street: locality.street,
            buildingNo: locality.buildingNo,
            locationNote: locality.locationNote,
          );
    case UserRole.salonAdmin:
    case UserRole.salonMaster:
      // Invite-flow roles never run the Step 3 wizard.
      return;
  }
}
