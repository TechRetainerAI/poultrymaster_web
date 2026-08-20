"use client"

// Doc 3 §8: Organization Profile — edit the owner/organization-level details
// (distinct from company setup). Stored on the owner's account.
// Extracted from the page so Business Setup can render it inline in a tab.
import { useEffect, useState } from "react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { ORG_CURRENCIES } from "@/lib/currency"
import { Loader2, Copy, Check } from "lucide-react"
import { setOrganizationCode as apiSetOrgCode, getOrganizationProfile, updateOrganizationProfile } from "@/lib/api/admin"
import { useToast } from "@/hooks/use-toast"
import { useAuthStore } from "@/lib/store/auth-store"

export function OrganizationProfilePanel({ showHeading = true }: { showHeading?: boolean }) {
  const { toast } = useToast()
  const user = useAuthStore((s) => s.user)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [orgCode, setOrgCode] = useState("")
  const [copied, setCopied] = useState(false)
  // When no org code exists, the owner can enter one (validated + unique).
  const [codeInput, setCodeInput] = useState("")
  const [savingCode, setSavingCode] = useState(false)
  // Changing an existing code is deliberate: click "Update", then type the new one.
  const [editingCode, setEditingCode] = useState(false)
  const [form, setForm] = useState({ businessOfficeName: "", firstName: "", lastName: "", email: "", phoneNumber: "", businessOfficeCurrency: "", businessOfficeCountry: "" })

  useEffect(() => {
    (async () => {
      try {
        // JWT-keyed read — resolves the authenticated owner on the backend, so
        // it always returns their own name/contact + business-office fields.
        const res = await getOrganizationProfile()
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
        // Prefer the code from the profile; fall back to the value stashed at
        // login (localStorage "myOrgCode") and the auth store.
        let code = (d.organizationCode || d.OrganizationCode || "").toString()
        if (!code && typeof window !== "undefined") code = localStorage.getItem("myOrgCode") || ""
        if (!code) code = ((user as any)?.organizationCode || "").toString()
        setOrgCode(code.toUpperCase())
        if (!res.success && res.message) toast({ title: "Could not load organization profile", description: res.message, variant: "destructive" })
      } catch (e: any) {
        toast({ title: "Could not load organization profile", description: e?.message, variant: "destructive" })
      } finally { setLoading(false) }
    })()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function save() {
    setSaving(true)
    try {
      const res = await updateOrganizationProfile({
        firstName: form.firstName,
        lastName: form.lastName,
        phoneNumber: form.phoneNumber,
        businessOfficeName: form.businessOfficeName,
        businessOfficeCurrency: form.businessOfficeCurrency,
        businessOfficeCountry: form.businessOfficeCountry,
      })
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
      setOrgCode(saved); setCodeInput(""); setEditingCode(false)
      try { localStorage.setItem("myOrgCode", saved) } catch {}
      toast({ title: "Organization code updated", description: saved })
    } catch (e: any) {
      toast({ title: "Couldn't save code", description: e?.message, variant: "destructive" })
    } finally { setSavingCode(false) }
  }

  return (
    <div className="space-y-6">
      {showHeading && (
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Organization Profile</h1>
          <p className="text-slate-600">Your organization/owner details. This is separate from each company&apos;s own setup.</p>
        </div>
      )}
      {loading ? <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div> : (
        <Card><CardContent className="p-6 space-y-4">
          {/* Organization code — the code employees enter at login to join this
              organization. Editing is deliberate: click Update, then type the new code. */}
          <div className="rounded-xl border border-orange-200 bg-orange-50/60 p-4">
            <div className="flex items-center justify-between gap-3">
              <div className="min-w-0">
                <div className="text-xs font-semibold uppercase tracking-wide text-orange-700">Organization code</div>
                {orgCode && !editingCode && <div className="mt-1 font-mono text-xl font-bold tracking-[0.2em] text-slate-900">{orgCode}</div>}
                <div className="text-xs text-slate-500 mt-1">Share this with staff — they enter it at login to join your organization.{!orgCode && !editingCode && " No code yet — click Set code to create one (4–30 letters/numbers)."}</div>
              </div>
              {!editingCode && (
                <div className="flex items-center gap-2 shrink-0">
                  {orgCode && (
                    <Button type="button" variant="outline" size="sm" onClick={copyCode}>
                      {copied ? <><Check className="h-4 w-4 mr-1 text-emerald-600" /> Copied</> : <><Copy className="h-4 w-4 mr-1" /> Copy</>}
                    </Button>
                  )}
                  <Button type="button" size="sm" onClick={() => { setCodeInput(""); setEditingCode(true) }}>{orgCode ? "Update" : "Set code"}</Button>
                </div>
              )}
            </div>
            {editingCode && (
              <div className="mt-3 space-y-2">
                {orgCode && <div className="text-xs text-amber-700">Enter a new code. Staff will need the new code to join — the current one ({orgCode}) stops working.</div>}
                <div className="flex flex-col sm:flex-row gap-2 sm:items-center">
                  <Input value={codeInput} autoFocus onChange={(e) => setCodeInput(e.target.value.toUpperCase())} placeholder="Enter new code" className="font-mono uppercase w-full sm:w-56" maxLength={30} />
                  <Button type="button" size="sm" onClick={saveCode} disabled={savingCode} className="shrink-0">{savingCode ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save new code"}</Button>
                  <Button type="button" variant="outline" size="sm" onClick={() => { setEditingCode(false); setCodeInput("") }} className="shrink-0">Cancel</Button>
                </div>
              </div>
            )}
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div className="sm:col-span-2 lg:col-span-3 space-y-1"><Label>Organization / Business Office name</Label><Input value={form.businessOfficeName} onChange={(e) => setForm({ ...form, businessOfficeName: e.target.value })} /></div>
            <div className="space-y-1"><Label>Owner first name</Label><Input value={form.firstName} onChange={(e) => setForm({ ...form, firstName: e.target.value })} /></div>
            <div className="space-y-1"><Label>Owner last name</Label><Input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} /></div>
            <div className="space-y-1"><Label>Email</Label><Input type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
            <div className="space-y-1"><Label>Phone</Label><Input value={form.phoneNumber} onChange={(e) => setForm({ ...form, phoneNumber: e.target.value })} /></div>
            {/* Was a free-text box, which let any string through and left the
                Business Office with no reliable symbol to print. Now a fixed
                list — the stored value is always a code (GHS / USD). A legacy
                value outside the list shows the placeholder until re-picked. */}
            <div className="space-y-1">
              <Label>Default currency</Label>
              <Select
                value={ORG_CURRENCIES.some((c) => c.code === form.businessOfficeCurrency) ? form.businessOfficeCurrency : ""}
                onValueChange={(v) => setForm({ ...form, businessOfficeCurrency: v })}
              >
                <SelectTrigger><SelectValue placeholder="Select currency" /></SelectTrigger>
                <SelectContent>
                  {ORG_CURRENCIES.map((c) => (
                    <SelectItem key={c.code} value={c.code}>{c.symbol} — {c.label} ({c.code})</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-slate-500">Used where no single company is in view — e.g. the Business Office company cards.</p>
            </div>
            <div className="space-y-1"><Label>Country</Label><Input value={form.businessOfficeCountry} onChange={(e) => setForm({ ...form, businessOfficeCountry: e.target.value })} placeholder="e.g. Ghana" /></div>
          </div>
          <div className="flex justify-end"><Button onClick={save} disabled={saving}>{saving ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save changes"}</Button></div>
        </CardContent></Card>
      )}
    </div>
  )
}
