// Phase 21.14 — Owner own-profile loader.
//
// Resolves everything `OwnerOwnProfileScreen` renders in ONE AsyncValue:
//
//   • the owner's identity + contacts, from the already-shipped
//     `GET /users/me` read (see REUSE below);
//   • OPTIONALLY, the owner-as-master section (stats / bio / categories),
//     which exists only when the signed-in `SALON_OWNER` also has an active
//     `masterType = SALON_OWNER` master row.
//
// ── REUSE ─────────────────────────────────────────────────────────────────
// Nothing here fetches anything new. The three reads are the SHIPPED ones:
//
//   1. `clientEditProfileProvider` — the keepAlive `GET /users/me` → [User]
//      read. Its name says CLIENT (it was introduced for the client edit
//      screens) but its `build()` requires only an `Authenticated` session and
//      the endpoint is `isAuthenticated()`-gated backend-side, so it is
//      role-agnostic in fact. Reused verbatim rather than forked into a second
//      provider hitting the same endpoint — a fork would double the round trip
//      AND let the two drift. (Renaming it is a cross-feature rename of ~10
//      call sites; out of scope for this phase, flagged instead of done.)
//   2. `masterProfileProvider` — the keepAlive `GET /masters/me` read. Backend
//      commit `c4d69ac` widened that endpoint's `@PreAuthorize` to include
//      `SALON_OWNER` (`MasterController:110`), which is what makes it callable
//      from here at all.
//   3. `publicServiceRepositoryProvider.getMasterServices(masterId)` — the
//      PUBLIC `GET /masters/{masterId}/services`. The same call
//      `salon_staff_member_notifier.dart` and `public_master_profile_notifier
//      .dart` already make.
//
// ── WHY NOT `servicesListProvider` ────────────────────────────────────────
// The obvious-looking reuse (mirror `master_profile_screen.dart`, which reads
// its categories from `servicesListProvider`) is WRONG here and would ship a
// permanently-failing section. `servicesListProvider` →
// `ServiceRepository.listMyServices()` → `GET /independent-masters/me/services`,
// which is `@PreAuthorize("hasRole('INDEPENDENT_MASTER')")`
// (`ServiceController:229-230`) — a `SALON_OWNER` gets 403, always. The
// master-row-keyed public endpoint is the only one an owner may call, and
// `masterProfileProvider` is what supplies that master-row id (`Master.id`,
// which is NOT the User UUID).
//
// ── THE `hasMasterProfile` GATE ───────────────────────────────────────────
// [User.hasMasterProfile] is `bool?` and its three states are NOT two:
//
//   • `false` — proven negative. The section renders ABSENT without consulting
//     `/masters/me` at all. (Since the 2026-08-31 perf fix the PROBE itself is
//     still issued — it is started in parallel with `/users/me`, before this
//     value is known — and simply discarded. See the body's own note for why
//     that trade is the right one.)
//   • `true`  — proven positive. Load the section.
//   • `null`  — UNKNOWN (older backend, or a `User` rehydrated from a cache
//     written before the field existed). Since the backend auto-creates the
//     master row on first-salon registration, the default for an existing
//     owner is ON, so treating null as `false` would blank the section for the
//     COMMON case. Null therefore falls through to the same probe as `true`
//     and lets `GET /masters/me` answer the question.
//
// ── 404 IS "ABSENT", NOT "BROKEN" ─────────────────────────────────────────
// `GET /masters/me` answers 404 (not 403) for an owner with no active master
// row. That can be raced: `hasMasterProfile` was true when `/users/me`
// answered and the row was deactivated before `/masters/me` was reached. The
// master section is OPTIONAL, so a failure to load it degrades to ABSENT
// rather than erroring the whole tab — erroring an entire profile because an
// optional section raced is a strictly worse failure than omitting it. Only
// the `/users/me` read (identity + contacts, the screen's reason to exist) can
// put this provider into `AsyncError`.

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/home/application/client_edit_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

part 'owner_own_profile_notifier.g.dart';

/// The owner-as-master section's data: the owner's own master row paired with
/// the services that row performs. `null` on [OwnerOwnProfileData.master] means
/// the section is ABSENT — the owner does not work as a master, or their master
/// row could not be resolved (see the file header's 404 note).
typedef OwnerMasterSection = (Master master, List<MasterService> services);

/// Everything `OwnerOwnProfileScreen` renders.
typedef OwnerOwnProfileData = ({User owner, OwnerMasterSection? master});

