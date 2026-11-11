// Shared harness for the split `service_setup_screen_*_test.dart` files
// (moved verbatim from the former single `service_setup_screen_test.dart`;
// only the leading `_` of the shared top-level names was dropped so the
// split files can import them).
//
// First-time service setup — widget tests for [ServiceSetupScreen].
//
// [ServiceSetupScreen] is a ConsumerStatefulWidget driving:
//   • the empty-state catalogue loader (approvedCategoriesProvider): loading /
//     error+retry / data;
//   • lazy per-category service-type expansion (serviceTypesProvider family);
//   • per-row include toggles + a footer CTA that counts included rows and is
//     disabled at zero;
//   • a bulk save through serviceSetupProvider → ServiceRepository.bulkCreate.
//
// Strategy:
//   • Override approvedCategoriesProvider + the serviceTypesProvider(slug)
//     family + serviceRepositoryProvider (mocktail) so NOTHING hits a network.
//   • Mount inside a GoRouter so context.go(RouteNames.services) resolves; the
//     screen uses go_router, never Navigator.
//   • Find widgets by Key per the project convention: cat_$name, group_$slug,
//     setup_row_$id, rowwrap_$id, btn-setup-save.
//   • ScreenProtector lifecycle calls are guarded by !kDebugMode, so they are
//     never invoked in tests.

import 'dart:async';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class MockServiceRepository extends Mock implements ServiceRepository {}

// ── Stub data ────────────────────────────────────────────────────────────────

const manicure = ServiceCategoryOption(
  name: 'MANICURE',
  displayName: 'Манікюр',
);
const hair = ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся');

/// A pathological "uncategorised" category — both the wire slug and the
/// display name blank. `approvedCategoriesProvider` sources from
/// `GET /service-categories/approved`, which gates to ~20-24 named platform
/// categories, so this shape is not expected from that endpoint today; it
/// exists to prove the SCREEN's own wiring onto `categoryIconOrNullFor`
/// (mobile-qa gap-closure, 2026-08-27) rather than only the widget's already
/// covered `iconAsset: null` handling (`service_setup_widgets_test.dart`).
/// If a future edit ever swaps this screen's call sites from
/// `categoryIconOrNullFor` to the never-null `categoryIconFor`, this is the
/// test that goes red — a blank category would otherwise silently render the
/// cosmetology fallback glyph instead of no icon.
const blank = ServiceCategoryOption(name: '', displayName: '');

const typeClassic = ServiceTypeOption(
  id: 'type-classic',
  slug: 'CLASSIC',
  nameUk: 'Класичний манікюр',
  categoryName: 'MANICURE',
);
const typeGel = ServiceTypeOption(
  id: 'type-gel',
  slug: 'GEL',
  nameUk: 'Гель-лак',
  categoryName: 'MANICURE',
);
const typeCut = ServiceTypeOption(
  id: 'type-cut',
  slug: 'CUT',
  nameUk: 'Стрижка',
  categoryName: 'HAIR',
);
// A THIRD manicure type — used by the submitted-index-mapping regression so an
// EXCLUDED on-screen row can sit between/before included ones, making the
// submitted index provably differ from the on-screen index.
const typeArt = ServiceTypeOption(
  id: 'type-art',
  slug: 'ART',
  nameUk: 'Художній розпис',
  categoryName: 'MANICURE',
);

const createdService = <MasterService>[
  MasterService(
    id: 'svc-1',
    serviceDefId: 'def-1',
    name: 'Класичний манікюр',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
  ),
];

// ── APPEND-mode fixtures ─────────────────────────────────────────────────────
//
// `servicesListProvider` is the SNAPSHOT source [_ServiceSetupScreenState]
// reads ONCE in initState to decide (a) SETUP vs APPEND framing and (b) which
// service-type ids are already owned and must therefore be un-includable.

/// A service the master already offers whose `serviceTypeId` matches
/// [typeClassic] — so expanding MANICURE must render classic as already-added.
const ownsClassic = <MasterService>[
  MasterService(
    id: 'svc-owned-classic',
    serviceDefId: 'def-owned-classic',
    name: 'Класичний манікюр',
    serviceTypeId: 'type-classic',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
  ),
];

