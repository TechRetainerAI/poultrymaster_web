"use client"

// The wide Add / Edit production record modal -- the default way in from the
// list, as on the poultry Production Records page. Chrome only: every field
// lives in <ProductionRecordForm>, which the full-page routes render too.

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { ClipboardList, Maximize2, X } from "lucide-react"
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { getProductionRecord, type ProductionRecord } from "@/lib/api/livestock"
import { ProductionRecordForm } from "./production-record-form"
import { LoadError, Loading } from "./livestock-page"

export function LivestockProductionRecordModal({ open, onOpenChange, recordId, presetGroupId, onSaved }: {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Present = edit. */
  recordId?: number | null
  presetGroupId?: number | null
  onSaved?: () => void
}) {
  const router = useRouter()
  const isEdit = recordId != null
  const [record, setRecord] = useState<ProductionRecord | null>(null)
  const [error, setError] = useState<string | null>(null)

  // The list rows may not carry every line, so an edit loads the full record.
  useEffect(() => {
    if (!open || !isEdit) { setRecord(null); setError(null); return }
    let live = true
    getProductionRecord(recordId!).then((r) => { if (live) setRecord(r) }).catch((e) => { if (live) setError(e?.message ?? String(e)) })
    return () => { live = false }
  }, [open, isEdit, recordId])

  const fullPage = isEdit
    ? `/livestock-production-records/${recordId}`
    : `/livestock-production-records/new${presetGroupId ? `?groupId=${presetGroupId}` : ""}`

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent
        className="flex max-h-[90vh] w-[92vw] max-w-[1100px] flex-col gap-0 overflow-hidden p-0 sm:max-w-[1100px]"
        onPointerDownOutside={(e) => e.preventDefault()}
        onInteractOutside={(e) => e.preventDefault()}
        showCloseButton={false}
      >
        <div className="flex shrink-0 items-start justify-between gap-2 border-b border-amber-200 bg-gradient-to-r from-amber-100 to-amber-50/40 px-3 py-3 sm:px-5">
          <div className="flex min-w-0 items-center gap-3">
            <span className="hidden h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-amber-700 text-white shadow-sm sm:flex">
              <ClipboardList className="h-4 w-4" />
            </span>
            <div className="min-w-0">
              <DialogTitle className="text-sm font-semibold text-slate-900 sm:text-base">
                {isEdit ? "Edit Production Record" : "Add Production Record"}
              </DialogTitle>
              <DialogDescription className="mt-0.5 truncate text-xs text-slate-500">
                {record ? `${record.groupName} · ${new Date(record.date + "T00:00:00").toLocaleDateString()}` : "A group's day: produce, deaths, feed and medicine"}
              </DialogDescription>
            </div>
          </div>
          <div className="flex shrink-0 items-center gap-1.5">
            <Button type="button" variant="outline" size="sm" className="px-2 sm:px-3" title="Open full page"
              onClick={() => { onOpenChange(false); router.push(fullPage) }}>
              <Maximize2 className="h-3.5 w-3.5 sm:mr-1.5" /><span className="hidden sm:inline">Open Full Page</span>
            </Button>
            <Button type="button" variant="ghost" size="icon" aria-label="Close" onClick={() => onOpenChange(false)}><X className="h-4 w-4" /></Button>
          </div>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto bg-slate-50 px-3 py-4 sm:px-5">
          {open && (isEdit
            ? (error ? <LoadError message={error} /> : !record ? <Loading /> : (
              <ProductionRecordForm key={record.recordId} record={record}
                onSaved={() => { onOpenChange(false); onSaved?.() }} onCancel={() => onOpenChange(false)} />
            ))
            : (
              <ProductionRecordForm presetGroupId={presetGroupId ?? null}
                onSaved={() => { onOpenChange(false); onSaved?.() }} onCancel={() => onOpenChange(false)} />
            ))}
        </div>
      </DialogContent>
    </Dialog>
  )
}
