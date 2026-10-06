// Phase 9.7 — the master photo URL reaches the shared MasterAvatarBadge from
// every booking identity widget (badge, shell, strip, column chip, feedback
// card); null keeps the gradient glyph. Asserted on the RENDERED image
// provider's URL.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_avatar_badge.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_column_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_feedback_card.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip_shell.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fake_media_cache.dart';
import '../../../../helpers/pump_app.dart';
import '../../../../helpers/rendered_image_url.dart';

const String _url = 'https://media.test/avatars/m1.png';

Booking _booking({String? avatarUrl}) {
  final DateTime start = DateTime.utc(2000, 1, 1, 15);
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterType: 'INDEPENDENT_MASTER',
    masterAvatarUrl: avatarUrl,
    serviceId: 's1',
    serviceName: 'Манікюр',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Київ',
    street: 'вул. Хрещатик',
    buildingNo: '12',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.completed,
    canReview: true,
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpApp(Align(alignment: Alignment.topLeft, child: child));
  await tester.pump();
}

MasterColumnEntry _entry({String? imageUrl}) => MasterColumnEntry(
  masterId: 'm1',
  name: 'Олена Ковальчук',
  type: MasterType.salonMaster,
  bookingCount: 2,
  imageUrl: imageUrl,
);

SalonMasterSchedule _schedule({String? avatarUrl}) => SalonMasterSchedule(
  masterId: 'm1',
  firstName: 'Софія',
  lastName: 'Мельник',
  type: MasterType.salonMaster,
  avatarUrl: avatarUrl,
  services: const [],
  orderedMasterServiceIds: const <String>[],
);

Master _master({String? avatarUrl}) => Master(
  id: 'm1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  reviewCount: 0,
  type: MasterType.independentMaster,
  avatarUrl: avatarUrl,
);

void main() {
  late FakeMediaCacheManager media;

  setUp(() {
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    media = FakeMediaCacheManager(mediaLoaded);
    debugMediaCacheManager = media;
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  group('MasterAvatarBadge', () {
    for (final bool bordered in <bool>[false, true]) {
      testWidgets('imageUrl renders RemoteImage (bordered: $bordered)', (
        tester,
      ) async {
        await _pump(
          tester,
          MasterAvatarBadge(imageUrl: _url, bordered: bordered),
        );
        expect(find.byType(RemoteImage), findsOneWidget);
        expect(renderedImageUrls(tester), <String>[_url]);
      });
    }

    testWidgets('null keeps the glyph and renders no image', (tester) async {
      await _pump(tester, const MasterAvatarBadge());
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('a non-allow-listed host falls back to the glyph, no fetch', (
      tester,
    ) async {
      await _pump(
        tester,
        const MasterAvatarBadge(imageUrl: 'https://evil.test/p.png'),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
      expect(media.getFileStreamCalls, 0);
    });

    testWidgets('a failed load falls back to the glyph', (tester) async {
      debugMediaCacheManager = FakeMediaCacheManager(mediaFetchError);
      await _pump(tester, const MasterAvatarBadge(imageUrl: _url));
      await tester.pump();
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });
  });

  testWidgets('MasterStripShell forwards avatarImageUrl to the badge', (
    tester,
  ) async {
    await _pump(
      tester,
      const MasterStripShell(
        semanticsLabel: 's',
        name: 'Софія',
        avatarImageUrl: _url,
      ),
    );
    expect(renderedImageUrls(tester), <String>[_url]);
  });

  testWidgets('MasterStrip.fromBooking threads Booking.masterAvatarUrl', (
    tester,
  ) async {
    await _pump(tester, MasterStrip.fromBooking(_booking(avatarUrl: _url)));
    expect(renderedImageUrls(tester), <String>[_url]);
  });

  testWidgets('MasterStrip.fromBooking without a URL renders no image', (
    tester,
  ) async {
    await _pump(tester, MasterStrip.fromBooking(_booking()));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'MasterStrip.fromSchedule threads SalonMasterSchedule.avatarUrl',
    (tester) async {
      await _pump(tester, MasterStrip.fromSchedule(_schedule(avatarUrl: _url)));
      expect(renderedImageUrls(tester), <String>[_url]);
    },
  );

  testWidgets('MasterStrip.fromSchedule without a URL renders no image', (
    tester,
  ) async {
    await _pump(tester, MasterStrip.fromSchedule(_schedule()));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
  });

  testWidgets('MasterStrip.fromMaster threads Master.avatarUrl', (
    tester,
  ) async {
    await _pump(tester, MasterStrip.fromMaster(_master(avatarUrl: _url)));
    expect(renderedImageUrls(tester), <String>[_url]);
  });

  testWidgets('MasterStrip(avatarImageUrl:) reaches the badge', (tester) async {
    await _pump(
      tester,
      const MasterStrip(
        name: 'Софія',
        type: MasterType.salonMaster,
        avatarImageUrl: _url,
      ),
    );
    expect(renderedImageUrls(tester), <String>[_url]);
  });

  testWidgets('MasterColumnStrip chip shows the entry photo', (tester) async {
    await _pump(
      tester,
      MasterColumnStrip(
        entries: <MasterColumnEntry>[_entry(imageUrl: _url)],
        columnWidth: 160,
        gutter: 8,
      ),
    );
    expect(renderedImageUrls(tester), <String>[_url]);
  });

  testWidgets('MasterColumnStrip chip without a URL renders no image', (
    tester,
  ) async {
    await _pump(
      tester,
      MasterColumnStrip(
        entries: <MasterColumnEntry>[_entry()],
        columnWidth: 160,
        gutter: 8,
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(MasterAvatarBadge), findsOneWidget);
  });

  testWidgets('MasterFeedbackCard forwards avatarImageUrl to the badge', (
    tester,
  ) async {
    await _pump(
      tester,
      const MasterFeedbackCard(
        name: 'Софія',
        roleLabel: 'Майстер',
        visitContext: 'Манікюр · 10 липня',
        avatarImageUrl: _url,
      ),
    );
    expect(renderedImageUrls(tester), <String>[_url]);
  });

  testWidgets('MasterFeedbackCard without a URL renders no image', (
    tester,
  ) async {
    await _pump(
      tester,
      const MasterFeedbackCard(
        name: 'Софія',
        roleLabel: 'Майстер',
        visitContext: 'Манікюр · 10 липня',
      ),
    );
    expect(find.byType(Image), findsNothing);
  });
}
