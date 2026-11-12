"use client"

// The Edit Flock form, shared by the /flocks/[id] page and the popup opened from
// Initial Farm Setup's "what this setup created" list. Moved out of the page
// unchanged; the page only adds the layout around it.

import { useEffect, useState } from "react"
import { BreedSelect } from "@/components/poultry/breed-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Loader2, Save, Users, Home } from "lucide-react"
import { getFlock, updateFlock, getFlockEditContext, type FlockEditContext, type FlockInput } from "@/lib/api/flock"
import { FlockHistoryPanel, openingDraftFrom, openingDraftToEdit, openingDraftWarnings, type OpeningHistoryDraft } from "@/components/poultry/flock-history-panel"
import { useToast } from "@/hooks/use-toast"
import { clearFlocksCache } from "@/lib/utils/flock-utils"
import { getHouses, type House } from "@/lib/api/house"
import { getFlockBatches, type FlockBatch } from "@/lib/api/flock-batch"
import { getUserContext } from "@/lib/utils/user-context"
import { FlockTreatmentHistory } from "@/components/production/flock-treatment-history"

export function FlockEditForm({
  flockId, onSaved, onCancel, showTreatments = true,
}: {
  flockId: string
  /** Called after a successful save. */
  onSaved?: () => void
  onCancel?: () => void
  /** The campaign treatment history under the form (the full page shows it). */
  showTreatments?: boolean
}) {
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  // 414: restored from posted records, not from the dialog that created it.
  const [editCtx, setEditCtx] = useState<FlockEditContext | null>(null)
  const [openingDraft, setOpeningDraft] = useState<OpeningHistoryDraft | null>(null)
  const { toast } = useToast()

  const [formData, setFormData] = useState<FlockInput>({
    farmId: "",
    userId: "",
    name: "",
    startDate: "",
    breed: "",
    quantity: 0,
    active: true,
    houseId: null,
    batchId: 0,
    inactivationReason: "",
    otherReason: "",
    notes: "",
  })

  const [houses, setHouses] = useState<House[]>([])
  const [housesLoading, setHousesLoading] = useState(true)
  const [flockBatches, setFlockBatches] = useState<FlockBatch[]>([])
  const [flockBatchesLoading, setFlockBatchesLoading] = useState(true)
  const [selectedFlockBatch, setSelectedFlockBatch] = useState<FlockBatch | null>(null)
  const [remainingBirds, setRemainingBirds] = useState<number | null>(null)

  useEffect(() => {
    load()
  }, [flockId])

  useEffect(() => {
    if (selectedFlockBatch) {
      setRemainingBirds(selectedFlockBatch.numberOfBirds - formData.quantity)
    } else {
      setRemainingBirds(null)
    }
  }, [formData.quantity, selectedFlockBatch])

  const load = async () => {
    const { farmId, userId } = getUserContext()
    
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      setLoading(false)
      return
    }

    const [flockRes, housesRes, flockBatchesRes, ctx] = await Promise.all([
      getFlock(parseInt(flockId), userId, farmId),
      getHouses(userId, farmId),
      getFlockBatches(userId, farmId),
      getFlockEditContext(parseInt(flockId), farmId),
    ])
    setEditCtx(ctx)
    setOpeningDraft(openingDraftFrom(ctx))

    if (housesRes.success && Array.isArray(housesRes.data)) setHouses(housesRes.data as House[])
    setHousesLoading(false)

    if (flockBatchesRes.success && Array.isArray(flockBatchesRes.data)) setFlockBatches(flockBatchesRes.data as FlockBatch[])
    setFlockBatchesLoading(false)

    if (flockRes.success && flockRes.data) {
      const flock = flockRes.data
      setFormData({
        farmId: flock.farmId ?? "",
        userId: flock.userId ?? "",
        name: flock.name ?? "",
        startDate: flock.startDate?.split('T')[0] ?? "",
        breed: flock.breed ?? "",
        quantity: flock.quantity ?? 0,
        active: flock.active ?? false,
        hasArrived: Boolean(flock.hasArrived),
        flockType: flock.flockType ?? null,
        houseId: flock.houseId ?? null,
        batchId: flock.batchId ?? 0,
        inactivationReason: flock.inactivationReason ?? "",
        otherReason: flock.otherReason ?? "",
        notes: flock.notes ?? "",
      })
      console.log("[v0] Loaded flock data - houseId:", flock.houseId, "batchId:", flock.batchId)
      const initialSelectedBatch = flockBatchesRes.data?.find(batch => batch.batchId === flock.batchId) || null
      setSelectedFlockBatch(initialSelectedBatch)
    } else {
      setError(flockRes.message || "Failed to load flock")
    }
    
    setLoading(false)
  }

  const handleInputChange = (field: keyof FlockInput, value: string | number | boolean | null) => {
    setFormData(prev => ({
      ...prev,
      [field]: value as any
    }))
  }

  const handleFlockBatchChange = (batchId: number | null) => {
    const selected = flockBatches.find(batch => batch.batchId === batchId) || null
    setSelectedFlockBatch(selected)
    handleInputChange("batchId", batchId || 0)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const { farmId, userId } = getUserContext()
    
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      return
    }

    if (!formData.name.trim() || !formData.startDate) {
      setError("Please fill in all required fields")
      return
    }

    if (!openingDraft && formData.quantity <= 0) {
      setError("Quantity must be greater than 0")
      return
    }

    // Out-of-proportion numbers are WARNINGS — the save still goes through.
    const localWarnings: string[] = [...openingDraftWarnings(editCtx, openingDraft)]
    const birdsOnForm = openingDraft
      ? Number(openingDraft.live || 0) + (editCtx?.quantityAdjustments ?? 0)
      : formData.quantity

    setSaving(true)
    setError("")

    const flockData: Partial<FlockInput> = {
      name: formData.name,
      startDate: formData.startDate + 'T00:00:00Z',
      breed: formData.breed,
      quantity: formData.quantity,
      active: formData.active,
      houseId: formData.houseId ?? null,
      batchId: formData.batchId ?? 0,
      farmId, // ensure backend receives FarmId
      userId, // ensure backend receives UserId
      inactivationReason: formData.inactivationReason,
      otherReason: formData.inactivationReason === 'other' ? formData.otherReason : '',
      notes: formData.notes,
      hasArrived: formData.hasArrived,
      flockType: formData.flockType || undefined,
      ...(openingDraft ? { openingHistory: openingDraftToEdit(openingDraft), quantity: birdsOnForm } : {}),
    }

    const result = await updateFlock(parseInt(flockId), flockData)

    if (result.success) {
      clearFlocksCache()
      const warnings = Array.from(new Set([...(result.warnings ?? []), ...localWarnings]))
      if (warnings.length > 0) {
        toast({ title: "Flock updated — please check", description: warnings.join(" "), duration: 12000 })
      } else {
        toast({ title: "Flock updated" })
      }
      setSaving(false)
      onSaved?.()
    } else {
      setError(result.message || "Failed to update flock")
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="rounded-xl border border-slate-200 overflow-hidden">
        <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock Information</div>
        <div className="p-6 bg-white">
          <div className="animate-pulse space-y-4">
            <div className="h-4 bg-slate-200 rounded w-1/3"></div>
            <div className="h-11 bg-slate-200 rounded"></div>
            <div className="h-4 bg-slate-200 rounded w-1/3"></div>
            <div className="h-11 bg-slate-200 rounded"></div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Error Alert */}
      {error && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {/* Form */}
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Section: Flock Information */}
        <div className="rounded-xl border border-slate-200 overflow-hidden">
          <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Flock Information</div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
            <div className="space-y-2">
              <Label htmlFor="batchId" className="text-sm font-medium text-slate-700">
                Assign to Flock Batch
              </Label>
              <div className="relative">
                <select
                  id="batchId"
                  className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  value={formData.batchId ?? ''}
                  onChange={(e) => handleFlockBatchChange(e.target.value ? parseInt(e.target.value) : null)}
                  disabled={saving || flockBatchesLoading}
                >
                  <option value="">No batch</option>
                  {flockBatches.map(batch => (
                    <option key={batch.batchId} value={batch.batchId}>{batch.batchName}</option>
                  ))}
                </select>
                <Users className="w-4 h-4 text-slate-400 absolute right-3 top-3" />
              </div>
              {selectedFlockBatch && (
                <p className="text-xs text-slate-500">
                  Available: {selectedFlockBatch.numberOfBirds} birds
                </p>
              )}
            </div>
        
            <div className="space-y-2">
              <Label htmlFor="name" className="text-sm font-medium text-slate-700">
                Name *
              </Label>
              <Input
                id="name"
                type="text"
                placeholder="e.g., Flock A - Rhode Island Reds"
                value={formData.name}
                onChange={(e) => handleInputChange("name", e.target.value)}
                required
                disabled={saving}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="breed" className="text-sm font-medium text-slate-700">
                Breed
              </Label>
              <BreedSelect
                value={formData.breed}
                known={flockBatches.map((b) => b.breed)}
                onChange={(breed) => handleInputChange("breed", breed)}
                disabled={saving}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="startDate" className="text-sm font-medium text-slate-700">
                Start Date *
              </Label>
              <Input
                id="startDate"
                type="date"
                value={formData.startDate}
                onChange={(e) => handleInputChange("startDate", e.target.value)}
                required
                disabled={saving}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="quantity" className="text-sm font-medium text-slate-700">
                Number of Birds *
              </Label>
              {openingDraft ? (
                <>
                  <NumberInput id="quantity" value={Number(openingDraft.live || 0) + (editCtx?.quantityAdjustments ?? 0)} disabled />
                  <p className="text-xs text-slate-500">Set by &quot;Current birds when registered&quot; in Bird history below.</p>
                </>
              ) : (
                <>
                  <NumberInput
                    id="quantity"
                    min="1"
                    placeholder="e.g., 100"
                    value={formData.quantity}
                    onChange={(e) => handleInputChange("quantity", parseInt(e.target.value) || 0)}
                    required
                    disabled={saving}
                  />
                  {(editCtx?.position?.productionrecordcount ?? 0) > 0 && (
                    <p className="text-xs text-slate-500">
                      Birds placed. Live birds now ({(editCtx?.position?.currentlivebirds ?? 0).toLocaleString()}) come from the latest production record.
                    </p>
                  )}
                </>
              )}
            </div>

            <div className="space-y-2">
              <Label htmlFor="houseId" className="text-sm font-medium text-slate-700">
                Assign to House
              </Label>
              <div className="relative">
                <select
                  id="houseId"
                  className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  value={formData.houseId ?? ''}
                  onChange={(e) => handleInputChange("houseId", e.target.value ? parseInt(e.target.value) : null)}
                  disabled={saving || housesLoading}
                >
                  <option value="">No house</option>
                  {houses.map((h) => (
                    <option key={h.houseId} value={h.houseId}>{(h as any).houseName || (h as any).name}</option>
                  ))}
                </select>
                <Home className="w-4 h-4 text-slate-400 absolute right-3 top-3" />
              </div>
            </div>
          </div>
        </div>

        {editCtx && (
          <FlockHistoryPanel ctx={editCtx} draft={openingDraft} onDraftChange={setOpeningDraft} disabled={saving} />
        )}

        {/* Section: Status & Notes */}
        <div className="rounded-xl border border-slate-200 overflow-hidden">
          <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Status &amp; Notes</div>
          <div className="p-4 bg-white space-y-4">
            <div className="flex items-center space-x-2">
              <Switch
                id="active"
                checked={formData.active}
                onCheckedChange={(checked) => handleInputChange("active", checked)}
                disabled={saving}
              />
              <Label htmlFor="active" className="text-sm font-medium text-slate-700">
                Active Flock
              </Label>
              <p className="text-xs text-slate-500 ml-2">
                (Uncheck if this flock is no longer active)
              </p>
            </div>

            {!formData.active && (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="inactivationReason" className="text-sm font-medium text-slate-700">
                    Reason for Inactivation
                  </Label>
                  <select
                    id="inactivationReason"
                    className="w-full h-10 rounded-md border border-slate-200 bg-white px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                    value={formData.inactivationReason}
                    onChange={(e) => handleInputChange("inactivationReason", e.target.value)}
                    disabled={saving}
                  >
                    <option value="">Select a reason</option>
                    <option value="all flock sold">All flock sold</option>
                    <option value="all flocks on the market">All flocks on the market</option>
                    <option value="disease outbreak">Disease outbreak</option>
                    <option value="end of production cycle">End of production cycle</option>
                    <option value="relocation">Relocation</option>
                    <option value="other">Other</option>
                  </select>
                </div>
                {formData.inactivationReason === "other" && (
                  <div className="space-y-2">
                    <Label htmlFor="otherReason" className="text-sm font-medium text-slate-700">
                      Other Reason
                    </Label>
                    <Input
                      id="otherReason"
                      type="text"
                      placeholder="Please specify the reason"
                      value={formData.otherReason}
                      onChange={(e) => handleInputChange("otherReason", e.target.value)}
                      disabled={saving}
                    />
                  </div>
                )}
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="notes" className="text-sm font-medium text-slate-700">
                Notes (Optional)
              </Label>
              <textarea
                id="notes"
                placeholder="Add any additional notes about the flock"
                value={formData.notes || ''}
                onChange={(e) => handleInputChange("notes", e.target.value)}
                className="w-full rounded-md border border-slate-200 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[80px]"
                disabled={saving}
              />
            </div>
          </div>
        </div>

        {/* Form Actions */}
        <div className="flex gap-3 justify-end pt-2">
          <Button
            type="button"
            disabled={saving}
            onClick={() => onCancel?.()}
            className="min-w-[120px] bg-red-600 hover:bg-red-700 text-white"
          >
            Cancel
          </Button>
          <Button
            type="submit"
            disabled={saving}
            className="min-w-[160px]"
          >
            {saving ? (
              <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Updating...</>
            ) : (
              <><Save className="w-4 h-4 mr-2" />Update Flock</>
            )}
          </Button>
        </div>
      </form>


      {/* Treatments from campaigns (339), kept with the flock. */}
      <div className="mt-6">
        {showTreatments && <FlockTreatmentHistory flockId={parseInt(flockId)} />}
      </div>
    </div>
  )
}
