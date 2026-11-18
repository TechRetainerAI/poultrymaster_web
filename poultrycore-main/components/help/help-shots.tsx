"use client"

import { useState } from "react"
import { ChevronLeft, ChevronRight, ZoomIn } from "lucide-react"
import { Dialog, DialogContent, DialogDescription, DialogTitle } from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import type { HelpShot } from "@/lib/help/help-types"

/**
 * The picture walkthrough under an answer: numbered screenshots, each with its
 * caption, tap to see it full size. The highlighted box in each picture is
 * burned in by the capture script, so it survives being shared on WhatsApp.
 */
export function HelpShots({ shots, title }: { shots: HelpShot[]; title: string }) {
  const [open, setOpen] = useState<number | null>(null)
  if (shots.length === 0) return null

  const current = open === null ? null : shots[open]
  const go = (d: number) => setOpen((i) => (i === null ? i : (i + d + shots.length) % shots.length))

  return (
    <div className="mt-4 border-t border-slate-100 pt-3">
      <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">See how, step by step</div>
      <ol className="space-y-4">
        {shots.map((s, i) => (
          <li key={s.src}>
            <div className="mb-1.5 flex gap-2.5 text-sm text-slate-700">
              <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-indigo-600 text-[11px] font-semibold text-white">
                {i + 1}
              </span>
              <span>{s.caption}</span>
            </div>
            <button
              type="button"
              onClick={() => setOpen(i)}
              className="group relative block w-full overflow-hidden rounded-lg border border-slate-200 bg-slate-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-indigo-400"
              aria-label={`Enlarge step ${i + 1}: ${s.caption}`}
            >
              {/* eslint-disable-next-line @next/next/no-img-element -- static, pre-sized JPEGs; next/image adds nothing here */}
              <img
                src={s.src}
                alt={s.caption}
                width={s.width}
                height={s.height}
                loading="lazy"
                decoding="async"
                className="h-auto w-full"
              />
              <span className="absolute right-2 top-2 inline-flex items-center gap-1 rounded-md bg-slate-900/70 px-2 py-1 text-[11px] text-white opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100">
                <ZoomIn className="h-3 w-3" /> Enlarge
              </span>
            </button>
          </li>
        ))}
      </ol>

      <Dialog open={open !== null} onOpenChange={(o) => !o && setOpen(null)}>
        <DialogContent className="w-[96vw] max-w-6xl p-3 sm:p-4">
          {current && open !== null && (
            <>
              <DialogTitle className="pr-8 text-sm font-medium">
                {title}: step {open + 1} of {shots.length}
              </DialogTitle>
              <DialogDescription className="text-sm text-slate-600">{current.caption}</DialogDescription>
              <div className="max-h-[75vh] overflow-auto rounded-md border border-slate-200">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={current.src} alt={current.caption} width={current.width} height={current.height} className="h-auto w-full" />
              </div>
              {shots.length > 1 && (
                <div className="flex justify-between">
                  <Button variant="outline" size="sm" onClick={() => go(-1)}><ChevronLeft className="mr-1 h-4 w-4" />Previous</Button>
                  <Button variant="outline" size="sm" onClick={() => go(1)}>Next<ChevronRight className="ml-1 h-4 w-4" /></Button>
                </div>
              )}
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}
