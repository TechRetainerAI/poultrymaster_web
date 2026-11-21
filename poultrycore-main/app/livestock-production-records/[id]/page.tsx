"use client"

// Full-page EDIT production record, like poultry's /production-records/[id]:
// the record opens straight into the same form the Add page and the modal use,
// every section shown, with Close at the top. Save and Cancel go back to the
// list. Delete is on the list row.
//
// /livestock-production-records/[id]/edit redirects here.

import { useCallback, useEffect, useState } from "react"
import { useParams, useRouter } from "next/navigation"
import { ClipboardList, X } from "lucide-react"
import { Button } from "@/components/ui/button"
import { getProductionRecord, type ProductionRecord } from "@/lib/api/livestock"
import { LivestockPage, LoadError, Loading, fmtDate } from "@/components/livestock/livestock-page"
import { ProductionRecordForm } from "@/components/livestock/production-record-form"

export default function LivestockProductionRecordPage() {
  const { id } = useParams<{ id: string }>()
  const recordId = Number(id)
  const router = useRouter()
  const [r, setR] = useState<ProductionRecord | null>(null)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setError(null)
    try { setR(await getProductionRecord(recordId)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [recordId])
  useEffect(() => { if (Number.isFinite(recordId) && recordId > 0) load(); else setError("That production record could not be found.") }, [load, recordId])

  const toList = () => router.push("/livestock-production-records")

  return (
    <LivestockPage
      title="Edit Production Record"
      description={r ? <>{r.groupName} · {r.speciesName} · {fmtDate(r.date)}{r.createdBy && ` · recorded by ${r.createdBy}`}{r.updatedBy && ` · last changed by ${r.updatedBy}`}</> : "Update production record details"}
      icon={ClipboardList}
      actions={<Button size="sm" className="gap-1.5 bg-red-600 text-white hover:bg-red-700" onClick={toList}><X className="h-4 w-4" /> Close</Button>}
    >
      {error ? <LoadError message={error} onRetry={Number.isFinite(recordId) && recordId > 0 ? load : undefined} />
        : !r ? <Loading />
        : <ProductionRecordForm key={r.recordId} record={r} onSaved={toList} onCancel={toList} />}
    </LivestockPage>
  )
}
