// Phase 363 — every user-visible notification string, resolved from the ARB.
//
// Shape rules (so the copy stays scannable in a long list):
//  * the TITLE says what happened, in the reader's own terms;
//  * the BODY says to whom / what / when — a provider leads with the client
//    («Олена Коваль — Манікюр +2, пт, 3 жовтня, 14:30»), a client leads with
//    the service and ends with who provides it;
//  * `+N` = `serviceCount - 1`, appended to the first service of a visit;
//  * titles avoid gendered verbs: the API sends a display name, not a gender.
//
// AUDIENCE: the wire row carries no audience, so the two types that read
// differently for a client and a provider (declined, rescheduled) are decided
// by the viewer's role — `isClient`.
//
// DATES: `startsAt` is a canonical-UTC instant; it is shown in Europe/Kyiv via
// the shared booking formatters (`toBeauticaTime`), never the device zone.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/uk_calendar.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';

import '../domain/app_notification.dart';

abstract final class NotificationCopy {
  /// Wire role name of an invited salon administrator.
  static const String _salonAdminWire = 'SALON_ADMIN';

  static String title(
    AppLocalizations l10n,
    AppNotificationType type, {
    required bool isClient,
  }) => switch (type) {
    AppNotificationType.bookingCreated => l10n.notificationTitleBookingCreated,
    AppNotificationType.bookingCancelledByClient =>
      l10n.notificationTitleCancelledByClient,
    AppNotificationType.bookingDeclined =>
      isClient
          ? l10n.notificationTitleDeclinedClient
          : l10n.notificationTitleDeclinedProvider,
    AppNotificationType.bookingRescheduled =>
      isClient
          ? l10n.notificationTitleRescheduledClient
          : l10n.notificationTitleRescheduledProvider,
    AppNotificationType.inviteAccepted => l10n.notificationTitleInviteAccepted,
    AppNotificationType.bookingNotCompleted =>
      l10n.notificationTitleNotCompleted,
    AppNotificationType.reviewRequested =>
      l10n.notificationTitleReviewRequested,
    AppNotificationType.reviewReceived => l10n.notificationTitleReviewReceived,
    AppNotificationType.bookingCancelledSalonClosed =>
      l10n.notificationTitleSalonClosed,
    AppNotificationType.bookingCancelledMasterRemoved =>
      l10n.notificationTitleMasterRemoved,
    AppNotificationType.unknown => l10n.notificationTitleUnknown,
  };

  /// The row's second line, or `null` when there is nothing honest to say (an
  /// unknown type carries no known params shape).
  ///
  /// A known type whose params are missing any field its template needs reads
  /// «Деталі більше недоступні» — the backend nulls them when the recipient
  /// lost access to the subject, and a half-filled sentence would mislead.
  static String? body(
    AppLocalizations l10n,
    AppNotification item, {
    required bool isClient,
  }) {
    final NotificationParams p = item.params;
    if (item.type == AppNotificationType.unknown) return null;

    if (item.type == AppNotificationType.inviteAccepted) {
      final String? subject = sanitize(p.subjectName);
      if (subject == null) {
        return l10n.notificationsParamsGone;
      }
      final String role = p.subjectRole == _salonAdminWire
          ? l10n.notificationRoleSalonAdmin
          : l10n.notificationRoleSalonMaster;
      return l10n.notificationBodyInviteAccepted(subject, role);
    }

    final String? counterpart = sanitize(p.counterpartName);
    final String? serviceName = sanitize(p.serviceName);
    final DateTime? startsAt = p.startsAt;
    if (counterpart == null || serviceName == null || startsAt == null) {
      return l10n.notificationsParamsGone;
    }
    final int extra = (p.serviceCount ?? 1) - 1;
    final String service = extra > 0
        ? l10n.notificationServiceWithExtra(serviceName, extra)
        : serviceName;
    final String when = startsAtLabel(startsAt);
    final bool rescheduled =
        item.type == AppNotificationType.bookingRescheduled;
    if (isClient) {
      return rescheduled
          ? l10n.notificationBodyClientRescheduled(counterpart, service, when)
          : l10n.notificationBodyClient(counterpart, service, when);
    }
    return rescheduled
        ? l10n.notificationBodyProviderRescheduled(counterpart, service, when)
        : l10n.notificationBodyProvider(counterpart, service, when);
  }

  // The code points are spelled as doubled-backslash escapes / char codes so
  // the SOURCE stays plain ASCII: a literal bidi character in a Dart string is
  // exactly what `text_direction_code_point_in_literal` forbids.
  static final RegExp _spaceLike = RegExp('[\\s\\u0085\\u2028\\u2029]+');

