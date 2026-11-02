"use client"

/**
 * Everything the header search can find for the active company: its pages
 * (from the gated nav configs) and its named records (customers, suppliers,
 * flocks, products...).
 *
 * HOOK ORDER: every hook below runs for every company type. The farm type only
 * picks which plain function builds the page list -- see the TopNavigation
 * comment about the Water crash for why a hook behind a farm-type branch is not
 * an option.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { useQuery } from "@tanstack/react-query"
import { Home } from "lucide-react"
import { usePermissions } from "@/hooks/use-permissions"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { useAuthStore } from "@/lib/store/auth-store"
import { useQuickLinkHrefs } from "@/lib/store/quick-links-store"
import { buildPoultryNavConfig } from "@/lib/nav/poultry-nav-config"
import { buildWaterNavConfig } from "@/lib/nav/water-nav-config"
import { buildHotelNavConfig } from "@/lib/nav/hotel-nav-config"
import { buildRestaurantNavConfig } from "@/lib/nav/restaurant-nav-config"
import { buildGenericNavGroups } from "@/lib/nav/generic-nav-config"
import {
  HOTEL_REPORT_NAV_GROUPS, POULTRY_REPORT_NAV_GROUPS, RESTAURANT_REPORT_NAV_GROUPS, WATER_REPORT_NAV_GROUPS,
} from "@/lib/nav/report-nav-adapters"
import type { MegaMenuGroup } from "@/lib/nav/nav-model"
import { filterWaterNavItems } from "@/lib/utils/water-nav-access"
import { filterHotelNavItems } from "@/lib/utils/hotel-nav-access"
import { filterRestaurantNavItems } from "@/lib/utils/restaurant-nav-access"
import { flattenNavConfig, type SearchPage } from "@/lib/search/page-index"
import type { SearchRecord } from "@/lib/search/records"
import { getUserContext } from "@/lib/api/config"
import { getCustomers as getPoultryCustomers } from "@/lib/api/customer"
import { getSuppliers as getPoultrySuppliers } from "@/lib/api/supplier"
import { getFlocks } from "@/lib/api/flock"
import { getHouses } from "@/lib/api/house"
import { listWaterCustomers, listWaterDrivers } from "@/lib/api/water"
import {
  getCustomers as getGenericCustomers, getProducts as getGenericProducts, getSuppliers as getGenericSuppliers,
} from "@/lib/api/generic"

const noop = () => {}

/** Run a report menu through the same href gate its company's rail uses. */
function gateReports(groups: MegaMenuGroup[], gate: <T extends { href: string }>(items: T[]) => T[]): MegaMenuGroup[] {
  return groups.map((g) => ({
    ...g,
    label: `Reports · ${g.label}`,
    items: gate(g.items.filter((i): i is typeof i & { href: string } => !!i.href)),
  }))
}

function homePage(type: string | null): SearchPage {
  const href =
    type === "Water" ? "/water-dashboard" :
    type === "Generic" ? "/generic-dashboard" :
    type === "Hotel" ? "/hotel-dashboard" :
    type === "Restaurant" ? "/restaurant-dashboard" : "/dashboard"
  return { href, title: "Dashboard", group: "Home", icon: Home, keywords: ["home", "overview", "main", "summary"] }
}

