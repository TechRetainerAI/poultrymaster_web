"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Settings, CheckCircle2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  type BusinessCategory,
  type GenericCompanyProfile,
  getBusinessCategories,
  getProfile,
  setupProfile,
} from "@/lib/api/generic"

export default function GenericSetupPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [profile, setProfile] = useState<GenericCompanyProfile | null>(null)
  const [categories, setCategories] = useState<BusinessCategory[]>([])

  const [form, setForm] = useState({
    businessCategoryId: "",
    businessDescription: "",
    defaultCurrency: "GHC",
    openingCashBalance: "0",
    businessStartDate: "",
    mainLocation: "",
    ownerName: "",
    phoneNumber: "",
    notes: "",
  })

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") {
      router.replace("/dashboard")
      return
    }
    let cancelled = false
    ;(async () => {
      try {
        const [cats, p] = await Promise.all([getBusinessCategories(), getProfile()])
        if (cancelled) return
        setCategories(cats)
        if (p) {
          setProfile(p)
          setForm({
            businessCategoryId: p.businessCategoryId?.toString() ?? "",
            businessDescription: p.businessDescription ?? "",
            defaultCurrency: p.defaultCurrency ?? "GHC",
            openingCashBalance: (p.openingCashBalance ?? 0).toString(),
            businessStartDate: p.businessStartDate?.slice(0, 10) ?? "",
            mainLocation: p.mainLocation ?? "",
            ownerName: p.ownerName ?? "",
            phoneNumber: p.phoneNumber ?? "",
            notes: p.notes ?? "",
          })
        }
      } catch (e: any) {
        toast({ title: "Could not load setup data", description: e?.message ?? String(e), variant: "destructive" })
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router, toast])

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    try {
      const updated = await setupProfile({
        businessCategoryId: form.businessCategoryId ? Number(form.businessCategoryId) : null,
        businessDescription: form.businessDescription || null,
        defaultCurrency: form.defaultCurrency || "GHC",
        openingCashBalance: Number(form.openingCashBalance) || 0,
        businessStartDate: form.businessStartDate || null,
        mainLocation: form.mainLocation || null,
        ownerName: form.ownerName || null,
        phoneNumber: form.phoneNumber || null,
        notes: form.notes || null,
      })
      if (updated) {
        setProfile(updated)
        toast({
          title: profile ? "Profile updated" : "Generic Company set up",
          description: "Default categories, cash accounts and lookups have been seeded.",
        })
        if (!profile) router.push("/generic-dashboard")
      }
    } catch (err: any) {
      toast({ title: "Could not save", description: err?.message ?? String(err), variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-6">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Settings className="h-6 w-6 text-emerald-600" />
              {profile ? "Business profile" : "Set up your business"}
            </h1>
            <p className="text-sm text-slate-500">
              {profile
                ? "Update your profile. Default lookups stay as they are; this form does not re-seed."
                : "Pick a business category and basic details — we'll seed default expense categories, cash accounts, customer/supplier types, and payment methods."}
            </p>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : (
            <Card className="max-w-3xl">
              <CardHeader>
                <CardTitle>Profile</CardTitle>
                <CardDescription>
                  {profile && (
                    <span className="inline-flex items-center gap-1 text-emerald-700">
                      <CheckCircle2 className="h-4 w-4" /> Already set up
                    </span>
                  )}
                </CardDescription>
              </CardHeader>
              <CardContent>
                <form onSubmit={onSubmit} className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div className="md:col-span-2">
                    <Label>Business category</Label>
                    <Select
                      value={form.businessCategoryId}
                      onValueChange={(v) => setForm((f) => ({ ...f, businessCategoryId: v }))}
                    >
                      <SelectTrigger><SelectValue placeholder="Choose…" /></SelectTrigger>
                      <SelectContent>
                        {categories.map((c) => (
                          <SelectItem key={c.businessCategoryId} value={c.businessCategoryId.toString()}>
                            {c.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-slate-500 mt-1">Restaurant, hotel, shop, salon, pharmacy, etc.</p>
                  </div>

                  <div>
                    <Label>Default currency</Label>
                    <Input
                      value={form.defaultCurrency}
                      maxLength={10}
                      onChange={(e) => setForm((f) => ({ ...f, defaultCurrency: e.target.value }))}
                    />
                  </div>

                  <div>
                    <Label>Business start date</Label>
                    <Input
                      type="date"
                      value={form.businessStartDate}
                      onChange={(e) => setForm((f) => ({ ...f, businessStartDate: e.target.value }))}
                    />
                  </div>

                  <div>
                    <Label>Owner name</Label>
                    <Input
                      value={form.ownerName}
                      maxLength={150}
                      onChange={(e) => setForm((f) => ({ ...f, ownerName: e.target.value }))}
                    />
                  </div>

                  <div>
                    <Label>Phone number</Label>
                    <Input
                      value={form.phoneNumber}
                      maxLength={50}
                      onChange={(e) => setForm((f) => ({ ...f, phoneNumber: e.target.value }))}
                    />
                  </div>

                  <div>
                    <Label>Main location</Label>
                    <Input
                      value={form.mainLocation}
                      maxLength={255}
                      onChange={(e) => setForm((f) => ({ ...f, mainLocation: e.target.value }))}
                    />
                  </div>

                  <div>
                    <Label>Opening cash ({form.defaultCurrency})</Label>
                    <Input
                      type="number"
                      step="0.01"
                      value={form.openingCashBalance}
                      onChange={(e) => setForm((f) => ({ ...f, openingCashBalance: e.target.value }))}
                    />
                    <p className="text-xs text-slate-500 mt-1">Seeds the &quot;Main Cash Box&quot; account.</p>
                  </div>

                  <div className="md:col-span-2">
                    <Label>Business description</Label>
                    <Textarea
                      rows={2}
                      maxLength={500}
                      value={form.businessDescription}
                      onChange={(e) => setForm((f) => ({ ...f, businessDescription: e.target.value }))}
                    />
                  </div>

                  <div className="md:col-span-2">
                    <Label>Notes</Label>
                    <Textarea
                      rows={2}
                      maxLength={1000}
                      value={form.notes}
                      onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))}
                    />
                  </div>

                  <div className="md:col-span-2 flex justify-end gap-2 pt-2">
                    <Button type="button" variant="outline" onClick={() => router.push("/generic-dashboard")}>Cancel</Button>
                    <Button type="submit" disabled={saving}>
                      {saving ? <Loader2 className="h-4 w-4 animate-spin mr-2" /> : null}
                      {profile ? "Save changes" : "Set up & continue"}
                    </Button>
                  </div>
                </form>
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}
