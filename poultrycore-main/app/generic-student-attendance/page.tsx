"use client"

// Student attendance — mark students present/absent for a given date and class.

import { useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Badge } from "@/components/ui/badge"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, ClipboardCheck, Check } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import {
  getCustomers, getClasses, getCustomerAttendance, upsertCustomerAttendance,
  type GenericCustomer, type GenericClass, type GenericCustomerAttendance,
} from "@/lib/api/generic"

const STATUSES = ["Present", "Absent", "Late", "HalfDay", "Excused"] as const
const STATUS_COLORS: Record<string, string> = {
  Present: "bg-emerald-100 text-emerald-700",
  Absent: "bg-rose-100 text-rose-700",
  Late: "bg-amber-100 text-amber-700",
  HalfDay: "bg-blue-100 text-blue-700",
  Excused: "bg-slate-100 text-slate-600",
}

export default function GenericStudentAttendancePage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [students, setStudents] = useState<GenericCustomer[]>([])
  const [classes, setClasses] = useState<GenericClass[]>([])
  const [records, setRecords] = useState<GenericCustomerAttendance[]>([])
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10))
  const [classFilter, setClassFilter] = useState<string>("all")
  const [marks, setMarks] = useState<Record<number, string>>({})

  const load = async () => {
    setLoading(true)
    try {
      const [ss, cs, recs] = await Promise.all([
        getCustomers(), getClasses(), getCustomerAttendance(date),
      ])
      setStudents(ss.filter((s) => s.isActive))
      setClasses(cs.filter((c) => c.isActive))
      setRecords(recs)
      // Pre-fill marks from existing records
      const m: Record<number, string> = {}
      for (const r of recs) m[r.genericCustomerId] = r.status
      setMarks(m)
    } catch (e: any) {
      toast({ title: "Could not load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router, date])

  // Filter students by class
  const filtered = useMemo(() => {
    if (classFilter === "all") return students
    return students.filter((s) => s.classOrGrade === classFilter)
  }, [students, classFilter])

  const setMark = (customerId: number, status: string) => {
    setMarks((prev) => ({ ...prev, [customerId]: status }))
  }

  const markAll = (status: string) => {
    const m: Record<number, string> = { ...marks }
    for (const s of filtered) m[s.genericCustomerId] = status
    setMarks(m)
  }

  const saveAll = async () => {
    setSaving(true)
    try {
      const classId = classFilter !== "all"
        ? classes.find((c) => c.className === classFilter)?.genericClassId
        : undefined
      const promises = filtered
        .filter((s) => marks[s.genericCustomerId])
        .map((s) =>
          upsertCustomerAttendance({
            genericCustomerId: s.genericCustomerId,
            attendanceDate: date,
            status: marks[s.genericCustomerId],
            genericClassId: classId ?? null,
          })
        )
      await Promise.all(promises)
      toast({ title: `Attendance saved for ${promises.length} students` })
    } catch (e: any) {
      toast({ title: "Could not save attendance", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  // Stats
  const stats = useMemo(() => {
    const total = filtered.length
    const marked = filtered.filter((s) => marks[s.genericCustomerId]).length
    const present = filtered.filter((s) => marks[s.genericCustomerId] === "Present").length
    const absent = filtered.filter((s) => marks[s.genericCustomerId] === "Absent").length
    return { total, marked, present, absent }
  }, [filtered, marks])

  // Class names from the classes table (sorted by level), with fallback to student data
  const classNames = useMemo(() => {
    if (classes.length > 0) {
      return classes.map((c) => c.className)
    }
    const set = new Set(students.map((s) => s.classOrGrade).filter(Boolean) as string[])
    return Array.from(set).sort()
  }, [classes, students])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="max-w-4xl mx-auto space-y-4">
            <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
              <ClipboardCheck className="h-5 w-5" /> Student Attendance
            </h1>

            {/* Controls */}
            <div className="flex flex-wrap gap-3 items-end">
              <div>
                <label className="text-xs text-slate-500 block mb-1">Date</label>
                <Input type="date" value={date} onChange={(e) => setDate(e.target.value)} className="w-44" />
              </div>
              <div>
                <label className="text-xs text-slate-500 block mb-1">Class</label>
                <Select value={classFilter} onValueChange={setClassFilter}>
                  <SelectTrigger className="w-44"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="all">All classes</SelectItem>
                    {classNames.map((cn) => (
                      <SelectItem key={cn} value={cn}>{cn}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="flex gap-1.5">
                <Button variant="outline" size="sm" onClick={() => markAll("Present")}>All Present</Button>
                <Button variant="outline" size="sm" onClick={() => markAll("Absent")}>All Absent</Button>
              </div>
            </div>

            {/* Stats */}
            <div className="flex gap-3 text-sm">
              <Badge variant="secondary">{stats.total} students</Badge>
              <Badge variant="secondary">{stats.marked} marked</Badge>
              <Badge className="bg-emerald-100 text-emerald-700">{stats.present} present</Badge>
              <Badge className="bg-rose-100 text-rose-700">{stats.absent} absent</Badge>
            </div>

            {/* Student list */}
            <Card>
              <CardContent className="p-0">
                {loading ? (
                  <div className="flex items-center justify-center py-12"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
                ) : filtered.length === 0 ? (
                  <p className="text-center text-sm text-slate-500 py-12">
                    {students.length === 0 ? "No students found. Add students first." : "No students in this class."}
                  </p>
                ) : (
                  <div className="divide-y">
                    {filtered.map((s) => {
                      const current = marks[s.genericCustomerId] || ""
                      return (
                        <div key={s.genericCustomerId} className="flex items-center justify-between gap-3 px-4 py-2.5">
                          <div className="min-w-0">
                            <p className="text-sm font-medium text-slate-900 truncate">{s.customerName}</p>
                            <p className="text-xs text-slate-500">
                              {s.admissionNumber && <span>{s.admissionNumber} · </span>}
                              {s.classOrGrade ?? "No class"}
                            </p>
                          </div>
                          <div className="flex gap-1">
                            {STATUSES.map((st) => (
                              <button
                                key={st}
                                type="button"
                                onClick={() => setMark(s.genericCustomerId, st)}
                                className={`rounded-md px-2.5 py-1 text-xs font-medium transition ${
                                  current === st
                                    ? STATUS_COLORS[st]
                                    : "bg-slate-50 text-slate-400 hover:bg-slate-100"
                                }`}
                              >
                                {st === "HalfDay" ? "Half" : st}
                              </button>
                            ))}
                          </div>
                        </div>
                      )
                    })}
                  </div>
                )}
              </CardContent>
            </Card>

            {/* Save */}
            {filtered.length > 0 && (
              <div className="flex justify-end">
                <Button onClick={saveAll} disabled={saving || stats.marked === 0} size="lg">
                  {saving ? (
                    <><Loader2 className="h-4 w-4 mr-2 animate-spin" /> Saving…</>
                  ) : (
                    <><Check className="h-4 w-4 mr-2" /> Save attendance ({stats.marked})</>
                  )}
                </Button>
              </div>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}
