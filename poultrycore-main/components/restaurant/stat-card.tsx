import { Card, CardContent } from "@/components/ui/card"
import { type LucideIcon } from "lucide-react"

interface StatCardProps {
  label: string
  value: string | number
  icon: LucideIcon
  color?: "rose" | "green" | "blue" | "amber" | "purple" | "red" | "indigo"
}

const borderColors: Record<string, string> = {
  rose: "border-l-rose-500",
  green: "border-l-green-500",
  blue: "border-l-blue-500",
  amber: "border-l-amber-500",
  purple: "border-l-purple-500",
  red: "border-l-red-500",
  indigo: "border-l-indigo-500",
}

const bgColors: Record<string, string> = {
  rose: "bg-rose-50 text-rose-600",
  green: "bg-green-50 text-green-600",
  blue: "bg-blue-50 text-blue-600",
  amber: "bg-amber-50 text-amber-600",
  purple: "bg-purple-50 text-purple-600",
  red: "bg-red-50 text-red-600",
  indigo: "bg-indigo-50 text-indigo-600",
}

export function StatCard({ label, value, icon: Icon, color = "rose" }: StatCardProps) {
  return (
    <Card className={`border-l-4 ${borderColors[color]}`}>
      <CardContent className="py-3 px-4 flex items-center gap-3">
        <div className={`rounded-lg p-2 ${bgColors[color]}`}>
          <Icon className="h-5 w-5" />
        </div>
        <div>
          <p className="text-2xl font-bold">{value}</p>
          <p className="text-xs text-muted-foreground">{label}</p>
        </div>
      </CardContent>
    </Card>
  )
}
