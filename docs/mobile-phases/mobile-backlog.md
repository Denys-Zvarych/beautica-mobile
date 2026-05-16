# Mobile QA Backlog

Low and Info severity findings that do not block merge. Address in next iteration or when the affected file is next touched.

---

## LOW — Stale comment in auth_gradient_background_test.dart

**File:** `test/features/auth/presentation/auth_gradient_background_test.dart` (lines 1–12, file header)

**Finding:** The file header comment still describes the painter as using `canvas.drawCircle() + RadialGradient.createShader()` — the previous implementation. The current painter uses `canvas.drawRect()` only. The test code itself is correct; only the prose comment is stale.

**Fix:** Update the comment to say `canvas.drawRect()` (already partially done in the header rewrite during QA audit 2026-05-17; the body comment on line 8 in the original was the specific stale line).

**Pattern:** M2-adjacent (comment accuracy, not a test gap).

**Added:** 2026-05-17 | **Audit:** auth_gradient_background drawRect redesign

---
