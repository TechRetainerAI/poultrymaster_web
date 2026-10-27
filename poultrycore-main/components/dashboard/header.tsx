"use client"

import { EggsPerCrateLoader } from "@/hooks/use-eggs-per-crate"
import { useFarmAlertCount } from "@/hooks/use-farm-alert-count"

import { Button } from "@/components/ui/button"
import { MessageCircle, User, Menu, Briefcase, Bell } from "lucide-react"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { useChatStore } from "@/lib/store/chat-store"
import { useSidebarStore } from "@/lib/store/sidebar-store"
import { useAuthStore } from "@/lib/store/auth-store"
import { TopNavigation } from "./top-nav"
import { MobileBottomNav } from "./mobile-bottom-nav"
import { InventoryLogo } from "@/components/auth/logo"
import { CompanySwitcher } from "./company-switcher"
import { GlobalSearch } from "./global-search"

export function DashboardHeader() {
  const router = useRouter()
  const unread = useChatStore((s) => s.unreadCount)
  const openChat = useChatStore((s) => s.openChat)
  const { isCollapsed, isMobileOpen, toggleMobile } = useSidebarStore()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const alertCount = useFarmAlertCount()
  const clearActiveCompany = useAuthStore((s) => s.clearActiveCompany)
  const [username, setUsername] = useState("")
  const [roleLabel, setRoleLabel] = useState("")

  useEffect(() => {
    if (typeof window === 'undefined') return
    setUsername(localStorage.getItem('username') || localStorage.getItem('userName') || "")
    setRoleLabel(localStorage.getItem('isStaff') === 'true' ? 'Staff' : 'Admin')
  }, [])

  // Search placeholder adapts to active company type. Poultry-only terms
  // ("flocks") shouldn't show on Water or Generic companies.
  const searchPlaceholder =
    activeFarmType === "Water"   ? "Search pages, customers, drivers…" :
    activeFarmType === "Generic" ? "Search pages, customers, products…" :
    activeFarmType === "Hotel" || activeFarmType === "Restaurant" ? "Search pages and reports…" :
    "Search pages, customers, flocks…"

  return (
    <div className="flex flex-col min-w-0 overflow-x-hidden">
      {/* Loads the farm's eggs per crate (344) once, for every egg screen. */}
      <EggsPerCrateLoader />
      <header className="bg-slate-900 border-b border-slate-800 px-2 sm:px-6 py-3 min-w-0">
        <div className="hidden lg:flex items-center justify-between gap-4">
          {/* VisibilityCore branding - visible when sidebar doesn't show its own */}
          {isCollapsed && (
            <div className="shrink-0">
              <InventoryLogo dark />
            </div>
          )}

          {/* Company switcher */}
          <div className="hidden xl:block">
            <CompanySwitcher />
          </div>

          {/* Search */}
          <div className="flex-1 max-w-md min-w-0">
            <GlobalSearch placeholder={searchPlaceholder} />
          </div>

          {/* Right side actions */}
          <div className="flex items-center gap-2 sm:gap-4">
            <span className="text-sm text-slate-300 whitespace-nowrap">
              Welcome, <span className="text-white font-medium">{username || 'User'}</span>
              {roleLabel && <span className="text-slate-400"> ({roleLabel})</span>}
            </span>

            {/* Business Office and chat sit together as a pair — both leave the
                page you are on rather than acting on it. Business Office clears
                the active company on the way in (same behaviour as the sidebar),
                because it is the one destination above all companies. */}
            <div className="flex items-center gap-1">
              {/* Farm Alerts: completeness, unsorted eggs, flock alerts, stock
                  running low. Poultry only -- the page is poultry's. */}
              {activeFarmType === "Poultry" && (
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => router.push("/poultry-alerts")}
                  title={alertCount ? `Farm Alerts — ${alertCount} need attention` : "Farm Alerts"}
                  aria-label={alertCount ? `Farm Alerts, ${alertCount} need attention` : "Farm Alerts"}
                  className="relative shrink-0 text-slate-300 hover:text-white hover:bg-slate-800"
                >
                  <Bell className="h-5 w-5" />
                  {alertCount != null && alertCount > 0 && (
                    <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 bg-red-600 text-white text-[10px] rounded-full flex items-center justify-center">
                      {alertCount > 99 ? '99+' : alertCount}
                    </span>
                  )}
                </Button>
              )}
              <Button
                variant="ghost"
                size="icon"
                onClick={() => {
                  try { clearActiveCompany() } catch {}
                  router.push("/business-office")
                }}
                title="Business Office"
                aria-label="Business Office"
                className="shrink-0 text-slate-300 hover:text-white hover:bg-slate-800"
              >
                <Briefcase className="h-5 w-5" />
              </Button>

              <div className="relative">
                <Button
                  onClick={() => openChat()}
                  variant="ghost"
                  size="icon"
                  aria-label="Open chat"
                  className="text-slate-300 hover:text-white hover:bg-slate-800 relative min-h-[44px] min-w-[44px] lg:min-h-0 lg:min-w-0"
                >
                  <MessageCircle className="h-5 w-5" />
                  {unread > 0 && (
                    <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 bg-red-600 text-white text-[10px] rounded-full flex items-center justify-center">
                      {unread > 99 ? '99+' : unread}
                    </span>
                  )}
                </Button>
              </div>
            </div>

            <Button 
              variant="ghost" 
              size="icon" 
              className="text-slate-300 hover:text-white hover:bg-slate-800 min-h-[44px] min-w-[44px] lg:min-h-0 lg:min-w-0"
              onClick={() => router.push('/profile')}
              aria-label="View profile"
            >
              <div className="w-8 h-8 bg-purple-600 rounded-full flex items-center justify-center">
                <User className="h-4 w-4 text-white" />
              </div>
            </Button>
          </div>
        </div>

        {/* Mobile header layout: top row actions + full-width search */}
        <div className="lg:hidden space-y-2">
          <div className="flex items-center justify-between gap-1 min-w-0">
            <Button
              variant="ghost"
              size="icon"
              onClick={() => toggleMobile()}
              className="text-slate-300 hover:text-white hover:bg-slate-800 h-12 w-12 shrink-0"
              aria-label="Toggle sidebar"
            >
              <Menu className="h-7 w-7" />
            </Button>

            {!isMobileOpen && (
              <div className="min-w-0 flex-1">
                <InventoryLogo dark />
              </div>
            )}

            <div className="flex items-center gap-0.5 shrink-0">
              {activeFarmType === "Poultry" && (
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => router.push("/poultry-alerts")}
                  aria-label={alertCount ? `Farm Alerts, ${alertCount} need attention` : "Farm Alerts"}
                  className="relative text-slate-300 hover:text-white hover:bg-slate-800 h-10 w-10"
                >
                  <Bell className="h-5 w-5" />
                  {alertCount != null && alertCount > 0 && (
                    <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 bg-red-600 text-white text-[10px] rounded-full flex items-center justify-center">
                      {alertCount > 99 ? '99+' : alertCount}
                    </span>
                  )}
                </Button>
              )}
              <div className="relative">
                <Button
                  onClick={() => openChat()}
                  variant="ghost"
                  size="icon"
                  aria-label="Open chat"
                  className="text-slate-300 hover:text-white hover:bg-slate-800 relative h-10 w-10"
                >
                  <MessageCircle className="h-5 w-5" />
                  {unread > 0 && (
                    <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 bg-red-600 text-white text-[10px] rounded-full flex items-center justify-center">
                      {unread > 99 ? '99+' : unread}
                    </span>
                  )}
                </Button>
              </div>

              <Button
                variant="ghost"
                size="icon"
                className="text-slate-300 hover:text-white hover:bg-slate-800 h-10 w-10"
                onClick={() => router.push('/profile')}
                aria-label="View profile"
              >
                <div className="w-8 h-8 bg-purple-600 rounded-full flex items-center justify-center">
                  <User className="h-4 w-4 text-white" />
                </div>
              </Button>
            </div>
          </div>

          <div className="w-full">
            <CompanySwitcher fullWidth />
          </div>
          {/* Search bar removed on mobile per request — global search remains
              available on desktop and via the in-page list filters. */}
        </div>
      </header>

      {/* Top horizontal navigation - visible on desktop only */}
      <TopNavigation />

      {/* Mobile bottom tab bar - visible on mobile only */}
      <MobileBottomNav />
    </div>
  )
}
