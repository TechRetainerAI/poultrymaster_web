"use client"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { InfoSection, InfoRow, PageHeader } from "@/components/ui/info-section"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"
import { Save, MapPin, DollarSign, Building2, Phone, Mail, Globe, Users, Clock } from "lucide-react"
import { SuccessModal } from "@/components/auth/success-modal"
import { Alert, AlertDescription } from "@/components/ui/alert"

export default function SettingsPage() {
  const router = useRouter()
  const [isEditing, setIsEditing] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState("")
  const [showSuccess, setShowSuccess] = useState(false)

  // Form state
  const [formData, setFormData] = useState({
    farmName: "",
    farmLocation: "",
    currency: "GHS",
    farmPhone: "",
    farmEmail: "",
    farmType: "",
    totalCapacity: "",
    operatingHours: "",
    farmDescription: "",
    ownerName: "",
    timezone: "",
  })

  useEffect(() => {
    loadSettings()
  }, [])

  const loadSettings = async () => {
    try {
      setFormData({
        farmName: localStorage.getItem("farmName") || "",
        farmLocation: localStorage.getItem("farmLocation") || "",
        currency: localStorage.getItem("currency") || "GHS",
        farmPhone: localStorage.getItem("farmPhone") || "",
        farmEmail: localStorage.getItem("farmEmail") || "",
        farmType: localStorage.getItem("farmType") || "",
        totalCapacity: localStorage.getItem("totalCapacity") || "",
        operatingHours: localStorage.getItem("operatingHours") || "",
        farmDescription: localStorage.getItem("farmDescription") || "",
        ownerName: localStorage.getItem("ownerName") || "",
        timezone: localStorage.getItem("timezone") || "",
      })
    } catch (error) {
      console.error("Error loading settings:", error)
    }
  }

  const handleSave = async () => {
    setIsSaving(true)
    setError("")

    try {
      localStorage.setItem("farmName", formData.farmName)
      localStorage.setItem("farmLocation", formData.farmLocation)
      localStorage.setItem("currency", formData.currency.toUpperCase())
      localStorage.setItem("farmPhone", formData.farmPhone)
      localStorage.setItem("farmEmail", formData.farmEmail)
      localStorage.setItem("farmType", formData.farmType)
      localStorage.setItem("totalCapacity", formData.totalCapacity)
      localStorage.setItem("operatingHours", formData.operatingHours)
      localStorage.setItem("farmDescription", formData.farmDescription)
      localStorage.setItem("ownerName", formData.ownerName)
      localStorage.setItem("timezone", formData.timezone)

      setShowSuccess(true)
    } catch (error) {
      setError("Failed to save settings. Please try again.")
    }

    setIsSaving(false)
  }

  const handleInputChange = (field: string, value: string) => {
    setFormData((prev) => ({
      ...prev,
      [field]: value,
    }))
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
        <DashboardSidebar onLogout={handleLogout} />
        
        <div className="flex-1 flex flex-col">
          <DashboardHeader />
          
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
            <div className="space-y-6">
              {/* Page Header */}
              <PageHeader 
                title="Farm Settings"
                subtitle="Manage your farm configuration and preferences"
                action={
                  <div className="flex gap-2">
                    <Button onClick={loadSettings} disabled={isSaving} className="bg-red-600 hover:bg-red-700 text-white">
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
                          Save Changes
                        </>
                      )}
                    </Button>
                  </div>
                }
              />

              {/* Error Alert */}
              {error && (
                <Alert variant="destructive" className="mb-6">
                  <AlertDescription>{error}</AlertDescription>
                </Alert>
              )}

              <div className="space-y-4">
                {/* Farm Details */}
                <InfoSection title="Farm details" collapsible={false}>
                  {isEditing ? (
                    <div className="space-y-4 py-2">
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">Farm name</Label>
                          <Input
                            value={formData.farmName}
                            onChange={(e) => handleInputChange("farmName", e.target.value)}
                            placeholder="Enter your farm name"
                            disabled={isSaving}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">Owner / Manager name</Label>
                          <Input
                            value={formData.ownerName}
                            onChange={(e) => handleInputChange("ownerName", e.target.value)}
                            placeholder="Enter owner or manager name"
                            disabled={isSaving}
                          />
                        </div>
                      </div>
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">Farm location</Label>
                          <Input
                            value={formData.farmLocation}
                            onChange={(e) => handleInputChange("farmLocation", e.target.value)}
                            placeholder="Enter farm location"
                            disabled={isSaving}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label className="text-sm text-slate-600">Farm type</Label>
                          <Select value={formData.farmType} onValueChange={(v) => handleInputChange("farmType", v)} disabled={isSaving}>
                            <SelectTrigger>
                              <SelectValue placeholder="Select farm type" />
                            </SelectTrigger>
                            <SelectContent>
                              <SelectItem value="Layers">Layers (Egg Production)</SelectItem>
                              <SelectItem value="Broilers">Broilers (Meat Production)</SelectItem>
                              <SelectItem value="Mixed">Mixed (Layers & Broilers)</SelectItem>
                              <SelectItem value="Hatchery">Hatchery</SelectItem>
                              <SelectItem value="Breeders">Breeders</SelectItem>
                              <SelectItem value="Other">Other</SelectItem>
                            </SelectContent>
                          </Select>
                        </div>
                      </div>
                      <div className="space-y-2">
                        <Label className="text-sm text-slate-600">Farm description</Label>
                        <Textarea
                          value={formData.farmDescription}
                          onChange={(e) => handleInputChange("farmDescription", e.target.value)}
                          placeholder="Brief description of your farm..."
                          rows={2}
                          disabled={isSaving}
                        />
                      </div>
                    </div>
                  ) : (
                    <>
                      <InfoRow label="Farm name" value={formData.farmName} icon={<Building2 className="w-4 h-4" />} />
                      <InfoRow label="Owner / Manager" value={formData.ownerName || "Not set"} icon={<Users className="w-4 h-4" />} />
                      <InfoRow label="Location" value={formData.farmLocation} icon={<MapPin className="w-4 h-4" />} />
                      <InfoRow label="Farm type" value={formData.farmType || "Not set"} icon={<Building2 className="w-4 h-4" />} />
                      {formData.farmDescription && (
                        <InfoRow label="Description" value={formData.farmDescription} icon={<Building2 className="w-4 h-4" />} />
                      )}
                    </>
                  )}
                </InfoSection>

                {/* Contact Information */}
                <InfoSection title="Contact information" collapsible={false}>
                  {isEditing ? (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4 py-2">
                      <div className="space-y-2">
                        <Label className="text-sm text-slate-600">Phone number</Label>
                        <Input
                          value={formData.farmPhone}
                          onChange={(e) => handleInputChange("farmPhone", e.target.value)}
                          placeholder="+233 XX XXX XXXX"
                          disabled={isSaving}
                        />
                      </div>
                      <div className="space-y-2">
                        <Label className="text-sm text-slate-600">Email address</Label>
                        <Input
                          type="email"
                          value={formData.farmEmail}
                          onChange={(e) => handleInputChange("farmEmail", e.target.value)}
                          placeholder="farm@example.com"
                          disabled={isSaving}
                        />
                      </div>
                    </div>
                  ) : (
                    <>
                      <InfoRow label="Phone" value={formData.farmPhone || "Not set"} icon={<Phone className="w-4 h-4" />} />
                      <InfoRow label="Email" value={formData.farmEmail || "Not set"} icon={<Mail className="w-4 h-4" />} />
                    </>
                  )}
                </InfoSection>

                {/* Operational Settings */}
                <InfoSection title="Operational settings" collapsible={false}>
                  {isEditing ? (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4 py-2">
                      <div className="space-y-2">
                        <Label className="text-sm text-slate-600">Total bird capacity</Label>
                        <Input
                          type="number"
                          min="0"
                          value={formData.totalCapacity}
                          onChange={(e) => handleInputChange("totalCapacity", e.target.value)}
                          placeholder="e.g., 5000"
                          disabled={isSaving}
                        />
                      </div>
                      <div className="space-y-2">
                        <Label className="text-sm text-slate-600">Operating hours</Label>
                        <Input
                          value={formData.operatingHours}
                          onChange={(e) => handleInputChange("operatingHours", e.target.value)}
                          placeholder="e.g., 6:00 AM - 6:00 PM"
                          disabled={isSaving}
                        />
                      </div>
                    </div>
                  ) : (
                    <>
                      <InfoRow label="Total capacity" value={formData.totalCapacity ? `${Number(formData.totalCapacity).toLocaleString()} birds` : "Not set"} icon={<Users className="w-4 h-4" />} />
                      <InfoRow label="Operating hours" value={formData.operatingHours || "Not set"} icon={<Clock className="w-4 h-4" />} />
                    </>
                  )}
                </InfoSection>

                {/* Regional Settings */}
                <InfoSection title="Regional settings" collapsible={false}>
                  {isEditing ? (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4 py-2">
                      <div className="space-y-2">
                        <Label className="text-sm text-slate-600">Currency</Label>
                        <Input
                          value={formData.currency}
                          onChange={(e) => handleInputChange("currency", e.target.value.toUpperCase())}
                          placeholder="GHS"
                          maxLength={3}
                          disabled={isSaving}
                        />
                        <p className="text-xs text-slate-500">
                          3-letter currency code (USD, EUR, GBP, GHS, KES, NGN)
                        </p>
                      </div>
                      <div className="space-y-2">
                        <Label className="text-sm text-slate-600">Timezone</Label>
                        <Select value={formData.timezone} onValueChange={(v) => handleInputChange("timezone", v)} disabled={isSaving}>
                          <SelectTrigger>
                            <SelectValue placeholder="Select timezone" />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="Africa/Accra">Africa/Accra (GMT+0)</SelectItem>
                            <SelectItem value="Africa/Lagos">Africa/Lagos (WAT, GMT+1)</SelectItem>
                            <SelectItem value="Africa/Nairobi">Africa/Nairobi (EAT, GMT+3)</SelectItem>
                            <SelectItem value="Africa/Johannesburg">Africa/Johannesburg (SAST, GMT+2)</SelectItem>
                            <SelectItem value="America/New_York">America/New_York (EST, GMT-5)</SelectItem>
                            <SelectItem value="Europe/London">Europe/London (GMT+0)</SelectItem>
                            <SelectItem value="Asia/Dubai">Asia/Dubai (GST, GMT+4)</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                    </div>
                  ) : (
                    <>
                      <InfoRow label="Currency" value={formData.currency || "GHS"} icon={<DollarSign className="w-4 h-4" />} />
                      <InfoRow label="Timezone" value={formData.timezone || "Not set"} icon={<Globe className="w-4 h-4" />} />
                    </>
                  )}
                </InfoSection>
              </div>
            </div>
          </main>
        </div>
      </div>

      {showSuccess && (
        <SuccessModal
          title="Settings Saved!"
          message="Your farm settings have been updated successfully"
          onClose={() => setShowSuccess(false)}
          buttonText="Continue"
        />
      )}
    </>
  )
}
