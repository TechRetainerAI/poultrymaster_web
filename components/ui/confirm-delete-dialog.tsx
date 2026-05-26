'use client'

import * as React from 'react'
import { Loader2 } from 'lucide-react'

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import { buttonVariants } from '@/components/ui/button'
import { useToast } from '@/hooks/use-toast'
import { cn } from '@/lib/utils'

type ConfirmDeleteDialogProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  title?: string
  description?: React.ReactNode
  itemLabel?: string
  confirmLabel?: string
  cancelLabel?: string
  successTitle?: string
  successDescription?: string
  errorTitle?: string
  onConfirm: () => Promise<unknown> | unknown
  onSuccess?: () => void
}

function extractErrorMessage(err: unknown, fallback: string): string {
  if (!err) return fallback
  if (typeof err === 'string') return tryParseJsonMessage(err) ?? err
  if (typeof err === 'object') {
    const e = err as {
      message?: unknown
      response?: { data?: { message?: unknown; title?: unknown } }
    }
    const apiMsg = e?.response?.data?.message ?? e?.response?.data?.title
    if (typeof apiMsg === 'string' && apiMsg.trim()) return apiMsg
    if (typeof e.message === 'string' && e.message.trim()) {
      return tryParseJsonMessage(e.message) ?? e.message
    }
  }
  return fallback
}

/**
 * The water/generic API helpers throw `new Error("POST /path -> 500 {json}")`
 * with the Farm API's JSON error body appended. Pull the `message` field out
 * so the toast shows "Only Approved batches can be reopened" instead of the
 * full HTTP envelope.
 */
function tryParseJsonMessage(s: string): string | null {
  const start = s.indexOf('{')
  if (start === -1) return null
  try {
    const obj = JSON.parse(s.slice(start)) as { message?: unknown; title?: unknown }
    const m = obj?.message ?? obj?.title
    return typeof m === 'string' && m.trim() ? m : null
  } catch {
    return null
  }
}

export function ConfirmDeleteDialog({
  open,
  onOpenChange,
  title = 'Delete this item?',
  description,
  itemLabel,
  confirmLabel = 'Delete',
  cancelLabel = 'Cancel',
  successTitle = 'Deleted',
  successDescription,
  errorTitle = 'Delete failed',
  onConfirm,
  onSuccess,
}: ConfirmDeleteDialogProps) {
  const { toast } = useToast()
  const [isDeleting, setIsDeleting] = React.useState(false)

  const resolvedDescription =
    description ??
    (itemLabel
      ? `Are you sure you want to delete "${itemLabel}"? This action cannot be undone.`
      : 'This action cannot be undone.')

  async function handleConfirm(e: React.MouseEvent) {
    e.preventDefault()
    setIsDeleting(true)
    try {
      const result = await onConfirm()
      if (result && typeof result === 'object' && 'success' in result) {
        const r = result as { success: boolean; message?: string }
        if (!r.success) {
          toast({
            title: errorTitle,
            description: r.message ?? 'Something went wrong. Please try again.',
            variant: 'destructive',
          })
          return
        }
      }
      if (successTitle) {
        toast({ title: successTitle, description: successDescription })
      }
      onSuccess?.()
      onOpenChange(false)
    } catch (err) {
      toast({
        title: errorTitle,
        description: extractErrorMessage(err, 'Something went wrong. Please try again.'),
        variant: 'destructive',
      })
    } finally {
      setIsDeleting(false)
    }
  }

  return (
    <AlertDialog
      open={open}
      onOpenChange={(next) => {
        if (isDeleting) return
        onOpenChange(next)
      }}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{resolvedDescription}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel
            disabled={isDeleting}
            className={cn(
              buttonVariants({ variant: 'outline' }),
              'bg-background text-foreground hover:bg-accent',
            )}
          >
            {cancelLabel}
          </AlertDialogCancel>
          <AlertDialogAction
            onClick={handleConfirm}
            disabled={isDeleting}
            className={cn(buttonVariants({ variant: 'destructive' }))}
          >
            {isDeleting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Deleting…
              </>
            ) : (
              confirmLabel
            )}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  )
}
