"use client"

// The company's business timezone, for the three Setup pages.
//
// WHY THIS IS A SELF-CONTAINED FIELD AND NOT PART OF THE SETUP FORM
// ================================================================
// The three setup pages each own a `form` object that is saved in one go by
// their own submit handler. The timezone deliberately does NOT join that object:
// it lives on `farms`, not on the vertical's profile table, and it is written by
// its own stored procedure, which validates the id and flips
// `timezoneconfirmed`. Folding it into the page's save would mean triplicating
// that call and three chances to get the confirmation flag wrong.
//
// So this component loads and saves itself, and the surrounding form does not
// know it exists beyond dropping it in a grid cell.
//
// WHY IT NAGS
// ===========
// Migration 298 gave every existing company a timezone GUESSED from its
// currency, marked `timeZoneConfirmed = false`. The guess is right for the 83
// Ghanaian companies and is a coin toss for anyone else. The amber note below is
// the only thing in the platform that asks a human to look — without it the flag
// is just a column nobody ever reads.

import { useEffect, useState } from "react"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Globe, Check, AlertTriangle } from "lucide-react"
import {
  getCompanyTimeContext,
  getCompanyTimeZones,
  setCompanyTimeZone,
  type CompanyTimeContext,
  type CompanyTimeZoneOption,
} from "@/lib/api/company-time"

export function CompanyTimeZoneField({ className }: { className?: string }) {
  const [ctx, setCtx] = useState<CompanyTimeContext | null>(null)
  const [zones, setZones] = useState<CompanyTimeZoneOption[]>([])
  const [selected, setSelected] = useState<string>("")
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState("")
  const [justSaved, setJustSaved] = useState(false)

  useEffect(() => {
    let cancelled = false
    Promise.all([getCompanyTimeContext(), getCompanyTimeZones()])
      .then(([c, z]) => {
        if (cancelled) return
        setCtx(c)
        setSelected(c.timeZoneId)
        setZones(z)
      })
      .catch((e) => {
        if (!cancelled) setError(e?.message ?? "Could not load the company timezone.")
      })
    return () => {
      cancelled = true
    }
  }, [])

  const save = async () => {
    if (!selected) return
    setSaving(true)
    setError("")
    setJustSaved(false)
    try {
      const r = await setCompanyTimeZone(selected)
      setCtx((prev) =>
        prev
          ? {
              ...prev,
              timeZoneId: r.timeZoneId,
              timeZoneConfirmed: r.timeZoneConfirmed,
              businessDate: r.businessDate,
            }
          : prev,
      )
      setJustSaved(true)
    } catch (e: any) {
      // The server's message is the SP's own wording, which already explains
      // what to send instead ("EST is a fixed-offset timezone... use
      // America/New_York"). Showing it beats replacing it with "Save failed".
      setError(e?.message ?? "Could not save the timezone.")
    } finally {
      setSaving(false)
    }
  }

  const changed = ctx != null && selected !== ctx.timeZoneId
  const needsConfirming = ctx != null && !ctx.timeZoneConfirmed

  return (
    <div className={className}>
      <Label htmlFor="company-timezone" className="flex items-center gap-1.5">
        <Globe className="w-3.5 h-3.5 text-slate-500" />
        Business timezone
      </Label>

      <Select value={selected} onValueChange={setSelected}>
        <SelectTrigger id="company-timezone">
          <SelectValue placeholder={ctx ? "Pick a timezone" : "Loading…"} />
        </SelectTrigger>
        <SelectContent>
          {/* ~550 region ids. The list is long on purpose: it is generated from
              the same catalogue the server validates against, so anything shown
              here is guaranteed to save. A short curated list would drift. */}
          {zones.map((z) => (
            <SelectItem key={z.timeZoneId} value={z.timeZoneId}>
              {z.timeZoneId} ({z.utcOffset})
            </SelectItem>
          ))}
        </SelectContent>
      </Select>

      {ctx && (
        <p className="mt-1 text-xs text-slate-500">
          Today here is <span className="font-medium text-slate-700">{ctx.businessDate}</span>. New
          records default to this date, and daily and period reports start and end by it.
        </p>
      )}

      {needsConfirming && !changed && (
        <p className="mt-1.5 flex items-start gap-1.5 text-xs text-amber-700">
          <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" />
          <span>
            This was guessed from your currency and has not been confirmed. If it is right, save it
            once to confirm.
          </span>
        </p>
      )}

      {changed && (
        <p className="mt-1.5 text-xs text-slate-500">
          Changing this does not alter any date already recorded — only what new entries default to
          and where report days start and end.
        </p>
      )}

      {error && <p className="mt-1.5 text-xs text-red-600">{error}</p>}

      {justSaved && !changed && (
        <p className="mt-1.5 flex items-center gap-1.5 text-xs text-emerald-700">
          <Check className="w-3.5 h-3.5" /> Timezone confirmed.
        </p>
      )}

      {ctx && (changed || needsConfirming) && (
        <Button
          type="button"
          size="sm"
          variant="outline"
          className="mt-2"
          disabled={saving}
          onClick={save}
        >
          {saving ? "Saving…" : changed ? "Save timezone" : "Confirm timezone"}
        </Button>
      )}
    </div>
  )
}
