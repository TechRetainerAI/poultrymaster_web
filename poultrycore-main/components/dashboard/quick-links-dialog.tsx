"use client"

/**
 * Choose what sits in your own Quick Links bar (migration 318).
 *
 * WHAT IT OFFERS IS THE RAIL ITSELF
 * =================================
 * The catalogue is built from the nav config that is already on screen, so it
 * lists exactly the pages this user can reach and nothing else. That is not a
 * convenience: it is what keeps a shortcut bar from becoming a way around a
 * permission. See lib/nav/quick-links.ts.
 *
 * ORDER FOLLOWS THE CATALOGUE, NOT THE ORDER OF TICKING
 * =====================================================
 * Ticking Cash Flow before Sales does not put Cash Flow first. The stored
 * array carries an order and the backend keeps it, so per-user ordering is a
 * drag handle away -- but a bar that silently reordered itself according to
 * which box you happened to tick first is a worse default than one that reads
 * down the rail the way every other menu does.
 *
 * SAVE IS EXPLICIT
 * ================
 * Nothing is written until Save. The bar is something a reader relies on
 * finding unchanged, and a picker that applied every tick live would rearrange
 * the page under someone who opened it to look.
 */

import { useEffect, useMemo, useState } from "react"
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Checkbox } from "@/components/ui/checkbox"
import { Loader2, RotateCcw, Search, Star } from "lucide-react"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { quickLinkCatalogue, type CustomisableNav, type QuickLinkChoice } from "@/lib/nav/quick-links"
import { useQuickLinksStore } from "@/lib/store/quick-links-store"

/** 318 enforces this too. The dialog says so before the server has to. */
const MAX_LINKS = 20

export function QuickLinksDialog({
  open, onOpenChange, nav,
}: {
  open: boolean
  onOpenChange: (o: boolean) => void
  /** The nav config already on screen — gated, and the source of the catalogue. */
  nav: CustomisableNav
}) {
  const { toast } = useToast()
  const stored = useQuickLinksStore((s) => s.hrefs)
  const save = useQuickLinksStore((s) => s.save)
  const reset = useQuickLinksStore((s) => s.reset)

  const catalogue = useMemo(() => quickLinkCatalogue(nav), [nav])
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [search, setSearch] = useState("")
  const [busy, setBusy] = useState(false)

  // Reopening re-reads the truth. A dialog that kept the selection it had when
  // it was last closed would quietly offer to save a stale bar.
  useEffect(() => {
    if (!open) return
    setSearch("")
    setPicked(new Set(stored ?? nav.quickLinks.items.map((i) => i.href)))
  }, [open, stored, nav])

  const groups = useMemo(() => {
    const q = search.trim().toLowerCase()
    const out = new Map<string, QuickLinkChoice[]>()
    for (const c of catalogue) {
      if (q && !c.label.toLowerCase().includes(q) && !c.href.toLowerCase().includes(q)) continue
      const list = out.get(c.group) ?? []
      list.push(c)
      out.set(c.group, list)
    }
    return [...out.entries()]
  }, [catalogue, search])

  const toggle = (href: string) => {
    setPicked((prev) => {
      const next = new Set(prev)
      if (next.has(href)) next.delete(href)
      else if (next.size >= MAX_LINKS) {
        toast({
          title: `That is ${MAX_LINKS} links`,
          description: "Remove one before adding another — a bar this long is not a shortcut.",
          variant: "destructive",
        })
        return prev
      } else next.add(href)
      return next
    })
  }

  // Catalogue order, not tick order. See the note at the top of this file.
  const inOrder = () => catalogue.filter((c) => picked.has(c.href)).map((c) => c.href)

  const run = async (fn: () => Promise<void>, ok: string) => {
    setBusy(true)
    try {
      await fn()
      toast({ title: ok })
      onOpenChange(false)
    } catch (e: any) {
      toast({ title: "That did not save", description: e?.message ?? String(e), variant: "destructive" })
    } finally {
      setBusy(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-2xl">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Star className="h-5 w-5 text-amber-500" /> Your Quick Links
          </DialogTitle>
          <DialogDescription>
            Pick the pages you open most. This is yours alone, and it applies to this
            company — switch company and you get that one&apos;s bar.
          </DialogDescription>
        </DialogHeader>

        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
          <Input value={search} onChange={(e) => setSearch(e.target.value)}
                 placeholder="Find a page…" className="pl-8 h-11 sm:h-10" />
        </div>

        {/* Its own scroll box, so the header, the count and the buttons stay
            put while a rail's worth of pages moves under them. */}
        <div className="max-h-[50vh] min-w-0 overflow-y-auto rounded-md border border-slate-200">
          {groups.length === 0 ? (
            <p className="p-4 text-sm text-slate-500">No page matches “{search}”.</p>
          ) : (
            groups.map(([group, items]) => (
              <div key={group} className="border-b border-slate-100 last:border-b-0">
                <div className="sticky top-0 bg-slate-50 px-3 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
                  {group}
                </div>
                {items.map((c) => {
                  const on = picked.has(c.href)
                  const Icon = c.icon
                  return (
                    <label key={c.href}
                           className={cn("flex cursor-pointer items-center gap-3 px-3 py-2.5 text-sm hover:bg-slate-50",
                                         on && "bg-amber-50/60")}>
                      <Checkbox checked={on} onCheckedChange={() => toggle(c.href)} />
                      <Icon className="h-4 w-4 shrink-0 text-slate-400" />
                      <span className="min-w-0 flex-1 break-words text-slate-900">{c.label}</span>
                      <span className="hidden shrink-0 text-xs text-slate-400 sm:inline">{c.href}</span>
                    </label>
                  )
                })}
              </div>
            ))
          )}
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-slate-500">
          <span>{picked.size} of {MAX_LINKS} chosen</span>
          {picked.size === 0 && <span>An empty bar is allowed — the menu stays hidden.</span>}
        </div>

        <div className="flex flex-col-reverse gap-2 pt-2 sm:flex-row sm:justify-between">
          {/* Reset DELETES the choice rather than saving today's defaults, so a
              shortcut added to the product later still reaches this user. */}
          <Button variant="ghost" disabled={busy} className="h-11 sm:h-10"
                  onClick={() => void run(reset, "Back to the default Quick Links")}>
            <RotateCcw className="h-4 w-4 mr-1" /> Reset to defaults
          </Button>
          <div className="flex flex-col-reverse gap-2 sm:flex-row">
            <Button variant="outline" disabled={busy} className="h-11 sm:h-10"
                    onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button disabled={busy} className="h-11 sm:h-10"
                    onClick={() => void run(() => save(inOrder()), "Quick Links saved")}>
              {busy && <Loader2 className="h-4 w-4 mr-1 animate-spin" />} Save
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  )
}
