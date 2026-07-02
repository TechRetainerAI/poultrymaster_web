"use client"

// Doc 3 §8: Organization Profile — edit the owner/organization-level details
// (distinct from company setup). Stored on the owner's account.
import { useEffect, useState } from "react"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Loader2 } from "lucide-react"
import { getUserProfile, updateUserProfile } from "@/lib/api/user-profile"
import { useToast } from "@/hooks/use-toast"

export default function OrganizationProfilePage() {
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [orgCode, setOrgCode] = useState("")
  const [form, setForm] = useState({ businessOfficeName: "", firstName: "", lastName: "", email: "", phoneNumber: "", businessOfficeCurrency: "", businessOfficeCountry: "" })

  useEffect(() => {
    (async () => {
      try {
        const username = (typeof window !== "undefined" && (localStorage.getItem("username") || localStorage.getItem("userName"))) || ""
        if (!username) { setLoading(false); return }
        const res = await getUserProfile(username)
        const d: any = res?.data || {}
        setForm({
          businessOfficeName: d.businessOfficeName || d.BusinessOfficeName || "",
          firstName: d.firstName || d.FirstName || "",
          lastName: d.lastName || d.LastName || "",
          email: d.email || d.Email || "",
          phoneNumber: d.phoneNumber || d.PhoneNumber || "",
          businessOfficeCurrency: d.businessOfficeCurrency || d.BusinessOfficeCurrency || "",
          businessOfficeCountry: d.businessOfficeCountry || d.BusinessOfficeCountry || "",
        })
        setOrgCode((d.organizationCode || d.OrganizationCode || "").toString().toUpperCase())
      } catch (e: any) {
        toast({ title: "Could not load organization profile", description: e?.message, variant: "destructive" })
      } finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function save() {
    setSaving(true)
    try {
      const res = await updateUserProfile(form)
      if (res.success) {
        if (form.businessOfficeName) try { localStorage.setItem("businessOfficeName", form.businessOfficeName) } catch {}
        toast({ title: "Organization profile saved" })
      } else toast({ title: "Save failed", description: res.message, variant: "destructive" })
    } catch (e: any) { toast({ title: "Save failed", description: e?.message, variant: "destructive" }) }
    finally { setSaving(false) }
  }

  return (
    <BusinessOfficeShell active="org">
      <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Organization Profile</h1>
          <p className="text-slate-600">Your organization/owner details. This is separate from each company's own setup.</p>
        </div>
        {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div> : (
          <Card className="max-w-2xl"><CardContent className="p-6 space-y-4">
            {orgCode && <div className="text-sm text-slate-500">Organization code: <span className="font-mono font-semibold text-slate-700">{orgCode}</span></div>}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="sm:col-span-2 space-y-1"><Label>Organization / Business Office name</Label><Input value={form.businessOfficeName} onChange={(e) => setForm({ ...form, businessOfficeName: e.target.value })} /></div>
              <div className="space-y-1"><Label>Owner first name</Label><Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} /></div>
              <div className="space-y-1"><Label>Owner last name</Label><Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} /></div>
              <div className="space-y-1"><Label>Email</Label><Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
              <div className="space-y-1"><Label>Phone</Label><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
              <div className="space-y-1"><Label>Default currency</Label><Input value={form.businessOfficeCurrency} onChange={(e) => setForm({ ...form, businessOfficeCurrency: e.target.value })} placeholder="e.g. GHS" /></div>
              <div className="space-y-1"><Label>Country</Label><Input value={form.businessOfficeCountry} onChange={(e) => setForm({ ...form, businessOfficeCountry: e.target.value })} placeholder="e.g. Ghana" /></div>
            </div>
            <div className="flex justify-end"><Button onClick={save} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save changes"}</Button></div>
          </CardContent></Card>
        )}
      </main>
    </BusinessOfficeShell>
  )
}
