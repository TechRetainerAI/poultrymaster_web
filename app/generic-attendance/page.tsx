"use client"

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, CalendarDays } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getAttendance, getStaff, upsertAttendance,
  type GenericAttendanceStatus, type GenericStaff, type GenericStaffAttendance,
} from "@/lib/api/generic"

const STATUSES: GenericAttendanceStatus[] = ["Present", "Absent", "Late", "HalfDay", "OffDay"]

function todayIso(): string {
  const d = new Date()
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
  return d.toISOString().slice(0, 10)
}

function statusBadgeClass(s: string) {
  switch (s) {
    case "Present": return "bg-emerald-100 text-emerald-800 hover:bg-emerald-100"
    case "Late":    return "bg-amber-100 text-amber-800 hover:bg-amber-100"
    case "HalfDay": return "bg-sky-100 text-sky-800 hover:bg-sky-100"
    case "Absent":  return "bg-rose-100 text-rose-800 hover:bg-rose-100"
    case "OffDay":  return "bg-slate-100 text-slate-700 hover:bg-slate-100"
    default:        return "bg-slate-100 text-slate-700 hover:bg-slate-100"
  }
}

export default function GenericAttendancePage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [date, setDate] = useState<string>(todayIso())
  const [staff, setStaff] = useState<GenericStaff[]>([])
  const [att, setAtt]     = useState<GenericStaffAttendance[]>([])
  const [loading, setLoading] = useState(true)
  const [savingId, setSavingId] = useState<number | null>(null)

  const loadAll = async (forDate: string) => {
    setLoading(true)
    try {
      const [s, a] = await Promise.all([
        getStaff(),
        getAttendance({ fromDate: forDate, toDate: forDate }),
      ])
      setStaff(s.filter((x) => x.isActive))
      setAtt(a)
    } catch (e: any) {
      toast({ title: "Could not load attendance", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    loadAll(date)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [date, activeFarmType, router])

  // Index attendance by staffId for current date (one shift only for the simple UI).
  const byStaff = useMemo(() => {
    const m = new Map<number, GenericStaffAttendance>()
    for (const a of att) {
      // attendanceDate from server is ISO datetime (DATE column stringified); compare just the date portion.
      const d = a.attendanceDate.slice(0, 10)
      if (d === date && !m.has(a.genericStaffId)) m.set(a.genericStaffId, a)
    }
    return m
  }, [att, date])

  const setStatus = async (staffId: number, status: GenericAttendanceStatus) => {
    setSavingId(staffId)
    try {
      await upsertAttendance({ genericStaffId: staffId, attendanceDate: date, status })
      const fresh = await getAttendance({ fromDate: date, toDate: date })
      setAtt(fresh)
    } catch (e: any) {
      toast({ title: "Could not save attendance", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setSavingId(null) }
  }

  const summary = useMemo(() => {
    const out = { Present: 0, Absent: 0, Late: 0, HalfDay: 0, OffDay: 0, NotRecorded: 0 }
    for (const s of staff) {
      const a = byStaff.get(s.genericStaffId)
      if (!a) out.NotRecorded++
      else out[a.status as keyof typeof out] = (out[a.status as keyof typeof out] ?? 0) + 1
    }
    return out
  }, [staff, byStaff])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-4 flex items-center justify-between flex-wrap gap-2">
            <div>
              <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
                <CalendarDays className="h-6 w-6 text-emerald-600" /> Attendance
              </h1>
              <p className="text-sm text-slate-500">
                Present {summary.Present} · Late {summary.Late} · Half {summary.HalfDay} · Absent {summary.Absent} · Off {summary.OffDay} · Not recorded {summary.NotRecorded}
              </p>
            </div>

            <div className="flex items-end gap-2">
              <div>
                <Label htmlFor="attDate">Date</Label>
                <Input id="attDate" type="date" value={date} onChange={(e) => setDate(e.target.value)} className="w-44" />
              </div>
              <Button variant="outline" onClick={() => setDate(todayIso())}>Today</Button>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : staff.length === 0 ? (
            <Card><CardContent className="py-8 text-center text-slate-500">No active staff yet. Add staff first.</CardContent></Card>
          ) : (
            <Card>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Staff</TableHead>
                      <TableHead>Role</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead>Set status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {staff.map((s) => {
                      const a = byStaff.get(s.genericStaffId)
                      return (
                        <TableRow key={s.genericStaffId}>
                          <TableCell className="font-medium">{s.firstName} {s.lastName}</TableCell>
                          <TableCell><Badge variant="outline">{s.role}</Badge></TableCell>
                          <TableCell>
                            {a
                              ? <Badge className={statusBadgeClass(a.status)}>{a.status}</Badge>
                              : <span className="text-slate-400 text-sm">Not recorded</span>}
                          </TableCell>
                          <TableCell>
                            <div className="flex items-center gap-2">
                              <Select
                                value={a?.status ?? ""}
                                onValueChange={(v) => setStatus(s.genericStaffId, v as GenericAttendanceStatus)}
                                disabled={savingId === s.genericStaffId}
                              >
                                <SelectTrigger className="w-36">
                                  <SelectValue placeholder="Set…" />
                                </SelectTrigger>
                                <SelectContent>
                                  {STATUSES.map((st) => <SelectItem key={st} value={st}>{st}</SelectItem>)}
                                </SelectContent>
                              </Select>
                              {savingId === s.genericStaffId && <Loader2 className="h-4 w-4 animate-spin text-slate-400" />}
                            </div>
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          )}
        </main>
      </div>
    </div>
  )
}
