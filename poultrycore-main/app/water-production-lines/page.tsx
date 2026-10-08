"use client"

// Water production lines — the OPERATIONAL scale water billing reads
// (customer-app spec 18/19, admin-app spec 5/7). The water company manages
// REAL production lines here; billing derives the count. Nobody types
// "billing line count = 3" anywhere.

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useToast } from "@/hooks/use-toast"
import { Loader2, Factory, ArrowLeft, Plus } from "lucide-react"
import { farmApiUrl, getAuthHeaders } from "@/lib/api/config"

interface Line {
  id: number
  name: string
  isActive: boolean
  notes?: string | null
  createdAt: string
}

export default function WaterProductionLinesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const [farmId, setFarmId] = useState<string | null>(null)
  const [lines, setLines] = useState<Line[]>([])
  const [loading, setLoading] = useState(true)
  const [name, setName] = useState("")
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    try { setFarmId(localStorage.getItem("farmId")) } catch { setFarmId(null) }
  }, [])

  const load = useCallback(async (f: string) => {
    setLoading(true)
    try {
      const res = await fetch(farmApiUrl(`/WaterProductionLines?farmId=${encodeURIComponent(f)}`), { headers: getAuthHeaders() })
      if (res.ok) setLines(await res.json())
    } finally { setLoading(false) }
  }, [])
  useEffect(() => { if (farmId) void load(farmId) }, [farmId, load])

  const add = async () => {
    if (!farmId || !name.trim()) return
    setBusy(true)
    try {
      const userId = localStorage.getItem("userId") ?? undefined
      const res = await fetch(farmApiUrl(`/WaterProductionLines`), {
        method: "POST", headers: getAuthHeaders(),
        body: JSON.stringify({ farmId, name: name.trim(), userId }),
      })
      if (res.ok) { setName(""); toast({ title: "Production line added" }); void load(farmId) }
      else toast({ variant: "destructive", title: "Could not add line", description: await res.text() })
    } finally { setBusy(false) }
  }

  const toggle = async (l: Line) => {
    if (!farmId) return
    const res = await fetch(farmApiUrl(`/WaterProductionLines/${l.id}`), {
      method: "PUT", headers: getAuthHeaders(),
      body: JSON.stringify({ farmId, name: l.name, notes: l.notes, isActive: !l.isActive }),
    })
    if (res.ok) void load(farmId)
  }

  const activeCount = lines.filter((l) => l.isActive).length

  return (
    <div className="mx-auto max-w-3xl space-y-4 p-4 sm:p-6">
      <div className="flex items-center gap-3">
        <Button variant="ghost" size="icon" onClick={() => router.back()}><ArrowLeft className="h-4 w-4" /></Button>
        <div>
          <h1 className="text-xl font-bold text-slate-900">Production lines</h1>
          <p className="text-sm text-slate-600">
            The real production lines this water company runs. Your VisibilityCore plan scales with the active count.
          </p>
        </div>
      </div>

      {!farmId ? (
        <Alert><AlertDescription>Open a water company first, then come back to configure its production lines.</AlertDescription></Alert>
      ) : (
        <Card>
          <CardHeader className="border-b border-slate-100 py-4">
            <div className="flex items-center justify-between">
              <CardTitle className="flex items-center gap-2 text-base">
                <Factory className="h-4 w-4 text-sky-600" /> Active production lines
              </CardTitle>
              <span className="rounded-full bg-sky-50 px-2.5 py-1 text-xs font-medium tabular-nums text-sky-700 ring-1 ring-inset ring-sky-600/10">
                {activeCount} active
              </span>
            </div>
          </CardHeader>
          <CardContent className="space-y-3 pt-4">
            <div className="flex gap-2">
              <Input placeholder="Line name — e.g. Sachet Line 1" value={name}
                onChange={(e) => setName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && void add()} />
              <Button onClick={() => void add()} disabled={busy || !name.trim()}>
                {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="mr-1 h-4 w-4" />} Add line
              </Button>
            </div>
            {loading ? (
              <div className="flex justify-center py-8"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
            ) : lines.length === 0 ? (
              <p className="py-6 text-center text-sm text-slate-500">
                No production lines yet. Add the lines you actually run — billing reads this count.
              </p>
            ) : (
              <div className="divide-y divide-slate-100">
                {lines.map((l) => (
                  <div key={l.id} className="flex items-center justify-between py-2.5">
                    <div>
                      <p className={`text-sm font-medium ${l.isActive ? "text-slate-900" : "text-slate-400 line-through"}`}>{l.name}</p>
                      <p className="text-xs text-slate-400">Added {new Date(l.createdAt).toLocaleDateString()}</p>
                    </div>
                    <Button size="sm" variant="outline" onClick={() => void toggle(l)}>
                      {l.isActive ? "Deactivate" : "Reactivate"}
                    </Button>
                  </div>
                ))}
              </div>
            )}
            <p className="text-xs leading-relaxed text-slate-500">
              Deactivating a line lowers the active count your plan is based on from the next billing evaluation.
              Already-issued invoices never change.
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
