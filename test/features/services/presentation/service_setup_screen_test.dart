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

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_setup_screen.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/category_request_dialog.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_setup_widgets.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_type_suggestion_dialog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import '../../../helpers/velvet_snack_matchers.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockServiceRepository extends Mock implements ServiceRepository {}

// ── Stub data ────────────────────────────────────────────────────────────────

const _manicure = ServiceCategoryOption(
  name: 'MANICURE',
  displayName: 'Манікюр',
);
const _hair = ServiceCategoryOption(name: 'HAIR', displayName: 'Волосся');

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
const _blank = ServiceCategoryOption(name: '', displayName: '');

const _typeClassic = ServiceTypeOption(
  id: 'type-classic',
  slug: 'CLASSIC',
  nameUk: 'Класичний манікюр',
  categoryName: 'MANICURE',
);
const _typeGel = ServiceTypeOption(
  id: 'type-gel',
  slug: 'GEL',
  nameUk: 'Гель-лак',
  categoryName: 'MANICURE',
);
const _typeCut = ServiceTypeOption(
  id: 'type-cut',
  slug: 'CUT',
  nameUk: 'Стрижка',
  categoryName: 'HAIR',
);
// A THIRD manicure type — used by the submitted-index-mapping regression so an
// EXCLUDED on-screen row can sit between/before included ones, making the
// submitted index provably differ from the on-screen index.
const _typeArt = ServiceTypeOption(
  id: 'type-art',
  slug: 'ART',
  nameUk: 'Художній розпис',
  categoryName: 'MANICURE',
);

