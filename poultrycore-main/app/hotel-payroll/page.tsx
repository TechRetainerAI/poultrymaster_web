"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Loader2, Banknote } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { listHotelStaff, type HotelStaff } from "@/lib/api/hotel"

export default function HotelPayrollPage() {
  const router = useRouter(); const { toast } = useToast(); const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const [staff, setStaff] = useState<HotelStaff[]>([]); const [loading, setLoading] = useState(true)

  useEffect(() => { if (!activeFarmType) return; if (activeFarmType !== "Hotel") { router.replace("/dashboard"); return }; load() }, [activeFarmType, router])
  async function load() { setLoading(true); try { setStaff(await listHotelStaff()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } finally { setLoading(false) } }

  const totalSalary = staff.reduce((s, x) => s + (x.salaryAmount ?? 0), 0)

  return (
    <div className="flex h-screen bg-slate-50"><DashboardSidebar onLogout={logout} /><div className="flex-1 flex flex-col min-w-0 overflow-hidden"><DashboardHeader />
      <main className="flex-1 overflow-auto p-4 md:p-6">
        <div className="flex items-center gap-3 mb-6"><Banknote className="h-6 w-6 text-violet-600" /><h1 className="text-2xl font-bold">Payroll</h1><span className="text-sm text-slate-500">{staff.length} staff — Monthly: {totalSalary.toFixed(2)}</span></div>
        {loading ? <div className="flex justify-center py-20"><Loader2 className="h-8 w-8 animate-spin text-violet-600" /></div> : (
          <Card><CardContent className="p-0"><table className="w-full text-sm"><thead className="bg-slate-50 border-b"><tr><th className="text-left p-3">Name</th><th className="text-left p-3">Role</th><th className="text-left p-3">Department</th><th className="text-left p-3">Hire Date</th><th className="text-right p-3">Monthly Salary</th></tr></thead>
            <tbody>{staff.map((s: any, idx: number) => (<tr key={s.hotelStaffId ?? s.hotelstaffid ?? `pr-${idx}`} className="border-b hover:bg-slate-50"><td className="p-3 font-medium">{s.firstName} {s.lastName}</td><td className="p-3">{s.role}</td><td className="p-3"><Badge variant="outline">{s.department}</Badge></td><td className="p-3">{s.hireDate?.slice(0,10)}</td><td className="p-3 text-right font-semibold">{(s.salaryAmount ?? 0).toFixed(2)}</td></tr>))}
              {staff.length === 0 && <tr><td colSpan={5} className="p-8 text-center text-slate-400">No staff. Add staff from the Staff page first.</td></tr>}
              {staff.length > 0 && <tr className="bg-violet-50 font-bold"><td colSpan={4} className="p-3 text-right">Total Monthly Payroll</td><td className="p-3 text-right text-violet-700">{totalSalary.toFixed(2)}</td></tr>}
            </tbody></table></CardContent></Card>
        )}
      </main></div></div>
  )
}
