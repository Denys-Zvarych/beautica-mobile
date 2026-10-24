// Phase 414 — pixel lock for «Посилання для запису» and its hub row.
//
// NEW baselines (no existing image moved):
//   • booking_link_screen_master_*      — INDEPENDENT_MASTER, one MASTER card
//   • booking_link_screen_owner_*       — SALON_OWNER, two SALON cards
//                                         (no master card — 2026-10-20)
//   • booking_link_screen_not_bookable_* — D6 warning + setup link
//   • booking_link_screen_loading_*     — shimmer skeleton
//   • settings_hub_master_booking_links_360_1x — hub with the row shown
//   • success_secondary_button_*        — the PROMOTED shared button at rest,
//     plus a half-width + 1.3x case exercising the additive ellipsis.
//
// Phase 415 — NEW baselines:
//   • booking_link_screen_revoked_master_360_1x — revoked MASTER card
//   • booking_link_screen_revoked_owner_360_1x  — one SALON revoked, the
//     other active (regenerate glyph in its header)
// The 414 screen baselines above MOVE in 415: every active card the screen
// renders now carries the header regenerate glyph (48 dp target → header
// row 42 → 48 dp, content below shifts 6 dp). Baseline refresh is the
// orchestrator's / user's call.
//
// The promoted button's ORIGINAL screens are locked by the unchanged
// `booking_slot_flow_golden_test.dart` success-* baselines, re-run green
// after the promotion.

import 'dart:async';

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_link_screen.dart';
import 'package:beautica_mobile/features/booking_links/presentation/booking_links_provider.dart';
import 'package:beautica_mobile/features/master/presentation/settings_hub_screen.dart';
import 'package:beautica_mobile/shared/widgets/success_secondary_button.dart';
import 'package:flutter/material.dart' hide BoxConstraints, Size;

import '../helpers/fakes/fake_notification_repository.dart' show FixedRoleAuth;
import 'helpers/golden_pump.dart';

const BookingLink _master = BookingLink(
  kind: BookingLinkKind.master,
  slug: 'olena-koval-x7k2',
  url: 'https://beautica.app/book/olena-koval-x7k2',
  displayName: 'Олена Коваль',
  bookable: true,
);

const BookingLink _salonA = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'lumiere-kyiv',
  url: 'https://beautica.app/book/s/lumiere-kyiv',
  displayName: 'Lumière',
  salonId: 'salon-a',
  bookable: true,
);

const BookingLink _salonB = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'beauty-loft-na-podoli-8r2c',
  url: 'https://beautica.app/book/s/beauty-loft-na-podoli-8r2c',
  displayName: 'Beauty Loft на Подолі',
  salonId: 'salon-b',
  bookable: true,
);

List<Object> _overrides(UserRole role, Future<BookingLinks> Function() load) =>
    <Object>[
      authProvider.overrideWith(() => FixedRoleAuth(role)),
      bookingLinksProvider.overrideWith((_) => load()),
      // The hub row reads the per-account family directly (cache split).
      bookingLinksForAccountProvider.overrideWith((_, _) => load()),
    ];

void main() {
  const double width = 360;
  const Size screen = Size(width, 900);

  for (final double scale in <double>[1.0, 1.3]) {
    final String s = scale == 1.0 ? '1x' : '1_3x';

    goldenTest(
      'booking links — independent master ($s)',
      fileName: 'booking_link_screen_master_360_$s',
      constraints: BoxConstraints.tight(screen),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: _overrides(
          UserRole.independentMaster,
          () async => const BookingLinks(
            shareEnabled: true,
            links: <BookingLink>[_master],
          ),
        ),
      ),
      builder: () => const BookingLinkScreen(),
    );

    goldenTest(
      'booking links — owner, two salons ($s)',
      fileName: 'booking_link_screen_owner_360_$s',
      constraints: BoxConstraints.tight(const Size(width, 1100)),
      textScaleFactor: scale,
      pumpWidget: goldenPumpWidget(
        width: width,
        overrides: _overrides(
          UserRole.salonOwner,
          () async => const BookingLinks(
            shareEnabled: true,
            links: <BookingLink>[_salonA, _salonB],
          ),
        ),
      ),
      builder: () => const BookingLinkScreen(),
    );
  }

  goldenTest(
    'booking links — not bookable (master)',
    fileName: 'booking_link_screen_not_bookable_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        UserRole.independentMaster,
        () async => BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master.copyWith(bookable: false)],
        ),
      ),
    ),
    builder: () => const BookingLinkScreen(),
  );

  goldenTest(
    'booking links — revoked master (415)',
    fileName: 'booking_link_screen_revoked_master_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        UserRole.independentMaster,
        () async => const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[
            BookingLink(
              kind: BookingLinkKind.master,
              slug: null,
              url: null,
              displayName: 'Олена Коваль',
              bookable: false,
              status: BookingLinkStatus.revoked,
            ),
          ],
        ),
      ),
    ),
    builder: () => const BookingLinkScreen(),
  );

  goldenTest(
    'booking links — owner, one salon revoked (415)',
    fileName: 'booking_link_screen_revoked_owner_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 1100)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        UserRole.salonOwner,
        () async => BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[
            _salonA.copyWith(
              slug: null,
              url: null,
              bookable: false,
              status: BookingLinkStatus.revoked,
            ),
            _salonB,
          ],
        ),
      ),
    ),
    builder: () => const BookingLinkScreen(),
  );

  goldenTest(
    'booking links — loading',
    fileName: 'booking_link_screen_loading_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      settle: false,
      overrides: _overrides(
        UserRole.independentMaster,
        () => Completer<BookingLinks>().future,
      ),
    ),
    pumpBeforeTest: pumpOnce,
    builder: () => const BookingLinkScreen(),
  );

  goldenTest(
    'settings hub — master config with the booking links row',
    fileName: 'settings_hub_master_booking_links_360_1x',
    constraints: BoxConstraints.tight(const Size(width, 840)),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        UserRole.independentMaster,
        () async => const BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master],
        ),
      ),
    ),
    builder: () => const SettingsHubScreen(showBookingLinks: true),
  );

  goldenTest(
    'success secondary button — promoted shared widget',
    fileName: 'success_secondary_button',
    constraints: const BoxConstraints(maxWidth: width),
    pumpWidget: goldenPumpWidget(width: width),
    builder: () => GoldenTestGroup(
      columns: 1,
      children: <Widget>[
        GoldenTestScenario(
          name: 'full width, 1x',
          child: SizedBox(
            width: 312,
            child: SuccessSecondaryButton(
              buttonKey: const Key('g-full'),
              label: 'Мої записи',
              icon: Icons.event_note_rounded,
              onPressed: () {},
            ),
          ),
        ),
        GoldenTestScenario(
          name: 'half width, 1.3x (ellipsis guard)',
          child: Builder(
            builder: (BuildContext context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: SizedBox(
                width: 130,
                child: SuccessSecondaryButton(
                  buttonKey: const Key('g-half'),
                  label: 'Копіювати посилання',
                  icon: Icons.content_copy_rounded,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
