"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Badge } from "@/components/ui/badge"
import { Pill, RefreshCw, Copy, Loader2, ImageIcon } from "lucide-react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { createHealthRecord, deleteHealthRecord, getHealthRecords, type HealthRecord } from "@/lib/api/health"
import { getProductionRecords, type ProductionRecord } from "@/lib/api/production-record"
import { getFlocks, type Flock } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"
import { formatDateShort, cn } from "@/lib/utils"
import { useIsMobile } from "@/hooks/use-mobile"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { buildMedicationStockLedger, type MedicationLedgerRow } from "@/lib/utils/medication-ledger"
import {
  buildMedicationPhotoNotesDb,
  getLatestMedicationPhotoByProductKey,
  listMedicationPhotoInfos,
  normalizeProductKey,
  primaryLabelFromText,
} from "@/lib/utils/medication-photo"
import { toReceiptViewUrl } from "@/lib/utils/expense-receipt"
import { AuthenticatedHealthImage } from "@/components/health/authenticated-health-image"
import { ExpenseReceiptField } from "@/components/expense/expense-receipt-field"

function normalizeHealthRecord(raw: Record<string, unknown>): HealthRecord {
  return {
    id: (raw.id ?? raw.Id) as number | undefined,
    flockId: (raw.flockId ?? raw.FlockId) as number | null | undefined,
    houseId: (raw.houseId ?? raw.HouseId) as number | null | undefined,
    itemId: (raw.itemId ?? raw.ItemId) as number | null | undefined,
    recordDate: String(raw.recordDate ?? raw.RecordDate ?? raw.date ?? raw.Date ?? ""),
    vaccination: (raw.vaccination ?? raw.Vaccination) as string | null | undefined,
    medication: (raw.medication ?? raw.Medication) as string | null | undefined,
    waterConsumption: (raw.waterConsumption ?? raw.WaterConsumption) as number | null | undefined,
    notes: (raw.notes ?? raw.Notes) as string | null | undefined,
    hasAttachmentImage: Boolean(raw.hasAttachmentImage ?? raw.HasAttachmentImage),
  }
}

function fileToBase64DataOnly(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const s = reader.result as string
      const i = s.indexOf(",")
      resolve(i >= 0 ? s.slice(i + 1) : s)
    }
    reader.onerror = () => reject(new Error("Could not read file"))
    reader.readAsDataURL(file)
  })
}

const LEDGER_PAGE_SIZE = 15

