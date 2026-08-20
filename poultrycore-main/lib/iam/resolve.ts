// Effective-permission resolution.
//
// One function decides what a user can do, and one flag decides which era we
// are in. Everything else — the hook, the pages, eventually the API filter —
// asks this.

import type { StaffFeaturePermissionKey } from "@/lib/employees/permissions"
import { legacyToPermissionKeys, type PermissionKey } from "./keys"

/**
 * Fallback for when the server has not told us yet.
 *
 * Which era we are in is NOT a constant in this file — it is `Iam:Enforced` on
 * the Farm API, read via GET /Iam/status. That matters because the API is what
 * actually enforces: if the client decided independently it could start hiding
 * things the server still allows, or offering things it now refuses. One flag,
 * one owner.
 *
 * Additive (false) is the safe default, so a client that cannot reach the status
 * endpoint errs towards showing too much rather than locking someone out of a
 * page they can still legitimately use.
 */
export const IAM_AUTHORITATIVE_DEFAULT = false

export interface ResolveInput {
  /**
   * True once the API enforces permissions (`Iam:Enforced`). While false, IAM is
   * ADDITIVE: effective access is the union of the legacy FeaturePermissions blob
   * and whatever IAM grants, so no deploy can take access away and the two admin
   * screens cannot contradict each other into a lockout. A user-level Deny then
   * only subtracts from IAM's own contribution — it cannot claw back something
   * the legacy flags already allow.
   *
   * When true, IAM is the only source: legacy flags are ignored and denies apply
   * outright. Migration 202 must have run first, or staff lose everything.
   */
  authoritative?: boolean
  /** Legacy per-user flags from AspNetUsers.FeaturePermissions. */
  legacy: Partial<Record<StaffFeaturePermissionKey, boolean>>
  /** True for the account owner / anyone the legacy model treats as admin. */
  isAdmin: boolean
  /** Keys granted by IAM roles and Allow overrides, resolved server-side. */
  iamAllow: readonly PermissionKey[]
  /** Keys explicitly denied at user level, resolved server-side. */
  iamDeny?: readonly PermissionKey[]
}

export interface ResolvedPermissions {
  /** Every key the user holds. Empty and `isSuperuser` true means "all keys". */
  keys: Set<PermissionKey>
  /** Short-circuit: holds everything, including keys added later. */
  isSuperuser: boolean
  can: (key: PermissionKey) => boolean
}

export function resolveEffectivePermissions(input: ResolveInput): ResolvedPermissions {
  const { legacy, isAdmin, iamAllow, iamDeny = [], authoritative = IAM_AUTHORITATIVE_DEFAULT } = input

  // Under the legacy model `isAdmin` already meant "not restricted", so treating
  // it as a superuser is what keeps the additive era behaving exactly as before.
  // Once the API enforces, admins are superusers only if a role says so — which
  // migration 200 arranges by giving account owners the Owner role.
  const isSuperuser = !authoritative && isAdmin

  const denies = new Set(iamDeny)
  const iam = new Set<PermissionKey>()
  for (const key of iamAllow) {
    if (!denies.has(key)) iam.add(key)
  }

  let keys: Set<PermissionKey>
  if (authoritative) {
    keys = iam
  } else {
    // Union. Deny has already been applied to the IAM contribution above and is
    // deliberately not applied to the legacy set.
    keys = new Set<PermissionKey>([...legacyToPermissionKeys(legacy), ...iam])
  }

  return {
    keys,
    isSuperuser,
    can: (key: PermissionKey) => isSuperuser || keys.has(key),
  }
}
