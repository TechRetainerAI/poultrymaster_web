// Badges for a person who is both an Employee (login) and a Staff member
// (payroll record) -- migration 362. Staff pages show EmployeeBadge, the
// Employees page shows StaffBadge.

import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"

export function EmployeeBadge({ className }: { className?: string }) {
  return (
    <Badge variant="outline" className={cn("border-blue-200 bg-blue-50 text-blue-700", className)} title="Also an employee: has a login">
      Employee
    </Badge>
  )
}

export function StaffBadge({ className }: { className?: string }) {
  return (
    <Badge variant="outline" className={cn("border-indigo-200 bg-indigo-50 text-indigo-700", className)} title="Also on the Staff page (payroll)">
      Staff
    </Badge>
  )
}