export function useSearchPages(): SearchPage[] {
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const genericModules = useGenericModules()
  const quickLinkHrefs = useQuickLinkHrefs()

  return useMemo(() => {
    const { featureAccess, isAdmin } = permissions
    let pages: SearchPage[]
    if (activeFarmType === "Water") {
      const nav = buildWaterNavConfig({ permissions, onOpenAlerts: noop, quickLinkHrefs })
      const gate = <T extends { href: string }>(items: T[]) => filterWaterNavItems(items, featureAccess, isAdmin)
      pages = flattenNavConfig(nav, [
        { key: "reports", label: "Reports", items: gate([{ id: "all", title: "Reports", href: "/water-reports" }]) } as MegaMenuGroup,
        ...gateReports(WATER_REPORT_NAV_GROUPS, gate),
      ])
    } else if (activeFarmType === "Generic") {
      const g = buildGenericNavGroups(genericModules, isAdmin)
      pages = flattenNavConfig({
        catalog: { label: "Catalog", items: g.catalog },
        subscriptions: { label: "Subscriptions", items: g.subscriptions },
        sales: { label: "Sales", items: g.sales },
        purchasing: { label: "Purchasing", items: g.purchasing },
        money: { label: "Money", items: g.money },
        people: { label: "People", items: g.people },
        admin: { label: "Admin", items: g.admin },
      })
    } else if (activeFarmType === "Hotel") {
      const gate = <T extends { href: string }>(items: T[]) => filterHotelNavItems(items, featureAccess, isAdmin)
      pages = flattenNavConfig(buildHotelNavConfig({ permissions }), gateReports(HOTEL_REPORT_NAV_GROUPS, gate))
    } else if (activeFarmType === "Restaurant") {
      const gate = <T extends { href: string }>(items: T[]) => filterRestaurantNavItems(items, featureAccess, isAdmin)
      pages = flattenNavConfig(buildRestaurantNavConfig({}, permissions), gateReports(RESTAURANT_REPORT_NAV_GROUPS, gate))
    } else {
      // Poultry, and the first paint before the persisted farm type rehydrates.
      const nav = buildPoultryNavConfig({ permissions, onOpenAlerts: noop, quickLinkHrefs })
      pages = flattenNavConfig(
        nav,
        featureAccess.canViewReports
          ? [
              { key: "reports", label: "Reports", items: [{ id: "all", title: "Reports", href: "/reports" }] } as MegaMenuGroup,
              ...gateReports(POULTRY_REPORT_NAV_GROUPS, (items) => items),
            ]
          : [],
      )
    }
    const home = homePage(activeFarmType)
    return [home, ...pages.filter((p) => p.href !== home.href)]
  }, [permissions, activeFarmType, genericModules, quickLinkHrefs])
}

/** `/mock/` in the message = the API failed and the wrapper made data up. */
function real<T>(res: { success: boolean; data?: T; message?: string }): T | [] {
  if (!res.success || /mock/i.test(res.message ?? "")) return []
  return res.data ?? []
}

const settle = <T,>(p: Promise<T[]>): Promise<T[]> => p.then((v) => (Array.isArray(v) ? v : [])).catch(() => [])

async function loadRecords(type: string | null, canOpen: (href: string) => boolean): Promise<SearchRecord[]> {
  const { userId, farmId } = getUserContext()
  const out: SearchRecord[] = []

  if (type === "Water") {
    const [customers, drivers] = await Promise.all([
      canOpen("/water-customers") ? settle(listWaterCustomers()) : [],
      canOpen("/water-drivers") ? settle(listWaterDrivers()) : [],
    ])
    for (const c of customers) out.push({
      kind: "customer", id: String(c.waterCustomerId), title: c.name,
      subtitle: [c.contactPhone, c.city].filter(Boolean).join(" · ") || undefined,
      extra: [c.contactEmail ?? "", c.address ?? ""], phones: [c.contactPhone],
      href: "/water-customers", prefill: c.name,
    })
    for (const d of drivers) out.push({
      kind: "driver", id: String(d.waterDriverId), title: d.driverName,
      subtitle: d.phoneNumber ?? undefined, phones: [d.phoneNumber],
      href: "/water-drivers", inactive: (d as { isActive?: boolean }).isActive === false,
    })
    return out
  }

  if (type === "Generic") {
    const [customers, suppliers, products] = await Promise.all([
      canOpen("/generic-customers") ? settle(getGenericCustomers()) : [],
      canOpen("/generic-suppliers") ? settle(getGenericSuppliers()) : [],
      canOpen("/generic-products") ? settle(getGenericProducts()) : [],
    ])
    for (const c of customers) out.push({
      kind: "customer", id: String(c.genericCustomerId), title: c.customerName,
      subtitle: [c.phoneNumber, c.location].filter(Boolean).join(" · ") || undefined,
      extra: [c.email ?? ""], phones: [c.phoneNumber],
      href: `/generic-customers/${c.genericCustomerId}/ledger`, inactive: c.isActive === false,
    })
    for (const s of suppliers) out.push({
      kind: "supplier", id: String(s.genericSupplierId), title: s.supplierName,
      subtitle: [s.phoneNumber, s.location].filter(Boolean).join(" · ") || undefined,
      extra: [s.email ?? ""], phones: [s.phoneNumber],
      href: `/generic-suppliers/${s.genericSupplierId}/ledger`, inactive: s.isActive === false,
    })
    for (const p of products) out.push({
      kind: "product", id: String(p.genericProductId), title: p.productName,
      subtitle: [p.categoryName, p.sku].filter(Boolean).join(" · ") || undefined,
      extra: [p.sku ?? "", p.barcode ?? ""],
      href: "/generic-products", prefill: p.productName, inactive: p.isActive === false,
    })
    return out
  }

  if (type === "Hotel" || type === "Restaurant") return out
  if (!userId || !farmId) return out

  const [customers, suppliers, flocks, houses] = await Promise.all([
    canOpen("/customers") ? getPoultryCustomers(userId, farmId).then(real).catch(() => []) : [],
    canOpen("/suppliers") ? getPoultrySuppliers(userId, farmId).then(real).catch(() => []) : [],
    canOpen("/flocks") ? getFlocks(userId, farmId).then(real).catch(() => []) : [],
    canOpen("/houses") ? getHouses(userId, farmId).then(real).catch(() => []) : [],
  ])
  for (const c of customers) out.push({
    kind: "customer", id: String(c.customerId), title: c.name,
    subtitle: [c.contactPhone, c.city].filter(Boolean).join(" · ") || undefined,
    extra: [c.contactEmail ?? "", c.address ?? ""], phones: [c.contactPhone],
    href: `/customers/${c.customerId}`,
  })
  for (const s of suppliers) out.push({
    kind: "supplier", id: String(s.supplierId), title: s.name,
    subtitle: [s.contactPhone, s.city].filter(Boolean).join(" · ") || undefined,
    extra: [s.contactEmail ?? "", s.address ?? ""], phones: [s.contactPhone],
    href: "/suppliers", prefill: s.name,
  })
  for (const f of flocks) out.push({
    kind: "flock", id: String(f.flockId), title: f.name,
    subtitle: [f.breed, f.active ? `${f.quantity?.toLocaleString?.() ?? f.quantity} birds` : "Closed"].filter(Boolean).join(" · "),
    href: `/flocks/${f.flockId}`, inactive: !f.active,
  })
  for (const h of houses) out.push({
    kind: "house", id: String(h.houseId), title: h.name,
    subtitle: [h.location, h.capacity ? `capacity ${h.capacity.toLocaleString()}` : ""].filter(Boolean).join(" · ") || undefined,
    href: "/houses",
  })
  return out
}

