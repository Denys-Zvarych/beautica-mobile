// Phase 464 / audit INFO — the client mirror of the backend service-name
// allow-list (`ServiceNameConstraints.NAME_REGEX`). Shared by the setup
// screen's in-place copy-name field and the create/edit service form, so one
// rule guards every service-name input.

import 'package:flutter/services.dart';

/// Input formatters for a service `name` field: letters of any script,
/// combining marks (a decomposed «й» = и + U+0306 keeps its mark; the backend
/// folds it under NFKC), digits, space and `- – — . , ' ’ ʼ ( ) + / & « » " №
/// : % ! ?`. The four Hangul fillers are denied: they are `Lo` letters that
/// render blank, and the backend subtracts them from its letter class.
final List<TextInputFormatter> serviceNameInputFormatters =
    List<TextInputFormatter>.unmodifiable(<TextInputFormatter>[
      FilteringTextInputFormatter.allow(
        RegExp('[\\p{L}\\p{M}0-9 –—.,\'’ʼ()+/&«»"№:%!?-]', unicode: true),
      ),
      FilteringTextInputFormatter.deny(RegExp('[ᅟᅠㅤﾠ]')),
    ]);
