// Phase 334 — «Відгук клієнта»: the read-only block on «Деталі запису» that
// shows the PROVIDER the review their client left about them.
//
// ## Reuses the shared [ReviewCard] — it is not a second review card
//
// The card itself is `features/review/presentation/widgets/review_card.dart`,
// the SAME leaf the salon «Відгуки» tab and the master's received-reviews
// screen render every one of their reviews through. Two of its fields were
// widened to nullable to accept this payload ([ReviewCardData.createdAt] and
// [ReviewCardData.comment] — see each one's doc); nothing else moved, and both
// existing callers pass non-null values, so their cards render byte-for-byte
// as before. A fix to the card's avatar, star row or spacing now lands here
// too, which is the point.
//
// ## The payload is thinner than the card
//
// `ClientAuthoredReview` is `{rating, comment?}` and nothing else — no review
// id, no author name, no timestamp (see that model's file header for why the
// backend sends no more). Three of the card's inputs are therefore sourced
// from the BOOKING instead of from the review:
//
//   * [ReviewCardData.id] ← the booking id. It seeds the card's widget key and
//     the deterministic avatar gradient; one booking carries at most one
//     client review, so the booking id is exactly as stable a seed as a review
//     id would be.
//   * [ReviewCardData.clientDisplayName] ← `BookingDisplayX.clientName`,
//     degrading to the localized «Гість» — the same name the counterparty
//     header at the top of this very screen already shows, so the review is
//     unmistakably attributed to the person the provider is looking at.
//   * [ReviewCardData.createdAt] ← `null`. The header row's relative-date
//     slot is omitted rather than filled with the BOOKING's date, which would
//     be a fabrication: a client can review days after the visit.
//
// ## Heading, not an eyebrow
//
// A plain [VelvetText.label] heading, matching `OutboundNote`'s idiom in
// `booking_notes.dart` — deliberately NOT the leave-review screens'
// `ReviewSectionLabel`, whose required `tag` («обов'язково» / «необов'язково»)
// is a FORM affordance that means nothing on a read-only block. The heading
// earns its place: the provider branch of this screen already renders
// client-written text just above (the client's booking brief, via
// [BookingNotes]), and without a heading two blocks of the client's words
// would run together with nothing to tell them apart.
//
// ## Accessibility
//
// [ReviewCard] draws its score as five bare [Icon] glyphs, which a screen
// reader cannot interpret at all. The section therefore wraps the whole block
// in a [Semantics] node that spells the rating out and excludes the
// descendants, exactly as `OutboundNote` does for a note.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/review/presentation/widgets/review_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/client_authored_review.dart';

/// The «Відгук клієнта» block — a heading over one shared [ReviewCard].
///
/// Render it only on the PROVIDER branch of «Деталі запису», and only when
/// `Booking.reviewByClient` is non-null. This widget does NOT re-check either
/// condition: it has no access to the session, and a null review has nothing
/// to draw. The caller owns both gates — see `booking_detail_screen.dart`.
class ClientReviewSection extends StatelessWidget {
  const ClientReviewSection({
    super.key,
    required this.review,
    required this.bookingId,
    required this.clientDisplayName,
  });

  /// The client's review of the master, already mapped off
  /// `GET /bookings/{id}`.
  final ClientAuthoredReview review;

  /// Seeds the card's widget key (`client-review-<bookingId>`) and its
  /// deterministic avatar gradient — the review payload carries no id of its
  /// own. See the file header.
  final String bookingId;

  /// The client's name as this screen already shows it in the counterparty
  /// header, pre-resolved and pre-localized by the caller (so this widget
  /// needs no guest fallback of its own).
  final String clientDisplayName;

  /// Widget-key namespace handed to [ReviewCard], alongside `salon-review`
  /// and `master-review`.
  static const String keyPrefix = 'client-review';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? comment = review.comment;
    return Semantics(
      label: comment == null
          ? l10n.bookingDetailClientReviewSemanticsNoComment(review.rating)
          : l10n.bookingDetailClientReviewSemantics(review.rating, comment),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l10n.bookingDetailClientReviewHeading,
            style: VelvetText.label(),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          ReviewCard(
            data: ReviewCardData(
              id: bookingId,
              clientDisplayName: clientDisplayName,
              rating: review.rating,
              // Both null-able here and both genuinely absent from the wire —
              // the card omits the body line and the relative-date slot
              // rather than inventing either. See the file header.
              comment: comment,
            ),
            keyPrefix: keyPrefix,
          ),
        ],
      ),
    );
  }
}
