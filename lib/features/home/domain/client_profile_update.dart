// CLIENT profile edit value object.
//
// Carries the editable subset of the CLIENT user's profile fields that the user
// can modify on the client settings edit screens (Personal / Contacts /
// Location). Passed to [ClientProfileRepository.updateMyProfile].
//
// Mirrors [MasterUpdate] but for the CLIENT role, with two deliberate
// differences vs the master value object:
//   • NO `instagram` field — clients have no Instagram on their profile, so the
//     repository never sends the `instagram` key in the PATCH body.
//   • Adds locality fields (cityId / districtId) because the CLIENT location
//     edit screen patches the same `PATCH /users/me` endpoint (the master
//     location edit hit a separate master-locality endpoint). The free-text
//     address fields (street / buildingNo / locationNote) are deliberately NOT
//     carried here: a CLIENT only edits the locality cascade, so those keys are
//     never sent and the backend preserves any existing values.
//
// Every field is nullable: each edit screen owns only a slice of the profile and
// the repository merges the slice onto the cached profile (see
// [ClientProfileRepository.updateMyProfile]) so editing one section never
// clobbers another. CLIENT location is OPTIONAL — [cityId] may legitimately be
// null (the backend `validateClientLocality` permits a null city for clients).
//
// Pure Dart: no Flutter imports.

/// Editable profile fields for the CLIENT role.
///
/// All fields are nullable so a partial update (one edit screen's slice) can be
/// merged onto the cached profile without clearing untouched fields. The
/// repository decides — per backend contract — which keys to actually send.
final class ClientProfileUpdate {
  const ClientProfileUpdate({
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.cityId,
    this.districtId,
    this.touchesLocation = false,
  });

  /// CLIENT's given name. Null when the editing screen does not own this field.
  final String? firstName;

  /// CLIENT's family name. Null when the editing screen does not own this field.
  final String? lastName;

  /// Contact phone number. Null when the editing screen does not own this field.
  final String? phoneNumber;

  /// UUID of the selected city, or null. CLIENT location is OPTIONAL, so a null
  /// here when [touchesLocation] is true legitimately means "no city".
  final String? cityId;

  /// UUID of the selected district, or null when the city has no districts /
  /// none chosen.
  final String? districtId;

  /// Whether this update OWNS the locality slice (cityId / districtId). When
  /// true the repository sends those keys EXACTLY as carried here — including a
  /// null [cityId] (CLIENT location is optional, so null legitimately clears the
  /// city). When false the locality keys are omitted entirely and the cached
  /// location is preserved. This flag is what lets the repository tell "field
  /// not owned by this screen" apart from "field explicitly cleared". The
  /// free-text address keys (street / buildingNo / locationNote) are never sent
  /// from the client and are always preserved server-side.
  final bool touchesLocation;
}
