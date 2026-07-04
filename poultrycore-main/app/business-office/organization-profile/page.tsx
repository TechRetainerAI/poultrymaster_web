"use client"

// Doc 3 §8: Organization Profile — edit the owner/organization-level details
// (distinct from company setup). Stored on the owner's account.
import { useEffect, useState } from "react"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Loader2, Copy, Check } from "lucide-react"
import { getUserProfile, updateUserProfile } from "@/lib/api/user-profile"
import { setOrganizationCode as apiSetOrgCode } from "@/lib/api/admin"
import { useToast } from "@/hooks/use-toast"
import { useAuthStore } from "@/lib/store/auth-store"

export default function OrganizationProfilePage() {
  const { toast } = useToast()
  const user = useAuthStore((s) => s.user)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [orgCode, setOrgCode] = useState("")
  const [copied, setCopied] = useState(false)
  // When no org code exists, the owner can enter one (validated + unique).
  const [codeInput, setCodeInput] = useState("")
  const [savingCode, setSavingCode] = useState(false)
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
        // Org code rarely comes back on the profile payload — fall back to the
        // value stashed at login (localStorage "myOrgCode") and the auth store.
        let code = (d.organizationCode || d.OrganizationCode || "").toString()
        if (!code && typeof window !== "undefined") code = localStorage.getItem("myOrgCode") || ""
        if (!code) code = ((user as any)?.organizationCode || "").toString()
        setOrgCode(code.toUpperCase())
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

  async function copyCode() {
    if (!orgCode) return
    try { await navigator.clipboard.writeText(orgCode); setCopied(true); setTimeout(() => setCopied(false), 1500) } catch {}
  }

  async function saveCode() {
    const code = codeInput.trim().toUpperCase()
    if (code.length < 4) return toast({ title: "Code must be at least 4 characters", variant: "destructive" })
    setSavingCode(true)
    try {
      const res = await apiSetOrgCode(code)
      if (!res.success) { toast({ title: "Couldn't save code", description: res.message, variant: "destructive" }); return }
      const saved = (res.data?.organizationCode || code).toUpperCase()
      setOrgCode(saved); setCodeInput("")
      try { localStorage.setItem("myOrgCode", saved) } catch {}
      toast({ title: "Organization code saved", description: saved })
    } catch (e: any) {
      toast({ title: "Couldn't save code", description: e?.message, variant: "destructive" })
    } finally { setSavingCode(false) }
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
            {/* Organization code — the code employees enter at login to join this
                organization. Read-only; generated by the system. */}
            <div className="rounded-xl border border-orange-200 bg-orange-50/60 p-4 flex items-center justify-between gap-3">
              <div className="min-w-0">
                <div className="text-xs font-semibold uppercase tracking-wide text-orange-700">Organization code</div>
                {orgCode
                  ? <div className="mt-1 font-mono text-xl font-bold tracking-[0.2em] text-slate-900">{orgCode}</div>
                  : (
                    <div className="mt-2 flex flex-col sm:flex-row gap-2 sm:items-center">
                      <Input value={codeInput} onChange={(e) => setCodeInput(e.target.value.toUpperCase())} placeholder="e.g. GREATFARM01" className="font-mono uppercase w-full sm:w-56" maxLength={30} />
                      <Button type="button" size="sm" onClick={saveCode} disabled={savingCode} className="shrink-0">{savingCode ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save code"}</Button>
                    </div>
                  )}
                <div className="text-xs text-slate-500 mt-1">Share this with staff — they enter it at login to join your organization.{!orgCode && " No code yet — enter one above (4–30 letters/numbers)."}</div>
              </div>
              {orgCode && (
                <Button type="button" variant="outline" size="sm" onClick={copyCode} className="shrink-0">
                  {copied ? <><Check className="h-4 w-4 mr-1 text-emerald-600" /> Copied</> : <><Copy className="h-4 w-4 mr-1" /> Copy</>}
                </Button>
              )}
            </div>
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