/// Owns BOTH manicure types — the "every type in this category is already
/// added" case.
const ownsClassicAndGel = <MasterService>[
  ...ownsClassic,
  MasterService(
    id: 'svc-owned-gel',
    serviceDefId: 'def-owned-gel',
    name: 'Гель-лак',
    serviceTypeId: 'type-gel',
    durationMinutes: 90,
    priceMin: 700,
    priceDisplay: '700 ₴',
  ),
];

/// A non-empty catalogue whose single service carries NO `serviceTypeId` — the
/// pre-Phase-16.3 shape, where a master's service predates the platform
/// service-type join.
///
/// Its `name` is deliberately IDENTICAL to [typeClassic]'s `nameUk`. The
/// exclusion is specified to key on the service-type ID and nothing else, so an
/// untyped row must contribute nothing to the owned set even when its display
/// name matches a type exactly. That is the documented degradation direction:
/// UNDER-blocking (the type stays selectable and the save may 409, which is
/// recoverable and explained) rather than OVER-blocking (hiding a service the
/// master then cannot add by any route at all — the setup screen is the ONLY
/// "add services" surface now that the single-create form is deleted).
const ownsUntypedLegacyRow = <MasterService>[
  MasterService(
    id: 'svc-legacy-untyped',
    serviceDefId: 'def-legacy-untyped',
    // Same display name as typeClassic.nameUk — a name-based exclusion would
    // wrongly match here.
    name: 'Класичний манікюр',
    durationMinutes: 60,
    priceMin: 500,
    priceDisplay: '500 ₴',
  ),
];

/// A non-empty catalogue whose single service matches NONE of the fixture
/// service-types — APPEND framing WITHOUT any row exclusion, so the copy switch
/// is isolated from the exclusion behaviour.
const ownsUnrelated = <MasterService>[
  MasterService(
    id: 'svc-owned-other',
    serviceDefId: 'def-owned-other',
    name: 'Педикюр',
    serviceTypeId: 'type-unrelated',
    durationMinutes: 60,
    priceMin: 400,
    priceDisplay: '400 ₴',
  ),
];

/// Seeds [servicesListProvider] so that the very FIRST synchronous
/// `ref.read(servicesListProvider).value` — which is exactly what the screen
/// does in `initState` — already sees [AsyncData].
///
/// [SynchronousFuture] is load-bearing and NOT interchangeable with
/// `Future.value` / an `async` body: riverpod resolves a returned `Future`
/// through `.then`, so a normally-async build leaves the provider in
/// [AsyncLoading] for the whole first frame and `.value` reads back null — the
/// screen would silently fall into SETUP mode with an EMPTY owned-id set and
/// every append test would pass for the wrong reason. `SynchronousFuture.then`
/// runs its callback inline, so the state is [AsyncData] before `ref.read`
/// returns. Verified empirically (a `Future.value` seed reads
/// `AsyncLoading`, this one reads `AsyncData`).
///
/// This mirrors production: the services list has already resolved this
/// keepAlive provider before it pushes the setup screen, so the read is a cache
/// hit on the first frame there too.
class SeededServicesList extends ServicesList {
  SeededServicesList(this.seed);

  final List<MasterService> seed;

  @override
  Future<List<MasterService>> build() => SynchronousFuture(seed);
}

/// A [ServicesList] whose successive BUILDS answer with successive seeds — the
/// "the catalogue changed under us" shape a fixed seed cannot express.
///
/// `_flagRowsNowOwned` re-reads `servicesListProvider.future` AFTER the 409
/// handler has invalidated it, so pinning that path requires the second read to
/// return something the first did not. With a fixed seed the newly-owned type
/// would already be in the initState snapshot, `alreadyAdded` would be seeded
/// true, the row would be un-includable, and the 409 could never be reached —
/// the test would pass vacuously.
///
/// The final seed repeats for any further build, so an extra invalidate (the
/// 409 handler invalidates `servicesListProvider` and
/// `masterServiceCatalogProvider` together) can never run the list off the end.
class MutatingServicesList extends ServicesList {
  MutatingServicesList(this.seeds);

