// The CLIENT as a provider sees them — photo (monogram fallback), name, a
// and the client's ★ rating (em-dash when unreviewed; none at all for a guest,
// who has no account to be rated). No client-kind label for any client
// (CLI-100 / CLI-D19, M568).
//
// PROMOTED (2026-11-14) from `booking_counterparty_header.dart`'s private
// `_ClientStrip`, so the provider RESCHEDULE confirm screen («Підтвердження»)
// shows the client with the SAME avatar + rating as «Деталі запису» instead of
// a bare «Клієнт / <name>» label card. REUSE-FIRST: one widget, both screens.
// The detail screen renders it via [BookingClientStrip.fromBooking] with no
// optional params, so its render is unchanged; [topLabel], [shellKey] and
// [avatarImageKey] are additive and default to the detail screen's values.
//
// M509 (2026-11-20): three more ADDITIVE params — [details], [onTap] and
// [semanticsLabel] — so the «Клієнти» list renders its rows with this same
// strip (avatar, name, ★ readout) instead of a fork. All default to `null`, so
// «Деталі запису» and the reschedule confirm render byte-identically.
//
// Reuses [MasterStripShell] directly rather than [MasterStrip]: that widget is
// master-shaped (a role sub-line, the «Запис до майстра» caption, master-worded
// semantics), whereas the shell is the data-agnostic frame this needs.
//
// 2026-11-25: [BookingClientStrip.walkIn] — the walk-in review card (master
// «Підтвердження» and the salon wizard's confirm step) renders the client with
// this same strip (photo + ★ of a picked existing client; monogram + «—» for a
// hand-typed one) instead of a bare «Клієнт / <name>» label card. One more
// ADDITIVE param, [semanticsDetail] (default `null`: every other caller's
// screen-reader label is unchanged).
//
// 2026-11-21 (user): the provider «⋯» (report / block) left this strip — it
// lives only on the client card now (tap the strip → card → «⋯»).
//
// SEC: the client's name is PII. Hosting screens hold the
// `ScreenProtectionManager`; this widget adds no logging.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart'
    show PhotoViewerReport;

import '../../domain/booking.dart';
import '../../domain/booking_display_x.dart';
import '../../domain/booking_status.dart';
import 'master_strip.dart';
import 'master_strip_shell.dart';

/// The client counterparty strip — see the file header.
class BookingClientStrip extends StatelessWidget {
  const BookingClientStrip({
    super.key,
    required this.name,
    this.avatarUrl,
    this.initials,
    this.rating,
    this.reviewCount = 0,
    this.isGuest = false,
    this.dimmed = false,
    this.topLabel,
    this.shellKey = defaultShellKey,
    this.avatarImageKey = defaultAvatarImageKey,
    this.details,
    this.onTap,
    this.semanticsLabel,
    this.avatarPreviewOnTap = false,
    this.avatarPreviewReport,
    this.semanticsDetail,
  });

