"use client"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Search, Users, Bell, User, Menu } from "lucide-react"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { useChatStore } from "@/lib/store/chat-store"
import { useSidebarStore } from "@/lib/store/sidebar-store"
import { TopNavigation } from "./top-nav"
import { MobileBottomNav } from "./mobile-bottom-nav"
import { InventoryLogo } from "@/components/auth/logo"

export function DashboardHeader() {
  const router = useRouter()
  const unread = useChatStore((s) => s.unreadCount)
  const openChat = useChatStore((s) => s.openChat)
  const { isCollapsed, isMobileOpen, toggleMobile } = useSidebarStore()
  const [username, setUsername] = useState("")
  const [roleLabel, setRoleLabel] = useState("")
  const [farmName, setFarmName] = useState("")
  const [searchQuery, setSearchQuery] = useState("")

  useEffect(() => {
    if (typeof window === 'undefined') return
    const u = localStorage.getItem('username') || localStorage.getItem('userName') || ""
    const f = localStorage.getItem('farmName') || localStorage.getItem('FarmName') || ""
    const isStaff = localStorage.getItem('isStaff') === 'true'
    setUsername(u)
    setFarmName(f)
    setRoleLabel(isStaff ? 'Staff' : 'Admin')
  }, [])

  // Define all available pages for navigation
  const pageRoutes = [
    { path: '/dashboard', keywords: ['overview', 'dashboard', 'home', 'main'] },
    { path: '/customers', keywords: ['customers', 'customer', 'client'] },
    { path: '/flocks', keywords: ['flocks', 'flock', 'birds', 'chicken'] },
    { path: '/flock-batch', keywords: ['flock batch', 'batch', 'batches'] },
    { path: '/employees', keywords: ['employees', 'employee', 'staff', 'workers'] },
    { path: '/sales', keywords: ['sales', 'sale', 'sell', 'revenue'] },
    { path: '/expenses', keywords: ['expenses', 'expense', 'cost', 'spending'] },
    { path: '/inventory', keywords: ['inventory', 'stock', 'items'] },
    { path: '/supplies', keywords: ['supplies', 'supply', 'materials'] },
    { path: '/production-records', keywords: ['production', 'records', 'production records'] },
    { path: '/egg-production', keywords: ['egg production', 'eggs', 'egg'] },
    { path: '/feed-usage', keywords: ['feed usage', 'feed', 'feeding'] },
    { path: '/health', keywords: ['health', 'vaccination', 'medication'] },
    { path: '/houses', keywords: ['houses', 'house', 'poultry house'] },
    { path: '/reports', keywords: ['reports', 'report', 'analytics'] },
    { path: '/profile', keywords: ['profile', 'account', 'user', 'settings'] },
    { path: '/audit-logs', keywords: ['audit logs', 'audit', 'logs', 'activity'] },
    { path: '/settings', keywords: ['settings', 'configuration', 'config'] },
    { path: '/resources', keywords: ['resources', 'resource', 'help'] },
    { path: '/help', keywords: ['help center', 'help', 'faq', 'how to', 'guide'] },
    { path: '/support', keywords: ['support', 'contact', 'talk to poultry master', 'poultry master', 'email', 'billing help'] },
    { path: '/terms', keywords: ['terms', 'conditions', 'policy'] },
  ]

  const findMatchingPage = (query: string): string | null => {
    const lowerQuery = query.toLowerCase().trim()
    if (!lowerQuery) return null
    
    // Exact match first
    for (const route of pageRoutes) {
      if (route.path === lowerQuery || route.path === `/${lowerQuery}`) {
        return route.path
      }
    }
    
    // Keyword match
    for (const route of pageRoutes) {
      for (const keyword of route.keywords) {
        if (lowerQuery.includes(keyword) || keyword.includes(lowerQuery)) {
          return route.path
        }
      }
    }
    
    return null
  }

  const handleSearchChange = (value: string) => {
    setSearchQuery(value)
    
    // Work in real-time - dispatch search event immediately as user types
    if (typeof window !== 'undefined') {
      const currentPath = window.location.pathname
      
      // If already on a list page, trigger search immediately for data filtering
      if (currentPath.includes('/employees') || 
          currentPath.includes('/customers') || 
          currentPath.includes('/flocks') ||
          currentPath.includes('/sales') ||
          currentPath.includes('/inventory') ||
          currentPath.includes('/expenses') ||
          currentPath.includes('/supplies') ||
          currentPath.includes('/health') ||
          currentPath.includes('/audit-logs')) {
        // Dispatch event for pages to listen to in real-time
        window.dispatchEvent(new CustomEvent('globalSearch', { detail: { query: value.trim() } }))
      }
      
      // Store in sessionStorage for navigation between pages
      if (value.trim()) {
        sessionStorage.setItem('globalSearchQuery', value.trim())
      } else {
        sessionStorage.removeItem('globalSearchQuery')
      }
    }
  }

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault()
    if (!searchQuery.trim()) return
    
    const matchingPage = findMatchingPage(searchQuery)
    
    if (matchingPage) {
      // Navigate to the matching page
      router.push(matchingPage)
      setSearchQuery("") // Clear search after navigation
      sessionStorage.removeItem('globalSearchQuery')
    } else {
      // If no page match, check if we're on a searchable page and filter data
      const currentPath = typeof window !== 'undefined' ? window.location.pathname : ''
      
      if (currentPath.includes('/employees') || 
          currentPath.includes('/customers') || 
          currentPath.includes('/flocks') ||
          currentPath.includes('/sales') ||
          currentPath.includes('/inventory') ||
          currentPath.includes('/expenses') ||
          currentPath.includes('/supplies') ||
          currentPath.includes('/health') ||
          currentPath.includes('/audit-logs')) {
        // Already filtering on current page, do nothing
      } else {
        // Navigate to dashboard if no match
        router.push('/dashboard')
      }
    }
  }

  return (
    <div className="flex flex-col min-w-0">
      <header className="bg-slate-900 border-b border-slate-800 px-2 sm:px-6 py-3 min-w-0">
        <div className="hidden lg:flex items-center justify-between gap-4">
          {/* Poultry Master branding - visible when sidebar doesn't show its own */}
          {isCollapsed && (
            <div className="shrink-0">
              <InventoryLogo dark />
            </div>
          )}

          {/* Farm name */}
          <div className="hidden xl:flex items-center gap-2 min-w-0 max-w-[240px]">
            <span className="text-xs text-slate-400 uppercase tracking-wide">Farm</span>
            <span className="text-sm text-white font-medium truncate">{farmName || "My Farm"}</span>
          </div>

          {/* Search */}
          <form onSubmit={handleSearch} className="flex-1 max-w-md min-w-0">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
              <Input
                type="text"
                placeholder="Search customers, flocks, sales..."
                value={searchQuery}
                onChange={(e) => handleSearchChange(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Escape') {
                    handleSearchChange('')
                  }
                }}
                className="pl-10 min-h-[44px] lg:min-h-9 bg-slate-800 border-slate-700 text-white placeholder:text-slate-400 focus:bg-slate-700 focus:border-slate-600"
              />
            </div>
          </form>

          {/* Right side actions */}
          <div className="flex items-center gap-2 sm:gap-4">
            <div className="flex items-center gap-2 text-slate-300">
              <Users className="h-5 w-5" />
              <div className="hidden sm:flex flex-col leading-tight">
                <span className="text-xs text-slate-400">{roleLabel}</span>
                <span className="text-sm text-white truncate max-w-[140px]">{username || 'User'}</span>
              </div>
            </div>
            
            <div className="relative">
              <Button
                onClick={() => openChat()}
                variant="ghost"
                size="icon"
                className="text-slate-300 hover:text-white hover:bg-slate-800 relative min-h-[44px] min-w-[44px] lg:min-h-0 lg:min-w-0"
              >
                <Bell className="h-5 w-5" />
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
              className="text-slate-300 hover:text-white hover:bg-slate-800 h-10 w-10 shrink-0"
              aria-label="Toggle sidebar"
            >
              <Menu className="h-5 w-5" />
            </Button>

            {!isMobileOpen && (
              <div className="min-w-0 flex-1">
                <InventoryLogo dark />
              </div>
            )}

            <div className="flex items-center gap-0.5 shrink-0">
              <div className="relative">
                <Button
                  onClick={() => openChat()}
                  variant="ghost"
                  size="icon"
                  className="text-slate-300 hover:text-white hover:bg-slate-800 relative h-10 w-10"
                >
                  <Bell className="h-5 w-5" />
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

          <div className="text-xs text-slate-300 truncate px-1">
            <span className="text-slate-400">Farm:</span> {farmName || "My Farm"}
          </div>

          <form onSubmit={handleSearch} className="w-full min-w-0">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
              <Input
                type="text"
                placeholder="Search..."
                value={searchQuery}
                onChange={(e) => handleSearchChange(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Escape') {
                    handleSearchChange('')
                  }
                }}
                className="pl-10 min-h-[44px] bg-slate-800 border-slate-700 text-white placeholder:text-slate-400 focus:bg-slate-700 focus:border-slate-600"
              />
            </div>
          </form>
        </div>
      </header>

      {/* Top horizontal navigation - visible on desktop only */}
      <TopNavigation />

      {/* Mobile bottom tab bar - visible on mobile only */}
      <MobileBottomNav />
    </div>
  )
}