  final List<List<MasterService>> seeds;

  /// Build count — asserted by the tests below so a change that stops
  /// re-reading the catalogue is visible as a count, not only as a missing flag.
  int builds = 0;

  @override
  Future<List<MasterService>> build() {
    final seed = seeds[builds.clamp(0, seeds.length - 1)];
    builds++;
    // SynchronousFuture for the same reason [SeededServicesList] uses one —
    // see its doc comment; an async build leaves initState reading null.
    return SynchronousFuture(seed);
  }
}

// ── Harness ──────────────────────────────────────────────────────────────────

class Harness {
  Harness() : repo = MockServiceRepository(), pushedRoutes = <String>[];

  final MockServiceRepository repo;
  final List<String> pushedRoutes;

  /// A router that mounts the setup screen at /services/setup and records
  /// navigation to /services so the success/conflict-redirect paths are
  /// observable without a real services screen.
  GoRouter router() => GoRouter(
    initialLocation: RouteNames.serviceSetup,
    routes: <RouteBase>[
      GoRoute(
        path: RouteNames.serviceSetup,
        builder: (_, _) => const ServiceSetupScreen(),
      ),
      GoRoute(
        path: RouteNames.services,
        builder: (_, _) {
          pushedRoutes.add(RouteNames.services);
          return const Scaffold(body: Text('SERVICES_LIST_STUB'));
        },
      ),
    ],
  );

  List<Object> overrides({
    AsyncValue<List<ServiceCategoryOption>>? categories,
    Map<String, FutureOr<List<ServiceTypeOption>>>? typesBySlug,
    List<MasterService>? existingServices,
  }) {
    final cat = categories ?? const AsyncData(<ServiceCategoryOption>[]);
    return <Object>[
      serviceRepositoryProvider.overrideWithValue(repo),
      // Only seeded when a test cares about SETUP-vs-APPEND: omitting it leaves
      // the real (repository-backed) provider in place, which is what the 32
      // pre-existing tests already exercise.
      if (existingServices != null)
        servicesListProvider.overrideWith(
          () => SeededServicesList(existingServices),
        ),
      approvedCategoriesProvider.overrideWith(
        (ref) => cat.when(
          data: (v) => v,
          loading: () => Completer<List<ServiceCategoryOption>>().future,
          error: (e, _) => Future<List<ServiceCategoryOption>>.error(e),
        ),
      ),
      if (typesBySlug != null)
        for (final entry in typesBySlug.entries)
          serviceTypesProvider(entry.key).overrideWith((ref) => entry.value),
    ];
  }
}

Future<void> pump(
  WidgetTester tester,
  Harness h, {
  required List<Object> overrides,
  Size? surfaceSize,
}) async {
  if (surfaceSize != null) {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    ProviderScope(
      retry: beauticaProviderRetry,
      overrides: overrides.cast(),
      child: MediaQuery(
        data: MediaQueryData(size: surfaceSize ?? const Size(800, 1200)),
        child: MaterialApp.router(
          routerConfig: h.router(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
        ),
      ),
    ),
  );
}

/// Toggles a service-type row's include switch ON.
///
/// The include switch ([_IncludeSwitch]) is a `Semantics(button, toggled,
/// label)` wrapping a `GestureDetector`. While a row is OFF (collapsed) it is
/// the ONLY `GestureDetector` in that row's card, so `.last` reliably targets
/// it regardless of any pricing-toggle GestureDetectors that appear once the
/// row expands.
Future<void> toggleRowOn(WidgetTester tester, String typeId) async {
  final switchFinder = find
      .descendant(
        of: find.byKey(Key('setup_row_$typeId')),
        matching: find.byType(GestureDetector),
      )
      .last;
  // Fully reveal the switch before tapping. With the reduced type scale the
  // list is more compact, so a prior `scrollUntilVisible` can leave the row's
  // switch (bottom-right of the card) only partially on-screen, making its
  // center un-hittable. `ensureVisible` is a no-op when already fully visible.
  await tester.ensureVisible(switchFinder);
  await tester.pumpAndSettle();
  await tester.tap(switchFinder);
  await tester.pumpAndSettle();
}

/// Taps the row's include switch regardless of whether the card is currently
/// expanded. Unlike [toggleRowOn]'s `.last`-GestureDetector heuristic (which is
/// only unambiguous while the row is OFF / collapsed), this targets the include
/// switch precisely: it is the GestureDetector nested inside the row's
/// `Semantics(toggled: …)` (the only toggled Semantics in the card — the pricing
/// mode toggle exposes no `toggled` flag), so it flips an ON+expanded row OFF
/// deterministically without colliding with the pricing-mode toggle's own
/// opaque GestureDetector.
Future<void> tapIncludeSwitch(WidgetTester tester, String typeId) async {
  final toggledSemantics = find.descendant(
    of: find.byKey(Key('setup_row_$typeId')),
    matching: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.toggled != null,
    ),
  );
  final switchFinder = find
      .descendant(of: toggledSemantics, matching: find.byType(GestureDetector))
      .last;
  await tester.tap(switchFinder);
  await tester.pumpAndSettle();
}

