"use client"

// Quick look at a flock's lifetime performance, in the house read-modal
// pattern (max-w-2xl, stacked sections). The body is FlockLifetimeView, the
// same component the full page (/flock-closeout/[flockId]) renders, so the two
// can never disagree -- the header links across to it.

import { useEffect, useState } from "react"
import Link from "next/link"
import { BarChart3, ExternalLink } from "lucide-react"
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { FlockLifetimeView } from "@/components/poultry/flock-lifetime-view"

interface Props {
  flockId: number | null
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Shows the Reopen action (poultry.flock-closeout.approve). */
  canReopen?: boolean
  onReopened?: () => void
}

export function FlockLifetimeDialog({ flockId, open, onOpenChange, canReopen = false, onReopened }: Props) {
  const [name, setName] = useState<string | null>(null)
  useEffect(() => { if (open) setName(null) }, [open, flockId])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto bg-slate-50">
        <DialogHeader>
          <DialogTitle className="flex flex-wrap items-center gap-2 pr-6">
            <BarChart3 className="h-5 w-5 text-slate-600" /> {name ?? "Flock"} — lifetime performance
            {flockId != null && (
              <Button asChild variant="outline" size="sm" className="ml-auto h-7">
                <Link href={`/flock-closeout/${flockId}`}>
                  <ExternalLink className="h-3.5 w-3.5 mr-1" /> Open full page
                </Link>
              </Button>
            )}
          </DialogTitle>
          <DialogDescription>
            Everything this flock produced, earned and cost. Only costs that belong to the flock are counted:
            feed and medication issued to it, its share of the batch's bird cost, and expenses tagged to it.
          </DialogDescription>
        </DialogHeader>

        {/* Mounted only while open, so every opening is a fresh read. */}
        {open && (
          <FlockLifetimeView
            flockId={flockId}
            layout="dialog"
            canReopen={canReopen}
            onReopened={onReopened}
            onLoaded={(s) => setName(s?.flockName ?? null)}
          />
        )}

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Close</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
