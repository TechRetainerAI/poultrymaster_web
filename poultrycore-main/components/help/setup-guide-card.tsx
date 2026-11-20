"use client"

import Link from "next/link"
import { useState } from "react"
import { Check, ChevronDown, ChevronUp, ExternalLink, Images, Link2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent } from "@/components/ui/card"
import { cn } from "@/lib/utils"
import type { HelpEntry, HelpShot } from "@/lib/help/help-types"
import { Highlighted } from "./help-entry-card"
import { HelpShots } from "./help-shots"
import type { HelpTone } from "./help-entry-card"

/**
 * One picture walkthrough on the Setup Guide page, behaving like a Help
 * Center answer card: open by default with every step showing, folded to its
 * title when tapped.
 *
 * Self-contained on purpose: it renders the shots itself rather than through
 * HelpEntryCard, so the Help Center can drop its pictures without taking them
 * off this page.
 */
export function SetupGuideCard({
  guide, shots, tone, open, onToggle, matched = [], canOpen, flash = false,
}: {
  guide: HelpEntry
  shots: HelpShot[]
  tone: HelpTone
  open: boolean
  onToggle: () => void
  matched?: string[]
  /** Whether this user may open a linked page. Links they may not are hidden. */
  canOpen: (href: string) => boolean
  flash?: boolean
}) {
  const [copied, setCopied] = useState(false)
  const links = (guide.links ?? []).filter((l) => canOpen(l.href))

  const copyLink = async () => {
    const url = `${window.location.origin}/poultry-setup-guide#${guide.id}`
    try {
      await navigator.clipboard.writeText(url)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      window.location.hash = guide.id
    }
  }

  return (
    <Card
      id={guide.id}
      className={cn(
        "scroll-mt-24 border-l-4 transition-all",
        tone.rail,
        open && "shadow-sm",
        flash && "ring-2 ring-indigo-400 ring-offset-2",
      )}
    >
      <CardContent className="p-0">
        <button
          className="w-full rounded-xl px-4 py-4 text-left transition-colors hover:bg-slate-50 sm:px-5"
          onClick={onToggle}
          aria-expanded={open}
        >
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0 flex-1">
              <div className="mb-1.5 flex flex-wrap gap-1">
                <Badge variant="outline" className={`text-[10px] font-medium ${tone.badge}`}>
                  {guide.category}
                </Badge>
                <Badge variant="outline" className="gap-1 border-slate-200 bg-white text-[10px] font-medium text-slate-500">
                  <Images className="h-3 w-3" /> {shots.length} {shots.length === 1 ? "picture" : "pictures"}
                </Badge>
              </div>
              <div className="font-medium text-slate-900"><Highlighted text={guide.title} matched={matched} /></div>
            </div>
            {open ? (
              <ChevronUp className="mt-0.5 h-5 w-5 shrink-0 text-slate-400" />
            ) : (
              <ChevronDown className="mt-0.5 h-5 w-5 shrink-0 text-slate-400" />
            )}
          </div>
        </button>

        {open && (
          <div className="px-4 pb-4 pt-0 sm:px-5">
            <div className="text-sm leading-relaxed text-slate-600">
              <HelpShots shots={shots} title={guide.title} />
            </div>
            <div className="mt-3 flex flex-wrap items-center gap-2">
              {links.map((l) => (
                <Link
                  key={l.href}
                  href={l.href}
                  className="inline-flex items-center gap-1 rounded-md border border-indigo-200 bg-indigo-50 px-2.5 py-1 text-xs font-medium text-indigo-700 hover:bg-indigo-100"
                >
                  {l.label}
                  <ExternalLink className="h-3 w-3" />
                </Link>
              ))}
              <button
                type="button"
                onClick={copyLink}
                className="ml-auto inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs text-slate-500 hover:bg-slate-100 hover:text-slate-700"
                aria-label="Copy a link to this guide"
              >
                {copied ? <Check className="h-3.5 w-3.5 text-emerald-600" /> : <Link2 className="h-3.5 w-3.5" />}
                {copied ? "Link copied" : "Copy link"}
              </button>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
