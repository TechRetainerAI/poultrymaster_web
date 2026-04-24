"use client"

import { useEffect, useMemo, useState } from "react"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { getFlocks } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"
import { createProductionRecord, updateProductionRecord, deleteProductionRecord, getProductionRecords, type ProductionRecordInput, type ProductionRecord } from "@/lib/api/production-record"
import { createFeedUsage, updateFeedUsage, getFeedUsages, type FeedUsageInput } from "@/lib/api/feed-usage"
import { usePermissions } from "@/hooks/use-permissions"
import { Trash2, Calendar as CalendarIcon } from "lucide-react"
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover"
import { Calendar } from "@/components/ui/calendar"
import { format } from "date-fns"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import { getBirdsLeftFromRecord, getLatestRecordForFlock } from "@/lib/utils/production-records"
import {
  EGG_GRADE_OPTIONS,
  EGG_GRADE_SELECT_VALUE_NONE,
  eggGradeFromApi,
  eggGradeToApi,
} from "@/lib/constants/egg-grade"

interface ProductionFormProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  record?: ProductionRecord | null
  onSaved?: () => void
  /**
   * Render mode:
   * - "modal" (default): inside a Dialog
   * - "page": full-width page form (no popup)
   */
  mode?: "modal" | "page"
}

export function ProductionForm({ open, onOpenChange, record, onSaved, mode = "modal" }: ProductionFormProps) {
  const { toast } = useToast()
  const [saving, setSaving] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [error, setError] = useState("")
  const [flocks, setFlocks] = useState<any[]>([])
  const [flocksError, setFlocksError] = useState("")
  const { isAdmin } = usePermissions()

  const today = useMemo(() => new Date().toISOString().slice(0, 10), [])

  const [form, setForm] = useState({
    flockId: "",
    date: today,
    morning: "",
    noon: "",
    evening: "",
    brokenEggs: "",
    feedKg: "",
    feedType: "",
    mortality: "",
    numBirds: "",
    notes: "",
    medication: "",
    eggGrade: EGG_GRADE_SELECT_VALUE_NONE,
  })

  const feedTypes = [
    "Starter Feed",
    "Grower Feed", 
    "Layer Feed",
    "Broiler Feed",
    "Organic Feed",
    "Custom Mix"
  ]
  const [manualAge, setManualAge] = useState(false)
  const [manualWeeks, setManualWeeks] = useState("")
  const [manualDays, setManualDays] = useState("")
  const [manualYears, setManualYears] = useState("")

  const [previousBirdsLeft, setPreviousBirdsLeft] = useState<number | null>(null)

  // Crate-based egg entry state for each time slot
  const EGGS_PER_CRATE = 30
  const [morningCrates, setMorningCrates] = useState(0)
  const [morningLoose, setMorningLoose] = useState(0)
  const [noonCrates, setNoonCrates] = useState(0)
  const [noonLoose, setNoonLoose] = useState(0)
  const [eveningCrates, setEveningCrates] = useState(0)
  const [eveningLoose, setEveningLoose] = useState(0)
  const [brokenCrates, setBrokenCrates] = useState(0)
  const [brokenLoose, setBrokenLoose] = useState(0)

  // Compute individual time slot totals from crates + loose
  const morningTotal = (morningCrates * EGGS_PER_CRATE) + morningLoose
  const noonTotal = (noonCrates * EGGS_PER_CRATE) + noonLoose
  const eveningTotal = (eveningCrates * EGGS_PER_CRATE) + eveningLoose
  const brokenTotal = (brokenCrates * EGGS_PER_CRATE) + brokenLoose

  // Keep form.morning/noon/evening in sync with crate values
  useEffect(() => {
    setForm(prev => ({ ...prev, morning: String(morningTotal) }))
  }, [morningTotal])
  useEffect(() => {
    setForm(prev => ({ ...prev, noon: String(noonTotal) }))
  }, [noonTotal])
  useEffect(() => {
    setForm(prev => ({ ...prev, evening: String(eveningTotal) }))
  }, [eveningTotal])
  useEffect(() => {
    setForm(prev => ({ ...prev, brokenEggs: String(brokenTotal) }))
  }, [brokenTotal])

  const total = (parseInt(form.morning) || 0) + (parseInt(form.noon) || 0) + (parseInt(form.evening) || 0)
  const totalCrates = Math.floor(total / EGGS_PER_CRATE)
  const totalPieces = total % EGGS_PER_CRATE
  // Birds left must always equal numBirds - mortality to keep data consistent
  const birdsLeft = (parseInt(form.numBirds) || 0) - (parseInt(form.mortality) || 0)
  const selectedFlock = useMemo(() => flocks.find((f) => String(f.flockId) === form.flockId), [flocks, form.flockId])
  const { ageWeeks, ageDays, ageYears } = useMemo(() => {
    try {
      if (!selectedFlock?.startDate || !form.date) return { ageWeeks: 0, ageDays: 0, ageYears: 0 }
      // Normalize both dates to UTC date-only to avoid timezone off-by-one
      const startStr = (selectedFlock.startDate || "").split("T")[0]
      const currStr = form.date.split("T")[0]
      const [sy, sm, sd] = startStr.split("-").map(Number)
      const [cy, cm, cd] = currStr.split("-").map(Number)
      const startUtc = Date.UTC(sy, sm - 1, sd)
      const currUtc = Date.UTC(cy, cm - 1, cd)
      const ms = Math.max(0, currUtc - startUtc)
      const days = Math.floor(ms / (1000 * 60 * 60 * 24))
      const weeks = Math.floor(days / 7)
      const years = Math.floor(days / 365)
      return { ageWeeks: weeks, ageDays: days, ageYears: years }
    } catch { return { ageWeeks: 0, ageDays: 0, ageYears: 0 } }
  }, [selectedFlock, form.date])

  useEffect(() => {
    const load = async () => {
      try {
        setFlocksError("")
        const { userId, farmId } = getUserContext()
        if (!userId || !farmId) return
        const res = await getFlocks(userId, farmId)
        if (res.success && Array.isArray(res.data)) setFlocks(res.data)
        else {
          setFlocks([])
          setFlocksError(res.message || "Failed to load flocks.")
        }
      } catch (e) {
        setFlocks([])
        setFlocksError("Unable to fetch flocks. Check API URL and CORS.")
      }
    }
    load()
  }, [])

  // Load previous records to calculate birds left
  useEffect(() => {
    const loadPreviousRecords = async () => {
      if (!form.flockId || !form.date) {
        setPreviousBirdsLeft(null)
        return
      }

      try {
        const { userId, farmId } = getUserContext()
        if (!userId || !farmId) return

        const res = await getProductionRecords(userId, farmId)
        if (res.success && res.data) {
          const flockIdNum = parseInt(form.flockId)
          const mostRecent = getLatestRecordForFlock(res.data, flockIdNum)

          if (mostRecent) {
            const lastBirdsLeft = getBirdsLeftFromRecord(mostRecent)
            setPreviousBirdsLeft(lastBirdsLeft)
            
            // Auto-populate numBirds if not set
            if (!form.numBirds && lastBirdsLeft > 0) {
              setForm(prev => ({ ...prev, numBirds: String(lastBirdsLeft) }))
            }
          } else {
            // No previous records, use flock's initial quantity
            const flock = flocks.find(f => f.flockId === flockIdNum)
            if (flock) {
              setPreviousBirdsLeft(flock.quantity || 0)
              if (!form.numBirds) {
                setForm(prev => ({ ...prev, numBirds: String(flock.quantity || 0) }))
              }
            } else {
              setPreviousBirdsLeft(null)
            }
          }
        }
      } catch (e) {
        console.error("Error loading previous records:", e)
        setPreviousBirdsLeft(null)
      }
    }

    loadPreviousRecords()
  }, [form.flockId, form.date, flocks])

  useEffect(() => {
    if (!record) {
      setForm({ flockId: "", date: today, morning: "", noon: "", evening: "", brokenEggs: "", feedKg: "", feedType: "", mortality: "", numBirds: "", notes: "", medication: "", eggGrade: EGG_GRADE_SELECT_VALUE_NONE })
      setMorningCrates(0); setMorningLoose(0)
      setNoonCrates(0); setNoonLoose(0)
      setEveningCrates(0); setEveningLoose(0)
      setBrokenCrates(0); setBrokenLoose(0)
      return
    }

    // Decompose stored totals into crates + loose
    const m = record.production9AM ?? 0
    const n = record.production12PM ?? 0
    const ev = record.production4PM ?? 0
    const br = record.brokenEggs ?? 0
    setMorningCrates(Math.floor(m / EGGS_PER_CRATE)); setMorningLoose(m % EGGS_PER_CRATE)
    setNoonCrates(Math.floor(n / EGGS_PER_CRATE)); setNoonLoose(n % EGGS_PER_CRATE)
    setEveningCrates(Math.floor(ev / EGGS_PER_CRATE)); setEveningLoose(ev % EGGS_PER_CRATE)
    setBrokenCrates(Math.floor(br / EGGS_PER_CRATE)); setBrokenLoose(br % EGGS_PER_CRATE)
    
    // First, set the main form data from the record
    const baseFormData = {
      flockId: String((record as any).flockId || ""),
      date: (record.date || "").split("T")[0],
      morning: String(record.production9AM ?? ""),
      noon: String(record.production12PM ?? ""),
      evening: String(record.production4PM ?? ""),
      brokenEggs: String(record.brokenEggs ?? ""),
      feedKg: String(record.feedKg ?? ""),
      feedType: "",
      mortality: String(record.mortality ?? ""),
      numBirds: String(record.noOfBirds ?? ""),
      notes: "",
      medication: record.medication || "",
      eggGrade: eggGradeFromApi((record as ProductionRecord & { eggGrade?: string | null }).eggGrade),
    }
    
    setForm(baseFormData)
    
    // Then try to load feed type from feed usage
    const loadFeedType = async () => {
      const { userId, farmId } = getUserContext()
      if (!userId || !farmId || !record.id) return
      
      try {
        const feedUsagesRes = await getFeedUsages(userId, farmId)
        if (feedUsagesRes.success && feedUsagesRes.data) {
          const matchingFeedUsage = feedUsagesRes.data.find(
            (fu: any) => fu.flockId === (record as any).flockId && 
            new Date(fu.usageDate).toISOString().split('T')[0] === (record.date || "").split("T")[0]
          )
          if (matchingFeedUsage) {
            setForm(prev => ({ ...prev, feedType: matchingFeedUsage.feedType || "" }))
          }
        }
      } catch (e) {
        console.error("Error loading feed type:", e)
      }
    }
    
    loadFeedType()
  }, [record, today])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    try {
      setSaving(true)
      setError("")
      const { userId, farmId } = getUserContext()
      if (!userId || !farmId) throw new Error("Missing user/farm context")

      // Validation
      const numBirds = parseInt(form.numBirds) || 0
      const mortality = parseInt(form.mortality) || 0
      // Always use numBirds - mortality to keep noOfBirds and noOfBirdsLeft consistent
      const calculatedLeft = numBirds - mortality

      if (mortality > numBirds) {
        const msg = `Mortality (${mortality}) cannot be greater than number of birds (${numBirds})`
        setError(msg)
        toast({ title: "Validation error", description: msg, variant: "destructive" })
        setSaving(false)
        return
      }

      if (calculatedLeft < 0) {
        const msg = "Birds left cannot be negative. Check your mortality and number of birds."
        setError(msg)
        toast({ title: "Validation error", description: msg, variant: "destructive" })
        setSaving(false)
        return
      }

      if (!form.flockId) {
        const msg = "Please select a flock."
        setError(msg)
        toast({ title: "Validation error", description: msg, variant: "destructive" })
        setSaving(false)
        return
      }

      const resolvedDays = manualAge
        ? (parseInt(manualDays) || ((parseInt(manualYears) || 0) * 365) || ((parseInt(manualWeeks) || 0) * 7))
        : ageDays
      const resolvedWeeks = manualAge
        ? (parseInt(manualWeeks) || Math.floor(((parseInt(manualDays) || 0) / 7)) || ((parseInt(manualYears) || 0) * 52))
        : ageWeeks

      const input: ProductionRecordInput = {
        farmId,
        userId,
        createdBy: userId,
        updatedBy: userId,
        ageInWeeks: resolvedWeeks,
        ageInDays: resolvedDays,
        date: form.date,
        noOfBirds: numBirds,
        mortality: mortality,
        noOfBirdsLeft: calculatedLeft,
        feedKg: parseFloat(form.feedKg) || 0,
        medication: form.medication || "None",
        production9AM: parseInt(form.morning) || 0,
        production12PM: parseInt(form.noon) || 0,
        production4PM: parseInt(form.evening) || 0,
        brokenEggs: parseInt(form.brokenEggs) || 0,
        totalProduction: total,
        flockId: form.flockId ? parseInt(form.flockId) : null,
        eggGrade: eggGradeToApi(form.eggGrade),
      }

      let productionRecordId: number | null = null
      if (record) {
        await updateProductionRecord(record.id, input)
        productionRecordId = record.id
      } else {
        const createRes = await createProductionRecord(input)
        if (createRes.success && (createRes as any).data) {
          productionRecordId = ((createRes as any).data as any).id || null
        }
      }

      // Sync feed usage if feedKg > 0 and feedType is provided
      if (parseFloat(form.feedKg) > 0 && form.flockId && form.feedType) {
        try {
          const { userId, farmId } = getUserContext()
          if (userId && farmId) {
            // Check if feed usage already exists for this date and flock
            const feedUsagesRes = await getFeedUsages(userId, farmId)
            let existingFeedUsage: any = null
            
            if (feedUsagesRes.success && feedUsagesRes.data) {
              existingFeedUsage = feedUsagesRes.data.find(
                (fu: any) => fu.flockId === parseInt(form.flockId) && 
                new Date(fu.usageDate).toISOString().split('T')[0] === form.date
              )
            }

            const feedUsageData: FeedUsageInput = {
              farmId,
              userId,
              flockId: parseInt(form.flockId),
              usageDate: form.date + 'T00:00:00Z',
              feedType: form.feedType,
              quantityKg: parseFloat(form.feedKg) || 0,
            }

            if (existingFeedUsage) {
              await updateFeedUsage(existingFeedUsage.feedUsageId, feedUsageData)
            } else {
              await createFeedUsage(feedUsageData)
            }
          }
        } catch (feedError) {
          console.error("Error syncing feed usage:", feedError)
          // Don't fail the whole operation if feed sync fails
        }
      }

      onOpenChange(false)
      onSaved?.()
    } catch (err: any) {
      setError(err?.message || "Failed to save")
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!record) return
    
    try {
      setDeleting(true)
      setError("")
      const { userId, farmId } = getUserContext()
      if (!userId || !farmId) throw new Error("Missing user/farm context")

      const res = await deleteProductionRecord(record.id, userId, farmId)
      
      if (!res.success) {
        setError(res.message || "Failed to delete production record")
        setShowDeleteConfirm(false)
        return
      }

      setShowDeleteConfirm(false)
      onOpenChange(false)
      onSaved?.()
    } catch (err: any) {
      setError(err?.message || "Failed to delete")
      setShowDeleteConfirm(false)
    } finally {
      setDeleting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="w-[95vw] max-w-[95vw] sm:max-w-6xl sm:w-[1100px] max-h-[90vh] flex flex-col overflow-hidden">
        <DialogHeader>
          <DialogTitle>{record ? "Edit Production Record" : "Log Production"}</DialogTitle>
          <DialogDescription>{record ? "Update production data" : "Record daily production data"}</DialogDescription>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto overflow-x-hidden pr-1">
        {error ? <div className="p-3 rounded border border-red-200 bg-red-50 text-red-700 mb-4">{error}</div> : null}

        <form onSubmit={handleSubmit} className="space-y-6 w-full min-w-0">
          {/* Section 1: Flock & Date */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">
              Flock &amp; Date
            </div>
            <div className="grid grid-cols-12 gap-4 px-4 py-4">
              <div className="col-span-12 md:col-span-6 space-y-2">
                <Label>Flock</Label>
                <Select value={form.flockId} onValueChange={(v) => setForm({ ...form, flockId: v })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select flock" />
                  </SelectTrigger>
                  <SelectContent>
                    {flocks.map((f) => (
                      <SelectItem key={f.flockId} value={String(f.flockId)}>
                        {f.name || `Flock ${f.flockId}`} (ID: {f.flockId})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {flocksError ? <div className="text-xs text-amber-600">{flocksError}</div> : null}
                {form.flockId ? (
                  <div className="text-xs text-slate-500">
                    Selected Flock ID: <span className="font-semibold">{form.flockId}</span>
                  </div>
                ) : null}
              </div>

              <div className="col-span-12 md:col-span-6 space-y-2">
                <Label>Date</Label>
                <Input
                  type="date"
                  value={form.date}
                  onChange={(e) => setForm({ ...form, date: e.target.value })}
                  required
                  className="w-full"
                />
                <div className="text-xs text-slate-500">
                  Defaults to today. Change only if you are logging for a different date.
                </div>
              </div>
            </div>
          </div>

          {/* Section 2: Egg Production */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">
              Egg Production
            </div>
            <div className="grid grid-cols-12 gap-4 px-4 py-4">
              {/* Morning (9am) - Crates + Loose */}
              <div className="col-span-12 p-3 bg-blue-50 border border-blue-200 rounded-lg space-y-2">
                <Label className="text-blue-800 font-semibold">Morning (9am) — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div className="space-y-1">
                    <Label className="text-xs">Crates ({EGGS_PER_CRATE} eggs)</Label>
                    <Input type="number" min="0" value={morningCrates} onChange={(e) => setMorningCrates(parseInt(e.target.value) || 0)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Loose Eggs</Label>
                    <Input type="number" min="0" max="29" value={morningLoose} onChange={(e) => setMorningLoose(parseInt(e.target.value) || 0)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Total</Label>
                    <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-blue-700">{morningTotal.toLocaleString()}</div>
                  </div>
                </div>
                <p className="text-xs text-blue-600">{morningCrates} crates × {EGGS_PER_CRATE} + {morningLoose} loose = {morningTotal.toLocaleString()} eggs</p>
              </div>

              {/* Noon (12pm) - Crates + Loose */}
              <div className="col-span-12 p-3 bg-orange-50 border border-orange-200 rounded-lg space-y-2">
                <Label className="text-orange-800 font-semibold">Noon (12pm) — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div className="space-y-1">
                    <Label className="text-xs">Crates ({EGGS_PER_CRATE} eggs)</Label>
                    <Input type="number" min="0" value={noonCrates} onChange={(e) => setNoonCrates(parseInt(e.target.value) || 0)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Loose Eggs</Label>
                    <Input type="number" min="0" max="29" value={noonLoose} onChange={(e) => setNoonLoose(parseInt(e.target.value) || 0)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Total</Label>
                    <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-orange-700">{noonTotal.toLocaleString()}</div>
                  </div>
                </div>
                <p className="text-xs text-orange-600">{noonCrates} crates × {EGGS_PER_CRATE} + {noonLoose} loose = {noonTotal.toLocaleString()} eggs</p>
              </div>

              {/* Evening (4pm) - Crates + Loose */}
              <div className="col-span-12 p-3 bg-purple-50 border border-purple-200 rounded-lg space-y-2">
                <Label className="text-purple-800 font-semibold">Evening (4pm) — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div className="space-y-1">
                    <Label className="text-xs">Crates ({EGGS_PER_CRATE} eggs)</Label>
                    <Input type="number" min="0" value={eveningCrates} onChange={(e) => setEveningCrates(parseInt(e.target.value) || 0)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Loose Eggs</Label>
                    <Input type="number" min="0" max="29" value={eveningLoose} onChange={(e) => setEveningLoose(parseInt(e.target.value) || 0)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Total</Label>
                    <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-purple-700">{eveningTotal.toLocaleString()}</div>
                  </div>
                </div>
                <p className="text-xs text-purple-600">{eveningCrates} crates × {EGGS_PER_CRATE} + {eveningLoose} loose = {eveningTotal.toLocaleString()} eggs</p>
              </div>

              {/* Brokens - Crates + Loose */}
              <div className="col-span-12 p-3 bg-red-50 border border-red-200 rounded-lg space-y-2">
                <Label className="text-red-800 font-semibold">Broken Eggs — Crates × {EGGS_PER_CRATE} + Loose Eggs</Label>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                  <div className="space-y-1">
                    <Label className="text-xs">Crates ({EGGS_PER_CRATE} eggs)</Label>
                    <Input type="number" min="0" value={brokenCrates} onChange={(e) => setBrokenCrates(parseInt(e.target.value) || 0)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Loose Eggs</Label>
                    <Input type="number" min="0" max="29" value={brokenLoose} onChange={(e) => setBrokenLoose(parseInt(e.target.value) || 0)} />
                  </div>
                  <div className="space-y-1">
                    <Label className="text-xs">Total</Label>
                    <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-red-700">{brokenTotal.toLocaleString()}</div>
                  </div>
                </div>
                <p className="text-xs text-red-600">{brokenCrates} crates × {EGGS_PER_CRATE} + {brokenLoose} loose = {brokenTotal.toLocaleString()} broken eggs</p>
              </div>

              {/* Total Eggs Summary */}
              <div className="col-span-12 p-3 bg-emerald-50 border border-emerald-200 rounded-lg">
                <div className="flex items-center justify-between">
                  <Label className="text-emerald-800 font-semibold">Total Eggs</Label>
                  <div className="text-right">
                    <div className="text-lg font-bold text-emerald-700">{total.toLocaleString()} eggs</div>
                    <div className="text-xs text-emerald-600">{totalCrates} crates + {totalPieces} pieces</div>
                  </div>
                </div>
              </div>

              <div className="col-span-12 md:col-span-6 space-y-2">
                <Label>Egg grade</Label>
                <Select
                  value={form.eggGrade}
                  onValueChange={(v) => setForm({ ...form, eggGrade: v })}
                >
                  <SelectTrigger className="bg-white">
                    <SelectValue placeholder="Select grade" />
                  </SelectTrigger>
                  <SelectContent>
                    {EGG_GRADE_OPTIONS.map((o) => (
                      <SelectItem key={o.value} value={o.value}>
                        {o.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <p className="text-xs text-slate-500">Quality band for this day’s eggs (e.g. P1, P2).</p>
              </div>
            </div>
          </div>

          {/* Section 3: Birds & Age */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">
              Birds &amp; Age
            </div>
            <div className="grid grid-cols-12 gap-4 px-4 py-4">
              <div className="col-span-12 md:col-span-4 space-y-2">
                <Label>Num of Birds</Label>
                <Input
                  type="number"
                  min="0"
                  value={form.numBirds}
                  onChange={(e) => setForm({ ...form, numBirds: e.target.value })}
                />
              </div>
              <div className="col-span-12 md:col-span-4 space-y-2">
                <Label>Mortality</Label>
                <Input
                  type="number"
                  min="0"
                  value={form.mortality}
                  onChange={(e) => setForm({ ...form, mortality: e.target.value })}
                />
              </div>
              <div className="col-span-12 md:col-span-4 space-y-2">
                <Label>Birds Left</Label>
                <div className="pt-2 font-semibold">
                  {previousBirdsLeft !== null && (
                    <span className="text-xs text-slate-500 block">
                      From previous: {previousBirdsLeft}
                    </span>
                  )}
                  <span className={birdsLeft < 0 ? "text-red-600" : ""}>{birdsLeft}</span>
                </div>
              </div>

              <div className="col-span-12 flex items-center gap-2 pt-2">
                <input
                  id="manualAge"
                  type="checkbox"
                  checked={manualAge}
                  onChange={(e) => setManualAge(e.target.checked)}
                />
                <Label htmlFor="manualAge">Enter age manually</Label>
              </div>

              {manualAge ? (
                <>
                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Age (weeks)</Label>
                    <Input
                      type="number"
                      min="0"
                      value={manualWeeks}
                      onChange={(e) => setManualWeeks(e.target.value)}
                      placeholder="e.g. 20"
                    />
                  </div>
                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Age (years)</Label>
                    <Input
                      type="number"
                      min="0"
                      value={manualYears}
                      onChange={(e) => setManualYears(e.target.value)}
                      placeholder="e.g. 1"
                    />
                  </div>
                  <div className="col-span-12 md:col-span-4 space-y-2">
                    <Label>Age (days)</Label>
                    <Input
                      type="number"
                      min="0"
                      value={manualDays}
                      onChange={(e) => setManualDays(e.target.value)}
                      placeholder="e.g. 140"
                    />
                  </div>
                </>
              ) : (
                <>
                  <div className="col-span-12 md:col-span-4">
                    <Label>Age (weeks)</Label>
                    <div className="pt-2 font-semibold">{ageWeeks}</div>
                  </div>
                  <div className="col-span-12 md:col-span-4">
                    <Label>Age (years)</Label>
                    <div className="pt-2 font-semibold">{ageYears}</div>
                  </div>
                  <div className="col-span-12 md:col-span-4">
                    <Label>Age (days)</Label>
                    <div className="pt-2 font-semibold">{ageDays}</div>
                  </div>
                </>
              )}
            </div>
          </div>

          {/* Section 4: Feed, Medication & Notes */}
          <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
            <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">
              Feed, Medication &amp; Notes
            </div>
            <div className="grid grid-cols-12 gap-4 px-4 py-4">
              <div className="col-span-12 md:col-span-4 space-y-2">
                <Label>Feed Type</Label>
                <Select value={form.feedType} onValueChange={(v) => setForm({ ...form, feedType: v })}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select feed type" />
                  </SelectTrigger>
                  <SelectContent>
                    {feedTypes.map((type) => (
                      <SelectItem key={type} value={type}>
                        {type}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="col-span-12 md:col-span-4 space-y-2">
                <Label>Feed (kg)</Label>
                <Input
                  type="number"
                  step="0.01"
                  min="0"
                  value={form.feedKg}
                  onChange={(e) => setForm({ ...form, feedKg: e.target.value })}
                />
              </div>
              <div className="col-span-12 md:col-span-4 space-y-2">
                <Label>Medication</Label>
                <Input
                  value={form.medication}
                  onChange={(e) => setForm({ ...form, medication: e.target.value })}
                  placeholder="e.g., Free water"
                />
              </div>

              <div className="col-span-12 space-y-2">
                <Label>Notes</Label>
                <Textarea
                  rows={3}
                  value={form.notes}
                  onChange={(e) => setForm({ ...form, notes: e.target.value })}
                />
              </div>
            </div>
          </div>

          {/* Actions */}
          <div className="flex flex-col gap-3 sm:flex-row sm:justify-between pt-2">
            {/* Delete button - Admin only, only when editing */}
            <div>
              {isAdmin && record && !showDeleteConfirm && (
                <Button
                  type="button"
                  variant="destructive"
                  onClick={() => setShowDeleteConfirm(true)}
                  className="min-w-[120px]"
                  disabled={saving || deleting}
                >
                  <Trash2 className="w-4 h-4 mr-2" />
                  Delete
                </Button>
              )}
              
              {/* Delete confirmation */}
              {isAdmin && record && showDeleteConfirm && (
                <div className="flex items-center gap-2">
                  <span className="text-sm text-red-600 font-medium">Delete this record?</span>
                  <Button
                    type="button"
                    variant="destructive"
                    size="sm"
                    onClick={handleDelete}
                    disabled={deleting}
                  >
                    {deleting ? "Deleting..." : "Yes, Delete"}
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    onClick={() => setShowDeleteConfirm(false)}
                    disabled={deleting}
                    className="bg-red-600 hover:bg-red-700 text-white"
                  >
                    Cancel
                  </Button>
                </div>
              )}
            </div>

            <div className="flex flex-col sm:flex-row gap-3">
              <Button
                type="button"
                onClick={() => onOpenChange(false)}
                className="w-full sm:w-auto sm:min-w-[120px] bg-red-600 hover:bg-red-700 text-white"
              >
                Cancel
              </Button>
              <Button type="submit" disabled={saving} className="w-full sm:w-auto sm:min-w-[160px]">
                {saving ? "Saving..." : record ? "Update" : "Log Production"}
              </Button>
            </div>
          </div>
        </form>
        </div>
      </DialogContent>
    </Dialog>
  )
}
