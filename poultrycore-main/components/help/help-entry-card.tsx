"use client"

import Link from "next/link"
import { useState } from "react"
import { Check, ChevronDown, ChevronUp, ExternalLink, Link2 } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent } from "@/components/ui/card"
import { cn } from "@/lib/utils"
import { highlightRuns } from "@/lib/help/help-search"
import type { HelpEntry } from "@/lib/help/help-types"

export interface HelpTone {
  rail: string
  badge: string
}

const KIND_LABEL = { faq: "Question", fix: "Troubleshooting", term: "Glossary" } as const

/** Text with the searched words picked out. */
export function Highlighted({ text, matched }: { text: string; matched: string[] }) {
  return (
    <>
      {highlightRuns(text, matched).map((r, i) =>
        r.hit ? <mark key={i} className="rounded bg-amber-100 px-0.5 text-inherit">{r.text}</mark> : <span key={i}>{r.text}</span>,
      )}
    </>
  )
}

/**
 * An answer body: paragraphs split on blank lines; a paragraph of "1. " lines
 * is a numbered list and one of "- " lines a bulleted list. Plain text in, so
 * the content file stays readable and nothing in it can inject markup.
 */
export function HelpBody({ body, matched }: { body: string; matched: string[] }) {
  return (
    <div className="space-y-2.5">
      {body.split(/\n\s*\n/).map((para, i) => {
        const lines = para.split("\n").map((l) => l.trim()).filter(Boolean)
        if (lines.length > 0 && lines.every((l) => /^\d+\.\s/.test(l))) {
          return (
            <ol key={i} className="space-y-1.5">
              {lines.map((l, j) => (
                <li key={j} className="flex gap-2.5">
                  <span className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-indigo-100 text-[11px] font-semibold text-indigo-700">
                    {j + 1}
                  </span>
                  <span><Highlighted text={l.replace(/^\d+\.\s/, "")} matched={matched} /></span>
                </li>
              ))}
            </ol>
          )
        }
        if (lines.length > 0 && lines.every((l) => l.startsWith("- "))) {
          return (
            <ul key={i} className="list-disc space-y-1 pl-5">
              {lines.map((l, j) => <li key={j}><Highlighted text={l.slice(2)} matched={matched} /></li>)}
            </ul>
          )
        }
        return <p key={i}><Highlighted text={lines.join(" ")} matched={matched} /></p>
      })}
    </div>
  )
}

export function HelpEntryCard({
  entry, tone, open, onToggle, matched = [], canOpen, showKind = false, flash = false,
}: {
  entry: HelpEntry
  tone: HelpTone
  open: boolean
  onToggle: () => void
  matched?: string[]
  /** Whether this user may open a linked page. Links they may not are hidden. */
  canOpen: (href: string) => boolean
  /** In search results, say whether this is a question, a fix or a term. */
  showKind?: boolean
  /** Briefly ring the card -- it is the one a shared link pointed at. */
  flash?: boolean
}) {
  const [copied, setCopied] = useState(false)
  const links = (entry.links ?? []).filter((l) => canOpen(l.href))

  const copyLink = async () => {
    const url = `${window.location.origin}/help#${entry.id}`
    try {
      await navigator.clipboard.writeText(url)
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    } catch {
      window.location.hash = entry.id
    }
  }

  return (
    <Card
      id={entry.id}
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
            {/* The badges sit ABOVE the question on a phone: inline, they took
                half the width and left the question wrapping in a two-word
                column. */}
            <div className="min-w-0 flex-1">
              <div className="mb-1.5 flex flex-wrap gap-1">
                {showKind && (
                  <Badge variant="outline" className="border-slate-200 bg-white text-[10px] font-medium text-slate-500">
                    {KIND_LABEL[entry.kind]}
                  </Badge>
                )}
                <Badge variant="outline" className={`text-[10px] font-medium ${tone.badge}`}>
                  {entry.category}
                </Badge>
              </div>
              <div className="font-medium text-slate-900"><Highlighted text={entry.title} matched={matched} /></div>
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
            <div className="border-t border-slate-100 pt-3 text-sm leading-relaxed text-slate-600">
              <HelpBody body={entry.body} matched={matched} />
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
                aria-label="Copy a link to this answer"
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