/// Loads the signed-in `SALON_OWNER`'s own profile, plus the optional
/// owner-as-master section.
///
/// Generated provider name: `ownerOwnProfileProvider`.
@riverpod
Future<OwnerOwnProfileData> ownerOwnProfile(Ref ref) async {
  // ── EVERY ref.watch HAPPENS BEFORE THE FIRST await ──────────────────────
  // `ref.watch` after a suspension point is not safe in an async provider
  // body (the provider may have been rebuilt or disposed in the meantime) —
  // the same rule `home_hub_notifier.dart`'s `clientProfile` spells out. Both
  // subscriptions are therefore established here, synchronously, and only
  // their FUTURES are awaited below.
  //
  // This also stops serializing two INDEPENDENT endpoints (mobile-perf
  // MEDIUM, 2026-08-31): `/users/me` and `/masters/me` share no dependency,
  // yet the gate below only carries information in ONE of its three states —
  // `true` and `null` both fetch `/masters/me` regardless — so awaiting the
  // first before starting the second bought a wasted round trip in the two
  // COMMON states. The accepted cost of the swap is the mirror image: in the
  // proven-negative `false` state `/masters/me` is now fetched speculatively
  // and discarded. That is one request, not a storm — `beauticaProviderRetry`
  // does not retry a `NotFoundFailure` — and `false` is the rare state (the
  // backend auto-creates the owner's master row on first-salon registration).
  final Future<User> ownerFuture = ref.watch(clientEditProfileProvider.future);

  // Errors are folded to `null` HERE, at creation, for two reasons: it is the
  // same "a failed optional section is ABSENT, not broken" rule the old
  // `on Failure` catch expressed (see 404 IS "ABSENT" above), and it attaches
  // the error handler synchronously so the `hasMasterProfile == false` arm
  // below can return WITHOUT awaiting this future — an unawaited rejected
  // Future is an unhandled zone error.
  final Future<Master?> masterFuture = ref
      .watch(masterProfileProvider.future)
      .then<Master?>(
        (Master master) => master,
        onError: (Object _, StackTrace _) => null,
      );

  // The identity read. A failure here DOES error the screen — without a name
  // and contacts there is no profile to render.
  final User owner = await ownerFuture;

  // Proven negative — render the section as ABSENT without consulting the
  // speculative probe at all.
  if (owner.hasMasterProfile == false) {
    return (owner: owner, master: null);
  }

  // WARM-START, not a read (mobile-perf LOW, 2026-08-31). The category cards
  // resolve their human labels from `approvedCategoriesProvider`, which
  // `ServiceCategoryCardList` first touches from its own `build()` — i.e. a
  // 4th hop that only STARTS after the loaded body's first paint, so the
  // labels visibly swap from `humanizeCategorySlug` to the real names and the
  // section relayouts under the user. Kicking it off here overlaps it with
  // the reads above instead.
  //
  // BELOW the `hasMasterProfile == false` early return (mobile-perf LOW,
  // 2026-09-01): in that arm there is no service-categories section to label,
  // so warming the categories bought a third request no card would ever
  // consume. Started here it still lands at least one round trip ahead of
  // `ServiceCategoryCardList.build()` — the `await masterFuture` below, plus
  // the `GET /masters/{id}/services` after it, both still have to resolve
  // before the section can paint — so the `true`/`null` states keep the full
  // benefit and the `false` state drops from 3 requests to 2.
  //
  // `ref.read`, not `ref.watch`: this provider is `keepAlive`, so a read is
  // enough to start AND retain the fetch, and no dependency edge is created —
  // its later resolution must rebuild the CARDS (which watch it themselves),
  // never this loader. `.ignore()` because the value is consumed there, not
  // here, and a failure must degrade to slug labels rather than error the tab.
  ref.read(approvedCategoriesProvider.future).ignore();

  final Master? master = await masterFuture;
  if (master == null) return (owner: owner, master: null);

  try {
    // A REAL dependency, not a serialization to remove: the public catalogue
    // endpoint is keyed on `Master.id`, which only `/masters/me` supplies.
    final List<MasterService> services = await ref
        .read(publicServiceRepositoryProvider)
        .getMasterServices(master.id);
    return (owner: owner, master: (master, services));
  } on Failure {
    // Every repository in this app throws a typed [Failure] and never lets a
    // raw DioException escape, so this catch covers the catalogue read's 403
    // (a role change mid-session) and its transport failures. Both mean the
    // same thing to this screen: render the section as ABSENT. The
    // `/masters/me` half of that contract is handled by the `onError` fold
    // above, which cannot live inside a `try` that starts after the await.
    return (owner: owner, master: null);
  }
}
