// M543 (CLI-80, CLI-D15, BOOK-80) — the typed in-memory route `extra` that
// opens the staff walk-in flow from a client card with the card's client
// prefilled.
//
// PII: [prefill] carries names + phone. It travels ONLY as a go_router
// `extra` (in memory) — never in a path, query or deep link, never logged.
// `toString` prints nothing. Lost on process death / cold deep link → the
// form opens empty (manual entry), which is correct.
//
// Pure Dart: no Flutter imports (`immutable` comes from `package:meta` via
// freezed_annotation).

import 'package:freezed_annotation/freezed_annotation.dart' show immutable;

import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';

@immutable
class WalkInLaunch {
  const WalkInLaunch({required this.prefill, this.salonId});

  /// Applied once by the host screen on open; editable afterwards.
  final ClientPrefill prefill;

  /// The salon the walk-in is booked under — required by
  /// `/salon/bookings/new`, `null` for the independent master's own flow.
  final String? salonId;

  @override
  String toString() => 'WalkInLaunch()';
}
