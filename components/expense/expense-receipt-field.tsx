"use client"

import { useId, useRef, useState, useEffect, useCallback } from "react"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Camera, ImageIcon, X } from "lucide-react"
import { cn } from "@/lib/utils"
import { toReceiptViewUrl } from "@/lib/utils/expense-receipt"
import { AuthenticatedExpenseImage } from "@/components/expense/authenticated-expense-image"

const RECEIPT_MAX_BYTES = 4 * 1024 * 1024
const RECEIPT_ACCEPT = "image/jpeg,image/png,image/webp"
const RECEIPT_MIME_TYPES = new Set(["image/jpeg", "image/png", "image/webp"])

function validateReceiptFile(file: File): string | null {
  if (!RECEIPT_MIME_TYPES.has(file.type)) {
    return "Use a JPEG, PNG, or WebP image."
  }
  if (file.size > RECEIPT_MAX_BYTES) {
    return "Image must be 4 MB or smaller."
  }
  return null
}

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
  /** Field label (default: Receipt photo) */
  label?: string
  /** Show "Take photo" for device camera (default: true) */
  showCaptureOption?: boolean
}

export function ExpenseReceiptField({
  existingPath,
  resolveReceiptFarmId,
  dbAttachment,
  pendingFile,
  onPendingFileChange,
  onRemoveExisting,
  disabled,
  label = "Receipt photo (optional)",
  showCaptureOption = true,
}: ExpenseReceiptFieldProps) {
  const inputId = useId()
  const uploadInputRef = useRef<HTMLInputElement>(null)
  const cameraInputRef = useRef<HTMLInputElement>(null)
  const [localPreview, setLocalPreview] = useState<string | null>(null)
  const [imgFailed, setImgFailed] = useState(false)
  const [fileError, setFileError] = useState<string | null>(null)

  const applySelectedFile = useCallback(
    (file: File | null) => {
      setFileError(null)
      if (!file) {
        onPendingFileChange(null)
        return
      }
      const err = validateReceiptFile(file)
      if (err) {
        setFileError(err)
        return
      }
      onPendingFileChange(file)
    },
    [onPendingFileChange]
  )

  const onFileInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      applySelectedFile(e.target.files?.[0] ?? null)
      e.target.value = ""
    },
    [applySelectedFile]
  )

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

  const hasPreview = Boolean(previewSrc || showDbPreview)

  return (
    <div className="space-y-2">
      <Label htmlFor={inputId} className="text-sm font-medium text-slate-700">
        {label}
      </Label>
      <p className="text-xs text-slate-500">
        JPEG, PNG, or WebP, up to 4 MB.
        {showCaptureOption
          ? " Upload from your device, or take a photo with the camera (works best on phones and tablets)."
          : " Saved with this record for your files."}
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <input
          ref={uploadInputRef}
          id={inputId}
          type="file"
          accept={RECEIPT_ACCEPT}
          className="hidden"
          disabled={disabled}
          onChange={onFileInputChange}
        />
        {showCaptureOption && (
          <input
            ref={cameraInputRef}
            type="file"
            accept={RECEIPT_ACCEPT}
            capture="environment"
            className="hidden"
            disabled={disabled}
            onChange={onFileInputChange}
            aria-label="Take photo with camera"
          />
        )}
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={disabled}
          className="gap-2"
          onClick={() => uploadInputRef.current?.click()}
        >
          <ImageIcon className="h-4 w-4" />
          {hasPreview ? "Replace image" : "Upload image"}
        </Button>
        {showCaptureOption && (
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={disabled}
            className="gap-2"
            onClick={() => cameraInputRef.current?.click()}
          >
            <Camera className="h-4 w-4" />
            Take photo
          </Button>
        )}
        {pendingFile && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="text-slate-600"
            disabled={disabled}
            onClick={() => applySelectedFile(null)}
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
      {fileError && (
        <p className="text-xs text-red-600" role="alert">
          {fileError}
        </p>
      )}
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
