// M510 — one row of «Ваші оцінки» (B526 `ClientOwnRatingResponse`): the
// viewer's scope's own stars for one visit. The contract carries NO comment
// text and this type has no field for one (REV-D10).
//
// Pure Dart: no Flutter imports.

import 'package:freezed_annotation/freezed_annotation.dart';

part 'client_own_rating.freezed.dart';

@freezed
abstract class ClientOwnRating with _$ClientOwnRating {
  const factory ClientOwnRating({
    required String bookingId,
    required DateTime visitAt,
    required String serviceName,

    /// 1..5.
    required int stars,
  }) = _ClientOwnRating;
}
