"use client"

import { useCallback, useEffect, useState } from "react"
import { useParams } from "next/navigation"
import { ClipboardList } from "lucide-react"
import { getProductionRecord, type ProductionRecord } from "@/lib/api/livestock"
import { LivestockPage, LoadError, Loading, fmtDate } from "@/components/livestock/livestock-page"
import { ProductionRecordForm } from "@/components/livestock/production-record-form"

export default function EditLivestockProductionRecordPage() {
  const { id } = useParams<{ id: string }>()
  const recordId = Number(id)
  const [r, setR] = useState<ProductionRecord | null>(null)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setError(null)
    try { setR(await getProductionRecord(recordId)) } catch (e: any) { setError(e?.message ?? String(e)) }
  }, [recordId])
  useEffect(() => { load() }, [load])

  return (
    <LivestockPage
      title={r ? `Edit ${r.groupName} · ${fmtDate(r.date)}` : "Edit daily record"}
      icon={ClipboardList}
      back={{ href: `/livestock-production-records/${recordId}`, label: "Back to the record" }}
    >
      {error ? <LoadError message={error} onRetry={load} /> : !r ? <Loading /> : <ProductionRecordForm record={r} />}
    </LivestockPage>
  )
}