export default function MedicationTrackerPage() {
  const router = useRouter()
  const { toast } = useToast()
  const isMobile = useIsMobile()
  const [records, setRecords] = useState<HealthRecord[]>([])
  const [productions, setProductions] = useState<ProductionRecord[]>([])
  const [flocks, setFlocks] = useState<Flock[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [refreshing, setRefreshing] = useState(false)

  const [flockFilter, setFlockFilter] = useState("ALL")
  const [ledgerTypeFilter, setLedgerTypeFilter] = useState("ALL")
  const [ledgerDescriptionFilter, setLedgerDescriptionFilter] = useState("")
  const [ledgerDateFrom, setLedgerDateFrom] = useState("")
  const [ledgerDateTo, setLedgerDateTo] = useState("")
  const [ledgerSortKey, setLedgerSortKey] = useState<string | null>("date")
  const [ledgerSortDir, setLedgerSortDir] = useState<SortDirection>("desc")
  const [ledgerPage, setLedgerPage] = useState(1)

  const [photoDialogOpen, setPhotoDialogOpen] = useState(false)
  const [photoMedicationName, setPhotoMedicationName] = useState("")
  const [photoFlockId, setPhotoFlockId] = useState("")
  const [photoRecordDate, setPhotoRecordDate] = useState("")
  const [photoCaption, setPhotoCaption] = useState("")
  const [photoFile, setPhotoFile] = useState<File | null>(null)
  const [photoExistingPath, setPhotoExistingPath] = useState<string | null>(null)
  const [photoReceiptRemoved, setPhotoReceiptRemoved] = useState(false)
  const [photoSaving, setPhotoSaving] = useState(false)
  const [photoDialogError, setPhotoDialogError] = useState("")
  const [photoExistingDbRecordId, setPhotoExistingDbRecordId] = useState<number | null>(null)

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  const loadData = useCallback(async () => {
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) {
      setError("Farm ID or User ID not found")
      setLoading(false)
      setRefreshing(false)
      return
    }
    const [healthRes, prodRes, flocksRes] = await Promise.all([
      getHealthRecords(userId, farmId),
      getProductionRecords(userId, farmId),
      getFlocks(userId, farmId),
    ])

    if (healthRes.success && healthRes.data) {
      const raw = healthRes.data as unknown
      const arr = Array.isArray(raw) ? raw : []
      const list = arr.map((row) => normalizeHealthRecord(row as Record<string, unknown>))
      setRecords(list)
      setError("")
    } else {
      setRecords([])
      setError(healthRes.message || "Failed to load health records")
    }

    if (prodRes.success && prodRes.data) setProductions(prodRes.data)
    else setProductions([])

    if (flocksRes.success && flocksRes.data) setFlocks(flocksRes.data)
    else setFlocks([])

    setLoading(false)
    setRefreshing(false)
  }, [])

  useEffect(() => {
    void loadData()
  }, [loadData])

  const flockIdForLedger = useMemo(() => {
    if (flockFilter === "ALL") return null
    const id = parseInt(flockFilter, 10)
    return Number.isFinite(id) ? id : null
  }, [flockFilter])

  const medStockLedger = useMemo(
    () => buildMedicationStockLedger(records, productions, flocks, { flockId: flockIdForLedger }),
    [records, productions, flocks, flockIdForLedger]
  )
  const {
    rows: medLedgerAllRows,
    byProduct: medByProduct,
    medicationUnitsAtHand,
    lastUpdatedIso,
    totalInUnits,
    totalOutUnits,
  } = medStockLedger

  const latestMedicationPhotos = useMemo(() => getLatestMedicationPhotoByProductKey(records), [records])

  const medicationPhotosNotInBalanceTable = useMemo(() => {
    const keys = new Set(medByProduct.map((p) => p.key))
    return [...latestMedicationPhotos.values()].filter((info) => !keys.has(info.productKey))
  }, [latestMedicationPhotos, medByProduct])

  const distinctLedgerTypes = useMemo(() => {
    const set = new Set(medLedgerAllRows.map((r) => r.type))
    return [...set].sort()
  }, [medLedgerAllRows])

  const filteredMedLedgerRows = useMemo(() => {
    let list = [...medLedgerAllRows]
    if (ledgerTypeFilter !== "ALL") list = list.filter((r) => r.type === ledgerTypeFilter)
    if (ledgerDescriptionFilter.trim()) {
      const q = ledgerDescriptionFilter.trim().toLowerCase()
      list = list.filter((r) => r.description.toLowerCase().includes(q))
    }
    if (ledgerDateFrom) list = list.filter((r) => toLocalDateKey(r.date) >= ledgerDateFrom)
    if (ledgerDateTo) list = list.filter((r) => toLocalDateKey(r.date) <= ledgerDateTo)
    return list
  }, [medLedgerAllRows, ledgerTypeFilter, ledgerDescriptionFilter, ledgerDateFrom, ledgerDateTo])

  const sortedMedLedgerRows = useMemo(
    () =>
      sortData(filteredMedLedgerRows, ledgerSortKey, ledgerSortDir, (item: MedicationLedgerRow, key: string) => {
        if (key === "date") return new Date(item.date)
        if (key === "type") return item.type
        if (key === "description") return item.description
        if (key === "in") return Number(item.in) || 0
        if (key === "out") return Number(item.out) || 0
        if (key === "balance") return Number(item.balance) || 0
        return (item as MedicationLedgerRow & Record<string, unknown>)[key]
      }),
    [filteredMedLedgerRows, ledgerSortKey, ledgerSortDir]
  )

  const ledgerTotalPages = Math.max(1, Math.ceil(sortedMedLedgerRows.length / LEDGER_PAGE_SIZE))
  const ledgerSafePage = Math.min(ledgerPage, ledgerTotalPages)
  const paginatedMedLedgerRows = useMemo(
    () =>
      sortedMedLedgerRows.slice((ledgerSafePage - 1) * LEDGER_PAGE_SIZE, ledgerSafePage * LEDGER_PAGE_SIZE),
    [sortedMedLedgerRows, ledgerSafePage]
  )

  useEffect(() => {
    setLedgerPage(1)
  }, [ledgerTypeFilter, ledgerDescriptionFilter, ledgerDateFrom, ledgerDateTo, ledgerSortKey, ledgerSortDir, flockFilter])

  const handleLedgerSort = (key: string) => {
    const r = toggleSort(key, ledgerSortKey, ledgerSortDir)
    setLedgerSortKey(r.key)
    setLedgerSortDir(r.direction)
  }

  const clearLedgerFilters = () => {
    setFlockFilter("ALL")
    setLedgerTypeFilter("ALL")
    setLedgerDescriptionFilter("")
    setLedgerDateFrom("")
    setLedgerDateTo("")
    setLedgerSortKey("date")
    setLedgerSortDir("desc")
    setLedgerPage(1)
    toast({ title: "Filters cleared" })
  }

  const handleCopyAtHand = () => {
    navigator.clipboard.writeText(String(Math.round((medicationUnitsAtHand + Number.EPSILON) * 100) / 100))
    toast({ title: "Copied", description: "Medication left / at hand (dose units) copied" })
  }

  const ledgerLastUpdated = lastUpdatedIso ? new Date(lastUpdatedIso) : null

  const handleRefresh = () => {
    setRefreshing(true)
    void loadData()
  }

  const openMedicationPhotoDialog = (prefillLabel: string) => {
    const label = primaryLabelFromText(prefillLabel).trim()
    setPhotoMedicationName(label)
    setPhotoCaption("")
    setPhotoFile(null)
    setPhotoReceiptRemoved(false)
    const key = normalizeProductKey(label)
    const existing = key ? latestMedicationPhotos.get(key) : undefined
    setPhotoExistingPath(existing?.path ?? null)
    setPhotoExistingDbRecordId(existing?.hasAttachmentImage ? existing.healthRecordId : null)
    const firstFlock = flocks[0]?.flockId
    setPhotoFlockId(firstFlock != null ? String(firstFlock) : "")
    setPhotoRecordDate(new Date().toISOString().split("T")[0])
    setPhotoDialogError("")
    setPhotoDialogOpen(true)
  }

  const deleteMedicationPhotoRecordsForKey = async (productKey: string, userId: string, farmId: string) => {
    const toRemove = listMedicationPhotoInfos(records).filter((i) => i.productKey === productKey)
    for (const info of toRemove) {
      const res = await deleteHealthRecord(info.healthRecordId, userId, farmId)
      if (!res.success) throw new Error(res.message || "Failed to remove old medication photo")
    }
  }

  const handleMedicationPhotoSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setPhotoDialogError("")
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      setPhotoDialogError("Sign in again to save.")
      return
    }
    const medLabel = primaryLabelFromText(photoMedicationName).trim()
    if (!medLabel) {
      setPhotoDialogError("Enter the medication name as it should appear in your records.")
      return
    }
    const productKey = normalizeProductKey(medLabel)
    if (!photoFlockId) {
      setPhotoDialogError("Select a flock for this reference entry.")
      return
    }

    if (photoReceiptRemoved && !photoFile) {
      setPhotoSaving(true)
      try {
        await deleteMedicationPhotoRecordsForKey(productKey, userId, farmId)
        toast({ title: "Photo removed", description: "Medication reference photo was deleted." })
        setPhotoDialogOpen(false)
        await loadData()
      } catch (err) {
        setPhotoDialogError(err instanceof Error ? err.message : "Could not remove photo")
      } finally {
        setPhotoSaving(false)
      }
      return
    }

    if (!photoFile && (photoExistingPath || photoExistingDbRecordId) && !photoReceiptRemoved) {
      setPhotoDialogOpen(false)
      return
    }

    if (!photoFile) {
      setPhotoDialogError("Choose a JPEG, PNG, or WebP image (max 4 MB), or remove the current photo.")
      return
    }

    setPhotoSaving(true)
    try {
      const attachmentImageBase64 = await fileToBase64DataOnly(photoFile)
      const attachmentContentType = photoFile.type || "image/jpeg"
      await deleteMedicationPhotoRecordsForKey(productKey, userId, farmId)
      const notes = buildMedicationPhotoNotesDb(photoCaption || undefined)
      const created = await createHealthRecord({
        userId,
        farmId,
        flockId: Number(photoFlockId),
        houseId: null,
        itemId: null,
        recordDate: `${photoRecordDate}T00:00:00Z`,
        vaccination: null,
        medication: medLabel,
        waterConsumption: null,
        notes,
        attachmentImageBase64,
        attachmentContentType,
      })
      if (!created.success) {
        setPhotoDialogError(created.message || "Could not save health record for photo")
        setPhotoSaving(false)
        return
      }
      toast({ title: "Photo saved", description: "Medication picture is stored in the database with this health record." })
      setPhotoDialogOpen(false)
      await loadData()
    } catch (err) {
      setPhotoDialogError(err instanceof Error ? err.message : "Save failed")
    } finally {
      setPhotoSaving(false)
    }
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-violet-100 rounded-lg flex items-center justify-center">
                  <Pill className="w-5 h-5 text-violet-800" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Medication at hand / Medication left</h1>
                  <p className="text-sm text-slate-600">
                    <strong>Medication left</strong> (same idea as medication at hand) is the running difference:{" "}
                    <strong>IN − OUT</strong>. <strong>IN</strong> = health records (medication / medication-type notes).{" "}
                    <strong>OUT</strong> = production records (medication field). Dose uses the first number in the text when
                    present; otherwise one unit per row.
                  </p>
                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm">
                    <Link href="/health" className="text-blue-600 hover:underline font-medium">
                      Health records (IN)
                    </Link>
                    <Link href="/production-records" className="text-blue-600 hover:underline font-medium">
                      Production records (OUT)
                    </Link>
                  </div>
                </div>
              </div>
              <Button
                type="button"
                variant="outline"
                className="shrink-0 gap-2"
                onClick={handleRefresh}
                disabled={refreshing || loading}
              >
                <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
                Refresh
              </Button>
            </div>

            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}

            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center text-slate-600">Loading medication left…</CardContent>
              </Card>
            ) : (
              <>
                <Card className="border-violet-200 bg-violet-50/40">
                  <CardHeader className="pb-2">
                    <CardDescription>Medication left · Medication at hand</CardDescription>
                    <CardTitle className="text-base font-semibold text-slate-800 mt-1">IN − OUT = dose units on hand</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <div className={cn("flex gap-4 flex-wrap", isMobile ? "flex-col" : "items-start justify-between")}>
                      <div className={cn("grid gap-4", isMobile ? "grid-cols-1" : "grid-cols-3")}>
                        <div>
                          <div className="text-xs font-medium uppercase tracking-wide text-slate-500">
                            Medication left / at hand
                          </div>
                          <div className="mt-1 flex items-center gap-2 flex-wrap">
                            <span
                              className={cn(
                                "text-2xl font-bold tabular-nums",
                                medicationUnitsAtHand < 0 ? "text-red-600" : "text-slate-900"
                              )}
                            >
                              {medicationUnitsAtHand.toLocaleString(undefined, { maximumFractionDigits: 2 })}
                            </span>
                            <span className="text-sm text-slate-500">dose units</span>
                            <Button
                              type="button"
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8 text-slate-500 hover:text-slate-700"
                              onClick={handleCopyAtHand}
                              aria-label="Copy medication at hand"
                            >
                              <Copy className="h-4 w-4" />
                            </Button>
                          </div>
                        </div>
                        <div>
                          <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total IN</div>
                          <div className="mt-1 text-2xl font-bold tabular-nums text-emerald-800">
                            {totalInUnits.toLocaleString(undefined, { maximumFractionDigits: 2 })}
                          </div>
                        </div>
                        <div>
                          <div className="text-xs font-medium uppercase tracking-wide text-slate-500">Total OUT</div>
                          <div className="mt-1 text-2xl font-bold tabular-nums text-slate-800">
                            {totalOutUnits.toLocaleString(undefined, { maximumFractionDigits: 2 })}
                          </div>
                        </div>
                      </div>
                      <div className="text-sm text-slate-500 shrink-0">
                        Last ledger event:{" "}
                        {ledgerLastUpdated
                          ? ledgerLastUpdated.toLocaleDateString("en-GB", {
                              day: "2-digit",
                              month: "short",
                              year: "numeric",
                            })
                          : "—"}
                      </div>
                    </div>
                    <p className="text-xs text-slate-500 mt-2">
                      Include numeric amounts in health and production medication text for more accurate totals (e.g. &quot;5
                      ml&quot;).
                    </p>
                    {medicationUnitsAtHand < 0 && (
                      <p className="text-xs text-amber-900 mt-2 rounded-md border border-amber-200 bg-amber-100/80 px-2 py-1.5">
                        Negative balance often means production medication was logged more than health intake — check entries and
                        dose parsing.
                      </p>
                    )}
                  </CardContent>
                </Card>

                <Card className="bg-white border-violet-100">
                  <CardHeader className="pb-2">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                      <div>
                        <CardTitle className="text-base">By medication</CardTitle>
                        <CardDescription>
                          Balance per product (dose units) from the same ledger. <strong>Finished</strong> means the running total
                          for that name is zero or below — time to restock or check entries. Use <strong>Pack photo</strong> to
                          attach a picture of the bottle, label, or invoice (stored in the database with the health record; it
                          does not change stock totals).
                        </CardDescription>
                      </div>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        className="shrink-0 gap-2"
                        onClick={() => openMedicationPhotoDialog("")}
                      >
                        <ImageIcon className="h-4 w-4" />
                        Add medication photo
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {medByProduct.length === 0 ? (
                      <p className="text-sm text-slate-600 py-2">
                        No medication products in the ledger yet. Add medication on health records (IN) and production (OUT).
                      </p>
                    ) : (
                      <div className="overflow-x-auto table-scroll-wrapper pb-1">
                        <Table className="w-full min-w-[560px]">
                          <TableHeader>
                            <TableRow>
                              <TableHead>Medication</TableHead>
                              <TableHead className="w-[140px]">Pack photo</TableHead>
                              <TableHead className="text-right">Balance</TableHead>
                              <TableHead className="text-right w-[120px]">Status</TableHead>
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {medByProduct.map((p) => {
                              const shot = latestMedicationPhotos.get(p.key)
                              const recordId = shot?.healthRecordId
                              const { userId: u, farmId: f } = getUserContext()
                              const tryAuthImage = Boolean(recordId && u && f)
                              const href = shot?.path ? toReceiptViewUrl(shot.path, f) : null
                              const hasAnyImage = tryAuthImage || Boolean(href)
                              return (
                              <TableRow key={p.key}>
                                <TableCell className="font-medium text-slate-900">{p.label}</TableCell>
                                <TableCell className="align-top">
                                  <div className="flex flex-col gap-2 min-w-[112px]">
                                    {tryAuthImage && recordId ? (
                                      <div className="inline-block rounded-md border bg-white overflow-hidden">
                                        <AuthenticatedHealthImage
                                          healthRecordId={recordId}
                                          userId={u}
                                          farmId={f}
                                          legacyFallbackSrc={href}
                                          className="h-14 w-14 object-cover"
                                          fallbackClassName="h-14 w-14"
                                        />
                                      </div>
                                    ) : href ? (
                                      <a
                                        href={href}
                                        target="_blank"
                                        rel="noopener noreferrer"
                                        className="inline-block rounded-md border bg-white overflow-hidden"
                                      >
                                        {/* eslint-disable-next-line @next/next/no-img-element */}
                                        <img
                                          src={href}
                                          alt=""
                                          className="h-14 w-14 object-cover"
                                        />
                                      </a>
                                    ) : (
                                      <div className="h-14 w-14 rounded-md border border-dashed border-slate-200 bg-slate-50 flex items-center justify-center">
                                        <ImageIcon className="h-6 w-6 text-slate-300" aria-hidden />
                                      </div>
                                    )}
                                    <Button
                                      type="button"
                                      variant="outline"
                                      size="sm"
                                      className="h-8 text-xs"
                                      onClick={() => openMedicationPhotoDialog(p.label)}
                                    >
                                      {hasAnyImage ? "Change" : "Add photo"}
                                    </Button>
                                  </div>
                                </TableCell>
                                <TableCell className="text-right tabular-nums">
                                  {p.balance.toLocaleString(undefined, { maximumFractionDigits: 2 })}
                                </TableCell>
                                <TableCell className="text-right">
                                  {p.depleted ? (
                                    <Badge variant="secondary" className="bg-slate-200 text-slate-800">
                                      Finished
                                    </Badge>
                                  ) : (
                                    <Badge variant="outline" className="border-emerald-300 text-emerald-800 bg-emerald-50">
                                      In stock
                                    </Badge>
                                  )}
                                </TableCell>
                              </TableRow>
                              )
                            })}
                          </TableBody>
                        </Table>
                      </div>
                    )}
                    {medicationPhotosNotInBalanceTable.length > 0 && (
                      <div className="mt-4 pt-4 border-t border-slate-100">
                        <p className="text-sm font-medium text-slate-800 mb-2">Pack photos (not in balance list above)</p>
                        <ul className="flex flex-wrap gap-3">
                          {medicationPhotosNotInBalanceTable.map((info) => {
                            const { userId: u, farmId: f } = getUserContext()
                            const tryAuthImage = Boolean(info.healthRecordId && u && f)
                            const href = info.path ? toReceiptViewUrl(info.path, f) : null
                            return (
                              <li
                                key={info.healthRecordId}
                                className="flex items-center gap-2 rounded-lg border bg-slate-50/80 px-2 py-1.5 text-sm"
                              >
                                <span className="font-medium text-slate-800 max-w-[160px] truncate" title={info.productLabel}>
                                  {info.productLabel}
                                </span>
                                {tryAuthImage ? (
                                  <div className="inline-flex rounded border bg-white overflow-hidden shrink-0">
                                    <AuthenticatedHealthImage
                                      healthRecordId={info.healthRecordId}
                                      userId={u}
                                      farmId={f}
                                      legacyFallbackSrc={href}
                                      className="h-10 w-10 object-cover"
                                      fallbackClassName="h-10 w-10"
                                    />
                                  </div>
                                ) : href ? (
                                  <a
                                    href={href}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="inline-flex rounded border bg-white overflow-hidden shrink-0"
                                  >
                                    {/* eslint-disable-next-line @next/next/no-img-element */}
                                    <img src={href} alt="" className="h-10 w-10 object-cover" />
                                  </a>
                                ) : null}
                                <Button
                                  type="button"
                                  variant="ghost"
                                  size="sm"
                                  className="h-8 text-xs"
                                  onClick={() => openMedicationPhotoDialog(info.productLabel)}
                                >
                                  Edit
                                </Button>
                              </li>
                            )
                          })}
                        </ul>
                      </div>
                    )}
                  </CardContent>
                </Card>

                <Card className="bg-white" id="medication-ledger">
                  <CardHeader>
                    <CardTitle>Medication stock ledger</CardTitle>
                    <CardDescription>
                      Each row updates the running total: <strong>balance = IN − OUT</strong> (dose units). Filter the table
                      below.
                    </CardDescription>
                    <div className={cn("grid gap-2 pt-3", isMobile ? "grid-cols-1" : "grid-cols-2 lg:grid-cols-6")}>
                      <Select value={flockFilter} onValueChange={setFlockFilter}>
                        <SelectTrigger>
                          <SelectValue placeholder="Flock" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All flocks</SelectItem>
                          {flocks.map((f) => (
                            <SelectItem key={f.flockId} value={String(f.flockId)}>
                              {f.name || `Flock #${f.flockId}`}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Select value={ledgerTypeFilter} onValueChange={setLedgerTypeFilter}>
                        <SelectTrigger>
                          <SelectValue placeholder="Type" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="ALL">All types</SelectItem>
                          {distinctLedgerTypes.map((t) => (
                            <SelectItem key={t} value={t}>
                              {t}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Input
                        placeholder="Description…"
                        value={ledgerDescriptionFilter}
                        onChange={(e) => setLedgerDescriptionFilter(e.target.value)}
                        className={cn(isMobile ? "" : "lg:col-span-2")}
                      />
                      <Input type="date" value={ledgerDateFrom} onChange={(e) => setLedgerDateFrom(e.target.value)} aria-label="From date" />
                      <Input type="date" value={ledgerDateTo} onChange={(e) => setLedgerDateTo(e.target.value)} aria-label="To date" />
                    </div>
                    <div className="pt-2">
                      <Button type="button" variant="outline" size="sm" onClick={clearLedgerFilters}>
                        Reset ledger filters
                      </Button>
                    </div>
                  </CardHeader>
                  <CardContent className="pt-0">
                    {sortedMedLedgerRows.length === 0 ? (
                      <p className="text-slate-600 py-8 text-center text-sm">
                        No ledger rows yet. Log medication on <strong>Health</strong> (IN) and on <strong>Production</strong>{" "}
                        records (OUT).
                      </p>
                    ) : (
                      <div className="overflow-x-auto table-scroll-wrapper pb-2" style={{ WebkitOverflowScrolling: "touch" }}>
                        <Table className="w-full min-w-[720px]">
                          <TableHeader>
                            <TableRow>
                              <SortableHeader
                                label="Date"
                                sortKey="date"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                              />
                              <SortableHeader
                                label="Type"
                                sortKey="type"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                              />
                              <SortableHeader
                                label="Description"
                                sortKey="description"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                              />
                              <SortableHeader
                                label="In"
                                sortKey="in"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                              <SortableHeader
                                label="Out"
                                sortKey="out"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                              <SortableHeader
                                label="Balance"
                                sortKey="balance"
                                currentSort={ledgerSortKey}
                                currentDirection={ledgerSortDir}
                                onSort={handleLedgerSort}
                                className="text-right"
                              />
                            </TableRow>
                          </TableHeader>
                          <TableBody>
                            {paginatedMedLedgerRows.map((row) => (
                              <TableRow key={row.sortKey}>
                                <TableCell className="font-medium whitespace-nowrap text-sm">
                                  {row.date ? formatDateShort(row.date) : "—"}
                                </TableCell>
                                <TableCell className="text-sm">{row.type}</TableCell>
                                <TableCell className="max-w-[280px] truncate text-sm" title={row.description}>
                                  {row.description}
                                </TableCell>
                                <TableCell className="text-right text-emerald-600 tabular-nums text-sm">
                                  {row.in > 0 ? row.in.toLocaleString(undefined, { maximumFractionDigits: 2 }) : "—"}
                                </TableCell>
                                <TableCell className="text-right text-red-600 tabular-nums text-sm">
                                  {row.out > 0 ? row.out.toLocaleString(undefined, { maximumFractionDigits: 2 }) : "—"}
                                </TableCell>
                                <TableCell className="text-right font-medium tabular-nums text-sm">
                                  {row.balance.toLocaleString(undefined, { maximumFractionDigits: 2 })}
                                </TableCell>
                              </TableRow>
                            ))}
                          </TableBody>
                        </Table>
                      </div>
                    )}
                    {sortedMedLedgerRows.length > 0 && (
                      <div className="flex flex-col gap-2 border-t px-2 py-3 sm:flex-row sm:items-center sm:justify-between sm:px-4 bg-slate-50/80">
                        <p className="text-xs text-slate-600 text-center sm:text-left">
                          Showing {(ledgerSafePage - 1) * LEDGER_PAGE_SIZE + 1}-
                          {Math.min(ledgerSafePage * LEDGER_PAGE_SIZE, sortedMedLedgerRows.length)} of {sortedMedLedgerRows.length}
                        </p>
                        <div className="flex items-center justify-center gap-2">
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            disabled={ledgerSafePage <= 1}
                            onClick={() => setLedgerPage((p) => Math.max(1, p - 1))}
                          >
                            Previous
                          </Button>
                          <span className="text-xs text-slate-600 whitespace-nowrap">
                            Page {ledgerSafePage} of {ledgerTotalPages}
                          </span>
                          <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            disabled={ledgerSafePage >= ledgerTotalPages}
                            onClick={() => setLedgerPage((p) => Math.min(ledgerTotalPages, p + 1))}
                          >
                            Next
                          </Button>
                        </div>
                      </div>
                    )}
                  </CardContent>
                </Card>
              </>
            )}
          </div>
        </main>

        <Dialog
          open={photoDialogOpen}
          onOpenChange={(open) => {
            setPhotoDialogOpen(open)
            if (!open) setPhotoDialogError("")
          }}
        >
          <DialogContent className="max-w-lg max-h-[90vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <ImageIcon className="h-5 w-5 text-violet-600" />
                Medication pack photo
              </DialogTitle>
              <DialogDescription>
                Upload a picture of the label, bottle, or pack. The image is stored in your farm database (not on the web
                server disk) so it keeps working after deploys. It does not change dose totals on this page.
              </DialogDescription>
            </DialogHeader>
            <form onSubmit={handleMedicationPhotoSubmit} className="space-y-4 pt-2">
              {photoDialogError && (
                <Alert variant="destructive">
                  <AlertDescription>{photoDialogError}</AlertDescription>
                </Alert>
              )}
              <div className="space-y-2">
                <Label htmlFor="med-photo-name">Medication name *</Label>
                <Input
                  id="med-photo-name"
                  value={photoMedicationName}
                  onChange={(e) => setPhotoMedicationName(e.target.value)}
                  placeholder="e.g. Amoxicillin 500mg"
                  disabled={photoSaving}
                  required
                />
                <p className="text-xs text-slate-500">
                  Match the name used in health or production records when possible so the photo lines up with the same product.
                </p>
              </div>
              <div className="space-y-2">
                <Label>Flock *</Label>
                <Select value={photoFlockId} onValueChange={setPhotoFlockId} disabled={photoSaving || flocks.length === 0}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select flock" />
                  </SelectTrigger>
                  <SelectContent>
                    {flocks.map((f) => (
                      <SelectItem key={f.flockId} value={String(f.flockId)}>
                        {f.name || `Flock #${f.flockId}`}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="med-photo-date">Reference date</Label>
                <Input
                  id="med-photo-date"
                  type="date"
                  value={photoRecordDate}
                  onChange={(e) => setPhotoRecordDate(e.target.value)}
                  disabled={photoSaving}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="med-photo-caption">Short caption (optional)</Label>
                <Textarea
                  id="med-photo-caption"
                  rows={2}
                  value={photoCaption}
                  onChange={(e) => setPhotoCaption(e.target.value)}
                  disabled={photoSaving}
                  placeholder="Batch number, supplier, expiry…"
                />
              </div>
              {photoExistingDbRecordId && !photoReceiptRemoved && !photoFile && (
                <div className="rounded-lg border border-slate-200 bg-slate-50 p-2 inline-block max-w-full">
                  <p className="text-xs text-slate-500 mb-2">Current photo (saved in database)</p>
                  <AuthenticatedHealthImage
                    healthRecordId={photoExistingDbRecordId}
                    userId={getUserContext().userId}
                    farmId={getUserContext().farmId}
                    className="max-h-56 max-w-full rounded object-contain"
                  />
                </div>
              )}
              <ExpenseReceiptField
                existingPath={photoReceiptRemoved || photoFile ? null : photoExistingDbRecordId ? null : photoExistingPath}
                resolveReceiptFarmId={getUserContext().farmId}
                pendingFile={photoFile}
                onPendingFileChange={setPhotoFile}
                onRemoveExisting={() => {
                  setPhotoReceiptRemoved(true)
                  setPhotoExistingPath(null)
                  setPhotoExistingDbRecordId(null)
                }}
                disabled={photoSaving}
              />
              <div className="flex justify-end gap-2 pt-2 border-t">
                <Button type="button" variant="outline" onClick={() => setPhotoDialogOpen(false)} disabled={photoSaving}>
                  Cancel
                </Button>
                <Button type="submit" disabled={photoSaving || flocks.length === 0}>
                  {photoSaving ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Saving…
                    </>
                  ) : (
                    "Save photo"
                  )}
                </Button>
              </div>
            </form>
          </DialogContent>
        </Dialog>
      </div>
    </div>
  )
}
