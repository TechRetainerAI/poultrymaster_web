"use client"

// Access Management → Security. The governance half of IAM (phase 4).
//
// Three questions an admin has to be able to answer and previously could not:
//   Policy   — what the rules are for passwords and sessions
//   Review   — does everyone who has access still need it
//   History  — who changed whose access, and when
//
// The change history is written by database triggers rather than by the API, so
// it records changes made by any route, a support script, or a future feature —
// not only the ones this UI knows about.
import { useEffect, useMemo, useState } from "react"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import {
  Loader2, Save, ShieldCheck, History, ClipboardCheck, AlertTriangle, Check, Flag, Clock,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { useToast } from "@/hooks/use-toast"
import {
  getPolicy, savePolicy, getAccessReview, recordAccessReview, getAccessAudit,
  type IamPolicy, type IamAccessReviewRow, type IamAccessAuditEntry,
} from "@/lib/api/iam"
import { formatDate } from "./shared"

const AUDIT_WINDOWS = [
  { value: "30", label: "Last 30 days" },
  { value: "90", label: "Last 90 days" },
  { value: "365", label: "Last year" },
]

export function SecurityView({ farmId, canEdit }: { farmId: string | null; canEdit: boolean }) {
  const { toast } = useToast()

  const [policy, setPolicy] = useState<IamPolicy | null>(null)
  const [policyDraft, setPolicyDraft] = useState<IamPolicy | null>(null)
  const [savingPolicy, setSavingPolicy] = useState(false)

  const [review, setReview] = useState<IamAccessReviewRow[]>([])
  const [reviewBusy, setReviewBusy] = useState<string | null>(null)

  const [audit, setAudit] = useState<IamAccessAuditEntry[]>([])
  const [auditDays, setAuditDays] = useState("90")

  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    void (async () => {
      setLoading(true)
      const [p, r] = await Promise.all([getPolicy(farmId), getAccessReview(farmId)])
      if (cancelled) return
      setPolicy(p)
      setPolicyDraft(p ? { ...p } : null)
      setReview(r ?? [])
      setLoading(false)
    })()
    return () => { cancelled = true }
  }, [farmId])

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const a = await getAccessAudit(null, Number(auditDays))
      if (!cancelled) setAudit(a ?? [])
    })()
    return () => { cancelled = true }
  }, [auditDays])

  const policyDirty = useMemo(
    () => !!policy && !!policyDraft && JSON.stringify(policy) !== JSON.stringify(policyDraft),
    [policy, policyDraft]
  )

  async function doSavePolicy() {
    if (!policyDraft) return
    setSavingPolicy(true)
    try {
      const res = await savePolicy(policyDraft, farmId)
      if (!res.success) {
        toast({ title: "Could not save policy", description: res.message, variant: "destructive" })
        return
      }
      setPolicy({ ...policyDraft })
      toast({ title: "Security policy saved" })
    } finally { setSavingPolicy(false) }
  }

  async function doReview(row: IamAccessReviewRow, decision: "Confirmed" | "Flagged") {
    setReviewBusy(row.userId)
    try {
      const res = await recordAccessReview({ userId: row.userId, decision }, farmId)
      if (!res.success) {
        toast({ title: "Could not record review", description: res.message, variant: "destructive" })
        return
      }
      toast({
        title: decision === "Confirmed" ? "Access confirmed" : "Flagged for follow-up",
        description: displayName(row),
      })
      setReview(await getAccessReview(farmId) ?? [])
    } finally { setReviewBusy(null) }
  }

  function displayName(r: IamAccessReviewRow) {
    return [r.firstName, r.lastName].filter(Boolean).join(" ") || r.userName || r.email || "Unnamed"
  }

  const needsAttention = review.filter((r) => r.isDormant || r.reviewIsStale).length

  if (loading) {
    return <div className="flex items-center gap-2 text-slate-500 p-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
  }

  const num = (v: number) => (Number.isFinite(v) ? v : 0)

  return (
    <Tabs defaultValue="review">
      <TabsList>
        <TabsTrigger value="review">
          <ClipboardCheck className="h-4 w-4 mr-1.5" /> Access Review
          {needsAttention > 0 && (
            <Badge className="ml-1.5 bg-amber-100 text-amber-800 hover:bg-amber-100 text-[10px]">{needsAttention}</Badge>
          )}
        </TabsTrigger>
        <TabsTrigger value="policy"><ShieldCheck className="h-4 w-4 mr-1.5" /> Policy</TabsTrigger>
        <TabsTrigger value="history"><History className="h-4 w-4 mr-1.5" /> Change History</TabsTrigger>
      </TabsList>

      {/* ---------------- Access review ---------------- */}
      <TabsContent value="review" className="pt-4 space-y-3">
        <p className="text-sm text-slate-600">
          Confirm that everyone here still needs the access they have. A confirmation goes stale after{" "}
          {policy?.accessReviewDays ?? 180} days, and someone who has not signed in for{" "}
          {policy?.dormantAfterDays ?? 90} days is flagged as dormant.
        </p>

        <Card><CardContent className="p-0 overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
              <tr>
                <th className="text-left font-semibold px-4 py-3">Person</th>
                <th className="text-left font-semibold px-4 py-3">Access</th>
                <th className="text-left font-semibold px-4 py-3">Last seen</th>
                <th className="text-left font-semibold px-4 py-3">Last reviewed</th>
                <th className="text-right font-semibold px-4 py-3">Decision</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {review.length === 0 ? (
                <tr><td colSpan={5} className="px-4 py-8 text-center text-slate-500">Nobody to review.</td></tr>
              ) : review.map((r) => (
                <tr key={r.userId} className={cn("hover:bg-slate-50/60", (r.isDormant || r.reviewIsStale) && "bg-amber-50/40")}>
                  <td className="px-4 py-3">
                    <div className="font-medium text-slate-900">{displayName(r)}</div>
                    <div className="text-xs text-slate-500">{r.email || r.userName}</div>
                  </td>
                  <td className="px-4 py-3 text-xs text-slate-600">
                    {r.roleCount} role{r.roleCount === 1 ? "" : "s"}
                    {r.overrideCount > 0 && <> · {r.overrideCount} exception{r.overrideCount === 1 ? "" : "s"}</>}
                    {r.roleCount === 0 && r.overrideCount === 0 && (
                      <span className="text-slate-400"> — none</span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-xs">
                    {r.lastSeenAt ? formatDate(r.lastSeenAt) : <span className="text-slate-400">Never</span>}
                    {r.isDormant && (
                      <div className="text-amber-700 flex items-center gap-1 mt-0.5">
                        <Clock className="h-3 w-3" /> Dormant
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-xs">
                    {r.lastReviewedAt ? formatDate(r.lastReviewedAt) : <span className="text-slate-400">Never</span>}
                    {r.lastDecision === "Flagged" && (
                      <div className="text-red-700 flex items-center gap-1 mt-0.5">
                        <Flag className="h-3 w-3" /> Flagged
                      </div>
                    )}
                    {r.reviewIsStale && r.lastDecision !== "Flagged" && (
                      <div className="text-amber-700 flex items-center gap-1 mt-0.5">
                        <AlertTriangle className="h-3 w-3" /> Needs review
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center justify-end gap-1.5">
                      <Button
                        size="sm" variant="outline"
                        onClick={() => doReview(r, "Confirmed")}
                        disabled={!canEdit || reviewBusy === r.userId}
                      >
                        {reviewBusy === r.userId
                          ? <Loader2 className="h-3.5 w-3.5 animate-spin" />
                          : <><Check className="h-3.5 w-3.5 mr-1" /> Still needed</>}
                      </Button>
                      <Button
                        size="sm" variant="outline"
                        className="text-amber-700 border-amber-200 hover:bg-amber-50"
                        onClick={() => doReview(r, "Flagged")}
                        disabled={!canEdit || reviewBusy === r.userId}
                      >
                        <Flag className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </CardContent></Card>
      </TabsContent>

      {/* ---------------- Policy ---------------- */}
      <TabsContent value="policy" className="pt-4 space-y-4">
        <div className="rounded-lg border border-sky-200 bg-sky-50 px-4 py-3 text-sm text-sky-900">
          These rules are recorded here, but passwords are checked when someone registers or changes
          their password — which happens in the sign-in service. Until that is wired up, treat the password
          settings as the policy you intend rather than one already being applied.
        </div>

        {!policyDraft ? (
          <Card><CardContent className="p-8 text-center text-sm text-slate-500">
            Security policy is unavailable. Apply <code className="text-xs bg-slate-100 px-1 py-0.5 rounded">203_IamPhase4Governance.sql</code>.
          </CardContent></Card>
        ) : (
          <>
            <Card><CardContent className="p-4 space-y-4">
              <div className="font-semibold text-slate-900">Passwords</div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label htmlFor="pw-min">Minimum length</Label>
                  <Input
                    id="pw-min" type="number" min={6} max={128}
                    value={policyDraft.passwordMinLength}
                    onChange={(e) => setPolicyDraft({ ...policyDraft, passwordMinLength: num(Number(e.target.value)) })}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="pw-exp">Expires after (days)</Label>
                  <Input
                    id="pw-exp" type="number" min={0}
                    value={policyDraft.passwordExpiryDays}
                    onChange={(e) => setPolicyDraft({ ...policyDraft, passwordExpiryDays: num(Number(e.target.value)) })}
                  />
                  <p className="text-xs text-slate-500">0 means never.</p>
                </div>
              </div>
              <div className="space-y-2">
                {([
                  ["passwordRequireUpper", "Require a capital letter"],
                  ["passwordRequireDigit", "Require a number"],
                  ["passwordRequireSymbol", "Require a symbol"],
                ] as const).map(([key, label]) => (
                  <div key={key} className="flex items-center justify-between gap-3">
                    <span className="text-sm text-slate-800">{label}</span>
                    <Switch
                      checked={policyDraft[key]}
                      onCheckedChange={(c) => setPolicyDraft({ ...policyDraft, [key]: c })}
                      aria-label={label}
                    />
                  </div>
                ))}
              </div>
            </CardContent></Card>

            <Card><CardContent className="p-4 space-y-4">
              <div className="font-semibold text-slate-900">Sessions and review</div>
              <div className="grid gap-4 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <Label htmlFor="s-idle">Sign out after inactivity (minutes)</Label>
                  <Input
                    id="s-idle" type="number" min={0}
                    value={policyDraft.sessionIdleMinutes}
                    onChange={(e) => setPolicyDraft({ ...policyDraft, sessionIdleMinutes: num(Number(e.target.value)) })}
                  />
                  <p className="text-xs text-slate-500">0 means no idle timeout.</p>
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="s-max">Maximum session length (hours)</Label>
                  <Input
                    id="s-max" type="number" min={0}
                    value={policyDraft.sessionMaxHours}
                    onChange={(e) => setPolicyDraft({ ...policyDraft, sessionMaxHours: num(Number(e.target.value)) })}
                  />
                  <p className="text-xs text-slate-500">0 means no cap.</p>
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="s-dormant">Treat as dormant after (days)</Label>
                  <Input
                    id="s-dormant" type="number" min={0}
                    value={policyDraft.dormantAfterDays}
                    onChange={(e) => setPolicyDraft({ ...policyDraft, dormantAfterDays: num(Number(e.target.value)) })}
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="s-review">Access review stays fresh for (days)</Label>
                  <Input
                    id="s-review" type="number" min={0}
                    value={policyDraft.accessReviewDays}
                    onChange={(e) => setPolicyDraft({ ...policyDraft, accessReviewDays: num(Number(e.target.value)) })}
                  />
                </div>
              </div>
              <div className="flex items-center justify-between gap-3">
                <div>
                  <span className="text-sm text-slate-800">Require two-factor sign-in for admins</span>
                  <p className="text-xs text-slate-500">Recorded as intent; two-factor is not built yet.</p>
                </div>
                <Switch
                  checked={policyDraft.requireMfaForAdmins}
                  onCheckedChange={(c) => setPolicyDraft({ ...policyDraft, requireMfaForAdmins: c })}
                  aria-label="Require two-factor sign-in for admins"
                />
              </div>
            </CardContent></Card>

            {policyDirty && (
              <div className="flex justify-end gap-2">
                <Button variant="outline" onClick={() => setPolicyDraft(policy ? { ...policy } : null)} disabled={savingPolicy}>
                  Reset
                </Button>
                <Button onClick={doSavePolicy} disabled={!canEdit || savingPolicy}>
                  {savingPolicy
                    ? <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Saving…</>
                    : <><Save className="h-4 w-4 mr-2" /> Save policy</>}
                </Button>
              </div>
            )}
          </>
        )}
      </TabsContent>

      {/* ---------------- Change history ---------------- */}
      <TabsContent value="history" className="pt-4 space-y-3">
        <div className="flex items-center justify-between gap-3">
          <p className="text-sm text-slate-600">
            Every change to who can do what, recorded by the database itself.
          </p>
          <Select value={auditDays} onValueChange={setAuditDays}>
            <SelectTrigger className="w-[160px] h-9"><SelectValue /></SelectTrigger>
            <SelectContent>
              {AUDIT_WINDOWS.map((w) => <SelectItem key={w.value} value={w.value}>{w.label}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>

        <Card><CardContent className="p-0 divide-y divide-slate-100 max-h-[32rem] overflow-y-auto">
          {audit.length === 0 ? (
            <p className="p-8 text-sm text-center text-slate-500">
              No access changes recorded in this period.
            </p>
          ) : audit.map((a) => (
            <div key={a.id} className="px-4 py-3 flex items-start gap-3">
              <Badge
                variant="secondary"
                className={cn(
                  "text-[10px] shrink-0 mt-0.5",
                  a.operation === "Delete" && "bg-red-100 text-red-700 hover:bg-red-100",
                  a.operation === "Insert" && "bg-emerald-100 text-emerald-700 hover:bg-emerald-100"
                )}
              >
                {a.operation}
              </Badge>
              <div className="min-w-0 flex-1">
                <div className="text-sm text-slate-800">{a.detail}</div>
                <div className="text-xs text-slate-500">
                  {a.subjectName?.trim() || a.subjectId || "unknown"}
                  {(a.actorName?.trim() || a.actorId) && <> · by {a.actorName?.trim() || a.actorId}</>}
                  {" · "}{new Date(a.occurredAt).toLocaleString()}
                </div>
              </div>
            </div>
          ))}
        </CardContent></Card>
      </TabsContent>
    </Tabs>
  )
}