  /// Every control (`Cc`) and format (`Cf`) character — bidi controls and
  /// isolates, zero-width characters, soft hyphen, BOM, the tag block, the
  /// Egyptian / shorthand format controls — by Unicode category, EXCEPT ZWNJ /
  /// ZWJ (U+200C / U+200D), which emoji and several scripts need. Plus the
  /// blank-looking code points that are NOT `Cf`: Hangul fillers (U+115F,
  /// U+1160, U+3164, U+FFA0), braille blank (U+2800), U+FFF9..FFFC, combining
  /// grapheme joiner (U+034F) and the Khmer inherent vowels (U+17B4 / U+17B5).
  /// The escapes are doubled backslashes so the SOURCE stays plain ASCII.
  static final RegExp _invisible = RegExp(
    '(?![\\u200C\\u200D])[\\p{Cc}\\p{Cf}]'
    '|[\\u115F\\u1160\\u3164\\uFFA0\\u2800\\uFFF9-\\uFFFC\\u034F\\u17B4\\u17B5\\u{1D159}]',
    unicode: true,
  );

  /// A visible base character. A name with none is missing.
  static final RegExp _visible = RegExp(
    r'[\p{L}\p{N}\p{S}\p{P}]',
    unicode: true,
  );

  /// Longest value (in user-perceived characters) spliced into a sentence.
  static const int maxNameLength = 80;

  /// Most combining marks kept after one base character (zalgo defence).
  static const int maxCombiningRun = 2;

  /// Any mark (Mn / Mc / Me) by Unicode category, not by block, so Hebrew,
  /// Arabic, Cyrillic, Tibetan... marks are capped too. Variation selectors
  /// are also Mn; callers test [_isSelector] first.
  static final RegExp _mark = RegExp(r'\p{M}', unicode: true);

  static bool _isCombining(int r) => _mark.hasMatch(String.fromCharCode(r));

  static bool _isJoiner(int r) => r == 0x200C || r == 0x200D;

  /// Variation selectors: FE00..FE0F, Mongolian FVS (U+180B..180D) and the
  /// ideographic supplement (U+E0100..E01EF).
  static bool _isSelector(int r) =>
      (r >= 0xFE00 && r <= 0xFE0F) ||
      (r >= 0x180B && r <= 0x180D) ||
      (r >= 0xE0100 && r <= 0xE01EF);

  /// Drops every combining mark beyond [maxCombiningRun] in a row. ZWNJ / ZWJ
  /// and variation selectors are transparent to the run counter (they neither
  /// extend nor reset it), so interleaving them cannot defeat the cap;
  /// consecutive joiners collapse to one, and a base keeps one selector.
  static String _capMarks(String s) {
    final StringBuffer out = StringBuffer();
    int run = 0;
    bool prevJoiner = false;
    bool selectorSeen = false;
    // False at the start and right after a space: a mark there has no base
    // to attach to and would otherwise bind to the FSI / a separator.
    bool hasBase = false;
    for (final int r in s.runes) {
      if (_isJoiner(r)) {
        if (out.isEmpty || prevJoiner) continue;
        prevJoiner = true;
        out.writeCharCode(r);
        continue;
      }
      if (_isSelector(r)) {
        // At most one variation selector per base character.
        if (out.isEmpty || selectorSeen) continue;
        selectorSeen = true;
        out.writeCharCode(r);
        continue;
      }
      if (_isCombining(r)) {
        // A baseless mark is dropped outright and never counts toward the run.
        if (!hasBase) continue;
        run++;
        // A dropped mark writes nothing, so it must not separate two joiners.
        if (run > maxCombiningRun) continue;
      } else {
        run = 0;
        selectorSeen = false;
        hasBase = r != 0x20;
      }
      prevJoiner = false;
      out.writeCharCode(r);
    }
    return out.toString();
  }

  static final String _fsi = String.fromCharCode(0x2068);
  static final String _pdi = String.fromCharCode(0x2069);