/// Reads the footer save button's `onPressed` — null means the CTA is disabled
/// (and tapping it is a guaranteed no-op).
VoidCallback? saveOnPressed(WidgetTester tester) {
  final button = tester.widget<NeumorphicButton>(
    find.byKey(const Key('btn-setup-save')),
  );
  return button.onPressed;
}

/// True when the service-type row card paints its error rim — i.e. the card's
/// own [AnimatedContainer] has a non-transparent border. The card sets
/// `Border.all(color: flagged ? BrandColors.error : Colors.transparent)`, so a
/// transparent (or absent) border means no rim. Targets the FIRST
/// AnimatedContainer under the row key (the card face) so the include-switch's
/// inner AnimatedContainer is never mistaken for the rim.
bool rowHasErrorRim(WidgetTester tester, String typeId) {
  final container = tester
      .widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byKey(Key('setup_row_$typeId')),
          matching: find.byType(AnimatedContainer),
        ),
      )
      .first;
  final decoration = container.decoration;
  if (decoration is! BoxDecoration) return false;
  final border = decoration.border;
  if (border is! Border) return false;
  return border.top.color.a != 0;
}

/// Enters a duration + a fixed price into a row's expanded fields, scoping both
/// entries to the row's own card (all included rows share the same
/// `pricing-fixed-amount` key, so the entry MUST be scoped or it collides).
Future<void> fillRowFixed(
  WidgetTester tester,
  String typeId, {
  required String duration,
  required String price,
}) async {
  await tester.enterText(
    find
        .descendant(
          of: find.byKey(Key('setup_row_$typeId')),
          matching: find.byType(TextField),
        )
        .first,
    duration,
  );
  await tester.enterText(
    find.descendant(
      of: find.byKey(Key('setup_row_$typeId')),
      matching: find.byKey(const Key('pricing-fixed-amount')),
    ),
    price,
  );
  await tester.pumpAndSettle();
}

/// The text currently in a row's DURATION field, read back off the live
/// controller.
///
/// Reading the CONTROLLER rather than a rendered string is the point: it is the
/// controller's survival that distinguishes a row carried over by identity from
/// one rebuilt from scratch, and a rebuilt row renders an empty field that no
/// `find.text` can assert the absence of unambiguously.
String? durationText(WidgetTester tester, String typeId) => tester
    .widget<TextField>(
      find
          .descendant(
            of: find.byKey(Key('setup_row_$typeId')),
            matching: find.byType(TextField),
          )
          .first,
    )
    .controller
    ?.text;

/// The text currently in a row's FIXED-price field.
///
/// The `pricing-fixed-amount` key sits on the neumorphic INSET wrapper, not on
/// the field itself, so the [TextField] is one level further down — `enterText`
/// resolves that on its own, a `widget<TextField>` read does not.
String? fixedPriceText(WidgetTester tester, String typeId) => tester
    .widget<TextField>(
      find.descendant(
        of: find.descendant(
          of: find.byKey(Key('setup_row_$typeId')),
          matching: find.byKey(const Key('pricing-fixed-amount')),
        ),
        matching: find.byType(TextField),
      ),
    )
    .controller
    ?.text;

