// The ONE reading of a generated `beautica_api` enum as its wire name.
//
// `scripts/regenerate_api.sh` runs openapi-generator with
// `enumUnknownDefaultCase=true`, so every generated built_value `EnumClass`
// carries a fallback member, `unknownDefaultOpenApi` (wire
// `unknown_default_open_api`), that ANY wire value this build predates decodes
// to — instead of the serializer throwing and failing the whole response (for
// `/users/me`, that throw used to end in a wiped session).
//
// The fallback is a decoding artefact, never data: its `name` must not reach a
// domain model as if it were a real value (e.g. as a settlement type to prefix
// a label with), and it must never be sent back in a request. Request enums
// are always built from explicit members by a domain switch, so only the READ
// side needs this helper.

import 'package:built_value/built_value.dart';

/// `EnumClass.name` of every generated enum's unknown-value fallback member.
const String kOpenApiUnknownEnumName = 'unknownDefaultOpenApi';

/// Whether [value] is the generated unknown-value fallback member.
bool isOpenApiUnknownDefault(EnumClass value) =>
    value.name == kOpenApiUnknownEnumName;

/// The wire name of [value] — `EnumClass.name`, which equals the wire value
/// for every generated `beautica_api` enum — or `null` when [value] is absent
/// or is the unknown-value fallback.
String? knownEnumName(EnumClass? value) =>
    value == null || isOpenApiUnknownDefault(value) ? null : value.name;
