"use client"

// The Edit Flock Batch form -- batch details, purchase details (cost, paid,
// supplier, cash account), order & delivery, arrived/active and notes. ONE
// form, used by the /flock-batch page's edit dialog, the /flock-batch/[id] page
// and the popup on Initial Farm Setup, so the three can never show different
// fields again. Moved out of components/setup-views/flock-batch.tsx unchanged.

import { useEffect, useMemo, useState } from "react"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Save } from "lucide-react"
import { BreedSelect } from "@/components/poultry/breed-select"
import { getFlockBatch, getFlockBatches, updateFlockBatch, type FlockBatchInput } from "@/lib/api/flock-batch"
import { getSuppliers, type Supplier } from "@/lib/api/supplier"
import { listPoultryCashAccounts, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { getUserContext } from "@/lib/utils/user-context"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import { batchStatusFromToggles, batchTogglesFromStatus } from "@/lib/utils/batch-status"
import { paymentStatus } from "@/lib/poultry/batch-purchase"
import { useFmt, useCurrency } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"

export function FlockBatchEditForm({
  batchId, onSaved, onCancel, suppliers: suppliersIn, cashAccounts: cashAccountsIn, knownBreeds: knownBreedsIn,
}: {
  batchId: number | string
  /** Called after a successful save (the form shows its own toast). */
  onSaved?: () => void
  onCancel?: () => void
  /** Optional: a page that already loaded these passes them to skip the fetch. */
  suppliers?: Supplier[]
  cashAccounts?: PoultryCashAccount[]
  knownBreeds?: string[]
}) {
  const { toast } = useToast()
  const fmtMoney = useFmt()
  const { symbol: currencySymbol } = useCurrency()
  const [editLoading, setEditLoading] = useState(false)
  const [editError, setEditError] = useState("")
  const [editForm, setEditForm] = useState({
    batchName: "",
    batchCode: "",
    startDate: "",
    breed: "",
    numberOfBirds: 0,
    costPerChick: 0,
    totalCost: 0,
    amountPaid: 0,
    supplierType: "local",
    supplierId: "" as string,
    hasArrived: false,
    active: true,
    notes: "",
    dollarConversionRate: 0,
    orderPlacementDate: "",
    estimatedArrivalDate: "",
    poultryCashAccountId: "" as string,
  })
  const [editFetching, setEditFetching] = useState(false)

  const [suppliersOwn, setSuppliers] = useState<Supplier[]>([])
  const [cashAccountsOwn, setCashAccounts] = useState<PoultryCashAccount[]>([])
  const [breedsOwn, setBreeds] = useState<string[]>([])
  const suppliers = suppliersIn ?? suppliersOwn
  const cashAccounts = cashAccountsIn ?? cashAccountsOwn
  const distinctBreeds = useMemo(() => knownBreedsIn ?? breedsOwn, [knownBreedsIn, breedsOwn])

  useEffect(() => {
    const { userId, farmId } = getUserContext()
    if (!suppliersIn && userId && farmId) {
      getSuppliers(userId, farmId).then((r) => { if (r.success && r.data) setSuppliers(r.data) }).catch(() => {})
    }
    if (!cashAccountsIn) {
      listPoultryCashAccounts().then((a) => setCashAccounts(a.filter((x) => x.isActive))).catch(() => setCashAccounts([]))
    }
    if (!knownBreedsIn && userId && farmId) {
      getFlockBatches(userId, farmId).then((r) => {
        if (r.success && Array.isArray(r.data)) setBreeds(Array.from(new Set(r.data.map((b) => b.breed).filter(Boolean))))
      }).catch(() => {})
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const loadBatch = async (batchId: number) => {
    setEditError("")
    setEditFetching(true)

    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setEditError("User context not found.")
      setEditFetching(false)
      return
    }

    const result = await getFlockBatch(batchId, userId, farmId)
    if (result.success && result.data) {
      const b = result.data
      const toggles = batchTogglesFromStatus(b.status)
      setEditForm({
        batchName: b.batchName || "",
        batchCode: b.batchCode || "",
        startDate: b.startDate ? b.startDate.split('T')[0] : "",
        breed: b.breed || "",
        numberOfBirds: b.numberOfBirds || 0,
        costPerChick: b.costPerChick || 0,
        totalCost: b.totalCost || 0,
        amountPaid: b.amountPaid || 0,
        supplierType: b.supplierType || "local",
        dollarConversionRate: b.dollarConversionRate || 0,
        supplierId: b.supplierId != null ? String(b.supplierId) : "",
        hasArrived: toggles.hasArrived,
        active: toggles.active,
        notes: b.notes || "",
        orderPlacementDate: b.orderPlacementDate ? b.orderPlacementDate.split('T')[0] : "",
        estimatedArrivalDate: b.estimatedArrivalDate ? b.estimatedArrivalDate.split('T')[0] : "",
        poultryCashAccountId: b.poultryCashAccountId != null ? String(b.poultryCashAccountId) : "",
      })
    } else {
      setEditError(result.message || "Failed to load flock batch")
    }
    setEditFetching(false)
  }
  useEffect(() => { void loadBatch(Number(batchId)) /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [batchId])

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      setEditError("User context not found.")
      toast({ title: "Session issue", description: "We could not confirm your farm or user. Please sign in again.", variant: "destructive" })
      return
    }

    if (!editForm.batchName.trim() || !editForm.batchCode.trim() || !editForm.startDate) {
      setEditError("Please fill in all required fields")
      toastFormGuide(toast, "Fill in batch name, batch code, and start date — they help track birds from arrival.")
      return
    }
    if (editForm.numberOfBirds <= 0) {
      setEditError("Number of birds must be greater than 0")
      toastFormGuide(toast, "Enter how many birds arrived in this batch — use a number greater than zero.")
      return
    }

    setEditLoading(true)
    setEditError("")

    const flockBatchData: Partial<FlockBatchInput> = {
      batchName: editForm.batchName,
      batchCode: editForm.batchCode,
      startDate: editForm.startDate + 'T00:00:00Z',
      breed: editForm.breed,
      numberOfBirds: editForm.numberOfBirds,
      costPerChick: editForm.costPerChick || 0,
      totalCost: editForm.totalCost || (editForm.costPerChick * editForm.numberOfBirds) || 0,
      amountPaid: editForm.amountPaid || 0,
      supplierType: editForm.supplierType,
      dollarConversionRate: editForm.dollarConversionRate || null,
      supplierId: editForm.supplierId ? Number(editForm.supplierId) : null,
      status: batchStatusFromToggles(editForm.hasArrived, editForm.active),
      notes: editForm.notes || undefined,
      orderPlacementDate: editForm.orderPlacementDate || null,
      estimatedArrivalDate: editForm.estimatedArrivalDate || null,
      // 0 clears the account; the update moves the batch's cash with it.
      poultryCashAccountId: editForm.poultryCashAccountId ? Number(editForm.poultryCashAccountId) : 0,
      farmId,
      userId,
    }

    const result = await updateFlockBatch(Number(batchId), flockBatchData)
    if (result.success) {
      const warnings: string[] = (result as any).warnings ?? []
      if (warnings.length > 0) {
        toast({ title: "Batch updated — please check", description: warnings.join(" "), duration: 12000 })
      } else {
        toast({ title: "Success!", description: "Flock batch updated successfully." })
      }
      onSaved?.()
    } else {
      setEditError(result.message || "Failed to update flock batch")
    }
    setEditLoading(false)
  }

  const editBalance = Math.max(0, (Number(editForm.totalCost) || 0) - (Number(editForm.amountPaid) || 0))
  const editStatus = paymentStatus(editForm.totalCost, editForm.amountPaid)

  return (
    <>
      {editError && (
        <Alert variant="destructive"><AlertDescription>{editError}</AlertDescription></Alert>
      )}
      {editFetching ? (
        <div className="py-8 text-center">
          <Loader2 className="w-8 h-8 animate-spin mx-auto mb-2 text-blue-600" />
          <p className="text-slate-600">Loading flock batch...</p>
        </div>
      ) : (
        <form onSubmit={handleEditSubmit} className="space-y-4">
          <div className="rounded-xl border border-slate-200 overflow-hidden">
            <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Batch Details</div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Batch Name *</Label>
                <Input placeholder="e.g., Batch A - Rhode Island Reds" value={editForm.batchName} onChange={(e) => setEditForm({ ...editForm, batchName: e.target.value })} required disabled={editLoading} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Batch Code *</Label>
                <Input placeholder="e.g., B-001" value={editForm.batchCode} onChange={(e) => setEditForm({ ...editForm, batchCode: e.target.value })} required disabled={editLoading} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Breed</Label>
                <BreedSelect value={editForm.breed} known={distinctBreeds} disabled={editLoading}
                  onChange={(breed) => setEditForm({ ...editForm, breed })} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Start Date *</Label>
                <Input type="date" value={editForm.startDate} onChange={(e) => setEditForm({ ...editForm, startDate: e.target.value })} required disabled={editLoading} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Number of Birds *</Label>
                <NumberInput min="1" placeholder="e.g., 100" value={editForm.numberOfBirds} onChange={(e) => {
                  const n = parseInt(e.target.value) || 0
                  setEditForm(prev => ({ ...prev, numberOfBirds: n, totalCost: prev.costPerChick > 0 ? +(prev.costPerChick * n).toFixed(2) : prev.totalCost }))
                }} required disabled={editLoading} />
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-slate-200 overflow-hidden">
            <div className="bg-emerald-600 px-4 py-2 text-sm font-semibold text-white">Purchase Details</div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Cost Per Chick</Label>
                <NumberInput min="0" step="0.01" placeholder="e.g., 2.50" value={editForm.costPerChick} onChange={(e) => {
                  const c = parseFloat(e.target.value) || 0
                  setEditForm(prev => ({ ...prev, costPerChick: c, totalCost: prev.numberOfBirds > 0 ? +(c * prev.numberOfBirds).toFixed(2) : prev.totalCost }))
                }} disabled={editLoading} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Total Cost</Label>
                <NumberInput min="0" step="0.01" placeholder="Auto-calculated" value={editForm.totalCost} onChange={(e) => setEditForm({ ...editForm, totalCost: parseFloat(e.target.value) || 0 })} disabled={editLoading} />
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Amount Paid ({currencySymbol})</Label>
                <NumberInput min="0" step="0.01" placeholder="e.g., 250.00" value={editForm.amountPaid} onChange={(e) => setEditForm({ ...editForm, amountPaid: parseFloat(e.target.value) || 0 })} disabled={editLoading} />
                <p className="text-xs text-slate-500">Raise this to record a further payment toward the balance.</p>
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Type</Label>
                <Select value={editForm.supplierType} onValueChange={(v) => setEditForm({ ...editForm, supplierType: v })} disabled={editLoading}>
                  <SelectTrigger><SelectValue placeholder="Supplier Type" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="local">Local</SelectItem>
                    <SelectItem value="foreign">Foreign</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Supplier</Label>
                <Select value={editForm.supplierId} onValueChange={(v) => setEditForm({ ...editForm, supplierId: v })} disabled={editLoading}>
                  <SelectTrigger><SelectValue placeholder={suppliers.length === 0 ? "No suppliers found" : "Select supplier"} /></SelectTrigger>
                  <SelectContent>
                    {suppliers.map(s => (
                      <SelectItem key={s.supplierId} value={String(s.supplierId)}>{s.name}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <CashAccountField accounts={cashAccounts} disabled={editLoading}
                value={editForm.poultryCashAccountId}
                onChange={(v) => setEditForm({ ...editForm, poultryCashAccountId: v })} />
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Dollar Conversion Rate</Label>
                <NumberInput min="0" step="0.0001" placeholder="e.g., 15.5" value={editForm.dollarConversionRate} onChange={(e) => setEditForm({ ...editForm, dollarConversionRate: parseFloat(e.target.value) || 0 })} disabled={editLoading} />
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-slate-200 overflow-hidden">
            <div className="bg-sky-600 px-4 py-2 text-sm font-semibold text-white">Order &amp; Delivery</div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4 bg-white">
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Order Placement Date</Label>
                <Input type="date" value={editForm.orderPlacementDate} onChange={(e) => setEditForm({ ...editForm, orderPlacementDate: e.target.value })} disabled={editLoading} />
                <p className="text-xs text-slate-500">When you placed the order with the supplier.</p>
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Estimated Arrival Date</Label>
                <Input type="date" value={editForm.estimatedArrivalDate} onChange={(e) => setEditForm({ ...editForm, estimatedArrivalDate: e.target.value })} disabled={editLoading} />
                <p className="text-xs text-slate-500">When the birds are expected to arrive.</p>
              </div>
              <div className="md:col-span-2 rounded-lg bg-slate-50 border border-slate-200 p-3 flex flex-wrap items-center justify-between gap-2">
                <div className="text-sm text-slate-600">
                  Total <span className="font-semibold text-slate-900 tabular-nums">{fmtMoney(editForm.totalCost)}</span>
                  <span className="mx-2 text-slate-300">•</span>
                  Paid <span className="font-semibold text-emerald-700 tabular-nums">{fmtMoney(editForm.amountPaid)}</span>
                  <span className="mx-2 text-slate-300">•</span>
                  Balance <span className={cn("font-semibold tabular-nums", editBalance > 0 ? "text-red-600" : "text-emerald-700")}>{fmtMoney(editBalance)}</span>
                </div>
                <Badge variant="outline" className={editStatus.className}>{editStatus.label}</Badge>
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-slate-200 overflow-hidden">
            <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Status &amp; Notes</div>
            <div className="p-4 bg-white space-y-4">
              <div className="flex items-center space-x-2">
                <Switch checked={editForm.hasArrived} onCheckedChange={(checked) => setEditForm({ ...editForm, hasArrived: checked })} disabled={editLoading} />
                <Label className="text-sm font-medium text-slate-700">Batch Has Arrived</Label>
                <p className="text-xs text-slate-500 ml-2">(Turn on once birds physically arrive)</p>
              </div>
              <div className="flex items-center space-x-2">
                <Switch checked={editForm.active} onCheckedChange={(checked) => setEditForm({ ...editForm, active: checked })} disabled={editLoading || !editForm.hasArrived} />
                <Label className="text-sm font-medium text-slate-700">Active Batch</Label>
                <p className="text-xs text-slate-500 ml-2">(Only applies once the batch has arrived)</p>
              </div>
              <div className="space-y-2">
                <Label className="text-sm font-medium text-slate-700">Notes (Optional)</Label>
                <textarea placeholder="Add any additional notes about the batch" value={editForm.notes || ''}
                  onChange={(e) => setEditForm({ ...editForm, notes: e.target.value })}
                  className="w-full rounded-md border border-slate-200 bg-white px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[80px]" disabled={editLoading} />
              </div>
            </div>
          </div>

          <div className="flex gap-3 justify-end pt-2">
            <Button type="button" onClick={() => onCancel?.()} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button type="submit" disabled={editLoading}>
              {editLoading ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Saving...</> : <><Save className="w-4 h-4 mr-2" />Update Batch</>}
            </Button>
          </div>
        </form>
      )}
    </>
  )
}

function CashAccountField({ accounts, value, onChange, disabled }: {
  accounts: PoultryCashAccount[]
  value: string
  onChange: (value: string) => void
  disabled?: boolean
}) {
  return (
    <div className="space-y-2">
      <Label className="text-sm font-medium text-slate-700">Pay from cash account</Label>
      <Select value={value || "none"} onValueChange={(v) => onChange(v === "none" ? "" : v)} disabled={disabled}>
        <SelectTrigger><SelectValue placeholder="None (no cash movement)" /></SelectTrigger>
        <SelectContent>
          <SelectItem value="none">None (no cash movement)</SelectItem>
          {accounts.map((a) => (
            <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
              {a.accountName} ({a.currentBalance.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })})
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      <p className="text-xs text-slate-500">The amount paid comes out of this account&apos;s balance.</p>
    </div>
  )
}
