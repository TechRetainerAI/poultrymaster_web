"use client"

// =============================================================================
// Egg Pick Time Settings (/business-office/egg-pick-settings)
//
// Farms pick eggs at different times of day. Production records are labelled
// generically (1st/2nd/3rd/4th Pick); this page configures the time each pick
// represents (display/reporting only) and whether the 4th pick is enabled for
// entry. Backed by FarmProductionSettings (migration 153).
// =============================================================================

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { ArrowLeft, Clock, Loader2, Save } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import {
  DEFAULT_PICK_SETTINGS,
  getFarmProductionSettings,
  saveFarmProductionSettings,
  formatPickTime,
  type FarmProductionSettings,
} from "@/lib/api/farm-production-settings"

export default function EggPickSettingsPage() {
  const router = useRouter()
  const logout = useLogout()
  const { toast } = useToast()

  const [form, setForm] = useState<FarmProductionSettings>(DEFAULT_PICK_SETTINGS)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    let cancelled = false
    getFarmProductionSettings()
      .then((s) => { if (!cancelled) setForm(s) })
      .catch(() => { /* keep defaults */ })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [])

  const save = async () => {
    setSaving(true)
    const res = await saveFarmProductionSettings(form)
    if (res.success) {
      if (res.data) setForm(res.data)
      toast({ title: "Egg pick settings saved" })
    } else {
      toast({ title: "Save failed", description: res.message || "Please try again.", variant: "destructive" })
    }
    setSaving(false)
  }

  const rows: { key: keyof FarmProductionSettings; label: string }[] = [
    { key: "firstPickTime", label: "1st Pick Time" },
    { key: "secondPickTime", label: "2nd Pick Time" },
    { key: "thirdPickTime", label: "3rd Pick Time" },
    { key: "fourthPickTime", label: "4th Pick Time" },
  ]

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4">
          <div className="space-y-6 max-w-2xl">
            {/* Header */}
            <div className="flex items-start gap-3">
              <Button variant="ghost" size="icon" onClick={() => router.push("/business-office/setup")} className="shrink-0">
                <ArrowLeft className="w-5 h-5" />
              </Button>
              <div className="w-10 h-10 shrink-0 bg-emerald-100 rounded-lg flex items-center justify-center">
                <Clock className="w-5 h-5 text-emerald-600" />
              </div>
              <div className="min-w-0">
                <h1 className="text-2xl font-bold text-slate-900">Egg Pick Time Settings</h1>
                <p className="text-sm text-slate-600">
                  Configure the time of day each egg pick represents for this farm. These times are used for display and
                  reporting, while production records are labelled 1st Pick, 2nd Pick, 3rd Pick, and 4th Pick.
                </p>
              </div>
            </div>

            <Card>
              <CardContent className="p-4 sm:p-6 space-y-5">
                {loading ? (
                  <div className="flex items-center gap-2 text-slate-500 py-8">
                    <Loader2 className="w-4 h-4 animate-spin" /> Loading…
                  </div>
                ) : (
                  <>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      {rows.map((r) => (
                        <div key={r.key} className="space-y-2">
                          <Label className="text-sm font-medium text-slate-700">{r.label}</Label>
                          <Input
                            type="time"
                            value={(form[r.key] as string) || ""}
                            onChange={(e) => setForm({ ...form, [r.key]: e.target.value })}
                            disabled={saving}
                          />
                          <p className="text-xs text-slate-400">
                            {formatPickTime(form[r.key] as string) || "Not set — falls back to the default."}
                          </p>
                        </div>
                      ))}
                    </div>

                    <div className="flex items-center gap-3 rounded-lg border border-slate-200 bg-slate-50 p-3">
                      <Switch
                        checked={form.enableFourthPick}
                        onCheckedChange={(checked) => setForm({ ...form, enableFourthPick: checked })}
                        disabled={saving}
                      />
                      <div className="min-w-0">
                        <Label className="text-sm font-medium text-slate-700">Enable 4th Pick</Label>
                        <p className="text-xs text-slate-500">
                          When off, the 4th Pick input is hidden on entry forms. Records and reports still support it, so
                          you can turn it on any time without losing data.
                        </p>
                      </div>
                    </div>

                    <div className="flex justify-end gap-3 pt-2">
                      <Button variant="outline" onClick={() => router.push("/business-office/setup")} disabled={saving}>
                        Cancel
                      </Button>
                      <Button onClick={save} disabled={saving} className="min-w-[140px]">
                        {saving ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving…</> : <><Save className="w-4 h-4 mr-2" />Save settings</>}
                      </Button>
                    </div>
                  </>
                )}
              </CardContent>
            </Card>
          </div>
        </main>
      </div>
    </div>
  )
}