/// A finder for the text `message` rendered INSIDE a specific row's card — so a
/// server/inline error can be asserted to land on the RIGHT row (and be absent
/// from the others) regardless of where else the same string renders.
Finder textInRow(String typeId, String message) => find.descendant(
  of: find.byKey(Key('setup_row_$typeId')),
  matching: find.text(message),
);

/// True when [style] carries the ROLE reserved for a collapsed row's
/// off-state sub-label: [VelvetText.svcCaptionNote] — the exact style
/// `service_setup_widgets.dart`'s `else if (owned || ownedNow)`
/// branch (~:704-724) renders into. The `ownedNow` arm only overrides
/// `fontWeight`/`color` via `copyWith`, so `fontSize`/`height`/`fontFamily`
/// still pin the base token for both branches.
///
/// Verified unique within a collapsed row's `Text` descendants: the row name
/// uses `subheading16` (fontSize 13, Comfortaa), the header-flag line uses
/// `feedback()` (fontSize 13, Nunito 700) and is unreachable while
/// `on == false` regardless (`showHeaderFlag` requires `clientFlagged`, which
/// requires `on`), and `svcCaptionNote` is not used anywhere else in
/// `service_setup_widgets.dart`.
bool isOffStateSubLabelStyle(TextStyle? style) =>
    style != null &&
    style.fontSize == VelvetText.svcCaptionNote.fontSize &&
    style.height == VelvetText.svcCaptionNote.height &&
    style.fontFamily == VelvetText.svcCaptionNote.fontFamily;

/// Asserts a COLLAPSED row (`on == false`) renders no off-state sub-label,
/// checked two ways:
///
///  1. ROLE (content-independent, primary): no `Text` descendant of the row
///     carries [isOffStateSubLabelStyle]. This trips on ANY reinstated
///     sub-label regardless of its string, l10n key, or locale — unlike a
///     literal/key-based check — while an unrelated `Text` (a badge, a price
///     hint, a duration chip) later added to the row with a DIFFERENT style
///     does not false-FAIL it.
///  2. FACT (additional — kept for locked/ownedNow exclusivity coverage): the
///     row renders neither [AppLocalizations.serviceSetupRowAlreadyAdded] nor
///     [AppLocalizations.serviceSetupRowAlreadyInMenu] specifically (via
///     [textInRow]).
void expectRowHasNoOffStateSubLabel(
  WidgetTester tester,
  AppLocalizations l10n,
  String typeId,
) {
  expect(
    find.descendant(
      of: find.byKey(Key('setup_row_$typeId')),
      matching: find.byWidgetPredicate(
        (Widget w) => w is Text && isOffStateSubLabelStyle(w.style),
      ),
    ),
    findsNothing,
    reason:
        'a merely-off row must render no Text carrying the off-state '
        'sub-label ROLE style, regardless of its copy/locale',
  );
  expect(textInRow(typeId, l10n.serviceSetupRowAlreadyAdded), findsNothing);
  expect(textInRow(typeId, l10n.serviceSetupRowAlreadyInMenu), findsNothing);
}

/// Taps a category chip and settles — the shared version of the `expandManicure`
/// closure the older groups each define locally.
Future<void> expand(WidgetTester tester, String slug) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>('cat_$slug')));
  await tester.pumpAndSettle();
}

/// True when `finder`'s render box is laid out AND vertically overlaps the
/// scroll viewport (the [Scrollable]'s on-screen rect — the true fold). Used to
/// assert a row is below the fold before a blocked save, then visible after the
/// scroll-to-flagged behaviour runs. Returns false when the row is unlaid-out
/// (lazy SliverList never built it because it is off-screen).
bool isInViewport(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final viewport = tester.getRect(find.byType(Scrollable).first);
  final rect = tester.getRect(finder);
  // Overlaps when its top is above the viewport bottom and its bottom is below
  // the viewport top.
  return rect.top < viewport.bottom && rect.bottom > viewport.top;
}
