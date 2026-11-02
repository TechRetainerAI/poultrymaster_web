"use client"

// =============================================================================
// CompanyTypeGuard — page-level enforcement that prevents cross-type access.
//
// A Water user typing /hotel-rooms, or a Hotel user typing /water-staff, will
// be shown a friendly "not available" screen instead of the page. This replaces
// the separate WaterAccessGuard and HotelAccessGuard and covers all five types.
//
// Mounted once in app/layout.tsx. Deliberately waits for both the active farm
// type and auth token before acting so SSR and initial hydration don't bounce.
//
// Shared routes (login, register, profile, companies, business-office, etc.)
// are whitelisted — every company type can reach them.
// =============================================================================

import { useEffect, useState } from "react"
import { usePathname } from "next/navigation"
import { useAuthStore } from "@/lib/store/auth-store"
import { type CompanyType } from "@/lib/api/companies"
import { COMPANY_CHANGED_EVENT } from "@/lib/store/auth-store"
import { CompanyTypeMismatch } from "./company-type-mismatch"

// ---------------------------------------------------------------------------
// Route prefix → required company type.
// Anything not listed here is considered shared (accessible to all types).
// ---------------------------------------------------------------------------

const ROUTE_PREFIX_TO_TYPE: Record<string, CompanyType> = {
  // Water
  "/water-": "Water",

  // Hotel
  "/hotel-": "Hotel",

  // Restaurant
  "/restaurant-": "Restaurant",

  // Generic
  "/generic-": "Generic",

  // Poultry-specific routes (the original module, many have no prefix)
  "/flocks": "Poultry",
  "/flock-closeout": "Poultry",
  "/flock-batch": "Poultry",
  "/batch-production-records": "Poultry",
  "/production-records": "Poultry",
  "/egg-production": "Poultry",
  "/egg-sorting": "Poultry",
  "/egg-tracker": "Poultry",
  "/houses": "Poultry",
  "/health": "Poultry",
  "/feed-usage": "Poultry",
  "/feed-tracker": "Poultry",
  "/feed-inventory": "Poultry",
  "/feed-formulas": "Poultry",
  "/feed-production": "Poultry",
  "/feed-distribution": "Poultry",
  "/medication-tracker": "Poultry",
  "/birds-left-tracker": "Poultry",
  "/poultry-": "Poultry",
  "/poultry/": "Poultry",
}

// Routes that are always accessible regardless of company type.
const SHARED_ROUTES = new Set([
  "/",
  "/login",
  "/login-2fa",
  "/register",
  "/forgot-password",
  "/reset-password",
  "/verify-account",
  "/profile",
  "/companies",
  "/pricing",
  "/help",
  "/terms",
  "/resources",
  "/audit-logs",
  "/test-email-confirmation",
  "/business-office",
  "/dashboard",       // Poultry dashboard but also the default fallback
  "/water-dashboard",
  "/hotel-dashboard",
  "/restaurant-dashboard",
  "/generic-dashboard",
])

/**
 * Returns the required company type for a given pathname, or null if it's
 * a shared route accessible to all types.
 */
function requiredTypeForPath(pathname: string): CompanyType | null {
  // Exact shared routes
  if (SHARED_ROUTES.has(pathname)) return null

  // Check prefix-based rules (longer prefixes checked first via the order)
  for (const [prefix, type] of Object.entries(ROUTE_PREFIX_TO_TYPE)) {
    if (pathname.startsWith(prefix)) return type
  }

  // Unrecognised routes default to shared (accessible)
  return null
}

export function CompanyTypeGuard() {
  const pathname = usePathname()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [blocked, setBlocked] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return
    if (!pathname) return
    if (!localStorage.getItem("auth_token")) return
    // Wait for store hydration — activeFarmType is null until hydrated
    if (!activeFarmType) return

    const required = requiredTypeForPath(pathname)
    if (required === null) {
      // Shared route — always allowed
      setBlocked(false)
      return
    }

    if (required === activeFarmType) {
      setBlocked(false)
      return
    }

    // Mismatch — block
    setBlocked(true)
  }, [pathname, activeFarmType])

  // Listen for company-switch events and re-evaluate the block state
  useEffect(() => {
    if (typeof window === "undefined") return

    const handleCompanyChanged = () => {
      const newType = localStorage.getItem("farmType") as CompanyType | null
      if (!newType) return

      const required = requiredTypeForPath(window.location.pathname)
      if (required !== null && required !== newType) {
        // Current page is not compatible with the new company type — block it
        setBlocked(true)
      } else {
        setBlocked(false)
      }
    }

    window.addEventListener(COMPANY_CHANGED_EVENT, handleCompanyChanged)
    return () => window.removeEventListener(COMPANY_CHANGED_EVENT, handleCompanyChanged)
  }, [])

  if (!blocked) return null

  return <CompanyTypeMismatch activeFarmType={activeFarmType} />
}