  /// The walk-in review card's client: [firstName] + [lastName], the
  /// [phone] (as typed/shown on the step) as the sub-line, and — only for a
  /// picked existing client — [avatarUrl] / [rating] / [reviewCount]. A
  /// hand-typed walk-in has none of those: the strip falls back to the
  /// name's monogram and the «—» readout, exactly like a guest row of the
  /// «Клієнти» list (CLI-47). [isGuest] stays `false` on purpose: that flag
  /// hides the rating readout, which a picked client keeps.
  factory BookingClientStrip.walkIn({
    Key? key,
    required String firstName,
    required String lastName,
    String? phone,
    String? avatarUrl,
    double? rating,
    int reviewCount = 0,
    String? topLabel,
    Key shellKey = defaultShellKey,
    Key avatarImageKey = defaultAvatarImageKey,
  }) {
    final String name = '$firstName $lastName'.trim();
    final String? shownPhone = (phone == null || phone.isEmpty) ? null : phone;
    return BookingClientStrip(
      key: key,
      name: name.isEmpty ? null : name,
      avatarUrl: avatarUrl,
      initials: _initialsOf(firstName, lastName),
      rating: rating,
      reviewCount: reviewCount,
      topLabel: topLabel,
      shellKey: shellKey,
      avatarImageKey: avatarImageKey,
      details: shownPhone == null
          ? null
          : Text(
              shownPhone,
              style: VelvetText.feedbackMutedSm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      semanticsDetail: shownPhone,
    );
  }

  /// First letter of each non-blank name part, upper-cased; `null` when
  /// both are blank (the shell then draws its generic glyph).
  static String? _initialsOf(String first, String last) {
    final String letters = <String>[first.trim(), last.trim()]
        .where((String p) => p.isNotEmpty)
        .map((String p) => String.fromCharCode(p.runes.first))
        .join()
        .toUpperCase();
    return letters.isEmpty ? null : letters;
  }

  /// The «Деталі запису» render of [booking]'s client — the exact derivation
  /// the private `_ClientStrip` used before the promotion.
  factory BookingClientStrip.fromBooking(
    Booking booking, {
    Key? key,
    VoidCallback? onTap,
    bool avatarPreviewOnTap = false,
    PhotoViewerReport? avatarPreviewReport,
  }) => BookingClientStrip(
    key: key,
    name: booking.clientName,
    avatarUrl: booking.clientAvatarUrl,
    initials: booking.clientInitials,
    rating: booking.clientDisplayRating,
    reviewCount: booking.clientReviewCount ?? 0,
    // Guest = an actual guest booking (`client_id IS NULL`) — never merely
    // because a name is missing. Hides the rating; no label (CLI-100).
    isGuest: booking.isGuestBooking,
    // A cancelled/declined booking's counterparty is dimmed — the same
    // `Opacity(0.7)` treatment the master strip gets.
    dimmed:
        booking.status == BookingStatus.cancelled ||
        booking.status == BookingStatus.declined,
    // ADDITIVE (2026-11-21): the provider detail's route into the client
    // card. `null` (every other caller) keeps the strip inert.
    onTap: onTap,
    avatarPreviewOnTap: avatarPreviewOnTap,
    avatarPreviewReport: avatarPreviewReport,
  );

  static const Key defaultShellKey = Key('booking-detail-client-strip');
  static const Key defaultAvatarImageKey = Key(
    'booking-detail-client-avatar-photo',
  );

  /// The client's display name; `null` renders the localized «Гість».
  final String? name;

  /// Public photo URL; `null` renders the [initials] monogram.
  final String? avatarUrl;

  /// ADDITIVE (2026-11-21): forwarded to
  /// [MasterStripShell.avatarPreviewOnTap]; `false` (the default) changes
  /// nothing.
  final bool avatarPreviewOnTap;

  /// ADDITIVE (MOD-39): with [avatarPreviewOnTap], the viewer's «Поскаржитися»
  /// for this profile (forwarded to [MasterStripShell.avatarPreviewReport]).
  /// `null` (the default) → no report button.
  final PhotoViewerReport? avatarPreviewReport;
  final String? initials;

  /// Already display-normalized (`BookingDisplayX.clientDisplayRating`);
  /// `null` = unreviewed (em-dash). Ignored when [isGuest].
  final double? rating;
  final int reviewCount;

  /// Guest booking (no client account): no rating, name-only semantics. No
  /// client-kind label (CLI-100, M568).
  final bool isGuest;

  /// Dead (cancelled/declined) booking: `Opacity(0.7)`.
  final bool dimmed;

  /// ADDITIVE: optional caption above the name (e.g. «Клієнт» on the
  /// reschedule confirm screen). `null` (the detail screen) shows none.
  final String? topLabel;

  final Key shellKey;
  final Key avatarImageKey;

  /// ADDITIVE (M509): extra sub-lines under the name (the list row's
  /// «Ост.: …» / «Наст.: …» dates and «Заблоковано» chip). `null` (every other
  /// call site) renders the sub-line exactly as before.
  final Widget? details;

  /// ADDITIVE (M509): makes the whole strip tappable, forwarded to
  /// [MasterStripShell.onTap] (press wash only, nothing at rest). `null` = inert.
  final VoidCallback? onTap;

  /// ADDITIVE (M509): replaces the computed screen-reader label. `null` keeps
  /// the label derived from [name] / [rating] / [isGuest].
  final String? semanticsLabel;

  /// ADDITIVE (2026-11-25): appended to the COMPUTED screen-reader label
  /// (e.g. the walk-in phone shown in [details]). Ignored when
  /// [semanticsLabel] is set; `null` (every other caller) changes nothing.
  final String? semanticsDetail;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final double? rating = this.rating;

    final String displayName = name ?? l10n.bookingDetailGuestClient;
    final String computed;
    if (semanticsLabel != null) {
      computed = semanticsLabel!;
    } else if (isGuest) {
      computed = l10n.bookingDetailClientSemantics(displayName);
    } else if (rating == null) {
      // Unreviewed: spoken as plain "no reviews yet", never «Рейтинг —». The
      // visible readout keeps its em-dash.
      computed = <String>[
        l10n.bookingDetailClientSemantics(displayName),
        l10n.masterReviewsEmpty,
      ].join('. ');
    } else {
      computed = l10n.bookingDetailClientRatedSemantics(
        displayName,
        rating.toStringAsFixed(1),
        l10n.salonReviewCountLabel(reviewCount),
      );
    }
    final String? extraSemantics = semanticsDetail;
    final String semantics = semanticsLabel != null || extraSemantics == null
        ? computed
        : '$computed, $extraSemantics';

    final Widget? extra = details;
    final Widget? middle = extra == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[extra],
          );

    // dim-gated: test/features/booking/presentation/booking_detail_provider_view_test.dart
    return Opacity(
      opacity: dimmed ? 0.7 : 1,
      child: MasterStripShell(
        key: shellKey,
        semanticsLabel: semantics,
        name: displayName,
        topLabel: topLabel,
        avatarImageUrl: avatarUrl,
        avatarInitials: initials,
        avatarImageKey: avatarImageKey,
        avatarPreviewOnTap: avatarPreviewOnTap,
        avatarPreviewReport: avatarPreviewReport,
        middleLine: middle,
        trailing: isGuest
            ? null
            : MasterRatingReadout(avgRating: rating, reviewCount: reviewCount),
        onTap: onTap,
      ),
    );
  }
}
