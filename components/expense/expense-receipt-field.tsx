"use client"

import { useId, useRef, useState, useEffect } from "react"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { ImageIcon, X } from "lucide-react"
import { cn } from "@/lib/utils"
import { toReceiptViewUrl } from "@/lib/utils/expense-receipt"
import { AuthenticatedExpenseImage } from "@/components/expense/authenticated-expense-image"

export type ExpenseDbAttachmentPreview = {
  expenseId: number
  userId: string
  farmId: string
}

type ExpenseReceiptFieldProps = {
  /** Legacy receipt path embedded in description (public URL) */
  existingPath: string | null
  /** Farm id for resolving mistaken paths like `/uuid.png` → `receipt-uploads/{farmId}/uuid.png` */
  resolveReceiptFarmId?: string | null
  /** Receipt bytes on expense row — preview via authenticated API */
  dbAttachment?: ExpenseDbAttachmentPreview | null
  /** New file chosen by user (not yet uploaded) */
  pendingFile: File | null
  onPendingFileChange: (file: File | null) => void
  /** When user removes an already-saved receipt (edit form) */
  onRemoveExisting?: () => void
  disabled?: boolean
}

export function ExpenseReceiptField({
  existingPath,
  resolveReceiptFarmId,
  dbAttachment,
  pendingFile,
  onPendingFileChange,
  onRemoveExisting,
  disabled,
}: ExpenseReceiptFieldProps) {
  const inputId = useId()
  const inputRef = useRef<HTMLInputElement>(null)
  const [localPreview, setLocalPreview] = useState<string | null>(null)
  const [imgFailed, setImgFailed] = useState(false)

  useEffect(() => {
    if (!pendingFile) {
      setLocalPreview(null)
      return
    }
    const url = URL.createObjectURL(pendingFile)
    setLocalPreview(url)
    return () => URL.revokeObjectURL(url)
  }, [pendingFile])

  useEffect(() => {
    setImgFailed(false)
  }, [existingPath, dbAttachment, pendingFile, localPreview])

  const showLegacyFile = Boolean(existingPath && !pendingFile && !dbAttachment)
  const existingViewUrl =
    showLegacyFile && existingPath
      ? toReceiptViewUrl(existingPath, resolveReceiptFarmId) ?? existingPath
      : null
  const previewSrc = pendingFile ? localPreview : existingViewUrl
  const showDbPreview = Boolean(dbAttachment && !pendingFile)
  const showRemoveSaved = Boolean((existingPath || dbAttachment) && !pendingFile)

  return (
    <div className="space-y-2">
      <Label htmlFor={inputId} className="text-sm font-medium text-slate-700">
        Receipt photo (optional)
      </Label>
      <p className="text-xs text-slate-500">
        JPEG, PNG, or WebP, up to 4 MB. Saved with this expense for your records.
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <input
          ref={inputRef}
          id={inputId}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="hidden"
          disabled={disabled}
          onChange={(e) => {
            const f = e.target.files?.[0] ?? null
            onPendingFileChange(f)
            e.target.value = ""
          }}
        />
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={disabled}
          className="gap-2"
          onClick={() => inputRef.current?.click()}
        >
          <ImageIcon className="h-4 w-4" />
          {previewSrc || showDbPreview ? "Replace image" : "Upload receipt"}
        </Button>
        {pendingFile && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="text-slate-600"
            disabled={disabled}
            onClick={() => onPendingFileChange(null)}
          >
            <X className="h-4 w-4 mr-1" />
            Clear new image
          </Button>
        )}
        {showRemoveSaved && onRemoveExisting && (
          <Button type="button" variant="ghost" size="sm" disabled={disabled} onClick={onRemoveExisting}>
            <X className="h-4 w-4 mr-1" />
            Remove saved receipt
          </Button>
        )}
      </div>
      {showDbPreview && dbAttachment && (
        <div
          className={cn(
            "mt-2 rounded-lg border border-slate-200 bg-slate-50 p-2 inline-block max-w-full",
            disabled && "opacity-60"
          )}
        >
          <AuthenticatedExpenseImage
            expenseId={dbAttachment.expenseId}
            userId={dbAttachment.userId}
            farmId={dbAttachment.farmId}
            alt="Receipt preview"
            className="max-h-56 max-w-full rounded object-contain"
            fallbackClassName="h-14 w-full max-w-sm"
          />
        </div>
      )}
      {previewSrc && !imgFailed && (
        <div
          className={cn(
            "mt-2 rounded-lg border border-slate-200 bg-slate-50 p-2 inline-block max-w-full",
            disabled && "opacity-60"
          )}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={previewSrc}
            alt="Receipt preview"
            className="max-h-56 max-w-full rounded object-contain"
            onError={() => setImgFailed(true)}
          />
        </div>
      )}
      {showLegacyFile && imgFailed && (
        <p className="mt-2 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-md px-2 py-1.5 max-w-md">
          Receipt file could not be loaded (it may be missing on the server after a deploy). Re-upload a photo or remove the saved receipt.
        </p>
      )}
    </div>
  )
}
