"use client"

// =============================================================================
// usePageActions — may this person add / edit / delete / approve / reverse /
// export on THIS page?
//
// The page guard already decides whether the page opens (view). This answers
// the next question, for the buttons on the page, from the same page catalog
// and with the same rule the API uses (IamEnforcementFilter + ExistingKey):
//
//   * the page's own key for the action when the catalog defines it;
//   * otherwise the next equal-or-stronger action the page does define
//     (IamPermissionMap.FallbackActions — reverse → approve → edit …);
//   * a page that defines none of them is not restricted on that action
//     (the API lets it through too: no catalog key, nothing to refuse).
//
// Owners can do everything. Before per-company page access (506/507) is live,
// or while the grants are still loading for an employer account, everything
// stays allowed so nothing flickers away; staff see nothing until loaded.
//
//   const act = usePageActions()                       // from the URL
//   const act = usePageActions("generic.purchases")    // a specific page
//   {act.approve && <Button>Approve</Button>}
// =============================================================================

import { useMemo } from "react"
import { usePathname } from "next/navigation"
import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { resolvePathAccess } from "@/lib/iam/page-registry"
import { PAGE_CATALOG, type PageAction, type PageDef } from "@/lib/iam/page-catalog"
import type { PermissionKey } from "@/lib/iam/keys"

export type PageActions = Record<Exclude<PageAction, "view">, boolean> & {
  /** The page key these answers are for ("generic.purchases"), or null when the page is not permission-controlled. */
  page: string | null
}

/** Mirror of IamPermissionMap.FallbackActions on the API. Keep them in step. */
const FALLBACK: Record<Exclude<PageAction, "view">, readonly PageAction[]> = {
  create: ["edit"],
  edit: [],
  delete: ["edit"],
  approve: ["edit"],
  reverse: ["approve", "delete", "edit"],
  export: ["view"],
}

const ACTIONS = Object.keys(FALLBACK) as Array<Exclude<PageAction, "view">>

const ALL: Omit<PageActions, "page"> = { create: true, edit: true, delete: true, approve: true, reverse: true, export: true }
const NONE: Omit<PageActions, "page"> = { create: false, edit: false, delete: false, approve: false, reverse: false, export: false }

/** The key a page action is decided by, or null when the page defines none in the chain. */
export function keyForAction(page: Pick<PageDef, "module" | "resource" | "actions">, action: Exclude<PageAction, "view">): string | null {
  const held = new Set<PageAction>(["view", ...(page.actions ?? [])])
  for (const a of [action, ...FALLBACK[action]]) {
    if (held.has(a)) return `${page.module}.${page.resource}.${a}`
  }
  return null
}

export function usePageActions(pageKey?: string): PageActions {
  const pathname = usePathname() ?? "/"
  const companyType = useAuthStore((s) => s.activeFarmType)
  const permissions = usePermissions()

  return useMemo(() => {
    let page: PageDef | null = null
    if (pageKey) {
      page = PAGE_CATALOG.find((p) => `${p.module}.${p.resource}` === pageKey) ?? null
    } else {
      const access = resolvePathAccess(pathname, companyType)
      page = access.kind === "page" ? access.page : null
    }
    const key = page ? `${page.module}.${page.resource}` : null

    if (!permissions.pageAccess) return { ...ALL, page: key }
    if (!permissions.accessLoaded) return { ...(permissions.isStaff ? NONE : ALL), page: key }
    if (permissions.isOwner || !page) return { ...ALL, page: key }

    const out = { ...ALL, page: key }
    for (const action of ACTIONS) {
      const k = keyForAction(page, action)
      out[action] = k === null ? true : permissions.can(k as PermissionKey)
    }
    return out
  }, [pageKey, pathname, companyType, permissions.pageAccess, permissions.accessLoaded, permissions.isStaff, permissions.isOwner, permissions.can])
}
