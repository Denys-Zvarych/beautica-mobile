// Phase 469 — copy hint for services that share one displayed name.
//
// Track: docs/duplicate-services-track.md (D3 — the hint is client-side).
// One rule, shared with website 036 (`src/lib/booking/serviceHint.ts`); the
// two are kept in step by the shared fixture cases in
// `test/features/services/domain/service_name_hint_test.dart`.
//
// Pure Dart — no Flutter imports.

import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';

/// One row of an owner's service list, reduced to what the hint rule reads.
final class ServiceHintInput {
  const ServiceHintInput({
    required this.id,
    required this.displayedName,
    required this.customName,
    required this.durationMinutes,
  });

  /// Builds the input from a [MasterService] using the card label rule
  /// ([MasterServiceDisplayName.displayedName]).
  factory ServiceHintInput.fromMasterService(MasterService s) =>
      ServiceHintInput(
        id: s.id,
        displayedName: s.displayedName,
        customName: s.name,
        durationMinutes: s.durationMinutes,
      );

  final String id;
  final String displayedName;
  final String? customName;
  final int durationMinutes;
}

/// The card label rule: the master's custom name when present, otherwise the
/// platform service-type name; empty when both are empty.
extension MasterServiceDisplayName on MasterService {
  String get displayedName {
    final String custom = name.trim();
    return custom.isNotEmpty ? custom : (serviceTypeNameUk ?? '').trim();
  }
}

String _normalise(String value) => value.trim().toLowerCase();

/// Hints keyed by service id, for ONE owner's list (across categories).
///
/// Items are grouped by `displayedName.trim().toLowerCase()`. A group of one
/// gets no entry. In a larger group each item gets its [ServiceHintInput.
/// customName] when that differs (normalised) from the displayed name,
/// otherwise its duration via [DurationMinutes.format].
Map<String, String> serviceNameHints(Iterable<ServiceHintInput> items) {
  final Map<String, List<ServiceHintInput>> groups =
      <String, List<ServiceHintInput>>{};
  for (final ServiceHintInput item in items) {
    (groups[_normalise(item.displayedName)] ??= <ServiceHintInput>[]).add(item);
  }
  final Map<String, String> hints = <String, String>{};
  for (final List<ServiceHintInput> group in groups.values) {
    if (group.length < 2) continue;
    for (final ServiceHintInput item in group) {
      // Unreachable from the app today (displayed = custom when set); kept to
      // mirror website 036 — exercised via the input contract by F5/F6.
      final String custom = (item.customName ?? '').trim();
      final bool customDiffers =
          custom.isNotEmpty &&
          _normalise(custom) != _normalise(item.displayedName);
      hints[item.id] = customDiffers
          ? custom
          : DurationMinutes.format(item.durationMinutes);
    }
  }
  return hints;
}

/// Convenience over [serviceNameHints] for a list of [MasterService]s.
Map<String, String> masterServiceNameHints(Iterable<MasterService> services) =>
    serviceNameHints(services.map(ServiceHintInput.fromMasterService));