  /// Cleans a SERVER-supplied name before it is spliced into a sentence.
  ///
  /// Pipeline: raw unit cap, strip control / format / filler characters,
  /// collapse whitespace and trim, cap marks / joiners / selectors, then cap
  /// to [maxNameLength] graphemes and [maxOutputUnits] units (whole graphemes,
  /// «…» re-appended within the budget), and only THEN check the final text
  /// has a visible base character. Wraps the result in FSI…PDI so even a
  /// legitimate right-to-left name cannot reorder the sentence. `null` when
  /// nothing visible is left (the caller treats that like a missing field).
  static String? sanitize(String? raw) {
    if (raw == null) return null;
    final String clean = _capMarks(
      _truncateUnits(raw, maxRawUnits)
          .replaceAll(_spaceLike, ' ')
          .replaceAll(_invisible, '')
          .replaceAll(_spaceLike, ' ')
          .trim(),
    );
    final String? capped = _capDisplay(clean);
    if (capped == null) return null;
    return '$_fsi$capped$_pdi';
  }

  /// Caps [s] to [maxNameLength] graphemes and [maxOutputUnits] UTF-16 units,
  /// cutting only between graphemes. A cut re-appends «…» inside the budget
  /// and never leaves a dangling joiner / selector / mark before it. `null`
  /// when the kept text has no visible base (a lone «…» does not count).
  static String? _capDisplay(String s) {
    String head = s;
    bool cut = false;
    // Graphemes never outnumber UTF-16 units, so a short string needs no scan.
    if (s.length > maxNameLength) {
      final List<String> kept = <String>[];
      int units = 0;
      for (final String g in s.characters) {
        if (kept.length == maxNameLength || units + g.length > maxOutputUnits) {
          cut = true;
          break;
        }
        kept.add(g);
        units += g.length;
      }
      if (cut) {
        while (kept.isNotEmpty && units > maxOutputUnits - 1) {
          units -= kept.removeLast().length;
        }
        head = _trimDangling(kept.join()).trimRight();
      }
    }
    if (!_visible.hasMatch(head)) return null;
    return cut ? '$head…' : head;
  }

  /// Drops trailing joiners, variation selectors and combining marks.
  static String _trimDangling(String s) {
    final List<int> r = s.runes.toList();
    while (r.isNotEmpty &&
        (_isJoiner(r.last) || _isSelector(r.last) || _isCombining(r.last))) {
      r.removeLast();
    }
    return String.fromCharCodes(r);
  }

  /// Hard bound on the raw input, in UTF-16 code units, before any pass runs.
  static const int maxRawUnits = 1024;

  /// Hard bound on the output: 80 graphemes x 4 UTF-16 units.
  static const int maxOutputUnits = 320;

  /// Cuts [s] to at most [max] UTF-16 units, never splitting a surrogate pair.
  static String _truncateUnits(String s, int max) {
    if (s.length <= max) return s;
    int end = max;
    final int last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    return s.substring(0, end);
  }

  /// «пт, 3 жовтня, 14:30», in Europe/Kyiv.
  static String startsAtLabel(DateTime startsAt) {
    final DateTime local = toBeauticaTime(startsAt);
    return '${weekdayAbbrev(local.weekday)}, ${local.day} '
        '${monthGenitive(local.month)}, ${formatSlotTime(startsAt)}';
  }

  /// The row timestamp, `HH:mm` in Europe/Kyiv.
  static String time(DateTime createdAt) => formatSlotTime(createdAt);

  /// Solid-fill rounded glyph per type (the nav/icon convention is solid,
  /// never stroked).
  static IconData glyph(AppNotificationType type) => switch (type) {
    AppNotificationType.bookingCreated => Icons.event_available_rounded,
    AppNotificationType.bookingCancelledByClient => Icons.event_busy_rounded,
    AppNotificationType.bookingDeclined => Icons.event_busy_rounded,
    AppNotificationType.bookingRescheduled => Icons.update_rounded,
    AppNotificationType.inviteAccepted => Icons.group_add_rounded,
    AppNotificationType.bookingNotCompleted => Icons.person_off_rounded,
    AppNotificationType.reviewRequested => Icons.rate_review_rounded,
    AppNotificationType.reviewReceived => Icons.star_rounded,
    AppNotificationType.bookingCancelledSalonClosed => Icons.storefront_rounded,
    AppNotificationType.bookingCancelledMasterRemoved =>
      Icons.person_remove_rounded,
    AppNotificationType.unknown => Icons.notifications_rounded,
  };

  /// «Сьогодні» / «Вчора» / «Пн, 28 вересня» for a Kyiv calendar day token
  /// ([day] and [today] come from `kyivDayOf` / `kyivToday`).
  static String dayHeader(AppLocalizations l10n, DateTime day, DateTime today) {
    if (day == today) return l10n.relativeDateToday;
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return l10n.relativeDateYesterday;
    }
    return '${ukCapitalize(weekdayAbbrev(day.weekday))}, ${day.day} '
        '${monthGenitive(day.month)}';
  }
}
