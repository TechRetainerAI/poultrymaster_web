"use client"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { InfoSection, InfoRow, PageHeader, StatusBadge } from "@/components/ui/info-section"
import { type UserProfile } from "@/lib/api/user-profile"
import { Edit2, Save, X, User, Mail, Phone, Building2, Shield, Check } from "lucide-react"
import { SuccessModal } from "@/components/auth/success-modal"
import { AuthService } from "@/lib/services/auth.service"
import { useAuth } from "@/lib/hooks/use-auth"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { DEFAULT_LOGIN_API_HOST } from "@/lib/api/default-api-hosts"
import { getAuthenticationApiUrl, tryRefreshAccessToken } from "@/lib/api/auth"
import { getAuthHeaders } from "@/lib/api/config"

export default function ProfilePage() {
  const router = useRouter()
  const { user, logout } = useAuth()
  const [profile, setProfile] = useState<UserProfile | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isEditing, setIsEditing] = useState(false)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState("")
  const [showSuccess, setShowSuccess] = useState(false)
  const [isToggling2FA, setIsToggling2FA] = useState(false)
  const [successMessage, setSuccessMessage] = useState({ title: "", message: "" })

  // Form state
  const [formData, setFormData] = useState({
    firstName: "",
    lastName: "",
    email: "",
    phoneNumber: "",
    farmName: "",
  })

  useEffect(() => {
    loadProfile()
  }, [])

  const loadProfile = async () => {
    setIsLoading(true)
    setError("")

    try {
      const userData = await AuthService.getCurrentUser()
      
      const username = userData.username || ""
      const email = userData.email || ""
      
      const profileData = {
        id: userData.id,
        userName: username,
        normalizedUserName: username.toUpperCase(),
        email: email,
        normalizedEmail: email.toUpperCase(),
        emailConfirmed: true,
        passwordHash: "",
        securityStamp: "",
        concurrencyStamp: "",
        phoneNumber: userData.phone || userData.phoneNumber || "",
        phoneNumberConfirmed: false,
        twoFactorEnabled: userData.twoFactorEnabled || (typeof window !== "undefined" ? localStorage.getItem("twoFactorEnabled") === "true" : false),
        lockoutEnd: null,
        lockoutEnabled: true,
        accessFailedCount: 0,
        farmId: userData.farmId || "",
        farmName: userData.farmName || "",
        isStaff: userData.isStaff || false,
        isSubscriber: userData.isSubscriber || false,
        refreshToken: "",
        refreshTokenExpiry: "",
        firstName: userData.firstName || "",
        lastName: userData.lastName || "",
        customerId: userData.customerId || ""
      } as UserProfile
      
      setProfile(profileData)
      
      setFormData({
        firstName: userData.firstName || "",
        lastName: userData.lastName || "",
        email: email,
        phoneNumber: userData.phoneNumber || userData.phone || "",
        farmName: userData.farmName || "",
      })
    } catch (error: any) {
      if (error?.status === 404 || (error instanceof Error && error.message.includes('404'))) {
        const userId = typeof window !== "undefined" ? localStorage.getItem("userId") : null
        const username = typeof window !== "undefined" ? localStorage.getItem("username") : null
        const farmId = typeof window !== "undefined" ? localStorage.getItem("farmId") : null
        const farmName = typeof window !== "undefined" ? localStorage.getItem("farmName") : null
        
        if (userId && username) {
          const profileData: UserProfile = {
            id: userId,
            userName: username,
            normalizedUserName: username.toUpperCase(),
            email: username,
            normalizedEmail: username.toUpperCase(),
            emailConfirmed: false,
            passwordHash: "",
            securityStamp: "",
            concurrencyStamp: "",
            phoneNumber: "",
            phoneNumberConfirmed: false,
            twoFactorEnabled: typeof window !== "undefined" ? localStorage.getItem("twoFactorEnabled") === "true" : false,
            lockoutEnd: null,
            lockoutEnabled: true,
            accessFailedCount: 0,
            farmId: farmId || "",
            farmName: farmName || "",
            isStaff: typeof window !== "undefined" ? localStorage.getItem("isStaff") === "true" : false,
            isSubscriber: typeof window !== "undefined" ? localStorage.getItem("isSubscriber") === "true" : false,
            refreshToken: "",
            refreshTokenExpiry: "",
            firstName: "",
            lastName: "",
            customerId: ""
          }
          setProfile(profileData)
          setFormData({
            firstName: "",
            lastName: "",
            email: username,
            phoneNumber: "",
            farmName: farmName || "",
          })
          setIsLoading(false)
          return
        }
      }
      
      console.error("Error loading profile:", error)
      setError(error instanceof Error ? error.message : "Failed to load profile. Please try again.")
      if (error?.status === 401 || (error instanceof Error && error.message.includes('401'))) {
        router.push('/login')
      }
    }

    setIsLoading(false)
  }

  const handleEdit = () => {
    setIsEditing(true)
    setError("")
  }

  const handleCancel = () => {
    setIsEditing(false)
    setError("")
    if (profile) {
      setFormData({
        firstName: profile.firstName || "",
        lastName: profile.lastName || "",
        email: profile.email || "",
        phoneNumber: profile.phoneNumber || "",
        farmName: profile.farmName || "",
      })
    }
  }

  const handleSave = async () => {
    setIsSaving(true)
    setError("")

    try {
      // Same-origin proxy → Login API. The previous code hit the Login API
      // origin directly, which would 404 with a CORS preflight failure on most
      // browsers and made it look like the save "worked" because the catch
      // wrote to localStorage instead. One automatic refresh-then-retry on 401
      // so an expired token doesn't kick the user back to login mid-edit.
      const url = getAuthenticationApiUrl("update-profile")
      const doFetch = () =>
        fetch(url, {
          method: "PUT",
          headers: getAuthHeaders(),
          body: JSON.stringify({
            firstName: formData.firstName,
            lastName: formData.lastName,
            email: formData.email,
            phoneNumber: formData.phoneNumber,
            farmName: formData.farmName,
          }),
        })

      let response = await doFetch()
      if (response.status === 401 && (await tryRefreshAccessToken())) {
        response = await doFetch()
      }

      if (!response.ok) {
        const errorText = await response.text()
        throw new Error(errorText || `Failed to update profile (HTTP ${response.status})`)
      }

      // Mirror farmName into localStorage so the dashboard header / sidebar
      // pick it up without waiting for a /Companies/mine refresh.
      if (typeof window !== "undefined" && formData.farmName) {
        localStorage.setItem("farmName", formData.farmName)
      }

      setSuccessMessage({
        title: "Profile Updated Successfully!",
        message: "Your profile information has been updated"
      })
      setShowSuccess(true)
      setIsEditing(false)
      await loadProfile()
    } catch (error) {
      setError(error instanceof Error ? error.message : "Failed to update profile")
    }

    setIsSaving(false)
  }

  const handleInputChange = (field: string, value: string) => {
    setFormData((prev) => ({
      ...prev,
      [field]: value,
    }))
  }

  const handleToggle2FA = async (enabled: boolean) => {
    setIsToggling2FA(true)
    setError("")

    try {
      // Same-origin proxy → Login API. The previous code hit the Login API
      // origin directly and had a silent localStorage fallback on 404 that
      // pretended 2FA was on — that's exactly why the login flow never
      // actually challenged for an OTP. One refresh-then-retry on 401.
      const url = getAuthenticationApiUrl(enabled ? "enable-2fa" : "disable-2fa")
      const doFetch = () => fetch(url, { method: "POST", headers: getAuthHeaders() })

      let response = await doFetch()
      if (response.status === 401 && (await tryRefreshAccessToken())) {
        response = await doFetch()
      }

      if (!response.ok) {
        const errorText = await response.text()
        throw new Error(errorText || `Failed to ${enabled ? 'enable' : 'disable'} 2FA (HTTP ${response.status})`)
      }

      setProfile((prev) => prev ? ({ ...prev, twoFactorEnabled: enabled }) : prev)
      // Mirror to localStorage so the next login page render reads the latest
      // state without waiting for a fresh getCurrentUser round-trip.
      if (typeof window !== "undefined") {
        localStorage.setItem("twoFactorEnabled", enabled ? "true" : "false")
      }

      setSuccessMessage({
        title: enabled ? "2FA Enabled!" : "2FA Disabled!",
        message: enabled
          ? "Two-factor authentication has been enabled. You'll receive OTP codes via email during login."
          : "Two-factor authentication has been disabled. You can enable it again anytime from your profile."
      })
      setShowSuccess(true)
    } catch (error) {
      setError(error instanceof Error ? error.message : `Failed to ${enabled ? 'enable' : 'disable'} 2FA`)
    }

    setIsToggling2FA(false)
  }

  if (isLoading) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="flex items-center justify-center h-full">
              <div className="text-center">
                <div className="w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
                <p className="text-slate-600">Loading profile...</p>
              </div>
            </div>
          </main>
        </div>
      </div>
    )
  }

  return (
    <>
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="space-y-6">
              {/* Page Header */}
              <PageHeader 
                title="User Profile"
                subtitle="Manage information about you and this account"
                action={
                  !isEditing ? (
                    <Button onClick={handleEdit} variant="outline" className="gap-2">
                      <Edit2 className="w-4 h-4" />
                      Edit
                    </Button>
                  ) : (
                    <div className="flex gap-2">
                      <Button onClick={handleCancel} disabled={isSaving} className="bg-red-600 hover:bg-red-700 text-white">
                        <X className="w-4 h-4 mr-2" />
                        Cancel
                      </Button>
                      <Button onClick={handleSave} disabled={isSaving} className="bg-blue-600 hover:bg-blue-700">
                        {isSaving ? (
                          <span className="flex items-center gap-2">
                            <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
                            Saving...
                          </span>
                        ) : (
                          <>
                            <Save className="w-4 h-4 mr-2" />
                            Save
                          </>
                        )}
                      </Button>
                    </div>
                  )
                }
              />

              {/* Error Alert */}
              {error && (
                <Alert variant="destructive" className="mb-6">
                  <AlertDescription>{error}</AlertDescription>
                </Alert>
              )}

              <div className="space-y-4">
                {/* Row 1: About You + Contact Information */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {/* About You Section */}
                  <InfoSection title="About you" collapsible={false}>
                    {isEditing ? (
                      <div className="space-y-4 py-2">
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">First Name</Label>
                          <Input
                            value={formData.firstName}
                            onChange={(e) => handleInputChange("firstName", e.target.value)}
                            placeholder="John"
                            disabled={isSaving}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">Last Name</Label>
                          <Input
                            value={formData.lastName}
                            onChange={(e) => handleInputChange("lastName", e.target.value)}
                            placeholder="Doe"
                            disabled={isSaving}
                          />
                        </div>
                      </div>
                    ) : (
                      <>
                        <InfoRow label="Account type" value={profile?.isStaff ? "Staff" : profile?.isSubscriber ? "Subscriber" : "Organization"} />
                        <InfoRow label="User ID" value={<span className="font-mono text-xs">{profile?.id}</span>} />
                        <InfoRow label="Username" value={profile?.userName} />
                        <InfoRow label="Full name" value={`${profile?.firstName || ''} ${profile?.lastName || ''}`.trim() || "Not set"} />
                      </>
                    )}
                  </InfoSection>

                  {/* Contact Information */}
                  <InfoSection title="Contact information" collapsible={false}>
                    {isEditing ? (
                      <div className="space-y-4 py-2">
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">Email address</Label>
                          <Input
                            type="email"
                            value={formData.email}
                            onChange={(e) => handleInputChange("email", e.target.value)}
                            placeholder="john@example.com"
                            disabled={isSaving}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">Phone number</Label>
                          <Input
                            type="tel"
                            value={formData.phoneNumber}
                            onChange={(e) => handleInputChange("phoneNumber", e.target.value)}
                            placeholder="+1 (555) 123-4567"
                            disabled={isSaving}
                          />
                        </div>
                      </div>
                    ) : (
                      <>
                        <InfoRow 
                          label="Email address" 
                          value={
                            <div className="flex items-center gap-2">
                              {profile?.email}
                              {profile?.emailConfirmed && <Check className="w-4 h-4 text-emerald-500" />}
                            </div>
                          }
                          icon={<Mail className="w-4 h-4" />}
                        />
                        <InfoRow 
                          label="Phone number" 
                          value={profile?.phoneNumber}
                          icon={<Phone className="w-4 h-4" />}
                        />
                      </>
                    )}
                  </InfoSection>
                </div>

                {/* Row 2: Farm Details + Account Status */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {/* Farm Information */}
                  <InfoSection title="Farm details" collapsible={false}>
                    {isEditing ? (
                      <div className="space-y-4 py-2">
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">Farm name</Label>
                          <Input
                            value={formData.farmName}
                            onChange={(e) => handleInputChange("farmName", e.target.value)}
                            placeholder="My Farm"
                            disabled={isSaving}
                          />
                        </div>
                      </div>
                    ) : (
                      <>
                        <InfoRow 
                          label="Farm name" 
                          value={profile?.farmName}
                          icon={<Building2 className="w-4 h-4" />}
                        />
                        <InfoRow 
                          label="Farm ID" 
                          value={<span className="font-mono text-xs">{profile?.farmId}</span>}
                        />
                      </>
                    )}
                  </InfoSection>

                  {/* Account Status */}
                  <InfoSection title="Account status" collapsible={false}>
                    <InfoRow 
                      label="Email verified" 
                      value={<StatusBadge status={profile?.emailConfirmed ? "verified" : "unverified"} />}
                    />
                    <InfoRow 
                      label="Phone verified" 
                      value={<StatusBadge status={profile?.phoneNumberConfirmed ? "verified" : "unverified"} />}
                    />
                  </InfoSection>
                </div>

                {/* Row 3: Security */}
                <InfoSection title="Security" collapsible={false}>
                  <div className="py-3">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <Shield className="w-5 h-5 text-slate-400" />
                        <div>
                          <p className="text-sm font-medium text-slate-900">Two-factor authentication</p>
                          <p className="text-xs text-slate-500">
                            {profile?.twoFactorEnabled 
                              ? "Enabled - OTP codes sent via email"
                              : "Add extra security to your account"}
                          </p>
                        </div>
                      </div>
                      <Switch
                        checked={profile?.twoFactorEnabled || false}
                        onCheckedChange={handleToggle2FA}
                        disabled={isToggling2FA}
                      />
                    </div>
                  </div>
                </InfoSection>
              </div>
            </div>
          </main>
        </div>
      </div>

      {showSuccess && (
        <SuccessModal
          title={successMessage.title}
          message={successMessage.message}
          onClose={() => {
            setShowSuccess(false)
            setIsToggling2FA(false)
          }}
          buttonText="Continue"
        />
      )}
    </>
  )
}