const _createdService = <MasterService>[
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
/// [_typeClassic] — so expanding MANICURE must render classic as already-added.
const _ownsClassic = <MasterService>[
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
const _ownsClassicAndGel = <MasterService>[
  ..._ownsClassic,
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
/// Its `name` is deliberately IDENTICAL to [_typeClassic]'s `nameUk`. The
/// exclusion is specified to key on the service-type ID and nothing else, so an
/// untyped row must contribute nothing to the owned set even when its display
/// name matches a type exactly. That is the documented degradation direction:
/// UNDER-blocking (the type stays selectable and the save may 409, which is
/// recoverable and explained) rather than OVER-blocking (hiding a service the
/// master then cannot add by any route at all — the setup screen is the ONLY
/// "add services" surface now that the single-create form is deleted).
const _ownsUntypedLegacyRow = <MasterService>[
  MasterService(
    id: 'svc-legacy-untyped',
    serviceDefId: 'def-legacy-untyped',
    // Same display name as _typeClassic.nameUk — a name-based exclusion would
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
const _ownsUnrelated = <MasterService>[
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
class _SeededServicesList extends ServicesList {
  _SeededServicesList(this.seed);

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
class _MutatingServicesList extends ServicesList {
  _MutatingServicesList(this.seeds);

  final List<List<MasterService>> seeds;

  /// Build count — asserted by the tests below so a change that stops
  /// re-reading the catalogue is visible as a count, not only as a missing flag.
  int builds = 0;

  @override
  Future<List<MasterService>> build() {
    final seed = seeds[builds.clamp(0, seeds.length - 1)];
    builds++;
    // SynchronousFuture for the same reason [_SeededServicesList] uses one —
    // see its doc comment; an async build leaves initState reading null.
    return SynchronousFuture(seed);
  }
}

// ── Harness ──────────────────────────────────────────────────────────────────

class _Harness {
  _Harness() : repo = _MockServiceRepository(), pushedRoutes = <String>[];

  final _MockServiceRepository repo;
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
          () => _SeededServicesList(existingServices),
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

Future<void> _pump(
  WidgetTester tester,
  _Harness h, {
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
Future<void> _toggleRowOn(WidgetTester tester, String typeId) async {
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
/// expanded. Unlike [_toggleRowOn]'s `.last`-GestureDetector heuristic (which is
/// only unambiguous while the row is OFF / collapsed), this targets the include
/// switch precisely: it is the GestureDetector nested inside the row's
/// `Semantics(toggled: …)` (the only toggled Semantics in the card — the pricing
/// mode toggle exposes no `toggled` flag), so it flips an ON+expanded row OFF
/// deterministically without colliding with the pricing-mode toggle's own
/// opaque GestureDetector.
Future<void> _tapIncludeSwitch(WidgetTester tester, String typeId) async {
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
VoidCallback? _saveOnPressed(WidgetTester tester) {
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
bool _rowHasErrorRim(WidgetTester tester, String typeId) {
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
Future<void> _fillRowFixed(
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
String? _durationText(WidgetTester tester, String typeId) => tester
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
String? _fixedPriceText(WidgetTester tester, String typeId) => tester
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
Finder _textInRow(String typeId, String message) => find.descendant(
  of: find.byKey(Key('setup_row_$typeId')),
  matching: find.text(message),
);

/// True when [style] carries the ROLE reserved for a collapsed row's
/// off-state sub-label: [VelvetText.svcCaptionNote] — the exact style
/// `service_setup_widgets.dart`'s `else if (!on && (locked || ownedNow))`
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
bool _isOffStateSubLabelStyle(TextStyle? style) =>
    style != null &&
    style.fontSize == VelvetText.svcCaptionNote.fontSize &&
    style.height == VelvetText.svcCaptionNote.height &&
    style.fontFamily == VelvetText.svcCaptionNote.fontFamily;

/// Asserts a COLLAPSED row (`on == false`) renders no off-state sub-label,
/// checked two ways:
///
///  1. ROLE (content-independent, primary): no `Text` descendant of the row
///     carries [_isOffStateSubLabelStyle]. This trips on ANY reinstated
///     sub-label regardless of its string, l10n key, or locale — unlike a
///     literal/key-based check — while an unrelated `Text` (a badge, a price
///     hint, a duration chip) later added to the row with a DIFFERENT style
///     does not false-FAIL it.
///  2. FACT (additional — kept for locked/ownedNow exclusivity coverage): the
///     row renders neither [AppLocalizations.serviceSetupRowAlreadyAdded] nor
///     [AppLocalizations.serviceSetupRowAlreadyInMenu] specifically (via
///     [_textInRow]).
void _expectRowHasNoOffStateSubLabel(
  WidgetTester tester,
  AppLocalizations l10n,
  String typeId,
) {
  expect(
    find.descendant(
      of: find.byKey(Key('setup_row_$typeId')),
      matching: find.byWidgetPredicate(
        (Widget w) => w is Text && _isOffStateSubLabelStyle(w.style),
      ),
    ),
    findsNothing,
    reason:
        'a merely-off row must render no Text carrying the off-state '
        'sub-label ROLE style, regardless of its copy/locale',
  );
  expect(_textInRow(typeId, l10n.serviceSetupRowAlreadyAdded), findsNothing);
  expect(_textInRow(typeId, l10n.serviceSetupRowAlreadyInMenu), findsNothing);
}

/// Taps a category chip and settles — the shared version of the `expandManicure`
/// closure the older groups each define locally.
Future<void> _expand(WidgetTester tester, String slug) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>('cat_$slug')));
  await tester.pumpAndSettle();
}

/// True when `finder`'s render box is laid out AND vertically overlaps the
/// scroll viewport (the [Scrollable]'s on-screen rect — the true fold). Used to
/// assert a row is below the fold before a blocked save, then visible after the
/// scroll-to-flagged behaviour runs. Returns false when the row is unlaid-out
/// (lazy SliverList never built it because it is off-screen).
bool _isInViewport(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  final viewport = tester.getRect(find.byType(Scrollable).first);
  final rect = tester.getRect(finder);
  // Overlaps when its top is above the viewport bottom and its bottom is below
  // the viewport top.
  return rect.top < viewport.bottom && rect.bottom > viewport.top;
}

void main() {
  late _Harness h;

  setUp(() {
    h = _Harness();
    registerFallbackValue(const <MasterServiceBulkItem>[]);
  });

  // ── Catalogue states ───────────────────────────────────────────────────────

  group('catalogue states', () {
    testWidgets('loading — shows a progress indicator', (tester) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncLoading<List<ServiceCategoryOption>>(),
        ),
      );
      await tester.pump(); // one frame; provider future never completes

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error — shows ErrorState; retry re-reads categories', (
      tester,
    ) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncError<List<ServiceCategoryOption>>(
            NetworkFailure(),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('service_setup_error_state')),
        findsOneWidget,
      );
      expect(find.byType(ErrorState), findsOneWidget);

      // The retry affordance must exist and be tappable without throwing.
      final retry = find.descendant(
        of: find.byType(ErrorState),
        matching: find.byType(GestureDetector),
      );
      expect(retry, findsWidgets);
    });

    testWidgets('data — renders a chip per category by key', (tester) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[
            _manicure,
            _hair,
          ]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('cat_MANICURE')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('cat_HAIR')), findsOneWidget);
    });
  });

  // ── Expansion + rows ─────────────────────────────────────────────────────────

  // ── Category-icon wiring (mobile-qa gap-closure, 2026-08-27) ────────────────
  //
  // service_setup_widgets_test.dart proves CategoryChip/CategoryGroupHeader
  // render whatever iconAsset they are handed. It hand-feeds that value, so it
  // cannot catch a wiring regression at the CALL SITE (e.g. this screen
  // swapping `categoryIconOrNullFor` for the never-null `categoryIconFor`, or
  // passing the wrong category's slug/name). These tests drive the resolver
  // through the real screen + real ServiceCategoryOption fixtures instead.
  group('category-icon wiring (resolver reached through the real screen)', () {
    testWidgets(
      'chip renders the resolver-mapped asset for its own category, not a '
      'sibling\'s',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[
              _manicure,
              _hair,
            ]),
          ),
        );
        await tester.pumpAndSettle();

        final AppIcon manicureIcon = tester.widget<AppIcon>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('cat_MANICURE')),
            matching: find.byType(AppIcon),
          ),
        );
        expect(
          manicureIcon.asset,
          equals(BeauticaAssetIcons.categoryNailService),
        );

        final AppIcon hairIcon = tester.widget<AppIcon>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('cat_HAIR')),
            matching: find.byType(AppIcon),
          ),
        );
        expect(hairIcon.asset, equals(BeauticaAssetIcons.categoryHairdressing));
        expect(hairIcon.asset, isNot(equals(manicureIcon.asset)));
      },
    );

    testWidgets(
      'expanded group header renders the SAME resolved asset as its chip',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final AppIcon headerIcon = tester.widget<AppIcon>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('group_MANICURE')),
            matching: find.byType(AppIcon),
          ),
        );
        expect(
          headerIcon.asset,
          equals(BeauticaAssetIcons.categoryNailService),
        );
      },
    );

    testWidgets(
      'a blank-slug/blank-name category renders NO icon on its CHIP through '
      'the screen (proves categoryIconOrNullFor, not categoryIconFor, is '
      'wired at the chip call site)',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_blank]),
          ),
        );
        await tester.pumpAndSettle();

        final chip = find.byKey(const ValueKey<String>('cat_'));
        expect(chip, findsOneWidget);
        expect(
          find.descendant(of: chip, matching: find.byType(AppIcon)),
          findsNothing,
          reason:
              'categoryIconFor() never returns null (it falls back to the '
              'cosmetology asset) — an AppIcon here means the call site '
              'regressed off categoryIconOrNullFor',
        );
      },
    );

    testWidgets(
      'a blank-slug/blank-name category renders NO icon on its EXPANDED '
      'GROUP HEADER either (proves categoryIconOrNullFor is wired at the '
      '_expandedSlots call site too — a separate call site from the chip '
      'above, and the one an isolated chip-only assertion would miss)',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_blank]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              '': const <ServiceTypeOption>[],
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey<String>('cat_')));
        await tester.pumpAndSettle();

        final header = find.byKey(const ValueKey<String>('group_'));
        expect(header, findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.byType(AppIcon)),
          findsNothing,
          reason:
              'categoryIconFor() never returns null — an AppIcon on a blank '
              'category\'s group header means _expandedSlots regressed off '
              'categoryIconOrNullFor',
        );
      },
    );
  });

  group('category expansion', () {
    testWidgets('selecting a category expands it and shows service-type rows', (
      tester,
    ) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('group_MANICURE')),
        findsOneWidget,
      );
      // The first row is on-screen; the second lives below the fold in the
      // lazy SliverList, so scroll it into view before asserting.
      expect(find.byKey(const Key('setup_row_type-classic')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('setup_row_type-gel')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('setup_row_type-gel')), findsOneWidget);
    });
  });

  // ── Footer count + CTA enable/disable ──────────────────────────────────────

  group('footer CTA', () {
    testWidgets('disabled (onPressed null) when nothing is included', (
      tester,
    ) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
      // No selection → footer shows the empty CTA copy.
      expect(find.text(l10n.serviceSetupCtaEmpty), findsOneWidget);
    });

    testWidgets(
      'expanding a category (opt-in: rows default OFF) keeps the count at zero '
      'and the CTA disabled; toggling rows ON raises the count',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Opt-in model: just revealing the rows includes NOTHING → the footer
        // still shows the empty CTA copy and the save callback is null.
        expect(find.text(l10n.serviceSetupCtaEmpty), findsOneWidget);
        expect(find.text(l10n.serviceSetupCtaCreate(2)), findsNothing);
        expect(_saveOnPressed(tester), isNull);

        // Toggle the first row ON — count rises to 1, CTA becomes enabled.
        await _toggleRowOn(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
        expect(_saveOnPressed(tester), isNotNull);

        // Toggle the second row ON (scroll it into view first) — count rises
        // to 2.
        await tester.scrollUntilVisible(
          find.byKey(const Key('setup_row_type-gel')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _toggleRowOn(tester, 'type-gel');
        expect(find.text(l10n.serviceSetupCtaCreate(2)), findsOneWidget);
      },
    );
  });

  // ── Save path ────────────────────────────────────────────────────────────────

  group('save', () {
    testWidgets(
      'tapping save with a valid included row calls bulkCreate and navigates '
      'to the services list',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => _createdService);

        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        // Opt-in: include the row FIRST, else it is excluded and the save is a
        // no-op (CTA disabled) — bulkCreate would never be called.
        await _toggleRowOn(tester, 'type-classic');

        // Fill the duration (the row's leading VelvetField — the first
        // TextField in the card) and the fixed price (keyed field).
        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-classic')),
                matching: find.byType(TextField),
              )
              .first,
          '60',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-fixed-amount')),
          '500',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(h.pushedRoutes, contains(RouteNames.services));
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'invalid range (max <= min) flags the row and blocks save — bulkCreate '
      'never called',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Opt-in: include the row first so it participates in validation.
        await _toggleRowOn(tester, 'type-classic');

        // Switch the row to RANGE mode and enter an invalid range.
        await tester.tap(find.byKey(const Key('pricing-toggle-range')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-classic')),
                matching: find.byType(TextField),
              )
              .first,
          '60',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-range-min')),
          '500',
        );
        await tester.enterText(
          find.byKey(const Key('pricing-range-max')),
          '300', // max <= min → invalid
        );
        await tester.pumpAndSettle();

        // The cross-field range error line appears (only on invalid range).
        expect(find.text(l10n.pricingRangeHint), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );
  });

  // ── Bug 1 regression — narrow-width layout (no RenderFlex overflow) ────────
  //
  // The compact duration+price line used to overflow horizontally on narrow
  // phones — worst in RANGE mode (two numeric fields + two "₴" suffixes
  // beside the duration). pricing_field.dart now stacks duration above price
  // below 360dp, and range min/max stack below 220dp. These tests pump the
  // screen at 320 / 360 / 412 dp, include + expand a row in each pricing mode,
  // and assert NO exception was thrown (a RenderFlex overflow surfaces via
  // tester.takeException()). They FAIL against the pre-fix single-Row layout.

  group('narrow-width layout — no overflow (Bug 1)', () {
    for (final width in <double>[320, 360, 412]) {
      for (final range in <bool>[false, true]) {
        final mode = range ? 'range' : 'fixed';
        testWidgets(
          'included row at ${width.toInt()}dp in $mode mode does not overflow',
          (tester) async {
            await _pump(
              tester,
              h,
              surfaceSize: Size(width, 900),
              overrides: h.overrides(
                categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
                typesBySlug: <String, List<ServiceTypeOption>>{
                  'MANICURE': <ServiceTypeOption>[_typeClassic],
                },
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey<String>('cat_MANICURE')),
            );
            await tester.pumpAndSettle();

            // Reveal the duration + price line by including the row.
            await _toggleRowOn(tester, 'type-classic');

            if (range) {
              await tester.tap(find.byKey(const Key('pricing-toggle-range')));
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('pricing-range-min')),
                findsOneWidget,
              );
              expect(
                find.byKey(const Key('pricing-range-max')),
                findsOneWidget,
              );
            } else {
              expect(
                find.byKey(const Key('pricing-fixed-amount')),
                findsOneWidget,
              );
            }

            // A RenderFlex overflow is reported as a thrown FlutterError that
            // tester.takeException() surfaces; null means the responsive
            // stacking kept every inner field above its min width.
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  // ── Bug 2 regression — opt-in flagging / premature validation ──────────────
  //
  // Rows used to default included, so expanding a category immediately made
  // every untouched row "required" — tapping save fired
  // "Вкажіть тривалість і ціну" on rows the master never opted into. The opt-in
  // model (rows default OFF) + per-row RowFlagReason fixes both the premature
  // flag AND the disambiguated messages.

  group('opt-in flagging (Bug 2)', () {
    Future<void> expandManicure(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'expanding then tapping save with NO row included shows no flag and '
      'never calls bulkCreate (the user-reported premature-flag bug)',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // The CTA is disabled (no-op) — tapping it must not flag the untouched
        // row nor reach the repository.
        expect(_saveOnPressed(tester), isNull);
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // No flag message of any kind on the untouched row.
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expect(find.text(l10n.serviceSetupRowMissingDuration), findsNothing);
        expect(find.text(l10n.serviceSetupRowMissingPriceOnly), findsNothing);
        expect(find.text(l10n.serviceSetupRowFixRange), findsNothing);
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets(
      'included row with empty duration flags missingDuration (not the generic '
      'both) on save',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await expandManicure(tester);
        await _toggleRowOn(tester, 'type-classic');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Duration empty, fixed price present → missingDuration only.
        await tester.enterText(
          find.byKey(const Key('pricing-fixed-amount')),
          '500',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        expect(find.text(l10n.serviceSetupRowMissingDuration), findsOneWidget);
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets(
      'included fixed row with duration but empty price flags missingPriceOnly',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await expandManicure(tester);
        await _toggleRowOn(tester, 'type-classic');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-classic')),
                matching: find.byType(TextField),
              )
              .first,
          '60',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // missingPriceOnly surfaces "Вкажіть ціну" twice: once as the header
        // flag (serviceSetupRowMissingPriceOnly) and once as the inline
        // fixed-price field hint (serviceSetupPriceRequired) — both ARB values
        // are the same string. Two matches proves the price-only path (the
        // missingBoth header would instead read "Вкажіть тривалість і ціну").
        expect(
          find.text(l10n.serviceSetupRowMissingPriceOnly),
          findsNWidgets(2),
        );
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expect(find.text(l10n.serviceSetupRowMissingDuration), findsNothing);
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets('included row with both empty falls back to missingBoth '
        '(serviceSetupRowMissingPrice)', (tester) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[_typeClassic],
          },
        ),
      );
      await expandManicure(tester);
      await _toggleRowOn(tester, 'type-classic');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.serviceSetupRowMissingPrice), findsOneWidget);
      verifyNever(() => h.repo.bulkCreate(any()));
    });
  });

  // ── MEDIUM regression — scroll-to-first-flagged on blocked save ────────────
  //
  // Spec required, but was missing in code: when a blocked save leaves an
  // included-and-flagged row BELOW the fold, the screen must scroll the topmost
  // such row back into view (post-frame Scrollable.ensureVisible) so the master
  // never stares at a silently no-op CTA. _scrollToFirstFlagged() now does this
  // off _save()'s blocked branch. This test stands a flagged included row below
  // the fold (small surface + scroll back to top), taps save, and asserts the
  // row is scrolled into view — and bulkCreate is never reached.

  group('scroll-to-first-flagged on blocked save (MEDIUM regression)', () {
    testWidgets(
      'a flagged included row below the fold is scrolled into view after a '
      'blocked save; bulkCreate is never called',
      (tester) async {
        // A short surface so the two manicure rows cannot both fit — the second
        // (type-gel) row sits below the fold once we scroll back to the top.
        //
        // This height is a CALIBRATED FIXTURE, not an arbitrary number: it has
        // to be re-trimmed whenever the header above the rows changes height.
        // Trimmed 440 → 360 on 2026-08-04 when the static three-line helper
        // note became the one-line tappable «Запропонувати категорію» strip —
        // the shorter header pulled both rows above the fold and the
        // `isFalse` PRECONDITION below started failing, which is the fixture
        // going stale, not the behaviour regressing. The precondition assert
        // is what makes that drift loud instead of silently turning this into
        // a test that proves nothing.
        await _pump(
          tester,
          h,
          surfaceSize: const Size(360, 360),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        final scrollable = find.byType(Scrollable).first;
        final lowerRow = find.byKey(const Key('setup_row_type-gel'));

        // Include the LOWER row (scroll it into view to tap its switch) but
        // leave it invalid (no duration / no price) so the save is blocked.
        await tester.scrollUntilVisible(lowerRow, 200, scrollable: scrollable);
        await _toggleRowOn(tester, 'type-gel');

        // Scroll back to the very top so the flagged lower row is below the
        // fold at the moment we trigger the blocked save.
        await tester.drag(scrollable, const Offset(0, 1200));
        await tester.pumpAndSettle();

        // Precondition: the flagged row starts off-screen (below the fold).
        expect(
          _isInViewport(tester, lowerRow),
          isFalse,
          reason: 'lower flagged row should start below the fold',
        );

        // Tapping save assembles → null (flagged) → _scrollToFirstFlagged().
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // The post-frame ensureVisible ran without throwing AND brought the
        // flagged row into the viewport.
        expect(tester.takeException(), isNull);
        expect(
          _isInViewport(tester, lowerRow),
          isTrue,
          reason: 'flagged row must be scrolled into view after blocked save',
        );

        // Its flag hint is now rendered and the save was genuinely blocked.
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsOneWidget);
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets(
      'blocked save with the flagged row already on-screen is a no-throw no-op '
      '(ensureVisible path is mounted-safe)',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        await _toggleRowOn(tester, 'type-classic');

        // Leave the included row invalid (empty) → blocked save scrolls to a
        // row that is already visible; must not throw.
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          _isInViewport(
            tester,
            find.byKey(const Key('setup_row_type-classic')),
          ),
          isTrue,
        );
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );
  });

  // ── HIGH regression — stale flag survives toggle-off / collapse-reexpand ────
  //
  // The user-reported stale-flag bug: an included row flagged on a blocked save
  // (flagReason set → "Вкажіть тривалість і ціну", missingBoth) kept painting
  // its error AFTER the master either (a) toggled the row OFF or (b) collapsed
  // and re-expanded its category. Two independent fixes guard this:
  //   • service_setup_widgets.dart — header flag gated on inclusion
  //     (`final bool flagged = on && row.flagged;`) so an excluded row never
  //     paints the flag/rim and the "excluded" sub-label takes over instead;
  //   • service_setup_screen.dart — `_toggleCategory`'s collapse branch calls
  //     `row.clearFlag()` on every retained row so a re-expanded row never
  //     resurrects a flag predating the collapse.
  // These tests stand a row up, blank both fields, fire a blocked save to set
  // the flag, then exercise each clear path. They FAIL against the pre-fix code
  // (the flag message lingers); they PASS now.

  group('stale flag clears on toggle-off / collapse-reexpand (HIGH regression)', () {
    Future<void> expandManicure(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();
    }

    /// Includes the single manicure row, leaves duration+price blank, and fires
    /// a blocked save so the row carries the missingBoth flag
    /// (`serviceSetupRowMissingPrice`). Returns the loaded l10n bundle.
    Future<AppLocalizations> includeAndBlock(WidgetTester tester) async {
      await expandManicure(tester);
      await _toggleRowOn(tester, 'type-classic');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      // Precondition: the blocked save flagged the included row.
      expect(find.text(l10n.serviceSetupRowMissingPrice), findsOneWidget);
      verifyNever(() => h.repo.bulkCreate(any()));
      return l10n;
    }

    testWidgets(
      'toggling a flagged row OFF removes its flag message and renders no '
      'sub-label at all (no error rim on the merely-off card)',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );

        final l10n = await includeAndBlock(tester);

        // The flagged card paints a tinted error rim while included+flagged.
        expect(_rowHasErrorRim(tester, 'type-classic'), isTrue);

        // Toggle the row OFF — `flagged = on && row.flagged` collapses to false
        // AND `_setIncluded` clears the flag.
        await _tapIncludeSwitch(tester, 'type-classic');

        // The flag message is GONE; a merely-off row (neither locked nor
        // ownedNow) renders no sub-label at all.
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        _expectRowHasNoOffStateSubLabel(tester, l10n, 'type-classic');
        // The merely-off card carries no error rim.
        expect(_rowHasErrorRim(tester, 'type-classic'), isFalse);
      },
    );

    testWidgets(
      'collapsing then re-expanding a category clears the stale flag AND leaves '
      'the row DESELECTED (collapse == deselect — clearFlag + included=false)',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );

        final l10n = await includeAndBlock(tester);

        // Collapse the category (tap the chip again). `_expanded` IS the
        // selection set, so collapsing DESELECTS: `_toggleCategory` runs both
        // `row.included = false` AND `row.clearFlag()` on the retained row.
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();
        // While collapsed there is no flagged card on screen.
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);

        // Re-expand — the row state is reused (no refetch). With the fix the
        // flag was cleared on collapse, so the re-expanded card is clean.
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('setup_row_type-classic')), findsOneWidget);
        // (a) The stale-flag guarantee STILL holds — no flag lingers after the
        // collapse/re-expand round-trip (pre-fix this would resurrect).
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expect(_rowHasErrorRim(tester, 'type-classic'), isFalse);
        // (b) NEW contract: collapse deselected the row, so the re-expanded card
        // is now merely off — it renders no sub-label at all, not an
        // unflagged-but-included row.
        _expectRowHasNoOffStateSubLabel(tester, l10n, 'type-classic');
      },
    );

    testWidgets(
      'an excluded row never paints a flag even after it had been flagged '
      'while included',
      (tester) async {
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );

        final l10n = await includeAndBlock(tester);

        // Toggle OFF (was flagged) → merely off, unflagged, no sub-label.
        await _tapIncludeSwitch(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        _expectRowHasNoOffStateSubLabel(tester, l10n, 'type-classic');
        expect(_rowHasErrorRim(tester, 'type-classic'), isFalse);

        // Toggle back ON — re-including starts clean (clearFlag on include); no
        // stale flag carries over from the earlier blocked save, and no
        // leftover off-state sub-label lingers either (that branch is gated
        // on `!on`, so it never fires once the row is included).
        await _tapIncludeSwitch(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupRowMissingPrice), findsNothing);
        expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNothing);
        expect(find.text(l10n.serviceSetupRowAlreadyInMenu), findsNothing);
        expect(_rowHasErrorRim(tester, 'type-classic'), isFalse);
      },
    );
  });

  // ── HIGH regression — deselecting (collapsing) a category drops its rows ────
  //   from BOTH the footer count AND the bulk-save payload.
  //
  // The user-reported bug: `_expanded` IS the category-selection set, so
  // collapsing a category == deselecting it. Before the fix, collapse was a
  // "pure visibility change" — the retained rows kept `included == true`, so a
  // deselected category still inflated the footer "Створити N послуг" count and
  // (critically) still contributed its serviceTypeIds to the bulk-save payload.
  //
  // The fix resets each retained row's `included = false` (alongside the existing
  // `clearFlag()`) in `_toggleCategory`'s collapse branch. These tests stand up
  // TWO categories, include rows in each, deselect one, then assert:
  //   • the footer count drops to ONLY the remaining category's rows; and
  //   • the assembled payload (captured at `bulkCreate`) carries ONLY the
  //     remaining category's serviceTypeId — proving `_assemble()` excludes the
  //     deselected rows, not just the footer label.
  // Both assertions FAIL against the pre-fix "stays-included" behaviour.

  group('deselect (collapse) drops a category from count + payload (HIGH '
      'regression)', () {
    List<Object> twoCategoryOverrides() => h.overrides(
      categories: const AsyncData(<ServiceCategoryOption>[_manicure, _hair]),
      typesBySlug: <String, List<ServiceTypeOption>>{
        'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
        'HAIR': <ServiceTypeOption>[_typeCut],
      },
    );

    testWidgets(
      'including 2 rows in A + 1 in B reads "3"; deselecting A drops the footer '
      'to "1" (NOT 3)',
      (tester) async {
        // A tall surface so both chips + all three expanded rows fit on screen
        // at once — every chip/row stays laid out, so no scroll juggling is
        // needed and the footer-count assertions are deterministic.
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: twoCategoryOverrides(),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Expand A (MANICURE) and toggle BOTH its rows ON → footer reads "2".
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();
        await _toggleRowOn(tester, 'type-classic');
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
        await _toggleRowOn(tester, 'type-gel');
        expect(find.text(l10n.serviceSetupCtaCreate(2)), findsOneWidget);

        // Expand B (HAIR) and toggle its single row ON → footer rises to "3".
        await tester.tap(find.byKey(const ValueKey<String>('cat_HAIR')));
        await tester.pumpAndSettle();
        await _toggleRowOn(tester, 'type-cut');
        expect(find.text(l10n.serviceSetupCtaCreate(3)), findsOneWidget);

        // Deselect A by tapping its chip again. The reported symptom: pre-fix the
        // footer stayed at "3"; post-fix it drops to "1" (only B's row counts).
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
        expect(find.text(l10n.serviceSetupCtaCreate(3)), findsNothing);
      },
    );

    testWidgets(
      'the bulk-save payload after deselecting A carries ONLY category B\'s '
      'serviceTypeId — none of the deselected A rows',
      (tester) async {
        // Capture the assembled payload handed to bulkCreate.
        final captured = <List<MasterServiceBulkItem>>[];
        when(() => h.repo.bulkCreate(any())).thenAnswer((invocation) async {
          captured.add(
            invocation.positionalArguments.first as List<MasterServiceBulkItem>,
          );
          return _createdService;
        });

        // A tall surface keeps every chip + row laid out at once.
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: twoCategoryOverrides(),
        );
        await tester.pumpAndSettle();

        // Expand A + include both rows.
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();
        await _toggleRowOn(tester, 'type-classic');
        await _toggleRowOn(tester, 'type-gel');

        // Expand B + include its row, then give it a VALID duration + price so
        // the (post-deselect) save assembles cleanly.
        await tester.tap(find.byKey(const ValueKey<String>('cat_HAIR')));
        await tester.pumpAndSettle();
        await _toggleRowOn(tester, 'type-cut');
        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-cut')),
                matching: find.byType(TextField),
              )
              .first,
          '45',
        );
        // All three included rows expand a fixed-price field with the same key,
        // so scope the entry to type-cut's card.
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('setup_row_type-cut')),
            matching: find.byKey(const Key('pricing-fixed-amount')),
          ),
          '350',
        );
        await tester.pumpAndSettle();

        // Deselect A — its (incomplete) rows must NOT block the save NOR appear
        // in the payload.
        await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
        await tester.pumpAndSettle();

        // Save.
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // bulkCreate was called once with EXACTLY B's single serviceTypeId.
        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(captured, hasLength(1));
        final ids = captured.single.map((i) => i.serviceTypeId).toList();
        expect(ids, <String>['type-cut']);
        expect(ids, isNot(contains('type-classic')));
        expect(ids, isNot(contains('type-gel')));
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── Close button — pop-with-fallback regression guard ──────────────────────
  //
  // Three close/return sites in ServiceSetupScreen were changed from
  // `context.go(RouteNames.services)` to
  // `canPop ? context.pop() : context.go(RouteNames.services)`.
  //
  // The change ensures deep-link safety: when the screen is reached directly
  // (no back stack), it falls back to go(); when it is pushed (has a back
  // stack), it pops instead of replacing the stack with a go().
  //
  // Test 1 — pushed path (canPop true): pump the setup screen on top of a
  //   previous route. Tap the close button. Assert the navigator returns to the
  //   previous route (pop happened) rather than replacing the stack with
  //   /services (go would have happened).
  //
  // Test 2 — direct-entry path (canPop false): pump the setup screen as the
  //   initial (only) route. Tap close. Assert the router lands on
  //   RouteNames.services (the go() fallback fired).

  group('close button pop-with-fallback (swipe-back regression guard)', () {
    // ── 1. Pushed path — close pops back to previous route ───────────────────

    testWidgets(
      'close button pops back to the previous route when a back stack exists',
      (tester) async {
        // A 3-route router: /prev → /services/setup → /services.
        // Starting at /prev and pushing /services/setup gives us a poppable stack.
        const prevPath = '/prev';
        final router = GoRouter(
          initialLocation: prevPath,
          routes: <RouteBase>[
            GoRoute(
              path: prevPath,
              builder: (_, _) => const Scaffold(body: Text('PREVIOUS_SCREEN')),
            ),
            GoRoute(
              path: RouteNames.serviceSetup,
              builder: (_, _) => const ServiceSetupScreen(),
            ),
            GoRoute(
              path: RouteNames.services,
              builder: (_, _) =>
                  const Scaffold(body: Text('SERVICES_LIST_STUB')),
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            retry: beauticaProviderRetry,
            overrides: h
                .overrides(
                  categories: const AsyncData(<ServiceCategoryOption>[]),
                )
                .cast(),
            child: MediaQuery(
              data: const MediaQueryData(size: Size(800, 1200)),
              child: MaterialApp.router(
                routerConfig: router,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('uk'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Navigate from /prev to /services/setup via push.
        unawaited(router.push(RouteNames.serviceSetup));
        await tester.pumpAndSettle();

        // Verify setup screen rendered (categories empty — just the chip area).
        expect(
          router.canPop(),
          isTrue,
          reason: 'canPop must be true — /prev is still on the back stack',
        );

        // Tap the close button.
        final closeBtn = find.byKey(const Key('btn-setup-close'));
        expect(
          closeBtn,
          findsOneWidget,
          reason: 'close button (Key btn-setup-close) must be present',
        );
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        // Must have returned to /prev, NOT replaced the stack with /services.
        // The PREVIOUS_SCREEN text is present; SERVICES_LIST_STUB is absent.
        expect(
          find.text('PREVIOUS_SCREEN'),
          findsOneWidget,
          reason:
              'close button must pop (return to /prev) when canPop is true. '
              'If this fails, the code reverted to context.go(services) which '
              'replaces the stack instead of popping.',
        );
        expect(
          find.text('SERVICES_LIST_STUB'),
          findsNothing,
          reason:
              'the services-list fallback screen must NOT appear — '
              'context.go(services) must not have fired when canPop was true',
        );
      },
    );

    // ── 2. Direct-entry path — close falls back to go(services) ─────────────

    testWidgets(
      'close button goes to services when there is no back stack (deep-link entry)',
      (tester) async {
        // The harness router uses serviceSetup as initialLocation — no prior
        // route on the stack — so canPop() is false and the fallback go() fires.
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[]),
          ),
        );
        await tester.pumpAndSettle();

        // The harness router starts at serviceSetup with no back-stack entry.
        // canPop() is false, so the close button must fire go(services).
        final closeBtn = find.byKey(const Key('btn-setup-close'));
        expect(
          closeBtn,
          findsOneWidget,
          reason: 'close button (Key btn-setup-close) must be present',
        );
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        // The services-list stub body text must be visible — go(services) fired.
        expect(
          find.text('SERVICES_LIST_STUB'),
          findsOneWidget,
          reason:
              'close button must navigate to services via go() when the '
              'back stack is empty (deep-link / direct-entry path)',
        );
      },
    );
  });

  // ── HIGH regression — per-field 400 lands inline on the offending SUBMITTED
  //   row instead of the generic «Перевірте дані» snack.
  //
  // The user-reported bug: a bulk-save 400 carrying per-field errors
  // (`errors: {"items[1].durationMinutes": "…"}`) surfaced the GENERIC
  // `errValidation` snack and flagged NO row, so the master could not tell
  // WHICH service the backend rejected. The fix:
  //   • service_setup_screen.dart — `_assemble()` captures `_submittedRows`
  //     (INCLUDED rows, in submitted order); `_save()` parses each
  //     `items[<i>].<field>` key, maps `i → _submittedRows[i]`, stamps
  //     `serverDurationError` (localized `serviceSetupDurationMax`) /
  //     `serverPriceError`, scrolls to the first flagged row, and only shows the
  //     generic snack when NO key maps;
  //   • service_setup_widgets.dart — the row card coalesces the server error into
  //     its inline field slot + red rim, and clears it on field edit.
  //
  // These tests FAIL against the old behaviour (generic snack, no row
  // flagged) and PASS now.

  group('per-field 400 maps to the offending submitted row (HIGH regression)', () {
    Future<void> expandManicure(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('cat_MANICURE')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'server items[1].durationMinutes flags the 2nd SUBMITTED row inline '
      '(serviceSetupDurationMax + red rim), leaves the 1st clean, and does NOT '
      'show the generic errValidation snackbar',
      (tester) async {
        when(() => h.repo.bulkCreate(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{
              'items[1].durationMinutes':
                  'Duration must be at most 480 minutes (8 hours)',
            },
          ),
        );

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Include BOTH rows with valid duration + price so a 2-item payload
        // assembles in submitted order [type-classic, type-gel].
        await _toggleRowOn(tester, 'type-classic');
        await _toggleRowOn(tester, 'type-gel');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await _fillRowFixed(tester, 'type-gel', duration: '90', price: '700');

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // The payload WAS submitted (both rows valid) — the 400 came from the
        // network, not the client guard.
        verify(() => h.repo.bulkCreate(any())).called(1);

        // items[1] → the 2nd SUBMITTED row (type-gel): the inline duration
        // message + the card's red error rim.
        expect(
          _textInRow('type-gel', l10n.serviceSetupDurationMax),
          findsOneWidget,
          reason:
              'the backend items[1] error must land inline on the 2nd submitted '
              'row (type-gel) as the localized duration-max message',
        );
        expect(_rowHasErrorRim(tester, 'type-gel'), isTrue);

        // The 1st submitted row (type-classic) is untouched.
        expect(
          _textInRow('type-classic', l10n.serviceSetupDurationMax),
          findsNothing,
        );
        expect(_rowHasErrorRim(tester, 'type-classic'), isFalse);

        // The generic validation snackbar must NOT fire — the OLD behaviour did
        // exactly this (and flagged no row).
        expect(
          find.text(l10n.errValidation),
          findsNothing,
          reason:
              'a per-field 400 that maps to a row must be shown inline, NOT via '
              'the generic errValidation snackbar (the regressed behaviour)',
        );
      },
    );

    testWidgets(
      'the index is into the SUBMITTED list, not the on-screen list — an '
      'EXCLUDED row is skipped so items[1] maps past it to the correct row',
      (tester) async {
        // Rows on screen: [classic (EXCLUDED), gel (incl), art (incl)].
        // Submitted order (only included, in order): [gel, art].
        //   items[0] → gel   (on-screen index 1)
        //   items[1] → art   (on-screen index 2)   ← the error target
        // A NAIVE on-screen index would wrongly resolve items[1] → gel, so
        // asserting the error lands on `art` (and NOT `gel`) proves the mapping
        // walks the submitted list, not the visible one.
        when(() => h.repo.bulkCreate(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{
              'items[1].durationMinutes':
                  'Duration must be at most 480 minutes (8 hours)',
            },
          ),
        );

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel, _typeArt],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Include gel + art (leave classic EXCLUDED), both valid.
        await _toggleRowOn(tester, 'type-gel');
        await _toggleRowOn(tester, 'type-art');
        await _fillRowFixed(tester, 'type-gel', duration: '60', price: '500');
        await _fillRowFixed(tester, 'type-art', duration: '90', price: '700');

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);

        // items[1] → `art` (submitted index 1), NOT the on-screen index-1 `gel`.
        expect(
          _textInRow('type-art', l10n.serviceSetupDurationMax),
          findsOneWidget,
          reason:
              'items[1] must map to the 2nd SUBMITTED row (art), not the 2nd '
              'on-screen row (gel) — the excluded classic row is not submitted',
        );
        expect(_rowHasErrorRim(tester, 'type-art'), isTrue);

        // gel (submitted index 0) + classic (excluded) must be clean.
        expect(
          _textInRow('type-gel', l10n.serviceSetupDurationMax),
          findsNothing,
        );
        expect(_rowHasErrorRim(tester, 'type-gel'), isFalse);
        expect(_rowHasErrorRim(tester, 'type-classic'), isFalse);
      },
    );

    testWidgets(
      'client-side > 480 guard flags the row (durationTooLong / '
      'serviceSetupDurationMax) BEFORE the network — bulkCreate is never called',
      (tester) async {
        // No bulkCreate stub — the client guard must short-circuit before any
        // network call, so the repository is never touched.
        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await _toggleRowOn(tester, 'type-classic');
        // 500 > 480 → the client mirror of the backend @Max(480) guard fires.
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '500',
          price: '500',
        );

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // The duration-max copy is rendered on the row (header flag + inline
        // duration hint both use serviceSetupDurationMax for durationTooLong).
        expect(
          _textInRow('type-classic', l10n.serviceSetupDurationMax),
          findsWidgets,
          reason:
              'the > 480 client guard must surface serviceSetupDurationMax on '
              'the row before any network round-trip',
        );
        expect(_rowHasErrorRim(tester, 'type-classic'), isTrue);

        // Proven pre-submit: the repository was NEVER called (count stays 0).
        verifyNever(() => h.repo.bulkCreate(any()));
      },
    );

    testWidgets(
      'a 400 whose field key does NOT match items[i].field falls back to the '
      'generic errValidation snackbar and flags no row',
      (tester) async {
        when(() => h.repo.bulkCreate(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{'somethingUnknown': 'x'},
          ),
        );

        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await _toggleRowOn(tester, 'type-classic');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);

        // Unmappable key → the generic snack is preserved (fallback intact).
        expect(find.text(l10n.errValidation), findsOneWidget);
        // No row flag / rim — nothing mapped to a row.
        expect(
          _textInRow('type-classic', l10n.serviceSetupDurationMax),
          findsNothing,
        );
        expect(_rowHasErrorRim(tester, 'type-classic'), isFalse);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'editing the flagged row\'s duration clears the mapped-back server error '
      '(inline message + red rim both disappear)',
      (tester) async {
        when(() => h.repo.bulkCreate(any())).thenThrow(
          const ValidationFailure(
            fieldErrors: <String, String>{
              'items[1].durationMinutes':
                  'Duration must be at most 480 minutes (8 hours)',
            },
          ),
        );

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
          ),
        );
        await expandManicure(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await _toggleRowOn(tester, 'type-classic');
        await _toggleRowOn(tester, 'type-gel');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await _fillRowFixed(tester, 'type-gel', duration: '90', price: '700');

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // Precondition: the server error is on type-gel.
        expect(
          _textInRow('type-gel', l10n.serviceSetupDurationMax),
          findsOneWidget,
        );
        expect(_rowHasErrorRim(tester, 'type-gel'), isTrue);

        // Editing the flagged row's duration clears the mapped-back error.
        await tester.enterText(
          find
              .descendant(
                of: find.byKey(const Key('setup_row_type-gel')),
                matching: find.byType(TextField),
              )
              .first,
          '75',
        );
        await tester.pumpAndSettle();

        expect(
          _textInRow('type-gel', l10n.serviceSetupDurationMax),
          findsNothing,
          reason: 'the server duration error must clear as the master edits it',
        );
        expect(_rowHasErrorRim(tester, 'type-gel'), isFalse);
      },
    );
  });

  // ── APPEND mode — already-owned service types are structurally excluded ────
  //
  // The screen now serves BOTH first-time SETUP and "add more services"
  // (APPEND). The bulk endpoint is all-or-nothing: ONE item naming a service the
  // master already offers rolls the WHOLE batch back with 409 DUPLICATE_SERVICE.
  // So a row whose service-type id is already in the master's catalogue is
  // seeded `alreadyAdded` — rendered in place, but with NO include switch at all
  // and a hard refusal in `ServiceRowState.included`'s setter.
  //
  // These tests seed `servicesListProvider` (the snapshot source read once in
  // initState) and assert the exclusion at THREE independent levels: the
  // rendered row, the group header's "n з m" denominator, and the assembled
  // bulk payload.

  group('APPEND mode — already-owned types are excluded (HIGH — the '
      'guaranteed-409 fix)', () {
    testWidgets(
      'an already-owned type renders «Вже додано» with NO include toggle, while '
      'its selectable sibling keeps its toggle',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
            existingServices: _ownsClassic,
          ),
        );
        await _expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Both rows are rendered — an owned type is shown, not hidden, so the
        // master can see WHY it is unselectable.
        expect(find.byKey(const Key('setup_row_type-classic')), findsOneWidget);
        expect(find.byKey(const Key('setup_row_type-gel')), findsOneWidget);

        // The owned row: the include switch does not exist at all (a disabled
        // switch would still invite tapping), and the sub-label states the fact.
        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsNothing,
          reason:
              'an already-added row must render NO include switch — the '
              'structural guard against the guaranteed-409 batch rollback',
        );
        expect(
          _textInRow('type-classic', l10n.serviceSetupRowAlreadyAdded),
          findsOneWidget,
        );
        expect(
          _textInRow('type-classic', l10n.serviceSetupRowAlreadyInMenu),
          findsNothing,
          reason:
              'the already-added fact must take the sub-label slot, not the '
              'catalogue-refresh «already in menu» fact',
        );

        // The selectable sibling is untouched — proves the exclusion is keyed on
        // the owned id, not applied blanket to the whole category.
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsOneWidget,
        );
        // The selectable sibling is merely off (neither locked nor ownedNow),
        // so it renders no sub-label at all.
        _expectRowHasNoOffStateSubLabel(tester, l10n, 'type-gel');

        // One-of-two owned is NOT the "all already added" case.
        expect(find.text(l10n.serviceSetupAllAlreadyAdded), findsNothing);
      },
    );

    testWidgets(
      'the SAME catalogue with an EMPTY services list keeps BOTH toggles — the '
      'exclusion is driven by the seeded snapshot, not by the fixture shape',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsOneWidget,
        );
        expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNothing);
      },
    );

    testWidgets(
      'the bulk payload after including the SELECTABLE sibling carries ONLY its '
      'serviceTypeId — the owned type can never reach the all-or-nothing batch',
      (tester) async {
        final captured = <List<MasterServiceBulkItem>>[];
        when(() => h.repo.bulkCreate(any())).thenAnswer((invocation) async {
          captured.add(
            invocation.positionalArguments.first as List<MasterServiceBulkItem>,
          );
          return _createdService;
        });

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
            existingServices: _ownsClassic,
          ),
        );
        await _expand(tester, 'MANICURE');

        // Precondition: the owned row exposes no switch, so the ONLY way it
        // could land in the payload is a state-level leak (covered by the
        // ServiceRowState setter unit test below).
        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsNothing,
        );

        await _toggleRowOn(tester, 'type-gel');
        await _fillRowFixed(tester, 'type-gel', duration: '90', price: '700');

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(captured, hasLength(1));
        final ids = captured.single.map((i) => i.serviceTypeId).toList();
        expect(ids, <String>['type-gel']);
        expect(
          ids,
          isNot(contains('type-classic')),
          reason:
              'submitting an already-owned service type 409s the ENTIRE batch — '
              'it must never be assembled into the payload',
        );
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'the group header "n з m" denominator counts only SELECTABLE types — 1 of '
      '2 owned reads «0 з 1», never «0 з 2»',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
            existingServices: _ownsClassic,
          ),
        );
        await _expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(
          find.text(l10n.serviceSetupGroupCount(0, 1)),
          findsOneWidget,
          reason:
              'm must exclude the already-owned type — counting it would render '
              '«0 з 8» for a master who already offers 8 of 8',
        );
        expect(find.text(l10n.serviceSetupGroupCount(0, 2)), findsNothing);

        // Including the one selectable row moves the numerator, not the
        // denominator.
        await _toggleRowOn(tester, 'type-gel');
        expect(find.text(l10n.serviceSetupGroupCount(1, 1)), findsOneWidget);
      },
    );

    testWidgets(
      'with an EMPTY catalogue the SAME two types read «0 з 2» — the denominator '
      'genuinely tracks ownership',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.text(l10n.serviceSetupGroupCount(0, 2)), findsOneWidget);
        expect(find.text(l10n.serviceSetupGroupCount(0, 1)), findsNothing);
      },
    );

    testWidgets(
      'when EVERY type in the expanded category is already owned the category '
      'says so (serviceSetupAllAlreadyAdded) instead of looking broken',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
            existingServices: _ownsClassicAndGel,
          ),
        );
        await _expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.text(l10n.serviceSetupAllAlreadyAdded), findsOneWidget);
        // Both rows are inert: neither has a switch, both carry the fact label.
        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsNothing,
        );
        expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNWidgets(2));
        // Nothing is selectable → the CTA stays disabled.
        expect(_saveOnPressed(tester), isNull);
        expect(find.text(l10n.serviceSetupGroupCount(0, 0)), findsOneWidget);
      },
    );
  });

  // ── Off-state sub-label — the three mutually exclusive facts, together ─────
  //
  // The sub-label slot under a collapsed row's name renders AT MOST one of two
  // facts now (`locked` → «Вже додано», `ownedNow` → «уже у вашому переліку»,
  // emphasised). A THIRD, merely-off row — neither at-load-owned nor just
  // claimed by a catalogue refresh — used to render a generic «Не пропонується»
  // sub-label; that branch was deleted, so it now renders NOTHING beyond the
  // name (regression: see the "renders no sub-label" assertions above, each
  // proven to go RED against the old 3-way branch by a mutation probe).
  //
  // The three states are exercised individually elsewhere in this file. This
  // group is the ONE place that stands all three up side by side in a single
  // screen — classic is owned at load (`locked`), art gets claimed by a
  // catalogue refresh mid-session (`ownedNow`), gel is never touched
  // (merely off) — so mutual exclusivity and the emphasis style are pinned
  // against real siblings rather than in isolation.
  group('off-state sub-label — locked / ownedNow / merely-off side by side', () {
    testWidgets('locked shows AlreadyAdded plainly, ownedNow shows AlreadyInMenu '
        'emphasised, merely-off shows neither — and no row ever renders the '
        'deleted generic «Не пропонується» copy', (tester) async {
      when(
        () => h.repo.bulkCreate(any()),
      ).thenAnswer((_) async => throw const ServiceDuplicateFailure());

      // Build 1 (initState snapshot): classic already owned → `locked`.
      // Build 2 (post-409 re-read): art JOINS the owned set → `ownedNow`.
      // Gel is never included in either build and never toggled, so it stays
      // merely off for the whole test.
      final servicesList = _MutatingServicesList(<List<MasterService>>[
        _ownsClassic,
        <MasterService>[
          ..._ownsClassic,
          const MasterService(
            id: 'svc-owned-art',
            serviceDefId: 'def-owned-art',
            name: 'Художній розпис',
            serviceTypeId: 'type-art',
            durationMinutes: 45,
            priceMin: 300,
            priceDisplay: '300 ₴',
          ),
        ],
      ]);

      await _pump(
        tester,
        h,
        surfaceSize: const Size(800, 2000),
        overrides: <Object>[
          serviceRepositoryProvider.overrideWithValue(h.repo),
          servicesListProvider.overrideWith(() => servicesList),
          approvedCategoriesProvider.overrideWith(
            (ref) => const <ServiceCategoryOption>[_manicure],
          ),
          serviceTypesProvider('MANICURE').overrideWith(
            (ref) => const <ServiceTypeOption>[
              _typeClassic,
              _typeGel,
              _typeArt,
            ],
          ),
        ],
      );
      await _expand(tester, 'MANICURE');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      // Include + fill art, then trigger the 409 re-read that claims it.
      await _toggleRowOn(tester, 'type-art');
      await _fillRowFixed(tester, 'type-art', duration: '45', price: '300');
      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      // ── classic — locked (owned at load) ──────────────────────────────
      expect(
        find.byKey(const Key('setup_row_toggle_type-classic')),
        findsNothing,
        reason: 'a locked row renders no include switch at all',
      );
      expect(
        _textInRow('type-classic', l10n.serviceSetupRowAlreadyAdded),
        findsOneWidget,
      );
      expect(
        _textInRow('type-classic', l10n.serviceSetupRowAlreadyInMenu),
        findsNothing,
        reason: 'locked and ownedNow are mutually exclusive facts',
      );
      expect(
        tester
            .widget<Text>(
              _textInRow('type-classic', l10n.serviceSetupRowAlreadyAdded),
            )
            .style
            ?.fontWeight,
        isNot(FontWeight.w800),
        reason:
            'the plain "already added" fact must NOT carry the '
            'catalogue-refresh emphasis style',
      );

      // ── art — ownedNow (claimed by the mid-session catalogue refresh) ──
      expect(
        find.byKey(const Key('setup_row_toggle_type-art')),
        findsOneWidget,
        reason:
            'unlike locked, ownedNow is not the immutable at-load '
            'exclusion — the row keeps its (now-off) switch',
      );
      expect(
        _textInRow('type-art', l10n.serviceSetupRowAlreadyInMenu),
        findsOneWidget,
      );
      expect(
        _textInRow('type-art', l10n.serviceSetupRowAlreadyAdded),
        findsNothing,
        reason: 'ownedNow and locked are mutually exclusive facts',
      );
      final artSubLabelStyle = tester
          .widget<Text>(
            _textInRow('type-art', l10n.serviceSetupRowAlreadyInMenu),
          )
          .style;
      expect(
        artSubLabelStyle?.fontWeight,
        FontWeight.w800,
        reason:
            'ownedNow is the one fact that CHANGED under the master — '
            'it must read as emphasised, not as a routine label',
      );
      expect(artSubLabelStyle?.color, BrandColors.accentDeep);

      // ── gel — merely off (never locked, never claimed) ─────────────────
      expect(
        find.byKey(const Key('setup_row_toggle_type-gel')),
        findsOneWidget,
        reason: 'a merely-off row stays freely selectable',
      );
      // Neither locked nor ownedNow — nothing to say beyond the switch itself.
      _expectRowHasNoOffStateSubLabel(tester, l10n, 'type-gel');

      // ── no row, anywhere on screen, resurrects the deleted generic copy ─
      expect(
        // i18n-finder-ok: pins the exact DELETED literal, not live UI copy — asserts serviceSetupRowExcluded never resurfaces under a new l10n key
        find.text('Не пропонується'),
        findsNothing,
        reason:
            'serviceSetupRowExcluded was deleted from both ARBs — this '
            'pins the exact removed literal, not just a Text count, so a '
            'regression that reintroduces it under a NEW l10n key still '
            'fails this assertion',
      );
      await pumpPastVelvetSnack(tester);
    });
  });

  // ── State-level guard — ServiceRowState.included refuses alreadyAdded ───────
  //
  // The UI-level proof above (no switch rendered) and this state-level proof are
  // deliberately independent: the widget test would still pass if the switch were
  // merely hidden while the flag stayed mutable, and this test would still pass
  // if the card rendered a live switch over an immutable flag. Only both together
  // establish that an owned type cannot reach the payload.

  group('ServiceRowState.alreadyAdded — the included setter hard-refuses', () {
    test('setting included = true on an alreadyAdded row leaves it false and '
        'notifies nobody', () {
      final row = ServiceRowState(
        serviceTypeId: 'type-classic',
        nameUk: 'Класичний манікюр',
        alreadyAdded: true,
      );
      addTearDown(row.dispose);

      var notifications = 0;
      row.addListener(() => notifications++);

      expect(row.included, isFalse);

      row.included = true;

      expect(
        row.included,
        isFalse,
        reason:
            'the setter must refuse — this is the single choke point that stops '
            'any call site (a stray toggle, a future "select all") smuggling an '
            'owned type into the all-or-nothing bulk payload',
      );
      expect(
        notifications,
        0,
        reason: 'a refused write must not fake a state change to listeners',
      );
    });

    test(
      'a NON-owned row still toggles normally — the guard is not blanket',
      () {
        final row = ServiceRowState(
          serviceTypeId: 'type-gel',
          nameUk: 'Гель-лак',
        );
        addTearDown(row.dispose);

        var notifications = 0;
        row.addListener(() => notifications++);

        row.included = true;

        expect(row.included, isTrue);
        expect(notifications, 1);
      },
    );

    test(
      'an alreadyAdded row can still be set FALSE (idempotent, no throw)',
      () {
        final row = ServiceRowState(
          serviceTypeId: 'type-classic',
          nameUk: 'Класичний манікюр',
          alreadyAdded: true,
        );
        addTearDown(row.dispose);

        row.included = false;

        expect(row.included, isFalse);
      },
    );
  });

  // ── SETUP vs APPEND copy ───────────────────────────────────────────────────
  //
  // One screen, two framings. `_appending` is derived ONCE in initState from
  // `servicesListProvider.value` being non-empty. Both directions are asserted
  // (and each asserts the OTHER variant is absent) so the switch is genuinely
  // pinned rather than accidentally satisfied by a shared substring.

  group('SETUP vs APPEND copy', () {
    testWidgets(
      'a NON-EMPTY catalogue uses the APPEND title + «Додати N» CTA',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
            // Owns something UNRELATED — APPEND framing with no row exclusion,
            // so this test isolates the copy switch from the exclusion logic.
            existingServices: _ownsUnrelated,
          ),
        );
        await _expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.text(l10n.serviceSetupTitleAppend), findsOneWidget);
        expect(find.text(l10n.serviceSetupTitle), findsNothing);

        await _toggleRowOn(tester, 'type-classic');

        expect(find.text(l10n.serviceSetupCtaAdd(1)), findsOneWidget);
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsNothing);
      },
    );

    testWidgets('an EMPTY catalogue uses the SETUP title + «Створити N» CTA', (
      tester,
    ) async {
      await _pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[_typeClassic],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await _expand(tester, 'MANICURE');

      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      expect(find.text(l10n.serviceSetupTitle), findsOneWidget);
      expect(find.text(l10n.serviceSetupTitleAppend), findsNothing);

      await _toggleRowOn(tester, 'type-classic');

      expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
      expect(find.text(l10n.serviceSetupCtaAdd(1)), findsNothing);
    });
  });

  // ── 503 BulkSetupBusyFailure — retry, and STAY on the screen ───────────────
  //
  // The per-master bulk lock was held past the backend's 3 s ceiling. The batch
  // is all-or-nothing, so NOTHING was written: the master's whole configuration
  // is still valid and a retry is the only useful next action. The screen must
  // therefore keep them where they are and hand them an explicit RETRY.
  //
  // The failure is stubbed ASYNCHRONOUSLY (`thenAnswer((_) async => throw …)`),
  // never `thenThrow`: a Dio-backed repository always fails asynchronously, and
  // a synchronous throw takes a different path through the notifier's
  // AsyncValue.guard than the one production hits.

  group('503 BulkSetupBusyFailure — retryable snackbar, no navigation', () {
    /// Stands up a single valid included row and taps save. Returns a counter
    /// that the bulkCreate stub increments on EVERY call, so the retry action's
    /// effect is observable as 1 → 2 rather than inferred.
    Future<int Function()> failingSaveOnce(
      WidgetTester tester,
      Failure failure,
    ) async {
      var calls = 0;
      when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
        calls++;
        throw failure;
      });

      await _pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[_typeClassic],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await _expand(tester, 'MANICURE');
      await _toggleRowOn(tester, 'type-classic');
      await _fillRowFixed(tester, 'type-classic', duration: '60', price: '500');

      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();

      return () => calls;
    }

    testWidgets(
      'shows serviceSetupErrBusy with a RETRY action, keeps the master on the '
      'screen, and the action re-invokes bulkCreate (1 → 2)',
      (tester) async {
        final calls = await failingSaveOnce(
          tester,
          const BulkSetupBusyFailure(),
        );

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(calls(), 1);

        // The retry affordance itself — remove `onRetry` from lib/ and this is
        // the assertion that goes red. expectVelvetSnack's `actionLabel` param
        // asserts the trailing action text renders on the showing snack.
        expectVelvetSnack(
          l10n.serviceSetupErrBusy,
          variant: VelvetSnackVariant.error,
          actionLabel: l10n.serviceSetupRetry,
        );

        // The master stays put with their configuration intact.
        expect(find.byType(ServiceSetupScreen), findsOneWidget);
        expect(
          h.pushedRoutes,
          isEmpty,
          reason:
              'a 503 wrote nothing — navigating away would discard a still-'
              'valid selection',
        );
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);

        // Tapping RETRY re-submits — the observable proof that the action is
        // wired to _save and not a no-op label.
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(
          calls(),
          2,
          reason: 'the RETRY action must re-run the save, not merely dismiss',
        );
        expect(find.byType(ServiceSetupScreen), findsOneWidget);
        expect(h.pushedRoutes, isEmpty);
        // The retry re-fired the same (still-failing) save, which shows a
        // SECOND retryable snack — drain it so its dwell timer does not leak.
        await pumpPastVelvetSnack(tester, hasAction: true);
      },
    );

    testWidgets(
      'a NON-retryable failure (409) shows no action-carrying VelvetSnack — '
      'the retry affordance is specific to the 503 branch',
      (tester) async {
        final calls = await failingSaveOnce(
          tester,
          const ServiceDuplicateFailure(),
        );
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(calls(), 1);
        expect(
          find.text(l10n.serviceSetupRetry),
          findsNothing,
          reason:
              'only the transient 503 gets a RETRY; a duplicate would fail '
              'identically on every retry',
        );
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── 409 ServiceDuplicateFailure on save — stay, do NOT pop ─────────────────
  //
  // In APPEND mode owned types are already un-includable, so reaching a 409 means
  // the catalogue changed underneath the screen (another device, or a type added
  // since it mounted). The batch was rolled back, so the selection is still
  // meaningful: the screen refreshes its snapshot sources and keeps the master
  // here to deselect the offender and re-save. Forcing a navigation would throw
  // away their unsaved configuration.

  group('409 ServiceDuplicateFailure on save keeps the selection', () {
    Future<void> pumpWithSingleValidRow(WidgetTester tester) async {
      await _pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[_typeClassic],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await _expand(tester, 'MANICURE');
      await _toggleRowOn(tester, 'type-classic');
      await _fillRowFixed(tester, 'type-classic', duration: '60', price: '500');

      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'shows serviceErrDuplicate and does NOT leave the screen (the selection '
      'survives)',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => throw const ServiceDuplicateFailure());

        await pumpWithSingleValidRow(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(find.text(l10n.serviceErrDuplicate), findsOneWidget);

        expect(
          find.byType(ServiceSetupScreen),
          findsOneWidget,
          reason:
              'the batch was rolled back — popping would discard the master\'s '
              'unsaved configuration',
        );
        expect(h.pushedRoutes, isEmpty);
        // The row is still included AND still carries its typed values.
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find
                    .descendant(
                      of: find.byKey(const Key('setup_row_type-classic')),
                      matching: find.byType(TextField),
                    )
                    .first,
              )
              .controller
              ?.text,
          '60',
        );
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'CONTRAST — the identical flow with a SUCCESSFUL save DOES leave for the '
      'services list',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => _createdService);

        await pumpWithSingleValidRow(tester);

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        verify(() => h.repo.bulkCreate(any())).called(1);
        expect(find.text(l10n.serviceSetupSuccess), findsOneWidget);
        expect(
          h.pushedRoutes,
          contains(RouteNames.services),
          reason:
              'only the success path leaves — this is what makes the 409 "stays "'
              'assertion above meaningful rather than vacuous',
        );
        expect(find.byType(ServiceSetupScreen), findsNothing);
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── Request affordances — missing CATEGORY strip + per-category TYPE prompt ─
  //
  // Two requests with different scopes. The category strip sits above the chip
  // Wrap and takes no argument; the service-type prompt closes each expanded
  // category's rows and MUST forward that category's own wire slug. A prompt
  // that opens the dialog for the wrong category is the bug worth catching, so
  // the slug is read off the mounted dialog widget rather than inferred from the
  // fact that a dialog appeared.

  group('request affordances (category strip + per-category type prompt)', () {
    testWidgets('tapping btn-setup-request-category opens the category-request '
        'dialog', (tester) async {
      await _pump(
        tester,
        h,
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          existingServices: const <MasterService>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CategoryRequestDialog), findsNothing);

      await tester.tap(find.byKey(const Key('btn-setup-request-category')));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryRequestDialog), findsOneWidget);
      expect(
        find.byKey(const Key('field-category-request-name')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('btn-submit-suggest-category')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a successful category request invalidates the catalogue and snackbars '
      'categoryRequestSuccess',
      (tester) async {
        when(
          () => h.repo.requestCategory(
            name: any(named: 'name'),
            displayName: any(named: 'displayName'),
            initialServiceName: any(named: 'initialServiceName'),
          ),
        ).thenAnswer((_) async {});

        await _pump(
          tester,
          h,
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            existingServices: const <MasterService>[],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn-setup-request-category')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-category-request-name')),
            matching: find.byType(TextField),
          ),
          'Нарощування вій',
        );
        await tester.tap(find.byKey(const Key('btn-submit-suggest-category')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.byType(CategoryRequestDialog), findsNothing);
        expect(find.text(l10n.categoryRequestSuccess), findsOneWidget);
        verify(
          () => h.repo.requestCategory(
            name: any(named: 'name'),
            displayName: 'Нарощування вій',
            initialServiceName: any(named: 'initialServiceName'),
          ),
        ).called(1);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'each expanded category closes with its OWN suggest-type prompt, and the '
      'prompt threads THAT category\'s slug into the dialog',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[
              _manicure,
              _hair,
            ]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
              'HAIR': <ServiceTypeOption>[_typeCut],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');
        await _expand(tester, 'HAIR');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // One prompt per expanded category, each labelled with the category's
        // Ukrainian DISPLAY name (not its wire slug).
        expect(
          find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('suggest_type_HAIR')),
          findsOneWidget,
        );
        // Derived from the FIXTURES' own displayName rather than repeating the
        // literal: the label under test is exactly "whatever display name that
        // category carries", so sourcing it from the fixture proves the wiring
        // instead of proving two copies of a string match. It also keeps the
        // finder locale-free (`scripts/forbid_cyrillic_finder.sh`) — a
        // hardcoded 'Манікюр' here would silently become findsNothing the day
        // EN ships.
        expect(
          find.text(l10n.serviceSetupMissingTypePrompt(_manicure.displayName)),
          findsOneWidget,
        );
        expect(
          find.text(l10n.serviceSetupMissingTypePrompt(_hair.displayName)),
          findsOneWidget,
        );

        // Tap the SECOND category's prompt. If the prompt were wired to the
        // wrong category (or to one shared handler) the dialog would carry
        // 'MANICURE' and this would go red.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('suggest_type_HAIR')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('suggest_type_HAIR')),
                matching: find.byType(GestureDetector),
              )
              .last,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ServiceTypeSuggestionDialog), findsOneWidget);
        expect(
          tester
              .widget<ServiceTypeSuggestionDialog>(
                find.byType(ServiceTypeSuggestionDialog),
              )
              .categoryName,
          'HAIR',
          reason:
              'the prompt must forward its OWN category slug — a suggestion '
              'filed against the wrong category is silently wrong data',
        );
        expect(
          find.byKey(const Key('field-service-type-suggest-name')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the MANICURE prompt opens the dialog for MANICURE (the mirror of the '
      'HAIR case, so neither slug is hard-coded)',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[
              _manicure,
              _hair,
            ]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
              'HAIR': <ServiceTypeOption>[_typeCut],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');
        await _expand(tester, 'HAIR');

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
                matching: find.byType(GestureDetector),
              )
              .last,
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<ServiceTypeSuggestionDialog>(
                find.byType(ServiceTypeSuggestionDialog),
              )
              .categoryName,
          'MANICURE',
        );
      },
    );

    testWidgets(
      'a successful service-type suggestion snackbars serviceTypeSuggestSuccess',
      (tester) async {
        when(
          () => h.repo.suggestServiceType(
            categoryName: any(named: 'categoryName'),
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async {});

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');

        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
                matching: find.byType(GestureDetector),
              )
              .last,
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-service-type-suggest-name')),
            matching: find.byType(TextField),
          ),
          'Ламінування вій',
        );
        await tester.tap(
          find.byKey(const Key('btn-submit-suggest-service-type')),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(find.byType(ServiceTypeSuggestionDialog), findsNothing);
        expect(find.text(l10n.serviceTypeSuggestSuccess), findsOneWidget);
        verify(
          () => h.repo.suggestServiceType(
            categoryName: 'MANICURE',
            name: 'Ламінування вій',
            description: any(named: 'description'),
          ),
        ).called(1);
        await pumpPastVelvetSnack(tester);
      },
    );

    // ── The invalidate after a suggestion must actually REFRESH ──────────────
    //
    // `_suggestServiceType` ends with `ref.invalidate(serviceTypesProvider(slug))`
    // so an auto-approved suggestion "can appear on the next expand". That is a
    // behavioural promise, not a cosmetic one, and it is the only mechanism by
    // which a master ever sees the type they just suggested without killing the
    // app.
    //
    // The promise is currently BROKEN and the break is invisible: dropping the
    // provider does nothing, because `_toggleCategory` short-circuits on
    // `_rowsByCategory.containsKey(slug)` and re-expanding therefore never
    // re-reads the provider. Nothing in the 889-test suite noticed, because
    // every other test asserts only that the dialog closed and the snackbar
    // rendered.
    //
    // This test drives the OBSERVABLE consequence — re-expanding shows the
    // refreshed list — and additionally counts provider builds, so it fails on
    // the CAUSE (no refetch) rather than only on the symptom.
    testWidgets(
      'after a successful suggestion, re-expanding the category REFETCHES its '
      'types and renders the newly approved one',
      (tester) async {
        when(
          () => h.repo.suggestServiceType(
            categoryName: any(named: 'categoryName'),
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async {});

        // Counts real provider BUILDS. The first build models the catalogue
        // before the suggestion; every later one models the backend having
        // auto-approved it, so the refreshed list carries the extra type.
        var typeFetches = 0;

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          // Hand-built rather than via `h.overrides`: this test needs a
          // serviceTypesProvider override whose RESULT CHANGES between builds,
          // which the map-shaped helper cannot express. Duplicating a provider
          // override (helper list + extra entry) throws in Riverpod, so the
          // list is assembled once here.
          overrides: <Object>[
            serviceRepositoryProvider.overrideWithValue(h.repo),
            servicesListProvider.overrideWith(
              () => _SeededServicesList(const <MasterService>[]),
            ),
            approvedCategoriesProvider.overrideWith(
              (ref) => const <ServiceCategoryOption>[_manicure],
            ),
            serviceTypesProvider('MANICURE').overrideWith((ref) {
              typeFetches++;
              return typeFetches == 1
                  ? const <ServiceTypeOption>[_typeClassic]
                  : const <ServiceTypeOption>[_typeClassic, _typeGel];
            }),
          ],
        );
        await _expand(tester, 'MANICURE');

        // Baseline: exactly one build so far, and the not-yet-suggested type is
        // absent. This is the control that makes the post-suggestion assertion
        // non-vacuous — without it, a `findsOneWidget` on type-gel could be
        // satisfied by the type having been there all along.
        expect(typeFetches, 1);
        expect(find.byKey(const Key('setup_row_type-classic')), findsOneWidget);
        expect(find.byKey(const Key('setup_row_type-gel')), findsNothing);

        // Suggest a type for MANICURE and let it succeed.
        await tester.ensureVisible(
          find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('suggest_type_MANICURE')),
                matching: find.byType(GestureDetector),
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byKey(const Key('field-service-type-suggest-name')),
            matching: find.byType(TextField),
          ),
          'Ламінування вій',
        );
        await tester.tap(
          find.byKey(const Key('btn-submit-suggest-service-type')),
        );
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.serviceTypeSuggestSuccess), findsOneWidget);
        // Drain the still-showing snack BEFORE the next tap: it is
        // bottom-anchored and would otherwise sit over the category chip,
        // hit-testing into the overlay and silently swallowing the tap below.
        await pumpPastVelvetSnack(tester);

        // Collapse, then re-expand — «the next expand», exactly as the
        // invalidate's own doc comment promises.
        await _expand(tester, 'MANICURE'); // collapse
        await _expand(tester, 'MANICURE'); // re-expand

        expect(
          typeFetches,
          greaterThanOrEqualTo(2),
          reason:
              'the invalidate is dead unless a re-expand actually re-reads the '
              'provider — `_toggleCategory` returns early on '
              '`_rowsByCategory.containsKey(slug)`, so the cached rows must be '
              'dropped alongside the invalidate for the refresh to happen',
        );
        expect(
          find.byKey(const Key('setup_row_type-gel')),
          findsOneWidget,
          reason:
              'a master who suggests a type and is told it was submitted must '
              'be able to see and configure it once approved, without '
              'restarting the app',
        );
      },
    );
  });

  // ── 503 RETRY AFTER LEAVING — the snack must not survive with a live action ─
  //
  // `_showErrorSnack` posts a VelvetSnack on the app's ROOT `Overlay` (see
  // `velvet_snack_host.dart`), which — like the retired `ScaffoldMessenger`-
  // backed bar before it — is NOT scoped to this route's own Navigator. So
  // WITHOUT the explicit `dispose()` → `unawaited(_retrySnack?.dismiss())`
  // call, the 503 snack (deliberately given the longer `dwellWithAction`, 6s,
  // so it is still up while the master decides) would survive a pop/go away
  // from the setup screen, with its «Повторити» action still wired to `_save`
  // on a State that is by then DISPOSED.
  //
  // `_save`'s very first statement is `AppLocalizations.of(context)`, so a tap
  // on a still-live action does not degrade — it throws on a deactivated
  // element. `dispose()`'s explicit dismiss is the fix; this test asserts the
  // INVARIANT it guarantees — no exception, and no second POST — leaving room
  // for the snack to still be mid-exit-animation at the moment we check rather
  // than asserting it is instantly gone.

  group('503 retry AFTER leaving the screen (disposed-state crash)', () {
    testWidgets(
      'tapping the retry action once the master has left must not throw and '
      'must not re-POST',
      (tester) async {
        var calls = 0;
        when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
          calls++;
          // Async, never `thenThrow` — a Dio-backed repository always fails
          // asynchronously, and a sync throw takes a different path through the
          // notifier's AsyncValue.guard than production hits.
          throw const BulkSetupBusyFailure();
        });

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');
        await _toggleRowOn(tester, 'type-classic');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Precondition: the 503 branch ran and put its retry bar up.
        expect(calls, 1);
        expect(find.text(l10n.serviceSetupRetry), findsOneWidget);

        // Leave the screen the way a master would — the close affordance.
        await tester.tap(find.byKey(const Key('btn-setup-close')));
        await tester.pumpAndSettle();
        expect(
          find.byType(ServiceSetupScreen),
          findsNothing,
          reason:
              'precondition: the setup screen is gone and its State is '
              'disposed',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'leaving the screen must not throw on its own',
        );

        // `dispose()`'s `unawaited(_retrySnack?.dismiss())` starts an async
        // exit animation, so the snack may still be mid-teardown for a frame
        // or two — this stays a conditional tap (not an unconditional
        // `findsNothing`) so the test is not coupled to that animation timing.
        // Either way, "still there AND still live enough to crash on tap" is
        // the one outcome that must never happen.
        final Finder retry = find.text(l10n.serviceSetupRetry);
        if (retry.evaluate().isNotEmpty) {
          await tester.tap(retry);
          await tester.pumpAndSettle();
        }

        expect(
          tester.takeException(),
          isNull,
          reason:
              'even if the snack outlives the route for a frame (it lives on '
              'the ROOT Overlay, not scoped to this route), invoking its '
              'action must never run _save against a disposed ConsumerState '
              '(AppLocalizations.of on a deactivated element throws)',
        );
        expect(
          calls,
          1,
          reason:
              'a retry fired from a screen the master has already left must '
              'not silently POST their abandoned selection',
        );
      },
    );

    testWidgets(
      'CONTROL — retrying WITHOUT leaving still re-POSTs, so the assertion '
      'above is about the disposed state and not about retry being broken',
      (tester) async {
        var calls = 0;
        when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
          calls++;
          throw const BulkSetupBusyFailure();
        });

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');
        await _toggleRowOn(tester, 'type-classic');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(calls, 1);

        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(calls, 2);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── _retrySnack handle lifetime ────────────────────────────────────────────
  //
  // `dispose` dismisses the tracked 503 snack so a route the master left cannot
  // leave a live retry action behind.
  //
  // This group predates the VelvetSnack migration and originally pinned a
  // `ScaffoldFeatureController`-specific footgun: a handle whose bar had
  // already left the `ScaffoldMessenger` queue (by timeout, swipe, or a third
  // party clearing it) made `close()` operate on an EMPTY queue —
  // `assert(_snackBars.first == controller)` threw `StateError: No element` in
  // debug, and silently killed an unrelated bar in release. `_retrySnack` had
  // to be nulled the instant its bar left the queue by any route OTHER than
  // `_showSnack` replacing it or `dispose` closing it, tracked via
  // `controller.closed.whenComplete` + an `identical()` guard against a
  // slow-completing older bar nulling a newer handle.
  //
  // VelvetSnack removes the whole footgun structurally: [VelvetSnackHandle]
  // wraps a `GlobalKey`, and `dismiss()` is `_key.currentState?.retire(...)` —
  // null-safe by construction. Calling `dismiss()` on a handle whose snack
  // already retired (by timeout, swipe, or single-slot pre-emption from a
  // NEWER snack) is simply a no-op; there is no queue to be out of sync with,
  // and no `identical()` guard is needed because `_showErrorSnack` overwrites
  // `_retrySnack` SYNCHRONOUSLY when it posts a new snack (no async completion
  // race to lose to). The tests below are kept as the regression net for that
  // null-safety property, updated for the mechanism that actually makes them
  // pass now.
  //
  // ALSO NOTE — the timeout IS now a reachable removal path, unlike before.
  // The old `SnackBar` set `persist = persist ?? action != null`, so a bar
  // carrying a `SnackBarAction` never auto-dismissed at all. VelvetSnack has no
  // such escape hatch: an action-carrying snack dwells LONGER
  // (`VelvetSnackMotion.dwellWithAction`, 6s, vs the plain 4s) but still
  // eventually retires on its own. The first test below pins that dwell
  // window instead of pinning eternal persistence.

  group('_retrySnack is dropped when its bar goes away on its own', () {
    /// Stands up one valid row, saves into a 503, and returns once the retry
    /// bar is up. The stub keeps failing, so a retry would 503 again.
    Future<void> saveInto503(WidgetTester tester) async {
      when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
        throw const BulkSetupBusyFailure();
      });

      await _pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[_typeClassic],
          },
          existingServices: const <MasterService>[],
        ),
      );
      await _expand(tester, 'MANICURE');
      await _toggleRowOn(tester, 'type-classic');
      await _fillRowFixed(tester, 'type-classic', duration: '60', price: '500');
      await tester.tap(find.byKey(const Key('btn-setup-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('the 503 snack carries an action, so it dwells the LONGER '
        'dwellWithAction window (6s) rather than the plain 4s — but, unlike '
        'the retired SnackBar `persist` footgun, it still eventually retires '
        'on its own', (tester) async {
      await saveInto503(tester);
      final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

      expect(find.text(l10n.serviceSetupRetry), findsOneWidget);

      // Past the PLAIN dwell (4s) but comfortably short of the action dwell
      // (6s) — proves the retry snack is using `dwellWithAction`, not the
      // shorter default, giving the master real time to reach the action.
      // fixed-wait-ok: probing a dwell WINDOW, not a race — the margin below
      // the 6s ceiling is deliberate, not a flaky timing guess.
      await tester.pump(VelvetSnackMotion.dwell + const Duration(seconds: 1));
      expect(
        find.text(l10n.serviceSetupRetry),
        findsOneWidget,
        reason:
            'a snack carrying an action must dwell VelvetSnackMotion.'
            'dwellWithAction (6s), not the plain 4s dwell — if this goes '
            'red the retry snack started expiring before the master can '
            'realistically reach the action',
      );

      // Unlike the retired ScaffoldMessenger-backed bar (`persist = persist
      // ?? action != null`, which NEVER auto-dismissed a bar carrying a
      // SnackBarAction), VelvetSnack has no such escape hatch — it always
      // eventually retires an action-carrying snack too, just later.
      await pumpPastVelvetSnack(tester, hasAction: true);
      expect(
        find.text(l10n.serviceSetupRetry),
        findsNothing,
        reason:
            'VelvetSnack auto-retires eventually even with an action — '
            'this is the deliberate behaviour change from the old SnackBar '
            '`persist` footgun this migration removes',
      );
    });

    testWidgets(
      'a 503 snack SWIPED away, then a dispose, must not throw — dismiss() '
      'on an already-retired handle is a safe no-op',
      (tester) async {
        await saveInto503(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        expect(
          find.text(l10n.serviceSetupRetry),
          findsOneWidget,
          reason: 'precondition: the 503 branch put its retry snack up',
        );

        // The reachable unattended removal: the master flicks the snack away
        // rather than acting on it. VelvetSnack wires the exact same
        // `Dismissible` (DismissDirection.down) the old SnackBar did — see
        // `velvet_snack_host.dart`'s `_VelvetSnackScope.build()`.
        await tester.fling(
          find.byType(VelvetSnack),
          const Offset(0, 300),
          1000,
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.serviceSetupRetry),
          findsNothing,
          reason:
              'precondition: the swipe really removed the snack. If it is '
              'still up, the dispose assertion below is vacuous',
        );

        // Now leave. `dispose` will call `_retrySnack?.dismiss()`.
        await tester.tap(find.byKey(const Key('btn-setup-close')));
        await tester.pumpAndSettle();

        expect(
          find.byType(ServiceSetupScreen),
          findsNothing,
          reason: 'precondition: the State really was disposed',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              'the swipe already retired the underlying `_VelvetSnackScopeState`'
              ', so its `GlobalKey.currentState` is null by the time dispose '
              'calls dismiss() — `VelvetSnackHandle.dismiss()` is null-safe by '
              'construction (`_key.currentState?.retire(...)`), unlike the '
              'retired `ScaffoldFeatureController.close()`, which asserted '
              '`_snackBars.first == controller` and threw on an empty queue',
        );
      },
    );

    testWidgets(
      'two 503s in a row — the second snack is still owned, so leaving '
      'dismisses it (the first snack retiring must not null the newer '
      'handle)',
      (tester) async {
        await saveInto503(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Retry immediately: `_showErrorSnack` posts a second retry snack,
        // which pre-empts (retires) the first via the single-slot host, and
        // SYNCHRONOUSLY overwrites `_retrySnack` with the new handle — no
        // async completion race to lose to (see the group doc comment above).
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.serviceSetupRetry),
          findsOneWidget,
          reason: 'precondition: the retry 503 posted a fresh retry snack',
        );

        await tester.tap(find.byKey(const Key('btn-setup-close')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text(l10n.serviceSetupRetry),
          findsNothing,
          reason:
              'dispose must still own the SECOND snack and dismiss it. If the '
              'first snack retiring had nulled `_retrySnack`, this snack would '
              'outlive the route with a live action bound to a disposed State',
        );
      },
    );

    testWidgets(
      '503 then SUCCESS — the untracked success snack survives the pop and '
      'the stale retry handle takes nothing with it',
      (tester) async {
        var calls = 0;
        when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
          calls++;
          if (calls == 1) throw const BulkSetupBusyFailure();
          return const <MasterService>[];
        });

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic],
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');
        await _toggleRowOn(tester, 'type-classic');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.serviceSetupRetry), findsOneWidget);

        // The retry succeeds: the single-slot VelvetSnack host pre-empts the
        // still-showing retry snack with an UNTRACKED success snack (never
        // routed through `_retrySnack`), and the screen leaves. The old
        // retry snack's underlying state retires as part of that
        // pre-emption, so `_retrySnack` — still holding THAT handle, since
        // the success path never touches the field — is stale by the time
        // dispose runs.
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(calls, 2);
        expect(tester.takeException(), isNull);
        expect(
          find.byType(ServiceSetupScreen),
          findsNothing,
          reason:
              'precondition: success replaces the setup route with the list',
        );
        expect(
          find.text(l10n.serviceSetupSuccess),
          findsOneWidget,
          reason:
              'the success snack is deliberately NOT tracked, so dispose '
              '(dismissing only the stale `_retrySnack` handle, a safe no-op '
              'here) must leave it alone — the master reads the confirmation '
              'on the list screen they were just returned to',
        );
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── Nullable serviceTypeId degrades toward UNDER-blocking ──────────────────
  //
  // `MasterService.serviceTypeId` is nullable: a pre-Phase-16.3 row carries no
  // type id. `_ownedServiceTypeIds` is built with
  // `if (s.serviceTypeId case final String id when id.isNotEmpty)`, so such a
  // row contributes nothing and the corresponding type stays SELECTABLE.
  //
  // That direction is a deliberate product call, and it is the direction worth
  // pinning: over-blocking would hide a service the master cannot add any other
  // way (this screen is now the ONLY "add services" surface), whereas
  // under-blocking costs at most one recoverable, explained 409.
  //
  // The fixture's display name is identical to the service-type's, so a
  // "helpful" future change that matched owned services by NAME instead of ID
  // turns this test red immediately.

  group('APPEND with an untyped legacy service — exclusion is by ID only', () {
    testWidgets(
      'a catalogue row with a null serviceTypeId blocks NOTHING, even when its '
      'name matches a service type exactly',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
            existingServices: _ownsUntypedLegacyRow,
          ),
        );
        await _expand(tester, 'MANICURE');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // The catalogue is non-empty, so the screen IS in APPEND mode — this
        // proves the snapshot was read and non-empty, i.e. the assertions below
        // are about the ID filter and not about the screen having silently
        // fallen back to SETUP.
        expect(
          find.text(l10n.serviceSetupTitleAppend),
          findsOneWidget,
          reason:
              'precondition: a non-empty catalogue must select APPEND framing, '
              'otherwise this test would pass trivially in SETUP mode',
        );

        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsOneWidget,
          reason:
              'an untyped legacy row cannot be matched to a service type, so '
              'the type must stay selectable — degrading to a recoverable 409 '
              'beats hiding a service the master has no other way to add',
        );
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsOneWidget,
        );
        expect(find.text(l10n.serviceSetupRowAlreadyAdded), findsNothing);
        expect(find.text(l10n.serviceSetupAllAlreadyAdded), findsNothing);
        // The denominator counts both types — nothing was excluded.
        expect(find.text(l10n.serviceSetupGroupCount(0, 2)), findsOneWidget);
      },
    );

    testWidgets(
      'CONTRAST — the SAME row carrying the matching serviceTypeId DOES block '
      'it, so the test above is about the null and not about the fixture',
      (tester) async {
        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 1800),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': <ServiceTypeOption>[_typeClassic, _typeGel],
            },
            existingServices: _ownsClassic,
          ),
        );
        await _expand(tester, 'MANICURE');

        expect(
          find.byKey(const Key('setup_row_toggle_type-classic')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('setup_row_toggle_type-gel')),
          findsOneWidget,
        );
      },
    );
  });

  // ── _flagRowsNowOwned — the 409 catalogue re-read (E) ──────────────────────
  //
  // The 409 handler now re-reads the master's catalogue and switches OFF only
  // the included rows the REFRESHED list actually claims, flagging each
  // `alreadyInMenu`. The claim in the source comment is explicit and narrow:
  // "Every other selection, and every typed value, is untouched."
  //
  // That second half is the part worth pinning. A re-read that resets the whole
  // form would also make the first half's assertion pass, so both directions
  // are asserted in the same test against the SAME screen state — one row that
  // must change, one that must not.

  group('409 catalogue re-read switches off ONLY the newly-owned rows', () {
    testWidgets(
      'the row the refreshed catalogue claims goes off and says «already in '
      'menu»; the other row keeps BOTH its selection and its typed values',
      (tester) async {
        when(
          () => h.repo.bulkCreate(any()),
        ).thenAnswer((_) async => throw const ServiceDuplicateFailure());

        // Build 1 is the initState snapshot: an EMPTY catalogue, so both types
        // are freely includable and the screen takes SETUP framing. Build 2 —
        // the read `_flagRowsNowOwned` performs after the handler's invalidate
        // — is the catalogue having gained CLASSIC behind the master's back.
        // That divergence is the whole scenario: a fixed seed would have seeded
        // `alreadyAdded` true on classic, making it un-includable and the 409
        // unreachable.
        final servicesList = _MutatingServicesList(<List<MasterService>>[
          const <MasterService>[],
          _ownsClassic,
        ]);

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2000),
          overrides: <Object>[
            serviceRepositoryProvider.overrideWithValue(h.repo),
            servicesListProvider.overrideWith(() => servicesList),
            approvedCategoriesProvider.overrideWith(
              (ref) => const <ServiceCategoryOption>[_manicure],
            ),
            serviceTypesProvider('MANICURE').overrideWith(
              (ref) => const <ServiceTypeOption>[_typeClassic, _typeGel],
            ),
          ],
        );
        await _expand(tester, 'MANICURE');

        await _toggleRowOn(tester, 'type-classic');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '60',
          price: '500',
        );
        await _toggleRowOn(tester, 'type-gel');
        await _fillRowFixed(tester, 'type-gel', duration: '90', price: '700');

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        // Precondition: BOTH rows are included, so the post-409 count drop is
        // attributable to the re-read and not to a row that was never on.
        expect(
          find.text(l10n.serviceSetupCtaCreate(2)),
          findsOneWidget,
          reason:
              'precondition: two included rows before the save, otherwise the '
              '"only one was switched off" assertion below is vacuous',
        );

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();

        // The re-read actually happened.
        expect(
          servicesList.builds,
          greaterThanOrEqualTo(2),
          reason:
              '_flagRowsNowOwned must re-read the catalogue after the '
              'invalidate — with one build it is the stale initState snapshot '
              'answering, which can never claim a new row',
        );

        // ── The row that must change ────────────────────────────────────────
        expect(
          _textInRow('type-classic', l10n.serviceSetupRowAlreadyInMenu),
          findsOneWidget,
          reason:
              'the refreshed catalogue claims classic, so its row must be '
              'switched off AND say so — going quiet silently is the other bad '
              'option this copy exists to avoid',
        );

        // ── The row that must NOT change ────────────────────────────────────
        expect(
          _textInRow('type-gel', l10n.serviceSetupRowAlreadyInMenu),
          findsNothing,
          reason:
              'the refreshed catalogue does NOT claim gel, so a re-read that '
              'flags it is over-reaching',
        );
        expect(
          find.text(l10n.serviceSetupCtaCreate(1)),
          findsOneWidget,
          reason:
              'exactly one row was switched off — a count of 0 would mean the '
              're-read wiped the whole selection, which is the failure mode the '
              '"every other selection is untouched" promise rules out',
        );
        // Gel's card is still EXPANDED (it is still included), so its typed
        // values are still on screen to be read back.
        expect(
          _durationText(tester, 'type-gel'),
          '90',
          reason:
              'the untouched row must keep the duration the master typed — a '
              're-read that rebuilds rows from scratch loses it',
        );
        expect(
          _fixedPriceText(tester, 'type-gel'),
          '700',
          reason: 'and its price',
        );
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── _retryingAfterBusy latch (D) ───────────────────────────────────────────
  //
  // A 503 retry can land on a 409 whose meaning is genuinely ambiguous: an edge
  // proxy can return 503 AFTER the write committed, so "duplicate" may mean
  // "your own previous attempt succeeded". The latch swaps the copy for exactly
  // that case.
  //
  // A latch is only as good as its clearing. `_save` consumes it into a local
  // and resets it on the FIRST statement after the mounted guard, so an
  // intervening non-409 failure must leave the next ordinary duplicate reported
  // as a plain duplicate. A latch cleared only inside the 409 branch would pass
  // the first test below and fail the second.

  group('_retryingAfterBusy — ambiguous-duplicate copy is armed, then cleared', () {
    /// Fails `bulkCreate` with `failures` in order, repeating the last one.
    void seedFailures(List<Failure> failures, void Function(int) onCall) {
      var calls = 0;
      when(() => h.repo.bulkCreate(any())).thenAnswer((_) async {
        final Failure f = failures[calls.clamp(0, failures.length - 1)];
        calls++;
        onCall(calls);
        throw f;
      });
    }

    Future<void> pumpOneIncludedRow(WidgetTester tester) async {
      await _pump(
        tester,
        h,
        surfaceSize: const Size(800, 1800),
        overrides: h.overrides(
          categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
          typesBySlug: <String, List<ServiceTypeOption>>{
            'MANICURE': <ServiceTypeOption>[_typeClassic],
          },
          // Empty, so `_flagRowsNowOwned` early-returns on an empty owned set
          // and cannot disturb the selection between saves.
          existingServices: const <MasterService>[],
        ),
      );
      await _expand(tester, 'MANICURE');
      await _toggleRowOn(tester, 'type-classic');
      await _fillRowFixed(tester, 'type-classic', duration: '60', price: '500');
    }

    testWidgets(
      'a 409 landing on a 503 RETRY reports the ambiguous "may already have '
      'saved" copy, not the plain duplicate',
      (tester) async {
        var seen = 0;
        seedFailures(const <Failure>[
          BulkSetupBusyFailure(),
          ServiceDuplicateFailure(),
        ], (c) => seen = c);

        await pumpOneIncludedRow(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();
        expect(seen, 1);
        expect(find.text(l10n.serviceSetupRetry), findsOneWidget);

        // The retry arms the latch, then re-saves into the 409.
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();

        expect(seen, 2);
        expect(
          find.text(l10n.serviceSetupErrDuplicateAfterRetry),
          findsOneWidget,
          reason:
              'after a 503 the batch fate is unknown, so the copy must claim '
              'neither outcome and point the master at their list',
        );
        expect(
          find.text(l10n.serviceErrDuplicate),
          findsNothing,
          reason:
              'the plain duplicate copy asserts the save definitely did not '
              'happen — exactly the claim this path cannot make',
        );
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'the latch does NOT survive a non-409 failure — a later ordinary '
      'duplicate is reported plainly',
      (tester) async {
        var seen = 0;
        seedFailures(const <Failure>[
          // 1: the 503 that offers the retry.
          BulkSetupBusyFailure(),
          // 2: the retry itself fails with something that is NOT a 409, so the
          // latch is consumed by this save and never reaches a duplicate.
          ServerFailure(statusCode: 500),
          // 3: a fresh, deliberate save that duplicates. It is NOT a retry, so
          // it must read as a plain duplicate.
          ServiceDuplicateFailure(),
        ], (c) => seen = c);

        await pumpOneIncludedRow(tester);
        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));

        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();
        expect(seen, 1);

        // Arm the latch, and let the retry fail with the 500.
        await tester.tap(find.text(l10n.serviceSetupRetry));
        await tester.pumpAndSettle();
        expect(seen, 2);
        expect(
          find.text(l10n.serviceSetupRetry),
          findsNothing,
          reason:
              'precondition: a 500 is not the 503 branch, so no retry action — '
              'the next save must be a deliberate CTA tap, not a retry',
        );

        // The floating 500 snack sits OVER the CTA, so the next tap would be
        // swallowed by the overlay. `ScaffoldMessenger.clearSnackBars()` is a
        // no-op against VelvetSnack (wrong host entirely — see
        // `test/helpers/velvet_snack_matchers.dart`'s file header); draining
        // its full lifecycle via `pumpPastVelvetSnack` is what actually
        // removes it (and, unlike a raw fixed wait, drives the SAME virtual
        // clock `pumpAndSettle` already uses rather than sleeping real time).
        await pumpPastVelvetSnack(tester);

        // A fresh save, from the CTA, that duplicates.
        await tester.tap(find.byKey(const Key('btn-setup-save')));
        await tester.pumpAndSettle();
        expect(seen, 3);

        expect(
          find.text(l10n.serviceErrDuplicate),
          findsOneWidget,
          reason:
              'this duplicate followed an ordinary save, so the honest copy is '
              'the plain one — nothing about it is ambiguous',
        );
        expect(
          find.text(l10n.serviceSetupErrDuplicateAfterRetry),
          findsNothing,
          reason:
              'a latch left armed by the intervening 500 would mislabel this '
              'as "may already have saved", telling the master to go hunting '
              'for a service that was never written',
        );
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  // ── Refetch row identity + deferred disposal (C, second half) ──────────────
  //
  // `_loadCategory` doubles as a REFETCH: surviving service-types keep their
  // EXISTING `ServiceRowState` (same object, so controllers/include flag/pricing
  // mode carry over) and only vanished types are dropped — disposed after the
  // frame that unmounts their card, never during it.
  //
  // The refetch test above pins that the refresh HAPPENS. Neither half of what
  // makes it safe was pinned: that a surviving row keeps what the master typed,
  // and that a vanished row's controllers are not torn down while its card is
  // still reading them.

  group('suggestion refetch — surviving rows carry over, vanished rows are '
      'disposed after the frame', () {
    /// Opens the type-suggestion dialog for `slug` and submits `name`.
    Future<void> suggestType(
      WidgetTester tester,
      String slug,
      String name,
    ) async {
      await tester.ensureVisible(
        find.byKey(ValueKey<String>('suggest_type_$slug')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(ValueKey<String>('suggest_type_$slug')),
              matching: find.byType(GestureDetector),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('field-service-type-suggest-name')),
          matching: find.byType(TextField),
        ),
        name,
      );
      await tester.tap(
        find.byKey(const Key('btn-submit-suggest-service-type')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a row that SURVIVES the refetch keeps its include state and every value '
      'the master typed',
      (tester) async {
        when(
          () => h.repo.suggestServiceType(
            categoryName: any(named: 'categoryName'),
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async {});

        var typeFetches = 0;

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: <Object>[
            serviceRepositoryProvider.overrideWithValue(h.repo),
            servicesListProvider.overrideWith(
              () => _SeededServicesList(const <MasterService>[]),
            ),
            approvedCategoriesProvider.overrideWith(
              (ref) => const <ServiceCategoryOption>[_manicure],
            ),
            // Build 1: classic only. Build 2 (the refetch): classic SURVIVES
            // and gel joins it — so classic is the carried-over row.
            serviceTypesProvider('MANICURE').overrideWith((ref) {
              typeFetches++;
              return typeFetches == 1
                  ? const <ServiceTypeOption>[_typeClassic]
                  : const <ServiceTypeOption>[_typeClassic, _typeGel];
            }),
          ],
        );
        await _expand(tester, 'MANICURE');

        await _toggleRowOn(tester, 'type-classic');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '75',
          price: '650',
        );

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(
          find.text(l10n.serviceSetupCtaCreate(1)),
          findsOneWidget,
          reason: 'precondition: classic is included before the refetch',
        );

        await suggestType(tester, 'MANICURE', 'Lamination');
        await pumpPastVelvetSnack(tester);

        // The refetch ran and brought the new type in.
        expect(typeFetches, greaterThanOrEqualTo(2));
        expect(find.byKey(const Key('setup_row_type-gel')), findsOneWidget);

        // …and classic came through it untouched.
        expect(
          find.text(l10n.serviceSetupCtaCreate(1)),
          findsOneWidget,
          reason:
              'the carried-over row must still be INCLUDED — rebuilding it as a '
              'fresh ServiceRowState resets `included` to false and silently '
              'empties the batch the master had assembled',
        );
        expect(
          _durationText(tester, 'type-classic'),
          '75',
          reason:
              'identity reuse is what preserves the controllers — a rebuilt row '
              'comes back with empty fields and the master retypes everything '
              'they had already entered',
        );
        expect(_fixedPriceText(tester, 'type-classic'), '650');
      },
    );

    testWidgets(
      'a row that VANISHES from the refetched catalogue is dropped without a '
      'use-after-dispose on its still-mounted card',
      (tester) async {
        when(
          () => h.repo.suggestServiceType(
            categoryName: any(named: 'categoryName'),
            name: any(named: 'name'),
            description: any(named: 'description'),
          ),
        ).thenAnswer((_) async {});

        var typeFetches = 0;

        await _pump(
          tester,
          h,
          surfaceSize: const Size(800, 2200),
          overrides: <Object>[
            serviceRepositoryProvider.overrideWithValue(h.repo),
            servicesListProvider.overrideWith(
              () => _SeededServicesList(const <MasterService>[]),
            ),
            approvedCategoriesProvider.overrideWith(
              (ref) => const <ServiceCategoryOption>[_manicure],
            ),
            // Build 2 DROPS gel — the type was retired platform-side between
            // the first expand and the refetch. Its row is orphaned while its
            // card is still mounted and still listening to its controllers.
            serviceTypesProvider('MANICURE').overrideWith((ref) {
              typeFetches++;
              return typeFetches == 1
                  ? const <ServiceTypeOption>[_typeClassic, _typeGel]
                  : const <ServiceTypeOption>[_typeClassic];
            }),
          ],
        );
        await _expand(tester, 'MANICURE');

        // Gel is ON and expanded, so its card holds live listeners on all four
        // of the row's controllers — the state that makes an eager dispose
        // observable rather than theoretical.
        await _toggleRowOn(tester, 'type-gel');
        await _fillRowFixed(tester, 'type-gel', duration: '90', price: '700');
        expect(find.byKey(const Key('setup_row_type-gel')), findsOneWidget);

        await suggestType(tester, 'MANICURE', 'Lamination');
        // Drain the success snack BEFORE the next tap below (_toggleRowOn) —
        // it is bottom-anchored and would otherwise sit over the row's
        // include switch, hit-testing into the overlay and silently missing.
        await pumpPastVelvetSnack(tester);

        expect(typeFetches, greaterThanOrEqualTo(2));
        expect(
          find.byKey(const Key('setup_row_type-gel')),
          findsNothing,
          reason:
              'precondition: the refetched catalogue no longer offers gel, so '
              'its row really was orphaned — without this the no-exception '
              'assertion below proves nothing',
        );
        expect(
          find.byKey(const Key('setup_row_type-classic')),
          findsOneWidget,
          reason: 'the surviving type is unaffected',
        );
        // SCOPE, measured rather than assumed (mutation-probed 2026-08-04):
        // this assertion catches disposing the orphans BEFORE the rebuilding
        // `setState` — that goes red with "A TextEditingController was used
        // after being disposed". It does NOT distinguish `addPostFrameCallback`
        // from a plain synchronous dispose placed immediately AFTER that
        // setState; by then the card is already scheduled out of the tree and
        // nothing reads the controllers again. So this pins the invariant
        // ("a vanished row never leaves a use-after-dispose behind"), not the
        // post-frame scheduling as such. Stated here so a later reader does not
        // mistake it for a guard on the callback itself.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'disposing an orphan while its card can still read its '
              'controllers is a use-after-dispose — the ordering in '
              '_disposeAfterFrame exists to keep exactly one owner',
        );

        // The screen must still be usable afterwards — a half-disposed row can
        // leave the tree throwing on the next interaction rather than this one.
        await _toggleRowOn(tester, 'type-classic');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ── Lazy row cards survive scroll recycling (G) ────────────────────────────
  //
  // Row cards are now built on demand from the `SliverList` delegate rather than
  // eagerly in `_expandedSlots`. That makes an off-screen row's card genuinely
  // UNMOUNT, which is precisely the condition under which per-row state kept in
  // the widget tree — rather than in the `ServiceRowState` the screen owns —
  // would be silently lost.
  //
  // Goldens cannot catch this: they render one frame and never scroll. The
  // regression shape is "master fills a row near the top, scrolls to the bottom
  // of a long category, comes back, and their values are gone".

  group('lazy row cards — state survives a scroll out of and back into view', () {
    testWidgets(
      'a filled row scrolled out of the viewport and back keeps its include '
      'state and typed values',
      (tester) async {
        // Enough rows that the sliver's cache extent cannot keep the first one
        // alive off-screen — with only two or three rows it would stay mounted
        // and the test would pass without ever exercising a recycle.
        final manyTypes = <ServiceTypeOption>[
          _typeClassic,
          for (var i = 0; i < 16; i++)
            ServiceTypeOption(
              id: 'type-filler-$i',
              slug: 'FILLER$i',
              nameUk: 'Filler type $i',
              categoryName: 'MANICURE',
            ),
        ];

        await _pump(
          tester,
          h,
          // Deliberately SHORT — a tall surface renders every row at once and
          // there is nothing to recycle.
          surfaceSize: const Size(420, 700),
          overrides: h.overrides(
            categories: const AsyncData(<ServiceCategoryOption>[_manicure]),
            typesBySlug: <String, List<ServiceTypeOption>>{
              'MANICURE': manyTypes,
            },
            existingServices: const <MasterService>[],
          ),
        );
        await _expand(tester, 'MANICURE');

        await _toggleRowOn(tester, 'type-classic');
        await _fillRowFixed(
          tester,
          'type-classic',
          duration: '45',
          price: '350',
        );

        final l10n = await AppLocalizations.delegate.load(const Locale('uk'));
        expect(find.text(l10n.serviceSetupCtaCreate(1)), findsOneWidget);

        final Finder scroller = find.byType(Scrollable).first;

        // Scroll far past the row, in steps — one huge drag can be clamped by
        // the scroll physics into a shorter effective distance.
        for (var i = 0; i < 4; i++) {
          await tester.drag(scroller, const Offset(0, -600));
          await tester.pumpAndSettle();
        }

        expect(
          find.byKey(const Key('setup_row_type-classic')),
          findsNothing,
          reason:
              'precondition: the lazy SliverList really did unmount the card. '
              'If this row is still in the tree the test is not exercising '
              'recycling at all and the assertions below are vacuous',
        );

        // Back to the top.
        for (var i = 0; i < 6; i++) {
          await tester.drag(scroller, const Offset(0, 600));
          await tester.pumpAndSettle();
        }

        expect(
          find.byKey(const Key('setup_row_type-classic')),
          findsOneWidget,
          reason: 'the card is rebuilt on the way back into view',
        );
        expect(
          find.text(l10n.serviceSetupCtaCreate(1)),
          findsOneWidget,
          reason:
              'the include flag lives on the ServiceRowState the screen owns, '
              'not in the card — a recycle that resets it silently empties the '
              'batch',
        );
        expect(
          _durationText(tester, 'type-classic'),
          '45',
          reason:
              'the controllers are owned by ServiceRowState and outlive the '
              'card — a rebuilt card that re-creates them loses what the master '
              'typed the moment they scroll',
        );
        expect(_fixedPriceText(tester, 'type-classic'), '350');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
