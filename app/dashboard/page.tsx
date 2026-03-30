"use client"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { MetricsCards } from "@/components/dashboard/metrics-cards"
import { DashboardCharts } from "@/components/dashboard/charts"
import { Setup2FADialog } from "@/components/auth/setup-2fa-dialog"

export default function DashboardPage() {
  const router = useRouter()
  const [show2FASetup, setShow2FASetup] = useState(false)
  const [twoFactorEnabled, setTwoFactorEnabled] = useState(false)

  // Check if user has 2FA enabled
  useEffect(() => {
    // Check from localStorage if 2FA is enabled
    const check2FA = localStorage.getItem("twoFactorEnabled")
    const skipped2FA = localStorage.getItem("2FASkipped")
    
    // Only show dialog if 2FA is not enabled and user hasn't skipped it
    if (check2FA !== "true" && skipped2FA !== "true") {
      // Show dialog after a short delay
      const timer = setTimeout(() => {
        setShow2FASetup(true)
      }, 2000)
      return () => clearTimeout(timer)
    }
  }, [])

  const handleEnable2FA = async () => {
    try {
      console.log("Enabling 2FA...")
      const token = localStorage.getItem("auth_token")
      
      // Call the API to enable 2FA
      const rawAdmin = process.env.NEXT_PUBLIC_ADMIN_API_URL || process.env.NEXT_PUBLIC_API_BASE_URL || 'usermanagementapi.techretainer.com'
      const baseUrl = rawAdmin.startsWith('http://') || rawAdmin.startsWith('https://') ? rawAdmin : `https://${rawAdmin}`
      const response = await fetch(`${baseUrl}/api/Authentication/enable-2fa`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${token}`,
          "Content-Type": "application/json",
        },
      })
      
      const result = await response.json()
      console.log("Enable 2FA response:", result)
      
      if (response.ok) {
        localStorage.setItem("twoFactorEnabled", "true")
        setTwoFactorEnabled(true)
        setShow2FASetup(false)
        alert("2FA has been enabled! On your next login, you'll receive an OTP code via email.")
      } else {
        alert(result.message || "Failed to enable 2FA. Please try again.")
      }
    } catch (error) {
      console.error("Error enabling 2FA:", error)
      alert("Failed to enable 2FA. Please try again.")
    }
  }

  const handleSkip2FA = () => {
    setShow2FASetup(false)
    // Store that user skipped for this session
    localStorage.setItem("2FASkipped", "true")
  }

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  return (
    <>
      <div className="flex min-h-screen bg-slate-50">
        {/* Sidebar - hidden on mobile, shown as overlay */}
        <DashboardSidebar onLogout={handleLogout} />
        
        {/* Main Content - full width on mobile */}
        <div className="flex-1 flex flex-col w-full lg:w-auto">
          {/* Header */}
          <DashboardHeader />
          
          {/* Main Content Area */}
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="space-y-6">
              {/* Metrics Cards */}
              <MetricsCards />
              
              {/* Charts */}
              <DashboardCharts />
            </div>
          </main>
        </div>
      </div>

      {/* 2FA Setup Dialog */}
      <Setup2FADialog
        open={show2FASetup}
        onClose={handleSkip2FA}
        onEnable={handleEnable2FA}
        onSkip={handleSkip2FA}
      />
    </>
  )
}
