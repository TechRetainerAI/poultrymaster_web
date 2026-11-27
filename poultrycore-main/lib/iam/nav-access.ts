// Menus under per-company page access.
//
// Every nav builder (poultry, water, generic, hotel, restaurant, livestock)
// is wrapped with these two helpers:
//
//   legacyGate      — once page access is live, the old per-family flag rules
//                     (financial-nav-access, water/hotel/restaurant-nav-access,
//                     the admin-only Setup list) must not hide anything on
//                     their own, or a page the owner ticked could still be
//                     missing. They are fed "everything allowed" and stand aside.
//   applyPageAccess — then each row is kept only if canOpen(href) says so (the
//                     same rule the page guard uses), and a section left with
//                     no rows disappears (test 21: menu == effective access).
//
// Before page access is live both are no-ops, so menus behave as they always did.

import type { UserPermissions, FeatureAccessPermissions } from "@/hooks/use-permissions"

const ALL_OPEN = new Proxy({} as FeatureAccessPermissions, { get: () => true })

export function legacyGate<P extends UserPermissions | undefined>(permissions: P): P {
  if (!permissions?.pageAccess) return permissions
  return { ...permissions, featureAccess: ALL_OPEN, isAdmin: true } as P
}

type Row = { href?: string }
type Group = { items: unknown[] }

const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  !!v && typeof v === "object" && Object.getPrototypeOf(v) === Object.prototype && !("$$typeof" in (v as object))

const isGroup = (v: unknown): v is Group => isPlainObject(v) && Array.isArray(v.items)

/**
 * A copy of a nav config with rows the person may not open removed, and
 * groups (anything with an `items` array) emptied by that removed too. Action
 * rows (no href) are kept; icons and other components are left untouched.
 */
export function applyPageAccess<T>(config: T, permissions: UserPermissions | undefined): T {
  if (!permissions?.pageAccess) return config
  const canOpen = permissions.canOpen

  const walk = (node: unknown): unknown => {
    if (Array.isArray(node)) {
      const out: unknown[] = []
      for (const el of node) {
        const w = walk(el)
        if (isGroup(el) && el.items.length > 0 && isGroup(w) && w.items.length === 0) continue
        out.push(w)
      }
      return out
    }
    if (!isPlainObject(node)) return node
    const out: Record<string, unknown> = {}
    for (const [k, v] of Object.entries(node)) {
      if (k === "items" && Array.isArray(v)) {
        out[k] = v
          .filter((row) => !isPlainObject(row) || typeof (row as Row).href !== "string" || canOpen((row as Row).href!))
          .map(walk)
      } else {
        out[k] = walk(v)
      }
    }
    return out
  }
  return walk(config) as T
}
