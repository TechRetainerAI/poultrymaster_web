"use client"

// The wide production record modal — the default Add/Edit experience.
//
// It is chrome ONLY: a sticky header, a scrolling body, a sticky footer with a
// live summary, and the guards around leaving. Every field, calculation and
// validation lives in <ProductionRecordForm>, which the full-page routes render
// too. That is what keeps the two from drifting apart again.

import { useCallback, useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Dialog, DialogContent, DialogTitle, DialogDescription } from "@/components/ui/dialog"
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import { Button } from "@/components/ui/button"
import { Egg, Loader2, Maximize2, X } from "lucide-react"
import { cn } from "@/lib/utils"
import type { ProductionRecord } from "@/lib/api/production-record"
import { ProductionRecordForm, type ProductionRecordFormState } from "./production-record-form"

const FORM_ID = "production-record-form"

export interface ProductionRecordModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Present = edit; absent = create. */
  record?: ProductionRecord | null
  /** Pre-selects the flock when creating. */
  flockId?: number | null
  onSaved?: () => void
}

export function ProductionRecordModal({
  open, onOpenChange, record, flockId, onSaved,
}: ProductionRecordModalProps) {
  const router = useRouter()
  const isEdit = !!record
  const [state, setState] = useState<ProductionRecordFormState | null>(null)
  // "close" = discard and shut; "fullpage" = discard and navigate.
  const [confirming, setConfirming] = useState<null | "close" | "fullpage">(null)

  // Reset the lifted state between openings, or a stale summary flashes in the
  // footer before the fresh form reports its own.
  useEffect(() => { if (!open) setState(null) }, [open])

  const dirty = state?.dirty ?? false
  const saving = state?.saving ?? false
  const loading = state?.loading ?? false

  const fullPageHref = isEdit
    ? `/production-records/${record!.id}`
    : `/production-records/new${flockId != null ? `?flockId=${flockId}` : ""}`

  const requestClose = useCallback(() => {
    if (dirty) { setConfirming("close"); return }
    onOpenChange(false)
  }, [dirty, onOpenChange])

  const requestFullPage = useCallback(() => {
    if (dirty) { setConfirming("fullpage"); return }
    onOpenChange(false)
    router.push(fullPageHref)
  }, [dirty, onOpenChange, router, fullPageHref])

  const confirmDiscard = () => {
    const action = confirming
    setConfirming(null)
    onOpenChange(false)
    if (action === "fullpage") router.push(fullPageHref)
  }

  const contextLine = [
    state?.flockName,
    state?.date ? new Date(state.date).toLocaleDateString() : null,
  ].filter(Boolean).join(" • ")

  const s = state?.summary

  return (
    <>
      <Dialog
        open={open}
        onOpenChange={(next) => { if (!next) requestClose(); else onOpenChange(true) }}
      >
        <DialogContent
          // Wide, tall, and internally scrolled. p-0 because the sticky header
          // and footer own their own padding.
          className={cn(
            "flex max-h-[90vh] w-[92vw] max-w-[1100px] flex-col gap-0 overflow-hidden p-0",
            "sm:max-w-[1100px]",
          )}
          // A long form with real data must not be dismissable by a stray click
          // outside it. Escape still works, and goes through the same guard.
          onPointerDownOutside={(e) => e.preventDefault()}
          onInteractOutside={(e) => e.preventDefault()}
          onEscapeKeyDown={(e) => { e.preventDefault(); requestClose() }}
          showCloseButton={false}
        >
          {/* -------------------------------------------- sticky header */}
          <div className="flex shrink-0 items-start justify-between gap-2 border-b border-emerald-200 bg-gradient-to-r from-emerald-100 to-emerald-50/40 px-3 py-3 sm:gap-3 sm:px-5 sm:py-3.5">
            <div className="flex min-w-0 items-center gap-3">
              <span className="hidden h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-emerald-600 text-white shadow-sm sm:flex">
                <Egg className="h-4 w-4" />
              </span>
              <div className="min-w-0">
                <DialogTitle className="text-sm leading-tight font-semibold text-slate-900 sm:text-base">
                  {isEdit ? "Edit Production Record" : "Add Production Record"}
                </DialogTitle>
                <DialogDescription className="mt-0.5 truncate text-xs text-slate-500">
                  {contextLine || (isEdit ? "Update production data" : "Record daily egg production data for a flock")}
                </DialogDescription>
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-1.5">
            {/* The label collapses to its icon below `sm`. A 130px button
                next to a shrink-0 close button left the title about 120px on a
                phone, which is what wrapped "Add Production Record" onto three
                lines. The icon alone still opens the full page, and the label
                comes back as soon as there is room for it. */}
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={requestFullPage}
                className="px-2 sm:px-3"
                title="Open full page"
                aria-label="Open full page"
              >
                <Maximize2 className="h-3.5 w-3.5 sm:mr-1.5" />
                <span className="hidden sm:inline">Open Full Page</span>
              </Button>
              <Button type="button" variant="ghost" size="icon" onClick={requestClose} aria-label="Close">
                <X className="h-4 w-4" />
              </Button>
            </div>
          </div>

          {/* ---------------------------------------------- scroll body */}
          <div className="min-h-0 flex-1 overflow-y-auto bg-slate-50 px-5 py-4">
            {open && (
              <ProductionRecordForm
                mode={isEdit ? "edit" : "create"}
                displayMode="modal"
                formId={FORM_ID}
                recordId={record?.id}
                record={record ?? null}
                flockId={flockId ?? null}
                hideActions
                onStateChange={setState}
                onSaved={() => { onOpenChange(false); onSaved?.() }}
              />
            )}
          </div>

          {/* -------------------------------------------- sticky footer */}
          <div className="flex shrink-0 flex-wrap items-center justify-between gap-3 border-t bg-white px-5 py-3">
            <div className="flex min-w-0 flex-wrap items-center gap-x-4 gap-y-1 text-xs text-slate-500">
              {s && !loading ? (
                <>
                  <Stat label="Total eggs" value={s.totalEggs.toLocaleString()} />
                  <Stat label="Crates" value={`${s.totalCrates} + ${s.totalPieces}`} />
                  <Stat label="Net sellable" value={s.netSellableEggs.toLocaleString()} tone="good" />
                  <Stat label="Deaths" value={s.deaths.toLocaleString()} tone={s.deaths > 0 ? "bad" : undefined} />
                  <Stat label="Birds left" value={s.birdsLeft.toLocaleString()} tone={s.birdsLeft < 0 ? "bad" : undefined} />
                  <Stat label="Feed cost" value={s.feedCost.toFixed(2)} />
                </>
              ) : null}
            </div>
            {/* shrink-0 on a fixed row clips the primary off the right edge of a
                narrow phone. Cancel keeps its natural width and the primary
                takes the rest of the row. */}
            <div className="grid w-full shrink-0 grid-cols-[auto_1fr] gap-2 sm:flex sm:w-auto sm:items-center">
              <Button type="button" variant="outline" onClick={requestClose} disabled={saving} className="w-full sm:w-auto">
                Cancel
              </Button>
              <Button type="submit" form={FORM_ID} disabled={saving || loading} className="w-full sm:w-auto">
                {saving && <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />}
                {isEdit ? "Update Production Record" : "Save Production Record"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      <AlertDialog open={confirming !== null} onOpenChange={(o) => { if (!o) setConfirming(null) }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>You have unsaved changes</AlertDialogTitle>
            <AlertDialogDescription>
              {confirming === "fullpage"
                ? "Opening the full page will discard the changes you have made here."
                : "Are you sure you want to close this form? Your changes will be lost."}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Stay</AlertDialogCancel>
            <AlertDialogAction onClick={confirmDiscard}>
              {confirming === "fullpage" ? "Discard and continue" : "Discard changes"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </>
  )
}

function Stat({ label, value, tone }: { label: string; value: string; tone?: "good" | "bad" }) {
  return (
    <span className="whitespace-nowrap">
      {label}{" "}
      <b className={cn(
        "tabular-nums",
        tone === "good" ? "text-emerald-700" : tone === "bad" ? "text-rose-700" : "text-slate-900",
      )}>{value}</b>
    </span>
  )
}
