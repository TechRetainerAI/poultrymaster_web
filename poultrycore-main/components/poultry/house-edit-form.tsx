"use client"

// Edit one house/pen: the same fields as the Houses page's Edit House dialog.
// Used by the popup opened from Initial Farm Setup's "what this setup created".

import { useEffect, useState } from "react"
import { Loader2, Save } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { useToast } from "@/hooks/use-toast"
import { getHouse, updateHouse } from "@/lib/api/house"
import { getUserContext } from "@/lib/utils/user-context"

export function HouseEditForm({ houseId, onSaved, onCancel }: {
  houseId: number
  onSaved?: () => void
  onCancel?: () => void
}) {
  const { toast } = useToast()
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  const [name, setName] = useState("")
  const [capacity, setCapacity] = useState("")
  const [location, setLocation] = useState("")

  useEffect(() => {
    void (async () => {
      const { userId, farmId } = getUserContext()
      if (!userId || !farmId) { setError("Farm or user not found"); setLoading(false); return }
      const res = await getHouse(houseId, userId, farmId)
      if (res.success && res.data) {
        const h: any = res.data
        setName(h.name || h.houseName || "")
        setCapacity(h.capacity != null ? String(h.capacity) : "")
        setLocation(h.location || "")
      } else setError(res.message || "Failed to load the house")
      setLoading(false)
    })()
  }, [houseId])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (!name.trim()) { setError("Give this house a name."); return }
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) { setError("Farm or user not found"); return }
    setSaving(true); setError("")
    const res = await updateHouse(houseId, {
      userId, farmId, name: name.trim(), capacity: capacity ? parseInt(capacity) : null, location: location || null,
    })
    setSaving(false)
    if (res.success) { toast({ title: "House updated" }); onSaved?.() }
    else setError(res.message || "Failed to update the house")
  }

  if (loading) return <div className="flex items-center gap-2 p-4 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>

  return (
    <form onSubmit={submit} className="space-y-5">
      {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">House Details</div>
        <div className="grid grid-cols-1 gap-4 bg-white p-4 md:grid-cols-3">
          <div className="space-y-2">
            <Label htmlFor="house-name">House Name *</Label>
            <Input id="house-name" value={name} onChange={(e) => setName(e.target.value)} disabled={saving} required placeholder="House A" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="house-capacity">Capacity (birds)</Label>
            <NumberInput id="house-capacity" min="0" value={capacity} onChange={(e) => setCapacity(e.target.value)} disabled={saving} placeholder="1000" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="house-location">Location</Label>
            <Input id="house-location" value={location} onChange={(e) => setLocation(e.target.value)} disabled={saving} placeholder="North Wing" />
          </div>
        </div>
      </div>
      <div className="flex justify-end gap-3">
        <Button type="button" disabled={saving} onClick={() => onCancel?.()} className="min-w-[120px] bg-red-600 text-white hover:bg-red-700">Cancel</Button>
        <Button type="submit" disabled={saving} className="min-w-[160px]">
          {saving ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" />Updating...</> : <><Save className="mr-2 h-4 w-4" />Update House</>}
        </Button>
      </div>
    </form>
  )
}
