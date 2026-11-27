// =============================================================================
// URL → page permission.
//
// The page guard, the menus, Quick Links and global search all ask this one
// function whether a path may be opened, so they can never disagree.
// Built from lib/iam/page-catalog.ts; nothing here is hand-maintained.
// =============================================================================

import {
  MEMBER_ROUTES, PAGE_CATALOG, PLATFORM_ROUTES, PUBLIC_ROUTES,
  moduleForCompanyType, viewKey, type PageDef, type PageModule,
} from "@/lib/iam/page-catalog"

export type PathAccess =
  | { kind: "public" }
  | { kind: "member" }
  | { kind: "platform" }
  | { kind: "page"; page: PageDef; key: string }
  | { kind: "unregistered" }

function cleanPath(pathname: string): string {
  let p = pathname.split("?")[0].split("#")[0]
  if (p.length > 1 && p.endsWith("/")) p = p.slice(0, -1)
  return p || "/"
}

const covers = (route: string, path: string) =>
  route === "/" ? path === "/" : path === route || path.startsWith(route + "/")

function longest(routes: readonly string[], path: string): number {
  let best = -1
  for (const r of routes) if (covers(r, path) && r.length > best) best = r.length
  return best
}

/** Index: every (route, page) pair, so lookups are a scan of ~600 short strings. */
const ROUTE_INDEX: ReadonlyArray<{ route: string; page: PageDef }> =
  PAGE_CATALOG.flatMap((page) => page.routes.map((route) => ({ route, page })))

/**
 * Which page does `pathname` belong to, for a company of `companyType`?
 *
 * Longest matching route wins, so `/poultry/reports/profit-loss` resolves to
 * the financial-report category rather than the Reports menu, and detail pages
 * (`/expenses/123`, `/generic-projects/new`) inherit their parent. When a route
 * is listed by several modules (e.g. `/recurring-expenses`, shared by Poultry
 * and Generic) the active company's module wins.
 */
export function resolvePathAccess(pathname: string, companyType?: string | null): PathAccess {
  const path = cleanPath(pathname)
  if (longest(PUBLIC_ROUTES, path) >= 0) return { kind: "public" }
  if (longest(PLATFORM_ROUTES, path) >= 0) return { kind: "platform" }

  const module: PageModule | null = moduleForCompanyType(companyType)
  let best: { len: number; page: PageDef; own: boolean } | null = null
  for (const { route, page } of ROUTE_INDEX) {
    if (!covers(route, path)) continue
    const own = page.module === module || page.module === "office"
    const better =
      !best ||
      route.length > best.len ||
      (route.length === best.len && own && !best.own)
    if (better) best = { len: route.length, page, own }
  }

  // A member route only wins when it is at least as specific as any page.
  const memberLen = MEMBER_ROUTES.filter((r) => r !== "/").reduce((m, r) => (covers(r, path) ? Math.max(m, r.length) : m), -1)
  if (path === "/" || (memberLen >= 0 && (!best || memberLen >= best.len))) return { kind: "member" }

  if (best) return { kind: "page", page: best.page, key: viewKey(best.page) }
  return { kind: "unregistered" }
}

export interface AccessContext {
  companyType?: string | null
  /** Owner (or platform operator): every page, cannot be restricted. */
  isOwner: boolean
  /** Is this permission key in the caller's effective set for the active company? */
  can: (key: string) => boolean
}

/**
 * May this person open `pathname`? The single rule every surface uses.
 *
 * Unregistered paths are denied to everyone but owners: a page nobody gave a
 * permission is not silently open to staff.
 */
export function canOpenPath(pathname: string, ctx: AccessContext): boolean {
  const access = resolvePathAccess(pathname, ctx.companyType)
  switch (access.kind) {
    case "public":
    case "member":
      return true
    case "platform":
    case "unregistered":
      return ctx.isOwner
    case "page":
      if (ctx.isOwner) return true
      if (!ctx.can(access.key)) return false
      return !access.page.dependsOn || ctx.can(`${access.page.dependsOn}.view`)
  }
}

/** The view key for a path, or null when the path is not permission-controlled. */
export function permissionKeyForPath(pathname: string, companyType?: string | null): string | null {
  const access = resolvePathAccess(pathname, companyType)
  return access.kind === "page" ? access.key : null
}
