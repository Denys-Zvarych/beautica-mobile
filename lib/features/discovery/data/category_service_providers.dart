// Phase 13.x (Variant A redesign) — second-level service options provider.
//
// Feeds the «Послуги · {category}» chip drawer that opens beneath a selected
// category in the Variant A search rail. Returns the bookable services for a
// given category wire slug (e.g. `HAIR` → Стрижка / Фарбування / …).
//
// ─────────────────────────────────────────────────────────────────────────
// OUTSTANDING BACKEND WIRING — READ ME.
//
// There is NO backend endpoint that returns the services within a category
// yet. `approvedCategoriesProvider` (services feature) returns only the flat
// category list (`ServiceCategoryOption{name, displayName}`) with no nested
// services. So this provider is a PLACEHOLDER: it maps each category slug to a
// hardcoded service list transcribed verbatim from the approved preview's
// `catalog.dart`, so the Variant A drawer renders EXACTLY as designed.
//
// To make this real, `backend-dev` must expose a services-within-category
// endpoint (e.g. `GET /api/v1/service-categories/{slug}/services` or include a
// `services[]` array on the approved-categories response). Then:
//   1. regenerate the OpenAPI client,
//   2. replace [_kPreviewCatalog] with a repository call mapping the DTO into
//      [CategoryServiceOption], and
//   3. make [categoryServiceOptionsProvider] async (FutureProvider) + handle
//      loading/error in the drawer (today it is synchronous mock data, so the
//      drawer needs no async states).
// The UI, selection controller, and chip widget are already shaped for that
// swap — only this file changes.
// ─────────────────────────────────────────────────────────────────────────

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/category_service_option.dart';

part 'category_service_providers.g.dart';

/// Placeholder catalog of services per category wire slug, transcribed verbatim
/// from the approved preview's `catalog.dart`. Keys are matched case-insensitively
/// by substring against the live category slug so the dynamic backend taxonomy
/// (which may split e.g. nails into `MANICURE`/`PEDICURE`) still resolves to a
/// family service list. Unmapped categories return an empty list (the drawer
/// then shows nothing, never crashes).
//
// TODO(backend-dev): delete this map once a services-within-category endpoint
// exists; replace with a real repository call. See file header.
const Map<String, List<CategoryServiceOption>> _kPreviewCatalog =
    <String, List<CategoryServiceOption>>{
  'HAIR': <CategoryServiceOption>[
    CategoryServiceOption(key: 'haircut', displayName: 'Стрижка'),
    CategoryServiceOption(key: 'coloring', displayName: 'Фарбування'),
    CategoryServiceOption(key: 'styling', displayName: 'Укладка'),
    CategoryServiceOption(key: 'keratin', displayName: 'Кератин'),
    CategoryServiceOption(key: 'treatment', displayName: 'Догляд'),
    CategoryServiceOption(key: 'highlights', displayName: 'Мелірування'),
  ],
  'NAIL': <CategoryServiceOption>[
    CategoryServiceOption(key: 'manicure', displayName: 'Манікюр'),
    CategoryServiceOption(key: 'pedicure', displayName: 'Педикюр'),
    CategoryServiceOption(key: 'gel', displayName: 'Гель-лак'),
    CategoryServiceOption(key: 'extension', displayName: 'Нарощування'),
    CategoryServiceOption(key: 'design', displayName: 'Дизайн'),
  ],
  'BROW': <CategoryServiceOption>[
    CategoryServiceOption(key: 'brow_shape', displayName: 'Корекція брів'),
    CategoryServiceOption(key: 'brow_tint', displayName: 'Фарбування брів'),
    CategoryServiceOption(key: 'lamination', displayName: 'Ламінування'),
    CategoryServiceOption(key: 'lash_ext', displayName: 'Нарощування вій'),
  ],
  'LASH': <CategoryServiceOption>[
    CategoryServiceOption(key: 'lash_ext', displayName: 'Нарощування вій'),
    CategoryServiceOption(key: 'lamination', displayName: 'Ламінування'),
  ],
  'MAKE': <CategoryServiceOption>[
    CategoryServiceOption(key: 'day', displayName: 'Денний макіяж'),
    CategoryServiceOption(key: 'evening', displayName: 'Вечірній макіяж'),
    CategoryServiceOption(key: 'bridal', displayName: 'Весільний образ'),
    CategoryServiceOption(key: 'lesson', displayName: 'Урок макіяжу'),
  ],
  'COSMETOLOG': <CategoryServiceOption>[
    CategoryServiceOption(key: 'cleansing', displayName: 'Чистка обличчя'),
    CategoryServiceOption(key: 'peeling', displayName: 'Пілінг'),
    CategoryServiceOption(key: 'mask', displayName: 'Догляд за шкірою'),
    CategoryServiceOption(key: 'massage_face', displayName: 'Масаж обличчя'),
  ],
  'MASSAGE': <CategoryServiceOption>[
    CategoryServiceOption(key: 'classic', displayName: 'Класичний'),
    CategoryServiceOption(key: 'relax', displayName: 'Релакс'),
    CategoryServiceOption(key: 'sport', displayName: 'Спортивний'),
    CategoryServiceOption(key: 'lymph', displayName: 'Лімфодренаж'),
  ],
  'DEPIL': <CategoryServiceOption>[
    CategoryServiceOption(key: 'wax', displayName: 'Воском'),
    CategoryServiceOption(key: 'sugar', displayName: 'Шугаринг'),
    CategoryServiceOption(key: 'laser', displayName: 'Лазерна'),
  ],
  'TAN': <CategoryServiceOption>[
    CategoryServiceOption(key: 'spray', displayName: 'Моментальна'),
    CategoryServiceOption(key: 'solarium', displayName: 'Солярій'),
  ],
  'BODY': <CategoryServiceOption>[
    CategoryServiceOption(key: 'wrap', displayName: 'Обгортання'),
    CategoryServiceOption(key: 'scrub', displayName: 'Скраб'),
  ],
  'TATTOO': <CategoryServiceOption>[
    CategoryServiceOption(key: 'tattoo', displayName: 'Татуювання'),
    CategoryServiceOption(key: 'piercing', displayName: 'Пірсинг'),
  ],
  'PERMANENT': <CategoryServiceOption>[
    CategoryServiceOption(key: 'pm_brows', displayName: 'Брови'),
    CategoryServiceOption(key: 'pm_lips', displayName: 'Губи'),
  ],
  'SPA': <CategoryServiceOption>[
    CategoryServiceOption(key: 'hammam', displayName: 'Хаммам'),
    CategoryServiceOption(key: 'sauna', displayName: 'Сауна'),
  ],
};

/// Returns the bookable services for the given category wire [slug].
///
/// PLACEHOLDER: synchronous mock data (see file header). Resolves the slug by
/// substring match against [_kPreviewCatalog] keys so split taxonomies still
/// land on a family list. Unmapped slugs return an empty list.
@riverpod
List<CategoryServiceOption> categoryServiceOptions(
  Ref ref,
  String slug,
) {
  final String upper = slug.toUpperCase();
  for (final MapEntry<String, List<CategoryServiceOption>> entry
      in _kPreviewCatalog.entries) {
    if (upper.contains(entry.key)) return entry.value;
  }
  return const <CategoryServiceOption>[];
}