/**
 * The active company's records. Fetched only once the search has been opened
 * (`enabled`), then cached for a few minutes -- the search must not cost every
 * page load four list requests.
 */
export function useSearchRecords(enabled: boolean, pages: SearchPage[]) {
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const openable = useMemo(() => new Set(pages.map((p) => p.href.split("?")[0])), [pages])
  const sourceKey = useMemo(() => [...openable].filter((h) => /customers|suppliers|flocks|houses|products|drivers/.test(h)).sort().join(","), [openable])

  return useQuery({
    queryKey: ["global-search-records", activeFarmId, activeFarmType, sourceKey],
    queryFn: () => loadRecords(activeFarmType, (href) => openable.has(href)),
    enabled: enabled && !!activeFarmId,
    staleTime: 5 * 60 * 1000,
    gcTime: 15 * 60 * 1000,
    retry: false,
  })
}

// ---------------------------------------------------------------- recents

export interface RecentEntry {
  href: string
  title: string
  /** Page group, or the record kind label. */
  meta: string
  prefill?: string
}

const recentKey = (farmId: string | null) => `globalSearch:recent:${farmId ?? "none"}`

/** What this user opened from the search, per company, newest first. */
export function useSearchRecents() {
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const [recents, setRecents] = useState<RecentEntry[]>([])

  useEffect(() => {
    try {
      const raw = localStorage.getItem(recentKey(activeFarmId))
      setRecents(raw ? (JSON.parse(raw) as RecentEntry[]).slice(0, 6) : [])
    } catch {
      setRecents([])
    }
  }, [activeFarmId])

  const remember = useCallback((entry: RecentEntry) => {
    setRecents((prev) => {
      const next = [entry, ...prev.filter((r) => !(r.href === entry.href && r.prefill === entry.prefill))].slice(0, 6)
      try { localStorage.setItem(recentKey(activeFarmId), JSON.stringify(next)) } catch {}
      return next
    })
  }, [activeFarmId])

  const clear = useCallback(() => {
    setRecents([])
    try { localStorage.removeItem(recentKey(activeFarmId)) } catch {}
  }, [activeFarmId])

  return { recents, remember, clear }
}
