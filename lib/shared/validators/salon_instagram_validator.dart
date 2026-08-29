// Phase 21.3 — Salon Instagram validator.
//
// PROMOTED (REUSE-FIRST) out of `SalonContactsEditScreen`'s private
// `_validateInstagram` (Phase 21.10) so `RegisterSalonScreen` (Phase 21.3)
// can reuse the SAME validation instead of duplicating it. `SalonContactsEditScreen`
// is rewired onto this function verbatim — same rules, same error key, same
// behaviour, proven by that screen's own existing widget-test coverage
// (`test/features/salon/presentation/salon_edit_forms_test.dart`) staying
// green after the rewire.
//
// Mirrors backend `CreateSalonRequest`/`UpdateSalonRequest.instagramUrl`'s
// own pattern: accepts a bare `@handle`, an `@`-less handle, or a full
// instagram.com URL. Optional — an empty value is always valid.
//
// NOTE: `features/master/presentation/contacts_edit_screen.dart` carries its
// own separate, slightly different instagram-URL regex (`{1,60}` path
// segment vs this file's `+/?`) for the MASTER profile's Instagram field —
// a pre-existing drift this phase does not touch (different feature,
// different backend DTO/pattern: `MasterProfileUpdateRequest.instagram`).
// Consolidating that one too is a separate cleanup, out of this phase's scope.

import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Maximum salon-Instagram-URL length accepted by the backend
/// (`@Size(max = 500)`).
const int kSalonInstagramMaxLength = 500;

final RegExp _kSalonInstagramHandle = RegExp(r'^@?[A-Za-z0-9._]{1,30}$');
final RegExp _kSalonInstagramUrl = RegExp(
  r'^https://(www\.)?instagram\.com/[A-Za-z0-9._]+/?$',
);

/// Returns `null` when [v] is a valid (or empty) salon Instagram handle/URL,
/// or a localised error string otherwise.
String? validateSalonInstagram(String? v, AppLocalizations l10n) {
  final trimmed = v?.trim() ?? '';
  if (trimmed.isEmpty) return null; // optional
  if (!_kSalonInstagramHandle.hasMatch(trimmed) &&
      !_kSalonInstagramUrl.hasMatch(trimmed)) {
    return l10n.masterEditInstagramError;
  }
  return null;
}
