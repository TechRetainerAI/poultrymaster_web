// How the pre-upgrade Staff Page Access flags decided a page — used by the
// one-off migration of existing staff (migration 507 has the SQL twin) and by
// the test that proves the catalog reproduces today's access.
import type { LegacyFlag, LegacyRule } from "@/lib/iam/page-catalog"

/** Did a plain (non-admin) staff member with these flags see the page? */
export function evaluateLegacy(rule: LegacyRule, flags: ReadonlySet<LegacyFlag>, heldKey = false): boolean {
  if (rule === "always") return true
  if (rule === "admin") return false
  if (rule === "iam") return heldKey
  return rule.some((f) => flags.has(f))
}
